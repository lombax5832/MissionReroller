-- Publish one verified Lua search result through the previously tested local path.
-- A runtime factory: the assembler runs this file as function(host,lib,hooks).
local M,emit,read,pointer,page,u,hex=host.M,host.emit,host.read,host.pointer,host.page,host.u,host.hex
local reroll_session=host.reroll_session
local snapshot,participants,expected_code=host.snapshot,host.participants,host.expected_code
local Search,make_publication,make_ui_selection=lib.Search,lib.make_publication,lib.make_ui_selection
local selection_signatures,verify_predicted_board=lib.selection_signatures,lib.verify_predicted_board
local api,game,ffi,kernel
host.when_initialized(function(n)api,game,ffi,kernel=n.api,n.game,n.ffi,n.kernel end)
local on_existing_match,on_search_match,advance_live_publication
local transaction,selector,ui_selection,candidate,publication_used
local function word(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)
end
local function rawhex(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local function ownership(b)
    assert(pointer(game+0x347cee8)==b,'Board changed')
    local session=pointer(game+0x347cef0)
    assert(M.dialog_enabled or u(read(session+0x162d8,4),0)==1,'Expected one source owner')
    -- Alone the local player is the only participant. In a lobby the local
    -- player must be its host: a participant who owns the board.
    local source,sources,known=participants(session)
    local local_owner=read(session+0xb398,8)
    assert(known[local_owner],'Source is not local owner')
    assert(read(b+0x1f8078,8)==local_owner,'Not local selection owner')
    local count=u(read(b+0x1f80d0,4),0)
    assert(count<=5,'Invalid owner count')
    local entries=count>0 and read(b+0x1f8080,count*16) or '';local ids={}
    for i=0,count-1 do
        local id=entries:sub(i*16+1,i*16+8)
        assert(id~=string.rep('\0',8) and not ids[id],'Invalid owner entries');ids[id]=true
    end
    -- The game adds an entry for every participant that has none.
    local capacity=count
    for _,id in ipairs(sources)do if not ids[id]then capacity=capacity+1 end end
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
local function select_match(s)
    for _,sig in ipairs(selection_signatures)do
        assert(hex(read(game+sig[1],#sig[2]/2))==sig[2],'Selection signature changed')
    end
    local final=assert(snapshot(true),'Selection context unavailable')
    assert(final.fingerprint==s.fingerprint,'State changed before selection')
    ownership(s.board)
    assert(read(s.board+0x78e60,8)==s.selection:sub(1,8),'Selection context not published')
    page(s.board+0x78e60,36,0x20000);page(s.board+0x17a298,36,0x20000)
    local op
    for _,value in ipairs(s.decoded.operations)do if value.row==candidate.row then op=value end end
    assert(op and op.seed==candidate.operation_seed and op.difficulty==candidate.difficulty,'Predicted operation missing')
    ui_selection=make_ui_selection({root=function()return pointer(game+0x3326aa0)end,
        read=read,u32=function(bytes)return u(bytes,0)end,word=word,
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
    assert(read(s.board+0x78e60,8)==s.selection:sub(1,8),'Planet fields changed during selection')
    assert(u(read(s.board+0x78e68,4),0)==candidate.row,'Native selection rejected')
    assert(u(read(s.board+0x78e6c,4),0)==4294967295,'Mission unexpectedly selected')
    assert(hex(read(s.board+0x78e88,92))==s.active,'Active operation changed on selection')
    selector={started=api.time(),context=s.context,planets=s.selection:sub(1,8)}
    emit('PREDICTION_VERIFIED selected_row='..candidate.row..' active_preserved=true')
end
local function cleanup(reason)
    if ui_selection then
        local ok,err=pcall(function()ui_selection:restore()end)
        if not ok then emit('UI_RESTORE_FAILED '..tostring(err))end
    end
    if transaction and transaction.before then
        local ok,err=pcall(function()transaction:restore(reason)end)
        if not ok then emit('RESTORE_FAILED '..tostring(err));error(err)end
    end
    transaction=nil;selector=nil;ui_selection=nil
end
on_existing_match=function(s,op,now)
    ffi.cdef[[int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);]]
    candidate={seed=s.seed,planet=s.planet,row=op.row,difficulty=op.difficulty,operation_seed=op.seed}
    select_match(s);reroll_session.advance('selection_pending')
    emit('EXISTING_MATCH row='..op.row..' seed='..s.seed..' publication=false')
end
on_search_match=function(job,now)
    if publication_used and not M.dialog_enabled then reroll_session.finish('publication_blocked');emit('PUBLICATION_BLOCKED one publication per test session; restart to test again');return end
    local s=job.baseline;local match=job.operation
    candidate={seed=job.seed,planet=s.planet,row=match.row,difficulty=match.difficulty,operation_seed=match.seed,operations=job.operations,required=job.required or {[1]=true,[2]=true,[3]=true},modifiers=job.modifiers,
        constellations=job.constellations,scope=job.scope}
    ffi.cdef[[int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);]]
    transaction=make_publication({
        preflight=function(before,e)
            local current,reason=snapshot(true)
            assert(current,'Publication requires stable viewed-planet data and an idle backend: '..tostring(reason))
            assert(current.board==before.board and current.fingerprint==before.fingerprint,'Publication baseline changed')
            assert(current.seed~=e.seed,'Candidate is already installed')
            assert(read(before.board+0x78e60,8)==before.selection:sub(1,8),'Canonical map planet differs')
            assert(u(before.selection,4)==e.planet,'Viewed planet changed')
            local ui=pointer(game+0x3326aa0)
            local displayed_planet=u(read(ui+0x4ef8,4),0)
            local displayed_difficulty=u(read(ui+0x4f14,4),0)
            emit(string.format('PUBLICATION_UI planet=%u expected_planet=%u difficulty=%u expected_difficulty=%u campaign_row=%u',displayed_planet,e.planet,displayed_difficulty,e.difficulty,u(before.selection,8)))
            assert(displayed_planet==e.planet,'Keep the viewed planet open with operation icons visible until the search completes (UI planet='..displayed_planet..', expected='..e.planet..')')
            assert(displayed_difficulty==e.difficulty,'Display difficulty '..e.difficulty..' before starting (UI difficulty='..displayed_difficulty..')')
            for _,sig in ipairs(selection_signatures)do assert(hex(read(game+sig[1],#sig[2]/2))==sig[2],'Selection signature changed')end
            assert(hex(read(game+0x148c348,16))=='44896308c7430cffffffffe8e859e4ff','Map click signature changed')
            assert(Search.find({operations=e.operations},e.difficulty,e.required,e.modifiers,e.constellations,e.scope),'Predicted filter no longer matches')
            before.owner_guard=ownership(before.board)
            local final=assert(snapshot(true),'Publication context unavailable')
            assert(final.fingerprint==before.fingerprint,'Context changed before publication')
        end,
        publish=function(before,seed)
            assert(ownership(before.board)==before.owner_guard,'Owner changed')
            publication_used=true
            emit(string.format('PUBLISH_BEGIN previous_seed=%u candidate_seed=%u primary_planet=%u viewed_planet=%u',before.seed,seed,u(before.selection,0),u(before.selection,4)))
            write_seed(before.board,seed);notify(before.board)
            assert(hex(read(before.board+0x78e88,92))==before.active,'Active operation changed')
            emit('PUBLISH_RETURN active_preserved=true')
        end,
        restore=function(before,seed)
            assert(ownership(before.board)==before.owner_guard,'Restore owner changed; refusing stale write')
            assert(hex(read(before.board+0x78e88,92))==before.active,'Restore active operation changed')
            local current=u(read(before.board+0x78e84,4),0)
            assert(current==seed or current==before.seed,'External seed change; refusing overwrite')
            write_seed(before.board,before.seed);notify(before.board)
            emit('RESTORE_SEED previous_seed='..before.seed)
        end,
        matches=function(current,e)
            local ok,reason=verify_predicted_board(current,e.operations,u)
            emit('PREDICTION_CHECK descriptors_match='..tostring(ok)..' reason='..tostring(reason))
            return ok and current.active==s.active and current.selection:sub(1,8)==s.selection:sub(1,8)
        end,
    },candidate)
    local ok,err=pcall(function()transaction:start(s,now)end)
    if not ok then
        local attempted=transaction.used
        cleanup('Publication failed')
        reroll_session.finish(attempted and 'publication_failed' or 'publication_blocked')
        emit('PUBLICATION_BLOCKED '..tostring(err));return
    end
    reroll_session.advance('publication_pending')
end
advance_live_publication=function(action,now)
    if not transaction and not selector then return false end
    if action=='cancel' then cleanup('Cancelled or stopped');reroll_session.finish('publication_cancelled');return true end
    if transaction and transaction.state=='pending' then
        local s=snapshot(true)
        if s then local again=snapshot(true);if not again or again.fingerprint~=s.fingerprint then s=nil end end
        local state=transaction:poll(s,now)
        if state=='restored' then
            emit('PUBLICATION_RESTORED '..tostring(transaction.reason));transaction=nil;reroll_session.finish('publication_restored');return true
        elseif state=='verified' then
            -- The regenerated board is correct. Selection failure must not undo
            -- a verified board; the user can still select its operation manually.
            transaction:commit();transaction=nil
            select_match(assert(s));reroll_session.advance('selection_pending')
        end
    end
    if selector then
        assert(now-selector.started<=5,'Selection confirmation timed out')
        local s=snapshot(true)
        if s then assert(s.selection:sub(1,8)==selector.planets,'Planet fields changed before selection confirmation')end
        if s and s.context==selector.context and s.seed==candidate.seed
            and s.decoded.highlighted_operation==candidate.row and ui_selection:confirmed(candidate.row)
            and u(s.selection,12)==4294967295 then
            ui_selection:commit();ui_selection=nil;selector=nil
            emit('PUBLICATION_STATE_VERIFIED seed='..s.seed..' row='..candidate.row..' map_ui_row_confirmed=true mission_unselected=true')
            reroll_session.finish('publication_test_passed')
        end
    end
    return true
end
emit('Live publication enabled: alone on ship; keep the viewed planet open; verified match opens automatically')
return {on_existing_match=on_existing_match,on_search_match=on_search_match,advance_live_publication=advance_live_publication}
