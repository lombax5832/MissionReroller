local choose=dofile(arg[1]..'/mission_level_choice.lua')
local make_rng=dofile(arg[1]..'/generation_rng.lua')
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local cases=dofile(arg[2])
for i,case in ipairs(cases)do
    local rng=make_rng(0,0,raw(case.state))
    local result=choose(case.levels,case.special,case.slot,case.used,rng)
    assert((result or 4294967295)==case.result,'Level differs from native picker in case '..i)
    assert(rng:state_bytes()==raw(case.after),'RNG consumption differs in case '..i)
end
assert(not pcall(make_rng,0,0,'short'))
assert(not pcall(choose,{1},true,-1,{},make_rng(0)))
local rng=make_rng(4294967295,511);rng:next()
local restored=make_rng(0,0,rng:state_bytes());assert(restored:next()==rng:next(),'RNG state round trip failed')
print('Level picker: '..#cases..' native results and complete RNG states matched, including exhausted and repeated-level paths')
