local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local O=H.offsets(arg[1])
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d);return a+b*256+c*65536+d*16777216 end
local defs,game=1000000,10000000
local memory={}
memory[game+O.rva.categories+9]='\0';memory[game+O.rva.categories+8*0xa8+9]='\1'
memory[defs+O.definitions.special_pool_count]=word(1);memory[defs+O.definitions.pool_count]=word(1)
memory[defs+O.definitions.special_pool_start]=word(0);memory[defs+O.definitions.pool_start]=word(0)
memory[defs+O.definitions.level_roots]=word(8);memory[defs+O.definitions.node_count]=word(12)
memory[defs+8*0x88+0x78]=word(2)
memory[defs+8*0x88+0x18]=word(0);memory[defs+8*0x88+0x1c]=word(1)
memory[defs+O.definitions.edges]=word(8)..word(9);memory[defs+O.definitions.edges+0x30]=word(10)..word(8)
memory[defs+9*0x88+0x14]=word(6);memory[defs+10*0x88+0x14]=word(4)
local function read(address,size)local bytes=assert(memory[address],'Unexpected graph read');assert(#bytes==size);return bytes end
local collect=H.module(arg[1]..'/level_inputs.lua')(read,u,game)
local levels,special,key=collect(defs,{id=0,category=0})
assert(not special and #levels==2 and levels[1]==8 and levels[2]==9)
levels,special=collect(defs,{id=0,category=8})
assert(special and #levels==2 and levels[2]==10)
memory[defs+9*0x88+0x14]=word(4)
local changed,_,changed_key=collect(defs,{id=0,category=0})
assert(#changed==1 and changed_key~=key,'Graph metadata must affect fingerprint')
memory[defs+9*0x88+0x14]=word(6)
assert(#collect(defs,{id=1,category=0})==0,'Out-of-pool ID has no levels')
assert(not pcall(collect,defs,{id=-1,category=0}))
memory[defs+O.definitions.level_roots]=word(4294967295);assert(#collect(defs,{id=0,category=0})==0)
memory[defs+O.definitions.level_roots]=word(12);assert(not pcall(collect,defs,{id=0,category=0}))
memory[defs+O.definitions.level_roots]=word(8)
memory[defs+8*0x88+0x78]=word(25);assert(not pcall(collect,defs,{id=0,category=0}))
memory[defs+8*0x88+0x78]=word(2)
memory[defs+8*0x88+0x18]=word(12288);assert(not pcall(collect,defs,{id=0,category=0}))
memory[defs+8*0x88+0x18]=word(0)
memory[defs+O.definitions.edges]=word(8)..word(12);assert(not pcall(collect,defs,{id=0,category=0}))

local make_rng=dofile(arg[1]..'/generation_rng.lua')
local choose=dofile(arg[1]..'/mission_level_choice.lua')
local verify=dofile(arg[1]..'/level_verification.lua')(make_rng,choose)
local rng=make_rng(99);local missions={}
for i=1,3 do
    if i==2 then rng:next()end
    missions[i]={seed=rng:next(),level_index=9+i}
end
local operations={{row=0,seed=99,missions=missions}}
local graphs={[0]={levels={10,11,12},special=false}}
local result=verify(operations,graphs)
assert(result.passed and result.checked==3 and result.category_draws==1)
missions[2].level_index=12;result=verify(operations,graphs)
assert(not result.passed and result.checked==1 and result.errors[1]:find('expected_level=11',1,true),
    'An observed level must never influence which RNG trace is accepted')
missions[2].level_index=11
missions[2].seed=(missions[2].seed+1)%4294967296;result=verify(operations,graphs)
assert(not result.passed and result.errors[1]:find('RNG trace',1,true))
assert(not verify({},{}).passed)
print('Level graph decoder: normal/special edges, fingerprints and bounds; seed-assisted verification catches level and RNG mismatches')
