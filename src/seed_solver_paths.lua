-- Draw paths for solving campaign seeds (docs/SEED_SOLVER_RESEARCH.md; port
-- of scripts/seed_solver.py Planet.paths and its mission-seed walks). A path
-- lists, for one operation seed y, the intervals its draws must land in for
-- the operation to deliver every required mission kind with its rules:
--   {kind='final', position=1, lo, hi}     the finalizer's template draw
--   {kind='direct', position, lo, hi}      a composition draw (category)
--   {kind='mission', position, lo, hi, mission}
--       the position-th composition draw is a mission seed m; the kind draw
--       starts at (m + y) mod 2^32 (lo, hi nil when the kind is forced), and
--       mission = {draws={[p]={lo,hi}}, mods={{modulus,lo,hi}}} constrains
--       the stream started at m (enemy tags, side objectives) and the
--       environment's state m*A+C modulo its weight totals.
-- Template, category and kind draws run the real choice modules on a stub
-- generator that returns one output; enemy-tag and side-objective draws are
-- walked step by step (ports of constellation_prediction.lua and
-- side_objective_prediction.lua, checked against them by
-- tests/test_seed_solver_paths.lua). Every choice is monotone in its output,
-- so each outcome owns one interval, found by bisection.
local ffi,bit=require('ffi'),require('bit')
local single=ffi.new('float[1]')
local function f(n)single[0]=n;return tonumber(single[0])end
local SCALE=f(1/4294967296)
local FLOOR=f(1e-6)
local M32=2^32
local LAST=M32-1
local EXTRA_OBJECTIVE=0x68bfbb59 -- side_objective_prediction.lua: the context's extra tactical entry

