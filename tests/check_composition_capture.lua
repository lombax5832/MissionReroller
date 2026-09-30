local fixture=dofile(arg[1]);local root=arg[2];local ffi=require('ffi')
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local pages={}
for _,r in ipairs(fixture.ranges)do pages[tonumber(r.address)]=raw(r.hex)end
local cache={}
local function read(a,n)
    a=tonumber(ffi.cast('uintptr_t',a));local key=string.format('%.0f:%d',a,n)
    if cache[key]then return cache[key]end
    local pieces={};local remaining=n;local at=a
    while remaining>0 do
        local page=math.floor(at/4096)*4096;local offset=at-page
        local data=pages[page]
        if not data and arg[3] then
            local out=assert(io.open(arg[3],'w'));out:write(string.format('0x%x',page));out:close()
        end
        assert(data,string.format('Missing composition page 0x%x',page))
        local count=math.min(remaining,4096-offset);pieces[#pieces+1]=data:sub(offset+1,offset+count)
        at=at+count;remaining=remaining-count
    end
    local bytes=table.concat(pieces);cache[key]=bytes;return bytes
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function pointer(s)local value=ffi.new('uint64_t[1]');ffi.copy(value,s,8);if value[0]==0 then return nil end;return ffi.cast('uint8_t*',value[0])end
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local function module(name)return H.module(root..'/'..name..'.lua')end
local game,definitions=tonumber(fixture.game),tonumber(fixture.definitions)
game=ffi.cast('uint8_t*',game)
local board=definitions-0x22b1a8
local Planet=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua').planet_model(root)
local inputs=Planet.bind(read,u,pointer,game,board,fixture.planet).inputs()
local rng=module('generation_rng')
local bases=module('operation_base_inputs')(module('operation_identity')(rng),module('special_operation_inputs'),module('template_environments'))
local predict=module('composition_prediction')(rng,module('mission_category_choice'),module('mission_level_choice'),module('mission_weighted_choice')(rng),module('operation_finalization')(rng))
local levels=module('level_inputs')(read,u,game)
-- Without make_bases: the displayed bases, the earlier checkpoint.
local capture=module('composition_capture')(Planet.bind,module('level_inputs'),predict)(read,u,pointer,game)
local search_factory,candidate_factory
if arg[5] then
    local function up(fn,name)
        for i=1,100 do local key,value=debug.getupvalue(fn,i);if key==name then return value end;if not key then break end end
        error('Missing upvalue '..name)
    end
    CowboyBingusModLoader={api=1,version=18,open_log=function()return nil end}
    update=function()end
    dofile(arg[5])
    capture=up(up(up(update,'tick'),'prepare'),'Planet').capture(read,u,pointer,game)
    if arg[6] then
        local ready=up(up(update,'tick'),'on_prediction_ready')
        local packaged=up(ready,'Planet')
        search_factory=up(ready,'make_search_job')
        candidate_factory=function(take,planet)return packaged.bind(take,u,pointer,game,board,planet).predictor(definitions)end
    end
end
local active_bytes=read(board+0x17a2c0,92)
local active
if active_bytes:byte(53)~=0 and (not fixture.planet or active_bytes:byte(17)+active_bytes:byte(18)*256==fixture.planet) then
    active={row=u(active_bytes,0),seed=u(active_bytes,12),id=active_bytes:byte(25),template_index=u(active_bytes,56),modifiers={}}
    for i=0,active_bytes:byte(69)-1 do active.modifiers[#active.modifiers+1]=u(active_bytes,60+i*4)end
end
local total=0;local baseline_snapshot;local cached_predictor;local compatibility_catalogue
for case_index,case in ipairs(fixture.cases)do
    local bytes,missions=raw(case.operations),raw(case.missions)
    local operations,planet={},nil
    for row=0,109 do
        local at=row*92
        if bytes:byte(at+53)~=0 then
            planet=bytes:byte(at+17)+bytes:byte(at+18)*256
            operations[#operations+1]={row=row,id=bytes:byte(at+25),seed=u(bytes,at+12),difficulty=bytes:byte(at+33),
                faction=u(bytes,at+36),category=u(bytes,at+28),explicit_hash=u(bytes,at+8)}
        end
    end
    local output=predict(operations,planet,inputs,function(op)return levels(definitions,op)end,active)
    local independent,preserved=bases(read,u,pointer,game,board,definitions,planet,inputs)(case.seed)
    if case_index==1 then
        local campaign=board+0x101438
        local function reject(overrides,expected)
            local ok,why=pcall(bases,function(address,size)
                local at=tonumber(ffi.cast('uintptr_t',address));return overrides[at] or read(address,size)
            end,u,pointer,game,board,definitions,planet,inputs)
            assert(not ok and tostring(why):find(expected,1,true),tostring(why))
        end
        local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
        reject({[campaign+0x46050+planet*0x130]='\0'},'Planet generation disabled')
        reject({[campaign+0x7284c]=word(0)},'Unsupported normal campaign event count')
        reject({[campaign+0x78c60]=word(1),[campaign+0x77a64]=word(planet)},'Unsupported invasion operation bases')
        for i=0,u(read(campaign+0x7284c,4),0)-1 do
            local at=campaign+0x7004c+i*20
            if u(read(at+8,4),0)==planet then reject({[at+12]=word(2)},'Unsupported defense operation bases');break end
        end
    end
    assert(#independent==#operations,'Independent operation count mismatch')
    for i,op in ipairs(independent)do
        for _,key in ipairs({'row','id','seed','difficulty','faction','category','explicit_hash'})do
            assert(op[key]==operations[i][key],string.format('Independent base mismatch row=%d field=%s predicted=%s actual=%s',op.row,key,tostring(op[key]),tostring(operations[i][key])))
        end
    end
    output=predict(independent,planet,inputs,function(op)return levels(definitions,op)end,preserved)
    if candidate_factory then
        cached_predictor=cached_predictor or candidate_factory(read,planet)
        output=cached_predictor(case.seed)
    end
    local decoded={operations={}}
    for _,op in ipairs(operations)do
        local at=op.row*92
        local observed={row=op.row,operation_id=op.id,seed=op.seed,difficulty=op.difficulty,template_index=u(bytes,at+56),missions={}}
        for slot=1,bytes:byte(at+89)do
            local offset=bytes:byte(at+85+slot)*76
            observed.missions[slot]={seed=u(missions,offset+52),native_type=u(missions,offset+48),level_index=u(missions,offset+44)}
        end
        decoded.operations[#decoded.operations+1]=observed
    end
    local snapshot={board=board,planet=planet,seed=case.seed,operations=bytes,decoded=decoded}
    if case_index==1 then
        local catalogue=module('filter_catalogue').build(inputs,snapshot,10,u,module('search_session').options,module('mission_compatibility'))
        compatibility_catalogue=catalogue
        assert(#catalogue.missions>0 and #catalogue.modifiers>0,'Real capture must provide faction-valid filter choices')
        print(string.format('Real catalogue faction=%d missions=%d modifiers=%d',catalogue.faction,#catalogue.missions,#catalogue.modifiers))
    end
    for _,op in ipairs(output)do if op.difficulty==10 then
        local catalogue=compatibility_catalogue
        local rules={};for id in pairs(catalogue.modifier_set)do rules[id]='exclude' end
        for _,id in ipairs(op.modifiers)do assert(catalogue.modifier_set[id],'Predicted modifier absent from eligible pool');rules[id]='require' end
        local required={};local search=module('search_session')
        for id,opt in ipairs(search.options)do for _,m in ipairs(op.missions)do for _,kind in ipairs(opt.ids)do
            if m.native_type==kind then required[id]=true end
        end end end
        assert(module('filter_catalogue').possible(catalogue,required,rules),'Native operation rejected by compatibility')
    end end
    assert(module('verify_predicted_board')(snapshot,output,u))
    local observed_type=decoded.operations[1].missions[1].native_type
    decoded.operations[1].missions[1].native_type=255
    assert(not module('verify_predicted_board')(snapshot,output,u),'Publication must reject a wrong mission')
    decoded.operations[1].missions[1].native_type=observed_type
    if not baseline_snapshot then baseline_snapshot=snapshot end
    local catalogue=module('search_session')
    local search=module('seed_search')(function(seed)
        local candidate,keep=bases(read,u,pointer,game,board,definitions,planet,inputs)(seed)
        return predict(candidate,planet,inputs,function(op)return levels(definitions,op)end,keep)
    end,catalogue,{seed=case.seed,limit=1,difficulty=10,required={[1]=true,[2]=true,[3]=true}})
    local expected=catalogue.find(decoded,10,{[1]=true,[2]=true,[3]=true})
    assert(search:step()==(expected and 'matched' or 'exhausted'),'Independent filter result must agree with oracle board')
    if expected then assert(search.operation.row==expected.row and search.seed==case.seed)end
    local result,fingerprint=capture(snapshot,definitions)
    assert(result.passed,table.concat(result.errors,'; '))
    if arg[5] then
        assert(result.independent_bases and result.bases==#operations)
        local op=decoded.operations[1];local seed=op.seed;op.seed=(seed+1)%4294967296
        local mismatch,same_inputs=capture(snapshot,definitions)
        assert(not mismatch.passed and same_inputs==fingerprint,'Observed operation seeds must not drive independent prediction')
        op.seed=seed
    end
    local first=decoded.operations[1].missions[1]
    local seed=first.seed;first.seed=(seed+1)%4294967296
    local mismatch,again=capture(snapshot,definitions)
    assert(not mismatch.passed and #mismatch.errors==1,'Observed seed must only affect comparison')
    assert(fingerprint==again,'Observed mission seed must not affect captured prediction inputs')
    first.seed=seed
    local first_op=decoded.operations[1];local difficulty=first_op.difficulty
    first_op.difficulty=nil
    local ok,reason=pcall(capture,snapshot,definitions)
    if arg[5] then assert(ok and not reason.passed,'Observed difficulty must only affect independent comparison')
    else assert(not ok and tostring(reason):find('[COMPOSITION_INPUT] decoded row=',1,true),'Missing difficulty must name the decoded row')end
    first_op.difficulty=difficulty
    for _,op in ipairs(output)do
        local at=op.row*92;local prefix='seed='..case.seed..' row='..op.row..' '
        assert(op.valid,prefix..'predicted invalid')
        assert(op.template_index==u(bytes,at+56),prefix..'template')
        assert(#op.modifiers==bytes:byte(at+69),prefix..'modifier count')
        for i,id in ipairs(op.modifiers)do assert(id==u(bytes,at+56+i*4),prefix..'modifier')end
        assert(#op.missions==bytes:byte(at+89),prefix..'mission count '..#op.missions)
        for i,m in ipairs(op.missions)do
            local at_m=bytes:byte(at+85+i)*76
            assert(m.seed==u(missions,at_m+52),prefix..'mission seed slot='..i)
            assert(m.native_type==u(missions,at_m+48),prefix..'mission type slot='..i..' predicted='..m.native_type..' live='..u(missions,at_m+48))
            assert(m.level_index==u(missions,at_m+44),prefix..'mission level slot='..i)
            total=total+1
        end
    end
end
print(string.format('Complete composition from base operation inputs: %d boards, %d mission descriptors matched',#fixture.cases,total))
if arg[6] then
    local s=baseline_snapshot
    local job=search_factory(read,function(take)
        assert(Planet.capture(take,u,pointer,game)(s,definitions).passed)
    end,function(take)return candidate_factory(take,s.planet)end,
        {seed=0,limit=256,difficulty=10,required={[1]=true,[2]=true,[3]=true},quantum=512})
    local frames,max_seconds=0,0
    while job.status=='running' do
        local start=os.clock();job:step(function()end);max_seconds=math.max(max_seconds,os.clock()-start)
        frames=frames+1;assert(frames<100000,'Search failed to finish within work budget')
    end
    assert(job.status=='matched',job.status..': '..tostring(job.error))
    local options=module('search_session')
    assert(options.find({operations={job.operation}},10,{[1]=true,[2]=true,[3]=true}))
    print(string.format('Packaged cooperative search matched seed=%u row=%d attempts=%d frames=%d ranges=%d max_slice_ms=%.3f',job.seed,job.operation.row,job.attempts,frames,job.ranges,max_seconds*1000))
end
if arg[4] then
    local file=assert(io.open(arg[4],'w'));file:write('[')
    local first=true
    for key,value in pairs(cache)do
        local address,size=key:match('^(%d+):(%d+)$')
        if not first then file:write(',')end;first=false
        local hex=(value:gsub('.',function(c)return string.format('%02x',c:byte())end))
        file:write(string.format('{"address":%s,"size":%s,"hex":"%s"}',address,size,hex))
    end
    file:write(']');file:close()
end
