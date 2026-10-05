-- Usage: luajit tests/test_worker_probe.lua <built entry.lua> <out dir> [run|old_loader]
-- Runs the Worker Thread Probe (scripts/native_solver/worker_probe.lua) with a
-- stubbed loader, update and shutdown on a fast schedule: two short runs,
-- then a long one that shutdown stops mid-walk. Its worker VMs and
-- thread-pool threads are real.
local entry,out,mode=assert(arg[1]),assert(arg[2]),arg[3] or 'run'
local ffi=require('ffi')
ffi.cdef[[void Sleep(uint32_t ms);]]
local log_path=out..'/WorkerThreadProbe.log'
CowboyBingusModLoader={api=1,version=mode=='old_loader' and 15 or 18,
    open_log=function(name)return io.open(out..'/'..name,'w')end}
WorkerThreadProbeSchedule={first=0,gap=0.1,runs={{workers=1,seconds=0.5},{workers=3,seconds=0.5},{workers=1,seconds=120}}}
local shutdown_calls=0
function update(dt)return 'a',nil,dt end
function shutdown(...)shutdown_calls=shutdown_calls+1;return 7,select('#',...)end
local original_update=update
dofile(entry)
local function read()
    local f=assert(io.open(log_path,'r'));local s=f:read('*a');f:close();return s
end

if mode=='old_loader' then
    assert(update==original_update,'update wrapped under an old loader')
    assert(read():find('STOPPED: Bingus Shared Loader v16',1,true),'no STOPPED line')
    print('test_worker_probe (old loader): passed')
    return
end

local probe=assert(rawget(_G,'WorkerThreadProbe'))
assert(update~=original_update,'update not wrapped')
-- The wrapper returns every value the game's update returns, nil included.
local n=select('#',update(0.016))
local a,b,c=update(0.25)
assert(n==3 and a=='a' and b==nil and c==0.25,'update results changed')
-- Loading again is a no-op.
local wrapped=update
dofile(entry)
assert(update==wrapped,'second load wrapped again')

local started=os.clock()
local function frames(until_done)
    local wall=0
    while not until_done()do
        update(0.016);ffi.C.Sleep(10);wall=wall+0.01
        assert(wall<90,'timed out in status '..tostring(probe.status))
    end
end
frames(function()return probe.run_index==3 and probe.active end)
-- Let the long run walk for a moment, then shut down mid-walk.
for _=1,40 do update(0.016);ffi.C.Sleep(10)end
local r1,r2=shutdown('x','y')
assert(r1==7 and r2==2 and shutdown_calls==1,'shutdown results changed')
assert(not probe.active,'workers still active after shutdown')

local text=read()
assert(not text:find('STOPPED',1,true),'STOPPED in log:\n'..text)
assert(not text:find('PROBE_ABANDONED',1,true),'abandoned:\n'..text)
local done={}
for line in text:gmatch('PROBE_DONE[^\n]*')do done[#done+1]=line end
assert(#done==3,'expected three PROBE_DONE lines:\n'..text)
for i,line in ipairs(done)do
    assert(line:find('failed=0',1,true),'worker failed: '..line)
    local steps=tonumber(line:match('steps=(%d+)'))
    assert(steps and steps>0,'no steps: '..line)
    assert(tonumber(line:match('held_after_close_mb=([%-%d%.]+)'))<1,'memory held after close: '..line)
    assert(line:find('run='..i..' ',1,true),line)
end
assert(done[2]:find('workers=3',1,true),done[2])
assert(text:find('PROBE_SHUTDOWN joined=1 run=3',1,true),'no join at shutdown:\n'..text)
for _,phase in ipairs({'startup','before','setup','walk','walked','closed'})do
    assert(text:find('phase='..phase..' ',1,true),'no memory phase '..phase)
end
assert(text:find('PROBE_PROGRESS run=3',1,true),'no progress of the long run')
local rate=tonumber(done[1]:match('steps_per_second=(%d+)'))
print(string.format('test_worker_probe: passed (%s; one worker %.0f steps/s; %d log lines)',jit and jit.version or '?',
    rate,select(2,text:gsub('\n',''))))
