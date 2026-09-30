-- The MODS tab binding: registration with a stubbed Mod Bindings Menu, the
-- per-frame activation, and naming the bound key from a simulated binding map.
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local B=H.module(assert(arg[1]))
local function le(n,size)local out={};for i=1,size do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
-- Simulated memory: segments of bytes at numeric addresses.
local segments={}
local function place(address,bytes)segments[#segments+1]={address,bytes}end
local failing=false
local function read(a,n)
    assert(not failing,'memory read failed')
    for _,seg in ipairs(segments)do
        if a>=seg[1] and a+n<=seg[1]+#seg[2] then return seg[2]:sub(a-seg[1]+1,a-seg[1]+n)end
    end
    error('unmapped read at '..a)
end
local function u(b,o)local a,c,d,e=b:byte(o+1,o+4);assert(e,'short read');return a+c*256+d*65536+e*16777216 end
local function pointer(a)local b=read(a,8);local lo,hi=u(b,0),u(b,4);assert(lo+hi*4294967296>0,'missing pointer');return lo+hi*4294967296 end
local game,owner,buckets=0x100000000,0x200000,0x300000
place(game+B.INPUT_OWNER,le(owner,8))
place(owner+B.BINDING_MAP,le(buckets,8)..le(256,4))
local code=10*65536+3
local function mapping(device,index)return string.char(device+16*B.BUTTON)..'\255\144\0'..le(index,2)..string.rep('\0',14)end
local function bind(mappings,at)
    local map={}
    for i=0,255 do map[i+1]=le(i==(at or 7) and code or 12*65536+i,4)..le(0,4)..string.rep('\0',320)end
    local record=le(code,4)..le(#mappings,4)..table.concat(mappings)
    map[(at or 7)+1]=record..string.rep('\0',328-#record)
    segments[3]={buckets,table.concat(map)}
end
bind({mapping(B.KEYBOARD,B.KEYBOARD_BASE+0x77),mapping(2,16)})

-- The menu keeps its records in a state upvalue of register_binding, as v2.0 does.
local state={registry={}}
local calls,refuse,down_value,raise={},false,nil,false
local menu={api=1,version=2,capacity=36}
function menu.register_binding(id,label,slot,options)
    calls[#calls+1]={id=id,label=label,slot=slot,options=options}
    if refuse then return false,'all 36 binding actions in use' end
    state.registry[id]={id=id,label=label,group=10,action=3,code=code}
    return true
end
function menu.is_down(id)assert(id==B.ID);if raise then error('input owner moved')end;return down_value end
local present=false
local logs={}
local names={[0x77]='f8',[0x09]='tab'}
local keyboard={button_name=function(vk)return names[vk]end}
local function make()
    return B.new({read=read,pointer=pointer,u=u,game=game,emit=function(s)logs[#logs+1]=s end,keyboard=keyboard,
        menu=function()return present and menu or nil end})
end
local b=make()
assert(b:step()==false and b.status=='absent' and select(2,b:keys())=='unknown' and #calls==0,'nothing without the menu')
present=true
assert(b:step()==false and b.status=='registered' and #calls==1,'registers on the first frame the menu is present')
assert(calls[1].id==B.ID and calls[1].label=='Reroll operations' and calls[1].slot==0 and calls[1].options.category=='Mission Reroller')
assert(logs[1]=='BINDING_REGISTERED '..B.ID..' action 10:3',logs[1])
assert(not b.ready and select(2,b:keys())=='unknown','native input not ready: no key yet')
down_value=false
assert(b:step()==false and b.ready and b:keys()=='f8' and select(2,b:keys())=='bound','the bound keyboard key is named')
down_value=true
assert(b:step()==true,'the binding activates')
down_value=false;assert(b:step()==false)
assert(#calls==1,'registered once')
print('Registration and activation OK')

-- The key follows the live binding map.
bind({mapping(2,16),mapping(B.MOUSE,32)});assert(b:keys()=='MOUSE 1','a mouse button')
bind({mapping(1,0)});assert(b:keys()=='CONTROLLER' and select(2,b:keys())=='bound','controller only')
bind({});assert(b:keys()==nil and select(2,b:keys())=='unbound','unbound')
bind({mapping(B.KEYBOARD,B.KEYBOARD_BASE+200)});assert(b:keys()=='KEY 200','an unnamed key shows its code')
bind({mapping(B.KEYBOARD,B.KEYBOARD_BASE+0x09),mapping(B.KEYBOARD,B.KEYBOARD_BASE+0x77)});assert(b:keys()=='tab / f8','every keyboard key')
bind({mapping(B.KEYBOARD,B.KEYBOARD_BASE+0x77)},200);assert(b:keys()=='f8','a moved bucket is found again')
failing=true;assert(b:keys()==nil and select(2,b:keys())=='unknown','a failed read names nothing');failing=false
assert(b:keys()=='f8','and recovers')
place(owner+B.BINDING_MAP,le(buckets,8)..le(128,4));segments[2]=segments[#segments];segments[#segments]=nil
bind({mapping(B.KEYBOARD,B.KEYBOARD_BASE+0x77)},3)
assert(b:keys()==nil and select(2,b:keys())=='unknown','an unexpected map capacity names nothing')
place(owner+B.BINDING_MAP,le(buckets,8)..le(256,4));segments[2]=segments[#segments];segments[#segments]=nil
assert(b:keys()=='f8')
print('Key names OK')

-- Failures: a refused registration is logged once and never retried; an
-- is_down error disables the binding; without debug the key is unknown.
calls,logs,state.registry={},{},{}
refuse=true;local c=make()
assert(c:step()==false and c.status=='failed' and #calls==1 and logs[1]:find('BINDING_FAILED',1,true) and logs[1]:find('36',1,true))
assert(c:step()==false and #calls==1 and #logs==1,'not retried')
refuse=false
local d=make();down_value=true;assert(d:step()==true)
raise=true;assert(d:step()==false and d.status=='failed' and logs[#logs]:find('input owner moved',1,true));raise=false
assert(d:step()==false,'stays off')
local saved=debug;debug=nil
local e=make();assert(e:step()==true and e.status=='registered' and logs[#logs]:find('action unknown',1,true))
down_value=false;assert(e:step()==false and e.ready and select(2,e:keys())=='unknown','without the record the key is unknown')
debug=saved
-- Version 1 menus have no automatic slots: the third-party slot is requested.
calls={};menu.version=nil
local f=make();assert(f:step()==false and calls[1].slot==2)
menu.version=2
-- A menu with another API is ignored.
menu.api=2;local g=make();assert(g:step()==false and g.status=='absent');menu.api=1
print('test_mod_binding: registration, activation, key names and failures passed')
