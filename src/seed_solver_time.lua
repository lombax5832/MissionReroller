-- The Day / Night filter for the seed solver (docs/SEED_SOLVER_RESEARCH.md).
-- A normal operation's missions take its level nodes slot by slot
-- (mission_level_choice.lua: slot s uses levels[s+1], drawing nothing
-- unless the graph is special), and every slot below min(total, #levels)
-- holds a mission whenever the template has candidates. Where its missions
-- stand is therefore fixed by the operation ID, not the seed: before the
-- search, the IDs whose nodes all stay on the chosen side are the only
-- ones a match can draw. During the search a candidate is kept only when
-- the row it was solved for draws such an ID, checked through the identity
-- stage (operation_identity.lua) at a cost far below a board prediction.
-- accepts(op) is src/day_night.lua's checker.accepts, so the window it
-- tests moves with war time as the search refreshes it.
return function()
    local R={}
    -- The level nodes an operation's missions occupy, or nil for a special
    -- graph (drawn per seed; not solved).
    function R.mission_nodes(op)
        if op.special then return nil end
        local nodes={}
        for slot=1,math.min(op.total,#op.levels)do nodes[slot]=op.levels[slot]end
        return nodes
    end
    -- An operation-shaped table with a mission on each node, for accepts().
    local function placed(nodes)
        local missions={}
        for i,node in ipairs(nodes)do missions[i]={level_index=node}end
        return {missions=missions}
    end
    -- {[id]=true} for the operations of a difficulty that accepts() can
    -- pass now, and how many there are of how many.
    function R.valid_ids(operations,difficulty,accepts)
        local valid,count,total={},0,0
        for _,op in ipairs(operations)do
            if op.difficulty==difficulty then
                total=total+1
                local nodes=R.mission_nodes(op)
                if nodes and #nodes>0 and accepts(placed(nodes))then valid[op.id]=true;count=count+1 end
            end
        end
        return valid,count,total
    end
    -- accept(seed, row) for seed_solver_chain.lua: the row draws an ID whose
    -- nodes accepts() passes; with scope 'all', every generated row of the
    -- difficulty does. identity(input, seed) is operation_identity.lua's.
    function R.accept(operations,difficulty,accepts,identity,input,scope)
        local nodes={}
        for _,op in ipairs(operations)do
            if op.difficulty==difficulty then nodes[op.id]=R.mission_nodes(op)end
        end
        local function ok(id)
            local list=nodes[id]
            return list~=nil and #list>0 and accepts(placed(list))
        end
        return function(seed,row)
            local rows=identity(input,seed)
            if scope=='all' then
                for r=(difficulty-1)*3,difficulty*3-1 do
                    local entry=rows[r]
                    if entry and not entry.preserved and not ok(entry.id)then return false end
                end
                return true
            end
            local entry=rows[row]
            return entry~=nil and ok(entry.id)
        end
    end
    return R
end
