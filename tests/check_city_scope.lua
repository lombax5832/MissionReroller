-- Usage: luajit check_city_scope.lua <capture.lua> <src> <built entry> <missing page file> [<difficulty>]
-- Replays captured campaign memory of a planet with cities or megafactories:
-- the displayed board, the options of each city, and a search limited to it.
-- A page absent from the capture is written to <missing page file>, exit 3.
local fixture=dofile(arg[1]);local root=arg[2];local ffi=require('ffi')
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local pages={}
for _,r in ipairs(fixture.ranges)do pages[tonumber(r.address)]=raw(r.hex)end
local function read(a,n)
    a=tonumber(ffi.cast('uintptr_t',a))
    local pieces={};local remaining=n;local at=a
    while remaining>0 do
        local page=math.floor(at/4096)*4096;local offset=at-page
        local data=pages[page]
        if not data then
            local out=assert(io.open(arg[4],'w'));out:write(string.format('0x%x',page));out:close()
            os.exit(3)
        end
        local count=math.min(remaining,4096-offset);pieces[#pieces+1]=data:sub(offset+1,offset+count)
        at=at+count;remaining=remaining-count
    end
    return table.concat(pieces)
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function pointer(s,o)
    local value=ffi.new('uint64_t[1]');ffi.copy(value,s:sub((o or 0)+1,(o or 0)+8),8)
    if value[0]<0x10000 then return nil end
    return ffi.cast('uint8_t*',value[0])
end
local function up(fn,name)
    for i=1,100 do local key,value=debug.getupvalue(fn,i);if key==name then return value end;if not key then break end end
    error('Missing upvalue '..name)
end
local function module(name)return dofile(root..'/'..name..'.lua')end
CowboyBingusModLoader={api=1,version=18,open_log=function()return nil end}
update=function()end
dofile(arg[3])
local ready=up(up(update,'tick'),'on_prediction_ready')
local Planet=up(ready,'Planet');local make_job=up(ready,'make_search_job')
local Search=module('search_session');local Catalogue=module('filter_catalogue')
local game=ffi.cast('uint8_t*',tonumber(fixture.game));local board=tonumber(fixture.board)
local planet=u(read(board+0x17a298,8),4);assert(planet<512,'No viewed planet')
local seed=u(read(board+0x78e84,4),0)
local difficulty=tonumber(arg[5]) or 10
local key=read(board+0x101454+planet*0x118,4);local definitions
for _,offset in ipairs({0x22b1a8,0x2cc9ec,0x36e230})do
    if read(board+offset,4)==key then definitions=board+offset;break end
end
assert(definitions,'Planet definitions are not cached')
local bytes=read(board+0xf7280,110*92)
local count=u(read(board+0xffc08,4),0);assert(count<=330)
local missions=count>0 and read(board+0xf9a10,count*76) or ''
local decoded={operations={}};local regions,seen={},{}
for row=0,109 do
    local at=row*92
    if bytes:byte(at+53)~=0 and bytes:byte(at+17)+bytes:byte(at+18)*256==planet then
        local op={row=row,operation_id=bytes:byte(at+25),seed=u(bytes,at+12),difficulty=bytes:byte(at+33),
            template_index=u(bytes,at+56),faction=u(bytes,at+36),missions={},modifiers={}}
        for slot=1,bytes:byte(at+89)do
            local offset=bytes:byte(at+85+slot)*76
            op.missions[slot]={seed=u(missions,offset+52),native_type=u(missions,offset+48),level_index=u(missions,offset+44)}
        end
        for i=1,bytes:byte(at+69)do op.modifiers[i]=u(bytes,at+56+i*4)end
        decoded.operations[#decoded.operations+1]=op
        if row>=30 then
            local region=math.floor((row-30)/10)
            assert(op.operation_id==region,'City rows must carry their region')
            if not seen[region]then seen[region]=true;regions[#regions+1]=region end
        end
    end
end
assert(#decoded.operations>0,'The viewed planet has no operations')
local snapshot={board=board,planet=planet,seed=seed,operations=bytes,decoded=decoded}
print(string.format('planet=%d seed=%u operations=%d city regions=[%s] difficulty=%d',planet,seed,#decoded.operations,table.concat(regions,','),difficulty))
assert(#regions>0,'View a planet with a city or megafactory')
-- The displayed board, cities included, is what the predictor produces.
local predict=Planet.bind(read,u,pointer,game,board,planet).predictor(definitions)
local ok,why=module('verify_predicted_board')(snapshot,predict(seed),u)
assert(ok,'Displayed board differs from its prediction: '..tostring(why))
print('Displayed board, city operations included, equals its prediction')
local model=Planet.bind(read,u,pointer,game,board,planet)
local function catalogue(scope)
    local function accepts(row)return Search.in_scope(row,scope)end
    local result,err=model.catalogue(snapshot,difficulty,scope and accepts)
    assert(not err,tostring(err))
    return result
end
local function names(list)local out={};for i,item in ipairs(list)do out[i]=item.name end;return table.concat(out,'; ')end
local whole=catalogue(nil)
print('whole planet: missions: '..names(whole.missions)..' | modifiers: '..names(whole.modifiers))
-- Every mission the game displays must be offered by name for its scope.
local function family(kind)
    for id,option in ipairs(Search.options)do for _,native in ipairs(option.ids)do
        if native==kind then return id,option.name end
    end end
end
local displayed=0
for _,op in ipairs(decoded.operations)do
    local scope=op.row>=30 and {region=math.floor((op.row-30)/10)} or nil
    local offered
    for _,mission in ipairs(op.missions)do
        local id,name=family(mission.native_type)
        assert(id,string.format('Mission type %d in row %d has no name',mission.native_type,op.row))
        if op.difficulty==difficulty then
            offered=offered or catalogue(scope)
            assert(offered.mission_set[id] and whole.mission_set[id],string.format('%s in row %d is displayed but not offered',name,op.row))
        end
        displayed=displayed+1
    end
end
print(string.format('All %d displayed missions have a name and are offered for their scope',displayed))
local function run(required,groups,scope)
    local function accepts(row)return Search.in_scope(row,scope)end
    local job=make_job(read,function()end,function(take)
        local frozen=Planet.bind(take,u,pointer,game,board,planet)
        local bound=frozen.predictor(definitions)
        local annotate=up(ready,'bind_constellations')
        local tag=annotate and annotate(frozen)
        local function evaluate(candidate,level,rows)
            local operations=bound(candidate,level,rows)
            if tag then for _,op in ipairs(operations)do tag(op)end end
            return operations
        end
        return function(candidate)return evaluate(candidate,difficulty,accepts)end,function(candidate)return evaluate(candidate)end
    end,{seed=(seed+1)%4294967296,limit=65536,difficulty=difficulty,required=required,constellations={groups=groups},
        scope=scope,quantum=4096,clock=os.clock,slice=0.016,batch=256,revalidate=1})
    local started=os.clock()
    while job.status=='running' do job:step(function()end)end
    return job,os.clock()-started
end
jit.flush()
for _,region in ipairs(regions)do
    local scope={region=region};local row=30+region*10+difficulty-1
    local present=false
    for _,op in ipairs(decoded.operations)do if op.row==row then present=true end end
    local active=read(board+0x78e88,92)
    local in_progress=active:byte(53)~=0 and u(active,0)==row and active:byte(17)+active:byte(18)*256==planet
    if present and in_progress then
        local city=catalogue(scope)
        print(string.format('region %d (row %d) is the operation in progress; its missions cannot be rerolled. missions: %s',
            region,row,names(city.missions)))
    elseif present then
        local city=catalogue(scope)
        print(string.format('region %d (row %d): missions: %s | modifiers: %s',region,row,names(city.missions),names(city.modifiers)))
        for id in pairs(city.mission_set)do assert(whole.mission_set[id],'A city cannot offer what the planet does not')end
        assert(#city.missions>0,'A city with an operation must offer missions')
        -- Search for a mission the game rolled for this city, so it is reachable.
        local family,title
        for _,op in ipairs(decoded.operations)do if op.row==row then
            family,title=(function()
                for id,option in ipairs(Search.options)do for _,native in ipairs(option.ids)do
                    if native==op.missions[1].native_type then return id,option.name end
                end end
            end)()
        end end
        assert(family and city.mission_set[family],'The displayed city mission must be offered')
        local reachable={}
        for _,option in ipairs(city.missions)do
            if Catalogue.possible(city,{[option.id]=true},{})then reachable[#reachable+1]=option.name end
        end
        print('  selectable alone: '..table.concat(reachable,'; '))
        local offered=city.constellation_groups[family]
        print(string.format('  %s can draw: %s',title,offered and names(offered.list) or 'unknown'))
        local groups={}
        if offered and offered.list[1]then groups[family]={[offered.list[1].id]='accept'}end
        if offered and offered.list[2]then groups[family][offered.list[2].id]='exclude'end
        local job,elapsed=run({[family]=true},groups,scope)
        assert(job.status=='matched',job.status..': '..tostring(job.error))
        assert(job.operation.row==row,'A city search must match that city: row '..job.operation.row)
        local again=Search.find({operations=job.operations},difficulty,{[family]=true},{},{groups=groups},scope)
        assert(again and again.row==row and #job.operations>=#decoded.operations,'The match carries the complete board')
        local tagged={}
        for i,mission in ipairs(job.operation.missions)do
            local list={};for tag in pairs(mission.tags or {})do list[#list+1]=tag end
            table.sort(list);tagged[i]=mission.native_type..':'..table.concat(list,'+')
        end
        print(string.format('  search matched seed=%u row=%d after %d seeds in %.2f s (%.0f seeds/s) missions=%s',
            job.seed,job.operation.row,job.attempts,elapsed,job.attempts/math.max(elapsed,0.001),table.concat(tagged,',')))
        -- The narrowed prediction equals the complete one on that row.
        for candidate=seed+1,seed+200 do
            local narrow=predict(candidate%4294967296,difficulty,function(r)return Search.in_scope(r,scope)end)
            local complete=predict(candidate%4294967296)
            assert(#narrow==1 and narrow[1].row==row,'One operation per city and difficulty')
            local match
            for _,op in ipairs(complete)do if op.row==row then match=op end end
            assert(match and match.seed==narrow[1].seed and match.template_index==narrow[1].template_index
                and #match.missions==#narrow[1].missions,'Narrowed city prediction differs')
            for i,mission in ipairs(match.missions)do
                local other=narrow[1].missions[i]
                assert(mission.seed==other.seed and mission.native_type==other.native_type and mission.level_index==other.level_index)
            end
        end
    else
        print(string.format('region %d has no operation at difficulty %d',region,difficulty))
    end
end
print('City scope: options, scoped search and narrowed prediction passed on captured campaign memory')
