package.path='scripts/harness/addons/perfscene/?.lua;'..package.path
local stress=require('stress')
local plans=stress.scenarios('/drawdistance setworld 20','/drawdistance setmob 20')
for name,steps in pairs(plans) do
    local duration,casts=0,0
    for _,s in ipairs(steps) do
        duration=duration+s[1]
        assert(#s[2]<=118,'chat payload too long')
        if s[2]=='aga_cast' then casts=casts+1 end
    end
    assert(duration<300, 'scenario leaves insufficient launch headroom')
    if name:match('aga') then assert(casts==20) end
end
local clock,commands,marks,state,entities=0,{},{},{running={},index=1,zone=106},{}
local own,selected=42,nil
local entity={
    GetName=function(_,i) return entities[i] and entities[i].name end,
    GetServerId=function(_,i) return entities[i] and entities[i].id or 0 end,
    GetRenderFlags0=function(_,i) return entities[i] and 0x200 or 0 end,
}
AshitaCore={GetMemoryManager=function() return {
    GetEntity=function() return entity end,
    GetTarget=function() return {GetTargetIndex=function() return 1 end,SetTarget=function(_,i) selected=i end} end,
    GetParty=function() return {GetMemberServerId=function() return own end} end,
    GetPlayer=function() return {GetMainJob=function() return 5 end,GetMainJobLevel=function() return 99 end,
        GetSubJob=function() return 4 end,GetSubJobLevel=function() return 49 end,HasSpell=function() return true end} end,
} end}
ashita={bits={unpack_be=function(data,_,offset,count) return data[offset] or 0 end}}
local function reset()
    clock,commands,marks=0,{},{}
    state.running={{1},{1}};state.index=1
    return stress.attach({state=state,now=function() return clock end,
        send=function(s) commands[#commands+1]=s end,
        mark=function(label,extra) marks[#marks+1]={label=label,extra=extra or ''} end})
end
local function packet(n,bad)
    local fields={[40]=42,[72]=n,[82]=4,[86]=174}
    local offset=150
    for i=1,n do
        fields[offset]=100+i;fields[offset+32]=1
        fields[offset+63]=10;fields[offset+80]=bad and 85 or (i==1 and 2 or 264)
        offset=offset+123
    end
    return {id=0x028,data=string.rep('\0',math.ceil(offset/8)),data_raw=fields}
end
for i=1,8 do entities[i]={name=string.format('Bench%02d',i),id=100+i} end
local api=reset();api.start('aga8');api.command('fixture aga 8','setup')
api.command('fixture_ready','ready');api.tick()
assert(marks[#marks].label=='fixture confirmed')
api.command('align_camera','camera target selected');assert(selected==1,'camera targeted outside the fixture')
local sent=#commands
api.command('target_pack','target')
assert(#commands==sent,'retargeting toggled off an already valid target')
api.command('phase_start aga-round-1','start');api.command('aga_cast','cast');api.packet(packet(8))
assert(marks[#marks].label~='stress cast completed','accepted client response without server audit')
api.text({message='PERFSTRESS cast 1 hits 8 expected 8'})
assert(marks[#marks].label=='stress cast completed')
assert(marks[#marks].extra:find('"hit_count": 8'))
api.command('aga_cast','cast');api.packet(packet(7))
assert(marks[#marks].label=='scenario failed' and commands[#commands]=='!perfstress 0 finish')
api=reset();api.start('aga8');api.command('fixture aga 8','setup');api.command('fixture_ready','ready');api.tick()
api.command('aga_cast','cast');api.packet(packet(8,true))
assert(marks[#marks].label=='scenario failed','accepted no-damage casts')
api=reset();api.start('aga8');api.command('chainspell','ability');clock=16;api.tick()
assert(marks[#marks].label=='scenario failed','missing Chainspell did not timeout')
api=reset();api.start('crowd');api.command('fixture city 16','setup');api.command('fixture_ready','ready')
clock=16;api.tick();assert(marks[#marks].label=='scenario failed','accepted short fixture')
local ok=pcall(stress.decode,'short',function() return 0 end)
assert(not ok,'accepted truncated packet')
-- Optional effects alter offsets; exercise both extension flags before target two.
local fields={[40]=42,[72]=2,[82]=4,[86]=174,[150]=101,[182]=1,[213]=9,[230]=2,
              [271]=1,[309]=1,[344]=102,[376]=1,[407]=10,[424]=264}
local decoded=stress.decode(string.rep('\0',64),function(offset) return fields[offset] or 0 end)
assert(decoded.targets[2].id==102 and decoded.targets[2].actions[1].message==264,
       'optional effect offsets broke second target')
for i=9,40 do entities[i]={name=string.format('Bench%02d',i),id=100+i} end
api=reset();api.start('aga40');api.command('fixture aga 40','setup');api.command('fixture_ready','ready');api.tick()
api.command('phase_start aga-round-1','start');api.command('aga_cast','cast')
api.text({message='PERFSTRESS cast 1 hits 40 expected 40'});api.packet(packet(15))
assert(marks[#marks].label=='stress cast completed' and marks[#marks].extra:find('"packet_targets": 15'),
       'did not reconcile full server audit with capped client response')
api.command('aga_cast','cast');api.text({message='PERFSTRESS cast 2 hits 39 expected 40'})
assert(marks[#marks].label=='scenario failed','accepted incomplete server hit audit')
print('Stress cadence, population, AoE hit validation, timeout and packet bounds passed')
