local live,removed,nextid,timers={}, {},100,{}
local listener, message
xi={objType={MOB=2,NPC=1},status={DISAPPEAR=2},mobMod={NO_DROPS=1}}
GetMobByID=function(id) return live[id] end
GetNPCByID=function(id) return live[id] end
DespawnMob=function(id) live[id]=nil;removed[#removed+1]=id end
GetPlayerByID=function() return {removeListener=function() end} end
local zoneid=234
local zone={getID=function() return zoneid end,insertDynamicEntity=function(_,p)
    nextid=nextid+1
    local id=nextid
    local e={getID=function() return id end,hideNPC=function() live[id]=nil end,
        timer=function(_,ms,f) timers[#timers+1]={ms,f} end}
    for _,name in ipairs({'setSpawn','setPos','setDropID','setMobMod','spawn','setAutoAttackEnabled','setMagicCastingEnabled',
                         'setMobAbilityEnabled','setBaseSpeed','setUnkillable','setMaxHP','setHP'}) do
        e[name]=function() end
    end
    e.setSpawn=function(_,x,y,z) e.spawnPos={x,y,z} end
    e.spawn=function() assert(e.spawnPos, 'spawn point must be set before spawning') end
    e.getMaxHP=function() return 1000000 end
    e.params=p;live[id]=e;return e
end}
local name='Hxitest'
local player={getName=function() return name end,getID=function() return 42 end,
    addListener=function(_,_,_,callback) listener=callback end, getZone=function() return zone end,getXPos=function() return 0 end,getYPos=function() return 0 end,
    getZPos=function() return 0 end,printToPlayer=function(_,text) message=text end}
local cmd=dofile('scripts/lsb-docker/commands/perfstress.lua')
cmd.onTrigger(player,8,'aga');assert(next(live)==nil,'mobs spawned in town')
name='Personal';cmd.onTrigger(player,16,'city');assert(next(live)==nil,'touched wrong character')
name='Hxitest';cmd.onTrigger(player,16,'city');assert(#xi.perfFixtures[42].rows==16)
local firstTimer=timers[1][2]
cmd.onTrigger(player,32,'mixed');assert(#xi.perfFixtures[42].rows==32)
firstTimer();assert(#xi.perfFixtures[42].rows==32,'old lease removed new generation')
cmd.onTrigger(player,0,'clear');assert(next(live)==nil,'NPC cleanup leaked')
zoneid=106;cmd.onTrigger(player,40,'aga');assert(#xi.perfFixtures[42].rows==40)
listener(player,nil,{getID=function() return 174 end},{getMsg=function() return 264 end,getParam=function() return 10 end})
assert(message=='PERFSTRESS cast 1 hits 40 expected 40','server did not audit full pack')
timers[#timers][2]();assert(next(live)==nil and xi.perfFixtures[42]==nil,'lease did not clean up')
cmd.onTrigger(player,100,'aga');assert(next(live)==nil,'unbounded crowd')
print('Fixture identity, zone restrictions, bounded populations, cleanup and expiry passed')
