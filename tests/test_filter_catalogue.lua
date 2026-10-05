local root=arg[1];local C=dofile(root..'/filter_catalogue.lua');local S=dofile(root..'/search_session.lua')
local make_search=dofile(root..'/seed_search.lua');local Rules=dofile(root..'/filter_rules.lua')
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
    C.validate(c,{required={[c.missions[1].id]=true},modifiers={[mod]='exclude'}})
    C.validate(c,{required={},modifiers={[mod]='require'}})
    assert(not pcall(C.validate,c,{required={}}))
    assert(not pcall(C.validate,c,{required={[8]=true}}))
    assert(not pcall(C.validate,c,{required={},modifiers={[modifier_by_faction[faction==2 and 3 or 2]]='require'}}))
end
local op={difficulty=10,valid=true,missions={{native_type=59}},modifiers={spores}}
assert(S.find({operations={op}},10,{required={[1]=true},modifiers={[spores]='require',[gunships]='exclude'}})==op)
assert(not S.find({operations={op}},10,{required={[1]=true},modifiers={[spores]='exclude'}}))
assert(not S.find({operations={op}},10,{required={[1]=true},modifiers={[gunships]='require'}}))
assert(not S.find({operations={{difficulty=10,missions={}}}},10,{required={},modifiers={[gunships]='exclude'}}),'Unknown modifier data cannot satisfy exclusions')
-- An excluded family rejects the operation wherever it appears, whatever
-- the constellations of its mission.
local pair={difficulty=10,valid=true,missions={{native_type=59,tags={[2]=true}},{native_type=22,tags={[4]=true}}},modifiers={}}
assert(not S.find({operations={pair}},10,{required={[1]=true},excluded={[2]=true}}),'Geological Survey is excluded')
assert(not S.find({operations={pair}},10,{required={},constellations={groups={[0]={[2]='accept'}}},excluded={[2]=true}}))
assert(not S.find({operations={pair}},10,{required={[1]=true},constellations={groups={[1]={[2]='accept'}}},excluded={[2]=true}}))
assert(S.find({operations={pair}},10,{required={[1]=true},excluded={[3]=true}})==pair,'An absent family is no obstacle')
assert(S.find({operations={op,pair}},10,{required={},excluded={[2]=true}})==op,'The next operation without it matches')
assert(S.find({operations={pair}},10,{required={},excluded={}})==pair)
local rules={[spores]='require'}
local search=make_search(function()return {op}end,S,{seed=1,limit=2,difficulty=10,rules=Rules.new({modifiers=rules})})
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
C.validate(c,{required={[9]=true,[10]=true},constellations={groups={[9]={[8]='accept'},[10]={[2]='accept',[3]='exclude'}}}})
C.validate(c,{required={},constellations={groups={[0]={[8]='exclude',[2]='exclude'}}}})
C.validate(c,{required={[9]=true},constellations={groups={[9]={}}}})
local function rejected(required,filter)return not pcall(C.validate,c,{required=required,constellations={groups=filter}})end
assert(rejected({},{}) and rejected({},{[0]={}}),'Empty groups are not a filter')
assert(rejected({[9]=true,[10]=true},{[10]={[8]='accept'}}),'Constellation removed for that mission')
assert(rejected({[9]=true},{[9]={[6]='accept'}}) and rejected({[9]=true},{[9]={[4]='exclude'}}),'Disabled and unweighted constellations')
assert(rejected({[9]=true},{[10]={[2]='accept'}}),'Constellations need their mission checked')
assert(rejected({[9]=true},{[0]={[2]='accept'}}),'The operation group excludes checked missions')
assert(rejected({},{[0]={[2]='require'}}) and rejected({},{[0]={[2]=true}}) and rejected({[7]=true},{[7]={[2]='accept'}}))
assert(C.possible(c,{required={[9]=true},constellations={groups={[9]={[2]='accept',[3]='accept',[8]='accept'}}}}))
-- A mission always draws one of its constellations: excluding all of them
-- is impossible, unless a drawn one can be removed afterwards.
assert(groups[9].open and C.possible(c,{required={[9]=true},constellations={groups={[9]={[2]='exclude',[3]='exclude',[8]='exclude'}}}}),
    'Tag 6 is drawn and then removed by the configuration, which leaves the mission without any')
