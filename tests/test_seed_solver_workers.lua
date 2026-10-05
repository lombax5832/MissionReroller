-- Usage: luajit tests/test_seed_solver_workers.lua <src> [capture.lua]
-- The seed solver's worker VMs (src/seed_solver_workers.lua) and their
-- codec (src/seed_solver_codec.lua), with real thread-pool threads in this
-- process's lua51.dll: the codec round trip; each worker's candidates equal
-- an in-process chain from the same start over the same steps; accept is
-- applied by the caller; close, reap and shutdown; the memory refusal; and
-- worker failures. With a capture, the same on the real request of
-- scripts/profile_seed_solver.lua (both rules: enemy force and excluded
-- objectives, 80 alternatives per mission).
local root,capture=assert(arg[1]),arg[2]
local ffi=require('ffi')
ffi.cdef[[void Sleep(uint32_t ms);]]
local function read(name)local f=assert(io.open(root..'/'..name,'rb'));local s=f:read('*a');f:close();return s end
local function module(name)return assert(loadstring(read(name),'='..name))()end
local Math=module('seed_solver_math.lua')
local Chain=module('seed_solver_chain.lua')(Math)
local Codec=module('seed_solver_codec.lua')
local sources={math=read('seed_solver_math.lua'),chain=read('seed_solver_chain.lua'),codec=read('seed_solver_codec.lua')}
local Workers=module('seed_solver_workers.lua')(sources)

local function starts(seed)
    local n=seed
    return function()n=(n+1)%4294967296;return Math.output(n,1)end
end
local function key(seed,row)return string.format('%d:%d',seed,row)end

-- Synthetic paths of the shapes the chain handles: stream draws, a mission
-- with alternatives (draws and a modular environment condition) shared by
-- two paths, a kind range, a mission without alternatives.
local shared_mission={alternatives={
    {draws={[1]={0,1073741823},[2]={0,2147483647}},mods={{7,0,3}}},
    {draws={[1]={3221225472,4294967295}},mods={}}}}
local plain_mission={draws={[2]={0,536870911}},mods={{5,1,2}}}
local synthetic={
    {constraints={{kind='stream',position=2,lo=0,hi=268435455},{kind='mission',position=3,lo=0,hi=2147483647,mission=shared_mission}}},
    {constraints={{kind='stream',position=1,lo=1000,hi=500000000},{kind='mission',position=4,mission=shared_mission}}},
    {constraints={{kind='mission',position=5,mission=plain_mission},{kind='stream',position=6,lo=0,hi=1073741823}}},
}
for _,path in ipairs(synthetic)do path.probability=Chain.mass(path)end
local rows={{row=27,seed_position=19,share=1},{row=28,seed_position=21,share=0.5}}

