-- HD2-Addon: mods/ipodalexei/mission_reroller
if rawget(_G, 'MissionReroller') then return end
local M = {version='0.2.0', status='initializing', native_ready=false}
-- The game build whose record layouts inspect_snapshot decodes. The core
-- stands alone, so it keeps its own copy; tests/test_offsets.py requires it
-- to equal the build of src/offsets.lua.
M.SUPPORTED_BUILD = 25480438
rawset(_G, 'MissionReroller', M)

-- Development core. No native adapter is installed: this file cannot issue
-- game requests, access memory, or draw a war-table button yet.
-- IDs and catalogues must eventually come from the selected planet's rules.
local function integer(n, lo, hi)
    return type(n)=='number' and n==math.floor(n) and n>=lo and n<=hi
end
local function id(value)
    return type(value)=='string' and #value>0 and #value<=128
end
local function list(values, maximum)
    assert(type(values)=='table', 'Expected an array')
    local n=0
    for k in pairs(values) do
        assert(integer(k,1,maximum), 'Invalid array key')
        n=n+1
    end
    for i=1,n do assert(values[i]~=nil, 'Sparse array') end
    return n
end
local function copy_ids(values, maximum)
    local result, seen={},{}
    for i=1,list(values,maximum) do
        local value=values[i]
        assert(id(value) and not seen[value], 'Invalid or repeated identifier')
        seen[value]=true
        result[i]=value
    end
    return result,seen
end
local function context_valid(context)
    return type(context)=='table' and id(context.key) and id(context.planet)
        and integer(context.difficulty,1,10) and context.available==true
        and context.host==true and context.screen=='planet'
        and context.operation_in_progress==false
end
local function same_context(a,b)
    return context_valid(a) and context_valid(b) and a.key==b.key
        and a.planet==b.planet and a.difficulty==b.difficulty
end

