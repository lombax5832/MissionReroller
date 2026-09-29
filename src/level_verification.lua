-- Stage verification, NOT an independent mission predictor: observed mission
-- seeds resolve the still-unported category draw (zero or one RNG step).
-- Observed level indices never influence that resolution.
return function(make_rng,choose)
    return function(operations,graphs)
        local checked,errors,category_draws=0,{},0
        for _,operation in ipairs(operations)do
            local graph=assert(graphs[operation.row],'Missing operation level graph')
            local state=make_rng(operation.seed):state_bytes()
            local used={}
            for slot,mission in ipairs(operation.missions)do
                local candidates={}
                for draws=0,1 do
                    local rng=make_rng(0,0,state)
                    if draws==1 then rng:next()end
                    local level=choose(graph.levels,graph.special,slot-1,used,rng)
                    if level and rng:next()==mission.seed then
                        candidates[#candidates+1]={level=level,state=rng:state_bytes(),draws=draws}
                    end
                end
                if #candidates~=1 then
                    errors[#errors+1]=string.format('row=%d slot=%d unsupported or ambiguous category RNG trace (%d matches)',operation.row,slot-1,#candidates)
                    break
                end
                local candidate=candidates[1]
                if candidate.level~=mission.level_index then
                    errors[#errors+1]=string.format('row=%d slot=%d expected_level=%d live_level=%d',operation.row,slot-1,candidate.level,mission.level_index)
                    break
                end
                state=candidate.state;used[#used+1]=candidate.level
                category_draws=category_draws+candidate.draws;checked=checked+1
            end
        end
        return {passed=#errors==0 and checked>0,checked=checked,errors=errors,category_draws=category_draws}
    end
end
