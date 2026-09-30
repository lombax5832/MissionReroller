-- Taking Escape out of a simulated binding map while the dialog is open,
-- and putting back only the buckets nobody else changed in between.
local E=dofile(assert(arg[1]))
local function le(n,size)local out={};for i=1,size do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
local function u(b,o)local a,c,d,e=b:byte(o+1,o+4);assert(e,'short read');return a+c*256+d*65536+e*16777216 end
local function mapping(device,kind,index,tail)return string.char(kind*16+device)..'\0\0\0'..le(index,2)..string.rep(tail or '\0',14)end
local function bucket(code,list,spare)
    local body=table.concat(list)..string.rep(spare or '\0',(16-#list)*20)
    return le(code,4)..le(#list,4)..body
end
local BASE=0x10000
-- The map as one byte string; bucket i lives at BASE+i*328.
local memory={}
local function reset()
    for i=0,255 do memory[i]=bucket(0,{})end
    -- Debugmenu Open: Escape and Right on the keyboard.
    memory[3]=bucket(7*65536+2,{mapping(3,4,76,'a'),mapping(3,4,88,'b')},'z')
    -- A menu back action: controller Circle, Escape, and a mouse button.
    memory[40]=bucket(1*65536+9,{mapping(1,4,1),mapping(3,4,76),mapping(4,4,33)})
    -- Escape as an axis and on another device is not a keyboard Escape button.
    memory[41]=bucket(1*65536+10,{mapping(3,2,76),mapping(4,4,76)})
end
local writes={}
local env={u=u,buckets=function()return BASE end}
function env.read(a,n)
    if a==BASE then local all={};for i=0,255 do all[#all+1]=memory[i]end;return table.concat(all):sub(1,n)end
    local i=(a-BASE)/328;assert(i%1==0 and n==328,'Unexpected read');return memory[i]
end
function env.write(a,bytes)
    local i=math.floor((a-BASE)/328);local at=a-BASE-i*328
    assert(at==4 and #bytes==324,'Only a bucket after its action code is written')
    writes[#writes+1]=i
    memory[i]=memory[i]:sub(1,4)..bytes
end

reset()
local original={};for i=0,255 do original[i]=memory[i]end
local gate=E.new(env)
assert(gate:hold()==2 and gate.held and gate.actions=='7:2,1:9','Both keyboard Escape mappings removed')
assert(#writes==2,'Only the changed buckets are written')
assert(u(memory[3],4)==1 and memory[3]:sub(9,28)==mapping(3,4,88,'b'),'Right stays, moved into the first slot')
assert(memory[3]:sub(29,48)==string.rep('\0',20)and memory[3]:sub(49)==original[3]:sub(49),'Freed slot zeroed, spare slots untouched')
assert(u(memory[40],4)==2 and memory[40]:sub(9,28)==mapping(1,4,1)and memory[40]:sub(29,48)==mapping(4,4,33),'Controller and mouse keep their order')
assert(memory[41]==original[41],'An axis or another device is not Escape')
assert(not pcall(gate.hold,gate),'Holding twice is refused')
local restored,skipped=gate:release()
assert(restored==2 and skipped==0 and not gate.held,'Both buckets put back')
for i=0,255 do assert(memory[i]==original[i],'Map restored exactly')end
assert(gate:release()==0,'Releasing again does nothing')

-- A bucket rebound in between is left as the other writer made it.
writes={}
assert(gate:hold()==2)
memory[40]=bucket(1*65536+9,{mapping(3,4,77)})
local rebound=memory[40]
restored,skipped=gate:release()
assert(restored==1 and skipped==1 and memory[40]==rebound and memory[3]==original[3],'Only unchanged buckets are restored')

-- No Escape anywhere: nothing is written, and release has nothing to do.
for i=0,255 do memory[i]=bucket(0,{})end
writes={}
assert(gate:hold()==0 and gate.actions==''and #writes==0)
assert(gate:release()==0)

-- A write that fails partway leaves the gate held with what was written,
-- so release puts it back.
reset();writes={}
local real=env.write;local calls=0
env.write=function(a,bytes)calls=calls+1;if calls==2 then error('write refused')end;return real(a,bytes)end
assert(not pcall(gate.hold,gate)and gate.held,'A failed hold stays held for release')
env.write=real
restored=gate:release()
assert(restored==1)
for i=0,255 do assert(memory[i]==original[i],'Partial hold undone')end

-- An unreadable count raises before anything is written.
memory[3]=le(1,4)..le(17,4)..string.rep('\0',320);writes={}
local fresh=E.new(env)
assert(not pcall(fresh.hold,fresh)and #writes==0 and not fresh.held,'A bad bucket writes nothing')
print('Escape gate: removal, exact restore, changed buckets kept, partial failure and bad map passed')
