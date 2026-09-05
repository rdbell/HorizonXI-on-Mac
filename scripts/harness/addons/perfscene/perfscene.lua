--[[
perfscene: run a fixed, reproducible in-world scenario on the local test server.

Loaded by menu-run.py through Ashita's boot script. It waits for the character to be in the
world, then walks a list of steps at a fixed cadence: GM commands to keep the character alive
and load the scene (weather, mobs, teleports), plus fps settings. Every step and every zone
change is appended to a markers file in the capture directory so the recorder can slice the
frame log by scenario phase without anyone watching the screen.

Environment (set by the launcher for one run, read through os.getenv):
  PERFSCENE_MARKERS   file to append JSON-lines markers to (required, otherwise idle)
  PERFSCENE_SCENARIO  scenario name from the table below (default: city)
  PERFSCENE_START     seconds after zone-in before the first step (default 8)

Commands:
  /perfscene run <name>    start a scenario by hand
  /perfscene stop          stop the running scenario
  /perfscene list          list scenarios
--]]

addon.name    = 'perfscene';
addon.author  = 'HorizonXI-on-Mac';
addon.version = '1.0';
addon.desc    = 'Reproducible in-world performance scenarios for the local test server.';
addon.link    = 'https://github.com/danielalanbates/HorizonXI-on-Mac';

require('common');
local chat = require('chat');
local ffi = require('ffi');
ffi.cdef[[
    int __stdcall QueryPerformanceCounter(int64_t *);
    int __stdcall QueryPerformanceFrequency(int64_t *);
    void __stdcall GetSystemTimeAsFileTime(uint64_t *);
]];
local qpc = ffi.new('int64_t[1]');
local frequency = ffi.new('int64_t[1]');
local filetime = ffi.new('uint64_t[1]');
ffi.C.QueryPerformanceFrequency(frequency);
local frequency_hz = tonumber(frequency[0]);
local function clock_s()
    ffi.C.QueryPerformanceCounter(qpc);
    return tonumber(qpc[0]) / frequency_hz;
end
ffi.C.GetSystemTimeAsFileTime(filetime);
local started = clock_s();
local epoch_started = tonumber(filetime[0]) / 10000000 - 11644473600;
local function epoch_s(now) return epoch_started + now - started; end
local requested_distance = tonumber(os.getenv('PERFSCENE_DRAW_DISTANCE') or '20');
local world_distance_command = '/drawdistance setworld ' .. tostring(requested_distance);
local entity_distance_command = '/drawdistance setmob ' .. tostring(requested_distance);

-- Each step is { delay_seconds, command, label }. Commands starting with '!' are LandSandBoat
-- GM commands sent as chat; '/' commands go to Ashita. setPos supplies position and byte
-- rotation through the server. 'home' asks the desktop driver to reset the camera after the
-- heading arrives. Zone ids: North Gustaberg 106, Bastok Markets 235, Bastok Mines 234.
-- Weather ids follow xi.weather (6 rain, 12 snow, 15 thunderstorms). Positions are fixed
-- zone-line arrival points from LandSandBoat's zone.yaml.
local scenarios = {
    -- The settled-city baseline: two fixed vantages in Bastok at uncapped FPS.
    city = {
        { 1,  '!addtime 0',                      'clock offset reset' },
        { 1,  '!perftime 12',                    'clock pinned to noon' },
        { 2,  '/fps 0',                          'fps uncapped' },
        { 2,  world_distance_command,            'world draw distance set' },
        { 2,  entity_distance_command,           'entity draw distance set' },
        { 3,  '!exec player:setPos(-201.904,1.928,-194.828,192,235)', 'zone bastok markets' },
        { 6,  'home',                            'camera reset requested' },
        { 20, 'settle',                          'city settled' },
        { 20, '!exec player:setPos(-104.018,9.359,81.411,64,234)', 'zone bastok mines' },
        { 6,  'home',                            'camera reset requested' },
        { 20, 'settle',                          'mines settled' },
        { 20, 'done',                            'done' },
    },
    -- Outdoors at a fixed vantage, then weather, then a crowd of mobs around the player.
    field = {
        { 1,  '!addtime 0',                      'clock offset reset' },
        { 1,  '!perftime 12',                    'clock pinned to noon' },
        { 2,  '/fps 0',                          'fps uncapped' },
        { 2,  world_distance_command,            'world draw distance set' },
        { 2,  entity_distance_command,           'entity draw distance set' },
        { 3,  '!exec player:setPos(0.840,-5.027,76.838,64,106)', 'zone north gustaberg' },
        { 6,  'home',                            'camera reset requested' },
        { 20, 'settle',                          'field settled' },
        { 20, '!setweather 15',                  'thunderstorms' },
        { 15, 'settle',                          'weather settled' },
        { 20, 'spawn 40',                        'spawn 40 mobs' },
        { 30, 'settle',                          'crowd settled' },
        { 20, '!exec player:setPos(-201.904,1.928,-194.828,192,235)', 'zone bastok markets' },
        { 6,  'home',                            'camera reset requested' },
        { 20, 'settle',                          'city after crowd' },
        { 20, 'done',                            'done' },
    },
};

