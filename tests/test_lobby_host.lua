-- Drive the real snapshot and publication guards with synthetic process
-- memory: alone, hosting a lobby and as its guest. arg[2] is 'lobby' for the
-- dialog build and 'solo' for a build that must keep refusing a lobby.
local ffi=require('ffi')
local lobby=assert(arg[2])=='lobby'
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local up=H.up
CowboyBingusModLoader={api=1,version=18,open_log=function()return {write=function()end,flush=function()end,close=function()end}end}
update=function()return 1,nil,3 end;shutdown=function()return 4,nil,6 end
dofile(arg[1])
local tick=up(update,'tick')
local match=up(up(tick,'advance_prediction_search'),'on_search_match')
local snapshot,ownership=up(match,'snapshot'),up(match,'ownership')
assert((MissionRerollerExperiment.dialog_enabled==true)==lobby,'The build does not match the expected mode')
ffi.cdef[[typedef struct {void *BaseAddress;void *AllocationBase;uint32_t AllocationProtect;
uint16_t PartitionId;uint16_t padding;size_t RegionSize;uint32_t State;uint32_t Protect;
uint32_t Type;uint32_t padding2;} MRE_MEMORY_BASIC_INFORMATION;]]
local base=0x10000000
local board,session,backend,root,screen=0x20000000,0x30000000,0x40000000,0x50000000,0x60000000
local memory={}
local function put(a,s)memory[a]=s end
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function ptr(n)return word(n)..word(0)end
local function player(n)return word(n)..word(0x01100001)end
local function address(a)return tonumber(ffi.cast('uintptr_t',a))end
local api={read=function(a,n)
    local bytes=memory[address(a)]
    assert(bytes and #bytes>=n,string.format('Unexpected synthetic read of %d at %x',n,address(a)))
    return bytes:sub(1,n)
end,pointer=function(bytes,offset)
    offset=offset or 0
    if not bytes or #bytes<offset+8 then return nil end
    local value=ffi.new('uintptr_t[1]');ffi.copy(value,bytes:sub(offset+1,offset+8),8)
    if value[0]<0x10000 then return nil end
    return ffi.cast('uint8_t *',value[0])
end}
local kernel={VirtualQuery=function(a,m)
    m=ffi.cast('MRE_MEMORY_BASIC_INFORMATION *',m) -- The adapter passes a void pointer.
    m[0].BaseAddress=a;m[0].RegionSize=4096;m[0].State=0x1000;m[0].Protect=4
    m[0].Type=address(a)==base+0x3483c38 and 0x1000000 or 0x20000
    return ffi.sizeof(m[0])
end}
H.natives(update,{api=api,ffi=ffi,kernel=kernel,game=ffi.cast('uint8_t *',base)})
-- The board holds no operations here; decoding them is tested elsewhere.
up(snapshot,'core',{inspect_snapshot=function()return {operations={}}end},true)
local code=up(up(ownership,'verify_code'),'offsets').code.campaign_helpers.bytes:gsub('..',function(v)return string.char(tonumber(v,16))end)
-- players: the session's participants. me: the local player. owner: whose
-- board it is. entries: the players the board already lists.
local function scene(players,me,owner,entries)
    memory={}
    put(base+0x347cee8,ptr(board));put(base+0x347cef0,ptr(session));put(base+0x347cee0,ptr(backend))
    put(base+0x3326340,ptr(root));put(base+0x347ce28,ptr(screen));put(base+0x12d5670,code)
    put(screen+0x429c,word(15)..string.rep('\0',16)..word(1))
    put(board+0x17a298,word(268)..word(268)..string.rep('\0',12))
    put(board+0xf9a08,word(268)..word(0));put(board+0xffc0c,word(268))
    put(backend+0x31c48,word(0));put(backend+0x702fc,word(14));put(backend+0x702f8,word(1))
    put(session+0x167e6,'\0');put(root+0x108d,'\0');put(root+0x1099,'\0');put(root+0x8e8,string.rep('\0',8))
    put(session+0x162d8,word(#players));put(session+0x162e0,table.concat(players))
    put(session+0xb398,me);put(board+0x1f8078,owner)
    local rows={};for i,entry in ipairs(entries)do rows[i]=entry..word(0)..word(0)end
    put(board+0x1f80d0,word(#entries));put(board+0x1f8080,table.concat(rows))
    put(board+0x78e84,word(321)..string.rep('\0',92));put(board+0x17a2bc,word(321))
    put(board+0xffc08,word(1));put(board+0xf7280,string.rep('\0',110*92));put(board+0xf9a10,string.rep('\0',76))
    return ffi.cast('uint8_t *',board)
end
local function fails(message,fn,...)
    local ok,err=pcall(fn,...)
    assert(not ok and tostring(err):find(message,1,true),'Expected "'..message..'", got '..tostring(err))
end
local a,b,c,d,e,f=player(1),player(2),player(3),player(4),player(5),player(6)
local none=string.rep('\0',8)
-- Alone, as every earlier build was tested.
local at=scene({a},a,a,{})
local s=assert(snapshot(true));assert(s.sc==1 and s.dc==0 and s.union==1 and s.planet==268 and s.seed==321)
local alone=ownership(at)
scene({a},a,a,{a});s=assert(snapshot(true));assert(s.union==1 and ownership(at)==alone,'A listed player needs no new entry')
scene({a},a,b,{});fails('Not local selection owner',ownership,at)
scene({a},b,b,{});fails('Source is not local owner',ownership,at)
scene({none},none,none,{});fails('invalid source owner',snapshot,true);fails('invalid source owner',ownership,at)
scene({},a,a,{});fails('owner count outside supervised bounds',snapshot,true)
if not lobby then
    scene({a,b},a,a,{})
    fails('owner count outside supervised bounds',snapshot,true)
    fails('Expected one source owner',ownership,at)
    print('Lobby guard: a build without the dialog still refuses a lobby: passed')
    return
end
-- Hosting: two to four players, the local one owning the board.
local guards={[alone]=true}
for n=2,4 do
    local players={a,b,c,d};for i=4,n+1,-1 do players[i]=nil end
    scene(players,a,a,{})
    s=assert(snapshot(true),'A host of '..n..' must get a snapshot');assert(s.sc==n and s.union==n)
    local guard=ownership(at)
    assert(not guards[guard],'A player joining must change the publication guard');guards[guard]=true
end
scene({b,a,c},a,a,{b,a});s=assert(snapshot(true));assert(s.sc==3 and s.dc==2 and s.union==3,'The host need not be listed first')
ownership(at)
scene({a,b,c,d},a,a,{a,b,c,d,e});s=assert(snapshot(true));assert(s.union==5);ownership(at)
-- The fingerprint follows the players, so a search notices one joining.
scene({a,b},a,a,{});local two=assert(snapshot(true)).fingerprint
scene({a,b,c},a,a,{});assert(assert(snapshot(true)).fingerprint~=two)
-- A guest gets a reason instead of a snapshot, and can never publish.
scene({a,b},b,a,{})
local nothing,why=snapshot(true);assert(nothing==nil and why=='Only the host can reroll operations',tostring(why))
fails('Not local selection owner',ownership,at)
scene({a,b},c,c,{});nothing,why=snapshot(true)
assert(nothing==nil and why=='Only the host can reroll operations','A player outside the session is no host')
fails('Source is not local owner',ownership,at)
-- Bounds.
scene({a,b,c,d,e},a,a,{});fails('owner count outside supervised bounds',snapshot,true)
fails('owner count outside supervised bounds',ownership,at)
scene({a,a},a,a,{});fails('invalid source owner',snapshot,true);fails('invalid source owner',ownership,at)
scene({a,none},a,a,{});fails('invalid source owner',snapshot,true)
scene({a,b,c,d},a,a,{e,f});fails('owner union overflow',snapshot,true)
fails('Owner queue has no capacity',ownership,at)
scene({a,b},a,a,{a,a});fails('invalid destination owner',snapshot,true);fails('Invalid owner entries',ownership,at)
print('Lobby guard: alone, host of two to four, guest, outsider, joining player and queue bounds: passed')
