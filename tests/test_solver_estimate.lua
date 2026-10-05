-- Usage: luajit test_solver_estimate.lua <src/solver_estimate.lua>
-- The dialog's background estimate with a stub planet and the plan of
-- src/seed_solver_search.lua (beside it) over a stub source: pending
-- until worked out, a slice per update, inputs kept across edits, an edit
-- restarting the paths or retargeting the input read, no seed possible,
-- unavailable, and a new snapshot dropping what was kept.
local make=dofile(arg[1])
local Rules=dofile((arg[1]:gsub('solver_estimate%.lua$','filter_rules.lua')))
local make_solver=dofile((arg[1]:match('^(.*[/\\])') or '')..'seed_solver_search.lua')
-- The solver's prepare and plan with source replaced.
local function solver(source)local R=make_solver({},{},{},{},{});R.source=source;return R end
local now=0
local function clock()return now end
-- Each read and each solver checkpoint costs 1 ms of the clock.
local reads,builds,sources=0,0,0
local planned={}
local Solver=solver(function(spec)
    sources=sources+1
    for _=1,5 do now=now+0.001;spec.checkpoint()end
    local plan=planned[next(spec.required) or 0]
    if plan=='none' then return nil,'no draw path'end
    if plan=='off' then return nil,'operations at the difficulty differ'end
    if plan=='dark' then return nil,'no operation passes Day / Night'end
    return {estimate={match=1/(plan or 100),steps=1000*(spec.daynight and 7 or 1)}}
end)
local specials={}
local function bind(read,s)
    return {definitions=function()read(1,4);return 0x1000 end,
        solver=function(definitions,difficulty,seeded,region)
            builds=builds+1
            for _=1,10 do read(2,4)end
            return {seeded=seeded},{planet=s.planet,specials=specials}
        end}
end
local E=make(Solver)({read=function()now=now+0.001;reads=reads+1;return '\0\0\0\0' end,clock=clock,slice=0.004,
    options={},rate=function()return 1000 end,setup=0,bind=bind})
local s={fingerprint='a',planet=100}
local function request(families,extra)
    local r={required={},constellations={groups={}},objectives={groups={}}}
    for _,f in ipairs(families)do r.required[f]=true end
    for k,v in pairs(extra or {})do r[k]=v end
    return Rules.new(r)
end
-- Work until the estimate is ready, counting updates.
local function settle(r,daynight,scope)
    local frames=0
    repeat E.update(s,10,scope,r,daynight);frames=frames+1 until E.view() or frames>100
    return E.view(),frames
end

E.update(s,10,nil,request({1}))
assert(E.view()==nil,'Pending until worked out')
assert(now<=0.006,'One update works about one slice: '..now)
local v,frames=settle(request({1}))
assert(v.match==1/100 and math.abs(v.seconds-1.3)<1e-9 and frames>=3 and builds==1,'Estimate: setup + steps / rate + 0.3')
-- Another request of the same view reuses the inputs.
v=settle(request({2}))
assert(v and builds==1 and sources==2,'Inputs are kept across edits')
-- A result is kept: going back costs nothing.
local before=sources;v=settle(request({1}))
assert(v.match==1/100 and sources==before,'Results are kept per request')
-- Enemy-force rules need the seeded inputs: built once more.
v=settle(request({1},{constellations={groups={[1]={[4]='accept'}}}}))
assert(builds==2,'Seeded inputs are built separately')
-- An edit while the paths are built restarts them.
planned[3]=50
E.update(s,10,nil,request({3}));assert(E.view()==nil)
local restarted=sources
v=settle(request({4}))
assert(v and v.match==1/100 and sources==restarted+1,'An edit restarts the paths: '..sources..' '..restarted)
-- An edit while the inputs are read keeps the read for the new request.
s={fingerprint='b',planet=100}
E.update(s,10,nil,request({1}));assert(E.view()==nil and builds==3,'The read has begun')
v=settle(request({3}))
assert(builds==3 and v.match==1/50,'The input read is kept for the new request')
-- Day / Night changes the result through its key.
v=settle(request({3}),{key='night:1',accepts=function()return true end})
assert(math.abs(v.seconds-7.3)<1e-9,'Day / Night is part of the request')
-- No path: impossible unless another operation of the difficulty could match.
planned[5]='none'
v=settle(request({5}))
assert(v.impossible,'No path and no other operation: no seed gives this')
specials[1]={minimum=9,maximum=10}
s={fingerprint='c',planet=100}
v=settle(request({5}))
assert(v.unavailable=='no draw path','An event operation of the difficulty might still match')
v=settle(request({5}),nil,{region=2})
assert(v.impossible,'A city has no other operation')
-- Day / Night passing no normal operation: likewise.
planned[7]='dark'
v=settle(request({7}))
assert(v.unavailable=='no operation passes Day / Night','A city of the difficulty might pass Day / Night')
specials[1]=nil
s={fingerprint='d',planet=100}
v=settle(request({7}))
assert(v.impossible,'No operation passes Day / Night and no city: no seed gives this')
planned[6]='off'
v=settle(request({6}))
assert(v.unavailable=='operations at the difficulty differ')
-- A failure inside the work is a result, not an error.
local Broken=make(solver(function()error('broken paths')end))({read=function()return '' end,clock=clock,slice=1,
    options={},rate=function()return 1 end,bind=bind})
