-- Usage: luajit test_template_environments.lua <src>
-- World modifiers on synthetic memory: which are present decides which tags
-- join the environment, as 1267460, 12672b0 and 12e1210 decide it.
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local O=H.offsets(arg[1])
local bytes={}
local function put(address,value,size)
    for i=0,(size or 4)-1 do bytes[address+i]=value%256;value=math.floor(value/256)end
end
local function read(address,size)
    local out={}
    for i=0,size-1 do out[i+1]=string.char(bytes[address+i] or 0)end
    return table.concat(out)
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function pointer(s)
    local value=0
    for i=8,1,-1 do value=value*256+s:byte(i)end
    return value>=0x10000 and value or nil
end
local game,board,heap=0x10000000,0x20000000,0x30000000
local campaign=board+O.board.campaign
local function alloc(size)local at=heap;heap=heap+size;return at end
local planet,other=2,4
put(campaign+O.campaign.planet_count,10);put(campaign+O.campaign.campaign_planet_count,10)
put(game+O.rva.objectives,alloc(0x20000),8)
-- Definitions: A, B, C and D carry one tag each; tag 9 is never added.
local hashes={A=0xa1,B=0xb2,C=0xc3,D=0xd4}
local tags={A={3},B={5,9},C={6},D={7}}
local definition={}
local ids,values=alloc(64),alloc(64);local n=0
for _,name in ipairs({'A','B','C','D'})do
    local at=alloc(0x200);definition[name]=at
    local list=alloc(16)
    for i,tag in ipairs(tags[name])do put(list+(i-1)*4,tag)end
    put(at+0x60,list,8);put(at+0x68,#tags[name])
    put(ids+n*4,hashes[name]);put(values+n*8,at,8);n=n+1
end
put(board+O.board.world_modifier_values,values,8);put(board+O.board.world_modifier_ids,ids,8);put(board+O.board.world_modifier_count,n)
local events=alloc(0x3000);put(game+O.rva.global_effects,events,8)
local function event(i,kind,target,holder,name)
    local at=events+i*O.global_effects.size
    put(at,17,1);put(at+4,hashes[name]);put(at+0x50,1)
    put(at+0x54,kind,1);put(at+0x58,target);put(at+0x5c,holder)
    put(events+O.global_effects.count,math.max(i+1,u(read(events+O.global_effects.count,4),0)))
end
local function state(i,name,required,excluded,flag)
    local at=game+O.rva.state_modifiers+i*16
    put(at,name and hashes[name] or 0);put(at+4,required and hashes[required] or 0)
    put(at+8,excluded and hashes[excluded] or 0);put(at+12,flag or 0,1)
end
local function override(i,name,kind)
    local at=board+O.board.planet_overrides+i*12
    put(at,hashes[name]);put(at+4,planet);put(at+8,kind);put(board+O.board.planet_override_count,i+1)
end
local effects={collect=function()return {}end,binding=function()return nil end}
local environments=H.module(arg[1]..'/template_environments.lua')(read,u,pointer,game,board,effects,function()return nil end)
local function check(expected,message)
    local got=table.concat(environments(planet,{},true),',')
    assert(got==expected,message..': expected ['..expected..'] got ['..got..']')
end
put(campaign+O.campaign.planet_faction+planet*O.campaign.planet_stride,3);put(campaign+O.campaign.planet_region+planet*O.campaign.planet_stride,7)

-- Events: another planet's event is ignored; an owner-scoped one applies.
event(0,0,other,0,'A')
check('','An event for another planet adds nothing')
event(1,2,3,0,'B')
check('5','An event for the planet owner adds its tags; tag 9 is dropped')
put(events+O.global_effects.size+0x5c,4)
check('','An event limited to another holder adds nothing')
put(events+O.global_effects.size+0x5c,3);put(events+O.global_effects.size+0x54,1,1);put(events+O.global_effects.size+0x58,7)
check('5','A sector event applies to the planet in that sector')
put(events+O.global_effects.size+0x54,3,1);put(events+O.global_effects.size+0x58,0)
check('5','A global event applies everywhere')

-- State entries depend on the modifiers collected before them.
state(0,'C','A');state(1,nil)
check('5','A modifier that requires an absent one stays absent')
state(0,'C','B');state(1,'D',nil,'C')
check('5,6','A modifier whose requirement is present applies; an excluded one does not')
state(1,'D',nil,'A')
check('5,6,7','An exclusion of an absent modifier does not block')
put(campaign+O.campaign.planet_enabled+planet*O.campaign.planet_stride,1,1);state(1,'D',nil,'A',1)
check('5,6','A flagged entry is skipped on a planet with its campaign byte set')
put(campaign+O.campaign.planet_enabled+planet*O.campaign.planet_stride,0,1);state(1,nil)

-- Overrides: add A, then remove B; A moves into B's slot, as in the game.
override(0,'A',1);override(1,'B',2)
check('3,6','Overrides add and remove modifiers')
put(board+O.board.planet_override_count,0)

-- A planet held by faction 1 takes unflagged modifiers only while listed.
put(campaign+O.campaign.planet_faction+planet*O.campaign.planet_stride,1);put(campaign+O.campaign.campaign_planet_count,10)
put(events+O.global_effects.count,0);state(0,'C')
check('','An unlisted faction-1 planet ignores unflagged modifiers')
put(campaign+O.campaign.bases+8+20,planet);put(campaign+O.campaign.base_count,2)
check('6','A listed faction-1 planet takes them')
put(campaign+O.campaign.base_count,0);put(definition.C+O.world_modifier.flags,1,1)
check('6','A flagged modifier applies to any faction-1 planet')
put(definition.C+O.world_modifier.flags,0,1)
put(campaign+O.campaign.planet_faction+planet*O.campaign.planet_stride,3)

-- An operation-suppressing modifier is refused only when present.
put(definition.D+0x4c,2,1);state(1,'D','A')
check('6','An absent suppressing modifier is harmless')
state(1,'D')
assert(not pcall(environments,planet,{},true),'A present suppressing modifier is refused')
print('template environments: world-modifier presence, dependencies, overrides and tags passed')
