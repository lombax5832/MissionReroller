-- Drive the real snapshot and publication guards with synthetic process
-- memory: alone, hosting a lobby and as its guest. arg[2] is 'lobby' for the
-- dialog build and 'solo' for a build that must keep refusing a lobby.
local ffi=require('ffi')
local lobby=assert(arg[2])=='lobby'
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local up=H.up
-- The offsets the entry was built with (src/offsets.lua).
local O=H.offsets((arg[0]:match('^(.*[/\\])') or '')..'../src')
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
-- protect: the protection VirtualQuery reports for an address, else 4.
local protect={}
local kernel={VirtualQuery=function(a,m)
    m=ffi.cast('MRE_MEMORY_BASIC_INFORMATION *',m) -- The adapter passes a void pointer.
    m[0].BaseAddress=a;m[0].RegionSize=4096;m[0].State=0x1000;m[0].Protect=protect[address(a)] or 4
    m[0].Type=address(a)==base+O.rva.rng_state and 0x1000000 or 0x20000
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
    put(base+O.rva.board,ptr(board));put(base+O.rva.session,ptr(session));put(base+O.rva.backend,ptr(backend))
    put(base+O.rva.ui_root,ptr(root));put(base+O.rva.screen_owner,ptr(screen));put(base+O.rva.campaign_helpers,code)
    put(screen+O.screen_owner.stack,word(15)..string.rep('\0',16)..word(1))
    put(board+O.board.selection,word(268)..word(268)..string.rep('\0',12))
    put(board+O.board.operation_cache,word(268)..word(0));put(board+O.board.mission_cache,word(268))
    put(backend+O.backend.pending_requests,word(0));put(backend+O.backend.state,word(14));put(backend+O.backend.available,word(1))
    put(session+O.session.gate,'\0');put(root+O.ui_root.loading_gate,'\0');put(root+O.ui_root.transition_gate,'\0');put(root+O.ui_root.transition,string.rep('\0',8))
    put(session+O.session.player_count,word(#players));put(session+O.session.players,table.concat(players))
    put(session+O.session.local_player,me);put(board+O.board.selection_owner,owner)
    local rows={};for i,entry in ipairs(entries)do rows[i]=entry..word(0)..word(0)end
    put(board+O.board.owner_count,word(#entries));put(board+O.board.owners,table.concat(rows))
    put(board+O.board.seed,word(321)..string.rep('\0',92));put(board+O.board.published_seed,word(321))
    put(board+O.board.mission_count,word(1));put(board+O.board.operations,string.rep('\0',110*92));put(board+O.board.missions,string.rep('\0',76))
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
-- Wine (Proton) can report the module's RNG data page as copy-on-write; it
-- is only read. Other protections fail, naming the page and its values,
-- and a private page reported as copy-on-write still fails.
scene({a},a,a,{})
protect[base+O.rva.rng_state]=8;assert(snapshot(true),'A copy-on-write module data page passes')
protect[base+O.rva.rng_state]=0x40;fails('rng_state state=0x1000 protect=0x40 type=0x1000000',snapshot,true)
protect[base+O.rva.rng_state]=nil
protect[board+O.board.seed]=8;fails('board.seed state=0x1000 protect=0x8 type=0x20000',snapshot,true)
protect[board+O.board.seed]=nil;assert(snapshot(true))
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
