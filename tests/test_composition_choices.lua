local root=arg[1];local cases=dofile(arg[2])
local eligible=dofile(root..'/mission_eligibility.lua')
local category=dofile(root..'/mission_category_choice.lua')
local rng=dofile(root..'/generation_rng.lua')
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
for i,c in ipairs(cases.eligibility)do
    assert(eligible(c.mission,c.context,c.category)==c.result,'Eligibility case '..i)
end
for i,c in ipairs(cases.category)do
    local state=rng(0,0,raw(c.state));local usage={}
    for cat,n in ipairs(c.usage)do usage[cat]=n end
    local selected=category(c.candidates,c.rules,usage,state)
    assert(#selected==#c.selected,'Category count case '..i)
    for j,id in ipairs(selected)do assert(id==c.selected[j],'Category order case '..i)end
    assert(state:state_bytes()==raw(c.after),'Category RNG case '..i)
end
local finalize=dofile(root..'/operation_finalization.lua')(rng)
for i,c in ipairs(cases.finalization)do
    local pool={};for _,id in ipairs(c.pool)do pool[#pool+1]=c.templates[id+1]end
    local result=finalize(c.seed,pool,c.explicit_hash,c.budget,c.templates)
    assert(result.valid==c.valid,'Finalizer validity case '..i)
    assert((result.template_index or 4294967295)==c.selected,'Finalizer template case '..i)
    assert(#result.modifiers==#c.modifiers,'Finalizer modifier count case '..i)
    for j,id in ipairs(result.modifiers)do assert(id==c.modifiers[j],'Finalizer modifier case '..i)end
end
print(string.format('Composition oracle: %d eligibility, %d category, %d finalizer cases passed',#cases.eligibility,#cases.category,#cases.finalization))
