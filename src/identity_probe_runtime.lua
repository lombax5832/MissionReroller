-- Diagnostic only: nothing here publishes, calls the game generator or selects.
-- A runtime factory: the assembler runs this file as function(host,lib,hooks).
-- Each hook is nil when its runtime is not in the build; without the
-- search's clock the capture slices on the adapter's timer.
local M,log,read,u,hex,snapshot=host.M,host.log,host.read,host.u,host.hex,host.snapshot
local reroll_session=host.reroll_session
local initialize,config=host.initialize,host.config
local make_rng,make_probe,predict_identity=lib.make_rng,lib.make_probe,lib.predict_identity
local make_special_inputs,make_level_inputs,make_level_verification=lib.make_special_inputs,lib.make_level_inputs,lib.make_level_verification
local choose_level,Planet,ModInventory=lib.choose_level,lib.Planet,lib.ModInventory
local ExternalEdits,O,pointer=lib.ExternalEdits,host.O,host.pointer
local dialog_tick,dialog_release,observe_constellations=hooks.dialog_tick,hooks.dialog_release,hooks.observe_constellations
local observe_objectives=hooks.observe_objectives
local on_prediction_ready,advance_prediction_search=hooks.on_prediction_ready,hooks.advance_prediction_search
local shutdown_search_workers,cool_search_workers=hooks.shutdown_search_workers,hooks.cool_search_workers
local advance_live_publication,search_clock=hooks.advance_live_publication,hooks.search_clock
local api,game,ffi,kernel,user32
host.when_initialized(function(n)api,game,ffi,kernel,user32=n.api,n.game,n.ffi,n.kernel,n.user32 end)
local original_update,original_shutdown=rawget(_G,'update'),rawget(_G,'shutdown')
local stopped,key_down,armed=false,true,nil
local mods_logged=false
local probe,last_poll,previous,stable=nil,-math.huge,nil,0
-- A run's first poll starts at once, and one poll whose two captures agree
-- is enough when the board matches the prediction: the search re-reads every
-- input, revalidates it every second and before a match, and checks the
-- board's fingerprint every slice. A board that does not match is captured
-- again until four polls 0.5 s apart agree before the run reports it, so a
-- read made while the map changed never ends a run as a mismatch.
local CONFIRM_POLLS=4
local needed,polls=1,0
local capture_failures,last_capture_error=0,nil
-- The first board seen per planet and campaign seed, the proof that a row
-- changed later without a reroll (external_edits.lua).
local baselines,last_baseline={},-math.huge
-- A poll captures the board twice, about 50 ms of reads each offline and more
-- in game. It runs as a coroutine whose reads yield once the frame's slice is
-- used, the slice of the seed search, so it no longer stalls one frame.
local poll,slice_end
local capture_slice=0.016
local function slice_clock()return search_clock and search_clock() or api.time()end
local function sliced_read(address,size)
    if slice_end and slice_clock()>=slice_end then coroutine.yield()end
    return read(address,size)
end
local function prepare()
    -- initialize() checks the generator code and the RNG constant with every
    -- other entry of src/offsets.lua.
    initialize()
    probe=make_probe(sliced_read,u,predict_identity,make_special_inputs(sliced_read,u,api.pointer),
        function(cached_read)return make_level_inputs(cached_read,u,game)end,
        make_level_verification(make_rng,choose_level),Planet.capture(sliced_read,u,api.pointer,game))
    reroll_session.advance('ready_read_only')
    log.debug('LUA_IDENTITY_READY signatures=verified read_only='..tostring(M.read_only))
