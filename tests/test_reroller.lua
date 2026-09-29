local entry=assert(arg[1], 'entry path required')
local old_update=function() return 1,nil,3,nil end
local old_shutdown=function() return nil,2 end
update,shutdown=old_update,old_shutdown
local logs={}
CowboyBingusModLoader={api=1,version=16,open_log=function(name)
    assert(name=='MissionReroller.log')
    return {write=function(_,s) logs[#logs+1]=s end,close=function() end}
end}
local M=assert(dofile(entry))
assert(M.status=='unsupported_native_adapter' and M.native_ready==false)
assert(update==old_update and shutdown==old_shutdown)
local nlogs=#logs
dofile(entry)
assert(MissionReroller==M and #logs==nlogs)

local function clone(t)
    if type(t)~='table' then return t end
    local out={}
    for k,v in pairs(t) do out[k]=clone(v) end
    return out
end
local ctx={key='context:1',planet='planet:A',difficulty=10,host=true,
    available=true,screen='planet',operation_in_progress=false}
local catalogue={context=ctx,complete=true,slots=3,
    missions={'icbm','survey','eradicate','evacuate'},
    modifiers={'fog','cooldown'},constellations={'armored','airborne'}}
local requested={missions={'icbm','survey'}}
local function operation(types)
    local missions={}
    for _,t in ipairs(types or {'icbm','survey','eradicate'}) do
        missions[#missions+1]={type=t,forecast_complete=true,constellations={'armored'}}
    end
    return {context_key=ctx.key,planet=ctx.planet,difficulty=10,native_generated=true,
        complete=true,modifiers_complete=true,modifiers={'fog'},missions=missions}
end
local filter=M.compile(catalogue,requested)
assert(M.matches(filter,operation()))
assert(M.matches(filter,operation({'survey','evacuate','icbm'})))
assert(M.matches(filter,operation({'survey','evacuate','eradicate'}))==false)
assert(M.matches(filter,operation({'icbm','icbm','eradicate'}))==false)
local o=operation(); o.missions[3]=nil
assert(M.matches(filter,o)==nil)
o=operation(); o.native_generated=false
assert(M.matches(filter,o)==nil)
o=operation(); o.planet='other'
assert(M.matches(filter,o)==nil)
o=operation(); o.context_key='old'
assert(M.matches(filter,o)==nil)
o=operation(); o.complete=false
assert(M.matches(filter,o)==nil)
-- Unknown forecasts do not block a filter which does not request them.
o=operation(); o.missions[1].forecast_complete=false
assert(M.matches(filter,o))
local full=M.compile(catalogue,{missions={'icbm','survey'},modifiers={'fog'},constellations={'armored'}})
assert(M.matches(full,operation()))
assert(M.matches(full,o)==nil)
o=operation(); o.missions[3].constellations={}
assert(M.matches(full,o)==false)
local union=M.compile(catalogue,{constellations={'armored','airborne'},constellation_scope='operation'})
o=operation(); o.missions[3].constellations={'airborne'}
assert(M.matches(union,o))
o.modifiers_complete=false
assert(M.matches(full,o)==nil)
o=operation(); o.modifiers={}
assert(M.matches(full,o)==false)
local function rejects(fn) assert(not pcall(fn), 'Expected rejection') end
rejects(function() M.compile(catalogue,{missions={'icbm','unknown'}}) end)
rejects(function() M.compile(catalogue,{missions={'icbm','icbm'}}) end)
rejects(function() M.compile(catalogue,{missions={'icbm','survey','eradicate','evacuate'}}) end)
rejects(function() M.compile(catalogue,{missions={[2]='icbm'}}) end)
rejects(function() M.compile(catalogue,{mission={'icbm'}}) end)
rejects(function() M.compile(catalogue,{constellation_scope='any'}) end)
local incomplete=clone(catalogue); incomplete.complete=false
rejects(function() M.compile(incomplete,{}) end)
-- Compiling does not retain caller-owned mutable selections or context.
local mutable=clone(requested); local copied=M.compile(catalogue,mutable)
mutable.missions[1]='evacuate'
assert(copied.missions[1]=='icbm' and copied.context~=ctx)

local function harness(initial)
    local h={context=clone(ctx),requests=0,response=nil,
        batch={generation='g0',context_key=ctx.key,complete=true,
            operations=initial or {operation({'eradicate','evacuate','eradicate'})}}}
    local a={
        context=function() return h.context end,
        catalogue=function() return catalogue end,
        snapshot=function() return h.batch end,
        request=function(context,generation)
            assert(context.key==ctx.key and generation)
            h.requests=h.requests+1
            return 'ticket:'..h.requests
        end,
        poll=function() return h.response end,
    }
    h.adapter=a
    h.search=M.new_search(a)
    function h:respond(ops,gen)
        self.response={ticket='ticket:'..self.requests,
            batch={generation=gen or 'g'..self.requests,context_key=ctx.key,complete=true,operations=ops}}
    end
    return h
end
local h=harness({operation()})
assert(h.search:start(requested,0)); assert(h.search.status=='matched' and h.requests==0)
h=harness(); assert(h.search:start(requested,0))
h.search:tick(0); assert(h.requests==1 and h.search.status=='waiting')
for i=1,20 do h.search:tick(i/10) end
assert(h.requests==1)
h:respond({operation()})
h.search:tick(3); assert(h.search.status=='matched' and h.search.result.missions[1].type=='icbm')
h.search:tick(99); assert(h.requests==1)
-- Never combine requirements from different operations in the same batch.
h=harness({operation({'icbm','eradicate','evacuate'}),operation({'survey','eradicate','evacuate'})})
assert(h.search:start(requested,0)); assert(h.search.status=='searching')
h.search:tick(0); h.search:cancel(); h.search:tick(100)
assert(h.search.status=='cancelled' and h.requests==1)
assert(h.search:start(requested,101)==false)
-- Delay and attempt budget apply only after a complete fresh response.
h=harness(); assert(h.search:start(requested,0,{max_attempts=2,interval=5}))
h.search:tick(0)
h:respond({operation({'eradicate','evacuate','eradicate'})})
h.search:tick(1); h.search:tick(5); assert(h.requests==1)
h.response=nil; h.search:tick(6); assert(h.requests==2)
h:respond({operation({'eradicate','evacuate','eradicate'})})
h.search:tick(7); assert(h.search.status=='exhausted' and h.requests==2)
-- Old generation, incomplete forecasts and late replies cannot cause retries.
h=harness(); assert(h.search:start(requested,0,{timeout=3}))
h.search:tick(0); h:respond({operation()},'g0'); h.search:tick(1)
assert(h.search.status=='waiting')
h.search:tick(3); assert(h.search.status=='timeout' and h.requests==1)
h:respond({operation()}); h.search:tick(4); assert(h.search.status=='timeout')
h=harness(); assert(h.search:start({constellations={'airborne'}},0,{timeout=3}))
h.search:tick(0); o=operation(); o.missions[1].forecast_complete=false
h:respond({o}); h.search:tick(1); assert(h.search.status=='waiting')
h.search:tick(3); assert(h.search.status=='timeout' and h.requests==1)
-- Resolve a partial response on a later frame under the same ticket.
h=harness(); assert(h.search:start({constellations={'airborne'}},0))
h.search:tick(0); o=operation(); o.missions[1].forecast_complete=false
h:respond({o}); h.search:tick(1)
for _,m in ipairs(o.missions) do m.forecast_complete=true; m.constellations={'airborne'} end
h.search:tick(2); assert(h.search.status=='matched')
for _,change in ipairs({{planet='other'},{difficulty=9},{host=false},{screen='briefing'},
    {available=false},{key='context:2'},{operation_in_progress=true}}) do
    h=harness(); assert(h.search:start(requested,0))
    for k,v in pairs(change) do h.context[k]=v end
    h.search:tick(0)
    assert(h.search.status=='cancelled' and h.requests==0)
end
h=harness(); h.context.host=false
assert(h.search:start(requested,0)==false and h.requests==0)
h=harness(); h.batch.complete=false
assert(h.search:start(requested,0)==false and h.requests==0)
h=harness(); assert(h.search:start(requested,0))
h.adapter.request=function() error('native unavailable') end
h.search:tick(0); assert(h.search.status=='failed')
h=harness(); assert(h.search:start(requested,0)); h.search:tick(0)
h.response={ticket='wrong',error='no'}
h.search:tick(1); assert(h.search.status=='failed' and h.requests==1)
h=harness(); assert(h.search:start(requested,0)); h.search:tick(0)
h.response={ticket='ticket:1',error='rate limited'}
h.search:tick(1); assert(h.search.status=='failed' and h.requests==1)
-- Loader failure and logging failure must not touch original callbacks.
MissionReroller=nil; CowboyBingusModLoader={api=1,version=15}
assert(dofile(entry).status=='unsupported_loader')
MissionReroller=nil; CowboyBingusModLoader={api=1,version=16,open_log=function() error('disk unavailable') end}
assert(dofile(entry).status=='unsupported_native_adapter')
assert(update==old_update and shutdown==old_shutdown)
print('test_reroller: all filter, lifecycle and asynchronous search cases passed')