local configured=tags.disabled;tags.disabled=function()return false end
local d=sample(true);tags.disabled=configured
assert(ids(d.constellation_groups[9])=='2,3,6,8' and not d.constellation_groups[9].open)
assert(C.possible(d,{required={[9]=true},constellations={groups={[9]={[2]='exclude',[3]='exclude',[6]='exclude'}}}}),'Several exclusions leave one to draw')
local all={[2]='exclude',[3]='exclude',[6]='exclude',[8]='exclude'}
local possible,why=C.possible(d,{required={[9]=true},constellations={groups={[9]=all}}})
assert(not possible and why=='Every constellation of this mission is excluded')
assert(not pcall(C.validate,d,{required={[9]=true},constellations={groups={[9]=all}}}))
assert(d.constellation_groups[10].open and C.possible(d,{required={[10]=true},constellations={groups={[10]={[2]='exclude',[3]='exclude',[6]='exclude'}}}}),
    'Purge Hatcheries can lose its drawn tag 8')
assert(d.constellation_groups[0].open and C.possible(d,{required={},constellations={groups={[0]=all}}}))
forced={9};c=sample(true)
assert(ids(c.constellation_groups[9])=='2,8' and c.forced[1]==9,'Planet-wide tags hide only-when-empty candidates')
-- The unit tooltip's input: kept planet-wide tags plus the hovered one, and
-- the spawn weights, read once and only when asked.
local spawns=0
tags.spawn=function(planet,effect)
    assert(planet==100 and effect==4294967295);spawns=spawns+1;return {[7]=2},{[8]=0.5}
