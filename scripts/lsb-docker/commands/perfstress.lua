-- Local Hxitest fixtures. Never move or alter the zone's original entities.
-- !perfstress <count> <city|mixed|aga|clear|refill> <lease>
-- NPCs can spawn in towns; attackable mobs are restricted to North Gustaberg.
local commandObj = {}
commandObj.cmdprops = { permission = 1, parameters = 'isi' }
local looks = {
    '0x01000B0102107620AB30AC401850736000700000',
    '0x01000A027D103B2000303B40A050006000700000',
    '0x01000901A510A520AB30A540AB50776100700000',
    '0x01000708C310C320C33060407A50886100700000',
    '0x01000A06AC10AB20AB3060407A50006000700000',
    '0x01000903AC10AB20AB3060407A50006000700000',
    '0x01000D07AC10AB20AB3060407A50006000700000',
}
-- Survives command hot reload. Store IDs, not Lua entity references after disappearance.
xi.perfFixtures = xi.perfFixtures or {}
local function remove(row)
    local entity = row.mob and GetMobByID(row.id) or GetNPCByID(row.id)
    if entity then
        if row.mob then DespawnMob(row.id) else entity:setStatus(xi.status.DISAPPEAR) end
    end
end
local function clear(owner)
    local old = xi.perfFixtures[owner]
    xi.perfFixtures[owner] = nil
    local player = GetPlayerByID(owner)
    if player then player:removeListener('PERFSTRESS_MAGIC') end
    if old then for _, row in ipairs(old.rows) do remove(row) end end
end
commandObj.onTrigger = function(player, count, mode, lease)
    if player:getName() ~= 'Hxitest' then return end
    local owner, zone = player:getID(), player:getZone()
    if not zone then return end
    mode, count, lease = mode or 'aga', count or 40, lease or 420
    if mode == 'finish' then clear(owner); SetTimeOffset(0); return end
    if mode == 'clear' then clear(owner); return end
    if mode == 'refill' then
        local fixture = xi.perfFixtures[owner]
        if fixture and fixture.zone == zone:getID() then
            player:setMP(player:getMaxMP())
            for _, row in ipairs(fixture.rows) do
                if row.mob then
                    local mob = GetMobByID(row.id)
                    if mob then mob:setHP(mob:getMaxHP()) end
                end
            end
        end
        return
    end
    if count < 0 or count > 64 or lease < 10 or lease > 420 or
       (mode ~= 'city' and mode ~= 'mixed' and mode ~= 'aga') then return end
    if mode == 'aga' and (zone:getID() ~= 106 or count > 40) then return end
    if mode ~= 'aga' and zone:getID() ~= 234 and zone:getID() ~= 235 then return end
    clear(owner)
    local fixture = { rows = {}, zone = zone:getID() }
    xi.perfFixtures[owner] = fixture
    local x, y, z = player:getXPos(), player:getYPos(), player:getZPos()
    for i = 1, count do
        -- Fixed grid south of the player; aga pack fits inside Firaga's radius.
        local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
        local mob = mode == 'aga'
        local spacing = mob and 0.45 or 1.2
        local params = {
            objtype = mob and xi.objType.MOB or xi.objType.NPC,
            name = string.format('Bench%02d', i), packetName = string.format('Bench%02d', i),
            x = x + (col - 3.5) * spacing, y = y, z = z + 7 + row * spacing,
            rotation = 192, releaseIdOnDisappear = true,
            look = mob and 272 or looks[mode == 'mixed' and ((i - 1) % #looks + 1) or 1],
            widescan = 0,
        }
        if mob then
            -- A retained SQL template in current LSB; synthetic hornet appearance, no AI/loot.
            params.groupId, params.groupZoneId = 5, 154
            params.minLevel, params.maxLevel = 1, 1
            params.respawn, params.isAggroable = 0, false
            params.modelHitboxSize = 1
        end
        local entity = zone:insertDynamicEntity(params)
        if not entity then clear(owner); player:printToPlayer('perfstress: creation failed'); return end
        fixture.rows[#fixture.rows + 1] = { id = entity:getID(), mob = mob }
        if mob then
            entity:setDropID(0)
            entity:setMobMod(xi.mobMod.NO_DROPS, 1)
            entity:setSpawn(params.x, params.y, params.z, params.rotation)
            entity:spawn()
            entity:setPos(params.x, params.y, params.z, params.rotation)
            entity:setAutoAttackEnabled(false)
            entity:setMagicCastingEnabled(false)
            entity:setMobAbilityEnabled(false)
            entity:setBaseSpeed(0)
            entity:setUnkillable(true)
            entity:setMaxHP(1000000)
            entity:setHP(1000000)
        end
        -- The callback owns a generation, so an old timer cannot remove a replacement pack.
        entity:timer(lease * 1000, function()
            if xi.perfFixtures[owner] == fixture then clear(owner) end
        end)
    end
    if mode == 'aga' then
        fixture.casts = 0
        player:addListener('MAGIC_USE', 'PERFSTRESS_MAGIC', function(caster, target, spell, action)
            if xi.perfFixtures[owner] ~= fixture or spell:getID() ~= 174 then return end
            fixture.casts = fixture.casts + 1
            local hits = 0
            for _, row in ipairs(fixture.rows) do
                local msg = action:getMsg(row.id)
                if (msg == 2 or msg == 264) and action:getParam(row.id) > 0 then hits = hits + 1 end
            end
            -- The client action packet carries at most 15 targets. Verify all server targets
            -- independently without modifying that packet or the spell implementation.
            caster:printToPlayer(string.format('PERFSTRESS cast %d hits %d expected %d',
                fixture.casts, hits, #fixture.rows))
        end)
    end
    player:printToPlayer(string.format('perfstress: ready %s %d lease %d', mode, #fixture.rows, lease))
end
return commandObj
