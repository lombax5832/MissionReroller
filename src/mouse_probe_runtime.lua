local previous_update,previous_shutdown=rawget(_G,'update'),rawget(_G,'shutdown')
local panel,gate,router,user,exe,cursor
local done=false;local old_key=nil;local started,base_selection,board
local checks={}
local note='Ctrl+Shift+F8 opens mouse test; no rerolls'
local function face()
    local function hash(a)local b=read(a,8);return string.format('%08x%08x',u(b,4),u(b,0))end
    return {font=hash(game+0x3772268),material=hash(pointer(game+0x37c5478)+24),atlas=hash(game+0x3772ee8)}
end
local function check_window()
    for _,sig in ipairs(window_signatures) do
        assert(hex(read(exe+sig[1],#sig[2]/2))==sig[2],'Window binding signature mismatch')
    end
    local app=pointer(exe+0x1a10210)
    assert(u(read(app+0x3b8,4),0)==1,'Expected one game window')
    local window=pointer(pointer(app+0x3c0))
    page(window+0x80,10,0x20000)
    local flag=read(window+0x89,1):byte();assert(flag==0 or flag==1,'Invalid focus flag')
    return tostring(window)
end
local function restore(reason)
    if gate then assert(gate:release(),'Restore failed') end
    if router then router=nil end
    if panel then panel:clear() end
    emit('RESTORED '..reason);note=reason
end
local function tick()
    if done then return end
    if not initialized then
        initialize();exe=assert(api.module(nil));panel=Panel.new(stingray)
        ffi.cdef[[
            int16_t GetAsyncKeyState(int);
            void *GetForegroundWindow(void);
            uint32_t GetWindowThreadProcessId(void *,uint32_t *);
            uint32_t GetCurrentProcessId(void);
        ]]
        user=ffi.load('user32');cursor=make_cursor(ffi)
        gate=make_gate(stingray.Window,check_window)
    end
    local hwnd=user.GetForegroundWindow();local pid=ffi.new('uint32_t[1]')
    user.GetWindowThreadProcessId(hwnd,pid)
    if pid[0]~=kernel.GetCurrentProcessId() then
        if router then restore('game lost focus') end
        old_key=nil;return
    end
    local key=user.GetAsyncKeyState(0x11)<0 and user.GetAsyncKeyState(0x10)<0 and user.GetAsyncKeyState(0x77)<0
    local trigger=key and old_key==false;old_key=key
    local now=api.time()
    if trigger and not router then
        local s=assert(snapshot(),'Select a planet on the map first')
        board=s.board or pointer(game+0x347cee8)
        router=make_router(gate);router:open();started=now
        base_selection=read(board+0x17a298,20)
        emit('CANDIDATE_GATE_ACQUIRED native_reseeds=0');note='Mouse preview; auto-close in 60s.'
    elseif trigger and router then router:close() end
    if not router then return end
    if now-started>60 then router:close() end
    assert(pointer(game+0x347cee8)==board,'Board changed')
    local screen=read(pointer(game+0x347ce28)+0x429c,24);local n=u(screen,20)
    assert(n>=1 and n<=5 and u(screen,(n-1)*4)==15,'Map closed during mouse test')
    local selection=read(board+0x17a298,20)
    if now-started<0.5 then base_selection=selection
    elseif selection~=base_selection then
        restore('BLOCKING_FAILED: underlying map selection changed');done=true;return
    end
    local width,height=stingray.Gui.resolution()
    local targets=Panel.layout(width,height).targets
    local cx,cy,cw,ch=cursor.client(hwnd)
    local x=cx*width/cw;local y=height-cy*height/ch
    local action=router:step(x,y,user.GetAsyncKeyState(1)<0,targets)
    if action=='close' then router:close()
    elseif action=='clear' then checks={};emit('CLICK clear selection')
    elseif action then checks[action]=not checks[action];emit('CLICK checkbox='..action..' value='..tostring(checks[action])) end
    if not router.opened and not router.closing then restore('dialog closed; Ctrl+Shift+F8 to reopen');return end
    local temp=stingray.Script.temp_byte_count();local ok,err=pcall(function()panel:show(Search.options,checks,face(),{x=x,y=y})end)
    stingray.Script.set_temp_byte_count(temp);assert(ok,err)
end
local function pack(...)return {n=select('#',...),...}end
_G.update=function(...)
    local result=previous_update and pack(previous_update(...)) or {n=0}
    if not done then
        local ok,err=pcall(tick)
        if not ok then
            emit('MOUSE_TEST_STOP '..tostring(err))
            local restored,why=pcall(function()restore('error cleanup')end)
            if not restored then emit('RESTORE_FAILED '..tostring(why))end
            done=true
        end
    end
    return unpack(result,1,result.n)
end
_G.shutdown=function(...)
    pcall(function()restore('shutdown')end)
    if log then pcall(function()log:close()end);log=nil end
    if previous_shutdown then return previous_shutdown(...)end
end
emit('Mouse test 0.2.1 ready; Ctrl+Shift+F8; native cursor; reopenable; no reseed calls')
