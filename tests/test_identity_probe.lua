local function up(fn,key,value,set)
    for i=1,100 do
        local k,v=debug.getupvalue(fn,i)
        if not k then break end
        if k==key then if set then debug.setupvalue(fn,i,value)end;return v end
    end
    error('Missing upvalue '..key)
end
local function word(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)
end
local function u(s,o)
    local a,b,c,d=s:byte(o+1,o+4);assert(d)
    return a+b*256+c*65536+d*16777216
end
local function replace(s,offset,bytes)return s:sub(1,offset)..bytes..s:sub(offset+#bytes+1)end
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local make_probe=H.module(arg[2])
local O=H.offsets(arg[2]:match('^(.*)[/\\]'))
local row=string.rep('\0',92)
row=replace(row,12,word(123));row=replace(row,16,string.char(12,1))
row=replace(row,24,string.char(6));row=replace(row,32,string.char(1));row=replace(row,52,string.char(1))
local operations=row..string.rep('\0',109*92)
local b=1000;local definitions=b+O.board.definitions[2];local changed=false
local capture_probe=make_probe(function(address,size)
    local bytes
    if address==b+O.board.campaign+0x1c+268*O.campaign.definition_stride or address==definitions then bytes=word(9)
    elseif address==b+O.board.definitions[1] then bytes=word(8)
    elseif address==definitions+O.definitions.pool_count then bytes=word(changed and 34 or 35)
    elseif address==b+O.board.active_snapshot then bytes=row
    else error('Unexpected read')end
    assert(#bytes==size);return bytes
end,u,function(input,seed)
    assert(input.planet==268 and input.pool_count==35 and input.active.seed==123 and input.active.id==6)
    assert(input.active.planet==268 and seed==9)
    return {[0]={id=6,seed=123,difficulty=1}}
end)
local snapshot={board=b,planet=268,seed=9,operations=operations,fingerprint='frame'}
local captured=capture_probe:capture(snapshot)
assert(capture_probe:compare(captured).passed)
changed=true;assert(capture_probe:capture(snapshot).fingerprint~=captured.fingerprint);changed=false
captured.operations=replace(operations,12,word(124))
local mismatch=capture_probe:compare(captured)
assert(not mismatch.passed and #mismatch.errors==1 and mismatch.errors[1]:find('124',1,true))
captured.operations=operations:sub(1,-2);assert(not pcall(function()capture_probe:compare(captured)end))
captured.operations=replace(operations,92,row)
assert(not capture_probe:compare(captured).passed,'Extra live operation must fail')
captured.operations=string.rep('\0',110*92)
assert(not capture_probe:compare(captured).passed,'Absent predicted operation must fail')

-- Pointer display text is not an address: the game renders every cdata value
-- as the same string. Exercise the real capture cache without private fixtures.
do
    local ffi=require('ffi')
    local board=ffi.cast('uint8_t*',0x20000000000)
    local defs=board+O.board.definitions[1]
    local function numeric(a)return tonumber(ffi.cast('uintptr_t',a))end
    local reads={}
    local function read(a,size)
        local n=numeric(a);local key=n..':'..size;reads[key]=(reads[key] or 0)+1
        if n==numeric(board+O.board.campaign+0x1c) or n==numeric(defs) then return word(9)end
        if n==numeric(board+O.board.active_snapshot) then return string.rep('\0',92)end
        if n==numeric(defs+O.definitions.pool_count) then return word(35):sub(1,size)end
        if n==numeric(defs+O.definitions.pool_start) then return word(407)end
        if n==numeric(defs+O.definitions.node_count) then return word(512)end
        error('Unexpected opaque-pointer read')
    end
    local probe=make_probe(read,u,function()end,nil,function(cached)
        return function(d)
            assert(u(cached(d+O.definitions.pool_count,4),0)==35)
            assert(u(cached(d+O.definitions.pool_start,4),0)==407,'Distinct pointer reads must not alias')
            assert(u(cached(d+O.definitions.node_count,4),0)==512)
            assert(cached(d+O.definitions.pool_count,2)==word(35):sub(1,2),'Read size is part of cache identity')
            local rebuilt=ffi.cast('uint8_t*',numeric(d)+O.definitions.pool_start)
            assert(u(cached(rebuilt,4),0)==407)
            return {1},false,'graph'
        end
    end)
    local original=tostring
    _G.tostring=function(v)return type(v)=='cdata' and '[cdata (deleted)]' or original(v)end
    local ok,result=pcall(probe.capture,probe,{board=board,planet=0,seed=9,operations=operations,
        fingerprint='frame',decoded={operations={{row=0,operation_id=6}}}})
    _G.tostring=original
    assert(ok,result)
    assert(reads[numeric(defs+O.definitions.pool_start)..':4']==1,'Equivalent pointer values must reuse the cached read')
    assert(not result.fingerprint:find('[cdata (deleted)]',1,true))
end

local logs,closed={},false
CowboyBingusModLoader={api=1,version=16,open_log=function()
    return {write=function(_,s)logs[#logs+1]=s end,flush=function()end,close=function()closed=true end}
end}
update=function()return 'original',nil,7 end
shutdown=function()return 'shutdown',nil,8 end
dofile(arg[1]);local installed=update;dofile(arg[1]);assert(update==installed)
assert(MissionRerollerExperiment.read_only)
local tick=up(update,'tick')
-- Reproduce the live cross-planet timeout through the actual adapter guard.
-- The ship remains on 268 while the viewed planet and both caches are 100.
local real_snapshot=up(tick,'snapshot')
local dirty,cache_planet=false,100
up(real_snapshot,'game',0,true)
up(real_snapshot,'pointer',function(address)return address end,true)
up(real_snapshot,'read',function(address,size)
    if address==O.rva.screen_owner+O.screen_owner.stack then return word(15)..string.rep('\0',16)..word(1)end
    if address==O.rva.board+O.board.selection then return word(268)..word(100)..word(4294967295)..word(4294967295)..word(0)end
    if address==O.rva.board+O.board.operation_cache then return word(cache_planet)..word(dirty and 1 or 0)end
    if address==O.rva.board+O.board.mission_cache then return word(cache_planet)end
    if address==O.rva.backend+O.backend.pending_requests then error('past_preview_cache_guard')end
    error('Unexpected cache-guard read')
end,true)
local ok,why=pcall(real_snapshot,true)
assert(not ok and tostring(why):find('past_preview_cache_guard',1,true),'Viewed planet 100 must pass the cache guard even while the ship remains on 268')
local value,reason=real_snapshot();assert(value==nil and reason=='waiting for caches','Publication adapter must retain its existing planet guard')
dirty=true;value,reason=real_snapshot(true);assert(value==nil and reason=='waiting for caches')
dirty=false;cache_planet=101;value,reason=real_snapshot(true);assert(value==nil and reason=='waiting for caches')
-- Continue through the real decoder, keeping the raw ship/view selection intact.
-- With game at 0 and pointers read as themselves, each global points at its own RVA.
local board,session,backend,root,screen=O.rva.board,O.rva.session,O.rva.backend,O.rva.ui_root,O.rva.screen_owner
local memory={}
local raw_selection=word(268)..word(100)..word(4294967295)..word(4294967295)..word(0)
memory[screen+O.screen_owner.stack]=word(15)..string.rep('\0',16)..word(1)
memory[board+O.board.selection]=raw_selection
memory[board+O.board.operation_cache]=word(100)..word(0);memory[board+O.board.mission_cache]=word(100)
memory[backend+O.backend.pending_requests]=word(0);memory[backend+O.backend.state]=word(14);memory[backend+O.backend.available]=word(1)
memory[session+O.session.gate]='\0';memory[root+O.ui_root.loading_gate]='\0';memory[root+O.ui_root.transition_gate]='\0';memory[root+O.ui_root.transition]=string.rep('\0',8)
memory[session+O.session.player_count]=word(1);memory[session+O.session.players]=word(1)..word(0)
memory[board+O.board.owner_count]=word(0);memory[board+O.board.owners]=''
memory[board+O.board.seed]=word(9)..row;memory[board+O.board.published_seed]=word(9)
local viewed_row=replace(row,16,string.char(100,0))
viewed_row=replace(viewed_row,84,string.char(1));viewed_row=replace(viewed_row,88,string.char(1))
memory[board+O.board.operations]=viewed_row..string.rep('\0',109*92)
memory[board+O.board.mission_count]=word(1);memory[board+O.board.missions]=replace(string.rep('\0',76),60,word(1))
up(real_snapshot,'page',function()end,true)
up(real_snapshot,'read',function(address,size)
    local bytes=assert(memory[address],'Missing synthetic snapshot field');assert(#bytes==size);return bytes
end,true)
local viewed=assert(real_snapshot(true))
assert(viewed.planet==100 and viewed.decoded.planet_index==100 and #viewed.decoded.operations==1)
assert(viewed.selection==raw_selection and viewed.fingerprint:find(raw_selection,1,true))
MissionRerollerExperiment.read_only=false
assert(not pcall(real_snapshot,true),'Preview mode must never be enabled for a writing adapter')
MissionRerollerExperiment.read_only=true
local prepare=up(tick,'prepare')
-- The adapter checks every code entry and anchor instruction of
-- src/offsets.lua on the first frame: bytes, or SHA-256 for the generator
-- functions.
local verify_offsets=up(up(prepare,'initialize'),'verify_offsets')
local verify_code=up(verify_offsets,'verify_code')
local offsets=up(verify_code,'offsets')
local EXE=0x40000000
local function base(entry)return entry.module=='exe' and EXE or 0 end
local function raw(s)return(s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local bad_signature=true
up(verify_code,'bases',{game=0,exe=EXE},true)
up(verify_code,'read',function(address,size)
    for _,entry in pairs(offsets.code)do
        if address==base(entry)+entry.rva then
            if entry.bytes then assert(size==#entry.bytes/2);return raw(entry.bytes)end
            assert(size==entry.size);return entry.sha256
        end
    end
    for _,entry in pairs(offsets.globals)do
        if entry.anchor and address==base(entry)+entry.anchor.rva then return raw(entry.anchor.bytes)end
    end
    for _,fields in pairs(offsets.structs)do
        for _,entry in pairs(fields)do
            local anchor=entry.anchor
            if type(anchor)=='table' and address==base(anchor)+anchor.rva then return raw(anchor.bytes)end
        end
    end
    error('Unexpected signature address')
end,true)
up(verify_code,'sha256',function(bytes)return bad_signature and 'mismatch' or bytes end,true)
assert(not pcall(verify_offsets),'Changed generator signature must block initialization')
bad_signature=false
local code_entries,anchors=verify_offsets()
local expected_code,expected_anchors=0,0
for _ in pairs(offsets.code)do expected_code=expected_code+1 end
for _,entry in pairs(offsets.globals)do if entry.anchor then expected_anchors=expected_anchors+1 end end
for _,fields in pairs(offsets.structs)do
    for _,entry in pairs(fields)do if type(entry.anchor)=='table' then expected_anchors=expected_anchors+1 end end
end
assert(code_entries==expected_code and anchors==expected_anchors and anchors>0)
up(prepare,'initialize',function()end,true)
up(prepare,'api',{pointer=function()error('Unexpected pointer read during initialization')end},true)
up(prepare,'game',0,true)
prepare()
assert(MissionRerollerExperiment.status=='ready_read_only')
local ffi=require('ffi')
local now,focused,down,ready,calls=0,true,false,true,0
local changing=false
local level_ok=true
local composition
local capture_attempts,fail_capture=0,nil
local collect_invalid=H.module((arg[2]:gsub('identity_probe.lua$','level_inputs.lua')))(function(address,size)
    if address==O.rva.categories+9 then return '\0'end
    if address==O.definitions.pool_count then return word(1)end
    if address==O.definitions.pool_start then return word(0)end
    if address==O.definitions.level_roots or address==O.definitions.node_count then return word(12)end
    error('Unexpected invalid-root read')
end,u,0)
local fake_probe={
    capture=function(_,s)
        capture_attempts=capture_attempts+1
        if fail_capture=='always' or fail_capture==capture_attempts then collect_invalid(0,{id=0,category=0})end
        return {fingerprint=changing and tostring(now)..tostring(calls) or 'stable',input={pool_count=35},level_graphs={},composition=composition}
    end,
    compare=function()calls=calls+1;return {passed=true,matched=30,observed=30,predicted=30,errors={}}end,
    compare_levels=function()return {passed=level_ok,checked=72,category_draws=3,errors=level_ok and {} or {'synthetic level mismatch'}}end,
}
up(tick,'probe',fake_probe,true)
up(tick,'api',{time=function()return now end},true)
up(tick,'ffi',ffi,true)
up(tick,'kernel',{GetCurrentProcessId=function()return 42 end},true)
up(tick,'user32',{
    GetForegroundWindow=function()return 1 end,
    GetWindowThreadProcessId=function(_,pid)pid[0]=focused and 42 or 100 end,
    GetAsyncKeyState=function()return down and -1 or 0 end,
},true)
up(tick,'snapshot',function()return ready and snapshot or nil,'open galactic map'end,true)
local function frame()now=now+0.5;local a,b,c=update();assert(a=='original' and b==nil and c==7)end
frame();down=true;frame();focused=false
for _=1,5 do frame()end
assert(calls==1 and MissionRerollerExperiment.status=='identity_and_level_tests_passed','Must finish while alt-tabbed')
for _=1,5 do frame()end;assert(calls==1,'One check per shortcut')
focused=true;down=false;frame();down=true;ready=false;frame()
for _=1,62 do frame()end
assert(MissionRerollerExperiment.status=='capture_timeout' and calls==1)
ready=true;down=false;frame();down=true;frame()
changing=true
for _=1,8 do frame()end
assert(calls==1,'Changing inputs must not pass stability gate')
changing=false
level_ok=false
for _=1,5 do frame()end
assert(calls==2,'Timeout and changed data must allow retry')
assert(MissionRerollerExperiment.status=='level_test_mismatch','Identity pass must not hide level failure')
-- A rejected graph must discard the capture without permanently killing the probe.
level_ok=true;down=false;frame();down=true
fail_capture=capture_attempts+2;frame() -- reject the second capture of this poll
assert(MissionRerollerExperiment.status=='capture_retry','Invalid graph must be retryable')
assert(calls==2,'Rejected capture must never be compared')
fail_capture=nil
for _=1,3 do frame()end
assert(calls==2,'Recovery still requires four new stable polls')
frame();assert(calls==3 and MissionRerollerExperiment.status=='identity_and_level_tests_passed')
down=false;frame();down=true;fail_capture='always';frame()
for _=1,62 do frame()end
assert(calls==3 and MissionRerollerExperiment.status=='capture_timeout','Persistent invalid graphs must time out, never pass')
local joined=table.concat(logs)
assert(joined:find('LUA_CAPTURE_RETRY',1,true) and joined:find('root=12 nodes=12',1,true),'Retain exact failed bounds in diagnostic log')
fail_capture=nil;down=false;frame();down=true;frame()
for _=1,4 do frame()end
assert(calls==4,'A failed capture session must allow a later shortcut retry')
for _,passed in ipairs({true,false})do
    composition={passed=passed,operations=30,templates=30,modifiers=30,checked=72,independent_bases=true,bases=30,errors=passed and {} or {'synthetic composition mismatch'}}
    down=false;frame();down=true;frame()
    for _=1,5 do frame()end
    assert(MissionRerollerExperiment.status==(passed and 'composition_test_passed' or 'composition_test_mismatch'))
end
assert(table.concat(logs):find('LUA_COMPOSITION_PASS',1,true) and table.concat(logs):find('LUA_COMPOSITION_MISMATCH',1,true))
assert(table.concat(logs):find('LUA_SEED_PREDICTION_PASS',1,true) and table.concat(logs):find('LUA_SEED_PREDICTION_MISMATCH',1,true))
composition.passed=true;composition.errors={};level_ok=false
down=false;frame();down=true;frame();for _=1,5 do frame()end
assert(MissionRerollerExperiment.status=='level_test_mismatch','Composition pass must not hide a separate level failure')
-- Capture reads yield once the frame's slice is used, so one poll spans
-- several frames instead of stalling one. Reads outside a poll never yield.
local sliced=up(prepare,'sliced_read')
local clock,reads,frame_reads,most=0,0,0,0
up(sliced,'slice_clock',function()return clock end,true)
up(sliced,'read',function()reads=reads+1;frame_reads=frame_reads+1;clock=clock+0.01;return 'x' end,true)
assert(sliced(0,1)=='x' and reads==1,'A read outside a poll must not yield')
local plain=fake_probe.capture
fake_probe.capture=function(...)for _=1,5 do sliced(0,1)end;return plain(...)end
level_ok=true;reads=0
local before=calls;down=false;frame();down=true
local frames=0
repeat frame_reads=0;frame();frames=frames+1;most=math.max(most,frame_reads)until calls>before or frames>60
assert(calls==before+1 and MissionRerollerExperiment.status=='composition_test_passed','A sliced capture must still pass')
-- Without a search stage the run ends at its last checkpoint.
local session=up(tick,'reroll_session')
local view=session.view();assert(not view.running and view.outcome=='composition_test_passed',view.phase)
assert(reads==4*2*5 and most<=2 and frames>=20,string.format('Polls must spread over frames: reads=%d most=%d frames=%d',reads,most,frames))
-- A new request mid-poll discards the poll in flight.
down=false;frame();down=true;frame();assert(reads>40 and calls==before+1)
down=false;frame();down=true;frame()
for _=1,40 do frame()end
assert(calls==before+2,'Only the restarted request may complete')
fake_probe.capture=plain
up(update,'tick',function()error('synthetic failure')end,true)
jit.flush() -- debug.setupvalue changes test wiring after the long retry loop.
frame();assert(MissionRerollerExperiment.status:find('synthetic failure',1,true),MissionRerollerExperiment.status)
assert(session.view().outcome=='stopped' and not table.concat(logs):find('SESSION_',1,true),'Every phase change follows the session rules')
local a,c,d=shutdown();assert(a=='shutdown' and c==nil and d==8 and closed)
print('Lua probe: cache capture, mismatches, stable inputs, repeat, timeout, background progress, duplicate guard and wrapper returns passed')
