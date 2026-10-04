-- Usage: luajit seed_solver_oracle.lua tables  <src> <capture oracle> <out.json>
--        luajit seed_solver_oracle.lua predict <src> <capture oracle> <seeds.txt> <out.json>
-- Research oracle for scripts/seed_solver.py. It replays a saved campaign
-- capture (artifacts/level-capture-oracle.lua) through the real prediction
-- modules in src: `tables` exports the frozen per-operation decision inputs
-- the solver inverts, `predict` writes the complete predicted board for each
-- campaign seed so solved seeds are checked by the mod's own predictor.
local mode,root,capture=arg[1],arg[2],arg[3]
assert((mode=='tables' and arg[4]) or (mode=='predict' and arg[5]),'Usage: tables|predict <src> <capture> ...')
local here=(arg[0]:match('^(.*[/\\])') or '')
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

if mode=='predict' then
    local out={}
    for line in io.lines(arg[4])do
        local seed=tonumber(line)
        if seed then out[#out+1]='{"seed":'..string.format('%d',seed)..',"operations":'..json(board_of(seed))..'}' end
    end
    write(arg[5],'['..table.concat(out,',\n')..']\n')
    return
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

-- tables: every normal (difficulty, operation ID) a seed can produce, with
-- the seed-independent inputs of finalization and mission composition.
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
local operations={}
local objective_ids,seeded={},true
for _,base in pairs(bases)do
    local op={row=0,id=base.id,seed=0,difficulty=base.difficulty,category=base.category,faction=base.faction,explicit_hash=base.explicit_hash}
    assert(op.explicit_hash==0,'The prototype expects no explicit template')
    op.effect_id=inputs.effect_id(op,planet)
    local budget,total=inputs.difficulty(op.difficulty,op.category)
    local templates={}
    for i,template in ipairs(inputs.templates(op,planet))do
        local modifiers={}
        for j,item in ipairs(template.modifiers)do modifiers[j]={id=item.id,weight=item.weight,cost=item.cost}end
        local candidates,weights,rules=inputs.candidates(template.index,op,planet)
        local list={}
        for j,candidate in ipairs(candidates)do list[j]={id=candidate.id,category=candidate.category} end
        local weight_list={}
        for id,weight in pairs(weights)do weight_list[#weight_list+1]={id,weight}end
        local rule_list={}
        for j,rule in ipairs(rules)do rule_list[j]={category=rule.category,minimum=rule.minimum,maximum=rule.maximum,weight=rule.weight}end
        templates[i]={index=template.index,weight=template.weight,modifiers=modifiers,candidates=list,weights=weight_list,rules=rule_list}
    end
    local levels,special=level_graph(op)
    local extra={}
    if op.category==0 then
        for _,template in ipairs(templates)do
            for _,item in ipairs(template.modifiers)do
                local kind=inputs.extra_mission(item.id,op.faction)
                if kind then extra[#extra+1]={item.id,kind} end
            end
        end
    end
    -- Usage counts the category the mission metadata gives under this effect.
    local categories,listed={},{}
    for _,template in ipairs(templates)do
        for _,candidate in ipairs(template.candidates)do
            if not listed[candidate.id]then
                listed[candidate.id]=true
                categories[#categories+1]={candidate.id,inputs.mission(candidate.id,planet,op.effect_id,0,false).category}
            end
        end
    end
    local entry={difficulty=op.difficulty,id=op.id,category=op.category,faction=op.faction,
        budget=budget,total=total,templates=templates,levels=levels,special=special and true or false,extra=extra,
        mission_categories=categories,effect_id=op.effect_id}
    -- Mission-seed draws: enemy tags (constellation_prediction.lua) and side
    -- objectives (side_objective_prediction.lua) for every candidate kind,
    -- when the capture holds their inputs.
    if seeded then
        seeded=pcall(function()
            tag_inputs=tag_inputs or model.constellation_inputs()
            objective_inputs=objective_inputs or model.objective_inputs()
            local context=objective_inputs.context(planet,op.effect_id)
            local banned={}
            for id in pairs(context.banned)do banned[#banned+1]=id end
            local kinds={}
            for _,c in ipairs(categories)do
                local kind=c[1]
                local record=tag_inputs.mission(kind)
                local settings=nil
                if record.faction>=2 and record.faction<=4 then settings=tag_inputs.settings(record.faction,op.difficulty)end
                local srecord=objective_inputs.mission(kind)
                local pick,reachable=objective_inputs.environments(planet,kind,context.modifiers)
                local environments={}
                for value in pairs(reachable)do environments[#environments+1]=value end
                table.sort(environments)
                for _,e in ipairs(srecord.pool)do objective_ids[e.id]=true end
                kinds[#kinds+1]={kind=kind,faction=record.faction,horde=record.horde,exclusions=record.exclusions,settings=settings,
                    objectives={lo=srecord.lo,hi=srecord.hi,category=srecord.category,pool=srecord.pool,
                        scale=objective_inputs.scale(srecord.category) or false},environments=environments,
                    environment=environment_tables(pick)}
            end
            entry.initial_tags=tag_inputs.campaign(planet,op.effect_id)
            entry.context={banned=banned,extra=context.extra,modifiers=context.modifiers}
            entry.counts=objective_inputs.counts(op.difficulty);entry.kinds=kinds
        end)
    end
    operations[#operations+1]=entry
end
local objectives,disabled_tags={},{}
if seeded then
    for id in pairs(objective_ids)do
        local r=objective_inputs.objective(id)
        objectives[#objectives+1]={pool_id=id,id=r.id,cap=r.cap,minimum=r.minimum,maximum=r.maximum,mask=r.mask,
            environments=r.environments,disabled=objective_inputs.disabled(r.id) and true or false}
    end
    for tag=0,31 do if tag_inputs.disabled(tag)then disabled_tags[#disabled_tags+1]=tag end end
else
    for _,entry in ipairs(operations)do entry.kinds,entry.initial_tags,entry.context,entry.counts=nil end
end
-- The filter rows (side_objective_prediction.lua R.rows): id -> row key, name.
local rows={}
for id,row in pairs(SideObjectives.row_of)do rows[#rows+1]={id=id,row=row,name=SideObjectives.names[row]}end
table.sort(rows,function(a,b)return a.id<b.id end)
local tag_names={}
for tag,name in pairs(Constellations.names)do tag_names[#tag_names+1]={tag,name}end
-- Mission family names by kind (search_session.lua options).
local kind_names={}
for _,option in ipairs(m.options)do for _,id in ipairs(option.ids)do kind_names[#kind_names+1]={id,option.name}end end
table.sort(operations,function(a,b)return a.difficulty*100+a.id<b.difficulty*100+b.id end)
local specials={}
for i,event in ipairs(identity.specials or {})do specials[i]={id=event.id,minimum=event.minimum,maximum=event.maximum}end
local active=identity.active
if active and active.planet==planet then active={row=active.row,id=active.id,seed=active.seed,difficulty=active.difficulty}else active=nil end
write(arg[4],json({planet=planet,active=active,capture_seed=case.seed,pool_count=identity.pool_count,max_difficulty=identity.max_difficulty,
    specials=specials,operations=operations,objectives=objectives,disabled_tags=disabled_tags,
    objective_rows=rows,tag_names=tag_names,kind_names=kind_names})..'\n')
print(string.format('seed_solver_oracle: %d operations exported for planet %d%s',#operations,planet,
    seeded and ', with enemy tags and side objectives' or ', missions only (the capture lacks tag and objective inputs)'))
