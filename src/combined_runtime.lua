local original_update,original_shutdown=rawget(_G,'update'),rawget(_G,'shutdown')
local search=Search.new({max_calls=false,interval=1})
local panel,thread,latest,previous,stable,last_poll=nil,nil,nil,nil,0,-math.huge
local visible,stopped=false,false
local cursor,difficulty,selected=1,10,{}
local keys={}
local protected,report,last_status=nil,'Select a planet; Ctrl+F8 opens filters',nil
local audited_seed
local gate,router,exe,selector
local selection_finished=false
local function invoke(s)
    assert(hex(read(game+0x12d5670,#expected_code/2))==expected_code,'helper signature changed')
    local final=assert(snapshot(),'Context unavailable at call')
    assert(final.fingerprint==s.fingerprint and final.context==s.context,'Context changed at call')
    emit('RESEED '..search.calls..' before_seed='..s.seed..' active='..s.active)
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
