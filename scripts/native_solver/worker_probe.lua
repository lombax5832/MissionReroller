-- Worker Thread Probe: research tool for Bingus Shared Loader v16+ / API 1.
-- docs/NATIVE_SOLVER_RESEARCH.md; test plan docs/WORKER_PROBE_TEST.md.
--
-- Answers in game whether an addon can run the seed solver's walk in extra
-- LuaJIT VMs on thread-pool threads, and how much address space below 2 GB
-- (where a non-GC64 LuaJIT keeps every heap) that costs. Each worker is a
-- fresh luaL_newstate from the game's own lua51.dll, set up with
-- seed_solver_math.lua (which scripts/native_solver/build_worker_probe.py
-- puts before this text as SEED_SOLVER_MATH) and started on a Windows
-- thread-pool thread at an FFI callback it created in itself. Machine code
-- comes only from lua51.dll's JIT.
--
-- It reads memory only through VirtualQuery, writes no game memory, reads
-- no input and changes nothing in the game. Remove it after the test.
if rawget(_G,'WorkerThreadProbe')then return end
local VERSION='0.1.0'
local state={version=VERSION,status='starting',run_index=0,active=false}
rawset(_G,'WorkerThreadProbe',state)

local loader=rawget(_G,'CowboyBingusModLoader')
local log
pcall(function()log=loader.open_log('WorkerThreadProbe.log')end)
local function emit(s)
    if log then pcall(function()log:write(s..'\n');log:flush()end)end
end
if type(loader)~='table' or (tonumber(loader.api) or 0)<1 or (tonumber(loader.version) or 0)<16 then
    state.status='stopped'
    emit('STOPPED: Bingus Shared Loader v16 / API 1 or newer is required')
    return
end

-- Runs, in order: the first `first` seconds after the first frame, each
-- next one `gap` seconds after the previous one closed. The last one runs
-- until the game shuts down (or its seconds pass), to test the join.
local SCHEDULE=rawget(_G,'WorkerThreadProbeSchedule') or {first=60,gap=20,runs={
    {workers=1,seconds=10},{workers=4,seconds=10},{workers=1,seconds=900}}}
local LOW=2^31 -- non-GC64 LuaJIT heaps live below 2 GB
local LUA_GLOBALSINDEX,LUA_GCCOLLECT,LUA_GCCOUNT,LUA_GCSETPAUSE=-10002,2,3,6
local WAIT_OBJECT_0,MEM_FREE,MEM_PRIVATE=0,0x10000,0x20000

-- The worker VM's chunk. It shares only `probe_worker_t` memory with this
-- VM; its own ffi.cdef cannot clash with other addons, since it is a
-- separate VM. The callback is wrapped whole in pcall: an error escaping a
-- LuaJIT callback would end the process.
local WORKER=[==[
local math_source,shared_address,index,seconds,event_address=...
local ffi=require('ffi')
ffi.cdef[[
typedef struct { int32_t stop, done, failed, priority; double steps, answers, seconds, heap_kb, peak_kb; } probe_worker_t;
void SetEventWhenCallbackReturns(void *instance, void *event);
int CallbackMayRunLong(void *instance);
void *GetCurrentThread(void);
int GetThreadPriority(void *thread);
int SetThreadPriority(void *thread, int priority);
int QueryPerformanceCounter(int64_t *count);
int QueryPerformanceFrequency(int64_t *frequency);
]]
local C=ffi.C
local Math=assert(loadstring(math_source,'=seed_solver_math.lua'))()
local shared=ffi.cast('probe_worker_t *',shared_address)+index
local event=ffi.cast('void *',event_address)
local counter=ffi.new('int64_t[1]')
C.QueryPerformanceFrequency(counter)
local frequency=tonumber(counter[0])
local function clock()C.QueryPerformanceCounter(counter);return tonumber(counter[0])/frequency end
-- The solver's work: starts whose third output lies in the lowest eighth,
-- walked as seed_solver_chain.lua walks a root draw; each start's fifth
-- output inverted back, which must give the start again. The stop flag is
-- read after a C call each batch, so the JIT cannot keep it in a register.
local function body()
    local walk,invert,out=Math.walk(3,0,536870911),Math.inverter(5),{}
    local s,off=walk.start(index*7919)
    local started,steps,answers=clock(),0,0
    while true do
        for _=1,4096 do
            if not s or s>=4294967296 then s,off=walk.start(0)end
            local n=invert(Math.output(s,5),out)
            local found=false
            for i=1,n do if out[i]==s then found=true end end
            if not found then error('inversion missed start '..s)end
            answers,steps=answers+n,steps+1
            s,off=walk.advance(s,off)
        end
        local t=clock()-started
        local kb=collectgarbage('count')
        shared.steps,shared.answers,shared.seconds,shared.heap_kb=steps,answers,t,kb
        if kb>shared.peak_kb then shared.peak_kb=kb end
        if shared.stop~=0 or t>=seconds then return end
    end
end
PROBE_ENTRY=ffi.cast('void (*)(void *, void *)',function(instance)
    local ok,err=pcall(function()
        -- The event is set only once this callback has returned, so the
        -- probe never closes this VM while LuaJIT is still leaving it.
        C.SetEventWhenCallbackReturns(instance,event)
        C.CallbackMayRunLong(instance)
        local thread=C.GetCurrentThread()
        local priority=C.GetThreadPriority(thread)
        shared.priority=priority
        C.SetThreadPriority(thread,-1) -- THREAD_PRIORITY_BELOW_NORMAL
        local walked,why=pcall(body)
        -- Pool threads are shared with the game: give the priority back.
        C.SetThreadPriority(thread,priority)
        if not walked then error(why,0)end
    end)
    if not ok then PROBE_ERROR=tostring(err);shared.failed=1 end
    shared.done=1
end)
return tonumber(ffi.cast('intptr_t',PROBE_ENTRY))
]==]

