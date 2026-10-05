-- Usage (run inside the game's own lua51.dll by worker_threads.py):
--   worker_threads.lua <repo> <capture.lua> <mode> <steps> <thread counts, comma separated>
-- Research only (docs/NATIVE_SOLVER_RESEARCH.md). Can the seed solver walk
-- on several cores from inside the game's LuaJIT with no foreign machine
-- code? This VM stands in for the mod: it builds the request of
-- scripts/profile_seed_solver.lua, runs its (path, row) jobs here as the
-- in-game search would, then hands the same jobs to worker VMs: a fresh
-- luaL_newstate from lua51.dll each, holding only seed_solver_math.lua,
-- seed_solver_chain.lua and the paths as text, run on an OS thread
-- started at an FFI callback the worker created in itself. Results come
-- back through FFI memory; candidates must equal this VM's.
local repo,capture,mode,limit,counts,start=arg[1],arg[2],arg[3] or 'both',tonumber(arg[4]) or 1000000,arg[5] or '1,2,4,8',arg[6] or 'thread'
local ffi=require('ffi')
ffi.cdef[[
typedef struct lua_State lua_State;
lua_State *luaL_newstate(void);
void luaL_openlibs(lua_State *L);
int luaL_loadbuffer(lua_State *L, const char *buff, size_t sz, const char *name);
int lua_pcall(lua_State *L, int nargs, int nresults, int errfunc);
double lua_tonumber(lua_State *L, int idx);
const char *lua_tolstring(lua_State *L, int idx, size_t *len);
void lua_close(lua_State *L);
int lua_gc(lua_State *L, int what, int data);
void *CreateThread(void *attr, size_t stack, void *start, void *param, uint32_t flags, uint32_t *id);
uint32_t WaitForMultipleObjects(uint32_t n, void *const *handles, int all, uint32_t ms);
int CloseHandle(void *h);
int TrySubmitThreadpoolCallback(void *callback, void *context, void *environment);
void Sleep(uint32_t ms);
]]
local C=ffi.C


-- A high-resolution wall clock: os.clock is CPU time of the whole process.
ffi.cdef[[int QueryPerformanceCounter(int64_t *c); int QueryPerformanceFrequency(int64_t *f);]]
local qpc,qpf=ffi.new('int64_t[1]'),ffi.new('int64_t[1]')
C.QueryPerformanceFrequency(qpf)
local function now()C.QueryPerformanceCounter(qpc);return tonumber(qpc[0])/tonumber(qpf[0])end

local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local here=repo..'/'
local root=here..'src'
local Cap=dofile(here..'scripts/seed_solver_capture.lua')(here..'scripts/',root,capture)
local H=Cap.H
local solver,identity=Cap.solver_inputs()
local Math=H.module(root..'/seed_solver_math.lua')
local Paths=H.module(root..'/seed_solver_paths.lua')(H.module(root..'/mission_category_choice.lua'),
    H.module(root..'/mission_weighted_choice.lua'),H.module(root..'/operation_finalization.lua'))
local Chain=H.module(root..'/seed_solver_chain.lua')(Math)
local P=Paths.new({records=solver.records,row_of=Cap.SideObjectives.row_of,disabled_tags=solver.disabled_tags})
local active=identity.active
local preserved=active and active.planet==Cap.planet and active.row or nil
local avoid={}
for row,name in pairs(Cap.SideObjectives.names)do if name=='Lidar Station' or name=='SEAF Artillery' then avoid[row]='exclude' end end
local op
for _,o in ipairs(Cap.board_of(Cap.case.seed))do
    if o.row<30 and o.row~=preserved and #o.missions>=3 and o.missions[1][4] and (not op or o.difficulty>op.difficulty)then op=o end
end
local kinds,rules={},{}
for i=1,3 do
    local m=op.missions[i];kinds[i]=m[1]
    rules[m[1]]={tags=mode~='objectives' and m[4] and m[4][1] and {[m[4][1]]='accept'} or nil,
        objectives=mode~='tags' and avoid or nil}
end
local d=op.difficulty
local paths=assert(P.shared_paths(solver.operations,d,kinds,rules))
local rows={}
for r=(d-1)*3,d*3-1 do if r~=preserved then local _,sp=Chain.positions(r,preserved);rows[#rows+1]={row=r,seed_position=sp}end end
local state=11
local jobs={}
for p=1,#paths do for _,row in ipairs(rows)do
    state=(state*1103515245+12345)%4294967296
    jobs[#jobs+1]={path=p,row=row.row,seed_position=row.seed_position,s0=state}
end end

-- Plain data as a Lua constructor (numbers, strings, booleans, tables).
local function serialize(v,out)
    local t=type(v)
    if t=='number' then out[#out+1]=string.format('%.17g',v)
    elseif t=='string' then out[#out+1]=string.format('%q',v)
    elseif t=='boolean' then out[#out+1]=tostring(v)
    elseif t=='table' then
        out[#out+1]='{'
        for k,x in pairs(v)do
            local kt,xt=type(k),type(x)
            if (kt=='number' or kt=='string') and (xt=='number' or xt=='string' or xt=='boolean' or xt=='table')then
                out[#out+1]='[';serialize(k,out);out[#out+1]=']=';serialize(x,out);out[#out+1]=','
            end
        end
        out[#out+1]='}'
    else out[#out+1]='nil' end
end
local function text(v)local out={};serialize(v,out);return table.concat(out)end
local paths_text=text(paths)

-- One job run here for `limit` steps: steps, candidates, seed sum.
local function run(chain_module,path_list,job)
    local chain=chain_module.new({paths={path_list[job.path]},rows={{row=job.row,seed_position=job.seed_position}},
        planet=Cap.planet,random=function()return job.s0 end})
    local j=chain.jobs[1]
    local n,sum=0,0
    while j.steps<limit do
        local seed,done=j.next(math.min(4096,limit-j.steps))
        if seed then n=n+1;sum=(sum+seed)%4294967296 elseif done then break end
    end
    return j.steps,n,sum
end
-- Candidates of this VM (the in-game search's situation), on the same
-- serialized paths the workers get.
local local_paths=assert(loadstring('return '..paths_text))()
local expected={}
local t0=now()
for k,job in ipairs(jobs)do expected[k]={run(Chain,local_paths,job)}end
local main_seconds=now()-t0
local total=0
for _,e in ipairs(expected)do total=total+e[1]end
print(string.format('main VM (game lua51.dll, %s): %d jobs, %d steps in %.3f s = %.0f steps/s',jit and jit.version or '?',#jobs,
    total,main_seconds,total/main_seconds))

-- The worker: its own VM, given module sources, the paths and its jobs.
local WORKER=[==[
local math_source,chain_source,paths_text,jobs,planet,limit,out,done_address,index=...
local ffi=require('ffi')
local Math=assert(loadstring(math_source,'=seed_solver_math.lua'))()
local Chain=assert(loadstring(chain_source,'=seed_solver_chain.lua'))()(Math)
local paths=assert(loadstring('return '..paths_text))()
local results=ffi.cast('double *',out)
local function body()
    for _,job in ipairs(jobs)do
        local chain=Chain.new({paths={paths[job.path]},rows={{row=job.row,seed_position=job.seed_position}},
            planet=planet,random=function()return job.s0 end})
        local j=chain.jobs[1]
        local n,sum=0,0
        while j.steps<limit do
            local seed,done=j.next(math.min(4096,limit-j.steps))
            if seed then n=n+1;sum=(sum+seed)%4294967296 elseif done then break end
        end
        results[job.k*3],results[job.k*3+1],results[job.k*3+2]=j.steps,n,sum
    end
end
-- The thread's entry; kept alive in a global until the VM is closed.
WORKER_ENTRY=ffi.cast('uint32_t (__stdcall *)(void *)',function()
    local ok,err=pcall(body)
    if not ok then WORKER_ERROR=tostring(err);return 1 end
    return 0
end)
-- The same work as a thread-pool callback: the thread starts in ntdll and
-- calls it; it raises its done flag when finished.
local done=ffi.cast('volatile int32_t *',done_address)
WORKER_POOL_ENTRY=ffi.cast('void (__stdcall *)(void *, void *)',function()
    local ok,err=pcall(body)
    if not ok then WORKER_ERROR=tostring(err)end
    done[index]=ok and 1 or 2
end)
return tonumber(ffi.cast('intptr_t',WORKER_ENTRY)),tonumber(ffi.cast('intptr_t',WORKER_POOL_ENTRY))
]==]
local math_source,chain_source=read(root..'/seed_solver_math.lua'),read(root..'/seed_solver_chain.lua')

local function check(L,status,what)
    if status~=0 then error(what..': '..ffi.string(C.lua_tolstring(L,-1,nil)))end
end
for threads in counts:gmatch('%d+')do
    threads=tonumber(threads)
    local results=ffi.new('double[?]',#jobs*3+3)
    local done=ffi.new('int32_t[?]',threads)
    local states,handles={},ffi.new('void *[?]',threads)
    local t_setup=now()
    heap_kb=0
    for t=1,threads do
        local mine={}
        for k,job in ipairs(jobs)do
            if (k-1)%threads==t-1 then mine[#mine+1]={k=k-1,path=job.path,row=job.row,seed_position=job.seed_position,s0=job.s0}end
        end
        local L=C.luaL_newstate()
        assert(L~=nil,'luaL_newstate failed')
        C.luaL_openlibs(L)
        -- The worker chunk with its arguments bound as a prelude.
        local prelude=string.format('local args={%q,%q,%q,%s,%d,%d,%.17g,%.17g,%d}\nreturn (function(...)\n',
            math_source,chain_source,paths_text,text(mine),Cap.planet,limit,tonumber(ffi.cast('intptr_t',results)),tonumber(ffi.cast('intptr_t',done)),t-1)
        local chunk=prelude..WORKER..'\nend)(unpack(args))'
        check(L,C.luaL_loadbuffer(L,chunk,#chunk,'=worker'),'worker load')
        check(L,C.lua_pcall(L,0,2,0),'worker setup')
        local entry=ffi.cast('void *',ffi.cast('intptr_t',C.lua_tonumber(L,-2)))
        local pool=ffi.cast('void *',ffi.cast('intptr_t',C.lua_tonumber(L,-1)))
        states[t]={L=L,entry=entry,pool=pool}
        heap_kb=(heap_kb or 0)+C.lua_gc(L,3,0)
    end
    t_setup=now()-t_setup
    local t1=now()
    if start=='pool' then
        for t=1,threads do assert(C.TrySubmitThreadpoolCallback(states[t].pool,nil,nil)~=0,'TrySubmitThreadpoolCallback failed')end
        -- Polled as the mod would poll once a frame.
        local finished=0
        while finished<threads do
            C.Sleep(1)
            finished=0
            for t=0,threads-1 do if done[t]~=0 then finished=finished+1 end end
        end
    else
        for t=1,threads do
            handles[t-1]=C.CreateThread(nil,0,states[t].entry,nil,0,nil)
            assert(handles[t-1]~=nil,'CreateThread failed')
        end
        C.WaitForMultipleObjects(threads,handles,1,0xffffffff)
    end
    local seconds=now()-t1
    local after_kb=0
    for t=1,threads do
        after_kb=after_kb+C.lua_gc(states[t].L,3,0)
        if start~='pool' then C.CloseHandle(handles[t-1])end
        C.lua_close(states[t].L)
    end
    local mismatches=0
    for k,e in ipairs(expected)do
        local i=(k-1)*3
        if results[i]~=e[1] or results[i+1]~=e[2] or results[i+2]~=e[3]then mismatches=mismatches+1 end
    end
    print(string.format('%2d workers ('..start..'): %d steps in %.3f s = %.0f steps/s (%.1fx the main VM); set-up %.0f ms; worker heap %.0f KB each after set-up, %.0f KB after the walk; %d mismatching jobs',
        threads,total,seconds,total/seconds,main_seconds/seconds,t_setup*1000,heap_kb/threads,after_kb/threads,mismatches))
end
