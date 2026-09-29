local original_update,original_shutdown=rawget(_G,'update'),rawget(_G,'shutdown')
local search=Search.new()
local panel,thread,latest,previous,stable,last_poll=nil,nil,nil,nil,0,-math.huge
local visible,stopped=false,false
local cursor,difficulty,selected=1,10,{}
local keys={}
local protected,report,last_status=nil,'Select a planet; Ctrl+F8 opens filters',nil
local audited_seed
local function invoke(s)
    assert(hex(read(game+0x12d5670,#expected_code/2))==expected_code,'helper signature changed')
    local final=assert(snapshot(),'Context unavailable at call')
    assert(final.fingerprint==s.fingerprint and final.context==s.context,'Context changed at call')
    emit('RESEED '..search.calls..'/5 before_seed='..s.seed..' active='..s.active)
    ffi.cast('void (*)(void *, uint8_t, uintptr_t, uint8_t)',game+0x12d5670)(s.board,1,0,0)
    assert(hex(read(s.board+0x78e88,92))==s.active,'Active operation changed in helper')
    emit('RESEED_RETURN canonical_seed='..u(read(s.board+0x78e84,4),0))
    previous=nil;stable=0;latest=nil
end
local function focus()
    local pid=ffi.new('uint32_t[1]')
    user32.GetWindowThreadProcessId(user32.GetForegroundWindow(),pid)
    return pid[0]==kernel.GetCurrentProcessId()
end
local function pressed(key)
    local down=user32.GetAsyncKeyState(0x11)<0 and user32.GetAsyncKeyState(0x10)<0
        and user32.GetAsyncKeyState(key)<0
    local old=keys[key];keys[key]=down
    return old==false and down -- Require a released sample first.
end
local function face()
    local function hash(a)local b=read(a,8);return string.format('%08x%08x',u(b,4),u(b,0))end
    local f={font=hash(game+0x3772268),material=hash(pointer(game+0x37c5478)+24),atlas=hash(game+0x3772ee8)}
    for _,v in pairs(f) do assert(v~='0000000000000000','Font not ready') end
    return f
end
local function draw()
    if not visible then panel:clear();return end
    local lines={'REROLL OPERATIONS - EXPERIMENT',
        'Planet '..(latest and latest.planet or '?')..'   Difficulty '..difficulty..'   Calls '..search.calls..'/5',
        'Require ALL checked types in ONE operation:',
        'Hold Ctrl+Shift: F3/F4 move, F5 toggle'}
    for i,opt in ipairs(Search.options) do
        lines[#lines+1]=(i==cursor and '> ' or '  ')..(selected[i] and '[x] ' or '[ ] ')..opt.name
    end
    lines[#lines+1]='Ctrl+Shift+F6/F7: difficulty -/+   F9: start'
    lines[#lines+1]='Ctrl+Shift+F10: cancel    Ctrl+Shift+F8: close'
    lines[#lines+1]='Modifiers / constellations: unavailable in this test'
    lines[#lines+1]='Common mission types; not a complete legal catalogue'
    lines[#lines+1]='Start confirms you are alone on your own ship'
    lines[#lines+1]=report:sub(1,76)
    lines[#lines+1]=search.status:sub(1,76)
    if search.match then
        local ids={};for _,m in ipairs(search.match.missions) do ids[#ids+1]=tostring(m.native_type) end
        lines[#lines+1]='Match: operation '..search.match.operation_id..' row '..search.match.row..' mission IDs '..table.concat(ids,',')
    end
    assert(panel:show(lines,face()),'GUI world unavailable')
end
local function tick()
    if stopped then return end
    if not initialized then initialize();panel=make_panel(assert(stingray,'Game GUI unavailable')) end
    local tid=tonumber(kernel.GetCurrentThreadId())
    if thread then assert(thread==tid,'Lua update thread changed') else thread=tid end
    local now=api.time()
    if protected then
        assert(pointer(game+0x347cee8)==protected.board,'Board changed during experiment')
        assert(hex(read(protected.board+0x78e88,92))==protected.active,'Active operation changed; experiment stopped')
    end
    if not focus() then
        keys={};visible=false;search:cancel('Game lost focus');panel:clear();return
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
                report=stable>=40 and 'Ready for a bounded search' or 'Waiting for stable map samples'
            else latest=nil;stable=0;previous=nil;report='State changed during read' end
        else
            latest=nil;stable=0;previous=nil;report=reason
            if reason=='open galactic map' or reason=='select planet' then
                visible=false;search:cancel('Map closed or planet unselected');panel:clear()
            end
        end
    end
    local toggle=pressed(0x77)
    local up,down,toggle_type=pressed(0x72),pressed(0x73),pressed(0x74)
    local lower,higher,start,cancel=pressed(0x75),pressed(0x76),pressed(0x78),pressed(0x79)
    if toggle and latest then visible=not visible;if not visible then search:cancel('Dialog closed') end end
    if visible then
        if cancel then search:cancel() end
        if not search.running then
            if up then cursor=(cursor-2)%#Search.options+1 end
            if down then cursor=cursor%#Search.options+1 end
            if toggle_type then selected[cursor]=not selected[cursor] or nil end
            if lower then difficulty=math.max(1,difficulty-1) end
            if higher then difficulty=math.min(10,difficulty+1) end
            if start and latest and stable>=40 then
                local ok,err=pcall(function()search:start(latest,difficulty,selected,now)end)
                if ok then
                    protected=protected or latest;audited_seed=nil
                    local names={}
                    for i,opt in ipairs(Search.options) do if search.required[i] then names[#names+1]=opt.name end end
                    emit('SEARCH_STARTED planet='..latest.planet..' difficulty='..difficulty..' required='..table.concat(names,' + '))
                else report=tostring(err) end
            end
        end
    end
    -- Render successfully before authorizing any native action from this frame.
    local temp=stingray.Script.temp_byte_count()
    local ok,err=pcall(draw)
    stingray.Script.set_temp_byte_count(temp)
    assert(ok,err)
    if search.running and latest and audited_seed~=latest.seed then
        audited_seed=latest.seed
        emit('CHECK_BATCH seed='..latest.seed..' calls='..search.calls)
        for _,op in ipairs(latest.operations) do
            if op.difficulty==search.difficulty then
                local ids={}
                for _,mission in ipairs(op.missions) do ids[#ids+1]=tostring(mission.native_type) end
                emit('CANDIDATE row='..op.row..' operation_id='..op.operation_id..' missions='..table.concat(ids,','))
            end
        end
    end
    search:advance(latest,now,invoke)
    M.native_calls=search.calls;M.status=search.status
    if last_status~=search.status then emit(search.status);last_status=search.status end
end
local function pack(...)return {n=select('#',...),...}end
_G.update=function(...)
    local result=original_update and pack(original_update(...)) or {n=0}
    if not stopped then
        local ok,err=pcall(tick)
        if not ok then
            stopped=true;search:cancel('STOPPED: '..tostring(err))
            search.status='STOPPED: '..tostring(err);M.status=search.status
            emit(search.status);if panel then pcall(function()panel:clear()end)end
        end
    end
    return unpack(result,1,result.n)
end
_G.shutdown=function(...)
    stopped=true;search:cancel('Shutdown')
    if panel then pcall(function()panel:clear()end)end
    if log then pcall(function()log:close()end);log=nil end
    if original_shutdown then return original_shutdown(...) end
end
M.status='waiting_for_update'
emit('Mission Reroller Experiment 0.3.1 loaded; Ctrl+Shift+F8; five-call session budget')
