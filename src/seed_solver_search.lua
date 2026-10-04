-- The seed solver as a candidate source for the in-game search
-- (docs/SEED_SOLVER_RESEARCH.md). source(spec) turns a search request into
-- the chain of src/seed_solver_chain.lua over the requested difficulty's
-- generated rows; the search predicts every candidate it yields and keeps
-- only a seed whose board matches, so filter parts the paths leave out
-- (modifier rules, excluded missions, the Day / Night window as it moves)
-- only make the candidates less selective. Nil and a reason when the
-- request is one the chain cannot seed; the search then scans seeds in order.
return function(Math,Paths,Chain,Time,Inputs)
    local R={inputs=Inputs}
    -- Walk starts for the chain's jobs: the generator's first output of
    -- successive values from a 32-bit seed.
    function R.starts(seed)
        local n=seed%2^32
        return function()n=(n+1)%2^32;return Math.output(n,1)end
    end
    -- Every choice of one present kind per required family, in family order.
    local function combinations(lists)
        local out={{}}
        for _,list in ipairs(lists)do
            local next_out={}
            for _,prefix in ipairs(out)do
                for _,kind in ipairs(list)do
                    local combo={unpack(prefix)};combo[#combo+1]=kind;next_out[#next_out+1]=combo
                end
            end
            out=next_out
        end
        return out
    end
    -- spec: solver and input (planet_model.lua planet.solver), identity
    -- (operation_identity.lua), difficulty, required={[family]=true},
    -- options (search_session.lua S.options), constellations and objectives
    -- ({groups}) or nil, scope, daynight (checker.accepts) or nil, row_of
    -- (side_objective_prediction.lua), random() returning a 32-bit start,
    -- checkpoint() called often while the paths and walks are set up.
    -- Returns {next(budget) -> seed | nil, done; steps(); paths; rows;
    -- valid, ids: how many operation IDs the Day / Night window passes, of
    -- how many} or nil, reason.
    -- The campaign-stream position of a city's (campaign event's) seed
    -- draw: after the two draws of every generated normal row, one per
    -- event row in event order (operation_identity.lua), the preserved row
    -- drawing none.
    function R.event_position(input,row)
        local active=input.active
        local preserved=active and active.planet==input.planet and active.row or nil
        local at=0
        for r=0,3*input.max_difficulty-1 do if r~=preserved then at=at+2 end end
        for _,event in ipairs(input.specials or {})do
            for difficulty=event.minimum,event.maximum do
                local r=event.id*10+29+difficulty
                if r~=preserved then
                    at=at+1
                    if r==row then return at end
                end
            end
        end
    end
    function R.source(spec)
        local families={}
        for family in pairs(spec.required)do families[#families+1]=family end
        table.sort(families)
        if #families==0 then return nil,'no required mission'end
        local solver,input,difficulty,scope=spec.solver,spec.input,spec.difficulty,spec.scope
        -- Row positions assume each row's ID comes from the first pick, which
        -- holds while the pool outnumbers the rows (operation_identity.lua).
        if input.pool_count<3*input.max_difficulty then return nil,'operation pool smaller than the rows'end
        local operations={}
        for _,op in ipairs(solver.operations)do if op.difficulty==difficulty then operations[#operations+1]=op end end
        local sample=operations[1]
        if not sample then return nil,'no operation at the difficulty'end
        if #sample.extra>0 then return nil,'modifier missions'end
        if sample.special~=(scope~=nil)then return nil,scope and 'city without a special level graph' or 'special levels'end
        local groups=spec.constellations and spec.constellations.groups or {}
        local rows_of=spec.objectives and spec.objectives.groups or {}
        if (next(groups) or next(rows_of)) and not solver.seeded then return nil,'mission-seed inputs missing'end
        -- A family's kinds the operation can draw; the paths deliver one of each.
        local lists,rules={},{}
        for _,family in ipairs(families)do
            local list={}
            for _,kind in ipairs(spec.options[family].ids)do
                if sample.category_of[kind]~=nil then
                    list[#list+1]=kind
                    rules[kind]={tags=groups[family],objectives=rows_of[family]}
                end
            end
            lists[#lists+1]=list
        end
        local P=Paths.new({records=solver.records,row_of=spec.row_of or {},disabled_tags=solver.disabled_tags,
            checkpoint=spec.checkpoint})
        -- A city's levels are drawn: Day / Night constrains each level draw
        -- to the nodes the checker passes now, one node at a time.
        local level_ok
        if scope and spec.daynight then
            level_ok=function(node)return spec.daynight({missions={{level_index=node}}})end
        end
        local paths={}
        for _,combo in ipairs(combinations(lists))do
            local ok,found=pcall(P.shared_paths,operations,difficulty,combo,rules,level_ok)
            if not ok then return nil,tostring(found)end
            if not found then return nil,'operations at the difficulty differ'end
            for _,path in ipairs(found)do paths[#paths+1]=path end
        end
        if #paths==0 then return nil,'no draw path'end
        local active=input.active
        local preserved=active and active.planet==input.planet and active.row or nil
        local rows={}
        if scope then
            local row=30+scope.region*10+difficulty-1
            local position=row~=preserved and R.event_position(input,row)
            if not position then return nil,'city operation not generated'end
            rows[1]={row=row,seed_position=position}
        else
            for r=(difficulty-1)*3,difficulty*3-1 do
                if r~=preserved then
                    local _,seed_position=Chain.positions(r,preserved)
                    rows[#rows+1]={row=r,seed_position=seed_position}
                end
            end
        end
        local accept,valid,ids
        if spec.daynight and not scope then
            local _
            _,valid,ids=Time.valid_ids(operations,difficulty,spec.daynight) -- set, count, total
            accept=Time.accept(operations,difficulty,spec.daynight,spec.identity,input,'any')
        end
        local chain=Chain.new({paths=paths,rows=rows,planet=input.planet,random=spec.random,accept=accept,
            checkpoint=spec.checkpoint})
        return {next=chain.next,steps=function()return chain.steps end,paths=#paths,rows=#rows,valid=valid,ids=ids}
    end
    return R
end
