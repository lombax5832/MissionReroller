-- One planet's prediction inputs, decoded through one read function. Every
-- caller (capture, search, dialog catalogue, constellation tags) builds them
-- here, so live, cached and frozen reads decode the same bytes the same way.
-- Built once from the library modules; a module a build leaves out (the
-- search's predictor, the dialog's catalogue and tag inputs) leaves the
-- method that needs it unavailable.
local O=...
return function(m)
    local predict=m.composition_prediction(m.rng,m.category,m.level_choice,m.mission_choice(m.rng),m.finalizer(m.rng))
    local make_bases=m.base_inputs(m.identity,m.special_inputs,m.environments)
    local make_predictor=m.predictor and m.predictor(m.levels,make_bases,predict)
    local Planet={}
    -- Decoders are created on first use and shared: the configuration and
    -- campaign effects decoded for the missions also feed the tag inputs.
    function Planet.bind(read,u,pointer,game,board,index)
        local planet={board=board,index=index}
        local config,effects,inputs,tags,objectives
        -- The configuration manager is read first, then the effects, in the
        -- order of the native collectors.
        local function configuration(missing)
            if not config then
                config=m.config(read,u,pointer,assert(pointer(read(game+O.rva.configuration,8)),missing))
            end
            return config
        end
        local function campaign()
            effects=effects or m.effects(read,u,pointer,game,board)
            return effects
        end
        -- Mission metadata, templates, modifiers and enable rules.
        function planet.inputs()
            if not inputs then
                local c=configuration('Missing composition pointer')
                inputs=m.composition_inputs(read,u,pointer,game,board,c,campaign(),m.eligible,m.environments)
            end
            return inputs
        end
        -- Enemy-tag inputs (constellation_inputs.lua).
        function planet.constellation_inputs()
            if not tags then
                local c=configuration('Missing configuration manager')
                tags=assert(m.constellation_inputs,'Constellation inputs unavailable')(read,u,pointer,game,board,campaign(),c)
            end
            return tags
        end
        -- Side-objective inputs (side_objective_inputs.lua).
        function planet.objective_inputs()
            if not objectives then
                local c=configuration('Missing configuration manager')
                objectives=assert(m.objective_inputs,'Side objective inputs unavailable')(read,u,pointer,game,board,c,planet.inputs())
            end
            return objectives
        end
        -- predict(seed, difficulty, accepts) for the planet's bases under a
        -- candidate seed (candidate_predictor.lua).
        function planet.predictor(definitions)
            return assert(make_predictor,'Candidate predictor unavailable')(read,u,pointer,game,board,definitions,index,planet.inputs())
        end
        -- The cached level definitions of this planet, found by its key as
        -- the identity probe finds them (identity_probe.lua), or nil.
        function planet.definitions()
            local key=read(board+O.board.campaign+0x1c+index*O.campaign.definition_stride,4)
            for _,offset in ipairs(O.board.definitions)do
                if read(board+offset,4)==key then return board+offset end
            end
        end
        -- The seed solver's inputs for every normal operation ID of one
        -- difficulty, or with region for that city's operation only
        -- (seed_solver_inputs.lua; seeded adds the enemy-tag and
        -- side-objective inputs), and the identity input its rows are drawn
        -- from (operation_identity.lua). Nil and a reason when those rows
        -- cannot be solved.
        function planet.solver(definitions,difficulty,seeded,region)
            local Inputs=assert(m.solver_inputs,'Seed solver unavailable')
            local inputs=planet.inputs()
            local rows,_,input=make_bases(read,u,pointer,game,board,definitions,index,inputs)(0)
            local bases={}
            if region then
                -- A city is a campaign event; its operation's ID is the region.
                for _,op in ipairs(rows)do
                    if op.special and op.id==region and op.difficulty==difficulty then
                        bases[1]={difficulty=difficulty,id=region,category=op.category,faction=op.faction,explicit_hash=0}
                    end
                end
                if not bases[1]then return nil,'no city operation at the difficulty'end
            else
                if difficulty>input.max_difficulty then return nil,'difficulty above the cap'end
                local category,faction
                for _,op in ipairs(rows)do
                    if not op.special and not op.preserved then category,faction=op.category,op.faction;break end
                end
                if not category then return nil,'no normal operation'end
                for id=0,input.pool_count-1 do
                    bases[#bases+1]={difficulty=difficulty,id=id,category=category,faction=faction,explicit_hash=0}
                end
            end
            local levels=m.levels(read,u,game)
            local solver=Inputs(index,bases,inputs,function(op)return levels(definitions,op)end,
                seeded and planet.constellation_inputs() or nil,seeded and planet.objective_inputs() or nil)
            return solver,input
        end
        -- The filter options of one difficulty, optionally one city's rows.
        -- Mission and modifier options survive a tag or side-objective
        -- input failure, returned as the second and third values.
        function planet.catalogue(snapshot,difficulty,accepts)
            local C=assert(m.catalogue,'Filter catalogue unavailable')
            local result=C.build(planet.inputs(),snapshot,difficulty,u,m.options,m.compatibility,accepts)
            local ok,err=pcall(function()
                C.constellations(result,planet.constellation_inputs(),m.labels,index,difficulty,m.options)
            end)
            local fine,failure=true,nil
            if m.objective_inputs then
                fine,failure=pcall(function()
                    C.objectives(result,planet.objective_inputs(),m.objectives,index,difficulty,m.options)
                end)
            end
            return result,not ok and err or nil,not fine and failure or nil
        end
        return planet
    end
    -- capture(snapshot, definitions) compares the prediction for the
    -- snapshot's seed with its displayed board and returns the result and the
    -- bytes it read (composition_capture.lua).
    Planet.capture=m.capture(Planet.bind,m.levels,predict,make_bases)
    return Planet
end
