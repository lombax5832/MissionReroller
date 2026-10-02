-- One coroutine owns each search. check_context must pass before each resume
-- and again before a finished job is exposed; the host owns wall-clock timeout
-- and can cancel at any yield.
--
-- Candidates are predicted from frozen bytes, so a rejected candidate needs no
-- validation. With options.clock the job fills a time slice per resume,
-- revalidates the frozen bytes every options.revalidate seconds, and always
-- before a match is exposed. Without a clock it validates and yields after
-- every candidate.
--
-- bind_predictor returns the search predictor and, optionally, a complete one.
-- The search predictor may cover only the operations that can match; a match
-- is then confirmed against the complete prediction of the same seed.
return function(make_reads,make_search,catalogue)
    return function(read,baseline,bind_predictor,options)
        local self={status='running',phase='capture',attempts=0,next_seed=options.seed}
        local steps=0;local quantum=options.quantum or 512
        assert(quantum>=1 and quantum==math.floor(quantum),'Invalid search quantum')
        local clock,slice,batch=options.clock,options.slice or 0.016,options.batch or 256
        local revalidate=options.revalidate or 1
        assert(clock==nil or type(clock)=='function','Invalid search clock')
        assert(slice>0 and revalidate>0 and batch>=1 and batch==math.floor(batch),'Invalid search slice')
        local deadline=math.huge
        local function checkpoint()
            steps=steps+1
            if steps>=quantum or (clock and steps%64==0 and clock()>=deadline)then steps=0;coroutine.yield()end
        end
        local frozen,revalidation,pending_status
        local thread=coroutine.create(function()
            frozen=make_reads(read,checkpoint,options.input_limits)
            baseline(frozen.read)
            local predict,complete=bind_predictor(frozen.read)
            self.phase='validate baseline';frozen:validate()
            local search=make_search(function(seed)
                self.phase='evaluate';self.candidate_seed=seed
                local operations=predict(seed)
                if not clock then self.phase='validate candidate';self.ranges,self.bytes=frozen:validate()end
                return operations
            end,catalogue,options)
            local validated,evaluated=clock and clock(),0
            repeat
                search:step();self.attempts=search.attempts;self.next_seed=search.next_seed
                if search.status=='searching' then
                    evaluated=evaluated+1
                    if not clock then coroutine.yield()
                    else
                        if clock()-validated>=revalidate then
                            self.phase='validate inputs';frozen:validate();validated=clock()
                        end
                        -- The candidate cap bounds a slice if the clock stalls.
                        if evaluated>=batch or clock()>=deadline then evaluated=0;coroutine.yield()end
                    end
                end
            until search.status~='searching'
            if search.status=='matched' then
                if complete then
                    self.phase='complete candidate'
                    local operations=complete(search.seed);local valid={}
                    for _,op in ipairs(operations)do if op.valid then valid[#valid+1]=op end end
                    local match=catalogue.find({operations=valid},options.difficulty,options.required,
                        options.modifiers,options.constellations,options.scope,options.daynight,options.excluded)
                    assert(match and match.row==search.operation.row,'Search and complete predictions differ')
                    search.operation=match;search.operations=operations
                end
                -- Covers inputs first read by the complete prediction as well.
                self.phase='validate candidate';self.ranges,self.bytes=frozen:validate()
            end
            self.phase='complete';self.status=search.status
            self.seed=search.seed;self.operation=search.operation;self.operations=search.operations;self.error=search.error
        end)
        function self:cancel(reason)
            if self.status=='running' then self.status='cancelled';self.error=reason;thread=nil;revalidation=nil;self.seed=nil;self.operation=nil end
        end
        function self:step(check_context)
            if self.status~='running' then return self.status end
            local function context()
                local ok,ready,reason=pcall(check_context)
                if not ok then self:cancel(tostring(ready));return false end
                if ready==false then
                    self.waiting=true;self.wait_reason=reason;return false
                end
                return true
            end
            -- A finished job held back by a wait needs only the context check.
            if not context() then return self.status end
            if self.waiting then
                self.waiting=false;self.wait_reason=nil
                -- A backend pause can span arbitrary campaign updates. Replay
                -- the entire byte validation before resuming or exposing a match.
                revalidation=coroutine.create(function()if frozen then frozen:validate()end end)
            end
            local work=revalidation or thread
            if coroutine.status(work)~='dead' then
                if clock then deadline=clock()+slice end
                local ok,err=coroutine.resume(work)
                if not ok then self.status='failed';self.error=tostring(err);self.seed=nil;self.operation=nil;thread=nil;revalidation=nil;return self.status end
            end
            if self.status~='running' then pending_status=self.status;self.status='running' end
            if revalidation and coroutine.status(revalidation)=='dead' then revalidation=nil end
            if pending_status and not revalidation then
                -- The context may have changed while the last slice worked.
                if not context() then return self.status end
                self.status=pending_status;thread=nil
            end
            return self.status
        end
        return self
    end
end
