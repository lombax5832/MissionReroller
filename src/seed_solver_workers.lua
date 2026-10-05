-- The seed solver's walk in worker VMs (docs/NATIVE_SOLVER_RESEARCH.md,
-- docs/WORKER_PROBE_TEST.md). Each worker is a fresh LuaJIT VM from the
-- game's own lua51.dll, holding seed_solver_math.lua, seed_solver_chain.lua
-- and seed_solver_codec.lua as text (the build passes them in `sources`) and
-- the request's paths as codec text. It runs on a Windows thread-pool thread
-- at below-normal priority, started at an FFI callback it created in
-- itself. The workers share each job's random base and split its starts
-- into equal arcs, one each (seed_solver_chain.lua arc), so between them
-- they walk every start once; candidates (seed and row) come back through a
-- ring in FFI memory. The caller's VM
-- applies `accept` (the Day / Night ID check, a closure over game data) and
-- predicts each candidate as before.
--
-- Every heap of this non-GC64 LuaJIT lives below 2 GB, where the game had
-- about 30 MB free (docs/WORKER_PROBE_TEST.md): start() scans that range
-- with VirtualQuery and starts only as many workers as fit beside a reserve,
-- and stops a worker whose heap passes a cap. A worker VM is closed only
-- once the pool has set its callback-return event, never while its thread
-- may still be in it. No memory is written outside the pool's own buffers.
--
-- sources = {math=, chain=, codec=} (the three files' text). Returns
-- {pool(ffi, options) -> pool | nil, reason}.
return function(sources)
    local W={}
    local Codec=assert(loadstring(sources.codec,'=seed_solver_codec.lua'))()
    local LOW=2^31
    local LUA_GLOBALSINDEX=-10002
    local MEM_FREE,WAIT_OBJECT_0=0x10000,0
    local CAP=256 -- candidates a worker may hold before it waits for the caller
    local MB=2^20
    local DEFAULTS={max_workers=8,reserve_mb=16,largest_mb=2,heap_cap_kb=16384,
        base_kb=512,text_factor=8}
    W.DEFAULTS=DEFAULTS

    -- The worker VM's chunk: its own VM, so its ffi.cdef cannot clash with
    -- other addons. The callback is wrapped whole in pcall, since an error
    -- escaping a LuaJIT callback ends the process.
    local WORKER=[==[
-- Texts arrive as (address, length) of read-only buffers the pool keeps
-- alive until this VM is closed; they are copied on the worker's thread.
local texts,shared_address,start,step_limit,event_address,cap,index,count=...
local ffi=require('ffi')
ffi.cdef[[
typedef struct { int32_t stop, finished, failed, exhausted, head, tail, limited, pad;
    double steps, heap_kb, peak_kb, expected, setup_kb; double seed[256]; int32_t row[256]; } solver_worker_t;
void SetEventWhenCallbackReturns(void *instance, void *event);
int CallbackMayRunLong(void *instance);
void *GetCurrentThread(void);
int GetThreadPriority(void *thread);
int SetThreadPriority(void *thread, int priority);
uint32_t GetCurrentThreadId(void);
void Sleep(uint32_t ms);
// The thread pool's simple callback (PTP_SIMPLE_CALLBACK): instance, context.
typedef void (*solver_worker_entry_t)(void *, void *);
]]
local C=ffi.C
local shared=ffi.cast('solver_worker_t *',shared_address)
local function text(name)
    local t=texts[name]
    return ffi.string(ffi.cast('const char *',t[1]),t[2])
end
-- Loads the modules and decodes the paths: on the worker's thread, so its
-- cost (it grows with the request) never lands in the game's frame.
local function body()
    local Math=assert(loadstring(text('math'),'=seed_solver_math.lua'))()
    local Chain=assert(loadstring(text('chain'),'=seed_solver_chain.lua'))()(Math)
    local Codec=assert(loadstring(text('codec'),'=seed_solver_codec.lua'))()
    local paths,rows,planet=Codec.decode(text('data'))
    texts=nil
    -- Drop the set-up's garbage and collect sooner while walking.
    collectgarbage('collect');collectgarbage('setpause',110)
    shared.setup_kb=collectgarbage('count')
    -- Each job's base as SeedSolver.starts gives it, from the seed every
    -- worker of the search shares; this worker walks arc `index` of `count`.
    local n=start
    local function random()n=(n+1)%4294967296;return Math.output(n,1)end
    local chain=Chain.new({paths=paths,rows=rows,planet=planet,random=random,arc={index=index,count=count}})
    while true do
        local budget=4096
        if step_limit>0 then
            budget=math.min(budget,step_limit-chain.steps)
            -- A step limit covers part of the space only: limited, not exhausted.
            if budget<=0 then shared.limited=1;return end
        end
        local seed,done,row=chain.next(budget)
        shared.steps,shared.expected=chain.steps,chain.expected()
        if seed then
            while shared.head-shared.tail>=cap do
                if shared.stop~=0 then return end
                C.Sleep(1)
            end
            local i=shared.head%cap
            shared.seed[i],shared.row[i]=seed,row
            -- A C call between the data and the index keeps the JIT from
            -- reordering them; x64 keeps stores in order.
            C.GetCurrentThreadId()
            shared.head=shared.head+1
        end
        if done then shared.exhausted=1;return end
        local kb=collectgarbage('count')
        shared.heap_kb=kb
        if kb>shared.peak_kb then shared.peak_kb=kb end
        -- After a C call, so the stop flag is read from memory each time.
        C.GetCurrentThreadId()
        if shared.stop~=0 then return end
    end
end
SOLVER_WORKER_ENTRY=ffi.cast('solver_worker_entry_t',function(instance)
    local ok,err=pcall(function()
        -- Set once this callback has returned: only then may the VM close.
        C.SetEventWhenCallbackReturns(instance,ffi.cast('void *',event_address))
        C.CallbackMayRunLong(instance)
        local thread=C.GetCurrentThread()
        local priority=C.GetThreadPriority(thread)
        C.SetThreadPriority(thread,-1) -- THREAD_PRIORITY_BELOW_NORMAL
        local walked,why=pcall(body)
        -- Pool threads are shared with the game: give the priority back.
        C.SetThreadPriority(thread,priority)
        if not walked then error(why,0)end
    end)
    if not ok then SOLVER_WORKER_ERROR=tostring(err);shared.failed=1 end
    shared.finished=1
end)
return tonumber(ffi.cast('intptr_t',SOLVER_WORKER_ENTRY))
]==]
    W.WORKER=WORKER

    -- options: max_workers, reserve_mb, largest_mb, heap_cap_kb, base_kb,
    -- text_factor (DEFAULTS), processors (default: the system's count).
    function W.pool(ffi,options)
        options=options or {}
        for k,v in pairs(DEFAULTS)do if options[k]==nil then options[k]=v end end
        -- Resolved by address and called through unnamed pointers taking
        -- void *, as src/window_cursor.lua does: the first ffi.cdef of a
        -- name wins for the whole VM.
        ffi.cdef[[void *GetModuleHandleA(const char *); void *GetProcAddress(void *, const char *);]]
        local kernel=ffi.load('kernel32')
        local function importer(module_name)
            local module=kernel.GetModuleHandleA(module_name)
            if module==nil then return nil end
            return function(name,signature)
                local address=kernel.GetProcAddress(module,name)
                assert(address~=nil,name..' is unavailable')
                return ffi.cast(signature,address)
            end
        end
        local k,l=importer('kernel32.dll'),importer('lua51.dll')
        if not k or not l then return nil,'lua51.dll not loaded'end
        local ok,K,L51=pcall(function()
            return {query=k('VirtualQuery','size_t (*)(void *, void *, size_t)'),
                submit=k('TrySubmitThreadpoolCallback','int (*)(void *, void *, void *)'),
                create_event=k('CreateEventA','void *(*)(void *, int, int, void *)'),
                wait=k('WaitForSingleObject','uint32_t (*)(void *, uint32_t)'),
                close_handle=k('CloseHandle','int (*)(void *)'),
                processors=k('GetActiveProcessorCount','uint32_t (*)(uint16_t)'),
                qpc=k('QueryPerformanceCounter','int (*)(void *)'),
                qpf=k('QueryPerformanceFrequency','int (*)(void *)')},
            {newstate=l('luaL_newstate','void *(*)(void)'),
                openlibs=l('luaL_openlibs','void (*)(void *)'),
                loadbuffer=l('luaL_loadbuffer','int (*)(void *, const char *, size_t, const char *)'),
                pcall=l('lua_pcall','int (*)(void *, int, int, int)'),
                tonumber=l('lua_tonumber','double (*)(void *, int)'),
                tolstring=l('lua_tolstring','const char *(*)(void *, int, void *)'),
                getfield=l('lua_getfield','void (*)(void *, int, const char *)'),
                settop=l('lua_settop','void (*)(void *, int)'),
                gc=l('lua_gc','int (*)(void *, int, int)'),
                close=l('lua_close','void (*)(void *)')}
        end)
        if not ok then return nil,tostring(K)end
        local shared_type=ffi.typeof([=[struct { int32_t stop, finished, failed, exhausted, head, tail, limited, pad;
            double steps, heap_kb, peak_kb, expected, setup_kb; double seed[256]; int32_t row[256]; }[?]]=])
        local counter=ffi.new('int64_t[1]')
        assert(K.qpf(counter)~=0,'No performance counter')
        local frequency=tonumber(counter[0])
        local function now()K.qpc(counter);return tonumber(counter[0])/frequency end
        local processors=options.processors or tonumber(K.processors(0xffff))
        local function address(p)return tonumber(ffi.cast('intptr_t',p))end
        local pool={processors=processors,max_workers=math.max(1,math.min(options.max_workers,math.floor(processors/2)))}
        -- A string in FFI memory: {buffer, length}; the buffer must outlive
        -- every worker that may read it.
        local function buffer(value)
            local b=ffi.new('char[?]',#value)
            ffi.copy(b,value,#value)
            return {b,#value}
        end
        local source_buffers={math=buffer(sources.math),chain=buffer(sources.chain),codec=buffer(sources.codec)}

        -- Address space below 2 GB, read with VirtualQuery only.
        local info=ffi.new('uint8_t[48]') -- MEMORY_BASIC_INFORMATION
        function pool.memory()
            local at,free,largest=0x10000,0,0
            while at<LOW do
                if K.query(ffi.cast('void *',at),info,48)==0 then break end
                local base=tonumber(ffi.cast('uint64_t *',info)[0])
                local size=tonumber(ffi.cast('uint64_t *',info+24)[0])
                if size<=0 then break end
                if ffi.cast('uint32_t *',info+32)[0]==MEM_FREE then
                    local part=math.min(size,LOW-base)
                    free=free+part
                    if part>largest then largest=part end
                end
                at=base+size
            end
            return free,largest
        end

        -- Workers whose search ended; closed once their callbacks return.
        -- active: every source still running, for shutdown.
        local retired,active={},{}
        local function release(w)
            if w.L then L51.close(w.L);w.L=nil end
            if w.event then K.close_handle(w.event);w.event=nil end
        end
        local function returned(w,ms)
            if not w.submitted or w.returned then return true end
            if K.wait(w.event,ms or 0)==WAIT_OBJECT_0 then w.returned=true end
            return w.returned
        end
        -- Only for a worker whose callback has returned: its VM is idle.
        local function error_of(w)
            if w.shared.failed==0 or not w.L or not returned(w)then return nil end
            L51.getfield(w.L,LUA_GLOBALSINDEX,'SOLVER_WORKER_ERROR')
            local message=L51.tolstring(w.L,-1,nil)
            return message~=nil and ffi.string(message) or 'worker failed'
        end
        -- Closes the retired workers whose callbacks have returned; each frame.
        function pool.reap()
            for i=#retired,1,-1 do
                local w=retired[i]
                if returned(w)then
                    w.error=w.error or error_of(w)
                    release(w);table.remove(retired,i)
                end
            end
            return #retired
        end
        -- At shutdown: stops every worker, waits up to `seconds` for their
        -- callbacks and closes those that returned. Returns how many are
        -- left open (their VMs are left for the process exit).
        function pool.shutdown(seconds)
            local deadline=now()+(seconds or 3)
            for source in pairs(active)do source.close()end
            for _,w in ipairs(retired)do w.shared.stop=1 end
            for i=#retired,1,-1 do
                local w=retired[i]
                while not returned(w,5)do if now()>deadline then break end end
                if w.returned or not w.submitted then release(w);table.remove(retired,i)end
            end
            return #retired
        end

        -- spec: Chain.new's spec (paths, rows, planet, random, accept);
        -- step_limit (tests only) stops each worker after that many walk
        -- steps. Returns a chain-like source {next, steps, close, workers
        -- (how many it will run), report()} or nil and the reason no worker
        -- started. Only the first worker starts here; next() starts the rest,
        -- about 2 ms of set-up per call, so no call holds the frame long.
        function pool.start(spec)
            -- spec.checkpoint (the search's pause) splits this set-up so it
            -- stays inside the frame slice.
            local checkpoint=spec.checkpoint or function()end
            pool.reap()
            local started=now()
            local text=Codec.encode(spec.paths,spec.rows,spec.planet,checkpoint)
            checkpoint()
            local free,largest=pool.memory()
            checkpoint()
            local per_kb=options.base_kb+options.text_factor*#text/1024
            local fit=math.floor((free/MB-options.reserve_mb)*1024/per_kb)
            local count=math.min(pool.max_workers,fit)
            local report={free_mb=free/MB,largest_mb=largest/MB,text_kb=#text/1024,per_worker_kb=per_kb,
                processors=processors}
            if largest/MB<options.largest_mb then count=0 end
            if count<1 then
                return nil,string.format('memory below 2 GB: %.1f MB free, largest block %.1f MB',free/MB,largest/MB),report
            end
            local workers={}
            local shared=ffi.new(shared_type,count)
            local data=buffer(text)
            text=nil
            local texts='{'
            for _,name in ipairs({'math','chain','codec'})do
                local b=source_buffers[name]
                texts=texts..string.format('%s={%.17g,%d},',name,address(b[1]),b[2])
            end
            texts=texts..string.format('data={%.17g,%d}}',address(data[1]),data[2])
            checkpoint()
            -- One base for every worker, so their arcs tile each job's starts.
            local base=spec.random()
            -- Builds and submits the next worker; nil and why on failure. Its
            -- set-up runs on its own thread, so this takes well under a
            -- millisecond whatever the request.
            local function spawn()
                local i=#workers
                local w={shared=shared[i],keep=shared,data=data,sources=source_buffers}
                local ok,err=pcall(function()
                    local L=L51.newstate()
                    if L==nil then error('luaL_newstate failed')end
                    w.L=L
                    L51.openlibs(L)
                    local event=K.create_event(nil,1,0,nil)
                    if event==nil then error('CreateEventA failed')end
                    w.event=event
                    local chunk=string.format('return (function(...)\n%s\nend)(%s,%.17g,%.17g,%d,%.17g,%d,%d,%d)',
                        WORKER,texts,address(shared+i),base,spec.step_limit or 0,address(event),CAP,i,count)
                    if L51.loadbuffer(L,chunk,#chunk,'=seed_solver_worker')~=0 or L51.pcall(L,0,1,0)~=0 then
                        error('worker set-up: '..ffi.string(L51.tolstring(L,-1,nil)))
                    end
                    w.entry=ffi.cast('void *',ffi.cast('intptr_t',L51.tonumber(L,-1)))
                    L51.settop(L,0)
                end)
                if not ok then release(w);return nil,tostring(err)end
                if K.submit(w.entry,nil,nil)==0 then release(w);return nil,'thread pool refused the work'end
                w.submitted=true
                workers[#workers+1]=w
                return w
            end
            local first,why=spawn()
            if not first then return nil,why,report end
            checkpoint()
            report.setup_ms=(now()-started)*1000

            local source={workers=count}
            local accept=spec.accept
            local closed,at,calls,spawn_error=false,0,0,nil
            local function retire()
                if closed then return end
                closed=true
                active[source]=nil
                text=nil
                for _,w in ipairs(workers)do
                    w.shared.stop=1
                    if w.L then retired[#retired+1]=w end
                end
                pool.reap()
            end
            -- A candidate seed (then nil and its row), or nil and done once
            -- the space is covered (every planned worker walked its arcs) or
            -- no worker is left (an arc unwalked: the search then scans), or
            -- nil, false, true while the workers have none ready.
            function source.next()
                if closed then return nil,true end
                calls=calls+1
                if #workers<count and not spawn_error then
                    local t=now()
                    repeat
                        local w,err=spawn()
                        if not w then spawn_error=err end
                    until spawn_error or #workers>=count or now()-t>0.002
                    if spawn_error or #workers>=count then text=nil end
                end
                local alive,exhausted=0,0
                for _=1,#workers do
                    at=at%#workers+1
                    local w=workers[at]
                    local s=w.shared
                    while s.tail<s.head do
                        local i=s.tail%CAP
                        local seed,row=s.seed[i],s.row[i]
                        s.tail=s.tail+1
                        if not accept or accept(seed,row)then return seed,nil,row end
                    end
                    if s.exhausted~=0 and s.finished~=0 then exhausted=exhausted+1 end
                    if s.finished==0 then
                        -- The heap cap: a runaway worker stops; the rest walk on.
                        if calls%64==0 and s.heap_kb>options.heap_cap_kb then s.stop=1;w.capped=true end
                        alive=alive+1
                    end
                end
                local starting=#workers<count and not spawn_error
                if exhausted==count or (alive==0 and not starting)then retire();return nil,true end
                return nil,false,true
            end
            function source.steps()
                local total=0
                for _,w in ipairs(workers)do total=total+w.shared.steps end
                return total
            end
            -- The candidates expected from the steps walked (chain.expected).
            function source.expected()
                local total=0
                for _,w in ipairs(workers)do total=total+w.shared.expected end
                return total
            end
            source.close=retire
            active[source]=true
            -- Figures for the log: workers started, failed (with the first
            -- error), capped, the largest heap, and why starting stopped.
            function source.report()
                local r={workers=#workers,planned=count,failed=0,capped=0,peak_kb=0,setup_kb=0,spawn_error=spawn_error}
                for k,v in pairs(report)do if r[k]==nil then r[k]=v end end
                for _,w in ipairs(workers)do
                    if w.shared.failed~=0 then
                        r.failed=r.failed+1
                        w.error=w.error or error_of(w)
                        r.error=r.error or w.error
                    end
                    if w.capped then r.capped=r.capped+1 end
                    r.peak_kb=math.max(r.peak_kb,w.shared.peak_kb)
                    r.setup_kb=math.max(r.setup_kb,w.shared.setup_kb)
                end
                r.error=r.error or spawn_error
                return r
            end
            return source,nil,report
        end
        return pool
    end
    return W
end
