-- The dialog's estimate of a request before it is searched: how strict it
-- is and how long a search usually takes (src/seed_solver_search.lua
-- estimate), worked out in the background while the player edits it. One
-- worker coroutine runs a time slice per frame, yielding inside the reads
-- and the path building. The planet's solver inputs are kept per snapshot,
-- difficulty and scope, so most edits rebuild only the paths. An edit while
-- the paths are built restarts them; one while the inputs are read lets the
-- read finish for the new request.
return function(SeedSolver)
    -- Equal requests, equal text.
    local function canon(v)
        if type(v)~='table' then return tostring(v)end
        local keys={}
        for k in pairs(v)do keys[#keys+1]=k end
        table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
        local parts={}
        for _,k in ipairs(keys)do parts[#parts+1]=tostring(k)..'='..canon(v[k])end
        return '{'..table.concat(parts,',')..'}'
    end
    local function has_rules(groups)
        for _,rules in pairs(groups and groups.groups or {})do if next(rules)then return true end end
        return false
    end
    -- o: bind(read, s) -> planet model (planet_model.lua) of s's planet,
    -- read, clock, slice (seconds per frame), options (Search.options),
    -- row_of, identity (operation_identity.lua), rate() (walk steps per
    -- second of a search), setup (seconds a search spends before walking).
    return function(o)
        local self={}
        local inputs,results,inputs_key={},{},nil
        local worker,key
        local deadline=math.huge
        local function pause()if o.clock()>=deadline then coroutine.yield()end end
        local function paused_read(address,size)pause();return o.read(address,size)end
        local function work(w)
            local cached=inputs[w.inputs_key]
            if not cached then
                w.stage='inputs'
                local planet=o.bind(paused_read,w.s)
                local definitions=planet.definitions()
                if not definitions then return {unavailable='Planet definitions are not cached'}end
                local solver,input=planet.solver(definitions,w.difficulty,w.seeded,w.scope and w.scope.region)
                cached={solver=solver,input=input}
                inputs[w.inputs_key]=cached
            end
            w.stage='paths'
            if not cached.solver then return {unavailable=cached.input}end
            local request=w.request
            local source,why=SeedSolver.source({solver=cached.solver,input=cached.input,identity=o.identity,
                difficulty=w.difficulty,required=request.required or {},options=o.options,
                constellations=request.constellations,objectives=request.objectives,scope=w.scope,
                daynight=w.daynight,row_of=o.row_of,checkpoint=pause,estimate_only=true})
            if not source then
                -- No path, and no other operation that could match: no seed
                -- gives this now (a Day / Night window may open later).
                if why=='no draw path' then
                    local others=false
                    if not w.scope then
                        for _,event in ipairs(cached.input.specials or {})do
                            if event.minimum<=w.difficulty and w.difficulty<=event.maximum then others=true end
                        end
                    end
                    if not others then return {impossible=true}end
                end
                return {unavailable=why}
            end
            local e=source.estimate
            return {match=e.match,steps=e.steps}
        end
        -- s: the snapshot; request: filter_request.lua to_request; daynight:
        -- {key, accepts} while a side is chosen. Works for one slice.
        function self.update(s,difficulty,scope,request,daynight)
            local seeded=has_rules(request.constellations) or has_rules(request.objectives)
            local ikey=table.concat({s.fingerprint,difficulty,scope and scope.region or 'planet',seeded and 'seeded' or 'missions'},':')
            -- Inputs and results of an earlier snapshot or view are dropped.
            local view=table.concat({s.fingerprint,difficulty,scope and scope.region or 'planet'},':')
            if view~=inputs_key then inputs,results,inputs_key={},{},view end
            key=ikey..'|'..canon(request)..'|'..(daynight and daynight.key or '')
            if results[key]then return end
            if worker and worker.key~=key then
                if worker.stage=='inputs' and worker.inputs_key==ikey then
                    worker.key,worker.request,worker.daynight=key,request,daynight and daynight.accepts
                else worker=nil end
            end
            if not worker then
                local w={key=key,inputs_key=ikey,s=s,difficulty=difficulty,scope=scope,seeded=seeded,request=request,
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
        -- {match, seconds}, {impossible=true} or {unavailable=reason}.
        function self.view()
            local r=key and results[key]
            if not r or not r.steps then return r end
            return {match=r.match,seconds=(o.setup or 0.2)+r.steps/o.rate()+0.3}
        end
        -- Forget everything, as when the dialog closes.
        function self.reset()worker,key,inputs,results,inputs_key=nil,nil,{},{},nil end
        return self
    end
end
