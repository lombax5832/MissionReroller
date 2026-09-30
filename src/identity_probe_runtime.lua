-- Diagnostic only: nothing here publishes, calls the game generator or selects.
-- A runtime factory: the assembler runs this file as function(host,lib,hooks).
-- Each hook is nil when its runtime is not in the build; without the
-- search's clock the capture slices on the adapter's timer.
local M,emit,read,u,hex,snapshot=host.M,host.emit,host.read,host.u,host.hex,host.snapshot
local reroll_session=host.reroll_session
local initialize,config=host.initialize,host.config
local make_rng,sha256,make_probe,predict_identity=lib.make_rng,lib.sha256,lib.make_probe,lib.predict_identity
local make_special_inputs,make_level_inputs,make_level_verification=lib.make_special_inputs,lib.make_level_inputs,lib.make_level_verification
local choose_level,composition_factory,ModInventory=lib.choose_level,lib.composition_factory,lib.ModInventory
local dialog_tick,dialog_release,observe_constellations=hooks.dialog_tick,hooks.dialog_release,hooks.observe_constellations
local on_prediction_ready,advance_prediction_search=hooks.on_prediction_ready,hooks.advance_prediction_search
local advance_live_publication,search_clock=hooks.advance_live_publication,hooks.search_clock
local api,game,ffi,kernel,user32
host.when_initialized(function(n)api,game,ffi,kernel,user32=n.api,n.game,n.ffi,n.kernel,n.user32 end)
local original_update,original_shutdown=rawget(_G,'update'),rawget(_G,'shutdown')
local stopped,key_down,armed=false,true,nil
local mods_logged=false
local probe,last_poll,previous,stable=nil,-math.huge,nil,0
local capture_failures,last_capture_error=0,nil
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
local code_signatures={
    {0x11e3c10,1104,'e600b7f917c0dae668397ec326b9ec53df4705e0c1135d5880be8fcaa91d65bd'},
    {0x11e4060,1136,'5cc7271a512f5caf431abcc5b3e0fcbeb99c325eeae368b03f3ec52427e1661f'},
    {0x11e44d0,960,'761e9b878f605a026082169dd67c4a2f5cae070d03a840ac2027499531689801'},
    {0x11e4b50,248,'0847b63474ce07ef97714cd0acf6d71d76e9a1a4ec1acee82d0d25789bee0dc3'},
    {0x12d5550,288,'b4c826d4744fdbbc161f2da037c544451c77caea400dfe5b87c77233f060289a'},
    {0x12dbd70,64,'f021d86754fcf3cb8658ab2e205d01a9df0d85eb0fd24f8f7893ef0f3e315ca1'},
    {0x11e6020,743,'f5570461586131f1cc890d3745194440ae83dd0c2b1bb468db9f947c33fbc848'},
    {0x11e6800,338,'f5dfdd2ba5a53230faa8ad361012721980e49da2a121ad7ad7a44f03d0372358'},
    {0x11e5100,1291,'5d9b9f3fb65fd7f0b39817b4919bebea8bd14995f77694053c7f8e0e6aebb488'},
    {0x11e3250,2382,'93ef0654c865d859f1299ddcfa11d0c27772ab96542a1d1d95c9c2d819b85e5a'},
    {0x11e6340,793,'b417991b06d78e8df61b2866c5373e0b166a018d459dbaa3078f34880d6dfa9f'},
    {0x11f96e0,450,'b121a84355d760e1d95c35e3fbc508a2f86875fe3614cec66b643d4587d03667'},
    {0x12e7990,243,'1f2ccbbfa61bc50a3e2ec72bfcc2000a992f09f2495f60be2f173568064de7f4'},
    {0x12df110,952,'77111a8319abae6556e658acadbb13660f1582be47b3d2fc5d315ac8232c50a0'},
    {0x177e5b0,831,'66c3b348db09003218b6cec50fd322fb1de77c4512a464fb135e7556470e28f8'},
    {0x174ab50,335,'0bd16770e68656de8fb7e84f9d62a64cda0e8ffa0d81c25c539ef4e79d743ab9'},
    {0x174b110,464,'4b395978f97967bfc97024b41ab6b63246c120019aa369f91d358321b543a7a4'},
    {0x11ebb40,152,'5feaccab97b046561f786f2e60533112168f152ebcd19f38ad1e190c9a08e6a9'},
}
local function prepare()
    initialize()
    for _,sig in ipairs(code_signatures)do
        assert(sha256(read(game+sig[1],sig[2]))==sig[3],'Generator signature mismatch')
    end
    assert(hex(read(game+0x23c6780,8))=='000000000000f03d','RNG scaling constant mismatch')
    probe=make_probe(sliced_read,u,predict_identity,make_special_inputs(sliced_read,u,api.pointer),
        function(cached_read)return make_level_inputs(cached_read,u,game)end,
        make_level_verification(make_rng,choose_level),composition_factory(sliced_read,u,api.pointer,game))
    reroll_session.advance('ready_read_only')
    emit('LUA_IDENTITY_READY signatures=verified read_only='..tostring(M.read_only))
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
    if capture_failures==1 then emit('LUA_CAPTURE_RETRY '..last_capture_error)end
    return nil