end
local function capture(s)
    local ok,result=xpcall(function()return probe:capture(s)end,function(err)
        if debug and type(debug.traceback)=='function' then return debug.traceback(tostring(err),2)end
        return tostring(err)
    end)
    if ok then return result end
    -- A capture spans mutable game data. Reject it intact and retry, never
    -- weaken graph bounds or carry a prior partially stable sample forward.
    previous=nil;stable=0;capture_failures=capture_failures+1
    last_capture_error=string.format('planet=%d seed=%u %s',s.planet,s.seed,tostring(result))
    reroll_session.advance('capture_retry')
    if capture_failures==1 then log.debug('LUA_CAPTURE_RETRY '..last_capture_error)end
    return nil
end
-- Records the viewed planet's board once per campaign seed, before another
-- mod has a chance to edit it. Diagnostics: a failed read never stops the mod.
local function observe_baseline(now)
    if now-last_baseline<1 or reroll_session.view().running then return end
    last_baseline=now
    pcall(function()
        local b=pointer(game+O.rva.board)
        local planet=u(read(b+O.board.selection,8),4)
        if planet>=512 or ExternalEdits.known(baselines,planet,u(read(b+O.board.seed,4),0)) then return end
        local s=snapshot(true)
        if s and ExternalEdits.observe(baselines,s.planet,s.seed,s.operations) then
            log.debug(string.format('BASELINE_RECORDED planet=%d seed=%u',s.planet,s.seed))
        end
    end)