local ffi,K,L51,now,shared_type
local function initialize()
    ffi=require('ffi')
    -- Resolved by address and called through unnamed pointers taking void *,
    -- as src/window_cursor.lua does: the first ffi.cdef of a name wins VM-wide.
    ffi.cdef[[void *GetModuleHandleA(const char *); void *GetProcAddress(void *, const char *);]]
    local kernel=ffi.load('kernel32')
    local function importer(module_name)
        local module=kernel.GetModuleHandleA(module_name)
        assert(module~=nil,module_name..' is not loaded')
        return function(name,signature)
            local address=kernel.GetProcAddress(module,name)
            assert(address~=nil,name..' is unavailable')
            return ffi.cast(signature,address)
        end,module
    end
    local k=importer('kernel32.dll')
    K={query=k('VirtualQuery','size_t (*)(void *, void *, size_t)'),
        submit=k('TrySubmitThreadpoolCallback','int (*)(void *, void *, void *)'),
        create_event=k('CreateEventA','void *(*)(void *, int, int, void *)'),
        wait=k('WaitForSingleObject','uint32_t (*)(void *, uint32_t)'),
        close_handle=k('CloseHandle','int (*)(void *)'),
        sleep=k('Sleep','void (*)(uint32_t)'),
        qpc=k('QueryPerformanceCounter','int (*)(void *)'),
        qpf=k('QueryPerformanceFrequency','int (*)(void *)')}
    local l,lua51=importer('lua51.dll')
    L51={newstate=l('luaL_newstate','void *(*)(void)'),
        openlibs=l('luaL_openlibs','void (*)(void *)'),
        loadbuffer=l('luaL_loadbuffer','int (*)(void *, const char *, size_t, const char *)'),
        pcall=l('lua_pcall','int (*)(void *, int, int, int)'),
        tonumber=l('lua_tonumber','double (*)(void *, int)'),
        tolstring=l('lua_tolstring','const char *(*)(void *, int, void *)'),
        getfield=l('lua_getfield','void (*)(void *, int, const char *)'),
        settop=l('lua_settop','void (*)(void *, int)'),
        gc=l('lua_gc','int (*)(void *, int, int)'),
        close=l('lua_close','void (*)(void *)')}
    shared_type=ffi.typeof('struct { int32_t stop, done, failed, priority; double steps, answers, seconds, heap_kb, peak_kb; }[?]')
    local counter=ffi.new('int64_t[1]')
    assert(K.qpf(counter)~=0,'No performance counter')
    local frequency=tonumber(counter[0])
    now=function()K.qpc(counter);return tonumber(counter[0])/frequency end
    return lua51
end
local function address(p)return tonumber(ffi.cast('intptr_t',p))end

-- Address space below 2 GB, read with VirtualQuery only.
local info
local function scan()
    info=info or ffi.new('uint8_t[48]') -- MEMORY_BASIC_INFORMATION
    local started=now()
    local at,used,private,free,largest,regions=0x10000,0,0,0,0,0
    while at<LOW do
        if K.query(ffi.cast('void *',at),info,48)==0 then break end
        local base=tonumber(ffi.cast('uint64_t *',info)[0])
        local size=tonumber(ffi.cast('uint64_t *',info+24)[0])
        if size<=0 then break end
        local part=math.min(size,LOW-base)
        regions=regions+1
        if ffi.cast('uint32_t *',info+32)[0]==MEM_FREE then
            free=free+part
            if part>largest then largest=part end
        else
            used=used+part
            if ffi.cast('uint32_t *',info+40)[0]==MEM_PRIVATE then private=private+part end
        end
        at=base+size
    end
    return {used=used,private=private,free=free,largest=largest,regions=regions,ms=(now()-started)*1000}
