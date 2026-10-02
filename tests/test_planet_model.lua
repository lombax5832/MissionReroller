local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local O=H.offsets(arg[1])
-- Usage: luajit test_planet_model.lua <src> [<capture oracle>]
-- The planet model's interface over scripted modules, then, when the saved
-- campaign capture (artifacts/level-capture-oracle.lua) is given, its
-- capture, predictor and catalogue over the real modules and memory.
local root=arg[1]
local ffi=require('ffi')
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function u(b,o)local a,c,d,e=b:byte(o+1,o+4);return a+c*256+d*65536+e*16777216 end

do
    local game,board,manager=0x10000000,0x20000000,0x30000000
    local memory,events={},{}
    local function poke(address,bytes)for i=1,#bytes do memory[address+i-1]=bytes:byte(i)end end
    local function read(address,size)
        events[#events+1]=string.format('read %x',address)
        local out={};for i=0,size-1 do out[#out+1]=string.char(memory[address+i] or 0)end
        return table.concat(out)
    end
    local function pointer(bytes)local value=u(bytes,0)+u(bytes,4)*4294967296;return value>=0x10000 and value or nil end
    local built={}
    local function note(name)built[name]=(built[name] or 0)+1;events[#events+1]=name end
    local labels,options,compatibility={},{},{}
    local stub={
        config=function(r,_,_,at)assert(r==read and at==manager);note('config');return {name='config'}end,
        effects=function(r,_,_,g,b)assert(r==read and g==game and b==board);note('effects');return {name='effects'}end,
        composition_inputs=function(r,_,_,g,b,config,effects,eligible,environments)
            assert(r==read and g==game and b==board and config.name=='config' and effects.name=='effects')
            assert(type(eligible)=='function' and type(environments)=='function')
            note('inputs');return {name='inputs'}
        end,
        constellation_inputs=function(r,_,_,g,b,effects,config)
            assert(r==read and g==game and b==board and effects.name=='effects' and config.name=='config')
            note('tags');return {name='tags'}
        end,
        predictor=function(levels,bases,predict)
            assert(type(levels)=='function' and type(bases)=='function' and type(predict)=='function')
            return function(r,_,_,g,b,definitions,planet,inputs)
                assert(r==read and g==game and b==board and definitions==0x40000000 and planet==268 and inputs.name=='inputs')
                return function(seed,difficulty,accepts)return {seed=seed,difficulty=difficulty,accepts=accepts}end
            end
        end,
        catalogue={build=function(inputs,s,difficulty,uu,o,c,accepts)
                assert(inputs.name=='inputs' and s.planet==268 and difficulty==10 and uu==u and o==options and c==compatibility)
                return {missions={{id=1}},accepts=accepts}
            end,
            constellations=function(result,tags,l,planet,difficulty,o)
                assert(tags.name=='tags' and l==labels and planet==268 and difficulty==10 and o==options)
                result.constellation_groups={[0]={list={}}}
            end},
        compatibility=compatibility,options=options,labels=labels,
        capture=function(bind,levels,predict,bases)
            assert(type(levels)=='function' and type(predict)=='function' and type(bases)=='function')
            return function(r,uu,p,g)return function(snapshot,definitions)
                local planet=bind(r,uu,p,g,snapshot.board,snapshot.planet)
                return {planet=planet,definitions=definitions}
            end end
        end}
    local function with(changes)
        local m={};for key,value in pairs(stub)do m[key]=value end
        for key,value in pairs(changes)do m[key]=value end
        return H.planet_model(root,m)
    end
    local Planet=with({})
    -- Nothing decodes until asked; each decoder is built once per binding.
    local planet=Planet.bind(read,u,pointer,game,board,268)
    assert(#events==0 and planet.board==board and planet.index==268,'Binding reads nothing')
    assert(not pcall(planet.inputs),'A missing configuration manager fails the inputs')
    assert(select(2,pcall(planet.inputs)):find('Missing composition pointer',1,true))
    assert(select(2,pcall(planet.constellation_inputs)):find('Missing configuration manager',1,true))
    poke(game+O.rva.configuration,word(manager)..word(0));events={}
    local inputs=planet.inputs()
    assert(table.concat(events,',')=='read 1347cdf8,config,effects,inputs','The manager, then the effects, as the native collectors')
    assert(planet.inputs()==inputs and planet.constellation_inputs().name=='tags')
    assert(built.config==1 and built.effects==1 and built.inputs==1 and built.tags==1,
        'Mission and tag inputs share one configuration and one effects decoder')
    -- The tag inputs alone read the manager too.
    events={}
    local tags=Planet.bind(read,u,pointer,game,board,268).constellation_inputs()
    assert(tags.name=='tags' and table.concat(events,',')=='read 1347cdf8,config,effects,tags')
    -- The predictor gets the planet's inputs and passes the request through.
    local function accepts()return true end
    local predicted=planet.predictor(0x40000000)(7,10,accepts)
    assert(predicted.seed==7 and predicted.difficulty==10 and predicted.accepts==accepts)
    -- The catalogue keeps its missions when the tag inputs fail.
    local s={planet=268,board=board}
    local catalogue,err=planet.catalogue(s,10,accepts)
    assert(catalogue.missions[1].id==1 and catalogue.accepts==accepts and catalogue.constellation_groups[0] and err==nil)
    local failing=with({constellation_inputs=function()error('Missing global effects')end})
    catalogue,err=failing.bind(read,u,pointer,game,board,268).catalogue(s,10)
    assert(catalogue.missions[1].id==1 and not catalogue.constellation_groups and tostring(err):find('Missing global effects',1,true),
        'A tag input failure leaves the mission and modifier options')
    -- The capture binds its own reads to the snapshot's board and planet.
    local result=Planet.capture(read,u,pointer,game)({board=board,planet=100},0x40000000)
    assert(result.planet.board==board and result.planet.index==100 and result.definitions==0x40000000)
    -- A build without the search or the dialog leaves those methods unavailable.
    local bare=with({predictor=false,catalogue=false,constellation_inputs=false})
    local p=bare.bind(read,u,pointer,game,board,268)
    assert(p.inputs().name=='inputs')
    assert(select(2,pcall(p.predictor,0)):find('Candidate predictor unavailable',1,true))
    assert(select(2,pcall(p.catalogue,s,10)):find('Filter catalogue unavailable',1,true))
    assert(select(2,pcall(p.constellation_inputs)):find('Constellation inputs unavailable',1,true))
end
print('Planet model: lazy shared decoders, read order, missing manager messages, predictor, catalogue with tag failure, capture binding and absent modules passed')

-- The saved campaign capture: the displayed boards are the prediction.
if not arg[2] then print('Planet model: no saved capture given; replay skipped');return end
local fixture=dofile(arg[2])
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local pages={}
for _,r in ipairs(fixture.ranges)do pages[tonumber(r.address)]=raw(r.hex)end
local function read(a,n)
    a=tonumber(ffi.cast('uintptr_t',a))
    local pieces={};local remaining=n;local at=a
    while remaining>0 do
        local page=math.floor(at/4096)*4096;local offset=at-page
        local data=assert(pages[page],string.format('Missing capture page 0x%x',page))
        local count=math.min(remaining,4096-offset);pieces[#pieces+1]=data:sub(offset+1,offset+count)
        at=at+count;remaining=remaining-count
    end
    return table.concat(pieces)
end
local function pointer(s)local value=ffi.new('uint64_t[1]');ffi.copy(value,s,8);if value[0]==0 then return nil end;return ffi.cast('uint8_t*',value[0])end
local Planet=H.planet_model(root)
local verify=dofile(root..'/verify_predicted_board.lua')
local game=ffi.cast('uint8_t*',tonumber(fixture.game));local definitions=tonumber(fixture.definitions)
local board=definitions-O.board.definitions[1]
local boards,descriptors=0,0
for index,case in ipairs(fixture.cases)do
    if index>4 then break end
    local bytes,missions=raw(case.operations),raw(case.missions)
    local decoded={operations={}};local planet
    for row=0,109 do
        local at=row*92
        if bytes:byte(at+53)~=0 then
            planet=bytes:byte(at+17)+bytes:byte(at+18)*256
            local op={row=row,operation_id=bytes:byte(at+25),seed=u(bytes,at+12),difficulty=bytes:byte(at+33),
                template_index=u(bytes,at+56),missions={},modifiers={}}
            for slot=1,bytes:byte(at+89)do
                local offset=bytes:byte(at+85+slot)*76
                op.missions[slot]={seed=u(missions,offset+52),native_type=u(missions,offset+48),level_index=u(missions,offset+44)}
            end
            for i=1,bytes:byte(at+69)do op.modifiers[i]=u(bytes,at+56+i*4)end
            decoded.operations[#decoded.operations+1]=op
        end
    end
    local snapshot={board=board,planet=planet,seed=case.seed,operations=bytes,decoded=decoded}
    local result,fingerprint=Planet.capture(read,u,pointer,game)(snapshot,definitions)
    assert(result.passed and result.independent_bases and result.bases==#decoded.operations,table.concat(result.errors,'; '))
    assert(#fingerprint>0,'The capture returns the bytes it read')
    if index==1 then
        -- Another mod gives one operation a new seed (external_edits.lua):
        -- only that row fails, and excusing it passes the board.
        local edited=decoded.operations[1];local at=edited.row*92
        local seed=(edited.seed+1)%4294967296
        local changed={operations={}}
        for i,op in ipairs(decoded.operations)do changed.operations[i]=op end
        local copy={};for k,v in pairs(edited)do copy[k]=v end;copy.seed=seed;changed.operations[1]=copy
        local tampered={board=board,planet=planet,seed=case.seed,decoded=changed,
            operations=bytes:sub(1,at+12)..word(seed)..bytes:sub(at+17)}
        local E=dofile(root..'/external_edits.lua')
        local failed=Planet.capture(read,u,pointer,game)(tampered,definitions)
        local rows=0;for row in pairs(failed.failed_rows)do assert(row==edited.row);rows=rows+1 end
        assert(not failed.passed and rows==1 and failed.general==0,table.concat(failed.errors,'; '))
        assert(E.composition_passes(failed,{[edited.row]=true}) and not E.composition_passes(failed,nil))
    end
    local model=Planet.bind(read,u,pointer,game,board,planet)
    local predict=model.predictor(definitions)
    local complete=predict(case.seed)
    assert(verify(snapshot,complete,u),'The predictor reproduces the displayed board')
    local narrow=predict(case.seed,10)
    for _,op in ipairs(narrow)do assert(op.difficulty==10)end
    local catalogue=model.catalogue(snapshot,10)
    assert(catalogue.faction and #catalogue.missions>0 and #catalogue.modifiers>0,'The catalogue offers the planet options')
    boards=boards+1
    for _,op in ipairs(complete)do descriptors=descriptors+#op.missions end
end
print(string.format('Planet model on the saved capture: %d boards, %d mission descriptors, capture, predictor and catalogue passed',boards,descriptors))
