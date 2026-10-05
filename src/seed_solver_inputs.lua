-- The seed-independent inputs the seed solver walks
-- (src/seed_solver_paths.lua), for every normal operation of one planet:
-- finalization and composition inputs, and for each candidate mission kind
-- its enemy-tag settings, side-objective pool and environment weights. Read
-- through the same input objects the predictor uses; no reads of its own.
--   bases: {{difficulty, id, category, faction, explicit_hash}}
--   inputs: composition_inputs.lua's object; level_graph(op) -> levels, special
--   tags, objectives: constellation_inputs.lua and side_objective_inputs.lua
--     objects, or nil for missions only; objectives.environment_tables gives
--     the weights behind each environment pick
return function(planet,bases,inputs,level_graph,tags,objectives)
    local operations,records,used={},{},{}
    for _,base in ipairs(bases)do
        assert(base.explicit_hash==0,'Explicit templates are not solved')
        -- effect_id goes into the constructor, never stored afterwards: once this
        -- loop is compiled, the game's LuaJIT 2.1.0-alpha reads a field stored
        -- after the call back as the constructor's value (tests/test_game_jit.py).
        local effect=inputs.effect_id({row=0,id=base.id,seed=0,difficulty=base.difficulty,category=base.category,
            faction=base.faction,explicit_hash=0},planet)
        local op={row=0,id=base.id,seed=0,difficulty=base.difficulty,category=base.category,faction=base.faction,
            explicit_hash=0,effect_id=effect}
        local budget,total=inputs.difficulty(op.difficulty,op.category)
        local templates={}
        for i,template in ipairs(inputs.templates(op,planet))do
            local modifiers={}
            for j,item in ipairs(template.modifiers)do modifiers[j]={id=item.id,weight=item.weight,cost=item.cost}end
            local candidates,weights,rules=inputs.candidates(template.index,op,planet)
            local list,weight_of,rule_list={},{},{}
            for j,candidate in ipairs(candidates)do list[j]={id=candidate.id,category=candidate.category}end
            for id,weight in pairs(weights)do weight_of[id]=weight end
            for j,rule in ipairs(rules)do
                rule_list[j]={category=rule.category,minimum=rule.minimum,maximum=rule.maximum,weight=rule.weight}
            end
            templates[i]={index=template.index,weight=template.weight,modifiers=modifiers,candidates=list,
                weights=weight_of,rules=rule_list}
        end
        local levels,special=level_graph(op)
        local extra={}
        if op.category==0 then
            for _,template in ipairs(templates)do
                for _,item in ipairs(template.modifiers)do
                    local kind=inputs.extra_mission(item.id,op.faction)
                    if kind then extra[#extra+1]={item.id,kind}end
                end
            end
        end
        -- Usage counts the category the mission metadata gives under this effect.
        local category_of={}
        for _,template in ipairs(templates)do
            for _,candidate in ipairs(template.candidates)do
                if category_of[candidate.id]==nil then
                    category_of[candidate.id]=inputs.mission(candidate.id,planet,op.effect_id,0,false).category
                end
            end
        end
        local entry={difficulty=op.difficulty,id=op.id,category=op.category,faction=op.faction,effect_id=op.effect_id,
            budget=budget,total=total,templates=templates,levels=levels,special=special and true or false,extra=extra,
            category_of=category_of}
        if tags and objectives then
            local context=objectives.context(planet,op.effect_id)
            local kind_of={}
            for kind in pairs(category_of)do
                local record=tags.mission(kind)
                local settings=false
                if record.faction>=2 and record.faction<=4 then settings=tags.settings(record.faction,op.difficulty)end
                local srecord=objectives.mission(kind)
                local _,reachable=objectives.environments(planet,kind,context.modifiers)
                local environments={}
                for value in pairs(reachable)do environments[#environments+1]=value end
                table.sort(environments)
                for _,e in ipairs(srecord.pool)do used[e.id]=true end
                kind_of[kind]={kind=kind,faction=record.faction,horde=record.horde,exclusions=record.exclusions,
                    settings=settings,objectives={lo=srecord.lo,hi=srecord.hi,category=srecord.category,pool=srecord.pool,
                        scale=objectives.scale(srecord.category) or false},
                    environments=environments,environment=objectives.environment_tables(planet,kind,context.modifiers)}
            end
            entry.kind_of=kind_of
            entry.initial_tags=tags.campaign(planet,op.effect_id)
            local banned={}
            for id in pairs(context.banned)do banned[id]=true end
            entry.context={banned=banned,extra=context.extra,modifiers=context.modifiers}
            entry.counts=objectives.counts(op.difficulty)
        end
        operations[#operations+1]=entry
    end
    local disabled_tags={}
    if tags and objectives then
        for id in pairs(used)do
            local r=objectives.objective(id)
            records[id]={id=r.id,cap=r.cap,minimum=r.minimum,maximum=r.maximum,mask=r.mask,
                environments=r.environments,disabled=objectives.disabled(r.id) and true or false}
        end
        for tag=0,31 do if tags.disabled(tag)then disabled_tags[tag]=true end end
    end
    table.sort(operations,function(a,b)
        if a.difficulty~=b.difficulty then return a.difficulty<b.difficulty end
        return a.id<b.id
    end)
    return {planet=planet,operations=operations,records=records,disabled_tags=disabled_tags,
        seeded=tags~=nil and objectives~=nil}
end
