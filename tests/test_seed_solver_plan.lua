-- Usage: luajit test_seed_solver_plan.lua <src/seed_solver_search.lua>
-- The one plan the search and the dialog's estimate share, with a stub
-- planet and source: which inputs a request needs, a source passed through,
-- each decline kind (unavailable inputs, no path or no Day / Night ID with
-- and without a campaign event row of the difficulty, in a city, any other
-- reason) and the seconds formula.
local R=dofile(arg[1])({},{},{},{},{})
local returned,seen
R.source=function(spec)seen=spec;return returned[1],returned[2]end

-- Mission-seed inputs for any enemy-force or side-objective group.
assert(R.seeded({required={[1]=true}})==false)
assert(R.seeded({constellations={groups={}},objectives={groups={}}})==false,'Empty rules need no seeded inputs')
assert(R.seeded({constellations={groups={[1]={[4]='accept'}}}})==true)
assert(R.seeded({objectives={groups={[0]={[7]='require'}}}})==true)
-- A group present is what source checks against the inputs, so it counts.
assert(R.seeded({constellations={groups={[2]={}}}})==true,'A group counts as source counts it')

-- prepare asks the planet once, with the difficulty, rules and region.
local asked
local planet={solver=function(definitions,difficulty,seeded,region)
    asked={definitions,difficulty,seeded,region}
    if definitions=='missing' then return nil,'Seed solver unavailable' end
    return {solver=true},{specials={}}
end}
local prepared=R.prepare(planet,0x1000,{difficulty=7,constellations={groups={[1]={[4]='accept'}}},scope={region=2}})
assert(asked[1]==0x1000 and asked[2]==7 and asked[3]==true and asked[4]==2,'prepare passes difficulty, seeded and region')
assert(prepared.solver and prepared.input)
R.prepare(planet,0x1000,{difficulty=3})
assert(asked[3]==false and asked[4]==nil)

-- Unavailable inputs: scanned, with the planet's reason; source not asked.
seen=nil
local source,decline=R.plan(R.prepare(planet,'missing',{difficulty=3}),{difficulty=3})
assert(not source and decline.kind=='scan' and decline.reason=='Seed solver unavailable' and not seen)

-- A source is passed through, the spec handed on with the inputs.
local function plan(input,spec,result,why)
    returned={result,why}
    return R.plan({solver={id='solver'},input=input},spec)
end
local made={estimate={match=0.5,steps=10}}
local spec={difficulty=5,required={[1]=true},estimate_only=true}
source,decline=plan({specials={}},spec,made)
assert(source==made and decline==nil)
assert(seen.solver.id=='solver' and seen.input.specials and seen.difficulty==5 and seen.required[1] and seen.estimate_only,
    'source gets the inputs and the spec')
assert(spec.solver==nil,'The caller\'s spec is left as it was')

-- No path or no Day / Night ID: impossible unless a campaign event row of
-- the difficulty could still match (the search scans for it).
local event={specials={{minimum=4,maximum=6}}}
local elsewhere={specials={{minimum=8,maximum=10}}}
for _,why in ipairs({'no draw path','no operation passes Day / Night'})do
    source,decline=plan({specials={}},{difficulty=5},nil,why)
    assert(not source and decline.kind=='impossible' and decline.reason==why,why..': no event row')
    source,decline=plan({},{difficulty=5},nil,why)
    assert(decline.kind=='impossible',why..': no specials listed')
    source,decline=plan(elsewhere,{difficulty=5},nil,why)
    assert(decline.kind=='impossible',why..': an event row at other difficulties')
    source,decline=plan(event,{difficulty=5},nil,why)
    assert(decline.kind=='scan' and decline.reason==why,why..': an event row of the difficulty')
    source,decline=plan(event,{difficulty=5,scope={region=1}},nil,why)
    assert(decline.kind=='impossible',why..': a city has no other operation')
end
-- Any other reason: scanned.
for _,why in ipairs({'no required mission','modifier missions','operations at the difficulty differ','mission-seed inputs missing'})do
    source,decline=plan({specials={}},{difficulty=5},nil,why)
    assert(not source and decline.kind=='scan' and decline.reason==why,why)
end

-- Seconds: set-up, steps at the rate, 0.3 s to confirm.
assert(R.seconds(1000,1000,0)==1.3)
assert(math.abs(R.seconds(800000,800000,0.2)-1.5)<1e-12)
assert(math.abs(R.seconds(7000,1000,0.5)-7.8)<1e-12)
print('Seed solver plan: seeded inputs, prepare, source, impossible and scan declines and seconds passed')
