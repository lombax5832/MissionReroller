-- Usage: luajit test_seed_solver_math.lua <src> <cases.lua>
-- Checks src/seed_solver_math.lua against answers the Python prototype
-- (scripts/seed_chain.py) computed: the 128-bit Euclid, the three-gap walk
-- and the inversion. tests/test_seed_solver_lua.py writes the cases.
local root,cases=arg[1],dofile(arg[2])
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local S=H.module(root..'/seed_solver_math.lua')
local ffi=require('ffi')
-- Decimal uint64 strings: parse exactly.
local function parse(text)
    local v=0ULL
    for d in text:gmatch('%d')do v=v*10ULL+ffi.new('uint64_t',tonumber(d))end
    return v
end
local function show(v)return v==nil and 'nil' or tostring(v):gsub('ULL$','')end

for k,c in ipairs(cases.first)do
    local got=S.first(parse(c[1]),parse(c[2]),parse(c[3]),parse(c[4]))
    local want=c[5]~='nil' and parse(c[5]) or nil
    assert(got==want or (got and want and got==want),
        string.format('first case %d: %s, expected %s',k,show(got),c[5]))
end

for k,c in ipairs(cases.output)do
    assert(S.output(c[1],c[2])==c[3],'output case '..k)
end

for k,c in ipairs(cases.walk)do
    local position,lo,hi,start,want=c[1],c[2],c[3],c[4],c[5]
    local w=S.walk(position,lo,hi)
    local s,off=w.start(start)
    local got={}
    while s and s<2^32 and #got<#want do got[#got+1]=s;s,off=w.advance(s,off)end
    assert(#got==#want,string.format('walk case %d: %d solutions, expected %d',k,#got,#want))
    for i=1,#want do assert(got[i]==want[i],string.format('walk case %d solution %d: %d, expected %d',k,i,got[i],want[i]))end
end

local out={}
for k,c in ipairs(cases.invert)do
    local position,value,want=c[1],c[2],c[3]
    local n=S.inverter(position)(value,out)
    local got={};for i=1,n do got[i]=out[i]end
    table.sort(got)
    assert(#got==#want,string.format('invert case %d (position %d): %d answers, expected %d',k,position,#got,#want))
    for i=1,#want do assert(got[i]==want[i],'invert case '..k)end
end
print(string.format('test_seed_solver_math: passed (%d first, %d walks, %d inversions)',
    #cases.first,#cases.walk,#cases.invert))