-- Called before each partition, so a caller inside a coroutine can yield
-- within its frame budget (R.new's planet.checkpoint); one search at a time.
local checkpoint=function()end
-- {{key, value, first, last}} for a choice monotone in the output: choice(o)
-- returns a key (never nil) and a value.
local function partition(choice)
    checkpoint()
    local parts,seen,at={},{},0
    while at<=LAST do
        local key,value=choice(at)
        assert(not seen[key],'choice is not monotone in the output')
        seen[key]=true
        local a,b=at,LAST
        while a<b do
            local mid=math.floor((a+b+1)/2)
            if (choice(mid))==key then a=mid else b=mid-1 end
        end
        parts[#parts+1]={key=key,value=value,first=at,last=a}
        at=a+1
    end
    return parts
end
-- The 1-based item a float32 weighted draw picks for output o, or nil.
local function weighted(o,list,field)
    local total=0
    for i=1,#list do total=f(total+f(list[i][field]))end
    local threshold=f(f(f(o)*SCALE)*total)
    local acc=0
    for i=1,#list do
        acc=f(acc+f(list[i][field]))
        if threshold<=acc then return i end
    end
end
local function copy(t)local r={};for k,v in pairs(t)do r[k]=v end;return r end
local function copies(list)local r={};for i,e in ipairs(list)do r[i]=copy(e)end;return r end
-- A canonical text of a value: equal values, equal text.
local function canon(v)
    if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v)end
    local keys={}
    for k in pairs(v)do keys[#keys+1]=k end
    table.sort(keys,function(a,b)
        if type(a)==type(b)then return a<b end
        return type(a)<type(b)
    end)
    local parts={}
    for _,k in ipairs(keys)do parts[#parts+1]=canon(k)..'='..canon(v[k])end
    return '{'..table.concat(parts,',')..'}'
end
local function merge(a,b)
    local out=copy(a)
    for p,r in pairs(b)do
        local lo,hi=r[1],r[2]
        if out[p]then
            lo,hi=math.max(lo,out[p][1]),math.min(hi,out[p][2])
            if lo>hi then return nil end
        end
        out[p]={lo,hi}
    end
    return out
end
local function mass(draws,mods)
    local p=1
    for _,r in pairs(draws)do p=p*(r[2]-r[1]+1)/M32 end
    for _,m in ipairs(mods)do p=p*(m[3]-m[2]+1)/m[1]end
    return p
end

-- Enemy tags (constellation_prediction.lua R.base and R.resolve) ----------
local function find(tags,tag)for i=1,#tags do if tags[i]==tag then return i end end end
local function add_tag(tags,tag)if not find(tags,tag) and #tags<16 then tags[#tags+1]=tag end end
local function tag_pool(settings,initial)
    local tags={}
    for _,t in ipairs(initial)do add_tag(tags,t)end
    local empty,pool,total=#tags==0,{},0
    for _,row in ipairs(settings.candidates)do
        if row.id~=0 and (not row.only_when_empty or empty)then pool[#pool+1]=row;total=f(total+row.weight)end
    end
    return tags,pool,total
end
local function finish_tags(tags,settings,kind,disabled)
    tags={unpack(tags)}
    if settings.fallback~=0 and not find(tags,settings.fallback)then
        local blocked=false
        for _,blocker in ipairs(settings.blockers)do
            if blocker==0 then break end
            if find(tags,blocker)then blocked=true;break end
        end
        if not blocked then add_tag(tags,settings.fallback)end
    end
    if kind.horde then add_tag(tags,1)end
    for _,tag in ipairs(kind.exclusions)do
        local i=find(tags,tag)
        if i then tags[i]=tags[#tags];tags[#tags]=nil end
    end
    local set={}
    for _,t in ipairs(tags)do if t~=0 and not disabled[t]then set[t]=true end end
    return set
end

-- The environment pick (side_objective_inputs.lua): two picks of state1 =
-- A*m + C modulo integer weight totals.
local function ranges(table_)
    if #table_.units==0 then return nil,{{0,nil}}end
    local total,acc,out,first=0,0,{},true
    for _,u in ipairs(table_.units)do total=total+u end
    for k,u in ipairs(table_.units)do
        if u~=0 then
            local lo=first and 0 or acc+1
            acc=acc+u;first=false
            out[#out+1]={table_.indices[k],{lo,acc}}
        end
    end
    return total,out
end
local function environment_branches(info)
    local tables=info.environment
    if not tables then return {{0,{}}}end
    local out={}
    local t1,biomes=ranges(tables.biome)
    for _,b in ipairs(biomes)do
        local biome,r1=b[1],b[2]
        local inner
        for _,t in ipairs(tables.inner)do if t.biome==biome then inner=t;break end end
        local t2,picks=ranges(inner)
        for _,pick in ipairs(picks)do
            local index,r2=pick[1],pick[2]
            local mods={}
            if t1 and r1 and r1[2]-r1[1]+1<t1 then mods[#mods+1]={t1,r1[1],r1[2]}end
            if t2 and r2 and r2[2]-r2[1]+1<t2 then mods[#mods+1]={t2,r2[1],r2[2]}end
            out[#out+1]={inner.ids[index+1],mods}
        end
    end
    return out
end

-- Side objectives (side_objective_prediction.lua R.resolve), split so its
-- draws can be walked: setup() is everything before the first draw.
local function objectives(records,row_of)
    local O={}
    function O.setup(kind,difficulty,counts,context,environment)
        local mission=kind.objectives
        local pool,D=mission.pool,difficulty
        local function in_range(r)
            return (r.minimum==0 or r.minimum<=D) and (r.maximum==0 or D<=r.maximum)
        end
        local side=counts.side
        if mission.scale then side=math.floor(f(f(side)*mission.scale)+0.5)end
        local taken,primary,primary_set,lo,hi,weight={},nil,false,0,0,0
        for k,e in ipairs(pool)do
            taken[k]=0
            if e.id~=0 and e.weight>0 then
                local r=records[e.id]
                if in_range(r)then
                    if e.role==0 then
                        primary=primary or k
                        if not primary_set and e.minimum~=0 then primary_set=true end
                    end
                    taken[k]=e.minimum
                    if e.role<=1 then
                        local cap=math.min(e.maximum,r.cap)
                        lo=lo+e.minimum;hi=hi+cap
                        if e.minimum<cap then weight=f(weight+e.weight)end
                    end
                end
            end
        end
        if not primary_set and primary then taken[primary]=taken[primary]+1 end
        local extra=0
        if mission.lo<mission.hi then
            local t=f(f((D-mission.lo)%M32)/f(mission.hi-mission.lo))
            local target=math.floor(f(f(f(1-t)*f(lo))+f(f(hi)*t))+0.5)%M32
            local upper=counts.substeps>lo and counts.substeps or lo
            if target<upper then upper=target end
            extra=upper-lo
        end
        return {pool=pool,taken=taken,weight=weight,extra=extra,side=side,in_range=in_range,
            context=context,environment=environment,tactical=counts.tactical}
    end
    -- The entry one sub-step draw picks: {k, weight, cap} on a hit, {k} for
    -- the last eligible entry on a miss, nil when nothing is eligible (the
    -- draw is spent and the loop stops).
    function O.substep_pick(s,o)
        local r=f(f(f(o)*SCALE)*s.weight)
        local acc,last=0,nil
        for k,e in ipairs(s.pool)do
            if (e.role<2 or e.role>4) and e.weight>0 then
                local cap=math.min(e.maximum,records[e.id].cap)
                if s.taken[k]<cap then
                    acc=f(acc+e.weight);last=k
                    if r<=acc then return {k,e.weight,cap}end
                end
            end
        end
        return last and {last}
    end
    function O.substep_apply(s,picked)
        local k,w,cap=picked[1],picked[2],picked[3]
        s.taken[k]=s.taken[k]+1
        if w and cap<=s.taken[k]then s.weight=f(s.weight-w)end
    end
    -- The minimum entries (appended to emitted) and the draw pools by role.
    function O.emit_minimums(s,emitted)
        local env=s.environment
        local function allowed(r)
            local list=r.environments
            if list[1]==0 then return true end
            for k=1,4 do
                if list[k]==0 then return false end
                if list[k]==env then return true end
            end
            return false
        end
        local left={[3]=s.side,[2]=s.tactical,[4]=LAST}
        local pools={[3]={},[2]={},[4]={}}
        for k,e in ipairs(s.pool)do
            if e.id~=0 and e.weight>0 then
                local r=records[e.id]
                if not r.disabled and allowed(r) and s.in_range(r) and not s.context.banned[e.id]then
                    for _=1,s.taken[k]do
                        local role=e.role
                        if left[role]==nil then emitted[#emitted+1]={e.id,role}
                        elseif left[role]~=0 then left[role]=left[role]-1;emitted[#emitted+1]={e.id,role}end
                    end
                    if pools[e.role]then
                        local list=pools[e.role]
                        list[#list+1]={id=r.id,weight=e.weight,cap=math.min(e.maximum,r.cap),count=e.minimum,
                            mask=r.mask,role=e.role}
                    end
                end
            end
        end
        return left,pools
    end
    -- 1757870: drop entries at their cap or sharing a drawn mask bit, moving
    -- the last into the gap; returns the live count.
    function O.draw_step(list,n,mask)
        local k=1
        while k<=n do
            while not (n<k or (list[k].count<list[k].cap and bit.band(list[k].mask,mask)==0))do
                list[k]=list[n];n=n-1
            end
            k=k+1
        end
        return n
    end
    function O.draw_pick(list,n,o)
        local total=0
        for j=1,n do total=f(total+list[j].weight)end
        local r=f(f(f(o)*SCALE)*total)
        local acc=0
        for j=1,n do
            acc=f(acc+list[j].weight)
            if r<=acc then return j end
        end
    end
    function O.draw_apply(list,n,j,mask,remaining,emitted)
        local e=list[j]
        emitted[#emitted+1]={e.id,e.role}
        e.count=e.count+1;mask=bit.bor(mask,e.mask);remaining=remaining-1
        if e.cap<=e.count then list[j]=list[n];n=n-1 end
        return n,mask,remaining
    end
    -- The filter rows (R.set) of emitted {id, role} pairs.
    function O.rows(emitted)
        local set={}
        for _,o in ipairs(emitted)do
            if (o[2]==3 or o[2]==2) and row_of[o[1]]then set[row_of[o[1]]]=true end
        end
        return set
    end
    -- R.resolve from these steps, for tests and forward checks: {{id, role}}.
    function O.resolve(kind,difficulty,counts,context,environment,next_output)
        local out={}
        if difficulty==0 then return out end
        local s=O.setup(kind,difficulty,counts,context,environment)
        local extra=s.extra
        while extra~=0 and s.weight>FLOOR do
            local picked=O.substep_pick(s,next_output())
            if not picked then break end
            O.substep_apply(s,picked)
            extra=extra-1
        end
        local left,pools=O.emit_minimums(s,out)
        for _,role in ipairs({3,2,4})do
            local list=copies(pools[role])
            local n,mask,remaining=#list,0,left[role]
            while n>0 and remaining~=0 do
                n=O.draw_step(list,n,mask)
                local value=next_output()
                if n==0 then break end
                local j=O.draw_pick(list,n,value)
                if j then n,mask,remaining=O.draw_apply(list,n,j,mask,remaining,out)end
            end
        end
        if context.extra then out[#out+1]={EXTRA_OBJECTIVE,2}end
        return out
    end
    return O
end

-- planet: {records={[pool id]=record}, row_of={[objective id]=row},
-- disabled_tags={[tag]=true}}; choose_category is mission_category_choice.lua,
-- choose_mission mission_weighted_choice.lua and finalize
-- operation_finalization.lua, each made with the stub generators below.
return function(choose_category,make_choose_mission,make_finalize)
    local R={partition=partition,canon=canon,merge=merge}
    -- A generator that returns o, then zeros; draws counts its calls.
    local stub={draws=0,o=0}
    local function stub_rng()
        local rng={}
        function rng.next()
            stub.draws=stub.draws+1
            return stub.draws==1 and stub.o or 0
        end
        function rng.state_bytes()return string.rep('\0',8)end
        return rng
    end
    local function stubbed(o)stub.draws,stub.o=0,o;return stub_rng()end
    local choose_mission=make_choose_mission(function()return stub_rng()end)
    local finalize=make_finalize(function()return stub_rng()end)

    function R.new(planet)
        checkpoint=planet.checkpoint or function()end
        local P={}
        local O=objectives(planet.records,planet.row_of)
        P.objectives=O
        -- Forward resolution of one mission's details, for tests:
        -- tags (set, or nil without settings), objectives and environment.
        function P.tags(info,initial,seed,next_output)
            local settings=info.settings
            if not settings then return nil end
            local tags,pool,total=tag_pool(settings,initial)
            for _=1,settings.draws do
                if #pool==0 or total<=0 then break end
                local i=weighted(next_output(),pool,'weight')
                if i then add_tag(tags,pool[i].id)end
            end
            return finish_tags(tags,settings,info,planet.disabled_tags)
        end

        local function tag_paths(op,info,rule)
            if not rule or next(rule)==nil then return {{}}end
            local settings=info.settings
            if not settings then return {}end -- unresolved tags never satisfy a rule
            local tags0,pool,total=tag_pool(settings,op.initial_tags)
            local draws=(#pool>0 and total>0) and settings.draws or 0
            local parts=draws>0 and partition(function(o)
                local i=weighted(o,pool,'weight')
                return i and pool[i].id or 'none'
            end) or {}
            local wanted={}
            for t,mode in pairs(rule)do if mode~='exclude' then wanted[#wanted+1]=t end end
            local out={}
            local combo={}
            local function each(d)
                if d>draws then
                    local tags={unpack(tags0)}
                    for _,part in ipairs(combo)do if part.key~='none' then add_tag(tags,part.key)end end
                    local final=finish_tags(tags,settings,info,planet.disabled_tags)
                    for t,mode in pairs(rule)do if mode=='exclude' and final[t]then return end end
                    if #wanted>0 then
                        local any=false
                        for _,t in ipairs(wanted)do if final[t]then any=true;break end end
                        if not any then return end
                    end
                    local draws_={}
                    for i,part in ipairs(combo)do
                        if part.first~=0 or part.last~=LAST then draws_[i]={part.first,part.last}end
                    end
                    out[#out+1]=draws_
                    return
                end
                for _,part in ipairs(parts)do combo[d]=part;each(d+1)end
            end
            each(1)
            return out
        end

        -- How many draws the sub-step loop can spend (1756730).
        local function substep_counts(s)
            local counts={}
            local function walk(s,extra,spent)
                if extra==0 or s.weight<=FLOOR then counts[spent]=true;return end
                for _,part in ipairs(partition(function(o)
                    local picked=O.substep_pick(s,o)
                    if not picked then return 'none' end
                    return picked[1]..(picked[2] and ':hit' or ':miss'),picked
                end))do
                    if part.key=='none' then counts[spent+1]=true
                    else
                        local t=copy(s);t.taken=copy(s.taken)
                        O.substep_apply(t,part.value)
                        walk(t,extra-1,spent+1)
                    end
                end
            end
            walk(s,s.extra,0)
            return counts
        end
        -- How many draws one pool's loop can spend (1757870).
        local function role_counts(list,remaining)
            local counts={}
            local function walk(list,n,mask,remaining,spent)
                if remaining==0 then counts[spent]=true;return end
                list=copies(list)
                n=O.draw_step(list,n,mask)
                if n==0 then counts[spent+1]=true;return end
                for _,part in ipairs(partition(function(o)return O.draw_pick(list,n,o) or 'none' end))do
                    if part.key~='none' then
                        local l2=copies(list)
                        local n2,mask2,rem2=O.draw_apply(l2,n,part.key,mask,remaining,{})
                        if n2==0 then counts[spent+1]=true else walk(l2,n2,mask2,rem2,spent+1)end
                    end
                end
            end
            if #list>0 and remaining~=0 then walk(list,#list,0,remaining,0)else counts[0]=true end
            return counts
        end
        local function sorted_keys(set)
            local list={}
            for k in pairs(set)do list[#list+1]=k end
            table.sort(list)
            return list
        end
        local function covers(need,rows)
            for r in pairs(need)do if not rows[r]then return false end end
            return true
        end
        local function union(a,b)local r=copy(a);for k in pairs(b)do r[k]=true end;return r end
        -- Walk the side (3) then tactical (2) pools' draws until every
        -- required row is drawn.
        local function draw_walk(pools,left,roles,rows,need,position,draws,out,state)
            if covers(need,rows)then out[#out+1]=draws;return end
            if not state then
                if #roles==0 then return end -- pools exhausted without every required row
                local role=roles[1]
                local rest={unpack(roles,2)}
                local list=copies(pools[role])
                local holds=false
                local ids={}
                for _,e in ipairs(list)do ids[#ids+1]={e.id,role}end
                for r in pairs(O.rows(ids))do if need[r]then holds=true;break end end
                if not holds then
                    -- Nothing required comes from this pool: only its draw count matters.
                    for _,spent in ipairs(sorted_keys(role_counts(list,left[role])))do
                        draw_walk(pools,left,rest,rows,need,position+spent,draws,out)
                    end
                    return
                end
                if #list==0 then return draw_walk(pools,left,rest,rows,need,position,draws,out)end
                state={role=role,rest=rest,list=list,n=#list,mask=0,remaining=left[role]}
            end
            if state.remaining==0 then return draw_walk(pools,left,state.rest,rows,need,position,draws,out)end
            local list=copies(state.list)
            local n=O.draw_step(list,state.n,state.mask)
            if n==0 then -- the draw is spent and the pool ends
                return draw_walk(pools,left,state.rest,rows,need,position+1,draws,out)
            end
            for _,part in ipairs(partition(function(o)return O.draw_pick(list,n,o) or 'none' end))do
                local d=merge(draws,{[position]={part.first,part.last}})
                if part.key~='none' and d then
                    local l2=copies(list)
                    local emitted={}
                    local n2,mask2,rem2=O.draw_apply(l2,n,part.key,state.mask,state.remaining,emitted)
                    local new=union(rows,O.rows(emitted))
                    if n2==0 then draw_walk(pools,left,state.rest,new,need,position+1,d,out)
                    else
                        draw_walk(pools,left,nil,new,need,position+1,d,out,
                            {role=state.role,rest=state.rest,list=l2,n=n2,mask=mask2,remaining=rem2})
                    end
                end
            end
        end
        local function objective_paths(op,info,rule,env)
            if not rule or next(rule)==nil then return {{}}end
            local need,avoid={},{}
            for r,mode in pairs(rule)do if mode=='require' then need[r]=true elseif mode=='exclude' then avoid[r]=true end end
            local s=O.setup(info,op.difficulty,op.counts,op.context,env)
            local emitted={}
            local left,pools=O.emit_minimums(s,emitted)
            local rows=O.rows(emitted)
            for r in pairs(rows)do if avoid[r]then return {}end end -- a fixed objective is excluded
            local offered={}
            for _,role in ipairs({3,2})do for _,e in ipairs(pools[role])do offered[#offered+1]={e.id,role}end end
            if not covers(need,union(rows,O.rows(offered)))then return {}end -- never drawn here
            local out={}
            for _,count in ipairs(sorted_keys(substep_counts(s)))do
                draw_walk(pools,left,{3,2},rows,need,count+1,{},out)
            end
            return out
        end

        -- Constraint sets on one mission's seed stream satisfying rule
        -- ({tags=..., objectives=...}): {{draws, mods, probability}}.
        function P.mission_paths(op,kind,rule)
            local info=op.kind_of[kind]
            rule=rule or {}
            local tags=tag_paths(op,info,rule.tags)
            if #tags==0 then return {}end
            local orule=rule.objectives
            local has=orule and next(orule)~=nil
            local envs=has and environment_branches(info) or {{false,{}}}
            if has then
                local distinct={}
                for _,e in ipairs(envs)do distinct[e[1]]=true end
                if #sorted_keys(distinct)==1 then envs={{envs[1][1],{}}}end -- one reachable environment
            end
            local cache,order={},{}
            for _,e in ipairs(envs)do
                if cache[e[1]]==nil then
                    cache[e[1]]=objective_paths(op,info,orule,e[1] or 0);order[#order+1]=e[1]
                end
            end
            if #order>1 then
                local same=true
                local first=canon(cache[order[1]])
                for _,e in ipairs(order)do if canon(cache[e])~=first then same=false;break end end
                if same then envs={{order[1],{}}}end -- the environment changes nothing here
            end
            local out={}
            for _,e in ipairs(envs)do
                for _,od in ipairs(cache[e[1]])do
                    for _,td in ipairs(tags)do
                        local draws=merge(td,od)
                        if draws then out[#out+1]={draws=draws,mods=e[2],probability=mass(draws,e[2])}end
                    end
                end
            end
            table.sort(out,function(a,b)return a.probability>b.probability end)
            return out
        end

        -- Every draw path through one operation's composition yielding all
        -- required kinds ({kind, ...} in order), each delivered through a
        -- mission_paths() branch when rules[kind] has rules. Draws after the
        -- last required mission are left free.
        function P.paths(op,required,rules)
            assert(not op.special and #op.extra==0,'special levels and modifier missions are not solved')
            rules=rules or {}
            local missions={}
            local out={}
            local function deliveries(kind,missing)
                local wanted=false
                for _,k in ipairs(missing)do if k==kind then wanted=true end end
                local rule=rules[kind]
                if rule and next(rule.tags or {})==nil and next(rule.objectives or {})==nil then rule=nil end
                if not wanted or not rule then return {{wanted,nil,1}}end
                missions[kind]=missions[kind] or P.mission_paths(op,kind,rule)
                local list={}
                for _,mp in ipairs(missions[kind])do list[#list+1]={true,{draws=mp.draws,mods=mp.mods},mp.probability}end
                list[#list+1]={false,nil,1} -- the slot may hold the kind without meeting its rules
                return list
            end
            local function walk(template,slot,position,usage,counts,kinds,constraints,probability)
                local missing={}
                for _,k in ipairs(required)do
                    local have=false
                    for _,g in ipairs(kinds)do if g==k then have=true;break end end
                    if not have then missing[#missing+1]=k end
                end
                if #missing==0 then
                    out[#out+1]={template=template.index,kinds={unpack(kinds)},constraints={unpack(constraints)},
                        probability=probability}
                    return
                end
                if slot>=op.total or op.total-slot<#missing then return end
                -- The category draw, if any: forced when the module makes no draw.
                local branches={}
                stubbed(0)
                local selected=choose_category(template.candidates,template.rules,usage,stubbed(0))
                if stub.draws==0 then branches[1]={selected,position,nil}
                else
                    for _,part in ipairs(partition(function(o)
                        local sel,category=choose_category(template.candidates,template.rules,usage,stubbed(o))
                        return category,sel
                    end))do
                        branches[#branches+1]={part.value,position+1,{kind='direct',position=position,lo=part.first,hi=part.last}}
                    end
                end
                for _,branch in ipairs(branches)do
                    local eligible,at,step=branch[1],branch[2],branch[3]
                    local p=probability*(step and (step.hi-step.lo+1)/M32 or 1)
                    local cons={unpack(constraints)}
                    if step then cons[#cons+1]=step end
                    if #eligible==0 or slot>=#op.levels then
                        walk(template,slot+1,at,usage,counts,kinds,cons,p)
                    else
                        local seed_position=at
                        local choices={}
                        if #eligible==1 then choices[1]={eligible[1],nil,counts}
                        else
                            for _,part in ipairs(partition(function(o)
                                stubbed(o)
                                local c=copy(counts)
                                return choose_mission(eligible,template.weights,c,0,0),c
                            end))do
                                choices[#choices+1]={part.key,{kind='mission',position=seed_position,lo=part.first,hi=part.last},part.value}
                            end
                        end
                        for _,choice in ipairs(choices)do
                            local kind,mstep,c2=choice[1],choice[2],choice[3]
                            local u2=copy(usage)
                            local cat=op.category_of[kind]
                            u2[cat]=(u2[cat] or 0)+1
                            local q=p*(mstep and (mstep.hi-mstep.lo+1)/M32 or 1)
                            for _,d in ipairs(deliveries(kind,missing))do
                                local delivers,mission,mp=d[1],d[2],d[3]
                                if delivers or op.total-slot-1>=#missing then
                                    local s=mstep
                                    if mission then
                                        s={kind='mission',position=seed_position,lo=mstep and mstep.lo,hi=mstep and mstep.hi,mission=mission}
                                    end
                                    local c3={unpack(cons)}
                                    if s then c3[#c3+1]=s end
                                    local k2={unpack(kinds)}
                                    if delivers then k2[#k2+1]=kind end
                                    walk(template,slot+1,seed_position+1,u2,c2,k2,c3,q*mp)
                                end
                            end
                        end
                    end
                end
            end
            for _,part in ipairs(partition(function(o)
                stubbed(o)
                local result=finalize(0,op.templates,0,op.budget)
                return result.valid and result.template_index or 'none'
            end))do
                if part.key~='none' then
                    local template
                    for _,t in ipairs(op.templates)do if t.index==part.key then template=t;break end end
                    local base={}
                    if part.first~=0 or part.last~=LAST then base[1]={kind='final',position=1,lo=part.first,hi=part.last}end
                    walk(template,0,1,{},{},{},base,(part.last-part.first+1)/M32)
                end
            end
            table.sort(out,function(a,b)return a.probability>b.probability end)
            return out
        end

        -- The paths for the required kinds at a difficulty when every
        -- operation there has the same inputs (IDs differing only in their
        -- level tiles), else nil.
        function P.shared_paths(operations,difficulty,required,rules)
            local derived={id=true,effect_id=true,levels=true}
            local signature,sample
            for _,op in ipairs(operations)do
                if op.difficulty==difficulty then
                    checkpoint()
                    local plain={levels=#op.levels}
                    for k,v in pairs(op)do if not derived[k]then plain[k]=v end end
                    local text=canon(plain)
                    if signature and text~=signature then return nil end
                    signature,sample=text,op
                end
            end
            if not sample then return {}end
            return P.paths(sample,required,rules)
        end
        return P
    end
    return R
end
