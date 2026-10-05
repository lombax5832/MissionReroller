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
    local mission_root

    -- A mission constraint compiled once into a decision tree in flat
    -- arrays, so the check the walk runs on every solution is numeric loops
    -- LuaJIT compiles: a recursive check over pairs() fell back to the
    -- interpreter, and the alternatives of excluded side objectives (80 per
    -- mission, every combination of a few intervals at each draw) took half
    -- the walk. Alternatives share prefixes of (draw position, interval)
    -- steps, in position order; a draw's output is computed once per
    -- mission seed; environment conditions are checked where an
    -- alternative ends. Walked depth first with an explicit stack.
    local function compile(mission)
        local list=mission.alternatives or {mission}
        local nodes={{edges={},ends={}}}
        for _,alternative in ipairs(list)do
            local steps={}
            for q,r in pairs(alternative.draws)do steps[#steps+1]={q,r[1],r[2]}end
            table.sort(steps,function(x,y)return x[1]<y[1] or (x[1]==y[1] and x[2]<y[2])end)
            local node=nodes[1]
            for _,s in ipairs(steps)do
                local found
                for _,e in ipairs(node.edges)do
                    if e[1]==s[1] and e[2]==s[2] and e[3]==s[3]then found=e;break end
                end
                if not found then
                    nodes[#nodes+1]={edges={},ends={}}
                    found={s[1],s[2],s[3],#nodes};node.edges[#node.edges+1]=found
                end
                node=nodes[found[4]]
            end
            node.ends[#node.ends+1]=alternative.mods
        end
        -- Flat arrays: a node's edges and its ends (each a list of mods).
        local slot_of,pos={},{}
        local efirst,elast,eslot,elo,ehi,echild={},{},{},{},{},{}
        local accept,sfirst,slast,mfirst,mlast,mmod,mlo,mhi={},{},{},{},{},{},{},{}
        local e,set,k=0,0,0
        for i,node in ipairs(nodes)do
            efirst[i]=e+1
            for _,edge in ipairs(node.edges)do
                local s=slot_of[edge[1]]
                if not s then s=#pos+1;pos[s]=edge[1];slot_of[edge[1]]=s end
                e=e+1;eslot[e],elo[e],ehi[e],echild[e]=s,edge[2],edge[3],edge[4]
            end
            elast[i]=e
            accept[i]=false
            sfirst[i]=set+1
            for _,mods in ipairs(node.ends)do
                if #mods==0 then accept[i]=true end
                set=set+1;mfirst[set]=k+1
                for _,mod in ipairs(mods)do k=k+1;mmod[k],mlo[k],mhi[k]=mod[1],mod[2],mod[3]end
                mlast[set]=k
            end
            slast[i]=set
        end
        local cache,stamp,generation,stack={},{},0,{}
        for s=1,#pos do cache[s],stamp[s]=0,0 end
        return function(m)
            generation=generation+1
            local state1
            local sp=1;stack[1]=1
            while sp>0 do
                local node=stack[sp];sp=sp-1
                if accept[node]then return true end
                for j=sfirst[node],slast[node]do
                    local ok=true
                    for x=mfirst[j],mlast[j]do
                        state1=state1 or A1*(0ULL+m)+C1
                        local v=tonumber(state1%mmod[x])
                        if v<mlo[x] or v>mhi[x]then ok=false;break end
                    end
                    if ok then return true end
                end
                for x=efirst[node],elast[node]do
                    local s=eslot[x]
                    local o
                    if stamp[s]==generation then o=cache[s]
                    else o=output(m,pos[s]);cache[s],stamp[s]=o,generation end
                    if o>=elo[x] and o<=ehi[x]then sp=sp+1;stack[sp]=echild[x]end
                end
            end
            return false
        end
    end
    local compiled=setmetatable({},{__mode='k'})
    local function checker(mission)
        local check=compiled[mission]
        if not check then check=compile(mission);compiled[mission]=check end
        return check
    end
    local function mission_ok(m,mission)return checker(mission)(m)end
    -- Every constraint of a path on the operation seed y.
    local function path_ok(y,path)
        for _,s in ipairs(path.constraints)do
            local o=output(y,s.position)
            if s.kind=='mission' then
                if s.lo then
                    local k=output((o+y)%M32,1)
                    if k<s.lo or k>s.hi then return false end
                end
                if s.mission and not checker(s.mission)(o)then return false end
            elseif o<s.lo or o>s.hi then return false end
        end
        return true
    end
    R.mission_ok,R.path_ok=mission_ok,path_ok

    -- The probability of a mission constraint.
    local function mission_mass(mission)
        if mission.alternatives then
            local sum=0
            for _,alternative in ipairs(mission.alternatives)do sum=sum+mission_mass(alternative)end
            return sum
        end
        local p=1
        for _,d in pairs(mission.draws)do p=p*(d[2]-d[1]+1)/M32 end
        for _,mod in ipairs(mission.mods)do p=p*(mod[3]-mod[2]+1)/mod[1]end
        return p
    end
    -- A mission's kind draw is the first output of m + y, m the mission
    -- seed drawn from y: the high half of A1*(m+y)+C1, which is the high
    -- halves of A1*m+C1 and A1*y+C1 added, minus C1, minus A1's low half
    -- when m+y wraps. So kind = t + c + delta (mod 2^32), t the mission
    -- seed's first draw (a tag or objective draw), c the operation's first
    -- draw (template and first category), delta one of six values: a carry
    -- of 0, 1 or 2 from the low halves, times wrapping or not.
    local DELTAS={}
    do
        local minus=0ULL-C1
        local high=tonumber(bit.rshift(minus,32))
        local u=tonumber(bit.band(minus,0xffffffffULL))/M32
        local low_a=tonumber(bit.band(A1,0xffffffffULL))
        local carry={(1-u)^2/2,0,u^2/2}
        carry[2]=1-carry[1]-carry[3]
        for e=0,2 do
            for w=0,1 do DELTAS[#DELTAS+1]={(high+e-w*low_a)%M32,carry[e+1]/2}end
        end
    end
    R.DELTAS=DELTAS
    -- Length of [lo, hi] inside the cyclic interval of `width` values from start.
    local function cyclic_overlap(lo,hi,start,width)
        local function plain(a,b)
            local l,h=math.max(lo,a),math.min(hi,b)
            return h>=l and h-l+1 or 0
        end
        local stop=start+width-1
        if stop<M32 then return plain(start,stop)end
        return plain(start,M32-1)+plain(0,stop-M32)
    end
    local SAMPLES=256
    -- A linked mission's share of mission seeds at each of SAMPLES values
    -- of c in [clo, chi]: the kind draw in [klo, khi] and the mission
    -- constraint met. checkpoint() is called every 16 values.
    local linked_cache=setmetatable({},{__mode='k'})
    local function linked(mission,klo,khi,clo,chi,checkpoint)
        local list=mission.alternatives or {mission}
        local by=linked_cache[list]
        if not by then by={};linked_cache[list]=by end
        local key=klo..':'..khi..':'..clo..':'..chi
        if by[key]then return by[key]end
        -- Alternatives grouped by their first-draw interval, with the
        -- probability of everything else they require.
        local groups,order={},{}
        for _,a in ipairs(list)do
            local d=a.draws[1]
            local tlo,thi=d and d[1] or 0,d and d[2] or M32-1
            local p=1
            for q,r in pairs(a.draws)do if q~=1 then p=p*(r[2]-r[1]+1)/M32 end end
            for _,mod in ipairs(a.mods)do p=p*(mod[3]-mod[2]+1)/mod[1]end
            local g=tlo..':'..thi
            if not groups[g]then groups[g]={tlo,thi,0};order[#order+1]=groups[g]end
            groups[g][3]=groups[g][3]+p
        end
        local width=khi-klo+1
        local values={}
        local step=(chi-clo+1)/SAMPLES
        for i=1,SAMPLES do
            if i%16==0 then checkpoint()end
            local c=math.floor(clo+(i-0.5)*step)
            local sum=0
            for _,g in ipairs(order)do
                local hit=0
                for _,d in ipairs(DELTAS)do
                    -- t with t + c + delta in [klo, khi].
                    hit=hit+d[2]*cyclic_overlap(g[1],g[2],(klo-c-d[1])%M32,width)
                end
                sum=sum+g[3]*hit/M32
            end
            values[i]=sum
        end
        by[key]=values
        return values
    end
    -- The probability of a path on a random operation seed: constraints on
    -- the same draw intersect, and missions whose kind draw and first
    -- mission draw are both constrained are integrated over c.
    -- checkpoint, optional, is called often while it works.
    function R.mass(path,checkpoint)
        checkpoint=checkpoint or function()end
        local at,missions={},{}
        for _,s in ipairs(path.constraints)do
            if s.kind=='mission' then missions[#missions+1]=s
            else
                local r=at[s.position]
                if r then at[s.position]={math.max(r[1],s.lo),math.min(r[2],s.hi)}
                else at[s.position]={s.lo,s.hi}end
            end
        end
        local p=1
        for position,r in pairs(at)do
            if r[2]<r[1]then return 0 end
            if position~=1 then p=p*(r[2]-r[1]+1)/M32 end
        end
        local c=at[1] or {0,M32-1}
        local curves={}
        for _,s in ipairs(missions)do
            local both=false
            if s.lo and s.mission then
                for _,a in ipairs(s.mission.alternatives or {s.mission})do if a.draws[1]then both=true;break end end
            end
            if both then curves[#curves+1]=linked(s.mission,s.lo,s.hi,c[1],c[2],checkpoint)
            else
                p=p*(s.lo and (s.hi-s.lo+1)/M32 or 1)*(s.mission and mission_mass(s.mission) or 1)
            end
        end
        local share=(c[2]-c[1]+1)/M32
        if #curves==0 then return p*share end
        local sum=0
        for i=1,SAMPLES do
            local v=1
            for _,curve in ipairs(curves)do v=v*curve[i]end
            sum=sum+v
        end
        return p*share*sum/SAMPLES
    end

    -- The mission-stream draw to walk for a mission constraint: the
    -- narrowest one every alternative constrains (the hull of their
    -- intervals), and the share of its solutions that pass the rest; nil
    -- when no draw is common to all.
    function mission_root(mission)
        local list=mission.alternatives or {mission}
        local hull
        for i,alternative in ipairs(list)do
            local next_hull={}
            for q,d in pairs(alternative.draws)do
                if i==1 then next_hull[q]={d[1],d[2]}
                elseif hull[q]then next_hull[q]={math.min(hull[q][1],d[1]),math.max(hull[q][2],d[2])}end
            end
            hull=next_hull
        end
        local p,r
        for q,d in pairs(hull or {})do
            if not r or d[2]-d[1]<r[2]-r[1] or (d[2]-d[1]==r[2]-r[1] and q<p)then p,r=q,d end
        end
        if not p then return nil end
        return p,r,math.min(1,mission_mass(mission)/((r[2]-r[1]+1)/M32))
    end

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
            elseif s.mission then
                local p,r,rest=mission_root(s.mission)
                -- Root solutions cost one cheap check; survivors cost an inversion.
                if p then option,c={kind='mission',step=n,position=p,lo=r[1],hi=r[2]},(r[2]-r[1]+1)*(1+8*rest)end
            end
            if option and (not cost or c<cost)then best,cost=option,c end
        end
        return best
    end

    -- A job's yield: it walks the solutions of its root draw (share r of
    -- all values) and finds on average p s / r candidates per step, p its
    -- path's probability, s its row's share (an accept check, 1 without).
    local function yield(path,root,share)
        return (path.probability or 1)*(share or 1)/(root and (root.hi-root.lo+1)/M32 or 1)
    end
    -- Jobs take turns of `quantum` steps by yield: the jobs of the highest
    -- yield (the tier: within 1% of the best, such as one path's rows)
    -- take turns, but each EVERY-th turn goes to the other jobs in turn,
    -- by yield. Yields differ by up to 12 times among a request's jobs, and
    -- equal turns for all averaged them; turns among the tier and the
    -- round-robin share hedge against a job whose solutions come in sparse
    -- clusters (docs/SEED_SOLVER_RESEARCH.md, Scheduling jobs by yield).
    local EVERY,TIER=10,0.99
    -- Job indices (1-based, paths outer, rows inner) by decreasing yield.
    local function by_yield(yields)
        local order={}
        for i=1,#yields do order[i]=i end
        table.sort(order,function(a,b)return yields[a]>yields[b] or (yields[a]==yields[b] and a<b)end)
        return order
    end
    -- How many of the sorted yields form the tier.
    local function tier(sorted)
        local k=1
        while sorted[k+1] and sorted[k+1]>=TIER*sorted[1] do k=k+1 end
        return k
    end

    -- The walk steps expected before the first candidate, the jobs (each
    -- path for each row, `shares` the rows' shares or their count) taking
    -- turns as R.new runs them. The schedule repeats every EVERY turns
    -- per job outside the tier (the tier's yields are all but equal); a
    -- Poisson wait is summed over one period of it.
    function R.expected_steps(paths,shares,quantum)
        if type(shares)=='number' then
            local n=shares;shares={}
            for i=1,n do shares[i]=1 end
        end
        local yields={}
        for _,path in ipairs(paths)do
            local y=yield(path,R.plan(path))
            for _,s in ipairs(shares)do yields[#yields+1]=y*s end
        end
        if #yields==0 then return math.huge end
        local sorted={}
        for k,i in ipairs(by_yield(yields))do sorted[k]=yields[i]end
        local top=tier(sorted)
        local spent,alive=0,1
        local function turn(rate)
            if rate>0 then
                local none=math.exp(-rate*quantum)
                spent=spent+alive*(1-none)/rate
                alive=alive*none
            else spent=spent+alive*quantum end
        end
        if top==#sorted then
            for k=1,top do turn(sorted[k])end
        else
            local at=0
            for t=1,EVERY*(#sorted-top)do
                if t%EVERY==0 then turn(sorted[top+t/EVERY])
                else at=at%top+1;turn(sorted[at])end
            end
        end
        if alive>=1 then return math.huge end
        return spent/(1-alive)
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

    -- One job: a path solved for one row, from a random start s0. accept,
    -- when given, is a last check on a candidate (seed, row), such as the
    -- Day / Night filter's ID check (src/seed_solver_time.lua).
    local function job(path,row,seed_position,planet,s0,others,paths,accept)
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
                if others_ok(xs[i])then
                    local seed=(xs[i]-planet)%M32
                    if not accept or accept(seed,row)then count=count+1;pending[count]=seed end
                end
            end
        end
        local walk,step,invert_m,check_root
        if not root then
            walk={start=function(s)return s,nil end,advance=function(s)return s+1,nil end}
        else
            walk=Math.walk(root.position,root.lo,root.hi)
            if root.kind=='mission' then
                step=path.constraints[root.step]
                check_root=checker(step.mission)
                invert_m=Math.inverter(step.position)
            end
        end
        -- The walk covers [s0, 2^32), then [0, s0).
        local phase,limit=1,M32
        local s,off=walk.start(s0)
        local j={steps=0,path=path,root=root}
        -- Up to `budget` walk steps; returns a candidate seed (then nil and
        -- its row), or nil when the budget is spent (done=false) or the job
        -- is exhausted (done=true).
        function j.next(budget)
            while true do
                if count>0 then
                    local seed=pending[count];pending[count]=nil;count=count-1
                    return seed,nil,row
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
                    elseif check_root(v)then
                        local n=invert_m(v,ys)
                        for i=1,n do if path_ok(ys[i],path)then campaign(ys[i])end end
                    end
                end
            end
        end
        return j
    end

    -- spec: {paths, rows={{row, seed_position, share=optional share of
    -- seeds the accept check passes for the row}}, others={seed positions
    -- of rows an "every operation" filter checks}, planet, random=function()
    -- returning a 32-bit start, accept=optional function(seed, row),
    -- checkpoint=optional function called before each job is set up}. Jobs
    -- take turns of `quantum` walk steps, by yield (EVERY and TIER above).
    function R.new(spec)
        local created,yields={},{}
        local checkpoint=spec.checkpoint or function()end
        for _,path in ipairs(spec.paths)do
            for _,row in ipairs(spec.rows)do
                checkpoint()
                local j=job(path,row.row,row.seed_position,spec.planet,spec.random(),spec.others or {},spec.paths,
                    spec.accept)
                created[#created+1]=j;yields[#yields+1]=yield(path,j.root,row.share)
            end
        end
        local jobs={}
        for k,i in ipairs(by_yield(yields))do jobs[k]=created[i];created[i].yield=yields[i]end
        local quantum=spec.quantum or 4096
        -- The job taking the turn (an index in jobs, best first), the steps
        -- left in it, the turns started, and the last tier job and other
        -- job given one.
        local turn,left,turns,at,other=nil,0,0,0,0
        local chain={jobs=jobs,steps=0}
        local sorted={}
        -- Up to `budget` walk steps in all; a candidate seed, then nil and its
        -- row (for a check made outside the chain, such as a worker VM's
        -- caller applying accept), or nil with done=true when every job is
        -- exhausted.
        function chain.next(budget)
            while #jobs>0 and budget>0 do
                if not turn then
                    turns,left=turns+1,quantum
                    for k,j in ipairs(jobs)do sorted[k]=j.yield end
                    for k=#jobs+1,#sorted do sorted[k]=nil end
                    local top=tier(sorted)
                    if top<#jobs and turns%EVERY==0 then
                        other=other+1
                        if other<=top or other>#jobs then other=top+1 end
                        turn=other
                    else
                        at=at+1
                        if at>top then at=1 end
                        turn=at
                    end
                end
                local j=jobs[turn]
                local before=j.steps
                local seed,done,row=j.next(math.min(budget,left))
                local spent=j.steps-before
                budget,left,chain.steps=budget-spent,left-spent,chain.steps+spent
                if seed then return seed,nil,row end
                if done then
                    table.remove(jobs,turn)
                    if other>=turn then other=other-1 end
                    if at>=turn then at=at-1 end
                    turn=nil
                elseif left<=0 then turn=nil end
            end
            return nil,#jobs==0
        end
        return chain
    end
    return R
end
