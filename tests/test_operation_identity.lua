local make_rng=dofile(arg[1])
local predict=dofile(arg[2])(make_rng)
local fixture=dofile(arg[3])
for _,vector in ipairs(fixture.rng)do
    local rng=make_rng(vector.seed,vector.planet)
    for _,value in ipairs(vector.values)do assert(rng:next()==value,'RNG differs from exact integer oracle')end
end
local cases,rows=0,0
for _,case in ipairs(fixture.cases)do
    local actual=predict(case.input,case.seed)
    local n=0
    for row in pairs(actual)do n=n+1 end
    assert(n==#case.expected,'Row count differs')
    for _,expected in ipairs(case.expected)do
        local observed=assert(actual[expected.row],'Missing row')
        for _,key in ipairs({'id','seed','difficulty'})do
            assert(observed[key]==expected[key],string.format('seed=%u row=%d %s: expected %s got %s',case.seed,expected.row,key,tostring(expected[key]),tostring(observed[key])))
        end
        rows=rows+1
    end
    cases=cases+1
end
-- The four-row mask must reserve an active row belonging to the next difficulty.
local input={planet=7,pool_count=2,max_difficulty=1,active={planet=7,row=3,id=0,seed=42,difficulty=2}}
local actual=predict(input,12)
assert(actual[0].id==1 and actual[1]==nil and actual[2]==nil and actual[3].seed==42)
assert(input.active.seed==42 and input.active.preserved==nil,'Mutated caller data')
input.active.planet=8
actual=predict(input,12)
assert(actual[3]==nil and actual[0] and actual[1] and actual[2]==nil)
assert(not pcall(predict,{planet=7,pool_count=65,max_difficulty=10},0))
assert(not pcall(make_rng,4294967296,0))
print(string.format('Lua identity predictor: %d oracle cases / %d rows; exact uint64 vectors and mask/guard cases passed',cases,rows))
