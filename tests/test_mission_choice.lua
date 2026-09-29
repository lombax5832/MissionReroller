local choose=dofile(arg[1]..'/mission_weighted_choice.lua')(dofile(arg[1]..'/generation_rng.lua'))
for _,case in ipairs(dofile(arg[2]))do
    local weights,counts={},{}
    for i,id in ipairs(case.pool)do weights[id]=case.weights[i];counts[id]=case.counts[i]end
    local selected=choose(case.pool,weights,counts,case.mission_seed,case.operation_seed)
    assert(selected==case.selected,'Selected mission differs from native picker')
    for i,id in ipairs(case.pool)do assert(counts[id]==case.after[i],'Usage update differs from native picker')end
end
local counts={[59]=1}
assert(choose({59},{[59]=1},counts,0,0)==59 and counts[59]==1,'Singleton must not increment')
assert(not pcall(choose,{59,81},{},{},0,0),'Missing eligible weights must fail explicitly')
assert(not pcall(choose,{59,81},{[59]=0/0,[81]=1},{},0,0),'NaN must fail')
assert(not pcall(choose,{162},{},{},0,0),'Unknown mission type must fail')
print('Mission picker: native choice and usage counts, float rounding, singleton and invalid-input guards passed')
