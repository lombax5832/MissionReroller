-- Usage: luajit test_seed_solver_chain.lua <src> <capture> <filters.lua>
-- Solves each filter of tests/test_seed_solver_lua.py with the LuaJIT seed
-- solver (seed_solver_inputs, seed_solver_paths, seed_solver_chain) on a
-- saved capture, and checks every candidate with the mod's own predictor
-- (scripts/seed_solver_capture.lua board_of): a filter with draw paths must
-- yield matching seeds within the step budget, one without must have none.
-- Prints the work per matching seed.
local root,capture,expected=arg[1],arg[2],dofile(arg[3])
local here=(arg[0]:match('^(.*[/\\])') or '')
local C=dofile(here..'../scripts/seed_solver_capture.lua')(here..'../scripts/',root,capture)
local H=C.H
local solver,identity=C.solver_inputs()
local Math=H.module(root..'/seed_solver_math.lua')
local Paths=H.module(root..'/seed_solver_paths.lua')(H.module(root..'/mission_category_choice.lua'),
    H.module(root..'/mission_weighted_choice.lua'),H.module(root..'/operation_finalization.lua'))
local Chain=H.module(root..'/seed_solver_chain.lua')(Math)
local P=Paths.new({records=solver.records,row_of=C.SideObjectives.row_of,disabled_tags=solver.disabled_tags})
local active=identity.active
local preserved=active and active.planet==C.planet and active.row or nil
local Time=H.module(root..'/seed_solver_time.lua')()
local make_rng=H.module(root..'/generation_rng.lua')
local Identity=H.module(root..'/operation_identity.lua')(make_rng)

-- Day / Night on a synthetic sky (as tests/test_day_night.lua builds one):
-- one body spinning in 15.7 hours. Node longitudes come from the capture's
-- level nodes (day_night.lua P.longitude) when it holds their pages, else
-- from a synthetic layout that keeps neighbouring nodes close.
local Sky=H.module(root..'/planet_sky.lua')(make_rng)
local D=H.module(root..'/day_night.lua')(Sky)
local NOW=84733314.67
local ffi=require('ffi')
local single=ffi.new('float[1]')
local function float(bytes,at)ffi.copy(single,bytes:sub(at+1,at+4),4);return single[0]end
local real=true
local longitudes={}
local function longitude(node)
    if longitudes[node]==nil then
        local ok,position=pcall(C.read,C.definitions+node*0x88+4,8)
        if ok then longitudes[node]=math.deg(math.atan2(float(position,4),float(position,0)))
        else real=false;longitudes[node]=(node*3.7)%360-180 end
    end
    return longitudes[node]
end
for _,op in ipairs(solver.operations)do for _,node in ipairs(op.levels)do longitude(node)end end
if not real then for node in pairs(longitudes)do longitudes[node]=(node*3.7)%360-180 end end
print(string.format('  Day / Night: %s node longitudes',real and "the capture's" or 'synthetic'))
local function sky_checker(side)
    local Q={0,0,0,1}
    local spin=56520
    local sky={seed=1,viewer=0,bodies={[0]={before=Q,after=Q,parent=9,distance=500,orbit={90000,90000,0},
        spin={spin,spin,0},phase={0.4,0.4}}}}
    local planet={sky=sky,buffer=Sky.buffer(Sky.day_length(sky,NOW),D.BAND,D.WANTED)}
    planet.longitude=longitude
    local c=D.checker(planet,side)
    c.refresh(NOW)
    return c
end

-- search_session.lua semantics for one mission and its kind's rules.
local function satisfies(rule,m)
    if not rule then return true end
    local tags,objectives=m[4],m[5]
    if rule.tags and next(rule.tags)then
        if not tags then return false end
        local set={}
        for _,t in ipairs(tags)do set[t]=true end
        local wanted,found=false,false
        for t,mode in pairs(rule.tags)do
            if mode=='exclude' then if set[t]then return false end
            else wanted=true;if set[t]then found=true end end
        end
        if wanted and not found then return false end
    end
    if rule.objectives and next(rule.objectives)then
        if not objectives then return false end
        local list={}
        for i,o in ipairs(objectives)do list[i]={id=o[1],role=o[2]}end
        local rows=C.SideObjectives.set(list)
        for row,mode in pairs(rule.objectives)do
            if (mode=='require')~=(rows[row]==true)then return false end
        end
    end
    return true
