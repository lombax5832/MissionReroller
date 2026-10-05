-- The seed solver's walk in worker VMs (docs/NATIVE_SOLVER_RESEARCH.md,
-- docs/WORKER_PROBE_TEST.md). Each worker is a LuaJIT VM from the game's
-- own lua51.dll, holding seed_solver_math.lua, seed_solver_chain.lua and
-- seed_solver_codec.lua as text (the build passes them in `sources`) and,
-- per search, the request's paths as codec text. A job runs on a Windows
-- thread-pool thread at below-normal priority, started at an FFI callback
-- the VM created in itself; between jobs a worker holds no thread. The
-- workers share each job's random base and split its starts into equal
-- arcs, one each (seed_solver_chain.lua arc), so between them they walk
-- every start once; candidates (seed and row) come back through a ring in
-- FFI memory. The caller's VM applies `accept` (the Day / Night ID check, a
-- closure over game data) and predicts each candidate as before.
--
-- Warm workers: while the pool is warm (pool.warm(true), on the ship) it
-- keeps up to max_workers idle VMs with their modules loaded, made one per
-- pool.tick(). A search's workers are closed when it ends and fresh idle
-- VMs replace them: a VM that walked keeps its peak heap below 2 GB until
-- lua_close (eight held 21 MB in game, 2026-10-05), while a fresh one
-- holds about 0.25 MB. Cold
-- (pool.warm(false), in a mission) every idle VM is closed and a search's
-- workers close when it ends, as they did before warm workers.
--
-- Every heap of this non-GC64 LuaJIT lives below 2 GB, where the game had
-- about 30 MB free (docs/WORKER_PROBE_TEST.md): the pool scans that range
-- with VirtualQuery and makes only as many workers as fit beside a reserve,
-- and stops a worker whose heap passes a cap. A worker VM is reused or
-- closed only once the pool has seen its callback-return event, never while
-- its thread may still be in it. No memory is written outside the pool's
-- own buffers.
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
    -- One worker's block, shared with its VM: the job the caller sets
    -- before each submit (job 0 loads the modules only, 1 walks the paths
    -- at data_address), then the worker's progress and candidate ring.
    local SHARED=[[struct { int32_t stop, finished, failed, exhausted, head, tail, limited, job, index, count, step_limit, pad;
    double steps, heap_kb, peak_kb, expected, setup_kb, data_address, data_length, base; double seed[256]; int32_t row[256]; }]]

    -- The worker VM's chunk: its own VM, so its ffi.cdef cannot clash with
    -- other addons. The callback is wrapped whole in pcall, since an error
    -- escaping a LuaJIT callback ends the process. It may run many times,
    -- one job at a time; the modules load on the first.
    local WORKER=[==[
-- Module texts arrive as (address, length) of read-only buffers the pool
-- keeps alive until this VM is closed; they are copied on the worker's thread.
local texts,shared_address,event_address,cap=...
local ffi=require('ffi')
ffi.cdef('typedef '..SHARED..' solver_worker_t;')
ffi.cdef[[
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
local function text(address,length)return ffi.string(ffi.cast('const char *',address),length)end
local Math,Chain,Codec
-- On the worker's thread, so the cost never lands in the game's frame.
local function load()
    if Chain then return end
    Math=assert(loadstring(text(texts.math[1],texts.math[2]),'=seed_solver_math.lua'))()
    Chain=assert(loadstring(text(texts.chain[1],texts.chain[2]),'=seed_solver_chain.lua'))()(Math)
    Codec=assert(loadstring(text(texts.codec[1],texts.codec[2]),'=seed_solver_codec.lua'))()
    texts=nil
end
-- Decodes this job's paths (the cost grows with the request) and walks arc
-- `index` of `count` of each job's starts.
local function walk()
    local paths,rows,planet=Codec.decode(text(shared.data_address,shared.data_length))
    -- Drop the set-up's garbage and collect sooner while walking.
    collectgarbage('collect');collectgarbage('setpause',110)
    shared.setup_kb=collectgarbage('count')
    local step_limit=shared.step_limit
    -- Each job's base as SeedSolver.starts gives it, from the seed every
    -- worker of the search shares.
    local n=shared.base
    local function random()n=(n+1)%4294967296;return Math.output(n,1)end
    local chain=Chain.new({paths=paths,rows=rows,planet=planet,random=random,arc={index=shared.index,count=shared.count}})
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
local function body()
    load()
    local ok,why=true,nil
    if shared.job~=0 then ok,why=pcall(walk)end
    -- Back to the modules only before the VM idles.
    collectgarbage('collect')
    shared.heap_kb=collectgarbage('count')
    if not ok then error(why,0)end
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
                reset_event=k('ResetEvent','int (*)(void *)'),
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
        local shared_type=ffi.typeof(SHARED..'[1]')
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
        local texts='{'
        for _,name in ipairs({'math','chain','codec'})do
            local b=source_buffers[name]
            texts=texts..string.format('%s={%.17g,%d},',name,address(b[1]),b[2])
        end
        texts=texts..'}'

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

        -- idle: VMs with their modules loaded and no thread, kept while warm.
        -- retired: workers stopped or warming up, waiting for their callbacks
        -- to return; then idle (a healthy warm-up while warm) or closed (a
        -- worker that walked keeps its heap until closed).
        -- active: every source still running, for cool and shutdown.
        local idle,retired,active={},{},{}
        local warm,warm_full=false,false
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
            L51.settop(w.L,0)
            return message~=nil and ffi.string(message) or 'worker failed'
        end
        -- Writes a job into the worker's block and hands it to a pool thread;
        -- false when the pool refuses it. job: nil to load the modules only,
        -- or {data, base, index, count, step_limit}.
        local function submit(w,job)
            ffi.fill(w.block,ffi.sizeof(shared_type))
            local s=w.shared
            if job then
                s.job,s.index,s.count,s.step_limit=1,job.index,job.count,job.step_limit or 0
                s.data_address,s.data_length,s.base=address(job.data[1]),job.data[2],job.base
                w.data=job.data
            end
            if w.submitted then K.reset_event(w.event)end
            w.returned,w.capped,w.error,w.warming=false,nil,nil,job==nil
            if K.submit(w.entry,nil,nil)==0 then w.submitted=false;return false end
            w.submitted=true
            return true
        end
        -- Makes a worker VM (well under a millisecond: its modules load on
        -- its own thread) and submits `job`; nil and why on failure.
        local function spawn(job)
            local block=ffi.new(shared_type)
            local w={block=block,shared=block[0],sources=source_buffers}
            local ok,err=pcall(function()
                local L=L51.newstate()
                if L==nil then error('luaL_newstate failed')end
                w.L=L
                L51.openlibs(L)
                local event=K.create_event(nil,1,0,nil)
                if event==nil then error('CreateEventA failed')end
                w.event=event
                local chunk=string.format('local SHARED=%q\nreturn (function(...)\n%s\nend)(%s,%.17g,%.17g,%d)',
                    SHARED,WORKER,texts,address(block),address(event),CAP)
                if L51.loadbuffer(L,chunk,#chunk,'=seed_solver_worker')~=0 or L51.pcall(L,0,1,0)~=0 then
                    error('worker set-up: '..ffi.string(L51.tolstring(L,-1,nil)))
                end
                w.entry=ffi.cast('void *',ffi.cast('intptr_t',L51.tonumber(L,-1)))
                L51.settop(L,0)
            end)
            if not ok then release(w);return nil,tostring(err)end
            if not submit(w,job)then release(w);return nil,'thread pool refused the work'end
            return w
        end
        -- Each frame: closes or idles the retired workers whose callbacks
        -- have returned, and while warm makes one more idle worker until
        -- there are max_workers or memory runs short. Returns how many
        -- workers are still retired.
        function pool.reap()
            for i=#retired,1,-1 do
                local w=retired[i]
                if returned(w)then
                    table.remove(retired,i)
                    w.error=w.error or error_of(w)
                    w.data=nil
                    if warm and w.warming and w.L and not w.error and w.shared.failed==0 then
                        idle[#idle+1]=w
                    else
                        -- A warm-up that failed would fail again: warm no further.
                        if w.warming and w.error then warm_full=true;pool.warm_error=w.error end
                        release(w)
                        -- A closed VM gave its memory back: warming short of
                        -- memory may go on.
                        if not pool.warm_error then warm_full=false end
                    end
                end
            end
            return #retired
        end
        function pool.tick()
            pool.reap()
            local busy=0
            for source in pairs(active)do busy=busy+source.workers end
            if warm and not warm_full and #idle+#retired+busy<pool.max_workers then
                local free,largest=pool.memory()
                if (free/MB-options.reserve_mb)*1024<options.base_kb or largest/MB<options.largest_mb then
                    warm_full=true
                else
                    local w,why=spawn(nil)
                    if w then retired[#retired+1]=w else warm_full=true;pool.warm_error=why end
                end
            end
            return #retired
        end
        -- Warm (true) keeps idle workers; cold (false) stops every running
        -- source and closes the idle workers now, the rest as they return.
        -- Returns how many workers it closed.
        function pool.warm(on)
            warm,warm_full=on and true or false,false
            if warm then return 0 end
            for source in pairs(active)do source.close()end
            local closed=#idle
            for _,w in ipairs(idle)do release(w)end
            idle={}
            pool.reap()
            return closed
        end
        -- Counts for the log: idle workers, workers not yet returned, warm,
        -- and full once warming stopped short of max_workers (memory below
        -- 2 GB, or warm_error).
        function pool.state()return {idle=#idle,retired=#retired,warm=warm,full=warm_full}end
        -- At shutdown: stops every worker, waits up to `seconds` for their
        -- callbacks and closes those that returned. Returns how many are
        -- left open (their VMs are left for the process exit).
        function pool.shutdown(seconds)
            local deadline=now()+(seconds or 3)
            pool.warm(false)
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
        -- started. Idle workers start here; new VMs, when too few are idle,
        -- start in next(), about 2 ms of them per call, so no call holds
        -- the frame long.
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
            -- An idle worker needs room for its copy of the paths only; a new
            -- one for its VM too.
            local text_kb=options.text_factor*#text/1024
            local per_kb=options.base_kb+text_kb
            local room=(free/MB-options.reserve_mb)*1024
            local reused=math.max(0,math.min(#idle,pool.max_workers,math.floor(room/math.max(text_kb,1))))
            room=room-reused*text_kb
            local count=reused+math.max(0,math.min(pool.max_workers-reused,math.floor(room/per_kb)))
            local report={free_mb=free/MB,largest_mb=largest/MB,text_kb=#text/1024,per_worker_kb=per_kb,
                processors=processors,warm=reused}
            if largest/MB<options.largest_mb then count=0 end
            if count<1 then
                return nil,string.format('memory below 2 GB: %.1f MB free, largest block %.1f MB',free/MB,largest/MB),report
            end
            local workers={}
            local data=buffer(text)
            text=nil
            checkpoint()
            -- One base for every worker, so their arcs tile each job's starts.
            local base=spec.random()
            local function job()
                return {data=data,base=base,index=#workers,count=count,step_limit=spec.step_limit}
            end
            -- Submits an idle worker or makes a new one; nil and why on failure.
            local function launch()
                local w=table.remove(idle)
                if w then
                    if not submit(w,job())then release(w);return nil,'thread pool refused the work'end
                else
                    local why
                    w,why=spawn(job())
                    if not w then return nil,why end
                end
                workers[#workers+1]=w
                return w
            end
            local spawn_error
            repeat
                local w,why=launch()
                if not w then spawn_error=why end
            until spawn_error or #workers>=count or (#workers>=reused and #workers>0)
            if #workers==0 then return nil,spawn_error,report end
            checkpoint()
            report.setup_ms=(now()-started)*1000

            local source={workers=count}
            local accept=spec.accept
            local closed,at,calls=false,0,0
            local function retire()
                if closed then return end
                closed=true
                active[source]=nil
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
                        local w,err=launch()
                        if not w then spawn_error=err end
                    until spawn_error or #workers>=count or now()-t>0.002
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
            -- Figures for the log: workers started (warm: how many were idle
            -- VMs), failed (with the first error), capped, the largest heap,
            -- and why starting stopped.
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
