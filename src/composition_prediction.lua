-- Predict complete mission descriptors from operation base inputs. The caller
-- supplies IDs/seeds/category/faction, not generated templates or mission seeds.
-- The canonical in-progress operation is an explicit preserved input.
return function(make_rng,choose_category,choose_level,choose_mission,finalize)
    return function(operations,planet,inputs,level_graph,active)
        local result={}
        for _,base in ipairs(operations)do
            -- 11e5670 resets the weighted-choice usage array per operation.
            local counts={}
            -- effect_id goes into the constructor, never stored afterwards: once this
            -- loop is compiled, the game's LuaJIT 2.1.0-alpha reads a field stored
            -- after the call back as the constructor's value (tests/test_game_jit.py).
            local effect=inputs.effect_id({row=base.row,id=base.id,seed=base.seed,difficulty=base.difficulty,
                faction=base.faction,category=base.category,explicit_hash=base.explicit_hash},planet)
            local op={row=base.row,id=base.id,seed=base.seed,difficulty=base.difficulty,
                faction=base.faction,category=base.category,explicit_hash=base.explicit_hash,effect_id=effect}
            local budget,total=inputs.difficulty(op.difficulty,op.category)
            local finished
            if active and active.row==op.row then
                assert(active.seed==op.seed and active.id==op.id,'Preserved operation identity differs')
                finished={valid=true,template_index=active.template_index,modifiers=active.modifiers}
            else
                local explicit=op.explicit_hash~=0 and inputs.explicit(op.explicit_hash) or nil
                local pool=explicit and {} or inputs.templates(op,planet)
                finished=finalize(op.seed,pool,op.explicit_hash,budget,explicit and {explicit} or {})
            end
            op.valid=finished.valid;op.template_index=finished.template_index;op.modifiers=finished.modifiers;op.missions={}
            if op.valid then
                local candidates,weights,rules=inputs.candidates(op.template_index,op,planet)
                local levels,special=level_graph(op)
                local rng=make_rng(op.seed);local used_levels,usage={},{}
                for slot=0,total-1 do
                    local eligible=choose_category(candidates,rules,usage,rng)
                    if #eligible>0 then
                        local level=choose_level(levels,special,slot,used_levels,rng)
                        if level then
                            local seed=rng:next();local kind=choose_mission(eligible,weights,counts,seed,op.seed)
                            local cat=inputs.mission(kind,planet,op.effect_id,0,false).category
                            usage[cat]=(usage[cat] or 0)+1;used_levels[#used_levels+1]=level
                            op.missions[#op.missions+1]={native_type=kind,seed=seed,level_index=level}
                        end
                    end
                end
                if op.category==0 then
                    for _,modifier in ipairs(op.modifiers)do
                        local kind=inputs.extra_mission(modifier,op.faction)
                        if kind then
                            local level=choose_level(levels,special,#op.missions,used_levels,rng)
                            if level then
                                local seed=rng:next()
                                -- Native singleton modifier missions do not update operation usage.
                                op.missions[#op.missions+1]={native_type=kind,seed=seed,level_index=level}
                                used_levels[#used_levels+1]=level
                            end
                        end
                    end
                end
                assert(#op.missions<=3,'Predicted operation exceeds mission capacity')
            end
            result[#result+1]=op
        end
        return result
    end
end
