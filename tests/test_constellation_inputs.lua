local root=arg[1]
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local make_inputs=H.module(root..'/constellation_inputs.lua')
local ffi=require('ffi')
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function single(n)local v=ffi.new('float[1]',n);return ffi.string(v,4)end
local function u(b,o)local a,c,d,e=b:byte(o+1,o+4);return a+c*256+d*65536+e*16777216 end
-- Sparse zero-filled memory; every read is counted.
local memory,reads={},0
local function poke(address,bytes)for i=1,#bytes do memory[address+i-1]=bytes:byte(i)end end
local function read(address,size)
    reads=reads+1;local out={}
    for i=0,size-1 do out[#out+1]=string.char(memory[address+i] or 0)end
    return table.concat(out)
end
local game,board,globals=0x10000000,0x20000000,0x30000000
local function pointer(bytes,offset)
    local value=u(bytes,offset or 0)
    if value<0x10000 then return nil end
    return value
end
for i=0,31 do poke(game+0x21e1920+i*4,word(0x1000+i))end
poke(game+0x346d518,word(globals))
local values={}
local config={hash=function(path)return table.concat(path,':')end,lookup=function(key)return values[key]end}
local rows={}
local effects={collect=function(planet,effect,class)
    assert(class==0x28,'Enemy tags use effect class 0x28')
    return rows[planet..':'..effect] or {}
end}
local function effect(kind,hash)return string.rep('\0',24)..word(kind)..word(hash)..string.rep('\0',20)end
local inputs=make_inputs(read,u,pointer,game,board,effects,config)
-- Difficulty rows: faction offsets, flags, fallback and the configured cap.
for difficulty=1,10 do
    local row=game+0x328d2a0+(difficulty-1)*0x330
    poke(row+0x110,word(difficulty))
    for faction,first in pairs({[2]=0x114,[3]=0x174,[4]=0x1d4})do
        poke(row+first,word(faction)..single(0.5)..string.char(1))
        poke(row+first+12,word(faction+10)..single(0.25)..string.char(0))
    end
    poke(row+0x27c,word(27)..word(28))
    poke(row+0x27c+32,word(28))
end
local bots=inputs.settings(3,4)
assert(bots.draws==4 and bots.candidates[1].id==3 and bots.candidates[1].only_when_empty and bots.candidates[1].weight==0.5)
assert(bots.candidates[2].id==13 and not bots.candidates[2].only_when_empty and bots.candidates[3].id==0 and bots.fallback==0)
local squid=inputs.settings(4,10)
assert(squid.draws==10 and squid.fallback==28 and squid.blockers[1]==27 and squid.blockers[2]==28 and squid.blockers[3]==0)
local count=reads;assert(inputs.settings(4,10)==squid and reads==count,'Decoded settings are cached')
assert(not pcall(inputs.settings,1,5) and not pcall(inputs.settings,5,5))
values['2938211500:4205559465']=string.rep('\0',12)..word(6)..word(7)..string.rep('\0',4)
local capped=make_inputs(read,u,pointer,game,board,effects,config)
assert(capped.settings(2,10).draws==7 and capped.settings(2,3).draws==3 and capped.settings(2,0).draws==1,'Difficulty cap and zero difficulty')
values['2938211500:4205559465']=nil
-- Mission records.
local mission=game+0x3773420+72*0x380
poke(mission+8,word(2));poke(mission+0x14,word(12)..word(0)..word(9));poke(mission+0x34,string.char(1))
local record=inputs.mission(72)
assert(record.faction==2 and not record.horde and #record.exclusions==1 and record.exclusions[1]==12,'Exclusions stop at the first empty slot')
local horde=game+0x3773420+17*0x380
poke(horde+8,word(3));poke(horde+0x34,string.char(2));poke(horde+0x360,'\x49\x78\x82\x7f\xd1\x2c\x7c\x85')
assert(inputs.mission(17).horde and inputs.mission(17).faction==3)
poke(game+0x3773420+18*0x380+0x34,string.char(2))
assert(not inputs.mission(18).horde,'Horde needs the matching resource')
poke(game+0x3773420+19*0x380+0x14,word(32))
assert(not pcall(inputs.mission,19) and not pcall(inputs.mission,162) and not pcall(inputs.mission,-1))
-- Special-operation effect binding.
local campaign=board+0x101438
poke(game+0x32e98e0+5*0xa8+9,string.char(1))
poke(campaign+0x26018,word(2));poke(campaign+0x23018,word(100)..word(7)..word(0));poke(campaign+0x23018+24,word(268)..word(9)..word(0))
assert(inputs.effect_id(5,9,268)==9 and inputs.effect_id(5,7,268)==4294967295 and inputs.effect_id(0,9,268)==4294967295)
assert(inputs.effect_id(14,9,268)==4294967295)
-- Campaign effects, then global entries by scope and faction filter.
poke(board+0x12444c,word(300))
local dynamic=board+0x147458+268*0x130
poke(dynamic+0x24,word(2));poke(dynamic+0x40,word(6))
rows['268:4294967295']={effect(13,0x1000+9),effect(12,0x1000+10),effect(13,0xdead),effect(13,0x1000+9)}
rows['268:9']={effect(13,0x1000+11)}
local function global(index,scope,value,filter,entries)
    local at=globals+index*0x164
    poke(at+0x50,word(#entries));poke(at+0x54,string.char(scope));poke(at+0x58,word(value));poke(at+0x5c,word(filter))
    for i,entry in ipairs(entries)do poke(at+(i-1)*16,string.char(entry[1])..string.rep('\0',3)..word(entry[2]))end
end
global(0,0,268,0,{{0x11,20},{0x10,21},{0x11,0}})
global(1,0,100,0,{{0x11,22}})
global(2,1,6,2,{{0x11,23}})
global(3,1,6,3,{{0x11,24}})
global(4,2,2,0,{{0x11,25}})
global(5,3,0,0,{{0x11,26}})
global(6,4,268,0,{{0x11,27}})
global(31,3,0,2,{{0x11,31}})
assert(table.concat(inputs.campaign(268,4294967295),',')=='9,9,20,23,25,26,31','Campaign order and applicability')
assert(table.concat(inputs.campaign(268,9),',')=='11,20,23,25,26,31','Operation effects use the effect binding')
assert(table.concat(inputs.campaign(300,4294967295),',')=='','Planets beyond the campaign have no global effects')
count=reads;inputs.campaign(268,9);assert(reads==count,'Campaign tags are cached')
global(7,3,0,0,{{0x11,1}});poke(globals+7*0x164+0x50,word(6))
assert(not pcall(make_inputs(read,u,pointer,game,board,effects,config).campaign,268,4294967295),'Entry count is bounded')
poke(globals+7*0x164+0x50,word(1));poke(globals+7*0x164+4,word(40))
assert(not pcall(make_inputs(read,u,pointer,game,board,effects,config).campaign,268,4294967295),'Unknown tag index fails closed')
assert(not pcall(inputs.campaign,512,0))
-- Configuration exclusions are keyed by the native tag hash.
values['3781555287:3964548889:'..(0x1000+4)]=string.rep('\0',24)
assert(inputs.disabled(4) and not inputs.disabled(2) and not pcall(inputs.disabled,32))
-- Duplicate hashes would make campaign decoding ambiguous.
poke(game+0x21e1920+4,word(0x1000))
assert(not pcall(make_inputs,read,u,pointer,game,board,effects,config))
print('Constellation inputs: settings, cap, mission records, effect binding, campaign scopes, exclusions and caches passed')
