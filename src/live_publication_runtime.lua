-- Publish one verified Lua search result through the previously tested local path.
-- A runtime factory: the assembler runs this file as function(host,lib,hooks).
local M,emit,read,pointer,page,u,hex=host.M,host.emit,host.read,host.pointer,host.page,host.u,host.hex
local reroll_session=host.reroll_session
local map,write=host.map,host.write
local snapshot,participants,verify_code,O=host.snapshot,host.participants,host.verify_code,host.O
local Search,make_publication,make_ui_selection=lib.Search,lib.make_publication,lib.make_ui_selection
local verify_predicted_board,DayNight=lib.verify_predicted_board,lib.DayNight
local api,game,ffi
host.when_initialized(function(n)api,game,ffi=n.api,n.game,n.ffi end)
local on_existing_match,on_search_match,advance_live_publication
local transaction,selector,ui_selection,candidate,publication_used
local function word(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)
end
local function rawhex(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
-- The code selection runs through (src/offsets.lua), checked again before each use.
local SELECTION={'select_operation','select_campaign_row','selection_dispatch','selection_listener'}
local function check_selection(what)
    local ok,err=pcall(verify_code,SELECTION)
    assert(ok,what..': '..tostring(err))
end
local function ownership(b)
    assert(pointer(game+O.rva.board)==b,'Board changed')
    local session=pointer(game+O.rva.session)
    assert(M.dialog_enabled or u(read(session+O.session.player_count,4),0)==1,'Expected one source owner')
    -- Alone the local player is the only participant. In a lobby the local
    -- player must be its host: a participant who owns the board.
    local source,sources,known=participants(session)
    local local_owner=read(session+O.session.local_player,8)
    assert(known[local_owner],'Source is not local owner')
    assert(read(b+O.board.selection_owner,8)==local_owner,'Not local selection owner')
    local count=u(read(b+O.board.owner_count,4),0)
    assert(count<=5,'Invalid owner count')
    local entries=count>0 and read(b+O.board.owners,count*16) or '';local ids={}
    for i=0,count-1 do
        local id=entries:sub(i*16+1,i*16+8)
        assert(id~=string.rep('\0',8) and not ids[id],'Invalid owner entries');ids[id]=true
    end
    -- The game adds an entry for every participant that has none.
    local capacity=count
    for _,id in ipairs(sources)do if not ids[id]then capacity=capacity+1 end end
    assert(capacity<=5,'Owner queue has no capacity for local source')
    page(b+O.board.seed,4,0x20000);page(b+O.board.owners,capacity*16,0x20000)
    page(b+O.board.owner_count,4,0x20000)
    local ok,err=pcall(verify_code,{'campaign_helpers'})
    assert(ok,'Publication signature changed: '..tostring(err))
    return tostring(session)..hex(source)
end
local function write_seed(b,seed)write(b+O.board.seed,word(seed),'Seed')end
local function notify(b)
    ffi.cast('void (*)(void *, uint32_t)',game+O.rva.publish_seed)(b,2)
end
local function select_match(s)
    check_selection('Selection signature changed')
    local final=assert(snapshot(true),'Selection context unavailable')
    assert(final.fingerprint==s.fingerprint,'State changed before selection')
    ownership(s.board)
    assert(read(s.board+O.board.selection_context,8)==s.selection:sub(1,8),'Selection context not published')
    page(s.board+O.board.selection_context,36,0x20000);page(s.board+O.board.selection,36,0x20000)
    local op
    for _,value in ipairs(s.decoded.operations)do if value.row==candidate.row then op=value end end
    assert(op and op.seed==candidate.operation_seed and op.difficulty==candidate.difficulty,'Predicted operation missing')
    ui_selection=make_ui_selection({map=map,read=read,word=word,
        page=function(a,n)page(a,n,0x20000)end,
        signature=function()
            local ok,err=pcall(verify_code,{'map_click'})
            assert(ok,'Normal UI click signature mismatch: '..tostring(err))
        end,
        -- The selection checks its own write; a restore is not re-read.
        write=function(a,bytes)write(a,bytes,'Map UI',false)end})
    ui_selection:apply(s.planet,candidate.difficulty,candidate.row)
    ffi.cast('void (*)(uintptr_t, uint32_t)',game+O.rva.select_operation)(0,candidate.row)
    assert(read(s.board+O.board.selection_context,8)==s.selection:sub(1,8),'Planet fields changed during selection')
    assert(u(read(s.board+O.board.selected_row,4),0)==candidate.row,'Native selection rejected')
    assert(u(read(s.board+O.board.selected_mission,4),0)==4294967295,'Mission unexpectedly selected')
    assert(hex(read(s.board+O.board.active_operation,92))==s.active,'Active operation changed on selection')
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
    candidate={seed=s.seed,planet=s.planet,row=op.row,difficulty=op.difficulty,operation_seed=op.seed}
    select_match(s);reroll_session.advance('selection_pending')
    emit('EXISTING_MATCH row='..op.row..' seed='..s.seed..' publication=false')
end
on_search_match=function(job,now)
    if publication_used and not M.dialog_enabled then reroll_session.finish('publication_blocked');emit('PUBLICATION_BLOCKED one publication per test session; restart to test again');return end
    local s=job.baseline;local match=job.operation
    candidate={seed=job.seed,planet=s.planet,row=match.row,difficulty=match.difficulty,operation_seed=match.seed,operations=job.operations,required=job.required or {[1]=true,[2]=true,[3]=true},modifiers=job.modifiers,
        constellations=job.constellations,scope=job.scope,daynight=job.daynight}
    transaction=make_publication({
        preflight=function(before,e)
            local current,reason=snapshot(true)
            assert(current,'Publication requires stable viewed-planet data and an idle backend: '..tostring(reason))
            assert(current.board==before.board and current.fingerprint==before.fingerprint,'Publication baseline changed')
            assert(current.seed~=e.seed,'Candidate is already installed')
            assert(read(before.board+O.board.selection_context,8)==before.selection:sub(1,8),'Canonical map planet differs')
            assert(u(before.selection,4)==e.planet,'Viewed planet changed')
            local displayed_planet,displayed_difficulty=map.viewed()
            emit(string.format('PUBLICATION_UI planet=%u expected_planet=%u difficulty=%u expected_difficulty=%u campaign_row=%u',displayed_planet,e.planet,displayed_difficulty,e.difficulty,u(before.selection,8)))
            assert(displayed_planet==e.planet,'Keep the viewed planet open with operation icons visible until the search completes (UI planet='..displayed_planet..', expected='..e.planet..')')
            assert(displayed_difficulty==e.difficulty,'Display difficulty '..e.difficulty..' before starting (UI difficulty='..displayed_difficulty..')')
            check_selection('Selection signature changed')
            local ok,err=pcall(verify_code,{'map_click'})
            assert(ok,'Map click signature changed: '..tostring(err))
            -- A day/night match must hold for the whole buffer from the write.
            local daynight=e.daynight and function(op)return e.daynight.confirm(op,DayNight.war_time(read,before.board))end
            assert(Search.find({operations=e.operations},e.difficulty,e.required,e.modifiers,e.constellations,e.scope,daynight),'Predicted filter no longer matches')
            before.owner_guard=ownership(before.board)
            local final=assert(snapshot(true),'Publication context unavailable')
            assert(final.fingerprint==before.fingerprint,'Context changed before publication')
        end,
        publish=function(before,seed)
            assert(ownership(before.board)==before.owner_guard,'Owner changed')
            publication_used=true
            emit(string.format('PUBLISH_BEGIN previous_seed=%u candidate_seed=%u primary_planet=%u viewed_planet=%u',before.seed,seed,u(before.selection,0),u(before.selection,4)))
            write_seed(before.board,seed);notify(before.board)
            assert(hex(read(before.board+O.board.active_operation,92))==before.active,'Active operation changed')
            emit('PUBLISH_RETURN active_preserved=true')
        end,
        restore=function(before,seed)
            assert(ownership(before.board)==before.owner_guard,'Restore owner changed; refusing stale write')
            assert(hex(read(before.board+O.board.active_operation,92))==before.active,'Restore active operation changed')
            local current=u(read(before.board+O.board.seed,4),0)
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
            if candidate.daynight then
                -- The written board keeps the predicted level nodes; the side is
                -- checked again against the war time now.
                local op
                for _,value in ipairs(assert(s).decoded.operations)do if value.row==candidate.row then op=value end end
                local ok,held=pcall(function()return op and candidate.daynight.confirm(op,DayNight.war_time(read,s.board))end)
                emit('DAYNIGHT_VERIFIED row='..candidate.row..' holds='..tostring(ok and held or false)..(ok and '' or ' error='..tostring(held)))
                if not (ok and held)then reroll_session.report('The operation may leave the chosen side within '..DayNight.duration(candidate.daynight.planet.buffer))end
            end
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
