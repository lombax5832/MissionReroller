local root=arg[1];local ffi=require('ffi')
local reads=dofile(root..'/frozen_prediction_reads.lua')
local new=dofile(root..'/prediction_search_job.lua')(reads,dofile(root..'/seed_search.lua'),dofile(root..'/search_session.lua'))
local Rules=dofile(root..'/filter_rules.lua')
local memory={[65536]='A',[65537]='B'};local calls=0
local function read(address,size)
    calls=calls+1;local value=memory[tonumber(ffi.cast('uintptr_t',address))];assert(value and #value==size);return value
end
local function operation(types)
    local missions={};for _,id in ipairs(types)do missions[#missions+1]={native_type=id}end
    return {{valid=true,row=2,difficulty=10,missions=missions}}
end
local function make()
    return new(read,function(take)assert(take(ffi.cast('uint8_t*',65536),1)=='A')end,function(take)
        assert(take(65536,1)=='A')
        return function(seed)
            assert(take(65536,1)=='A');take(65537,1)
            return operation(seed==12 and {0,22,7} or {0,28,7})
        end
    end,{seed=10,limit=5,difficulty=10,rules=Rules.new({required={[1]=true,[2]=true,[3]=true}}),quantum=2})
end
local job=make();local frames=0
while job.status=='running' do
    local before=calls;job:step(function()end);frames=frames+1
    assert(calls-before<=2,'One resume exceeded cooperative read budget');assert(frames<100)
end
assert(job.status=='matched' and job.seed==12 and job.attempts==3 and job.ranges==2 and frames>3)
local before=calls;job:step(function()error('Should not run')end);assert(calls==before)
job=make();job:step(function()end);memory[65536]='X'
while job.status=='running' do job:step(function()end)end
assert(job.status=='failed' and job.error:find('Prediction inputs changed',1,true) and not job.seed)
memory[65536]='A';job=make();job:step(function()error('Map changed')end)
assert(job.status=='cancelled' and not job.seed)
job=make();job:step(function()end);before=calls
for _=1,5 do assert(job:step(function()return false,'backend busy'end)=='running' and job.waiting)end
assert(calls==before,'Backend wait must not evaluate or read more inputs')
while job.status=='running' do job:step(function()end)end
assert(job.status=='matched' and job.seed==12,'Backend drain must resume without another start')
job=make();job:step(function()end);job:step(function()return false,'backend busy'end);memory[65536]='X'
while job.status=='running' do job:step(function()end)end
assert(job.status=='failed' and not job.seed,'Changed frozen inputs after waiting must be rejected')
memory[65536]='A'
job=make()
while job.status=='running' and job.phase~='complete' do
    job:step(function()if job.phase=='complete' then return false,'backend busy after match'end end)
end
assert(job.status=='running' and job.waiting,'A result must not escape a post-work backend wait')
while job.status=='running' do job:step(function()end)end
assert(job.status=='matched')
job=make()
while job.status=='running' and job.phase~='complete' do
    job:step(function()if job.phase=='complete' then return false,'backend busy after match'end end)
end
memory[65536]='X'
while job.status=='running' do job:step(function()end)end
assert(job.status=='failed' and not job.seed and not job.operation,'A held result must be discarded if inputs change during its wait')
memory[65536]='A'
-- The context is checked before every slice and again before a result is exposed.
job=make();local checks,slices=0,0
while job.status=='running' do
    slices=slices+1
    job:step(function()checks=checks+1;if job.phase=='complete' then error('Context changed after work')end end)
end
assert(job.status=='cancelled' and not job.seed and not job.operation and checks==slices+1)
-- Timed slices: rejected candidates read nothing, the frozen bytes are
-- revalidated once a second and before a match, and a match found on the
-- requested difficulty is confirmed against the complete prediction.
local now,cost,target,completed=0,0.001,nil,{}
local function board(seed,rows)
    local out={}
    for i,row in ipairs(rows)do
        out[i]={valid=true,row=row,difficulty=row==2 and 10 or 5,missions={}}
        for j,id in ipairs(seed==target and {0,22,7} or {0,28,7})do out[i].missions[j]={native_type=id}end
    end
    return out
end
local complete_rows={1,2,3}
local function timed(limit,batch)
    completed={}
    return new(read,function(take)assert(take(65536,1)=='A')end,function(take)
        take(65537,1)
        return function(seed)now=now+cost;return board(seed,{2})end,
            function(seed)completed[#completed+1]=seed;return board(seed,complete_rows)end
    end,{seed=10,limit=limit,difficulty=10,rules=Rules.new({required={[1]=true,[2]=true,[3]=true}}),quantum=64,
        clock=function()return now end,slice=0.016,batch=batch or 256,revalidate=1})
end
job=timed(5000);before=calls;job:step(function()end)
assert(job.attempts>=15 and job.attempts<=17 and job.next_seed==10+job.attempts,'One slice evaluates what fits in it: '..job.attempts)
local setup=calls-before;before=calls
for _=1,20 do job:step(function()end)end
assert(calls==before and job.attempts>300,'Rejected candidates must not read memory')
while job.attempts<1100 do job:step(function()end)end
assert(calls-before==2 and setup>=2,'The two frozen ranges are revalidated once a second: '..(calls-before))
while job.status=='running' do job:step(function()end)end
assert(job.status=='exhausted' and job.attempts==5000 and job.next_seed==5010 and #completed==0)
cost=0;job=timed(5000,100);job:step(function()end)
assert(job.attempts==100,'The candidate cap bounds a slice when the clock stalls')
job:step(function()end);assert(job.attempts==200);cost=0.001
target=700;job=timed(5000);before=calls
while job.status=='running' do job:step(function()end)end
assert(job.status=='matched' and job.seed==700 and job.attempts==691 and job.ranges==2)
assert(#completed==1 and completed[1]==700 and #job.operations==3 and job.operation==job.operations[2],'A match carries the complete board')
assert(calls-before>=setup+2,'A match is validated before it is exposed')
complete_rows={1,3};job=timed(5000)
while job.status=='running' do job:step(function()end)end
assert(job.status=='failed' and job.error:find('Search and complete predictions differ',1,true) and not job.seed)
complete_rows={1,2,3}
job=timed(5000);job:step(function()end);memory[65537]='X';local seen=job.attempts
while job.status=='running' do job:step(function()end)end
assert(job.status=='failed' and job.error:find('Prediction inputs changed',1,true) and not job.seed)
assert(job.attempts>seen and job.attempts<=700,'A change is noticed within a second, before any match: '..job.attempts)
memory[65537]='B';target=30;job=timed(5000);job:step(function()end);memory[65537]='X'
while job.status=='running' do job:step(function()end)end
assert(job.status=='failed' and not job.seed and not job.operation,'A match on changed inputs is rejected')
memory[65537]='B';target=nil
assert(not pcall(timed,5000,0) and not pcall(new,read,function()end,function()end,{seed=1,limit=1,difficulty=10,rules=Rules.new({required={[1]=true}}),clock=1}))
job=make();job:step(function()end);job:cancel('User cancelled');before=calls
assert(job:step(function()end)=='cancelled' and calls==before)
local frozen=reads(read,function()end,{entries=1,bytes=1})
local original=tostring;_G.tostring=function(x)return type(x)=='cdata' and '[cdata (deleted)]' or original(x)end
assert(frozen.read(ffi.cast('uint8_t*',65536),1)=='A' and frozen.read(65536,1)=='A')
assert(not pcall(frozen.read,65537,1),'Input budget must stop expansion')
_G.tostring=original
assert(not pcall(reads(function()return ''end,function()end).read,65536,1),'Short input must fail')
print('Prediction search job: timed slices, validation on match, complete-board confirmation, cooperative budget, frozen bytes, expansion, revalidation, cancellation, context changes and pointer keys passed')