end
forced={9,6,9};c=sample(true);assert(spawns==0,'No spawn reads before a hover')
local input=c.forecast(2)
assert(input.faction==2 and input.difficulty==10 and table.concat(input.tags,',')=='9,2','Disabled and repeated tags dropped')
assert(input.zone[7]==2 and input.war[8]==0.5)
assert(table.concat(c.forecast(9).tags,',')=='9' and spawns==1,'A planet-wide tag is not added twice; weights read once')
tags.spawn=nil;forced={9}
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
-- Side objectives: rows a mission type can draw on this planet and
-- difficulty, slots per type, and the checks on a request.
do
    local P=dofile(root..'/side_objective_prediction.lua')
    local lidar,artillery,sam,spewer,broadcast,pod=0xf1969b14,0x86cfeedb,0xc46443b2,0x62f023e9,0x4c10b12e,0xfdab51c3
    local jammer,eggs,nest,larva=0x6cac3f28,0xca82b4ab,0xb3dd50be,0x3209b101
    local records={[lidar]={id=lidar,minimum=0,maximum=0,environments={1,2,3,4}},[artillery]={id=artillery,minimum=0,maximum=0,environments={0,0,0,0}},
        [sam]={id=sam,minimum=0,maximum=0,environments={0,0,0,0}},[spewer]={id=spewer,minimum=2,maximum=0,environments={0,0,0,0}},
        [broadcast]={id=broadcast,minimum=0,maximum=0,environments={0,0,0,0}},[pod]={id=pod,minimum=0,maximum=0,environments={0,0,0,0}},
        [jammer]={id=jammer,minimum=0,maximum=0,environments={7,0,0,0}},[eggs]={id=eggs,minimum=0,maximum=0,environments={0,0,0,0}},
        [nest]={id=nest,minimum=0,maximum=0,environments={0,0,0,0}},
        [larva]={id=larva,minimum=0,maximum=0,environments={0,0,0,0}}}
    for _,r in pairs(records)do r.cap,r.mask=1,0 end
    local function pool(list)
        local out={}
        for _,e in ipairs(list)do out[#out+1]={id=e[1],role=e[2],weight=e[3] or 1,minimum=0,maximum=1}end
        return out
    end
    local missions={
        [0]={category=1,pool=pool({{lidar,3},{artillery,3},{spewer,3},{jammer,3},{broadcast,2},{pod,2},{eggs,3,0},{nest,3},{larva,2}})},
        [59]={category=1,pool=pool({{sam,3},{artillery,3},{pod,2},{broadcast,3}})},
        [7]={category=2,pool=pool({{lidar,3}})},
    }
    local inputs={context=function(_,effect)return {modifiers={},banned=effect==2 and {[sam]=true} or {}}end,
        counts=function(d)return {side=d>=6 and 3 or 1,tactical=1,substeps=0}end,
        mission=function(kind)return missions[kind]end,scale=function(category)return category==2 and 0 or nil end,
        environments=function()return function()return 1 end,{[1]=true}end,
        objective=function(id)return records[id]end,disabled=function(id)return id==pod end}
    local c={mission_set={[1]=true,[3]=true},native={[0]=true,[59]=true,[7]=true},effects={[1]=true}}
    C.objectives(c,inputs,P,100,6,S.options)
    local icbm,eradicate,any=c.objective_groups[1],c.objective_groups[3],c.objective_groups[0]
    local function names(group)local out={};for _,row in ipairs(group.list)do out[#out+1]=row.name end;return table.concat(out,', ')end
    -- Side objectives first; Illegal Broadcast is side on type 59, so side here.
    assert(names(icbm)=='Lidar Station, SEAF Artillery, SEAF SAM Site, Shrieker Nest, Spore Spewer, Terminate Illegal Broadcast, Retrieve Mutant Larva',names(icbm))
    assert(icbm.list[6].role==3 and icbm.list[7].role==2 and icbm.list[1].role==3,'Roles')
    assert(icbm.kinds[0].rows[broadcast]==2 and icbm.kinds[59].rows[broadcast]==3,'Per type, its own role')
    assert(names(eradicate)=='','Category scale 0 offers nothing')
    assert(any.set[lidar] and any.set[sam] and not any.set[jammer] and not any.set[pod] and not any.set[eggs],'Environment, configuration and weight')
    assert(icbm.kinds[0].side==3 and icbm.kinds[0].tactical==1 and icbm.kinds[7]==nil and eradicate.kinds[7].side==0)
    -- A row banned by every operation's world modifiers is not offered.
    local banned={mission_set={[1]=true},native={[59]=true},effects={[2]=true}}
    C.objectives(banned,inputs,P,100,6,S.options)
    assert(not banned.objective_groups[1].set[sam],'Banned everywhere')
    banned.effects[1]=true;C.objectives(banned,inputs,P,100,6,S.options)
    assert(banned.objective_groups[1].set[sam],'Allowed by one operation')
    -- Below the minimum difficulty Spore Spewer is gone.
    local low={mission_set={[1]=true},native={[0]=true},effects={[1]=true}}
    C.objectives(low,inputs,P,100,1,S.options)
    assert(not low.objective_groups[1].set[spewer] and low.objective_groups[1].kinds[0].side==1)
    local function rules(group,list)return {groups={[group]=list}}end
    local required={[1]=true}
    c.slots,c.missions,c.modifier_set,c.mission_set=3,{{id=1},{id=3}},{},{[1]=true,[3]=true}
    assert(C.possible(c,{required=required,objectives=rules(1,{[lidar]='require',[artillery]='require',[spewer]='require'})}))
    local ok,why=C.possible(c,{required=required,objectives=rules(1,{[lidar]='require',[artillery]='require',[spewer]='require',[nest]='require'})})
    assert(not ok and why:find('Too many'),why)
    assert(C.possible(c,{required=required,objectives=rules(1,{[sam]='require',[artillery]='require'})}),'Another mission type of the family holds them')
    ok,why=C.possible(c,{required=required,objectives=rules(1,{[lidar]='require',[sam]='require'})})
    assert(not ok and why:find('cannot draw'),'No one type offers both')
    ok,why=C.possible(c,{required=required,objectives=rules(1,{[broadcast]='exclude'})})
    assert(ok,'Mission 59 has no tactical row offered here, so excluding broadcast is fine')
    -- Only 59 draws SAM, and its three side slots take all three of its rows.
    ok,why=C.possible(c,{required=required,objectives=rules(1,{[broadcast]='exclude',[sam]='require'})})
    assert(not ok and why=='Too many excluded side objectives for this mission and difficulty',why)
    local all={};for _,row in ipairs(icbm.list)do all[row.id]='exclude' end;all[sam]=nil
    ok,why=C.possible(c,{required=required,objectives=rules(1,all)})
    assert(not ok and why=='Every side objective of this mission is excluded',why)
    all[sam]='exclude'
    ok,why=C.possible(c,{required=required,objectives=rules(1,all)})
    assert(not ok and why:find('excluded'),why)
    -- Three side slots: what is left must fill them. Type 0 keeps Artillery
    -- and Spore Spewer, type 59 SEAF SAM Site and Artillery.
    assert(C.possible(c,{required=required,objectives=rules(1,{[lidar]='exclude',[nest]='exclude'})}),'59 keeps three side rows')
    ok,why=C.possible(c,{required=required,objectives=rules(1,{[lidar]='exclude',[nest]='exclude',[broadcast]='exclude'})})
    assert(not ok and why=='Too many excluded side objectives for this mission and difficulty',why)
    -- A title with spare copies fills two slots.
    missions[0].pool[1].maximum=4;records[lidar].cap=2
    local copies={mission_set={[1]=true},native={[0]=true},effects={[1]=true},slots=3,missions={{id=1}},modifier_set={}}
    C.objectives(copies,inputs,P,100,6,S.options)
    assert(C.possible(copies,{required=required,objectives=rules(1,{[artillery]='exclude',[nest]='exclude'})}),'Lidar twice and Spore Spewer')
    ok,why=C.possible(copies,{required=required,objectives=rules(1,{[artillery]='exclude',[nest]='exclude',[spewer]='exclude'})})
    assert(not ok and why:find('Too many excluded'),why)
    missions[0].pool[1].maximum=1;records[lidar].cap=1
    -- The reported case: four side slots, five rows of one copy, two excluded.
    local five={mission_set={[1]=true},missions={{id=1}},slots=3,objective_groups={[1]={list={},set={},
        kinds={[0]={side=4,tactical=0,rows={},entries={}}}}}}
    for _,row in ipairs({lidar,artillery,sam,spewer,nest})do
        five.objective_groups[1].kinds[0].rows[row]=3
        local e=five.objective_groups[1].kinds[0].entries;e[#e+1]={row=row,role=3,copies=1,mask=0}
    end
    assert(C.possible(five,{required=required,objectives=rules(1,{[lidar]='exclude'})}),'One excluded leaves four')
    ok,why=C.possible(five,{required=required,objectives=rules(1,{[lidar]='exclude',[sam]='exclude'})})
    assert(not ok and why:find('Too many excluded'),why)
    -- A mask bit shared with a row left drops the excluded row from the draw.
    local masked={mission_set={[1]=true},missions={{id=1}},slots=3,objective_groups={[1]={list={},set={},
        kinds={[0]={side=0,tactical=2,rows={[broadcast]=2,[larva]=2},entries={{row=broadcast,role=2,copies=1,mask=1},{row=larva,role=2,copies=1,mask=1}}}}}}}
    assert(C.possible(masked,{required=required,objectives=rules(1,{[larva]='exclude'})}),'Drawing Broadcast drops Larva')
    masked.objective_groups[1].kinds[0].entries[2].mask=2
    assert(not C.possible(masked,{required=required,objectives=rules(1,{[larva]='exclude'})}),'Larva stays in the draw')
    -- Any mission: one type must avoid every excluded row. Type 7 draws none.
    assert(C.possible(c,{required={},objectives=rules(0,{[artillery]='exclude',[nest]='exclude',[lidar]='exclude'})}),'Eradicate avoids them')
    local eradicate7=any.kinds[7];any.kinds[7]=nil
    ok,why=C.possible(c,{required={},objectives=rules(0,{[artillery]='exclude',[nest]='exclude',[lidar]='exclude'})})
    assert(not ok and why=='Too many excluded side objectives for every mission here',why)
    any.kinds[7]=eradicate7
    assert(C.possible(c,{required={},objectives=rules(0,{[sam]='require',[spewer]='require'})}))
    ok,why=C.possible(c,{required={},objectives=rules(0,{[jammer]='require'})})
    assert(not ok,'Not offered anywhere')
    -- validate: the group needs its mission, rows must be offered, and one
    -- rule group alone is a request.
    C.validate(c,{required={},objectives=rules(0,{[lidar]='require'})})
    C.validate(c,{required=required,objectives=rules(1,{[artillery]='exclude'})})
    assert(not pcall(C.validate,c,{required={},objectives=rules(1,{[lidar]='require'})}),'Group without its mission')
    assert(not pcall(C.validate,c,{required=required,objectives=rules(1,{[jammer]='require'})}),'Unavailable row')
    assert(not pcall(C.validate,c,{required=required,objectives=rules(1,{[lidar]='accept'})}),'Unknown mode')
    -- The seed search accepts the same groups.
    local search=make_search(function()return {}end,S,{seed=1,limit=1,difficulty=10,rules=Rules.new({objectives=rules(0,{[lidar]='require'})})})
    assert(search:step()=='exhausted')
    assert(not pcall(make_search,function()return {}end,S,{seed=1,limit=1,difficulty=10,rules=Rules.new({objectives=rules(1,{[lidar]='require'})})}))
end
print('Faction catalogue: city scope, constellation candidates, all three factions, mission visibility, legal modifier pools/budgets, side objectives, request validation and require/exclude matching passed')