end
local function matches(board,f)
    local hits,total=0,0
    for _,op in ipairs(board)do
        if op.difficulty==f.difficulty and op.row~=preserved then
            total=total+1
            local found={}
            local placed={missions={}}
            for i,m in ipairs(op.missions)do
                if satisfies(f.rules[m[1]],m)then found[m[1]]=true end
                placed.missions[i]={level_index=m[3]}
            end
            local all=true
            for _,k in ipairs(f.required)do if not found[k]then all=false end end
            if f.daynight and not f.daynight.accepts(placed)then all=false end
            if all then hits=hits+1 end
        end
    end
    if f.scope=='all' then return total>0 and hits==total end
    return hits>0
end

local state=4101
local function random()state=(state*1103515245+12345)%4294967296;return state end

-- The IDs found valid before the search are exactly those whose operations
-- the checker passes on predicted boards (normal graphs, with missions).
local function check_valid(f,valid)
    local checked=0
    for _=1,200 do
        for _,op in ipairs(C.predict(random()))do
            if op.difficulty==f.difficulty and op.row~=preserved and op.valid and #op.missions>0 then
                assert(f.daynight.accepts(op)==(valid[op.id]==true),
                    string.format('%s: ID %d valid=%s, the checker says %s',f.name,op.id,tostring(valid[op.id]),
                        tostring(f.daynight.accepts(op))))
                checked=checked+1
            end
        end
    end
    return checked
end

local function solve(f)
    local operations=solver.operations
    local accept,note=nil,''
    if f.daynight then
        local valid,count,total=Time.valid_ids(operations,f.difficulty,f.daynight.accepts)
        local checked=check_valid(f,valid)
        note=string.format(' [%s: %d of %d IDs valid, agreeing with the checker on %d operations]',
            f.daynight.side,count,total,checked)
        local kept={}
        for _,op in ipairs(operations)do
            if op.difficulty~=f.difficulty or valid[op.id]then kept[#kept+1]=op end
        end
        operations=kept
        accept=Time.accept(solver.operations,f.difficulty,f.daynight.accepts,Identity,identity,f.scope)
        if count==0 then
            print(string.format('  %s: no valid position at difficulty %d now, nothing to solve%s',f.name,f.difficulty,note))
            return
        end
    end
    local paths=assert(P.shared_paths(operations,f.difficulty,f.required,f.rules))
    local rows,others={},{}
    for r=(f.difficulty-1)*3,f.difficulty*3-1 do
        if r~=preserved then
            local _,seed_position=Chain.positions(r,preserved)
            if f.scope=='all' and #rows>0 then others[#others+1]=seed_position
            else rows[#rows+1]={row=r,seed_position=seed_position}end
        end
    end
    local chain=Chain.new({paths=paths,rows=rows,others=others,planet=C.planet,random=random,accept=accept})
    local want=f.scope=='all' and 1 or 4
    local found,candidates,seen={},0,{}
    local started=os.clock()
    while #found<want do
        local seed,done=chain.next(65536)
        if seed and not seen[seed]then
            seen[seed]=true;candidates=candidates+1
            if matches(C.board_of(seed),f)then found[#found+1]=seed end
        elseif done then break end
    end
    local took=os.clock()-started
    if #paths==0 then
        assert(#found==0 and candidates==0,f.name..': seeds without a draw path')
        print(string.format('  %s: no draw path, nothing to solve%s',f.name,note))
        return 0
    end
    assert(#found==want,string.format('%s: %d of %d seeds within %d steps',f.name,#found,want,chain.steps))
    print(string.format('  %s: %d seeds, per seed %.0f walk steps, %.1f candidates, %.3f s (LuaJIT, boards included)%s',
        f.name,#found,chain.steps/#found,candidates/#found,took/#found,note))
    return #found
end

local solved=0
for _,f in ipairs(expected.filters)do
    solved=solved+(solve(f) or 0)
    if f.scope=='any' then
        for _,side in ipairs({'night','day'})do
            local g={}
            for k,v in pairs(f)do g[k]=v end
            g.name=f.name..', at '..side;g.daynight=sky_checker(side)
            solved=solved+(solve(g) or 0)
        end
    end
end
print(string.format('test_seed_solver_chain: passed (planet %d: %d seeds confirmed by the predictor)',C.planet,solved))
