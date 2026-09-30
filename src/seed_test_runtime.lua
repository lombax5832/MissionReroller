-- Supervised publication experiment; deliberately separate from normal search.
local original_update,original_shutdown=rawget(_G,'update'),rawget(_G,'shutdown')
local transaction,selector,thread,previous,stable,last_poll=nil,nil,nil,nil,0,-math.huge
local stopped,armed,key_down=false,false,true
local ui_selection
local function word(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)
end
local function rawhex(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local function ownership(b)
    assert(pointer(game+0x347cee8)==b,'Board changed')
    local session=pointer(game+0x347cef0)
    assert(u(read(session+0x162d8,4),0)==1,'Expected one source owner')
    local source=read(session+0x162e0,8)
    local local_owner=read(session+0xb398,8)
    assert(source==local_owner and source~=string.rep('\0',8),'Source is not local owner')
    assert(read(b+0x1f8078,8)==source,'Not local selection owner')
    local count=u(read(b+0x1f80d0,4),0)
    assert(count<=5,'Invalid owner count')
    local entries=count>0 and read(b+0x1f8080,count*16) or '';local found=false;local ids={}
    for i=0,count-1 do
        local id=entries:sub(i*16+1,i*16+8)
        assert(id~=string.rep('\0',8) and not ids[id],'Invalid owner entries');ids[id]=true
        if id==source then found=true end
    end
    local capacity=count+(found and 0 or 1)
    assert(capacity<=5,'Owner queue has no capacity for local source')
    page(b+0x78e84,4,0x20000);page(b+0x1f8080,capacity*16,0x20000)
    page(b+0x1f80d0,4,0x20000)
    assert(hex(read(game+0x12d5670,#expected_code/2))==expected_code,'Publication signature changed')
    return tostring(session)..hex(source)
end
local function write_seed(b,seed)
    page(b+0x78e84,4,0x20000)
    local bytes=word(seed);local written=ffi.new('size_t[1]')
    assert(kernel.WriteProcessMemory(kernel.GetCurrentProcess(),b+0x78e84,bytes,4,written)~=0
        and written[0]==4,'Seed write failed')
    assert(read(b+0x78e84,4)==bytes,'Seed write did not persist')
end
local function notify(b)
    ffi.cast('void (*)(void *, uint32_t)',game+0x12d57e0)(b,2)
end
local function records_hash(s)
    local rows={}
    for i=0,109 do
        local row=s.operations:sub(i*92+1,(i+1)*92)
        if row:byte(53)~=0 then rows[#rows+1]=word(i)..row end
    end
    return sha256(table.concat(rows)),sha256(s.missions)
end
local function prepare()
    initialize()
    ffi.cdef[[int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);]]
    transaction=make_publication({
        preflight=function(s,e)
            assert(s.planet==e.planet,'Select the test planet')
            assert(s.seed~=e.seed,'Candidate is already installed')
            assert(sha256(rawhex(s.active))==e.active_hash,'Active operation differs from prediction context')
            assert(s.seed==e.baseline_seed,'Prediction belongs to a different live seed; refresh candidate file')
            local op,missions=records_hash(s)
            assert(op==e.baseline_operation_hash and missions==e.baseline_mission_hash,'Live board differs from prediction baseline')
            s.owner_guard=ownership(s.board)
            local final=assert(snapshot(),'Context unavailable')
            assert(final.fingerprint==s.fingerprint,'Context changed before publication')
        end,
        publish=function(s,seed)
            assert(ownership(s.board)==s.owner_guard,'Owner changed')
            emit('PUBLISH_BEGIN previous_seed='..s.seed..' candidate_seed='..seed)
            write_seed(s.board,seed);notify(s.board)
            assert(hex(read(s.board+0x78e88,92))==s.active,'Active operation changed')
            emit('PUBLISH_RETURN active_preserved=true')
        end,
        restore=function(s,seed)
            assert(ownership(s.board)==s.owner_guard,'Restore owner changed; refusing stale write')
            assert(hex(read(s.board+0x78e88,92))==s.active,'Restore active operation changed')
            local current=u(read(s.board+0x78e84,4),0)
            assert(current==seed or current==s.seed,'External seed change; refusing overwrite')
            write_seed(s.board,s.seed);notify(s.board)
            emit('RESTORE_SEED previous_seed='..s.seed..' refresh_requested=true')
        end,
        matches=function(s,e)
            local op,missions=records_hash(s)
            emit('PREDICTION_CHECK seed='..s.seed..' operation_sha256='..op..' mission_sha256='..missions)
            return op==e.operation_hash and missions==e.mission_hash
        end,
    },candidate)
    emit('Seed publication test ready; candidate_file='..candidate_path..'; Ctrl+Shift+F9 reads it, alone on ship')
end
local function select_match(s)
    for _,sig in ipairs(selection_signatures)do
        assert(hex(read(game+sig[1],#sig[2]/2))==sig[2],'Selection signature changed')
    end
    local final=assert(snapshot(),'Selection context unavailable')
    assert(final.fingerprint==s.fingerprint,'State changed before selection')
    ownership(s.board)
    assert(read(s.board+0x78e60,8)==s.selection:sub(1,8),'Selection context not published')
    page(s.board+0x78e60,36,0x20000);page(s.board+0x17a298,36,0x20000)
    local op
    for _,value in ipairs(s.decoded.operations)do if value.row==candidate.row then op=value end end
    assert(op and op.seed==candidate.operation_seed and op.difficulty==candidate.difficulty,'Predicted operation missing')
    ui_selection=make_ui_selection({map=map_screen,read=read,word=word,
        page=function(a,n)page(a,n,0x20000)end,
        signature=function()
            local sig='44896308c7430cffffffffe8e859e4ff'
            assert(hex(read(game+0x148c348,#sig/2))==sig,'Normal UI click signature mismatch')
        end,
        write=function(a,bytes)
            page(a,#bytes,0x20000)
            local count=ffi.new('size_t[1]')
            assert(kernel.WriteProcessMemory(kernel.GetCurrentProcess(),a,bytes,#bytes,count)~=0
                and count[0]==#bytes,'Map UI write failed')
        end})
    ui_selection:apply(s.planet,candidate.difficulty,candidate.row)
    ffi.cast('void (*)(uintptr_t, uint32_t)',game+0x12d1d40)(0,candidate.row)
    assert(u(read(s.board+0x78e68,4),0)==candidate.row,'Native selection rejected')
    assert(u(read(s.board+0x78e6c,4),0)==4294967295,'Mission unexpectedly selected')
    assert(hex(read(s.board+0x78e88,92))==s.active,'Active operation changed on selection')
    selector={started=api.time(),context=s.context}
    emit('PREDICTION_VERIFIED selected_row='..candidate.row..' active_preserved=true')
end
local function tick()
    if not transaction then prepare() end
    local tid=tonumber(kernel.GetCurrentThreadId())
    if thread then assert(thread==tid,'Update thread changed') else thread=tid end
    local now=api.time()
    local pid=ffi.new('uint32_t[1]');user32.GetWindowThreadProcessId(user32.GetForegroundWindow(),pid)
    local focused=pid[0]==kernel.GetCurrentProcessId()
    local s
    if now-last_poll>=0.25 then
        last_poll=now;local reason;s,reason=snapshot()
        if reason=='open galactic map' or reason=='select planet' then armed=false end
        if s then
            local second=snapshot()
            if not second or second.fingerprint~=s.fingerprint then s=nil end
        end
        if s then
            stable=previous==s.fingerprint and stable+1 or 1;previous=s.fingerprint
            if stable<4 then s=nil end
        else stable=0;previous=nil end
    end
    local down=focused and user32.GetAsyncKeyState(0x11)<0 and user32.GetAsyncKeyState(0x10)<0 and user32.GetAsyncKeyState(0x78)<0
    if down and not key_down and not transaction.used then
        local ok,value=pcall(load_candidate,candidate_path)
        if ok then
            for key in pairs(candidate)do candidate[key]=nil end
            for key,v in pairs(value)do candidate[key]=v end
            armed=true;emit('PUBLICATION_ARMED candidate_seed='..candidate.seed..' baseline_seed='..candidate.baseline_seed)
        else armed=false;emit('PUBLICATION_BLOCKED '..tostring(value))end
    end
    key_down=down
    if armed and s and stable>=40 then
        armed=false
        local ok,err=pcall(function()transaction:start(s,now)end)
        if not ok then
            if transaction.used then error(err)end
            emit('PUBLICATION_BLOCKED '..tostring(err)..'; refresh candidate file and press shortcut again')
        end
        s=nil;previous=nil;stable=0
    end
    if transaction:poll(s,now)=='verified' then
        transaction:commit();select_match(assert(s))
    end
    if selector then
        assert(now-selector.started<=5,'Selection confirmation timed out')
        if s and s.context==selector.context and s.seed==candidate.seed
            and s.decoded.highlighted_operation==candidate.row
            and ui_selection and ui_selection:confirmed(candidate.row)
            and u(s.selection,12)==4294967295 then
            ui_selection:commit()
            emit('PUBLICATION_STATE_VERIFIED seed='..s.seed..' row='..candidate.row..' map_ui_row_confirmed=true mission_unselected=true; visual confirmation required')
            selector=nil;stopped=true;M.status='publication_test_passed'
        end
    end
    if transaction.state=='restored' then
        emit('PUBLICATION_TEST_RESTORED '..tostring(transaction.reason));stopped=true;M.status='restored'
    end
end
local function cleanup(reason)
    if ui_selection then
        local ok,err=pcall(function()ui_selection:restore()end)
        if not ok then emit('UI_RESTORE_FAILED '..tostring(err))end
    end
    if transaction and transaction.before then
        local ok,err=pcall(function()transaction:restore(reason)end)
        if not ok then emit('RESTORE_FAILED '..tostring(err)) end
    end
end
local function pack(...)return {n=select('#',...),...}end
_G.update=function(...)
    local result=original_update and pack(original_update(...)) or {n=0}
    if not stopped then
        local ok,err=pcall(tick)
        if not ok then stopped=true;M.status='STOPPED: '..tostring(err);emit(M.status);cleanup('Error') end
    end
    return unpack(result,1,result.n)
end
_G.shutdown=function(...)
    stopped=true;cleanup('Shutdown')
    if log then pcall(function()log:close()end);log=nil end
    if original_shutdown then return original_shutdown(...) end
end
emit('Mission Reroller 0.5.3 publication test; map UI selection enabled; background progress; Ctrl+Shift+F9')
