-- One planet's prediction inputs, decoded through one read function. Every
-- caller (capture, search, dialog catalogue, constellation tags) builds them
-- here, so live, cached and frozen reads decode the same bytes the same way.
-- Built once from the library modules; a module a build leaves out (the
-- search's predictor, the dialog's catalogue and tag inputs) leaves the
-- method that needs it unavailable.
return function(m)
    local predict=m.composition_prediction(m.rng,m.category,m.level_choice,m.mission_choice(m.rng),m.finalizer(m.rng))
    local make_bases=m.base_inputs(m.identity,m.special_inputs,m.environments)
    local make_predictor=m.predictor and m.predictor(m.levels,make_bases,predict)
    local Planet={}
    -- Decoders are created on first use and shared: the configuration and
    -- campaign effects decoded for the missions also feed the tag inputs.
    function Planet.bind(read,u,pointer,game,board,index)
        local planet={board=board,index=index}
        local config,effects,inputs,tags
        -- The configuration manager is read first, then the effects, in the
        -- order of the native collectors.
        local function configuration(missing)
            if not config then
                config=m.config(read,u,pointer,assert(pointer(read(game+0x347cdf8,8)),missing))
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
        -- predict(seed, difficulty, accepts) for the planet's bases under a
        -- candidate seed (candidate_predictor.lua).
        function planet.predictor(definitions)
            return assert(make_predictor,'Candidate predictor unavailable')(read,u,pointer,game,board,definitions,index,planet.inputs())
        end
        -- The filter options of one difficulty, optionally one city's rows.
        -- Mission and modifier options survive a tag input failure, which is
        -- returned as the second value.
        function planet.catalogue(snapshot,difficulty,accepts)
            local C=assert(m.catalogue,'Filter catalogue unavailable')
            local result=C.build(planet.inputs(),snapshot,difficulty,u,m.options,m.compatibility,accepts)
            local ok,err=pcall(function()
                C.constellations(result,planet.constellation_inputs(),m.labels,index,difficulty,m.options)
            end)
            return result,not ok and err or nil
        end
        return planet
    end
    -- capture(snapshot, definitions) compares the prediction for the
    -- snapshot's seed with its displayed board and returns the result and the
    -- bytes it read (composition_capture.lua).
    Planet.capture=m.capture(Planet.bind,m.levels,predict,make_bases)
    return Planet
end
