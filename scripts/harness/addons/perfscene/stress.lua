-- Repeatable local stress workloads. Only the driver starts them; no packet injection.
local M = {}
local bit = require('bit')
local names = { crowd = true, arrivals = true, camera = true,
                aga8 = true, aga24 = true, aga40 = true }
function M.is_scenario(name) return names[name] == true end
function M.scenarios(world, entities)
    local result = {}
    for name in pairs(names) do
        local aga = name:match('^aga(%d+)$')
        local s = {
            {1, "!exec xi.commands.perfstress = dofile('scripts/commands/perfstress.lua')", 'fixture command refreshed'},
            {1, "!exec xi.commands.perftime = dofile('scripts/commands/perftime.lua')", 'clock command refreshed'},
            {1, '!perftime 12', 'clock pinned to noon'},
            {1, '/fps 0', 'fps uncapped'}, {1, world, 'world draw distance set'},
            {1, entities, 'entity draw distance set'},
            {2, aga and '!exec player:setPos(30,-1,60,192,106)'
                    or '!exec player:setPos(39,0,-49,192,234)', 'stress zone requested'},
            {8, '!setweather 0', 'clear weather requested'},
            {2, 'home', 'camera reset requested'},
            {2, 'fixture clear 0', 'fixture cleared'},
        }
        local function add(delay, cmd, label) s[#s+1] = {delay, cmd, label} end
        local function phase(id, seconds)
            add(0.2, 'phase_start '..id, id..' settled')
            add(seconds, 'phase_end '..id, id..' end')
        end
        if aga then
            add(2, '!changejob RDM 99', 'RDM99 requested')
            add(2, '!changesjob BLM 49', 'BLM49 requested')
            add(2, '!addallspells', 'spells requested')
            add(3, 'aga_ready', 'aga character confirmed')
            add(1, '!exec player:delStatusEffect(48)', 'idle Chainspell cleared')
            add(1, 'fixture aga '..aga, 'mob pack requested')
            add(10, 'fixture_ready', 'mob pack confirmed')
            phase('aga-idle', 30)
            for round = 1, 2 do
                add(2, '!reset', 'recasts reset')
                add(2, '!exec player:delStatusEffect(48)', 'Chainspell cleared')
                add(2, '!perfstress 0 refill', 'MP and mob HP restored')
                add(1, 'target_pack', 'primary target requested')
                add(1, 'chainspell', 'Chainspell requested')
                add(1, 'phase_start aga-round-'..round, 'aga-round-'..round..' settled')
                for cast = 1, 10 do add(3, 'aga_cast', 'Firaga requested') end
                add(3, 'phase_end aga-round-'..round, 'aga-round-'..round..' end')
            end
        elseif name == 'crowd' then
            add(3, 'fixture_ready', 'empty fixture confirmed')
            phase('empty', 30)
            for _, count in ipairs({16, 32, 64}) do
                add(1, 'fixture city '..count, 'identical crowd requested')
                add(10, 'fixture_ready', 'crowd confirmed')
                phase('identical-'..count, 30)
            end
            add(1, 'fixture mixed 64', 'mixed crowd requested')
            add(10, 'fixture_ready', 'mixed crowd confirmed')
            phase('mixed-64', 30)
        elseif name == 'arrivals' then
            for round = 1, 3 do
                add(1, 'fixture clear 0', 'crowd removed')
                add(3, 'fixture_ready', 'empty fixture confirmed')
                add(1, 'phase_start arrival-'..round, 'arrival-'..round..' start')
                add(0.2, 'fixture mixed 32', 'arrival batch requested')
                add(10, 'fixture_ready', 'arrival batch confirmed')
                add(10, 'phase_end arrival-'..round, 'arrival-'..round..' end')
                phase('arrival-warm-'..round, 20)
            end
        else
            add(1, 'fixture mixed 64', 'camera crowd requested')
            add(10, 'fixture_ready', 'camera crowd confirmed')
            phase('facing-crowd', 30)
            -- Server-authoritative headings with a camera reset at each stop.
            -- Deliberate discrete turns; no wall-clock key hold masquerading as a fixed path.
            for i, heading in ipairs({0, 64, 128, 192}) do
                add(1, 'phase_start turn-'..i, 'turn-'..i..' start')
                add(0.2, '!exec player:setPos(39,0,-49,'..heading..',234)', 'heading requested')
                add(2, 'home', 'camera reset requested')
                add(8, 'phase_end turn-'..i, 'turn-'..i..' end')
                phase('heading-'..heading, 20)
            end
        end
        add(1, 'fixture clear 0', 'final fixture cleanup')
        add(3, 'fixture_ready', 'cleanup confirmed')
        add(1, 'done', 'done')
        result[name] = s
    end
    return result
end

-- Bounds-checked action decoder. Offset layout matches FFXI 0x028; optional additional
-- effects change each target's length, so a fixed stride is unsafe for an AoE packet.
function M.decode(data, unpack)
    local function bits(offset, count)
        if offset + count > #data * 8 then error('truncated action packet') end
        return unpack(offset, count)
    end
    local a = { actor=bits(40,32), count=bits(72,6), category=bits(82,4),
                id=bits(86,17), targets={} }
    local offset = 150
    for _ = 1, a.count do
        local t = { id=bits(offset,32), actions={} }
        local n = bits(offset+32,4)
        offset = offset + 36
        for _ = 1, n do
            t.actions[#t.actions+1] = { param=bits(offset+27,17), message=bits(offset+44,10) }
            offset = offset + 85
            local extra = bits(offset,1); offset = offset+1
            if extra == 1 then bits(offset+36,1); offset=offset+37 end
            local spikes = bits(offset,1); offset = offset+1
            if spikes == 1 then bits(offset+33,1); offset=offset+34 end
        end
        a.targets[#a.targets+1] = t
    end
    return a
end

function M.attach(ctx)
    local state, mark, send, now = ctx.state, ctx.mark, ctx.send, ctx.now
    local active, expected, mode, ids, pending, phase, deadline, polls = false, 0, 'clear', {}, nil, nil, 0, 0
    local cast_index, packet_hits, server_hits = 0,nil,nil
    local function fail(reason)
        pending = nil
        state.running = nil
        mark('scenario failed', ', "reason": "'..reason..'"')
        send('!perfstress 0 finish')
        active = false
    end
    local function resume()
        pending = nil
        local next_step = state.running and state.running[state.index+1]
        if next_step then state.next_at = now() + next_step[1] end
    end
    local function residents()
        local e = AshitaCore:GetMemoryManager():GetEntity()
        local found, n = {}, 0
        for index = 0, 2303 do
            local name = e:GetName(index)
            if name and name:match('^Bench%d%d$') and e:GetServerId(index) ~= 0
               and bit.band(e:GetRenderFlags0(index), 0x200) ~= 0 then
                found[e:GetServerId(index)] = name
                n = n+1
            end
        end
        return found,n
    end
    local function confirm()
        local found,n = residents()
        if n ~= expected then return false end
        local seen = {}
        for _,name in pairs(found) do seen[name]=true end
        for i=1,expected do if not seen[string.format('Bench%02d',i)] then return false end end
        ids = found
        return true
    end
    local function metadata(id)
        return string.format(', "phase": "%s", "expected_entities": %d, "fixture_mode": "%s"',id,expected,mode)
    end
    local function wait(kind)
        pending,deadline = kind,now()+15
        state.next_at=math.huge
    end
    local api = {}
    function api.start(name)
        active,expected,mode,ids,pending,phase = M.is_scenario(name),0,'clear',{},nil,nil
    end
    function api.command(cmd,label)
        if not active then return false end
        local m,n = cmd:match('^fixture (%w+) (%d+)$')
        if m then
            mode,expected=m,tonumber(n)
            cast_index=0
            send('!perfstress '..n..' '..m)
            mark(label, metadata(phase or 'setup'))
        elseif cmd == 'fixture_ready' then
            wait('fixture'); polls=0
        elseif cmd == 'aga_ready' then
            local p=AshitaCore:GetMemoryManager():GetPlayer()
            if state.zone~=106 or p:GetMainJob()~=5 or p:GetMainJobLevel()~=99
               or p:GetSubJob()~=4 or p:GetSubJobLevel()<28 or not p:HasSpell(174) then
                fail('RDM99/BLM28+ with Firaga in North Gustaberg required')
            else mark(label) end
        elseif cmd:match('^phase_start ') then
            phase=cmd:sub(13)
            mark('stress phase start',metadata(phase))
            if label:match('settled$') then mark(label) end
        elseif cmd:match('^phase_end ') then
            if not confirm() then fail('fixture population changed during phase')
            else mark('stress phase end',metadata(cmd:sub(11))); phase=nil end
        elseif cmd=='target_pack' then
            local mem=AshitaCore:GetMemoryManager()
            local index=mem:GetTarget():GetTargetIndex(0)
            if not index or not ids[mem:GetEntity():GetServerId(index)] then send('/targetnpc') end
            mark(label)
        elseif cmd=='chainspell' then
            send('/ja "Chainspell" <me>'); mark(label); wait('chainspell')
        elseif cmd=='aga_cast' then
            local mem=AshitaCore:GetMemoryManager()
            local index=mem:GetTarget():GetTargetIndex(0)
            if not confirm() then fail('mob pack changed before cast')
            elseif not index or not ids[mem:GetEntity():GetServerId(index)] then
                fail('selected target does not belong to the mob pack')
            else
                cast_index=cast_index+1;packet_hits,server_hits=nil,nil
                send('/ma "Firaga" <t>'); mark(label); wait('cast')
            end
        else return false end
        return true,pending~=nil
    end
    function api.tick()
        if not active then return end
        if pending and now()>=deadline then fail('stress response timed out after 15 seconds'); return end
        if pending=='fixture' and now()>=polls then
            polls=now()+0.5
            if confirm() then
                mark('fixture confirmed',metadata(phase or 'setup'))
                resume()
            end
        end
    end
    local function complete_cast()
        if not packet_hits or not server_hits then return end
        mark('stress cast completed', metadata(phase)..string.format(
            ', "spell_id": 174, "hit_count": %d, "packet_targets": %d, "cast_index": %d, "damage": %d',
            server_hits,packet_hits.count,cast_index,packet_hits.damage))
        resume()
    end
    function api.text(e)
        if not active or pending~='cast' then return end
        local serial,hits,total=(e.message or ''):match('PERFSTRESS cast (%d+) hits (%d+) expected (%d+)')
        if not serial then return end
        if tonumber(serial)~=cast_index or tonumber(hits)~=expected or tonumber(total)~=expected then
            fail('server Firaga audit differs from requested cast and pack'); return
        end
        server_hits=tonumber(hits);complete_cast()
    end
    function api.packet(e)
        if not active or (pending~='cast' and pending~='chainspell') or e.id~=0x028 then return end
        local ok,a=pcall(M.decode,e.data,function(offset,count)
            return ashita.bits.unpack_be(e.data_raw,0,offset,count)
        end)
        if not ok then fail('truncated action packet during stress cast'); return end
        local own=AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)
        if a.actor~=own then return end
        if pending=='chainspell' and a.category==6 and a.id==20 then
            if a.count~=1 or a.targets[1].id~=own or #a.targets[1].actions~=1
               or a.targets[1].actions[1].message~=100 then fail('Chainspell did not apply'); return end
            mark('stress Chainspell applied'); resume()
        elseif pending=='cast' and a.category==4 and a.id==174 then
            local seen, count, damage = {},0,0
            for _,t in ipairs(a.targets) do
                if not ids[t.id] or seen[t.id] or #t.actions~=1 then
                    fail('Firaga target set mismatch'); return
                end
                seen[t.id]=true
                local action=t.actions[1]
                if (action.message~=2 and action.message~=264) or action.param<=0 then
                    fail('Firaga did not damage every target'); return
                end
                count=count+1; damage=damage+action.param
            end
            if count~=math.min(expected,15) then fail('Firaga packet target count differs from protocol limit'); return end
            packet_hits={count=count,damage=damage};complete_cast()
        end
    end
    function api.is_active() return active end
    function api.stop()
        if active then send('!perfstress 0 finish') end
        active,pending=false,nil
    end
    return api
end
return M
