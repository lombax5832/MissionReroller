-- Read eligibility through the same input decoder used by the predictor.
local bit=require('bit')
-- Names resolved from build 25480438 modifier metadata +0x38 localization keys.
local C={names={
    [0xd77ec510]='Poor Intel',[0xda18d5ef]='Complex Stratagem Plotting',
    [0xce7ef33a]='Orbital Fluctuations',[0x1101e25c]='Atmospheric Spores',
    [0x8ea68ae6]='Atmospheric Interference',[0x6da4a636]='Spore Cloud Pockets',
    [0x84aad4e6]='Roving Shriekers',[0xa0687641]='AA Defenses',
    [0xf6f1b0c7]='Gunship Patrols',[0xa92f094f]='Leviathan Blockade',
    [0x1d90ea70]='SEAF Units in Area',[0x5b2923a7]='Civilians in Area',
    [0x0724ab37]='Civilians & SEAF in Area',
}}
-- With a scope only the rows it accepts contribute, so the options are those
-- of one city or megafactory. C.constellations adds the tag options.
function C.build(inputs,s,difficulty,u,options,compatibility,accepts)
    local result={missions={},modifiers={},mission_set={},modifier_set={},slots=0,profiles={},
        constellation_groups={},forced={},effects={}}
    result.compatibility=compatibility
    local native,seen={},{}
    for _,base in ipairs(s.decoded.operations)do
        if base.difficulty==difficulty and (not accepts or accepts(base.row))then
            local at=base.row*92
            local op={id=base.operation_id,row=base.row,difficulty=difficulty,
                faction=u(s.operations,at+36),category=u(s.operations,at+28),explicit_hash=u(s.operations,at+8)}
            assert(op.faction>=2 and op.faction<=4,'Unsupported filter faction')
            assert(not result.faction or result.faction==op.faction,'Mixed planet factions')
            result.faction=op.faction;op.effect_id=inputs.effect_id(op,s.planet)
            result.effects[op.effect_id]=true
            local key=op.faction..':'..op.category..':'..op.effect_id..':'..op.explicit_hash
            if not seen[key]then
                seen[key]=true
                local budget,slots=inputs.difficulty(difficulty,op.category)
                result.slots=math.max(result.slots,slots)
                local explicit=op.explicit_hash~=0 and inputs.explicit(op.explicit_hash)
                local templates=explicit and {explicit} or inputs.templates(op,s.planet)
                for _,template in ipairs(templates)do
                    local candidates,weights,rules=inputs.candidates(template.index,op,s.planet)
                    if compatibility then
                        local masks=compatibility.missions(candidates,rules or {},slots,options)
                        for _,chosen in ipairs(compatibility.modifiers(template.modifiers,budget))do
                            local extra,extra_count=compatibility.none,0
                            if op.category==0 then for _,id in ipairs(chosen)do
                                local mission=inputs.extra_mission(id,op.faction)
                                if mission then extra=compatibility.union(extra,compatibility.family(mission,options));extra_count=extra_count+1 end
                            end end
                            result.slots=math.max(result.slots,math.min(3,slots+extra_count))
                            local combined={};for mask in pairs(masks)do combined[compatibility.union(mask,extra)]=true end
                            result.profiles[#result.profiles+1]={masks=combined,modifiers=chosen}
                        end
                    end
                    for _,m in ipairs(candidates)do native[m.id]=true end
                    for _,m in ipairs(template.modifiers)do
                        if m.cost<=budget then
                            assert(C.names[m.id],'Unknown modifier display name; catalogue unavailable')
                            result.modifier_set[m.id]=true
                            if op.category==0 then
                                local id=inputs.extra_mission(m.id,op.faction)
                                if id then native[id]=true end
                            end
                        end
                    end
                end
            end
        end
    end
    assert(result.faction,'No operation data for this difficulty')
    -- A currently displayed/preserved operation is a concrete compatibility
    -- witness even if overrides no longer allow generating it from scratch.
    if compatibility then for _,op in ipairs(s.decoded.operations)do if op.difficulty==difficulty and op.modifiers
        and (not accepts or accepts(op.row))then
        local mask=compatibility.none
        for _,mission in ipairs(op.missions)do mask=compatibility.union(mask,compatibility.family(mission.native_type,options))end
        result.profiles[#result.profiles+1]={masks={[mask]=true},modifiers=op.modifiers}
    end end end
    for id,opt in ipairs(options)do
        for _,kind in ipairs(opt.ids)do if native[kind]then
            result.mission_set[id]=true
            result.missions[#result.missions+1]={id=id,name=opt.name};break
        end end
    end
    table.sort(result.missions,function(a,b)return a.name<b.name end)
    for id in pairs(result.modifier_set)do result.modifiers[#result.modifiers+1]={id=id,name=C.names[id]}end
    table.sort(result.modifiers,function(a,b)return a.name<b.name end)
    result.native=native
    return result
end
-- Constellations a mission can draw: the weighted base candidates of its own
-- faction and this difficulty, without the tags its mission record or the
-- configuration removes afterwards. Group i covers the eligible mission types
-- of family i; group 0 covers every eligible mission type. Planet-wide tags
-- are reported separately because rerolling cannot alter them. The catalogue
-- changes only after every input decoded, so a failure leaves it without
-- constellation options instead of partially filled.
function C.constellations(catalogue,tags,labels,planet,difficulty,options)
    -- Operations of one city share its effects; a mixed catalogue reports
    -- only what applies to the whole planet.
    local effect=next(catalogue.effects or {})
    if effect==nil or next(catalogue.effects,effect)~=nil then effect=4294967295 end
    local forced=tags.campaign(planet,effect)
    local groups={[0]={list={},set={}}}
    local function offer(group,kind)
        local record=tags.mission(kind)
        if record.faction~=catalogue.faction then return end
        local settings=tags.settings(record.faction,difficulty)
        local removed={};for _,tag in ipairs(record.exclusions)do removed[tag]=true end
        for _,row in ipairs(settings.candidates)do
            if settings.draws>0 and row.id~=0 and row.weight>0 and not (row.only_when_empty and #forced>0)then
                for _,target in ipairs({group,groups[0]})do
                    if removed[row.id] or tags.disabled(row.id)then
                        -- Drawn, then removed: the mission can end without any.
                        target.open=true
                    elseif not target.set[row.id]then
                        target.set[row.id]=true
                        target.list[#target.list+1]={id=row.id,name=assert(labels[row.id],'Unknown constellation name')}
                    end
                end
            end
        end
    end
    local named={}
    for id,option in ipairs(options)do
        if catalogue.mission_set[id]then
            groups[id]={list={},set={}}
            for _,kind in ipairs(option.ids)do
                if catalogue.native[kind]then named[kind]=true;offer(groups[id],kind)end
            end
        end
    end
    for kind in pairs(catalogue.native)do if not named[kind]then offer(groups[0],kind)end end
    for _,group in pairs(groups)do table.sort(group.list,function(a,b)return a.id<b.id end)end
    catalogue.constellation_groups,catalogue.forced=groups,forced
    -- The roster input of a mission here holding one more constellation
    -- (src/unit_forecast.lua): the planet-wide tags the configuration keeps,
    -- the tag, and the spawn weights, read on the first hover only.
    local zone,war
    function catalogue.forecast(tag)
        if not zone then zone,war=tags.spawn(planet,effect)end
        local list,seen={},{}
        for _,t in ipairs(forced)do
            if not seen[t] and not tags.disabled(t)then seen[t]=true;list[#list+1]=t end
        end
        if not seen[tag]then list[#list+1]=tag end
        return {faction=catalogue.faction,difficulty=difficulty,tags=list,zone=zone,war=war}
    end
end
-- Side objectives a mission can draw (src/side_objective_prediction.lua):
-- the side (role 3) and tactical (role 2) entries of its pool that this
-- difficulty, the configuration, the world modifiers of at least one
-- operation here and a biome environment the planet can give allow. A row
-- is a title (Prediction.rows) with its role, 3 when any mission type of
-- the group draws it as a side objective, else 2. Group i covers the eligible mission types of
-- family i, group 0 every one. Each group keeps, per mission type, its side
-- and tactical slots, the role of each row it offers and its drawable
-- entries (row, role, how many copies a draw can take, mask), for C.possible.
-- The catalogue changes only after every input decoded.
function C.objectives(catalogue,inputs,Prediction,planet,difficulty,options)
    local contexts={}
    for effect in pairs(catalogue.effects or {})do contexts[#contexts+1]=inputs.context(planet,effect)end
    assert(#contexts>0,'No operation effects for side objectives')
    local counts=inputs.counts(difficulty)
    local groups={[0]={list={},set={},kinds={}}}
    local function offer(group,kind)
        local mission=inputs.mission(kind)
        local scale=inputs.scale(mission.category)
        local side=scale and math.floor(counts.side*scale+0.5) or counts.side
        local info={side=side,tactical=counts.tactical,rows={},entries={}}
        local environments={}
        for _,context in ipairs(contexts)do
            local _,set=inputs.environments(planet,kind,context.modifiers)
            for id in pairs(set)do environments[id]=true end
        end
        for _,e in ipairs(mission.pool)do
            local row=Prediction.row_of[e.id]
            local slots=e.role==3 and side or e.role==2 and counts.tactical or 0
            if row and e.weight>0 and slots>0 then
                local record=inputs.objective(e.id)
                local allowed=record.environments[1]==0
                for k=1,4 do
                    local id=record.environments[k]
                    if id==0 then break end
                    if environments[id]then allowed=true end
                end
                local banned=true
                for _,context in ipairs(contexts)do if not context.banned[e.id]then banned=false end end
                if allowed and not banned and not inputs.disabled(record.id)
                    and (record.minimum==0 or record.minimum<=difficulty) and (record.maximum==0 or difficulty<=record.maximum)then
                    info.rows[row]=info.rows[row] or e.role
                    -- A drawn mask bit drops every entry sharing it, the
                    -- entry itself included (1757870), so a masked entry is
                    -- drawn once.
                    local copies=math.min(e.maximum,record.cap)
                    if record.mask~=0 then copies=math.min(copies,1)end
                    if copies>0 then info.entries[#info.entries+1]={row=row,role=e.role,copies=copies,mask=record.mask}end
                    for _,target in ipairs({group,groups[0]})do
                        if not target.set[row]then
                            target.set[row]=true
                            target.list[#target.list+1]={id=row,name=Prediction.names[row],role=e.role}
                        elseif e.role==3 then
                            -- A side objective of one type is listed as side.
                            for _,option in ipairs(target.list)do if option.id==row then option.role=3 end end
                        end
                    end
                end
            end
        end
        group.kinds[kind]=info;groups[0].kinds[kind]=info
    end
    local named={}
    for id,option in ipairs(options)do
        if catalogue.mission_set[id]then
            groups[id]={list={},set={},kinds={}}
            for _,kind in ipairs(option.ids)do
                if catalogue.native[kind]then named[kind]=true;offer(groups[id],kind)end
            end
        end
    end
    for kind in pairs(catalogue.native)do if not named[kind]then offer(groups[0],kind)end end
    -- Side objectives first, then tactical ones, each by name.
    for _,group in pairs(groups)do
        table.sort(group.list,function(a,b)if a.role~=b.role then return a.role>b.role end;return a.name<b.name end)
    end
    catalogue.objective_groups=groups
end
-- Whether a mission type can fill its side and tactical slots without an
-- excluded row. A draw keeps going until the slots are full or no entry is
-- left, so the entries not excluded must hold enough copies, unless every
-- excluded entry shares a mask bit with one of them and so can be dropped
-- (an upper bound: it never refuses a board the game can deal). Returns
-- false and whether nothing at all is left.
local function avoids_excluded(info,rules)
    for role,slots in pairs({[3]=info.side,[2]=info.tactical})do
        local copies,masks,blocked,any=0,0,false,false
        for _,e in ipairs(info.entries)do if e.role==role then
            if rules[e.row]=='exclude' then blocked=true
            else copies=copies+e.copies;masks=bit.bor(masks,e.mask);any=true end
        end end
        if blocked and slots>copies then
            for _,e in ipairs(info.entries)do
                if e.role==role and rules[e.row]=='exclude' and bit.band(e.mask,masks)==0 then return false,not any end
            end
        end
    end
    return true
end
-- Whether one mission type of a group can hold every required row and still
-- fill its side and tactical slots without an excluded row. The reason is
-- the closest type's: too many rows, then all excluded, then too few left,
-- then rows missing.
local function objectives_possible(group,rules)
    local why,rank='This mission cannot draw every required side objective',0
    for _,info in pairs(group.kinds)do
        local side,tactical,fits=0,0,true
        for row,mode in pairs(rules)do
            if mode=='require' then
                local role=info.rows[row]
                if role==3 then side=side+1 elseif role==2 then tactical=tactical+1 else fits=false end
            end
        end
        if fits and (side>info.side or tactical>info.tactical)then
            fits=false
            if rank<3 then why,rank='Too many required side objectives for this mission and difficulty',3 end
        end
        if fits then
            local none
            fits,none=avoids_excluded(info,rules)
            if not fits then
                if none then if rank<2 then why,rank='Every side objective of this mission is excluded',2 end
                elseif rank<1 then why,rank='Too many excluded side objectives for this mission and difficulty',1 end
            end
        end
        if fits then return true end
    end
    return false,why
end
-- rules: src/filter_rules.lua, or any table with its fields. Its time,
-- when given, is the Day / Night filter's side and counts as a rule.
-- Excluded mission families, which no mission of the operation may be,
-- each count as a rule and take no slot. Side-objective groups are like
-- constellation groups: row -> 'require' or 'exclude'; one rule group
-- counts as a rule.
function C.validate(catalogue,rules)
    local required,modifiers,constellations,time=rules.required,rules.modifiers,rules.constellations,rules.time
    local excluded,objectives=rules.excluded,rules.objectives
    local n,required_modifiers,total=0,0,0
    if time~=nil then assert(time=='day' or time=='night','Invalid time of day');total=1 end
    for id,value in pairs(required)do
        assert(value==true and catalogue.mission_set[id],'Mission is unavailable on this planet/difficulty')
        n=n+1;total=total+1
    end
    assert(n<=catalogue.slots,'Too many required missions for this difficulty')
    for id,value in pairs(excluded or {})do
        assert(value==true and catalogue.mission_set[id],'Excluded mission is unavailable on this planet/difficulty')
        assert(not required[id],'A mission cannot be both required and excluded')
        total=total+1
    end
    for id,mode in pairs(modifiers or {})do
        assert(catalogue.modifier_set[id],'Modifier is unavailable on this planet/difficulty')
        assert(mode=='require' or mode=='exclude','Invalid modifier rule')
        if mode=='require'then required_modifiers=required_modifiers+1 end
        total=total+1
    end
    assert(required_modifiers<=2,'Operations have at most two modifiers')
    for group,tags in pairs(constellations and constellations.groups or {})do
        assert((group==0 and n==0) or required[group],'Constellations need their mission checked')
        local offered=catalogue.constellation_groups and catalogue.constellation_groups[group]
        for tag,mode in pairs(tags)do
            assert(offered and offered.set[tag],'Constellation is unavailable for this mission')
            assert(mode=='accept' or mode=='exclude','Invalid constellation rule')
        end
        if next(tags)then total=total+1 end
    end
    for group,rows in pairs(objectives and objectives.groups or {})do
        assert((group==0 and n==0) or required[group],'Side objectives need their mission checked')
        local offered=catalogue.objective_groups and catalogue.objective_groups[group]
        for row,mode in pairs(rows)do
            assert(offered and offered.set[row],'Side objective is unavailable for this mission')
            assert(mode=='require' or mode=='exclude','Invalid side objective rule')
        end
        if next(rows)then total=total+1 end
    end
    assert(total>0,'Choose at least one mission, modifier rule, constellation, side objective or time of day')
    local possible,reason=C.possible(catalogue,rules);assert(possible,reason)
end
-- Whether the rules can be met here, with the reason when not; time is not checked.
function C.possible(catalogue,rules)
    local required,modifiers,constellations=rules.required,rules.modifiers,rules.constellations
    local excluded,objectives=rules.excluded,rules.objectives
    local n=0;for _ in pairs(required)do n=n+1 end
    if n>catalogue.slots then return false,'No mission slots remain; uncheck a mission first' end
    -- Every operation holds at least one mission, so excluding every
    -- mission offered here leaves nothing to match.
    if excluded and next(excluded)then
        local left=false
        for _,option in ipairs(catalogue.missions or {})do if not excluded[option.id]then left=true;break end end
        if not left then return false,'Every mission here is excluded' end
    end
    -- A mission always draws one of its constellations, so excluding all
    -- of them leaves nothing, unless a drawn one can be removed afterwards.
    for group,tags in pairs(constellations and constellations.groups or {})do
        local offered=catalogue.constellation_groups and catalogue.constellation_groups[group]
        local excluded=0
        for _,mode in pairs(tags)do if mode=='exclude' then excluded=excluded+1 end end
        if offered and not offered.open and excluded>0 and excluded>=#offered.list then
            return false,'Every constellation '..(group==0 and 'here' or 'of this mission')..' is excluded'
        end
    end
    -- Per mission, one of its types must hold the required rows; for the
    -- operation, every required row must be offered by some mission.
    for group,rows in pairs(objectives and objectives.groups or {})do
        local offered=catalogue.objective_groups and catalogue.objective_groups[group]
        if offered and next(rows)then
            if group==0 then
                for row,mode in pairs(rows)do
                    if mode=='require' and not offered.set[row]then return false,'No mission here can draw that side objective' end
                end
                -- Every mission of the operation avoids the excluded rows,
                -- so at least one mission type must.
                local avoided=false
                for _,info in pairs(offered.kinds)do if avoids_excluded(info,rows)then avoided=true;break end end
                if next(offered.kinds) and not avoided then return false,'Too many excluded side objectives for every mission here' end
            else
                local ok,why=objectives_possible(offered,rows)
                if not ok then return false,why end
            end
        end
    end
    if catalogue.compatibility then return catalogue.compatibility.possible(catalogue.profiles,required,modifiers,excluded)end
    return true
end
return C
