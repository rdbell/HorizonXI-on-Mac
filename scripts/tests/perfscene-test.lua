-- Run from the repository root with luajit scripts/tests/perfscene-test.lua.
local original_getenv, original_print = os.getenv, print;
local clock, commands, labels, handlers, name, job, level, learned, packets, respond;
local spell_ids = { ['Blaze Spikes'] = 249, ['Ice Spikes'] = 250, ['Shock Spikes'] = 251,
                    Stoneskin = 54, Blink = 53, Aquaveil = 55 };
local nx_enabled, nx_flags, nx_fails = false, 2, false;
local player = {
    GetIsZoning = function() return 0 end,
    GetMainJob = function() return job end,
    GetMainJobLevel = function() return level end,
    HasSpell = function() return learned end,
};
local party = {
    GetMemberName = function() return name end,
    GetMemberZone = function() return 234 end,
    GetMemberTargetIndex = function() return 0 end,
    GetMemberServerId = function() return 42 end,
};
local memory = { GetPlayer = function() return player end, GetParty = function() return party end };
local learn_allowed = true;
local chat_manager = { QueueCommand = function(_, _, command)
    commands[#commands + 1] = { time = clock, command = command };
    if command == '!changejob RDM 99' then job, level = 5, 99 end
    if command == '!addallspells' and learn_allowed then learned = true end
    local spell = command:match('^/ma "([^"]+)" <me>$');
    if spell and respond then
        packets[#packets + 1] = { at = clock + 2, id = spell_ids[spell] };
    end
end };
AshitaCore = {
    GetMemoryManager = function() return memory end,
    GetChatManager = function() return chat_manager end,
};
ashita = {
    events = { register = function(_, id, handler) handlers[id] = handler end },
    bits = { unpack_be = function(data, _, offset) return data[offset] or 0 end },
};
package.preload.common = function() return {} end;
package.preload.chat = function() return {
    header = function() return { append = function(_, value) return value end } end,
    message = function(value) return value end, error = function(value) return value end,
} end;
package.preload['ffxi.time'] = function() return {} end;
package.loaded.ffi = {
    cdef = function() end, new = function(_, initial) return { [0] = initial or 0 } end,
    cast = function(_, value) return value end,
    load = function() return {
        NtQueryInformationProcess = function(_, _, out) out[0] = nx_flags; return 0 end,
        NtSetInformationProcess = function(_, _, flags)
            if nx_fails then return -1 end
            nx_flags = flags[0]; return 0;
        end,
    } end,
    C = {
        QueryPerformanceCounter = function(out) out[0] = clock * 1000 end,
        QueryPerformanceFrequency = function(out) out[0] = 1000 end,
        GetSystemTimeAsFileTime = function(out) out[0] = 11644473600 * 10000000 end,
    },
};
os.getenv = function(key)
    if key == 'PERFSCENE_SCENARIO' then return 'effects' end
    if key == 'PERFSCENE_ENFORCE_NX' and nx_enabled then return '1' end
end;
print = function(label) labels[#labels + 1] = label end;
local function run(character, can_learn, reply)
    clock, commands, labels, handlers, packets = 0, {}, {}, {}, {};
    name, job, level, learned, learn_allowed = character, 1, 1, false, can_learn;
    respond = reply;
    addon = {};
    dofile('scripts/harness/addons/perfscene/perfscene.lua');
    handlers.perfscene_load();
    for tick = 0, 3000 do
        clock = tick / 10;
        for _, packet in ipairs(packets) do
            if not packet.sent and clock >= packet.at then
                packet.sent = true;
                handlers.perfscene_effect_actions({ id = 0x028, data = string.rep('\0', 30), data_raw = {
                    [40] = 42, [72] = 1, [82] = 4, [86] = packet.id, [150] = 42,
                    [182] = 1, [191] = packet.id, [230] = 230,
                } });
            end
        end
        handlers.perfscene_present();
    end
end
run('PersonalCharacter', true);
assert(#commands == 0, 'effects setup touched a different character');
assert(labels[#labels] == 'scenario failed');
run('Hxitest', false);
for _, row in ipairs(commands) do assert(not row.command:match('^/ma '), 'cast without spells') end
assert(labels[#labels] == 'scenario failed');
run('Hxitest', true, false);
local requests = 0;
for _, row in ipairs(commands) do if row.command:match('^/ma ') then requests = requests + 1 end end
assert(requests == 1 and labels[#labels] == 'scenario failed', 'missing response did not stop the sequence');
run('Hxitest', true, true);
local spells, chainspells, previous_cast = {}, 0, -math.huge;
for _, row in ipairs(commands) do
    assert(not row.command:find('perfcrowd'), 'effects test spawned mobs in town');
    assert(#row.command <= 118, 'command exceeds the chat payload limit');
    if row.command == '/ja "Chainspell" <me>' then chainspells = chainspells + 1 end
    local spell = row.command:match('^/ma "([^"]+)" <me>$');
    if spell then
        assert(row.time - previous_cast >= 5, 'next cast did not wait for completion plus cadence');
        previous_cast = row.time;
        spells[spell] = (spells[spell] or 0) + 1;
    end
end
assert(chainspells == 3);
for _, spell in ipairs({ 'Blaze Spikes', 'Ice Spikes', 'Shock Spikes', 'Stoneskin', 'Blink', 'Aquaveil' }) do
    assert(spells[spell] == 3, 'missing repeated casts for ' .. spell);
end
assert(labels[#labels] == 'done', 'bounded effects sequence did not finish');
assert(nx_flags == 2, 'changed execution policy without diagnostic opt-in');
nx_enabled = true;
run('Hxitest', true, true);
assert(nx_flags == 9 and labels[#labels] == 'done', 'NX diagnostic did not apply and complete');
nx_flags, nx_fails = 2, true;
run('Hxitest', true, true);
local failed = false;
for _, label in ipairs(labels) do failed = failed or label == 'scenario failed' end
assert(nx_flags == 2 and #commands == 0 and failed,
    'continued after execution-policy verification failed');
os.getenv, print = original_getenv, original_print;
print('Effects identity, readiness, chat length, response timeout, cadence and repetition checks passed');
