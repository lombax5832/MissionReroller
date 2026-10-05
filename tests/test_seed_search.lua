local root=arg[1]
local new=dofile(root..'/seed_search.lua');local catalogue=dofile(root..'/search_session.lua')
local Rules=dofile(root..'/filter_rules.lua')
-- Search options with the Filters as filter rules (src/filter_rules.lua).
local FILTERS={required=true,excluded=true,modifiers=true,constellations=true,objectives=true,time=true}
local function with(o)
    local out={rules=Rules.new(o)}
    for k,v in pairs(o)do if not FILTERS[k]then out[k]=v end end
    return out
end
local function operation(types,valid)
    local missions={};for _,id in ipairs(types)do missions[#missions+1]={native_type=id}end
    return {row=0,difficulty=10,valid=valid~=false,missions=missions}
end
local calls={};local required={[1]=true,[2]=true}
local options=with{seed=4294967295,limit=3,difficulty=10,required=required}
local search=new(function(seed)
    calls[#calls+1]=seed
    if seed==4294967295 then return {operation({0}),operation({22})}end
    return {operation({0,22,7},false),operation({0,22,7})}
end,catalogue,options)
required[3]=true;options.limit=1;options.difficulty=1
assert(search:step()=='searching','Required missions must belong to the same operation')
assert(search:step()=='matched' and search.seed==0 and #calls==2 and search.operation.valid,'Seed wrap and valid match')
search:step();search:cancel();assert(#calls==2 and search.status=='matched')
search=new(function()return {operation({0,7,28})}end,catalogue,with{seed=1,limit=2,difficulty=10,required={[1]=true,[2]=true}})
assert(search:step()=='searching' and search:step()=='exhausted' and search.attempts==2)
search:step();assert(search.attempts==2,'Exhaustion must not evaluate more seeds')
search=new(function()error('unsupported context')end,catalogue,with{seed=1,limit=2,difficulty=10,required={[1]=true}})
assert(search:step()=='failed' and search.error:find('unsupported context',1,true))
search:step();assert(search.attempts==1,'Predictor failure must not retry')
search=new(function()error('Must not run')end,catalogue,with{seed=1,limit=2,difficulty=10,required={[1]=true}})
search:cancel();assert(search:step()=='cancelled' and search.attempts==0)
local function tagged(icbm,eradicate)
    return {row=1,difficulty=10,valid=true,missions={{native_type=59,tags={[icbm]=true}},{native_type=65,tags={[eradicate]=true}}}}
end
local filter={groups={[1]={[4]='accept'}}}
search=new(function(seed)return {seed==5 and tagged(2,4) or tagged(4,2)}end,catalogue,
    with{seed=5,limit=3,difficulty=10,required={[1]=true},constellations=filter})
filter.groups[1][2]='accept';filter.groups[3]={[2]='accept'}
assert(search:step()=='searching' and search:step()=='matched' and search.seed==6,'Per-mission constellations are copied and applied')
search=new(function(seed)return {tagged(2,seed==8 and 6 or 4)}end,catalogue,
    with{seed=7,limit=3,difficulty=10,required={},constellations={groups={[0]={[6]='accept'}}}})
assert(search:step()=='searching' and search:step()=='matched' and search.seed==8,'Any-mission constellation needs no checked mission')
local function rejected(required,groups)
    return not pcall(new,function()end,catalogue,with{seed=1,limit=1,difficulty=10,required=required,constellations={groups=groups}})
end
assert(rejected({[1]=true},{[3]={[2]='accept'}}),'A group needs its mission checked')
assert(rejected({[1]=true},{[0]={[2]='accept'}}),'The operation group is only for requests without missions')
assert(rejected({},{[0]={[0]='accept'}}) and rejected({},{[0]={[32]='accept'}}) and rejected({},{[0]={[2]='require'}}))
assert(rejected({},{[0]={[2]=true}}) and rejected({},{[13]={[2]='accept'}}) and rejected({},{[0]={}}),'Empty groups are not a filter')
search=new(function(seed)return {seed==2 and tagged(6,4) or tagged(2,4)}end,catalogue,
    with{seed=1,limit=3,difficulty=10,required={[1]=true},constellations={groups={[1]={[2]='exclude',[4]='exclude'}}}})
assert(search:step()=='searching' and search:step()=='matched' and search.seed==2,'An exclusion alone is a filter')
-- Excluded missions: a filter on their own, copied, and never also required.
local excluded={[3]=true}
search=new(function(seed)return {operation(seed==4 and {0,22} or {0,7})}end,catalogue,
    with{seed=3,limit=3,difficulty=10,required={},excluded=excluded})
excluded[3]=nil;excluded[1]=true
assert(search:step()=='searching' and search:step()=='matched' and search.seed==4,'Excluded missions are copied and applied')
search=new(function()return {operation({0,7}),operation({22})}end,catalogue,with{seed=1,limit=1,difficulty=10,required={[2]=true},excluded={[3]=true}})
assert(search:step()=='matched' and search.operation.missions[1].native_type==22,'An operation without the excluded family matches')
assert(not pcall(new,function()end,catalogue,with{seed=1,limit=1,difficulty=10,required={[1]=true},excluded={[1]=true}}),'Required and excluded')
assert(not pcall(new,function()end,catalogue,with{seed=1,limit=1,difficulty=10,required={},excluded={[999]=true}}),'Unknown family')
assert(not pcall(new,function()end,catalogue,with{seed=1,limit=1,difficulty=10,required={},excluded={[1]='exclude'}}),'Excluded holds true')
local function rows(...)
    local out={}
    for i,row in ipairs({...})do out[i]={row=row,difficulty=10,valid=true,missions={{native_type=59}}}end
    return out
end
local scope={region=1}
search=new(function(seed)return seed==3 and rows(29,49) or rows(29,39,59)end,catalogue,
    with{seed=1,limit=5,difficulty=10,required={[1]=true},scope=scope})
scope.region=2
assert(search:step()=='searching' and search:step()=='searching' and search:step()=='matched')
assert(search.seed==3 and search.operation.row==49,'A city search matches only that city and copies its scope')
assert(not pcall(new,function()end,catalogue,with{seed=1,limit=1,difficulty=10,required={[1]=true},scope={region=9}}))
assert(not pcall(new,function()end,{options=catalogue.options,find=catalogue.find},
    with{seed=1,limit=1,difficulty=10,required={[1]=true},scope={region=1}}),'A matcher without scopes must refuse one')
-- A seed source (the seed solver): a spent budget tries no seed, each
-- candidate is judged by the predictor, and an exhausted source falls back
-- to seeds in order from options.seed.
local queue={false,9,false,7}
local tried={}
local source={next=function(budget)
    assert(budget==1024,'Default source budget')
    local item=table.remove(queue,1)
    if item==nil then return nil,true end
    if item==false then return nil,false end
    return item
end}
search=new(function(seed)tried[#tried+1]=seed;return {seed==20 and operation({0}) or operation({7})}end,catalogue,
    with{seed=19,limit=10,difficulty=10,required={[1]=true},source=source})
assert(search.solving and search:step()=='searching' and search.attempts==0 and #tried==0,'A spent budget tries no seed')
assert(not search.idle,'A spent budget is not idle')
assert(search:step()=='searching' and tried[1]==9 and search.attempts==1,'A candidate is predicted')
search:step();search:step()
assert(tried[2]==7 and search.attempts==2 and search.next_seed==19,'The source leaves the scan position alone')
assert(search:step()=='searching' and not search.solving and search.attempts==2,'An exhausted source ends solving')
assert(search:step()=='searching' and tried[3]==19 and search:step()=='matched' and search.seed==20,'Then seeds in order')
assert(not pcall(new,function()end,catalogue,with{seed=1,limit=1,difficulty=10,required={[1]=true},source={}}),'Invalid source')
-- Worker VMs with no candidate ready (src/seed_solver_workers.lua): the step
-- tries no seed and says idle, so the job can give the frame back.
search=new(function()error('No seed may be tried')end,catalogue,
    with{seed=1,limit=10,difficulty=10,required={[1]=true},source={next=function()return nil,false,true end}})
assert(search:step()=='searching' and search.idle and search.attempts==0 and search.solving,'An idle source tries no seed')
print('Seed search: seed source and fallback, city scope, constellation groups, operation-wide filter, wrap, budget, cancellation, invalid operations and fail-closed prediction passed')
