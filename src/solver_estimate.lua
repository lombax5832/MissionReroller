-- The dialog's estimate of a request before it is searched: how strict it
-- is and how long a search usually takes (src/seed_solver_search.lua
-- prepare and plan, as the search makes them), worked out in the
-- background while the player edits it. One worker coroutine runs a time
-- slice per frame, yielding inside the reads
-- and the path building. The planet's solver inputs are kept per snapshot,
-- difficulty and scope, so most edits rebuild only the paths. An edit while
-- the paths are built restarts them; one while the inputs are read lets the
-- read finish for the new request.
return function(SeedSolver)
    -- o: bind(read, s) -> planet model (planet_model.lua) of s's planet,
    -- read, clock, slice (seconds per frame), options (Search.options),
    -- row_of, identity (operation_identity.lua), rate() (walk steps per
    -- second of a search, nil before one is measured), setup (seconds a search spends before walking).
    return function(o)
        local self={}
        local inputs,results,inputs_key={},{},nil
        local worker,key
        local deadline=math.huge
        local function pause()if o.clock()>=deadline then coroutine.yield()end end
        local function paused_read(address,size)pause();return o.read(address,size)end
        -- The solver spec of w's current request (it may be retargeted
        -- while the inputs are read).
        local function spec_of(w)
            local rules=w.rules
            return {identity=o.identity,difficulty=w.difficulty,required=rules.required,options=o.options,
                constellations=rules.constellations,objectives=rules.objectives,scope=w.scope,
                daynight=w.daynight,row_of=o.row_of,checkpoint=pause,estimate_only=true}
        end
        local function work(w)
            local cached=inputs[w.inputs_key]
            if not cached then
                w.stage='inputs'
                local planet=o.bind(paused_read,w.s)
                local definitions=planet.definitions()
                if not definitions then return {unavailable='Planet definitions are not cached'}end
                cached=SeedSolver.prepare(planet,definitions,spec_of(w))
                inputs[w.inputs_key]=cached
            end
            w.stage='paths'
            local source,decline=SeedSolver.plan(cached,spec_of(w))
            if not source then
                -- No seed gives this now (a Day / Night window may open later).
                if decline.kind=='impossible' then return {impossible=true}end
                return {unavailable=decline.reason}
            end
            local e=source.estimate
            return {match=e.match,steps=e.steps}
        end
        -- s: the snapshot; rules: the request's filter rules
        -- (src/filter_rules.lua); daynight: {key, accepts} while a side is
        -- chosen. Works for one slice.
        function self.update(s,difficulty,scope,rules,daynight)
            local seeded=rules:seeded()
            local ikey=table.concat({s.fingerprint,difficulty,scope and scope.region or 'planet',seeded and 'seeded' or 'missions'},':')
            -- Inputs and results of an earlier snapshot or view are dropped.
            local view=table.concat({s.fingerprint,difficulty,scope and scope.region or 'planet'},':')
            if view~=inputs_key then inputs,results,inputs_key={},{},view end
            key=ikey..'|'..rules:key()..'|'..(daynight and daynight.key or '')
            if results[key]then return end
            if worker and worker.key~=key then
                if worker.stage=='inputs' and worker.inputs_key==ikey then
                    worker.key,worker.rules,worker.daynight=key,rules,daynight and daynight.accepts
                else worker=nil end
            end
            if not worker then
                local w={key=key,inputs_key=ikey,s=s,difficulty=difficulty,scope=scope,rules=rules,
                    daynight=daynight and daynight.accepts,spent=0}
                w.thread=coroutine.create(function()
                    local ok,value=pcall(work,w)
                    return ok and value or {unavailable=tostring(value)}
                end)
                worker=w
            end
            local started=o.clock()
            deadline=started+o.slice
            local ok,value=coroutine.resume(worker.thread)
            deadline=math.huge
            worker.spent=worker.spent+o.clock()-started
            if coroutine.status(worker.thread)=='dead' then
                results[worker.key]=ok and value or {unavailable=tostring(value)}
                worker=nil
            end
        end
        -- The current request's estimate: nil while it is worked out;
        -- {match, seconds}, {impossible=true} or {unavailable=reason};
        -- seconds is nil while rate() is (no search has measured one).
        function self.view()
            local r=key and results[key]
            if not r or not r.steps then return r end
            local rate=o.rate()
            return {match=r.match,seconds=rate and SeedSolver.seconds(r.steps,rate,o.setup or 0.2)}
        end
        -- Forget everything, as when the dialog closes.
        function self.reset()worker,key,inputs,results,inputs_key=nil,nil,{},{},nil end
        return self
    end
end
