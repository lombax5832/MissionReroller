local function release(reason)
    if gate then gate:release() end
    router=nil;visible=false;keys={}
    if panel then panel:clear() end
    emit('MODAL_RELEASE '..reason)
end
local function select_operation(s,op)
    for _,sig in ipairs(selection_signatures) do
        assert(hex(read(game+sig[1],#sig[2]/2))==sig[2],'Selection signature mismatch')
    end
    local final=assert(snapshot(),'Selection context unavailable')
    assert(final.fingerprint==s.fingerprint,'State changed before selection')
    local session=pointer(game+0x347cef0)
    local owner=read(session+0xb398,8)
    assert(owner~=string.rep('\0',8) and read(s.board+0x1f8078,8)==owner,'Not local selection owner')
    assert(read(s.board+0x78e60,8)==read(s.board+0x17a298,8),'Selection context not published')
    assert(u(read(s.board+0x78e60,4),0)==s.planet,'Canonical planet differs')
    page(s.board+0x78e60,36,0x20000);page(s.board+0x17a298,36,0x20000)
    assert(op.row>=0 and op.row<110,'Invalid match row')
    emit('SELECT_OPERATION row='..op.row..' id='..op.operation_id..' difficulty='..op.difficulty)
    ffi.cast('void (*)(uintptr_t, uint32_t)',game+0x12d1d40)(0,op.row)
    assert(u(read(s.board+0x78e68,4),0)==op.row,'Native selection rejected')
    assert(u(read(s.board+0x78e6c,4),0)==4294967295,'Mission unexpectedly selected')
    assert(hex(read(s.board+0x78e88,92))==s.active,'Active operation changed on selection')
end
local function init_ui()
    exe=assert(api.module(nil));panel=Panel.new(assert(stingray))
    cursor=make_cursor(ffi)
    gate=make_gate(stingray.Window,check_window)
end
local function tick()
    if stopped then return end
    if not initialized then initialize();init_ui() end
    local tid=tonumber(kernel.GetCurrentThreadId())
    if thread then assert(thread==tid,'Lua update thread changed') else thread=tid end
    local now=api.time()
    if protected then
        assert(pointer(game+0x347cee8)==protected.board,'Board changed during search')
        assert(hex(read(protected.board+0x78e88,92))==protected.active,'Active operation changed')
    end
    if not focus() then
        search:cancel('Game lost focus')
        if router then release('focus lost') end
        keys={};selector=nil;protected=nil;return
    end
    if now-last_poll>=0.25 then
        last_poll=now
        local s,reason=snapshot()
        if s then
            local second=assert(snapshot(),'Context changed between reads')
            if s.fingerprint==second.fingerprint then
                stable=previous==s.fingerprint and stable+1 or 1;previous=s.fingerprint
                s.records=s.operations;s.operations=s.decoded.operations
                latest=stable>=4 and s or nil
                report=stable>=40 and 'Ready - start only when alone on your ship' or 'Waiting for stable operation data'
            else latest=nil;stable=0;previous=nil;report='Waiting for consistent state' end
        else
            latest=nil;stable=0;previous=nil;report=reason
            if reason=='open galactic map' or reason=='select planet' then
                search:cancel('Map closed');if router then release('map closed')end;selector=nil;protected=nil
            end
        end
    end
    if pressed(0x77) then
        if router then search:cancel('Dialog closed');router:close();selector=nil
        elseif latest then
            router=make_router(gate);router:open();visible=true;selection_finished=false
            emit('MODAL_OPEN')
        end
    end
    if not router then return end
    local cx,cy,cw,ch=cursor.client(user32.GetForegroundWindow())
    local width,height=stingray.Gui.resolution()
    local x=cx*width/cw;local y=height-cy*height/ch
    local busy=search.running or (selector and selector.state=='pending')
    local model={running=not not busy,ready=latest~=nil and stable>=40 and not busy,
        difficulty=difficulty,calls=search.calls,status=search.status=='idle' and report or search.status}
    local action=router:step(x,y,user32.GetAsyncKeyState(1)<0,Panel.layout(width,height,model).targets)
    if action=='close' then search:cancel('Dialog closed');selector=nil;router:close()
    elseif action=='cancel' then search:cancel();selector=nil
    elseif not busy then
        if action=='clear' then selected={}
        elseif action=='up' then difficulty=math.min(10,difficulty+1)
        elseif action=='down' then difficulty=math.max(1,difficulty-1)
        elseif type(action)=='number' then selected[action]=not selected[action] or nil
        elseif action=='start' and model.ready then
            local ok,err=pcall(function()search:start(latest,difficulty,selected,now)end)
            if ok then
                protected=latest;audited_seed=nil;selector=nil;selection_finished=false
                local names={};for i,opt in ipairs(Search.options)do if selected[i] then names[#names+1]=opt.name end end
                emit('SEARCH_STARTED planet='..latest.planet..' difficulty='..difficulty..' required='..table.concat(names,' + '))
            else search.status=tostring(err) end
        end
    end
    if not router.opened and not router.closing then
        release(selection_finished and 'matched operation selected' or 'dialog closed')
        protected=nil;return
    end
    local temp=stingray.Script.temp_byte_count()
    local ok,err=pcall(function()panel:show(Search.options,selected,face(),{x=x,y=y},model)end)
    stingray.Script.set_temp_byte_count(temp);assert(ok,err)
    if router.closing then return end
    if search.running and latest and audited_seed~=latest.seed then
        audited_seed=latest.seed;emit('CHECK_BATCH seed='..latest.seed..' calls='..search.calls)
        for _,op in ipairs(latest.operations)do if op.difficulty==difficulty then
            local ids={};for _,m in ipairs(op.missions)do ids[#ids+1]=tostring(m.native_type)end
            emit('CANDIDATE row='..op.row..' id='..op.operation_id..' missions='..table.concat(ids,','))
        end end
    end
    local was_running=search.running
    search:advance(latest,now,invoke)
    if was_running and search.match then
        selector=make_selection({select=select_operation,confirm=function(s,row)
            return s.decoded.highlighted_operation==row and u(read(s.board+0x17a2a4,4),0)==4294967295
        end})
        selector:start(assert(latest),search.match,now)
        previous=nil;stable=0;latest=nil;search.status='Match found - selecting operation'
    end
    if selector and selector.state=='pending' then
        local state=selector:poll(latest,now)
        if state=='selected' then
            search.status='Matched operation selected';selection_finished=true;router:close()
            emit('SELECTION_CONFIRMED row='..selector.row..' mission_unselected=true active_preserved=true')
        elseif state=='failed' then search.status=selector.reason;emit('SELECTION_FAILED '..selector.reason)end
    end
    M.native_calls=search.calls;M.status=search.status
    if last_status~=search.status then emit(search.status);last_status=search.status end
end
local function pack(...)return {n=select('#',...),...}end
_G.update=function(...)
    local result=original_update and pack(original_update(...)) or {n=0}
    if not stopped then
        local ok,err=pcall(tick)
        if not ok then
            stopped=true;search:cancel();M.status='STOPPED: '..tostring(err);emit(M.status)
            local restored,why=pcall(function()release('error cleanup')end)
            if not restored then emit('RESTORE_FAILED '..tostring(why))end
        end
    end
    return unpack(result,1,result.n)
end
_G.shutdown=function(...)
    stopped=true;search:cancel('Shutdown');pcall(function()release('shutdown')end)
    if log then pcall(function()log:close()end);log=nil end
    if original_shutdown then return original_shutdown(...)end
end
M.status='waiting_for_update'
emit('Mission Reroller 0.4.1: mouse search; no session call cap; minimum interval=1s; native operation selection')
