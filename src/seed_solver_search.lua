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
    -- The declines that mean no normal operation of the difficulty can
    -- match (R.plan tells them from the others).
    local NO_PATH,NO_DAYNIGHT='no draw path','no operation passes Day / Night'
    -- Seeds sampled for the Day / Night share, and how many.
    local SHARE_SAMPLES=2048
    local function sampled_seed(i)return Math.output(i,3)end
    -- Per solver inputs, the operation standing for each difficulty
    -- (seed_solver_paths.lua P.shared): the dialog estimates every edit
    -- from the same inputs.
    local shared_of=setmetatable({},{__mode='k'})
    -- Per inputs, the Day / Night shares by difficulty and passing IDs:
    -- they do not depend on the missions requested.
    local shares_of=setmetatable({},{__mode='k'})
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
    -- checkpoint() called often while the paths and walks are set up,
    -- estimate_only to stop once the estimate is known (no next or steps),
    -- make_chain(chain spec) to walk elsewhere (src/seed_solver_workers.lua:
    -- a chain-like {next, steps, close, workers, report} or nil and why,
    -- when the walk stays here).
    -- Returns {next(budget) -> seed | nil, done, idle; steps(); close();
    -- workers (0 when the walk runs here) and workers_off (why), report();
    -- paths; rows;
    -- valid, ids: how many operation IDs the Day / Night window passes, of
    -- how many; estimate={match, steps}} or nil, reason. estimate.match is
    -- the share of campaign seeds whose board matches the paths (one row of
    -- them at least), estimate.steps the walk steps expected before the
    -- first candidate (almost every candidate matches).
    -- Parts of the filter left to the predictor are not counted.
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
        local known=shared_of[solver]
        if not known then known={};shared_of[solver]=known end
        if known[difficulty]==nil then
            local ok,sample=pcall(P.shared,operations,difficulty)
            if not ok then return nil,tostring(sample)end
            known[difficulty]=sample or false
        end
        local paths={}
        for _,combo in ipairs(combinations(lists))do
            local ok,found=pcall(P.shared_paths,operations,difficulty,combo,rules,level_ok,known[difficulty])
            if not ok then return nil,tostring(found)end
            if not found then return nil,'operations at the difficulty differ'end
            for _,path in ipairs(found)do paths[#paths+1]=path end
        end
        if #paths==0 then return nil,NO_PATH end
        -- Linked draws make the paths' own probabilities rough.
        for _,path in ipairs(paths)do
            if spec.checkpoint then spec.checkpoint()end
            path.probability=Chain.mass(path,spec.checkpoint)
        end
        table.sort(paths,function(a,b)return a.probability>b.probability end)
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
        local shares={}
        for i=1,#rows do shares[i]=1 end
        if spec.daynight and not scope then
            local set
            set,valid,ids=Time.valid_ids(operations,difficulty,spec.daynight) -- set, count, total
            -- Only city rows can match: the search scans for them.
            if valid==0 then return nil,NO_DAYNIGHT end
            accept=Time.accept(operations,difficulty,spec.daynight,spec.identity,input,'any')
            local passing={}
            for id in pairs(set)do passing[#passing+1]=id end
            table.sort(passing)
            local key=difficulty..':'..table.concat(passing,',')
            local kept=shares_of[input]
            if not kept then kept={};shares_of[input]=kept end
            if not kept[key]then
                local list={}
                for i,row in ipairs(rows)do list[i]=row.row end
                kept[key]=Time.shares(operations,difficulty,spec.daynight,spec.identity,input,list,SHARE_SAMPLES,
                    sampled_seed,spec.checkpoint)
            end
            shares=kept[key]
        end
        for i,row in ipairs(rows)do row.share=shares[i]end
        -- Paths are disjoint outcomes of the draws, so their probabilities add.
        local q=0
        for _,path in ipairs(paths)do q=q+path.probability end
        q=math.min(1,q)
        local none=1
        for _,s in ipairs(shares)do none=none*(1-q*s)end
        -- The walk's solutions come in clusters, so the first candidate takes
        -- longer than independent draws would: 1 to 2.7 times as long on
        -- the captures' filters (docs/SEED_SOLVER_RESEARCH.md).
        local estimate={match=1-none,steps=2*Chain.expected_steps(paths,shares,4096)}
        -- The dialog's estimate before a search needs no walks.
        if spec.estimate_only then return {paths=#paths,rows=#rows,valid=valid,ids=ids,estimate=estimate}end
        local chain_spec={paths=paths,rows=rows,planet=input.planet,random=spec.random,accept=accept,
            checkpoint=spec.checkpoint}
        local workers,workers_off
        if spec.make_chain then
            local ok,made,why=pcall(spec.make_chain,chain_spec)
            if ok and made then workers=made else workers_off=ok and why or tostring(made)end
        end
        if workers then
            return {next=workers.next,steps=workers.steps,close=workers.close,report=workers.report,
                workers=workers.workers,paths=#paths,rows=#rows,valid=valid,ids=ids,estimate=estimate}
        end
        local chain=Chain.new(chain_spec)
        return {next=chain.next,steps=function()return chain.steps end,close=function()end,workers=0,
            workers_off=workers_off,paths=#paths,rows=#rows,valid=valid,ids=ids,estimate=estimate}
    end
    -- The search and the dialog's estimate (src/solver_estimate.lua) plan a
    -- request the same way: prepare reads the planet's solver inputs, plan
    -- turns them into a source or says why not. spec is source's spec
    -- without solver and input.
    -- Whether spec's rules need the mission-seed inputs: any enemy-force or
    -- side-objective group, as source checks them.
    function R.seeded(spec)
        local function any(rules)return rules~=nil and next(rules.groups or {})~=nil end
        return any(spec.constellations) or any(spec.objectives)
    end
    -- {solver, input} of planet (planet_model.lua) for spec's difficulty,
    -- scope and rules; solver nil and input the reason when unavailable.
    function R.prepare(planet,definitions,spec)
        local solver,input=planet.solver(definitions,spec.difficulty,R.seeded(spec),spec.scope and spec.scope.region)
        return {solver=solver,input=input}
    end
    -- source(spec) on prepared inputs, or nil and a decline {kind, reason}:
    -- kind 'impossible' when no seed can match now (no path, or Day / Night
    -- passing no operation ID, and no campaign event row of the difficulty
    -- that a scan could still match: a city has none besides its own),
    -- otherwise 'scan'. Either way the search scans seeds in order.
    function R.plan(prepared,spec)
        if not prepared.solver then return nil,{kind='scan',reason=prepared.input}end
        local s={solver=prepared.solver,input=prepared.input}
        for k,v in pairs(spec)do s[k]=v end
        local source,why=R.source(s)
        if source then return source end
        if why==NO_PATH or why==NO_DAYNIGHT then
            local others=false
            if not spec.scope then
                for _,event in ipairs(prepared.input.specials or {})do
                    if event.minimum<=spec.difficulty and spec.difficulty<=event.maximum then others=true end
                end
            end
            if not others then return nil,{kind='impossible',reason=why}end
        end
        return nil,{kind='scan',reason=why}
    end
    -- The usual seconds of a search: set-up, the expected walk steps at rate
    -- steps a second, and 0.3 s to confirm the match.
    function R.seconds(steps,rate,setup)return setup+steps/rate+0.3 end
    return R
end
