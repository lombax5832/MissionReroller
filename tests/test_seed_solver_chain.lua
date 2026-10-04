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
            for _,m in ipairs(op.missions)do
                if satisfies(f.rules[m[1]],m)then found[m[1]]=true end
            end
            local all=true
            for _,k in ipairs(f.required)do if not found[k]then all=false end end
            if all then hits=hits+1 end
        end
    end
    if f.scope=='all' then return total>0 and hits==total end
    return hits>0
end

local state=4101
local function random()state=(state*1103515245+12345)%4294967296;return state end
local solved=0
for _,f in ipairs(expected.filters)do
    local paths=assert(P.shared_paths(solver.operations,f.difficulty,f.required,f.rules))
    local rows,others={},{}
    for r=(f.difficulty-1)*3,f.difficulty*3-1 do
        if r~=preserved then
            local _,seed_position=Chain.positions(r,preserved)
            if f.scope=='all' and #rows>0 then others[#others+1]=seed_position
            else rows[#rows+1]={row=r,seed_position=seed_position}end
        end
    end
    local chain=Chain.new({paths=paths,rows=rows,others=others,planet=C.planet,random=random})
    local want=f.scope=='all' and 1 or 4
    local found,candidates,seen={},0,{}
    local started=os.clock()
    local budget=f.budget or 2^31
    while #found<want and chain.steps<budget do
        local seed,done=chain.next(65536)
        if seed and not seen[seed]then
            seen[seed]=true;candidates=candidates+1
            if matches(C.board_of(seed),f)then found[#found+1]=seed end
        elseif done then break end
    end
    local took=os.clock()-started
    if #paths==0 then
        assert(#found==0 and candidates==0,f.name..': seeds without a draw path')
        print(string.format('  %s: no draw path, nothing to solve',f.name))
    else
        assert(#found==want,string.format('%s: %d of %d seeds within %d steps',f.name,#found,want,chain.steps))
        print(string.format('  %s: %d seeds, per seed %.0f walk steps, %.1f candidates, %.3f s (LuaJIT, boards included)',
            f.name,#found,chain.steps/#found,candidates/#found,took/#found))
        solved=solved+#found
    end
end
print(string.format('test_seed_solver_chain: passed (planet %d: %d seeds confirmed by the predictor)',C.planet,solved))