end
local function tick()
    if not probe then prepare()end
    local now=api.time()
    local pid=ffi.new('uint32_t[1]')
    user32.GetWindowThreadProcessId(user32.GetForegroundWindow(),pid)
    local focused=pid[0]==kernel.GetCurrentProcessId()
    if dialog_tick then dialog_tick(focused,now)end
    if observe_constellations then observe_constellations(now)end
    if observe_objectives then observe_objectives(now)end
    local down=focused and user32.GetAsyncKeyState(0x11)<0 and user32.GetAsyncKeyState(0x10)<0 and user32.GetAsyncKeyState(0x78)<0
    if M.dialog_enabled then down=false end
    if reroll_session.take_cancel() then
        armed=nil
        if advance_prediction_search then advance_prediction_search('cancel',now)end
        if advance_live_publication then advance_live_publication('cancel',now)end
        reroll_session.finish('cancelled')
    end
    local requested=reroll_session.take_request()
    if requested or (down and not key_down) then
        if advance_live_publication and advance_live_publication('cancel',now) then key_down=down;return end
        if advance_prediction_search and advance_prediction_search('cancel',now) then key_down=down;return end
        armed=now;poll=nil;previous=nil;stable=0;last_poll=-math.huge;needed,polls=1,0
        reroll_session.advance('waiting_for_stable_inputs')
        capture_failures=0;last_capture_error=nil;M.last_result=nil;M.level_result=nil;M.composition_result=nil
        log.debug('LUA_IDENTITY_ARMED; '..config.armed)
    end
    key_down=down
    local searching=advance_prediction_search and advance_prediction_search('tick',now)
    local publishing=advance_live_publication and advance_live_publication('tick',now)
    -- With no stage left to run, the run ends where it stands.
    if not armed then
        poll=nil
        if not searching and not publishing then reroll_session.settle();observe_baseline(now)end
        return
    end
    if now-armed>30 then
        armed=nil;poll=nil;reroll_session.finish('capture_timeout');log.warn('LUA_IDENTITY_BLOCKED stable map inputs unavailable; press shortcut to retry')
        if last_capture_error then log.warn('LUA_CAPTURE_DETAIL failures='..capture_failures..' last='..last_capture_error)end
        return
    end
    if not poll then
        if now-last_poll<0.5 then return end
        last_poll=now;polls=polls+1
        poll=coroutine.create(function()
            local s,why=snapshot(true)
            if not s then previous=nil;stable=0;reroll_session.advance('waiting_for_stable_inputs',why or 'waiting');return end
            local captured=capture(s)
            if not captured then return end
            local again=snapshot(true)
            local repeated=again and capture(again)
            if not repeated or repeated.fingerprint~=captured.fingerprint then
                previous=nil;stable=0;return
            end
            return s,captured
        end)
    end
    slice_end=slice_clock()+capture_slice
    local ok,s,captured=coroutine.resume(poll)
    slice_end=nil
    if not ok then poll=nil;error(s,0)end
    if coroutine.status(poll)~='dead' then return end
    poll=nil
    if not captured then return end
    stable=previous==captured.fingerprint and stable+1 or 1
    previous=captured.fingerprint
    if stable<needed then return end
    local start=api.time()
    local result=probe:compare(captured)
    local compare_ms=(api.time()-start)*1000
    -- Rows another mod rewrote since generation are left out of every check
    -- on the live board; the search's baseline and existing-match check read
    -- them from s.external.
    local edits,why
    if not result.passed then edits,why=ExternalEdits.classify(result,baselines,s.planet,s.seed)end
    local skip=edits and edits.rows
    local passed=result.passed or edits~=nil
    local levels=passed and captured.level_graphs and probe:compare_levels(captured,skip) or nil
    local composition_passed
    if passed and captured.composition then composition_passed=ExternalEdits.composition_passes(captured.composition,skip)end
    -- Anything short of an exact match, edited rows included, is confirmed
    -- over CONFIRM_POLLS stable polls before it is reported.
    local doubt=not result.passed and 'identity' or levels and not levels.passed and 'levels'
        or captured.composition and passed and not composition_passed and 'composition'
    if doubt and needed<CONFIRM_POLLS then
        needed,stable=CONFIRM_POLLS,1
        log.debug('LUA_IDENTITY_RECHECK '..doubt..' differs after one poll; confirming over '..CONFIRM_POLLS..' stable polls')
        return
    end
    local armed_for=now-armed;armed=nil
    if capture_failures>0 then log.debug('LUA_CAPTURE_RECOVERED rejected_captures='..capture_failures)end
    if result.passed then pcall(ExternalEdits.observe,baselines,s.planet,s.seed,s.operations)end
    s.external=skip
    if passed then reroll_session.advance('identity_test_passed')else reroll_session.finish('identity_test_mismatch')end
    M.last_result=result
    log[result.passed and 'debug' or 'warn'](string.format('LUA_IDENTITY_%s planet=%d seed=%u pool=%d special_events=%d matched=%d live=%d predicted=%d elapsed_ms=%.3f capture_s=%.3f polls=%d read_only='..tostring(M.read_only)..' scope=IDs/seeds/difficulty',
        result.passed and 'PASS' or edits and 'EDITED' or 'MISMATCH',s.planet,s.seed,captured.input.pool_count,#(captured.input.specials or {}),result.matched,result.observed,result.predicted,compare_ms,armed_for,polls))
    if edits then
        for _,d in ipairs(result.differences)do
            local o,p=d.observed,d.predicted
            log.warn(string.format('LUA_IDENTITY_EXTERNAL_EDIT row=%d observed=%d/%u/d%d predicted=%d/%u/d%d evidence=%s',
                d.row,o.id,o.seed,o.difficulty,p.id,p.seed,p.difficulty,skip[d.row].evidence))
        end
    else
        for i=1,math.min(#result.errors,8)do log.warn('LUA_IDENTITY_DETAIL '..result.errors[i])end
        if not result.passed then
            log.warn('LUA_IDENTITY_NOT_EXTERNAL '..tostring(why))
            -- Rows that only changed values look like another mod's edit made
            -- before the planet was first viewed, which leaves no proof.
            local edited=#(result.differences or {})>0
            for _,d in ipairs(result.differences or {})do if d.kind~='value' then edited=false end end
            if edited then reroll_session.report('Another mod may have changed these operations before the planet was viewed; see the log')end
        end
    end
    if levels then
        M.level_result=levels
        if levels.passed then reroll_session.advance('identity_and_level_tests_passed')else reroll_session.finish('level_test_mismatch')end
        log[levels.passed and 'debug' or 'warn'](string.format('LUA_LEVEL_%s checked=%d category_draws=%d observed_seed_assisted=true scope=level-selection',
            levels.passed and 'PASS' or 'MISMATCH',levels.checked,levels.category_draws))
        for i=1,math.min(#levels.errors,8)do log.warn('LUA_LEVEL_DETAIL '..levels.errors[i])end
    end
    if passed and captured.composition then
        local composition=captured.composition;M.composition_result=composition
        if not composition_passed then reroll_session.finish('composition_test_mismatch')
        elseif not M.level_result or M.level_result.passed then reroll_session.advance('composition_test_passed') end
        log[composition_passed and 'debug' or 'warn'](string.format('LUA_COMPOSITION_%s planet=%d operations=%d templates=%d modifiers=%d missions=%d observed_mission_seeds=false scope=operation-base-inputs',
            composition_passed and 'PASS' or 'MISMATCH',s.planet,composition.operations,composition.templates,composition.modifiers,composition.checked)
            ..(edits and ' edited_rows='..edits.count or ''))
        local shown=0
        for i=1,#composition.errors do
            local row=tonumber(composition.errors[i]:match('^row=(%d+) '))
            if shown<8 and not (skip and row and skip[row]) then shown=shown+1;log.warn('LUA_COMPOSITION_DETAIL '..composition.errors[i])end
        end
        if composition.independent_bases then
            log[composition_passed and 'debug' or 'warn'](string.format('LUA_SEED_PREDICTION_%s planet=%d seed=%u bases=%d operations=%d missions=%d observed_operation_bases=false preserved_active=true read_only='..tostring(M.read_only),
                composition_passed and 'PASS' or 'MISMATCH',s.planet,s.seed,composition.bases,composition.operations,composition.checked))
        end
    end
    if on_prediction_ready and passed and M.level_result and M.level_result.passed
        and composition_passed and M.composition_result.independent_bases then
        on_prediction_ready(s,captured.definitions,now)
    else
        if on_prediction_ready and passed then log.warn('LUA_SEARCH_NOT_STARTED level='..tostring(M.level_result and M.level_result.passed)..' composition='..tostring(composition_passed)..' independent_bases='..tostring(M.composition_result and M.composition_result.independent_bases))end
        log.debug('Read-only comparison; no publication. Constellations and unsupported campaign branches remain unverified. Press shortcut to test another planet.')
        reroll_session.settle()
    end
end
local function pack(...)return {n=select('#',...),...}end
_G.update=function(...)
    local result=original_update and pack(original_update(...)) or {n=0}
    -- Every mod has loaded by the first frame, so the list goes out then.
    if not mods_logged then
        mods_logged=true
        pcall(function()for _,line in ipairs(ModInventory.lines(_G))do log.info(line)end end)
    end
    if not stopped then
        local ok,err=pcall(tick)
        if not ok then
            stopped=true;reroll_session.fail(err);log.error(M.status)
            if advance_prediction_search then pcall(advance_prediction_search,'cancel',0)end
            if cool_search_workers then pcall(cool_search_workers)end
            if advance_live_publication then pcall(advance_live_publication,'cancel',0)end
            if dialog_release then pcall(dialog_release,'error')end
        end
    end
    return unpack(result,1,result.n)
end
_G.shutdown=function(...)
    stopped=true
    if advance_prediction_search then pcall(advance_prediction_search,'cancel',0)end
    -- No worker VM may still be walking when the game's VM goes away.
    if shutdown_search_workers then pcall(shutdown_search_workers,3)end
    if advance_live_publication then pcall(advance_live_publication,'cancel',0)end
    if dialog_release then pcall(dialog_release,'shutdown')end
    host.close_log()
    if original_shutdown then return original_shutdown(...)end
end
log.info(config.banner..'; '..config.mode..'; '..config.shortcut..'; background progress enabled')
return {tick=tick}
