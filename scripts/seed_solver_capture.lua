-- Replays a saved capture through the modules in src, for the seed solver
-- research (docs/SEED_SOLVER_RESEARCH.md):
--   local C=dofile('scripts/seed_solver_capture.lua')(here, src, capture)
-- C.predict(seed) is the predictor, C.board_of(seed) the board with each
-- mission's tags, objectives and environment, C.solver_inputs() the
-- solver's inputs (src/seed_solver_inputs.lua) for every normal operation.
-- Captures: artifacts/level-capture-oracle.lua (campaign) or
-- artifacts/planet-live/capture.lua (viewed planet).
return function(here,root,capture)
    local H=dofile(here..'../tests/harness.lua')
    local O=H.offsets(root)
    local ffi=require('ffi')
    local fixture=dofile(capture)
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
    local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
    local function pointer(s)local value=ffi.new('uint64_t[1]');ffi.copy(value,s,8);if value[0]==0 then return nil end;return ffi.cast('uint8_t*',value[0])end

    -- The composition and identity stages are wrapped to see their inputs; the
    -- wrappers call the real modules unchanged.
    local seen={}
    local Planet,m=H.planet_model(root)
    local real_identity,real_composition=m.identity,m.composition_prediction
    Planet=H.planet_model(root,{
        identity=function(input,seed)seen.identity=input;return real_identity(input,seed)end,
        composition_prediction=function(...)
            local predict=real_composition(...)
            return function(operations,planet,inputs,level_graph,active)
                seen.operations,seen.planet,seen.inputs,seen.level_graph,seen.active=operations,planet,inputs,level_graph,active
                return predict(operations,planet,inputs,level_graph,active)
            end
        end})

    local game=ffi.cast('uint8_t*',tonumber(fixture.game))
    local board,definitions,planet,case
    if fixture.cases then
        -- A saved campaign capture (level-capture-oracle.lua): boards of known seeds.
        definitions=tonumber(fixture.definitions);board=definitions-O.board.definitions[1]
        case=fixture.cases[1];local bytes=raw(case.operations)
        for row=0,109 do if bytes:byte(row*92+53)~=0 then planet=bytes:byte(row*92+17)+bytes:byte(row*92+18)*256 end end
    else
        -- A viewed-planet capture (scripts/check_live_planet.py): the planet the
        -- map shows and the board's own seed, as tests/check_viewed_planet.lua reads them.
        board=tonumber(fixture.board)
        planet=u(read(board+O.board.selection,8),4);assert(planet<512,'No viewed planet')
        local key=read(board+O.board.campaign+0x1c+planet*O.campaign.definition_stride,4)
        for _,offset in ipairs(O.board.definitions)do
            if read(board+offset,4)==key then definitions=board+offset;break end
        end
        assert(definitions,'Planet definitions are not cached')
        case={seed=u(read(board+O.board.seed,4),0)}
    end
    local predict=Planet.bind(read,u,pointer,game,board,planet).predictor(definitions)

    local function json(v,depth)
        depth=depth or 0;assert(depth<12,'JSON depth')
        local t=type(v)
        if t=='number' then
            if v~=v or v==math.huge or v==-math.huge then error('Non-finite number')end
            if v==math.floor(v) and math.abs(v)<2^53 then return string.format('%d',v)end
            return string.format('%.17g',v)
        elseif t=='boolean' then return tostring(v)
        elseif t=='string' then return string.format('%q',v):gsub('\\\n','\\n')
        elseif t=='nil' then return 'null'
        elseif t=='table' then
            local n=#v;local count=0
            for _ in pairs(v)do count=count+1 end
            local parts={}
            if count==n and n>0 then
                for i=1,n do parts[i]=json(v[i],depth+1)end
                return '['..table.concat(parts,',')..']'
            end
            local keys={}
            for k,item in pairs(v)do
                local kind=type(item)
                if kind~='function' and kind~='cdata' and kind~='userdata' then keys[#keys+1]=k end
            end
            table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
            for _,k in ipairs(keys)do parts[#parts+1]=string.format('%q',tostring(k))..':'..json(v[k],depth+1)end
            return '{'..table.concat(parts,',')..'}'
        end
        return 'null'
    end
    local function write(path,text)local f=assert(io.open(path,'wb'));f:write(text);f:close()end

    -- Enemy tags and side objectives, resolved as constellation_runtime.lua and
    -- side_objective_runtime.lua resolve them for a predicted operation.
    local model=Planet.bind(read,u,pointer,game,board,planet)
    local Constellations=H.module(root..'/constellation_prediction.lua')
    local SideObjectives=H.module(root..'/side_objective_prediction.lua')
    local tag_inputs,objective_inputs
    local function per_mission(op)
        tag_inputs=tag_inputs or model.constellation_inputs()
        objective_inputs=objective_inputs or model.objective_inputs()
        local initial=tag_inputs.campaign(planet,op.effect_id)
        local context=objective_inputs.context(planet,op.effect_id)
        local counts=objective_inputs.counts(op.difficulty)
        return function(mission)
            local kind,seed=mission.native_type,mission.seed
            local record=tag_inputs.mission(kind);local tags=false
            if record.faction>=2 and record.faction<=4 then
                tags=Constellations.resolve(seed,tag_inputs.settings(record.faction,op.difficulty),initial,record,tag_inputs.disabled).list
            end
            local srecord=objective_inputs.mission(kind)
            local environment=objective_inputs.environments(planet,kind,context.modifiers)(seed)
            local list=SideObjectives.resolve(seed,op.difficulty,srecord,counts,objective_inputs.scale(srecord.category),
                {objective=objective_inputs.objective,disabled=objective_inputs.disabled,context=context,
                    environment=function()return environment end})
            local objectives={}
            for i,o in ipairs(list)do objectives[i]={o.id,o.role}end
            return tags,objectives,environment
        end
    end

    local function board_of(seed)
        local result={}
        for _,op in ipairs(predict(seed))do
            local missions={}
            -- A capture made before the mission-seed inputs were read has no
            -- pages for them: those boards carry missions only.
            local ok,resolve=pcall(per_mission,op)
            for i,mission in ipairs(op.missions)do
                missions[i]={mission.native_type,mission.seed,mission.level_index}
                if ok then
                    local tags,objectives,environment=resolve(mission)
                    missions[i][4],missions[i][5],missions[i][6]=tags,objectives,environment
                end
            end
            result[#result+1]={row=op.row,id=op.id,seed=op.seed,difficulty=op.difficulty,valid=op.valid,
                template_index=op.template_index,modifiers=op.modifiers,missions=missions}
        end
        return result
    end

    -- side_objective_inputs.lua keeps the environment draw's weights in the
    -- closures environments() returns; read them back so the solver can
    -- constrain the draw. A pick is `state1 mod total` against cumulative units.
    local function upvalues(fn)
        local values={}
        for i=1,255 do
            local name,value=debug.getupvalue(fn,i)
            if not name then break end
            values[name]=value
        end
        return values
    end
    local function weighted_tables(fn)
        local v=upvalues(fn)
        if not v.candidates then return {units={},indices={}}end -- no candidates: always 0
        local indices={}
        for k,c in ipairs(v.candidates)do indices[k]=c.index end
        return {units=v.units,indices=indices}
    end
    local function environment_tables(pick)
        local v=upvalues(pick)
        if not v.inner then return false end -- planet without a definition: always 0
        local inner={}
        for j,fn in pairs(v.inner)do
            local w=upvalues(fn)
            local ids={}
            for s=0,7 do ids[s+1]=w.rows[s].id end
            local t=weighted_tables(w.pick);t.ids=ids;t.biome=j
            inner[#inner+1]=t
        end
        table.sort(inner,function(a,b)return a.biome<b.biome end)
        return {biome=weighted_tables(v.biome),inner=inner}
    end

    -- Every normal (difficulty, operation ID) a seed can produce, and the
    -- solver's inputs for them; missions only when the capture lacks the
    -- mission-seed inputs.
    local function solver_inputs()
        predict(case.seed)
        local identity,inputs,level_graph=seen.identity,seen.inputs,seen.level_graph
        local bases={}
        local probe=1
        for _=1,4000 do
            probe=(probe*1103515245+12345)%4294967296
            predict(probe)
            for _,op in ipairs(seen.operations)do
                if not op.special and not op.preserved then
                    local key=op.difficulty..':'..op.id
                    if not bases[key]then
                        bases[key]={difficulty=op.difficulty,id=op.id,category=op.category,faction=op.faction,explicit_hash=op.explicit_hash}
                    end
                end
            end
        end
        -- The solver's inputs (src/seed_solver_inputs.lua) in the JSON shape
        -- scripts/seed_solver.py reads. A capture made before the mission-seed
        -- inputs were read has no pages for them: missions only.
        local Inputs=H.module(root..'/seed_solver_inputs.lua')
        local base_list={}
        for _,base in pairs(bases)do base_list[#base_list+1]=base end
        local ok,solver=pcall(function()
            return Inputs(planet,base_list,inputs,level_graph,model.constellation_inputs(),model.objective_inputs(),environment_tables)
        end)
        if not ok then solver=Inputs(planet,base_list,inputs,level_graph,nil,nil,environment_tables)end
        return solver,identity
    end
    return {H=H,O=O,planet=planet,case=case,predict=predict,board_of=board_of,solver_inputs=solver_inputs,
        m=m,Constellations=Constellations,SideObjectives=SideObjectives,json=json,write=write,model=model}
end