end
local function tick()
    if not probe then prepare()end
    local now=api.time()
    local pid=ffi.new('uint32_t[1]')
    user32.GetWindowThreadProcessId(user32.GetForegroundWindow(),pid)
    local focused=pid[0]==kernel.GetCurrentProcessId()
    if dialog_tick then dialog_tick(focused,now)end
    if observe_constellations then observe_constellations(now)end
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
        armed=now;poll=nil;previous=nil;stable=0;reroll_session.advance('waiting_for_stable_inputs')
        capture_failures=0;last_capture_error=nil;M.last_result=nil;M.level_result=nil;M.composition_result=nil
        emit('LUA_IDENTITY_ARMED; '..config.armed)
    end
    key_down=down
    local searching=advance_prediction_search and advance_prediction_search('tick',now)
    local publishing=advance_live_publication and advance_live_publication('tick',now)
    -- With no stage left to run, the run ends where it stands.
    if not armed then poll=nil;if not searching and not publishing then reroll_session.settle()end;return end
    if now-armed>30 then
        armed=nil;poll=nil;reroll_session.finish('capture_timeout');emit('LUA_IDENTITY_BLOCKED stable map inputs unavailable; press shortcut to retry')
        if last_capture_error then emit('LUA_CAPTURE_DETAIL failures='..capture_failures..' last='..last_capture_error)end
        return
    end
    if not poll then
        if now-last_poll<0.5 then return end
        last_poll=now
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
    if stable<4 then return end
    armed=nil
    if capture_failures>0 then emit('LUA_CAPTURE_RECOVERED rejected_captures='..capture_failures)end
    local start=api.time()
    local result=probe:compare(captured)
    if result.passed then reroll_session.advance('identity_test_passed')else reroll_session.finish('identity_test_mismatch')end
    M.last_result=result
    emit(string.format('LUA_IDENTITY_%s planet=%d seed=%u pool=%d special_events=%d matched=%d live=%d predicted=%d elapsed_ms=%.3f read_only='..tostring(M.read_only)..' scope=IDs/seeds/difficulty',
        result.passed and 'PASS' or 'MISMATCH',s.planet,s.seed,captured.input.pool_count,#(captured.input.specials or {}),result.matched,result.observed,result.predicted,(api.time()-start)*1000))
    for i=1,math.min(#result.errors,8)do emit('LUA_IDENTITY_DETAIL '..result.errors[i])end
    if result.passed and captured.level_graphs then
        local levels=probe:compare_levels(captured);M.level_result=levels
        if levels.passed then reroll_session.advance('identity_and_level_tests_passed')else reroll_session.finish('level_test_mismatch')end
        emit(string.format('LUA_LEVEL_%s checked=%d category_draws=%d observed_seed_assisted=true scope=level-selection',
            levels.passed and 'PASS' or 'MISMATCH',levels.checked,levels.category_draws))
        for i=1,math.min(#levels.errors,8)do emit('LUA_LEVEL_DETAIL '..levels.errors[i])end
    end
    if result.passed and captured.composition then
        local composition=captured.composition;M.composition_result=composition
        if not composition.passed then reroll_session.finish('composition_test_mismatch')
        elseif not M.level_result or M.level_result.passed then reroll_session.advance('composition_test_passed') end
        emit(string.format('LUA_COMPOSITION_%s planet=%d operations=%d templates=%d modifiers=%d missions=%d observed_mission_seeds=false scope=operation-base-inputs',
            composition.passed and 'PASS' or 'MISMATCH',s.planet,composition.operations,composition.templates,composition.modifiers,composition.checked))
        for i=1,math.min(#composition.errors,8)do emit('LUA_COMPOSITION_DETAIL '..composition.errors[i])end
        if composition.independent_bases then
            emit(string.format('LUA_SEED_PREDICTION_%s planet=%d seed=%u bases=%d operations=%d missions=%d observed_operation_bases=false preserved_active=true read_only='..tostring(M.read_only),
                composition.passed and 'PASS' or 'MISMATCH',s.planet,s.seed,composition.bases,composition.operations,composition.checked))
        end
    end
    if on_prediction_ready and result.passed and M.level_result and M.level_result.passed
        and M.composition_result and M.composition_result.passed and M.composition_result.independent_bases then
        on_prediction_ready(s,captured.definitions,now)
    else
        if on_prediction_ready and result.passed then emit('LUA_SEARCH_NOT_STARTED level='..tostring(M.level_result and M.level_result.passed)..' composition='..tostring(M.composition_result and M.composition_result.passed)..' independent_bases='..tostring(M.composition_result and M.composition_result.independent_bases))end
        emit('Read-only comparison; no publication. Constellations and unsupported campaign branches remain unverified. Press shortcut to test another planet.')
        reroll_session.settle()
    end
end
local function pack(...)return {n=select('#',...),...}end
_G.update=function(...)
    local result=original_update and pack(original_update(...)) or {n=0}
    -- Every mod has loaded by the first frame, so the list goes out then.
    if not mods_logged then
        mods_logged=true
        pcall(function()for _,line in ipairs(ModInventory.lines(_G))do emit(line)end end)
    end
    if not stopped then
        local ok,err=pcall(tick)
        if not ok then
            stopped=true;reroll_session.fail(err);emit(M.status)
            if advance_live_publication then pcall(advance_live_publication,'cancel',0)end
            if dialog_release then pcall(dialog_release,'error')end
        end
    end
    return unpack(result,1,result.n)
end
_G.shutdown=function(...)
    stopped=true
    if advance_prediction_search then pcall(advance_prediction_search,'cancel',0)end
    if advance_live_publication then pcall(advance_live_publication,'cancel',0)end
    if dialog_release then pcall(dialog_release,'shutdown')end
    host.close_log()
    if original_shutdown then return original_shutdown(...)end
end
emit(config.banner..'; '..config.mode..'; '..config.shortcut..'; background progress enabled')
return {tick=tick}
