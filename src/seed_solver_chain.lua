-- Candidate campaign seeds for a filter, solved by chained 1-D inversions
-- (docs/SEED_SOLVER_RESEARCH.md; port of scripts/seed_chain.py). For each
-- draw path (src/seed_solver_paths.lua) and generated row:
-- 1. walk every mission seed m whose most selective draw lands in its
--    interval, from a random start, checking the mission's other draws;
-- 2. invert m to the operation seeds y that draw it, checking the path on y;
-- 3. invert y to the campaign seeds that give it to the row, checking the
--    other rows of an "every operation" filter against the paths.
-- A path with no mission-seed draw is walked over y instead. The caller
-- predicts each candidate's board and keeps the seeds that match; the
-- chain only discards seeds that cannot. Work is counted in walk steps, so
-- the caller can stop it inside a frame budget and resume it.
return function(Math)
    local bit=require('bit')
    local A1,C1=Math.A[1],Math.C[1]
    local output=Math.output
    local M32=2^32
    local R={}

    local function mission_ok(m,mission)
        for p,r in pairs(mission.draws)do
            local o=output(m,p)
            if o<r[1] or o>r[2]then return false end
        end
        if #mission.mods>0 then
            local state1=A1*(0ULL+m)+C1
            for _,mod in ipairs(mission.mods)do
                local v=tonumber(state1%mod[1])
                if v<mod[2] or v>mod[3]then return false end
            end
        end
        return true
    end
    -- Every constraint of a path on the operation seed y.
    local function path_ok(y,path)
        for _,s in ipairs(path.constraints)do
            local o=output(y,s.position)
            if s.kind=='mission' then
                if s.lo then
                    local k=output((o+y)%M32,1)
                    if k<s.lo or k>s.hi then return false end
                end
                if s.mission and not mission_ok(o,s.mission)then return false end
            elseif o<s.lo or o>s.hi then return false end
        end
        return true
    end
    R.mission_ok,R.path_ok=mission_ok,path_ok

    -- The root of a path: the draw leaving the fewest candidates to invert.
    -- {kind='mission', step=n, position, lo, hi} walks mission seeds,
    -- {kind='stream', position, lo, hi} operation seeds; nil scans every y.
    function R.plan(path)
        local best,cost
        for n,s in ipairs(path.constraints)do
            local option,c
            if s.kind~='mission' then
                -- Every root solution is a y to check: weight it like an inversion.
                option,c={kind='stream',position=s.position,lo=s.lo,hi=s.hi},(s.hi-s.lo+1)*8
            elseif s.mission and next(s.mission.draws)then
                local p,r
                for q,d in pairs(s.mission.draws)do
                    if not r or d[2]-d[1]<r[2]-r[1] or (d[2]-d[1]==r[2]-r[1] and q<p)then p,r=q,d end
                end
                local rest=1
                for q,d in pairs(s.mission.draws)do if q~=p then rest=rest*(d[2]-d[1]+1)/M32 end end
                for _,mod in ipairs(s.mission.mods)do rest=rest*(mod[3]-mod[2]+1)/mod[1]end
                -- Root solutions cost one cheap check; survivors cost an inversion.
                option,c={kind='mission',step=n,position=p,lo=r[1],hi=r[2]},(r[2]-r[1]+1)*(1+8*rest)
            end
            if option and (not cost or c<cost)then best,cost=option,c end
        end
        return best
    end

    -- Campaign-stream positions of a generated row's ID and seed draws: two
    -- draws per generated row before it (operation_identity.lua), the
    -- preserved row drawing none; no ID fallback while the pool outnumbers
    -- the rows.
    function R.positions(row,preserved)
        local before=0
        for r=0,row-1 do if r~=preserved then before=before+1 end end
        return 2*before+1,2*before+2
    end

    -- One job: a path solved for one row, from a random start s0.
    local function job(path,seed_position,planet,s0,others,paths)
        local root=R.plan(path)
        local pending,count={},0
        local invert_seed=Math.inverter(seed_position)
        local ys,xs={},{}
        local function others_ok(start)
            for _,at in ipairs(others)do
                local y=output(start,at)
                local any=false
                for _,p in ipairs(paths)do if path_ok(y,p)then any=true;break end end
                if not any then return false end
            end
            return true
        end
        local function campaign(y)
            local n=invert_seed(y,xs)
            for i=1,n do
                if others_ok(xs[i])then count=count+1;pending[count]=(xs[i]-planet)%M32 end
            end
        end
        local walk,step,invert_m
        if not root then
            walk={start=function(s)return s,nil end,advance=function(s)return s+1,nil end}
        else
            walk=Math.walk(root.position,root.lo,root.hi)
            if root.kind=='mission' then
                step=path.constraints[root.step]
                invert_m=Math.inverter(step.position)
            end
        end
        -- The walk covers [s0, 2^32), then [0, s0).
        local phase,limit=1,M32
        local s,off=walk.start(s0)
        local j={steps=0,path=path,root=root}
        -- Up to `budget` walk steps; returns a candidate seed, or nil when the
        -- budget is spent (done=false) or the job is exhausted (done=true).
        function j.next(budget)
            while true do
                if count>0 then
                    local seed=pending[count];pending[count]=nil;count=count-1
                    return seed
                end
                if budget<=0 then return nil,false end
                if not s or s>=limit then
                    if phase==2 or s0==0 then return nil,true end
                    phase,limit=2,s0
                    s,off=walk.start(0)
                else
                    local v=s
                    s,off=walk.advance(s,off)
                    budget=budget-1;j.steps=j.steps+1
                    if not root or root.kind=='stream' then
                        if path_ok(v,path)then campaign(v)end
                    elseif mission_ok(v,step.mission)then
                        local n=invert_m(v,ys)
                        for i=1,n do if path_ok(ys[i],path)then campaign(ys[i])end end
                    end
                end
            end
        end
        return j
    end

    -- spec: {paths, rows={{row, seed_position}}, others={seed positions of
    -- rows an "every operation" filter checks}, planet, random=function()
    -- returning a 32-bit start}. Jobs take turns of `quantum` walk steps.
    function R.new(spec)
        local jobs={}
        for _,path in ipairs(spec.paths)do
            for _,row in ipairs(spec.rows)do
                jobs[#jobs+1]=job(path,row.seed_position,spec.planet,spec.random(),spec.others or {},spec.paths)
            end
        end
        local quantum=spec.quantum or 4096
        local turn,left=1,quantum
        local chain={jobs=jobs,steps=0}
        -- Up to `budget` walk steps in all; a candidate seed, or nil with
        -- done=true when every job is exhausted.
        function chain.next(budget)
            while #jobs>0 and budget>0 do
                if turn>#jobs then turn=1 end
                local j=jobs[turn]
                local before=j.steps
                local seed,done=j.next(math.min(budget,left))
                local spent=j.steps-before
                budget,left,chain.steps=budget-spent,left-spent,chain.steps+spent
                if seed then return seed end
                if done then table.remove(jobs,turn);left=quantum
                elseif left<=0 then turn,left=turn+1,quantum end
            end
            return nil,#jobs==0
        end
        return chain
    end
    return R
end
