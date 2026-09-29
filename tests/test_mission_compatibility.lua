local root=arg[1];local C=dofile(root..'/mission_compatibility.lua')
local choose_category=dofile(root..'/mission_category_choice.lua')
local rng=dofile(root..'/generation_rng.lua')
local choose_mission=dofile(root..'/mission_weighted_choice.lua')(rng)
local options={{ids={10}},{ids={11}},{ids={12}},{ids={13}}}
local candidates={{id=10,category=1},{id=11,category=1},{id=12,category=2},{id=13,category=3}}
local rules={{category=1,minimum=1,maximum=1,weight=1},{category=2,minimum=1,maximum=1,weight=1},{category=3,minimum=1,maximum=1,weight=1}}
local masks=C.missions(candidates,rules,3,options)
local profiles={{masks=masks,modifiers={77}}}
assert(not C.possible(profiles,{[1]=true,[2]=true},{}),'Mutually exclusive category choices must be disabled')
assert(C.possible(profiles,{[1]=true,[3]=true,[4]=true},{}))
assert(not C.possible(profiles,{[1]=true},{[77]='exclude'}))
assert(C.possible(profiles,{[1]=true},{[77]='require'}))
assert(not C.possible({{masks={[C.bit(1)]=true},modifiers={}},{masks={[C.bit(2)]=true},modifiers={}}},{[1]=true,[2]=true},{}),'Cannot combine different templates')
-- Masks hold any family, not only the first thirty-two.
local wide=C.mask({[1]=true,[31]=true,[74]=true,[120]=true})
assert(C.covers(wide,C.bit(74)) and C.covers(wide,C.mask({[1]=true,[120]=true})) and not C.covers(wide,C.bit(73)))
assert(C.union(C.bit(31),C.bit(61))==C.union(C.bit(61),C.bit(31)) and C.bit(31)~=C.bit(61) and C.covers(wide,C.none))
assert(not pcall(C.bit,0) and not pcall(C.bit,121) and not pcall(C.bit,1.5))
local many={};for i=1,74 do many[i]={ids={200+i}}end
local far=C.missions({{id=201,category=1},{id=274,category=1},{id=240,category=2}},{},3,many)
assert(C.possible({{masks=far,modifiers={}}},{[1]=true,[74]=true,[40]=true},{}),'Families beyond thirty-two combine')
assert(not C.possible({{masks=far,modifiers={}}},{[1]=true,[73]=true},{}))
local combos=C.modifiers({{id=1,cost=1},{id=2,cost=1},{id=3,cost=2}},2)
for _,mods in ipairs(combos)do assert(#mods==1 and mods[1]==3 or #mods==2 and mods[1]~=3 and mods[2]~=3)end
assert(#combos==3,'Only terminal modifier draws are reachable')
-- Compare structural reachability with actual native-ported choosers, including
-- fallback/wildcard and zero-weight cases. Never reject an observed outcome.
for _,case in ipairs({rules,{},{{category=7,minimum=1,maximum=1,weight=1}},
    {{category=1,minimum=0,maximum=1,weight=0},{category=2,minimum=0,maximum=1,weight=0}},
    {{category=1,minimum=0,maximum=1,weight=1},{category=2,minimum=0,maximum=2,weight=3},{category=3,minimum=0,maximum=1,weight=0}}})do
    local reachable=C.missions(candidates,case,3,options)
    for seed=0,511 do
        local random=rng(seed);local usage,counts,mask={},{},C.none
        for slot=1,3 do
            local pool=choose_category(candidates,case,usage,random)
            local kind=choose_mission(pool,{[10]=1,[11]=2,[12]=3,[13]=0},counts,random:next(),seed)
            local category;for _,m in ipairs(candidates)do if m.id==kind then category=m.category end end
            usage[category]=(usage[category]or 0)+1;mask=C.union(mask,C.family(kind,options))
        end
        assert(reachable[mask],'Compatibility rejected a legal ported-generator outcome')
    end
end
print('Mission compatibility: wide family masks, category conflicts, cross-template conflicts, modifier budgets and 2560 generated outcomes passed')
