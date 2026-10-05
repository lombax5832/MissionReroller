-- Pure bounded candidate search. The caller owns a frozen predictor/context;
-- this module never refreshes the game, reads memory or publishes a seed.
-- Seeds are tried in order from options.seed, or taken from options.source
-- (the seed solver, src/seed_solver_search.lua): source.next(budget) returns
-- a candidate, or nil when its budget is spent (the step tries no seed) and
-- done when it has no more, after which the search continues in order. A
-- third result `idle` (worker VMs with no candidate ready) sets self.idle,
-- so the caller can yield instead of stepping again at once.
return function(evaluate,catalogue,options)
    local function integer(n,lo,hi)return type(n)=='number' and n==math.floor(n) and n>=lo and n<=hi end
    assert(type(evaluate)=='function' and type(catalogue.find)=='function','Missing predictor or matcher')
    assert(integer(options.seed,0,4294967295),'Invalid initial seed')
    assert(integer(options.limit,1,1048576),'Invalid candidate budget')
    assert(integer(options.difficulty,1,10),'Invalid difficulty')
    -- options.rules: src/filter_rules.lua, the request's Filters.
    local rules=options.rules
    rules:check(catalogue.options)
    local daynight=options.daynight
    assert(daynight==nil or type(daynight)=='function','Invalid day/night check')
    -- The time of day is a filter through daynight alone.
    assert(rules:count()>(rules.time and 1 or 0) or daynight,'Select missions, modifier rules, constellations or side objectives')
    local scope=catalogue.scope and catalogue.scope(options.scope)
    assert(scope or options.scope==nil,'City scope unavailable')
    local difficulty,limit=options.difficulty,options.limit
    local source=options.source
    assert(source==nil or type(source.next)=='function','Invalid seed source')
    -- Walk steps per step: about 1 ms at the slowest rate seen in game,
    -- so a step cannot overrun the frame slice the job keeps.
    local budget=options.source_budget or 1024
    local self={status='searching',attempts=0,next_seed=options.seed,solving=source~=nil}
    function self:cancel()
        if self.status=='searching' then self.status='cancelled' end
    end
    function self:step()
        if self.status~='searching' then return self.status end
        local seed
        self.idle=false
        if source then
            local done,idle
            seed,done,idle=source.next(budget)
            if not seed then
                if done then source=nil;self.solving=false else self.idle=idle==true end
                return self.status
            end
        else
            seed=self.next_seed;self.next_seed=(seed+1)%4294967296
        end
        self.attempts=self.attempts+1
        local ok,operations=pcall(evaluate,seed)
        if not ok then self.status='failed';self.error=tostring(operations);return self.status end
        local valid={}
        for _,op in ipairs(operations)do if op.valid then valid[#valid+1]=op end end
        local match=catalogue.find({operations=valid},difficulty,rules,scope,daynight)
        if match then self.status='matched';self.seed=seed;self.operation=match;self.operations=operations
        elseif self.attempts>=limit then self.status='exhausted' end
        return self.status
    end
    return self
end
