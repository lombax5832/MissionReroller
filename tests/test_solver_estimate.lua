-- Usage: luajit test_solver_estimate.lua <src/solver_estimate.lua>
-- The dialog's background estimate with a stub solver and planet: pending
-- until worked out, a slice per update, inputs kept across edits, an edit
-- restarting the paths or retargeting the input read, no seed possible,
-- unavailable, and a new snapshot dropping what was kept.
local make=dofile(arg[1])
local now=0
local function clock()return now end
-- Each read and each solver checkpoint costs 1 ms of the clock.
local reads,builds,sources=0,0,0
local planned={}
local Solver={source=function(spec)
    sources=sources+1
    for _=1,5 do now=now+0.001;spec.checkpoint()end
    local plan=planned[next(spec.required) or 0]
    if plan=='none' then return nil,'no draw path'end
    if plan=='off' then return nil,'operations at the difficulty differ'end
    return {estimate={match=1/(plan or 100),steps=1000*(spec.daynight and 7 or 1)}}
end}
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
    return r
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
planned[6]='off'
v=settle(request({6}))
assert(v.unavailable=='operations at the difficulty differ')
-- A failure inside the work is a result, not an error.
local Broken=make({source=function()error('broken paths')end})({read=function()return '' end,clock=clock,slice=1,
    options={},rate=function()return 1 end,bind=bind})
Broken.update(s,10,nil,request({1}))
assert(tostring(Broken.view().unavailable):find('broken paths',1,true))
E.reset();assert(E.view()==nil)
print('Solver estimate: pending, slices, kept inputs, restart and retarget on edits, Day / Night, impossible, unavailable and failures passed')
