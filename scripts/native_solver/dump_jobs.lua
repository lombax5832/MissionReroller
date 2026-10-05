-- Usage: luajit scripts/native_solver/dump_jobs.lua <capture.lua> <mode> <steps> <jobs.txt>
-- Research only (docs/NATIVE_SOLVER_RESEARCH.md). Builds the request of
-- scripts/profile_seed_solver.lua (mode: both, objectives or tags), writes
-- every (path, row) job of src/seed_solver_chain.lua as numbers for
-- solver_bench.c, then runs each job `steps` walk steps in LuaJIT from the
-- same start and writes its candidates and time, so the C port can be
-- checked and timed against it.
local here=(arg[0]:match('^(.*[/\\])') or '')..'../../'
local root=here..'src'
local C=dofile(here..'scripts/seed_solver_capture.lua')(here..'scripts/',root,arg[1])
local H=C.H
local mode,limit,out_path=arg[2] or 'both',tonumber(arg[3]) or 2000000,assert(arg[4],'jobs.txt')
local solver,identity=C.solver_inputs()
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
local kinds,rules={},{}
for i=1,3 do
    local m=op.missions[i];kinds[i]=m[1]
    rules[m[1]]={tags=mode~='objectives' and m[4] and m[4][1] and {[m[4][1]]='accept'} or nil,
        objectives=mode~='tags' and avoid or nil}
end
local d=op.difficulty
local paths=assert(P.shared_paths(solver.operations,d,kinds,rules))
local rows={}
for r=(d-1)*3,d*3-1 do if r~=preserved then local _,sp=Chain.positions(r,preserved);rows[#rows+1]={row=r,seed_position=sp}end end

-- The decision tree of seed_solver_chain.lua compile(), as numbers.
local function tree(mission,w)
    local list=mission.alternatives or {mission}
    local nodes={{edges={},ends={}}}
    for _,alternative in ipairs(list)do
        local steps={}
        for q,r in pairs(alternative.draws)do steps[#steps+1]={q,r[1],r[2]}end
        table.sort(steps,function(x,y)return x[1]<y[1] or (x[1]==y[1] and x[2]<y[2])end)
        local node=nodes[1]
        for _,s in ipairs(steps)do
            local found
            for _,e in ipairs(node.edges)do if e[1]==s[1] and e[2]==s[2] and e[3]==s[3]then found=e;break end end
            if not found then
                nodes[#nodes+1]={edges={},ends={}}
                found={s[1],s[2],s[3],#nodes};node.edges[#node.edges+1]=found
            end
            node=nodes[found[4]]
        end
        node.ends[#node.ends+1]=alternative.mods
    end
    w(#nodes)
    for _,node in ipairs(nodes)do
        w(#node.edges)
        for _,e in ipairs(node.edges)do w(e[1],e[2],e[3],e[4]-1)end
        w(#node.ends)
        for _,mods in ipairs(node.ends)do
            w(#mods)
            for _,m in ipairs(mods)do w(m[1],m[2],m[3])end
        end
    end
end

local f=assert(io.open(out_path,'w'))
local function w(...)
    for i=1,select('#',...)do f:write(string.format('%.0f ',select(i,...)))end
    f:write('\n')
end
local KIND={stream=1,mission=2}
local state=11
local function random()state=(state*1103515245+12345)%4294967296;return state end
w(C.planet,#paths*#rows,limit)
local total_steps,total_time,total_candidates=0,0,0
for _,path in ipairs(paths)do
    for _,row in ipairs(rows)do
        local s0=random()
        local chain=Chain.new({paths={path},rows={row},planet=C.planet,random=function()return s0 end})
        local job=chain.jobs[1]
        local r=job.root
        w(s0,row.seed_position,r and KIND[r.kind] or 0,r and r.position or 0,r and r.lo or 0,r and r.hi or 0,
            r and r.step or 0)
        w(#path.constraints)
        for _,s in ipairs(path.constraints)do
            w(s.kind=='mission' and 1 or 0,s.position,s.lo and 1 or 0,s.lo or 0,s.hi or 0,s.mission and 1 or 0)
            if s.mission then tree(s.mission,w)end
        end
        -- The Lua job over the same steps.
        local seeds={}
        local t0=os.clock()
        while job.steps<limit do
            local seed,done=job.next(math.min(4096,limit-job.steps))
            if seed then seeds[#seeds+1]=seed elseif done then break end
        end
        local t=os.clock()-t0
        total_steps,total_time,total_candidates=total_steps+job.steps,total_time+t,total_candidates+#seeds
        w(job.steps,#seeds)
        if #seeds>0 then w(unpack(seeds))end
        f:write(string.format('# lua_seconds %.6f\n',t))
    end
end
f:close()
print(string.format('lua: %s, %d jobs, %d steps in %.3f s = %.0f steps/s, %d candidates',mode,#paths*#rows,
    total_steps,total_time,total_steps/total_time,total_candidates))
