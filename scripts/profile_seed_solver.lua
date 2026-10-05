-- Usage: luajit scripts/profile_seed_solver.lua <capture.lua> [tags|objectives|both] [walk steps]
-- Times the seed solver (docs/SEED_SOLVER_RESEARCH.md) on a hard request
-- from a viewed-planet capture: three missions of one operation, each with
-- its enemy force and/or Lidar Station and SEAF Artillery excluded. Prints
-- the set-up, the alternatives per mission step, each path's root, the
-- walk's steps per second and one board prediction's cost. For a function
-- profile run it with LuaJIT's sampler: set LUA_PATH to
-- ../tools/src/LuaJIT/src/?.lua;; and pass -jp=F before the script; -joff
-- shows the interpreter's speed.
local here=(arg[0]:match('^(.*[/\\])') or '')..'../'
local root=here..'src'
local C=dofile(here..'scripts/seed_solver_capture.lua')(here..'scripts/',root,arg[1])
local H=C.H
local clock=os.clock
local t0=clock()
local solver,identity=C.solver_inputs()
local t_inputs=clock()-t0
local Math=H.module(root..'/seed_solver_math.lua')
local Paths=H.module(root..'/seed_solver_paths.lua')(H.module(root..'/mission_category_choice.lua'),
    H.module(root..'/mission_weighted_choice.lua'),H.module(root..'/operation_finalization.lua'))
local Chain=H.module(root..'/seed_solver_chain.lua')(Math)
local P=Paths.new({records=solver.records,row_of=C.SideObjectives.row_of,disabled_tags=solver.disabled_tags})
local active=identity.active
local preserved=active and active.planet==C.planet and active.row or nil
local avoid={}
for row,name in pairs(C.SideObjectives.names)do if name=='Lidar Station' or name=='SEAF Artillery' then avoid[row]='exclude' end end
local op
for _,o in ipairs(C.board_of(C.case.seed))do
    if o.row<30 and o.row~=preserved and #o.missions>=3 and o.missions[1][4] and (not op or o.difficulty>op.difficulty)then op=o end
end
local mode=arg[2] or 'both'
local kinds,rules={},{}
for i=1,3 do
    local m=op.missions[i];kinds[i]=m[1]
    rules[m[1]]={tags=mode~='objectives' and m[4] and m[4][1] and {[m[4][1]]='accept'} or nil,
        objectives=mode~='tags' and avoid or nil}
end
local d=op.difficulty
t0=clock()
local paths=assert(P.shared_paths(solver.operations,d,kinds,rules))
local t_paths=clock()-t0
local alts,steps_with={},0
for _,path in ipairs(paths)do
    for _,s in ipairs(path.constraints)do
        if s.mission then
            local n=s.mission.alternatives and #s.mission.alternatives or 1
            alts[#alts+1]=n
            local draws=0
            for _,a in ipairs(s.mission.alternatives or {s.mission})do for _ in pairs(a.draws)do draws=draws+1 end end
            steps_with=steps_with+draws
        end
    end
end
print(string.format('request: %s rules, difficulty %d, kinds %s',mode,d,table.concat(kinds,',')))
print(string.format('set-up: inputs %.0f ms (all difficulties, offline), paths %.0f ms; %d paths; alternatives per mission step: %s; %d interval checks in all',
    t_inputs*1000,t_paths*1000,#paths,table.concat(alts,','),steps_with))
for i,path in ipairs(paths)do
    local root=Chain.plan(path)
    print(string.format('  path %d p=%.3g root=%s position=%s share=%.4f',i,path.probability,root and root.kind or 'none',
        root and tostring(root.position) or '-',root and (root.hi-root.lo+1)/2^32 or 1))
end
local rows={}
for r=(d-1)*3,d*3-1 do if r~=preserved then local _,sp=Chain.positions(r,preserved);rows[#rows+1]={row=r,seed_position=sp}end end
local state=11
local chain=Chain.new({paths=paths,rows=rows,planet=C.planet,random=function()state=(state*1103515245+12345)%4294967296;return state end})
-- Walk a fixed number of steps.
local limit=tonumber(arg[3]) or 2000000
t0=clock()
local candidates=0
while chain.steps<limit do
    local seed,done=chain.next(4096)
    if seed then candidates=candidates+1 elseif done then break end
end
local t_walk=clock()-t0
print(string.format('walk: %d steps in %.2f s = %.0f steps/s; %d candidates; %.1f ms per 4096-step budget',
    chain.steps,t_walk,chain.steps/t_walk,candidates,4096/(chain.steps/t_walk)*1000))
-- Prediction cost of one candidate's board, with tags and objectives, for comparison.
t0=clock()
for i=1,50 do C.board_of(i*7919)end
print(string.format('one predicted board with tags and objectives: %.1f ms',(clock()-t0)/50*1000))
