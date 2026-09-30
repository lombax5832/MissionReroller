-- Pure bounded candidate search. The caller owns a frozen predictor/context;
-- this module never refreshes the game, reads memory or publishes a seed.
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
    local daynight=options.daynight
    assert(daynight==nil or type(daynight)=='function','Invalid day/night check')
    assert(n<=3 and (n+m+c>0 or daynight),'Select missions, modifier rules or constellations')
    local scope=catalogue.scope and catalogue.scope(options.scope)
    assert(scope or options.scope==nil,'City scope unavailable')
    local difficulty,limit=options.difficulty,options.limit
    local self={status='searching',attempts=0,next_seed=options.seed}
    function self:cancel()
        if self.status=='searching' then self.status='cancelled' end
    end
    function self:step()
        if self.status~='searching' then return self.status end
        local seed=self.next_seed
        self.attempts=self.attempts+1;self.next_seed=(seed+1)%4294967296
        local ok,operations=pcall(evaluate,seed)
        if not ok then self.status='failed';self.error=tostring(operations);return self.status end
        local valid={}
        for _,op in ipairs(operations)do if op.valid then valid[#valid+1]=op end end
        local match=catalogue.find({operations=valid},difficulty,required,modifiers,constellations,scope,daynight)
        if match then self.status='matched';self.seed=seed;self.operation=match;self.operations=operations
        elseif self.attempts>=limit then self.status='exhausted' end
        return self.status
    end
    return self
end
