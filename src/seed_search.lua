-- Pure bounded candidate search. The caller owns a frozen predictor/context;
-- this module never refreshes the game, reads memory or publishes a seed.
-- Seeds are tried in order from options.seed, or taken from options.source
-- (the seed solver, src/seed_solver_search.lua): source.next(budget) returns
-- a candidate, or nil when its budget is spent (the step tries no seed) and
-- done when it has no more, after which the search continues in order.
return function(evaluate,catalogue,options)
    local function integer(n,lo,hi)return type(n)=='number' and n==math.floor(n) and n>=lo and n<=hi end
    assert(type(evaluate)=='function' and type(catalogue.find)=='function','Missing predictor or matcher')
    assert(integer(options.seed,0,4294967295),'Invalid initial seed')
    assert(integer(options.limit,1,1048576),'Invalid candidate budget')
    assert(integer(options.difficulty,1,10),'Invalid difficulty')
    local required,n={},0
    for id,value in pairs(options.required)do
        assert(catalogue.options[id] and value==true,'Invalid mission filter');required[id]=true;n=n+1
    end
    -- Excluded families take no slot; none may also be required.
    local excluded,x={},0
    for id,value in pairs(options.excluded or {})do
        assert(catalogue.options[id] and value==true and not required[id],'Invalid excluded mission');excluded[id]=true;x=x+1
    end
    local modifiers,m={},0
    for id,mode in pairs(options.modifiers or {})do
        assert(integer(id,0,4294967295) and (mode=='require' or mode=='exclude'),'Invalid modifier rule')
        modifiers[id]=mode;m=m+1
    end
    -- Group 0 constrains the operation and is only meaningful without
    -- checked missions; every other group belongs to a checked mission.
    local constellations,c={groups={}},0
    for group,tags in pairs(options.constellations and options.constellations.groups or {})do
        assert(integer(group,0,#catalogue.options) and ((group==0 and n==0) or required[group]),'Invalid constellation group')
        local copy={}
        for tag,mode in pairs(tags)do
            assert(integer(tag,1,31) and (mode=='accept' or mode=='exclude'),'Invalid constellation rule');copy[tag]=mode
        end
        if next(copy)then constellations.groups[group]=copy;c=c+1 end
    end
    -- Side-objective groups follow the same rule; rows are objective ids.
    local objectives,o={groups={}},0
    for group,rows in pairs(options.objectives and options.objectives.groups or {})do
        assert(integer(group,0,#catalogue.options) and ((group==0 and n==0) or required[group]),'Invalid side objective group')
        local copy={}
        for row,mode in pairs(rows)do
            assert(integer(row,1,4294967295) and (mode=='require' or mode=='exclude'),'Invalid side objective rule');copy[row]=mode
        end
        if next(copy)then objectives.groups[group]=copy;o=o+1 end
    end
    local daynight=options.daynight
    assert(daynight==nil or type(daynight)=='function','Invalid day/night check')
    assert(n<=3 and (n+x+m+c+o>0 or daynight),'Select missions, modifier rules, constellations or side objectives')
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
        if source then
            local done
            seed,done=source.next(budget)
            if not seed then
                if done then source=nil;self.solving=false end
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
        local match=catalogue.find({operations=valid},difficulty,required,modifiers,constellations,scope,daynight,x>0 and excluded or nil,
            o>0 and objectives or nil)
        if match then self.status='matched';self.seed=seed;self.operation=match;self.operations=operations
        elseif self.attempts>=limit then self.status='exhausted' end
        return self.status
    end
    return self
end