-- Longer samples for profiler windows and repeated performance comparisons. The second
-- town vantage looks toward the Mines auction counters from the open plaza.
scenarios.city_long = {};
scenarios.town = {};
for _, s in ipairs(scenarios.city) do
    local delay = (s[3] == 'zone bastok mines' or s[3] == 'done') and 60 or s[1];
    scenarios.city_long[#scenarios.city_long + 1] = { delay, s[2], s[3] };
    local command = s[3] == 'zone bastok mines'
        and '!exec player:setPos(39,0,-49,128,234)' or s[2];
    local label = s[3] == 'mines settled' and 'mines plaza settled' or s[3];
    scenarios.town[#scenarios.town + 1] = { delay, command, label };
end

local state = {
    running   = nil,     -- scenario table
    index     = 0,
    next_at   = 0,
    markers   = os.getenv('PERFSCENE_MARKERS'),
    auto      = os.getenv('PERFSCENE_SCENARIO'),
    start     = tonumber(os.getenv('PERFSCENE_START') or '8'),
    in_world  = false,
    world_at  = 0,
    zone      = -1,
    file      = nil,
};

local draw_distance_code = nil;
local function mark(label, extra)
    local mem = AshitaCore:GetMemoryManager();
    local zone = mem:GetParty():GetMemberZone(0);
    local index = mem:GetParty():GetMemberTargetIndex(0);
    local position = '';
    if zone > 0 and index and index > 0 then
        local entity = mem:GetEntity();
        position = string.format(', "x": %.3f, "y": %.3f, "z": %.3f, "yaw": %.4f',
            entity:GetLocalPositionX(index), entity:GetLocalPositionY(index),
            entity:GetLocalPositionZ(index), entity:GetLocalPositionYaw(index));
        -- Reuse the loaded drawdistance addon's signature and read both effective values.
        if not draw_distance_code then
            draw_distance_code = ashita.memory.find(0, 0, '8BC1487408D80D', 0, 0);
        end
        if draw_distance_code and draw_distance_code ~= 0 then
            local world = ashita.memory.read_uint32(draw_distance_code + 0x07);
            local entities = ashita.memory.read_uint32(draw_distance_code + 0x0F);
            if world ~= 0 and entities ~= 0 then
                position = position .. string.format(', "world_distance": %.4f, "entity_distance": %.4f',
                    ashita.memory.read_float(world), ashita.memory.read_float(entities));
            end
        end
    end
    local line = string.format('{"epoch": %.3f, "label": "%s", "zone": %d%s%s}',
        epoch_s(clock_s()), (label:gsub('"', "'")), zone, position, extra or '');
    if (state.markers ~= nil) then
        local f = io.open(state.markers, 'a');
        if (f ~= nil) then f:write(line, '\n'); f:close(); end
    end
    print(chat.header(addon.name):append(chat.message(label)));
end

local function send(cmd)
    -- Mode 1: as if typed in the chat box. GM commands are plain text that begins with '!'.
    AshitaCore:GetChatManager():QueueCommand(1, cmd);
end

-- Spawn N copies of the nearest spawnable mob ids of this zone at the player's position.
-- LandSandBoat assigns mob ids per zone as 0x1000000 | zone << 12 | slot; !mobhere moves a
-- spawn to the player. Slots that hold no mob are rejected by the server and skipped.
-- The crowd is one server-side command, !perfcrowd, mounted into the local test server by
-- scripts/lsb-docker/docker-compose.yml. Forty separate !mobhere lines tripped the client's
-- outgoing chat rate limit, and an !exec one-liner exceeds the chat length limit.
local function spawn_crowd(n)
    send(string.format('!perfcrowd %d', n));
end

local function step()
    local sc = state.running;
    if (sc == nil) then return; end
    state.index = state.index + 1;
    local s = sc[state.index];
    if (s == nil) then
        state.running = nil;
        mark('scenario finished');
        return;
    end
    local cmd, label = s[2], s[3];
    if (cmd == 'settle') then
        mark(label);
    elseif (cmd == 'done') then
        mark(label);
        state.running = nil;
        return;
    elseif (cmd:sub(1, 6) == 'spawn ') then
        spawn_crowd(tonumber(cmd:sub(7)) or 20);
        mark(label);
    elseif (cmd == 'home') then
        -- The desktop driver sends Home after the server-supplied heading arrives.
        mark(label);
    else
        send(cmd);
        mark(label, string.format(', "command": "%s"', (cmd:gsub('"', "'"))));
    end
    -- Each step's delay is the pause *before* it runs, so schedule the next one now.
    local nxt = sc[state.index + 1];
    if (nxt ~= nil) then state.next_at = clock_s() + nxt[1]; end
end

local function start(name)
    local sc = scenarios[name];
    if (sc == nil) then
        print(chat.header(addon.name):append(chat.error('unknown scenario: ' .. tostring(name))));
        return;
    end
    state.running = sc; state.index = 0;
    state.next_at = clock_s() + sc[1][1];
    mark('scenario start: ' .. name);
end

ashita.events.register('load', 'perfscene_load', function ()
    if (state.markers ~= nil) then
        mark('addon loaded', string.format(', "jit_enabled": %s', tostring(jit and jit.status() or false)));
    end
end);

ashita.events.register('command', 'perfscene_command', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1] ~= '/perfscene') then return; end
    e.blocked = true;
    if (#args >= 3 and args[2] == 'run') then start(args[3]);
    elseif (#args >= 2 and args[2] == 'stop') then state.running = nil; mark('scenario stopped');
    elseif (#args >= 2 and args[2] == 'list') then
        for k, _ in pairs(scenarios) do print(chat.header(addon.name):append(chat.message(k))); end
    end
end);

-- Zone-in detection: the first time the party zone is a real zone and the player is not
-- zoning, the character is in the world. Every later change of zone is a marker too.
ashita.events.register('d3d_present', 'perfscene_present', function ()
    local mem = AshitaCore:GetMemoryManager();
    local zone = mem:GetParty():GetMemberZone(0);
    local zoning = mem:GetPlayer():GetIsZoning() ~= 0;
    if (zone ~= state.zone and zone > 0 and not zoning) then
        local first = not state.in_world;
        state.zone = zone;
        state.in_world = true;
        mark(first and 'in world' or 'zoned', string.format(', "zone_id": %d', zone));
        if (first) then
            state.world_at = clock_s();
        end
    end
    if (state.in_world and state.auto ~= nil and state.running == nil and not state.auto_done) then
        if (clock_s() - state.world_at >= state.start) then
            state.auto_done = true;
            start(state.auto);
        end
    end
    if (state.running ~= nil and clock_s() >= state.next_at) then
        step();
    end
end);

-- Renderer-independent benchmark counter. QueryPerformanceCounter is monotonic wall time.
local out_path=os.getenv('PERFSCENE_FPS');
local out=out_path and io.open(out_path,'w') or nil;
local last=started; local previous=started; local count=0; local frame_ms={};
if out then out:write('elapsed,epoch,fps,frames,seconds,zone,p50_ms,p95_ms,p99_ms,max_ms,jit_enabled\n'); out:flush(); end
ashita.events.register('d3d_present','benchmark_fps',function()
  if not out then return end
  count=count+1; local now=clock_s(); local dt=now-last;
  frame_ms[count]=(now-previous)*1000; previous=now;
  if dt>=1 then
    local zone=AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    table.sort(frame_ms);
    out:write(string.format('%.6f,%.6f,%.6f,%d,%.6f,%d,%.6f,%.6f,%.6f,%.6f,%d\n',
      now-started,epoch_s(now),count/dt,count,dt,zone,
      frame_ms[math.ceil(count*0.50)],frame_ms[math.ceil(count*0.95)],
      frame_ms[math.ceil(count*0.99)],frame_ms[count],jit and jit.status() and 1 or 0));
    out:flush();
    frame_ms={};
    count=0;last=now;
  end
end);
ashita.events.register('unload','benchmark_fps_cleanup',function() if out then out:close();out=nil;end end);

-- Menu-only experiment: the exact pointer walk used by Ashita's existing fps addon.
-- The game process owns this value; nothing is patched on disk. Reapply only if a
-- menu transition restores a nonzero divisor. Never change it after entering a zone.
local menu_uncap=os.getenv('PERFSCENE_MENU_UNCAP')=='1';
local divisor_slot=nil; local next_divisor_check=started+2;
local divisor_out=menu_uncap and out_path and io.open(out_path:gsub('common%-fps.csv$','menu-divisor.csv'),'w') or nil;
if divisor_out then divisor_out:write('epoch,before,after\n');divisor_out:flush();end
ashita.events.register('d3d_present','benchmark_menu_uncap',function()
  if not menu_uncap or clock_s()<next_divisor_check then return end
  next_divisor_check=clock_s()+1;
  if AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)~=0 then return end
  if not divisor_slot then
    local signature=ashita.memory.find(0,0,'81EC000100003BC174218B0D',0,0);
    if not signature or signature==0 then return end
    divisor_slot=ashita.memory.read_uint32(signature+0x0C);
  end
  if not divisor_slot or divisor_slot==0 then return end
  local object=ashita.memory.read_uint32(divisor_slot);
  if not object or object==0 then return end
  local before=ashita.memory.read_uint32(object+0x30);
  if before~=0 then ashita.memory.write_uint32(object+0x30,0);end
  if divisor_out then
    divisor_out:write(string.format('%.6f,%d,%d\n',epoch_s(clock_s()),before,ashita.memory.read_uint32(object+0x30)));divisor_out:flush();
  end
end);
ashita.events.register('unload','benchmark_menu_uncap_cleanup',function() if divisor_out then divisor_out:close();divisor_out=nil;end end);