Broken.update(s,10,nil,request({1}))
assert(tostring(Broken.view().unavailable):find('broken paths',1,true))
E.reset();assert(E.view()==nil)
-- Before any search has measured the walk rate: how strict, but no time.
local Unmeasured=make(Solver)({read=function()now=now+0.001;return '\0\0\0\0' end,clock=clock,slice=0.004,
    options={},rate=function()return nil end,setup=0,bind=bind})
s={fingerprint='e',planet=100}
repeat Unmeasured.update(s,10,nil,request({1}))until Unmeasured.view()
v=Unmeasured.view()
assert(v.match==1/100 and v.seconds==nil,'No rate measured: no seconds')
-- With the dialog's options to check, the worker goes on after the estimate
-- to the reachability, on the mission-seed inputs; the estimate shows first.
do
    local seen
    local Reaching=solver(function(spec)for _=1,5 do now=now+0.001;spec.checkpoint()end;return {estimate={match=1/10,steps=10}}end)
    Reaching.reachability=function(prepared,spec,offered)
        seen={seeded=prepared.solver.seeded,shown=offered(1)}
        for _=1,8 do now=now+0.001;spec.checkpoint()end
        if spec.required[2] then error('broken reachability')end
        return {ok=true,tag=function(_,tag,mode)return not (tag==6 and mode=='accept')end,objective=function()return true end}
    end
    local R2=make(Reaching)({read=function()now=now+0.001;return '\0\0\0\0' end,clock=clock,slice=0.004,
        options={},rate=function()return 1000 end,setup=0,bind=bind})
    local function offered(f)return {tags={6},objectives={}}end
    local sr={fingerprint='r',planet=100}
    local built=builds
    repeat R2.update(sr,10,nil,request({1}),nil,offered)until R2.view()
    assert(R2.view().match==1/10,'The estimate is shown before the reachability')
    local frames=0
    repeat R2.update(sr,10,nil,request({1}),nil,offered);frames=frames+1 until R2.reachable() or frames>50
    local reach=R2.reachable()
    assert(reach and reach.ok and reach.tag(1,6,'accept')==false and reach.tag(1,6,'exclude'),'The reachability follows')
    assert(seen.seeded==true and seen.shown.tags[1]==6,'Worked out on the mission-seed inputs with the options shown')
    assert(builds==built+2,'The estimate and the mission-seed inputs are each read once: '..(builds-built))
    -- Another edit of the same view reuses the mission-seed inputs.
    repeat R2.update(sr,10,nil,request({3}),nil,offered)until R2.reachable()
    assert(builds==built+2,'The mission-seed inputs are kept')
    -- No options, or no required mission: nothing is worked out.
    repeat R2.update(sr,10,nil,request({4}))until R2.view()
    for _=1,5 do R2.update(sr,10,nil,request({4}))end
    assert(R2.reachable()==nil,'No options to check')
    -- A failure leaves the estimate and rules nothing out.
    repeat R2.update(sr,10,nil,request({1,2}),nil,offered)until R2.view()
    for _=1,20 do R2.update(sr,10,nil,request({1,2}),nil,offered)end
    assert(R2.view().match==1/10 and R2.reachable()==nil,'A failed reachability is nil')
end
print('Solver estimate: pending, slices, kept inputs, restart and retarget on edits, Day / Night, impossible, unavailable, failures and reachability passed')