-- Decode the verified operation/mission layout from bounded byte strings.
-- Memory acquisition and build-signature checks belong to the future adapter.
-- Two agreeing passes reduce mixed-frame reads; they are not an atomic snapshot.
function M.inspect_snapshot(capture)
    assert(type(capture)=='table' and capture.build==M.SUPPORTED_BUILD, 'Unsupported snapshot build')
    assert(id(capture.session) and capture.session_after==capture.session, 'Snapshot session changed')
    local a,b=capture.before,capture.after
    assert(type(a)=='table' and type(b)=='table', 'Missing snapshot passes')
    local sizes={selection=20,operations=110*92,operation_cache=8,
        mission_count=4,mission_cache=4,campaign_seed=4,screen=24}
    local function u32(bytes,at)
        assert(type(bytes)=='string' and at>=0 and at+4<=#bytes, 'Short field')
        local x,y,z,w=bytes:byte(at+1,at+4)
        return x+256*y+65536*z+16777216*w
    end
    for key,size in pairs(sizes) do
        assert(type(a[key])=='string' and #a[key]==size, 'Invalid field size: '..key)
        assert(a[key]==b[key], 'Snapshot changed: '..key)
    end
    local n=u32(a.mission_count,0)
    assert(n<=330 and type(a.missions)=='string' and #a.missions==n*76, 'Invalid mission array')
    assert(a.missions==b.missions, 'Snapshot changed: missions')
    local screens=u32(a.screen,20)
    assert(screens>=1 and screens<=5 and u32(a.screen,4*(screens-1))==15, 'Map not open')
    local planet,selected=u32(a.selection,0),u32(a.selection,8)
    assert(planet<512 and (selected==0xffffffff or selected<110), 'Invalid map selection')
    assert(u32(a.operation_cache,0)==planet and a.operation_cache:byte(5)==0
        and u32(a.mission_cache,0)==planet, 'Stale operation cache')
    local result={planet_index=planet,highlighted_operation=selected~=0xffffffff and selected or nil,
        campaign_seed=u32(a.campaign_seed,0),operations={},matching_ready=false,atomic_snapshot=false}
    local used,found={},false
    for index=0,109 do
        local at=index*92
        local valid=a.operations:byte(at+53)
        assert(valid==0 or valid==1, 'Unknown operation validity')
        local lo,hi=a.operations:byte(at+17,at+18)
        if valid==1 and lo+256*hi==planet then
            assert(u32(a.operations,at)==index, 'Operation identity changed')
            local difficulty,count=a.operations:byte(at+33),a.operations:byte(at+89)
            assert(difficulty>=1 and difficulty<=10 and count>=1 and count<=3
                and a.operations:byte(at+85)==count, 'Unsupported operation shape')
            local op={row=index,operation_id=a.operations:byte(at+25),difficulty=difficulty,
                seed=u32(a.operations,at+12),template_index=u32(a.operations,at+56),
                faction=u32(a.operations,at+36),status_count=count,missions={},modifiers={}}
            local modifier_count=a.operations:byte(at+69)
            assert(modifier_count<=2,'Invalid operation modifier count')
            for j=0,modifier_count-1 do op.modifiers[#op.modifiers+1]=u32(a.operations,at+60+j*4)end
            for slot=0,count-1 do
                local mi=a.operations:byte(at+86+slot)
                assert(mi<n and not used[mi], 'Invalid or repeated mission reference')
                used[mi]=true
                local pos=mi*76
                assert(u32(a.missions,pos+40)==index and u32(a.missions,pos+60)==difficulty
                    and u32(a.missions,pos+68)==slot, 'Mission identity changed')
                local status=u32(a.missions,pos+56)
                assert(status==u32(a.operations,at+72+4*slot), 'Mission status changed')
                local kind=u32(a.missions,pos+48)
                assert(kind<256, 'Unknown mission type')
                op.missions[#op.missions+1]={row=mi,slot=slot,native_type=kind,
                    seed=u32(a.missions,pos+52),level_index=u32(a.missions,pos+44),
                    status=status,kind=u32(a.missions,pos+64)}
            end
            if index==selected then found=true end
            result.operations[#result.operations+1]=op
        end
    end
    assert(#result.operations>0 and (selected==0xffffffff or found), 'Operation selection unavailable')
    return result
end

-- All requested mission types must appear somewhere in ONE operation.
-- Unspecified mission slots and extra modifiers/constellations are unrestricted.
-- Constellations can be constrained on every mission or across the operation;
-- the UI must expose that distinction because native constellations are per-mission.
function M.compile(catalogue, requested)
    assert(type(catalogue)=='table' and context_valid(catalogue.context), 'Planet context unavailable')
    assert(catalogue.complete==true, 'Legal-option catalogue incomplete')
    assert(integer(catalogue.slots,1,3), 'Unknown operation size')
    assert(type(requested)=='table', 'Missing filters')
    for field in pairs(requested) do
        assert(field=='missions' or field=='modifiers' or field=='constellations'
            or field=='constellation_scope', 'Unknown filter field')
    end
    local c=catalogue.context
    local filter={context={key=c.key,planet=c.planet,difficulty=c.difficulty,
        available=true,host=true,screen='planet',operation_in_progress=false},
        slots=catalogue.slots, constellation_scope=requested.constellation_scope or 'every_mission'}
    assert(filter.constellation_scope=='every_mission' or filter.constellation_scope=='operation',
        'Unknown constellation scope')
    for _,kind in ipairs({'missions','modifiers','constellations'}) do
        local _,legal=copy_ids(catalogue[kind],256)
        local selected=copy_ids(requested[kind] or {},256)
        for _,value in ipairs(selected) do assert(legal[value], 'Unavailable '..kind..' option: '..value) end
        filter[kind]=selected
    end
    assert(#filter.missions<=filter.slots, 'More required mission types than operation slots')
    return filter
end

local function contains_all(have, required)
    local _,set=copy_ids(have,256)
    for _,value in ipairs(required) do if not set[value] then return false end end
    return true
end

-- true = match, false = nonmatch, nil = incomplete/untrusted input.
-- A complete flag is a contract for the future native reader, not independent
-- proof of vanilla legality. Only that reader may attest native provenance.
function M.matches(filter, operation)
    if type(operation)~='table' or operation.complete~=true then return nil,'incomplete operation' end
    if operation.context_key~=filter.context.key or operation.planet~=filter.context.planet
        or operation.difficulty~=filter.context.difficulty then return nil,'stale operation context' end
    if operation.native_generated~=true then return nil,'unverified operation provenance' end
    if list(operation.missions,3)~=filter.slots then return nil,'incomplete mission list' end
    local types,seen,union={},{},{}
    local forecasts_complete=true
    for _,mission in ipairs(operation.missions) do
        assert(type(mission)=='table' and id(mission.type), 'Invalid mission')
        if not seen[mission.type] then types[#types+1]=mission.type; seen[mission.type]=true end
        if #filter.constellations>0 then
            if mission.forecast_complete~=true then forecasts_complete=false
            else
                local tags=copy_ids(mission.constellations,32)
                for _,tag in ipairs(tags) do union[tag]=true end
            end
        end
    end
    if not contains_all(types,filter.missions) then return false,'mission requirements' end
    if #filter.modifiers>0 then
        if operation.modifiers_complete~=true then return nil,'incomplete modifiers' end
        if not contains_all(operation.modifiers,filter.modifiers) then return false,'modifier requirements' end
    end
    if #filter.constellations>0 then
        if not forecasts_complete then return nil,'incomplete constellation forecast' end
        if filter.constellation_scope=='every_mission' then
            for _,mission in ipairs(operation.missions) do
                if not contains_all(mission.constellations,filter.constellations) then
                    return false,'constellation requirements'
                end
            end
        else
            for _,tag in ipairs(filter.constellations) do
                if not union[tag] then return false,'constellation requirements' end
            end
        end
    end
    return true,'matched'
end

-- Adapter contract is documented in docs/ADAPTER.md. This controller never
-- loops on the update thread, retries an uncertain request, or mutates missions.
-- It is exercised with synthetic adapters only; no live adapter is supplied.
function M.new_search(adapter)
    assert(type(adapter)=='table', 'Missing adapter')
    for _,name in ipairs({'context','catalogue','snapshot','request','poll'}) do
        assert(type(adapter[name])=='function', 'Missing adapter method: '..name)
    end
    local self={status='idle',attempts=0,result=nil,reason=nil}
    local filter, pending, generation, last_time, next_request, deadline, max_attempts, interval, timeout
    local function stop(status,reason)
        self.status,self.reason=status,reason
        pending=nil
    end
    local function evaluate(batch)
        assert(type(batch)=='table' and id(batch.generation), 'Invalid operation batch')
        if batch.context_key~=filter.context.key then error('Operation batch changed context') end
        if batch.complete~=true then return nil end
        local n=list(batch.operations,110)
        if n==0 then return nil end
        local incomplete=false
        for _,operation in ipairs(batch.operations) do
            local match=M.matches(filter,operation)
            if match then self.result=operation; stop('matched','Matching native operation found'); return true end
            if match==nil then incomplete=true end
        end
        if incomplete then return nil end
        return false
    end
    function self:start(requested, now, options)
        if self.status~='idle' then return false,'Create a new search after native readiness is rechecked' end
        self.result,self.attempts=nil,0
        options=options or {}
        local ok,why=pcall(function()
            assert(type(now)=='number' and now>=0 and now<math.huge, 'Invalid time')
            local context=adapter.context()
            assert(context_valid(context), 'Select an available planet as host with no active operation')
            local catalogue=adapter.catalogue(context)
            filter=M.compile(catalogue,requested)
            assert(same_context(context,filter.context), 'Catalogue changed context')
            max_attempts=options.max_attempts or 100
            interval=options.interval or 5
            timeout=options.timeout or 30
            assert(integer(max_attempts,1,1000), 'Invalid attempt limit')
            assert(type(interval)=='number' and interval>=1 and interval<=300, 'Invalid request interval')
            assert(type(timeout)=='number' and timeout>=1 and timeout<=300, 'Invalid timeout')
            local batch=adapter.snapshot(context)
            self.status,self.reason='searching',nil
            last_time,next_request,deadline=now,now,now+timeout
            generation=batch.generation
            if evaluate(batch)==nil then stop('unavailable','Initial operation batch incomplete') end
        end)
        if not ok then stop('unavailable',tostring(why)); return false,self.reason end
        return self.status~='unavailable',self.reason
    end
    function self:cancel()
        if self.status=='searching' or self.status=='waiting' then
            -- An already-issued backend request cannot be undone here.
            stop('cancelled','Stopped; an in-flight native reroll may still finish')
        end
    end
    local function advance(now)
        assert(type(now)=='number' and now>=last_time and now<math.huge, 'Invalid monotonic time')
        last_time=now
        if not same_context(adapter.context(),filter.context) then
            stop('cancelled','Planet, difficulty, host, screen or operation state changed'); return
        end
        if pending then
            if now>=deadline then stop('timeout','Request outcome unknown; no automatic retry'); return end
            local response=adapter.poll(pending)
            if response==nil then return end
            assert(type(response)=='table' and response.ticket==pending, 'Mismatched request response')
            if response.error then stop('failed',tostring(response.error)); return end
            local batch=response.batch
            if not batch or batch.generation==generation then return end
            local outcome=evaluate(batch)
            if outcome==nil or outcome==true then return end
            generation,pending=batch.generation,nil
            self.status='searching'
            next_request=now+interval
        end
        if self.attempts>=max_attempts then stop('exhausted','No match within attempt limit'); return end
        if now<next_request then return end
        local ticket,why=adapter.request(filter.context,generation)
        assert(id(ticket), why or 'Reroll request refused')
        self.attempts=self.attempts+1
        pending,deadline=ticket,now+timeout
        self.status='waiting'
    end
    function self:tick(now)
        if self.status~='searching' and self.status~='waiting' then return end
        local ok,why=pcall(advance,now)
        if not ok then stop('failed',tostring(why)) end
    end
    return self
end

local loader=rawget(_G,'CowboyBingusModLoader')
local function report(text)
    pcall(function()
        local file=loader and loader.open_log and loader.open_log('MissionReroller.log')
        if not file then return end
        pcall(function() file:write('MissionReroller '..M.version..'\n'..text..'\n') end)
        pcall(function() file:close() end)
    end)
end
if type(loader)~='table' or type(loader.api)~='number' or loader.api<1
    or type(loader.version)~='number' or loader.version<16 then
    M.status='unsupported_loader'
else
    M.status='unsupported_native_adapter'
end
report(M.status..': development core only; no rerolls or UI are enabled')
-- No callback needs to be wrapped until the native adapter is verified.
-- Existing update/shutdown functions and their return values remain intact.
return M
