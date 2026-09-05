-- Run from the repository root with luajit scripts/tests/perftime-test.lua.
local clock = 1788620800
os.time = function() return clock end
local command = dofile('scripts/lsb-docker/commands/perftime.lua')
xi = { commands = { time = { onTrigger = function() end } } }
local writes, offset, hour, minute = {}, 0, 0, 0
GetSystemTime = function() return clock + offset end
SetTimeOffset = function(value) writes[#writes + 1] = value end
VanadielHour = function() return hour end
VanadielMinute = function() return minute end
local player = { printToPlayer = function() end }
for _, previous in ipairs({ -5000, 0, 2000 }) do
    offset = previous
    for h = 0, 23 do
        for _, m in ipairs({ 0, 1, 59 }) do
            hour, minute, writes = h, m, {}
            command.onTrigger(player, 12)
            assert(#writes == 1 and writes[1] <= offset, 'clock jumped forward')
            local adjusted = ((h * 60 + m) * 60 + (writes[1] - offset) * 25) % 86400
            assert(math.abs(adjusted - 43200) < 25, 'clock missed noon')
        end
    end
end
for _, invalid in ipairs({ -1, 24 }) do
    writes = {}
    command.onTrigger(player, invalid)
    assert(#writes == 0, 'invalid hour changed the clock')
end
print('216 clock cases and two invalid hours passed')
