-- Read eligibility through the same input decoder used by the predictor.
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
-- of one city or megafactory.
function C.build(inputs,s,difficulty,u,options,compatibility,tags,labels,accepts)
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
    if tags then C.constellations(result,tags,labels,s.planet,difficulty,options)end
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
end
function C.validate(catalogue,required,modifiers,constellations)
    local n,required_modifiers,total=0,0,0
    for id,value in pairs(required)do
        assert(value==true and catalogue.mission_set[id],'Mission is unavailable on this planet/difficulty')
        n=n+1;total=total+1
    end
    assert(n<=catalogue.slots,'Too many required missions for this difficulty')
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
    assert(total>0,'Choose at least one mission, modifier rule or constellation')
    local possible,reason=C.possible(catalogue,required,modifiers,constellations);assert(possible,reason)
end
function C.possible(catalogue,required,modifiers,constellations)
    local n=0;for _ in pairs(required)do n=n+1 end
    if n>catalogue.slots then return false,'No mission slots remain; uncheck a mission first' end
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
    if catalogue.compatibility then return catalogue.compatibility.possible(catalogue.profiles,required,modifiers)end
    return true
end
return C
