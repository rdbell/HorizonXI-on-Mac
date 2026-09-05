-- Local benchmark clock. Never jump forward: session expiry uses this clock.
local commandObj = {}
commandObj.cmdprops = { permission = 1, parameters = 'i' }
commandObj.onTrigger = function(player, hour)
    hour = hour or 12
    if hour < 0 or hour > 23 then return end
    local offset = GetSystemTime() - os.time()
    local current = (VanadielHour() * 60 + VanadielMinute()) * 60
    local backwards = math.ceil(((current - hour * 3600) % 86400) / 25)
    SetTimeOffset(offset - backwards)
    player:printToPlayer(string.format('perftime: moved back %d earth seconds', backwards))
    xi.commands.time.onTrigger(player)
end
return commandObj
