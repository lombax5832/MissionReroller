local root=arg[1];local C=dofile(root..'/filter_catalogue.lua');local S=dofile(root..'/search_session.lua')
local make_search=dofile(root..'/seed_search.lua')
local spores,gunships,leviathan=0x1101e25c,0xf6f1b0c7,0xa92f094f
local mission_by_faction={[2]=79,[3]=21,[4]=119}
local modifier_by_faction={[2]=spores,[3]=gunships,[4]=leviathan}
for faction=2,4 do
    local mod=modifier_by_faction[faction]
    local s={planet=100,operations='',decoded={operations={{row=0,operation_id=1,difficulty=10}}}}
    local function u(_,offset)if offset==36 then return faction end;return 0 end
    local inputs={effect_id=function()return 4294967295 end,difficulty=function()return 1,3 end,
        templates=function(op)assert(op.faction==faction);return {{index=5,modifiers={{id=mod,cost=1},{id=0xa0687641,cost=500}}}}end,
        candidates=function(index,op)assert(index==5 and op.faction==faction);return {{id=mission_by_faction[faction]}}end,
        extra_mission=function()return nil end}
    local c=C.build(inputs,s,10,u,S.options)
    assert(c.faction==faction and #c.missions==1 and #c.modifiers==1)
    assert(c.modifier_set[mod] and not c.modifier_set[0xa0687641],'Unaffordable modifier hidden')
    assert(c.missions[1].id==({[2]=9,[3]=11,[4]=1})[faction],'Other factions mission families hidden')
    C.validate(c,{[c.missions[1].id]=true},{[mod]='exclude'})
    C.validate(c,{}, {[mod]='require'})
    assert(not pcall(C.validate,c,{},{}))
    assert(not pcall(C.validate,c,{[8]=true},{}))
    assert(not pcall(C.validate,c,{}, {[modifier_by_faction[faction==2 and 3 or 2]]='require'}))
end
local op={difficulty=10,valid=true,missions={{native_type=59}},modifiers={spores}}
assert(S.find({operations={op}},10,{[1]=true},{[spores]='require',[gunships]='exclude'})==op)
assert(not S.find({operations={op}},10,{[1]=true},{[spores]='exclude'}))
assert(not S.find({operations={op}},10,{[1]=true},{[gunships]='require'}))
assert(not S.find({operations={{difficulty=10,missions={}}}},10,{}, {[gunships]='exclude'}),'Unknown modifier data cannot satisfy exclusions')
local rules={[spores]='require'}
local search=make_search(function()return {op}end,S,{seed=1,limit=2,difficulty=10,required={},modifiers=rules})
rules[spores]='exclude';assert(search:step()=='matched','Modifier-only filter copied into search')
-- Constellation options: weighted, enabled base candidates for the faction.
local labels=dofile(root..'/constellation_prediction.lua').names
local forced,asked,draws={},{},1
-- Eligible mission types: 79 Nuke Nursery, 66 Purge Hatcheries (its record
-- removes tag 8), 12 Search and Destroy of another faction, 150 outside the
-- named families (its record removes tag 2).
local records={[79]={faction=2,exclusions={}},[66]={faction=2,exclusions={8,12}},
    [12]={faction=3,exclusions={}},[150]={faction=2,exclusions={2}}}
local tags={settings=function(faction,difficulty)
        asked[#asked+1]=faction..':'..difficulty
        return {draws=draws,candidates={{id=2,weight=1},{id=3,weight=0.5,only_when_empty=true},{id=4,weight=0},
            {id=0,weight=0},{id=6,weight=1},{id=2,weight=1},{id=8,weight=0.7}}}
    end,campaign=function(planet,effect)assert(planet==100 and effect==4294967295);return forced end,
    mission=function(kind)return assert(records[kind],'Only eligible mission types are decoded')end,
    disabled=function(id)return id==6 end}
local function sample(with_tags)
    local s={planet=100,operations='',decoded={operations={{row=0,operation_id=1,difficulty=10}}}}
    local inputs={effect_id=function()return 4294967295 end,difficulty=function()return 1,3 end,
        templates=function()return {{index=5,modifiers={}}}end,
        candidates=function()return {{id=79},{id=66},{id=12},{id=150}}end,extra_mission=function()return nil end}
    local c=C.build(inputs,s,10,function(_,offset)return offset==36 and 2 or 0 end,S.options)
    if with_tags then C.constellations(c,tags,labels,s.planet,10,S.options)end
    return c
end
local function ids(group)local out={};for i,option in ipairs(group.list)do out[i]=option.id end;return table.concat(out,',')end
local c=sample(true);local groups=c.constellation_groups
for _,key in ipairs(asked)do assert(key=='2:10','Settings follow the mission faction and map difficulty')end
assert(ids(groups[9])=='2,3,8','Zero-weight, empty, duplicate and disabled candidates are hidden')
assert(ids(groups[10])=='2,3','Tags removed by the mission record are hidden for that mission')
assert(ids(groups[7])=='','A mission type of another faction offers nothing')
assert(ids(groups[0])=='2,3,8' and not groups[1],'Any-mission options unite every eligible mission type')
assert(groups[9].list[1].name=='Bile Bugs (BugAcid)' and groups[9].set[8] and not groups[10].set[8])
C.validate(c,{[9]=true,[10]=true},{},{groups={[9]={[8]='accept'},[10]={[2]='accept',[3]='exclude'}}})
C.validate(c,{},{},{groups={[0]={[8]='exclude',[2]='exclude'}}})
C.validate(c,{[9]=true},{},{groups={[9]={}}})
local function rejected(required,filter)return not pcall(C.validate,c,required,{},{groups=filter})end
assert(rejected({},{}) and rejected({},{[0]={}}),'Empty groups are not a filter')
assert(rejected({[9]=true,[10]=true},{[10]={[8]='accept'}}),'Constellation removed for that mission')
assert(rejected({[9]=true},{[9]={[6]='accept'}}) and rejected({[9]=true},{[9]={[4]='exclude'}}),'Disabled and unweighted constellations')
assert(rejected({[9]=true},{[10]={[2]='accept'}}),'Constellations need their mission checked')
assert(rejected({[9]=true},{[0]={[2]='accept'}}),'The operation group excludes checked missions')
assert(rejected({},{[0]={[2]='require'}}) and rejected({},{[0]={[2]=true}}) and rejected({[7]=true},{[7]={[2]='accept'}}))
assert(C.possible(c,{[9]=true},{},{groups={[9]={[2]='accept',[3]='accept',[8]='accept'}}}))
-- A mission always draws one of its constellations: excluding all of them
-- is impossible, unless a drawn one can be removed afterwards.
assert(groups[9].open and C.possible(c,{[9]=true},{},{groups={[9]={[2]='exclude',[3]='exclude',[8]='exclude'}}}),
    'Tag 6 is drawn and then removed by the configuration, which leaves the mission without any')
local configured=tags.disabled;tags.disabled=function()return false end
local d=sample(true);tags.disabled=configured
assert(ids(d.constellation_groups[9])=='2,3,6,8' and not d.constellation_groups[9].open)
assert(C.possible(d,{[9]=true},{},{groups={[9]={[2]='exclude',[3]='exclude',[6]='exclude'}}}),'Several exclusions leave one to draw')
local all={[2]='exclude',[3]='exclude',[6]='exclude',[8]='exclude'}
local possible,why=C.possible(d,{[9]=true},{},{groups={[9]=all}})
assert(not possible and why=='Every constellation of this mission is excluded')
assert(not pcall(C.validate,d,{[9]=true},{},{groups={[9]=all}}))
assert(d.constellation_groups[10].open and C.possible(d,{[10]=true},{},{groups={[10]={[2]='exclude',[3]='exclude',[6]='exclude'}}}),
    'Purge Hatcheries can lose its drawn tag 8')
assert(d.constellation_groups[0].open and C.possible(d,{},{},{groups={[0]=all}}))
forced={9};c=sample(true)
assert(ids(c.constellation_groups[9])=='2,8' and c.forced[1]==9,'Planet-wide tags hide only-when-empty candidates')
draws=0;assert(ids(sample(true).constellation_groups[0])=='','No draw, no constellation')
assert(next(sample(false).constellation_groups)==nil,'Catalogues without tag inputs offer none')
-- City scope: only accepted rows contribute missions, modifiers and effects.
do
    local s={planet=100,operations='',decoded={operations={{row=29,operation_id=1,difficulty=10,missions={}},
        {row=49,operation_id=1,difficulty=10,missions={}},{row=48,operation_id=1,difficulty=9,missions={}}}}}
    local inputs={effect_id=function(op)return op.row==49 and 1 or 4294967295 end,difficulty=function()return 1,3 end,
        templates=function(op)return {{index=op.row,modifiers={{id=op.row==49 and gunships or spores,cost=1}}}}end,
        candidates=function(index)return {{id=index==49 and 21 or 79}}end,extra_mission=function()return nil end}
    local function u(_,offset)return offset%92==36 and 3 or 0 end
    local asked
    local stub={settings=function()return {draws=1,candidates={{id=14,weight=1}}}end,disabled=function()return false end,
        mission=function()return {faction=3,exclusions={}}end,campaign=function(_,effect)asked=effect;return {}end}
    local function build(accepts)
        local c=C.build(inputs,s,10,u,S.options,nil,accepts)
        C.constellations(c,stub,labels,s.planet,10,S.options);return c
    end
    local whole=build(nil)
    assert(#whole.missions==2 and #whole.modifiers==2 and asked==4294967295,'The whole planet mixes city and planet options')
    local city=build(function(row)return S.in_scope(row,{region=1})end)
    assert(#city.missions==1 and city.missions[1].id==11 and #city.modifiers==1 and city.modifiers[1].id==gunships)
    assert(asked==1 and city.constellation_groups[11] and not city.constellation_groups[9],'A city reports its own effects and missions')
    assert(not pcall(build,function(row)return S.in_scope(row,{region=3})end),'A city without an operation has no catalogue')
end
print('Faction catalogue: city scope, constellation candidates, all three factions, mission visibility, legal modifier pools/budgets, request validation and require/exclude matching passed')