end
local MB=2^20
local function log_memory(phase,run,m)
    emit(string.format('PROBE_MEMORY run=%d phase=%s used_mb=%.1f private_mb=%.1f free_mb=%.1f largest_free_mb=%.1f regions=%d scan_ms=%.2f main_heap_kb=%.0f',
        run,phase,m.used/MB,m.private/MB,m.free/MB,m.largest/MB,m.regions,m.ms,collectgarbage('count')))
    return m
end

local active -- the run whose workers exist
local function release(w)
    -- Only for a worker whose callback never started or has returned.
    if w.L then L51.close(w.L);w.L=nil end
    if w.event then K.close_handle(w.event);w.event=nil end
end
local function start_run(index,spec)
    local run={index=index,spec=spec,workers={},shared=ffi.new(shared_type,spec.workers),last_progress=0,last_scan=0}
    run.before=log_memory('before',index,scan())
    active=run;state.active=true
    local started=now()
    local ok,err=pcall(function()
        for i=0,spec.workers-1 do
            local w={}
            run.workers[#run.workers+1]=w
            w.L=L51.newstate()
            if w.L==nil then w.L=nil;error('luaL_newstate failed')end
            L51.openlibs(w.L)
            w.event=K.create_event(nil,1,0,nil)
            if w.event==nil then w.event=nil;error('CreateEventA failed')end
            local chunk=string.format('return (function(...)\n%s\nend)(%q,%.17g,%d,%.17g,%.17g)',WORKER,SEED_SOLVER_MATH,
                address(run.shared),i,spec.seconds,address(w.event))
            if L51.loadbuffer(w.L,chunk,#chunk,'=worker_probe')~=0 or L51.pcall(w.L,0,1,0)~=0 then
                error('worker set-up: '..ffi.string(L51.tolstring(w.L,-1,nil)))
            end
            w.entry=ffi.cast('void *',ffi.cast('intptr_t',L51.tonumber(w.L,-1)))
            L51.settop(w.L,0)
            -- Drop the set-up's garbage and collect sooner while walking.
            L51.gc(w.L,LUA_GCCOLLECT,0);L51.gc(w.L,LUA_GCSETPAUSE,110)
            w.heap_kb=L51.gc(w.L,LUA_GCCOUNT,0)
        end
    end)
    run.setup_ms=(now()-started)*1000
    if not ok then
        for _,w in ipairs(run.workers)do release(w)end
        active=nil;state.active=false
        error(err,0)
    end
    run.setup=log_memory('setup',index,scan())
    run.started=now()
    for _,w in ipairs(run.workers)do
        if K.submit(w.entry,nil,nil)==0 then
            run.stopping=true
            emit('PROBE_SUBMIT_FAILED run='..index)
            break
        end
        w.submitted=true
    end
    for i=0,spec.workers-1 do run.shared[i].stop=run.stopping and 1 or 0 end
    emit(string.format('PROBE_START run=%d workers=%d seconds=%g setup_ms=%.1f worker_heap_kb=%.0f',index,spec.workers,
        spec.seconds,run.setup_ms,run.workers[1].heap_kb))
end
local function totals(run)
    local steps,answers,seconds,heap,peak,priority=0,0,0,0,0,nil
    for i=0,run.spec.workers-1 do
        local s=run.shared[i]
        steps,answers=steps+s.steps,answers+s.answers
        seconds,heap,peak=math.max(seconds,s.seconds),heap+s.heap_kb,math.max(peak,s.peak_kb)
        priority=priority or s.priority
    end
    return steps,answers,seconds,heap,peak,priority
end
-- Returns true once every worker's callback has returned (or never ran).
local function returned(run,ms)
    local all=true
    for _,w in ipairs(run.workers)do
        if w.submitted and not w.returned then
            if K.wait(w.event,ms or 0)==WAIT_OBJECT_0 then w.returned=true else all=false end
        end
    end
    return all
end
local function finish(run)
    run.walked=log_memory('walked',run.index,scan())
    local failed,errors=0,{}
    for i,w in ipairs(run.workers)do
        if run.shared[i-1].failed~=0 then
            failed=failed+1
            L51.getfield(w.L,LUA_GLOBALSINDEX,'PROBE_ERROR')
            local message=L51.tolstring(w.L,-1,nil)
            errors[#errors+1]=message~=nil and ffi.string(message) or '?'
        end
        release(w)
    end
    collectgarbage()
    local closed=log_memory('closed',run.index,scan())
    local steps,answers,seconds,_,peak,priority=totals(run)
    emit(string.format('PROBE_DONE run=%d workers=%d steps=%.0f answers=%.0f seconds=%.2f steps_per_second=%.0f peak_worker_heap_kb=%.0f added_mb=%.1f held_after_close_mb=%.1f pool_priority=%s failed=%d%s',
        run.index,run.spec.workers,steps,answers,seconds,seconds>0 and steps/seconds or 0,peak,
        (run.walked.used-run.before.used)/MB,(closed.used-run.before.used)/MB,tostring(priority),failed,
        #errors>0 and ' error='..table.concat(errors,' | ') or ''))
    active=nil;state.active=false
end
local function request_stop(run)
    run.stopping=true
    for i=0,run.spec.workers-1 do run.shared[i].stop=1 end
end
local function poll(t)
    local run=active
    local done=returned(run)
    if done then finish(run);return true end
    if t-run.last_progress>=1 then
        run.last_progress=t
        local steps,_,seconds,heap,peak=totals(run)
        emit(string.format('PROBE_PROGRESS run=%d elapsed_s=%.1f steps=%.0f steps_per_second=%.0f heap_kb=%.0f peak_kb=%.0f',
            run.index,t-run.started,steps,seconds>0 and steps/seconds or 0,heap,peak))
    end
    if t-run.last_scan>=2 then run.last_scan=t;log_memory('walk',run.index,scan())end
    return false
end

local next_at,stopped
local function first_frame()
    local lua51=initialize()
    local jit_state=rawget(_G,'jit')
    local processors='?'
    pcall(function()processors=tostring(os.getenv('NUMBER_OF_PROCESSORS'))end)
    emit(string.format('WORKER_PROBE version=%s jit=%s %s loader=v%s lua51=%s processors=%s',VERSION,
        tostring(jit_state and jit_state.status and jit_state.status()),tostring(jit_state and jit_state.version),
        tostring(loader.version),tostring(lua51):match('0x%x+') or '?',processors))
    log_memory('startup',0,scan())
    next_at=now()+SCHEDULE.first
    emit(string.format('PROBE_SCHEDULE runs=%d first_in_s=%g gap_s=%g',#SCHEDULE.runs,SCHEDULE.first,SCHEDULE.gap))
    state.status='waiting'
end
local function tick()
    if not now then first_frame()end
    local t=now()
    if active then
        if poll(t)then
            next_at=t+SCHEDULE.gap
            if state.run_index>=#SCHEDULE.runs then state.status='finished';emit('PROBE_FINISHED')end
        end
    elseif not stopped and state.run_index<#SCHEDULE.runs and t>=next_at then
        state.run_index=state.run_index+1
        state.status='running'
        start_run(state.run_index,SCHEDULE.runs[state.run_index])
    end
end

local original_update,original_shutdown=rawget(_G,'update'),rawget(_G,'shutdown')
local function pack(...)return {n=select('#',...),...}end
_G.update=function(...)
    local result=original_update and pack(original_update(...)) or {n=0}
    if not state.abandoned then
        local ok,err=pcall(tick)
        if not ok then
            if stopped then
                -- A second failure: leave the workers alone rather than risk
                -- closing a VM a thread may still be in.
                state.abandoned=true
                emit('PROBE_ABANDONED: '..tostring(err))
            else
                stopped=true;state.status='stopped'
                emit('STOPPED: '..tostring(err))
                if active then pcall(request_stop,active)end
            end
        end
    end
    return unpack(result,1,result.n)
end
_G.shutdown=function(...)
    stopped=true
    pcall(function()
        local run=active
        if not run or state.abandoned then return end
        request_stop(run)
        local started=now()
        -- The walk checks its stop flag every 4,096 steps (a few ms).
        while not returned(run,5) do
            if now()-started>3 then
                emit(string.format('PROBE_SHUTDOWN joined=0 run=%d waited_s=%.1f; worker VMs left open',run.index,now()-started))
                return
            end
        end
        local waited=now()-started
        finish(run)
        emit(string.format('PROBE_SHUTDOWN joined=1 run=%d waited_ms=%.0f',run.index,waited*1000))
    end)
    if log then pcall(function()log:close()end);log=nil end
    if original_shutdown then return original_shutdown(...)end
end
emit('WorkerThreadProbe '..VERSION..' loaded; waiting for the first frame')
