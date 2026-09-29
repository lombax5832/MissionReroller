-- Usage: luajit test_constellation_prediction.lua <src> [<recorded seed fixture>]
local root=arg[1]
local R=dofile(root..'/constellation_prediction.lua');local S=dofile(root..'/search_session.lua')
local function none()return false end
local function settings(weights,draws)
    local ids={2,3,4,6,8,7};local rows={}
    for i,id in ipairs(ids)do rows[i]={id=id,weight=weights[i],only_when_empty=false}end
    rows[7]={id=0,weight=0,only_when_empty=false};rows[8]={id=0,weight=0,only_when_empty=false}
    return {draws=draws or 1,candidates=rows,blockers={0,0,0,0,0,0,0,0},fallback=0}
end
local plain={horde=false,exclusions={}}
local function tags(result)return table.concat(result.list,',')end
-- One draw consumes one LCG step; the first candidate covers target 0.
local bugs=settings({1,0.5,1,0.7,0.7,1})
for seed=0,2000 do
    local result=R.resolve(seed,bugs,{},plain,none)
    assert(#result.list==1 and result.set[result.list[1]],'One base constellation per draw')
end
local counts={}
for seed=0,5999 do local id=R.resolve(seed*7919%4294967296,bugs,{},plain,none).list[1];counts[id]=(counts[id] or 0)+1 end
assert(counts[3]<counts[2] and counts[6]<counts[2] and counts[8]<counts[4],'Lower weights must draw less often')
assert(tags(R.resolve(5,settings({0,0,0,0,0,0}),{},plain,none))=='','Zero total weight draws nothing')
assert(tags(R.resolve(5,settings({1,1,1,1,1,1},0),{},plain,none))=='','Zero draws select nothing')
-- Initial tags precede draws; only-when-empty rows see the pre-draw count.
local gated=settings({1,1,1,1,1,1});for _,row in ipairs(gated.candidates)do row.only_when_empty=true end
assert(tags(R.resolve(9,gated,{10},plain,none))=='10','Only-when-empty candidates need an empty list')
assert(#R.resolve(9,gated,{},plain,none).list==1)
-- Native index 0 occupies a slot and therefore also blocks only-when-empty rows.
assert(tags(R.resolve(9,gated,{0},plain,none))=='','The native none entry still counts as a tag')
-- Fallback: absent blockers add it; any blocker suppresses it.
local squid={draws=1,candidates={},blockers={27,28,29,30,0,0,0,0},fallback=28}
for i=1,8 do squid.candidates[i]={id=0,weight=0,only_when_empty=false}end
assert(tags(R.resolve(3,squid,{},plain,none))=='28')
assert(tags(R.resolve(3,squid,{27},plain,none))=='27')
assert(tags(R.resolve(3,squid,{26},plain,none))=='26,28','Tags after the list terminator do not block')
squid.blockers={27,0,29,0,0,0,0,0}
assert(tags(R.resolve(3,squid,{29},plain,none))=='28,29','Blockers stop at the first empty slot')
-- Horde, mission exclusions and configuration exclusions apply afterwards.
assert(tags(R.resolve(3,squid,{},{horde=true,exclusions={}},none))=='1,28')
assert(tags(R.resolve(3,squid,{12},{horde=false,exclusions={12}},none))=='28')
assert(tags(R.resolve(3,squid,{12},{horde=true,exclusions={1,28}},none))=='12')
assert(tags(R.resolve(3,squid,{12},plain,function(tag)return tag==28 end))=='12')
local many={};for i=1,20 do many[i]=i end
assert(#R.resolve(3,squid,many,plain,none).list==16,'Native list capacity is sixteen tags')
assert(not pcall(R.resolve,-1,bugs,{},plain,none) and not pcall(R.resolve,1.5,bugs,{},plain,none))
assert(not pcall(R.resolve,1,bugs,{32},plain,none))
for id=1,31 do assert(R.names[id]:match('^[%w %-]+ %([%w_]+%)$'),'Constellation label '..id)end
assert(R.describe({})=='none' and R.describe({2,9})=='Bile Bugs (BugAcid), Predator Strain (GM_BugSuperPredators)')
-- Operation matching. Families: 1 Launch ICBM (type 59), 7 Search and
-- Destroy (type 68), 3 Eradicate (type 65).
local function operation(...)
    local missions={}
    for i,entry in ipairs({...})do
        local set={};for _,tag in ipairs(entry[2])do set[tag]=true end
        missions[i]={native_type=entry[1],tags=set}
    end
    return {difficulty=10,missions=missions}
end
-- Positive tags are accepted, negative ones excluded.
local function find(op,required,groups)
    local sets={}
    for group,list in pairs(groups)do
        sets[group]={};for _,tag in ipairs(list)do sets[group][math.abs(tag)]=tag<0 and 'exclude' or 'accept' end
    end
    return S.find({operations={op}},10,required,{},{groups=sets})
end
local mixed=operation({59,{2}},{68,{4,9}},{65,{6}})
assert(find(mixed,{[1]=true,[7]=true},{}),'No constellation imposes no constraint')
assert(find(mixed,{[1]=true,[7]=true},{[1]={2},[7]={4}}),'Each checked mission has its own constellation')
assert(not find(mixed,{[1]=true,[7]=true},{[1]={4},[7]={2}}),'A constellation on another mission does not count')
assert(find(mixed,{[1]=true,[7]=true},{[1]={3,2}}),'Any accepted constellation satisfies its mission')
assert(find(mixed,{[1]=true,[7]=true},{[7]={9}}) and not find(mixed,{[1]=true,[7]=true},{[7]={6}}))
assert(not find(mixed,{[1]=true,[2]=true},{[1]={2}}),'Missions are still required')
assert(find(mixed,{},{[0]={6}}) and find(mixed,{},{[0]={3,4}}),'Without checked missions one mission must match')
assert(not find(mixed,{},{[0]={3}}) and not find(operation(),{},{[0]={2}}))
assert(find(mixed,{[1]=true},{[1]={},[0]={}}),'Empty groups accept everything')
local twice=operation({65,{2}},{65,{4}})
assert(find(twice,{[3]=true},{[3]={4}}),'Either mission of a repeated family may match')
local unknown=operation({59,{2}},{68,{4}});unknown.missions[1].tags=nil
assert(not find(unknown,{[1]=true},{[1]={2}}) and find(unknown,{[1]=true,[7]=true},{[7]={4}}),'Unresolved tags never match')
assert(not find(unknown,{},{[0]={2}}) and find(unknown,{},{[0]={4}}))
assert(S.find({operations={unknown}},10,{[1]=true},{}),'Operations without constellations are unaffected')
-- Exclusion: the checked mission carries none of the excluded tags.
assert(find(mixed,{[7]=true},{[7]={-2,-3,-6}}) and not find(mixed,{[7]=true},{[7]={-2,-9}}),'Several tags can be excluded')
assert(not find(mixed,{[7]=true},{[7]={-4}}) and find(mixed,{[1]=true},{[1]={-4,-9,-6}}),'Exclusion follows its own mission')
assert(find(mixed,{[7]=true},{[7]={4,-2}}) and not find(mixed,{[7]=true},{[7]={4,-9}}),'Accepted and excluded tags combine')
assert(not find(mixed,{[7]=true},{[7]={2,-3}}),'Exclusion alone does not replace an accepted tag')
assert(find(twice,{[3]=true},{[3]={-2}}) and not find(twice,{[3]=true},{[3]={-2,-4}}),'One mission of a repeated family must pass')
assert(not find(unknown,{[1]=true},{[1]={-4}}) and find(unknown,{[7]=true},{[7]={-2}}),'Unresolved tags cannot prove an exclusion')
-- Without checked missions an exclusion covers every mission of the operation.
assert(find(mixed,{},{[0]={-3,-7,-8}}) and not find(mixed,{},{[0]={-9}}) and not find(mixed,{},{[0]={-3,-6}}))
assert(find(mixed,{},{[0]={6,-3}}) and not find(mixed,{},{[0]={6,-2}}) and not find(mixed,{},{[0]={3,-7}}))
assert(not find(unknown,{},{[0]={-3}}) and not find(operation(),{},{[0]={-3}}),'Every mission must be known to be clear')
-- City scope: region r owns rows 30+10r .. 39+10r.
local function at(row,kind)return {row=row,difficulty=10,missions={{native_type=kind,tags={[4]=true}}}}end
local planet_op,city,other=at(29,59),at(49,59),at(59,59)
local function scoped(ops,scope)return S.find({operations=ops},10,{[1]=true},{},{groups={}},scope)end
assert(scoped({planet_op,city,other},nil)==planet_op,'Without a scope the whole planet is searched')
assert(scoped({planet_op,city,other},{region=1})==city and scoped({planet_op,city,other},{region=2})==other)
assert(not scoped({planet_op,city},{region=2}) and not scoped({planet_op},{region=0}),'Other rows never match a city')
assert(S.in_scope(30,{region=0}) and S.in_scope(39,{region=0}) and not S.in_scope(40,{region=0}) and not S.in_scope(29,{region=0}))
assert(S.in_scope(109,{region=7}) and not S.in_scope(110,{region=7}) and S.in_scope(5,nil))
assert(S.scope(nil)==nil and S.scope({region=3}).region==3)
assert(not pcall(S.scope,{region=8}) and not pcall(S.scope,{region=-1}) and not pcall(S.scope,{region=1.5}) and not pcall(S.scope,{}))
-- Native captures recorded by the sibling reference project, when present.
local recorded=0
if arg[2]then
    local file=io.open(arg[2],'r')
    if file then
        file:close()
        local function native(id)if id==31 then return 1 end;return id==0 and 0 or id+1 end
        for _,row in ipairs(dofile(arg[2]))do
            local converted={draws=row.settings.draws,fallback=native(row.settings.fallback),blockers={},candidates={}}
            for i,b in ipairs(row.settings.blockers)do converted.blockers[i]=native(b)end
            for i,c in ipairs(row.settings.candidates)do converted.candidates[i]={id=native(c.id),weight=c.weight,only_when_empty=c.only_when_empty}end
            local initial={};for i,id in ipairs(row.initial)do initial[i]=native(id)end
            local expected={};for i,id in ipairs(row.expected)do expected[i]=native(id)end
            table.sort(expected)
            assert(tags(R.resolve(row.seed,converted,initial,plain,none))==table.concat(expected,','),'Recorded native seed '..row.seed)
            recorded=recorded+1
        end
    end
end
print('Constellation prediction: draws, weights, fallback, exclusions, capacity, per-mission acceptance and exclusion, city scope and '..recorded..' recorded native seeds passed')