-- Codec: every field the chain reads survives, shared missions stay shared.
local function check_codec(paths,rows,planet)
    local p2,r2,planet2=Codec.decode(Codec.encode(paths,rows,planet))
    assert(planet2==planet and #r2==#rows and #p2==#paths,'codec counts')
    for i,r in ipairs(rows)do
        assert(r2[i].row==r.row and r2[i].seed_position==r.seed_position and r2[i].share==(r.share or 1),'codec row')
    end
    local seen={}
    for i,path in ipairs(paths)do
        local q=p2[i]
        assert(q.probability==(path.probability or 1) and #q.constraints==#path.constraints,'codec path')
        for k,s in ipairs(path.constraints)do
            local t=q.constraints[k]
            assert((t.kind=='mission')==(s.kind=='mission') and t.position==s.position and t.lo==s.lo and t.hi==s.hi,'codec constraint')
            assert((t.mission==nil)==(s.mission==nil),'codec mission presence')
            if s.mission then
                if seen[s.mission]then assert(seen[s.mission]==t.mission,'shared mission decoded twice')end
                seen[s.mission]=t.mission
                local a=s.mission.alternatives or {s.mission}
                local b=t.mission.alternatives or {t.mission}
                assert(#a==#b and (s.mission.alternatives==nil)==(t.mission.alternatives==nil),'codec alternatives')
                for j,x in ipairs(a)do
                    for d,r in pairs(x.draws)do assert(b[j].draws[d][1]==r[1] and b[j].draws[d][2]==r[2],'codec draw')end
                    for d in pairs(b[j].draws)do assert(x.draws[d],'codec extra draw')end
                    assert(#x.mods==#b[j].mods,'codec mods')
                    for m,mod in ipairs(x.mods)do for z=1,3 do assert(b[j].mods[m][z]==mod[z],'codec mod')end end
                end
            end
        end
    end
end
check_codec(synthetic,rows,173)

local pool,why=Workers.pool(ffi,{max_workers=4,processors=8})
assert(pool,'pool: '..tostring(why))
local function wait(predicate,what)
    for _=1,3000 do if predicate()then return end;ffi.C.Sleep(5)end
    error('timed out: '..what)
end

-- Every worker's candidates equal an in-process chain over the same arc of
-- each job (one shared base, arc k of n) and the same steps, budgeted as the
-- worker budgets them; so do the steps and the expected candidates.
local function drain(source,label)
    local got,count,done={},0,nil
    wait(function()
        while true do
            local s,d,row=source.next()
            if s then got[key(s,row)]=(got[key(s,row)] or 0)+1;count=count+1
            else done=d;return d end
        end
    end,label..' candidates')
    assert(done==true,label..': not done')
    return got,count
end
local function reference(paths,rows,planet,base,n,limit)
    local want,expected,steps={},0,0
    for k=0,n-1 do
        local chain=Chain.new({paths=paths,rows=rows,planet=planet,random=starts(base),arc=n>1 and {index=k,count=n} or nil})
        while not limit or chain.steps<limit do
            local s,d,row=chain.next(limit and math.min(4096,limit-chain.steps) or 4096)
            if s then want[key(s,row)]=(want[key(s,row)] or 0)+1 elseif d then break end
        end
        expected,steps=expected+chain.expected(),steps+chain.steps
    end
    return want,expected,steps
end
local function same(got,want,label)
    for k,n in pairs(want)do assert(got[k]==n,label..': worker candidates differ at '..k)end
    for k,n in pairs(got)do assert(want[k]==n,label..': extra worker candidate '..k)end
end
local function compare(paths,rows,planet,limit,label)
    local base
    local given=starts(12345)
    local source,reason=pool.start({paths=paths,rows=rows,planet=planet,step_limit=limit,
        random=function()base=given();return base end})
    assert(source,label..': '..tostring(reason))
    local got,count=drain(source,label)
    local n=source.workers
    local want,expected,steps=reference(paths,rows,planet,base,n,limit)
    same(got,want,label)
    assert(source.steps()==steps and steps==limit*n,label..': steps '..source.steps())
    assert(math.abs(source.expected()-expected)<=1e-9*math.max(1,expected),label..': expected candidates')
    local r=source.report()
    assert(r.failed==0 and r.workers==n and r.workers==r.planned,label..': report')
    wait(function()return pool.reap()==0 end,label..' reap')
    return count,r
end
local n_synthetic,r_synthetic=compare(synthetic,rows,173,60000,'synthetic')
assert(n_synthetic>0,'synthetic request yielded no candidate')

-- The arcs tile each job's starts: walked to the end, the workers find
-- exactly the full walk's candidates once each, in as many steps, and the
-- source ends because the space is covered.
do
    local small={{constraints={{kind='stream',position=2,lo=0,hi=149999}}}}
    small[1].probability=Chain.mass(small[1])
    local base
    local source=assert(pool.start({paths=small,rows=rows,planet=173,random=function()base=1234567;return base end}))
    local got=drain(source,'exhaustive')
    local want,expected,steps=reference(small,rows,173,base,1)
    same(got,want,'exhaustive')
    assert(source.steps()==steps,'exhaustive steps: '..source.steps()..' against '..steps)
    assert(math.abs(source.expected()-expected)<=1e-9*expected,'exhaustive expected candidates')
    local r=source.report()
    assert(r.workers==r.planned and r.workers>1 and r.failed==0,'exhaustive report')
    wait(function()return pool.reap()==0 end,'exhaustive reap')
end

-- accept runs in this VM on (seed, row).
do
    local source=assert(pool.start({paths=synthetic,rows=rows,planet=173,step_limit=60000,random=starts(9),
        accept=function(_,row)return row==27 end}))
    local any=false
    wait(function()
        while true do
            local s,d,row=source.next()
            if s then assert(row==27,'accept not applied');any=true elseif d then return true else return false end
        end
    end,'accept run')
    assert(any,'no accepted candidate')
    wait(function()return pool.reap()==0 end,'accept reap')
end

-- Idle while nothing is ready, close mid-walk, and reap.
do
    local source=assert(pool.start({paths=synthetic,rows=rows,planet=173,random=starts(5)}))
    local s,d,idle=source.next()
    assert(s or (d==false and idle==true),'idle signal')
    ffi.C.Sleep(50)
    assert(source.steps()>0,'workers did not walk')
    source.close()
    assert(source.next()==nil,'closed source still yields')
    wait(function()return pool.reap()==0 end,'reap after close')
end

-- Shutdown stops a running source and closes its workers.
do
    assert(pool.start({paths=synthetic,rows=rows,planet=173,random=starts(6)}))
    ffi.C.Sleep(20)
    assert(pool.shutdown(3)==0,'workers left open at shutdown')
end

-- Warm workers: tick makes idle VMs up to max_workers; a search reuses
-- them with the same candidates, and they go back to idle when it ends,
-- twice over; cold closes the idle ones and stops a running search.
local r_warm
do
    assert(pool.state().idle==0 and not pool.state().warm,'a new pool is cold')
    assert(pool.tick()==0 and pool.state().idle==0,'a cold pool makes no worker')
    pool.warm(true)
    wait(function()pool.tick();local s=pool.state();return s.idle==pool.max_workers and s.retired==0 end,'warm-up')
    for _=1,10 do pool.tick()end
    assert(pool.state().idle==pool.max_workers,'warm stops at max_workers')
    for round=1,2 do
        local _,r=compare(synthetic,rows,173,60000,'warm '..round)
        assert(r.warm==pool.max_workers and r.workers==pool.max_workers,'warm '..round..': idle workers reused')
        assert(pool.state().idle==pool.max_workers,'warm '..round..': workers back to idle')
        r_warm=r
    end
    local source=assert(pool.start({paths=synthetic,rows=rows,planet=173,random=starts(7)}))
    ffi.C.Sleep(20)
    assert(pool.state().idle==0,'a running search holds the workers')
    assert(pool.warm(false)==0,'no idle worker to close while searching')
    assert(source.next()==nil and select(2,source.next())==true,'cold stops a running search')
    wait(function()return pool.reap()==0 end,'cold reap')
    assert(pool.state().idle==0,'cold closes returning workers')
    pool.warm(true)
    wait(function()pool.tick();return pool.state().idle==pool.max_workers end,'warm again')
    assert(pool.warm(false)==pool.max_workers and pool.state().idle==0,'cold closes the idle workers')
    -- Cold again: a search's workers close when it ends.
    compare(synthetic,rows,173,20000,'cold after warm')
    assert(pool.state().idle==0,'cold workers are not kept')
    -- Shutdown closes idle workers too.
    pool.warm(true)
    wait(function()pool.tick();return pool.state().idle==pool.max_workers end,'warm before shutdown')
    assert(pool.shutdown(3)==0 and pool.state().idle==0 and not pool.state().warm,'shutdown closes idle workers')
end

-- Too little memory below 2 GB: no worker starts.
do
    local tight=assert(Workers.pool(ffi,{reserve_mb=4096,processors=8}))
    local source,reason=tight.start({paths=synthetic,rows=rows,planet=173,random=starts(1)})
    assert(source==nil and reason:find('memory below 2 GB',1,true),'memory refusal: '..tostring(reason))
end

-- Set-up runs on the worker's thread: a worker whose set-up fails, like one
-- whose walk fails, ends the source and reports why.
do
    local broken=module('seed_solver_workers.lua')({math=sources.math,codec=sources.codec,chain='error("chain unavailable")'})
    local p=assert(broken.pool(ffi,{max_workers=2,processors=8}))
    local source=assert(p.start({paths=synthetic,rows=rows,planet=173,random=starts(2)}))
    wait(function()local s,d=source.next();return d==true end,'a failed set-up ends the source')
    wait(function()return p.reap()==0 end,'reap failed set-up')
    local r=source.report()
    assert(r.failed>=1 and r.error and r.error:find('chain unavailable',1,true),'set-up failure: '..tostring(r.error))
    -- A failed warm-up keeps no worker and warms no further.
    p.warm(true)
    wait(function()p.tick();return p.warm_error~=nil end,'failed warm-up')
    for _=1,10 do assert(p.tick()==0,'warming went on after a failure')end
    assert(p.state().idle==0 and p.warm_error:find('chain unavailable',1,true),'warm error: '..tostring(p.warm_error))
    p.warm(false)
    local failing=module('seed_solver_workers.lua')({math=sources.math,codec=sources.codec,
        chain='return function()return {new=function()return {steps=0,next=function()error("walk failed")end}end}end'})
    p=assert(failing.pool(ffi,{max_workers=2,processors=8}))
    source=assert(p.start({paths=synthetic,rows=rows,planet=173,random=starts(3)}))
    wait(function()local s,d=source.next();return d==true end,'failed workers end the source')
    wait(function()return p.reap()==0 end,'reap failed workers')
    local r=source.report()
    -- The first worker's failure ends the source before the others start.
    assert(r.failed>=1 and r.failed==r.workers and r.error and r.error:find('walk failed',1,true),'failure report: '..tostring(r.error))
end

local real=''
if capture then
    local here=(arg[0]:match('^(.*[/\\])') or '')..'../'
    local Cap=dofile(here..'scripts/seed_solver_capture.lua')(here..'scripts/',root,capture)
    local H=Cap.H
    local solver,identity=Cap.solver_inputs()
    local Paths=H.module(root..'/seed_solver_paths.lua')(H.module(root..'/mission_category_choice.lua'),
        H.module(root..'/mission_weighted_choice.lua'),H.module(root..'/operation_finalization.lua'))
    local P=Paths.new({records=solver.records,row_of=Cap.SideObjectives.row_of,disabled_tags=solver.disabled_tags})
    local active=identity.active
    local preserved=active and active.planet==Cap.planet and active.row or nil
    local avoid={}
    for row,name in pairs(Cap.SideObjectives.names)do if name=='Lidar Station' or name=='SEAF Artillery' then avoid[row]='exclude' end end
    local op
    for _,o in ipairs(Cap.board_of(Cap.case.seed))do
        if o.row<30 and o.row~=preserved and #o.missions>=3 and o.missions[1][4] and (not op or o.difficulty>op.difficulty)then op=o end
    end
    local kinds,rules={},{}
    for i=1,3 do
        local m=op.missions[i];kinds[i]=m[1]
        rules[m[1]]={tags=m[4] and m[4][1] and {[m[4][1]]='accept'} or nil,objectives=avoid}
    end
    local paths=assert(P.shared_paths(solver.operations,op.difficulty,kinds,rules))
    for _,path in ipairs(paths)do path.probability=Chain.mass(path)end
    local real_rows={}
    for r=(op.difficulty-1)*3,op.difficulty*3-1 do
        if r~=preserved then local _,sp=Chain.positions(r,preserved);real_rows[#real_rows+1]={row=r,seed_position=sp,share=1}end
    end
    check_codec(paths,real_rows,Cap.planet)
    local n,r=compare(paths,real_rows,Cap.planet,300000,'capture')
    real=string.format('; capture: %d paths, %.0f KB of text, %d candidates, worker heap %.0f KB after set-up, peak %.0f KB',
        #paths,r.text_kb,n,r.setup_kb,r.peak_kb)
end
print(string.format('test_seed_solver_workers: passed (%s; %d workers, %d warm; synthetic %d candidates, worker heap %.0f KB%s)',
    jit and jit.version or '?',r_synthetic.workers,r_warm.warm,n_synthetic,r_synthetic.setup_kb,real))
