-- The objectives of a mission descriptor (1756730, docs/SIDE_OBJECTIVE_RESEARCH.md):
-- the minimum entries, the sub-step draws, then weighted side (role 3),
-- tactical (role 2) and role 4 draws (1757870), all from one 64-bit LCG
-- seeded by the mission seed. Objectives are native ids; no reads or writes.
local ffi,bit=require('ffi'),require('bit')
local single=ffi.new('float[1]')
local function f(n)single[0]=n;return tonumber(single[0])end
local SCALE=f(1/4294967296)
-- The remaining sub-step weight below which native stops drawing.
local FLOOR=f(1e-6)
local R={}
-- One filter row per English title of the side (role 3) and tactical
-- (role 2) objectives, from the game's objective titles (strings table
-- 0xd29d9f674db28566); a row covers every id with that title and is keyed
-- by its first id.
R.rows={
    {name='Acquire Soil Scan Data',ids={0x89d44533}},
    {name='Anti-Air Emplacement',ids={0xb34e46ea,0xf86cb0fc}},
    {name='Cognitive Disruptor',ids={0x0c3f8046}},
    {name='Collect Black Box',ids={0x8fafc9b7}},
    {name='Compromise Automaton Defenses',ids={0x81af60fa}},
    {name='Destroy Bio-Processors',ids={0xff976e5a}},
    {name='Destroy Eggs',ids={0xca82b4ab}},
    {name='Destroy Fuel Reserves',ids={0xa8021946}},
    {name='Destroy Laser Obelisk',ids={0x891b274c}},
    {name='Destroy Rogue Research Station',ids={0xcab216b0}},
    {name='Destroy Stockpiled Ammunition',ids={0xd333e28d}},
    {name='Destroy Transmission Network',ids={0xbfc502e7}},
    {name='Detector Tower',ids={0xab4f05c9}},
    {name='Eliminate Devastator',ids={0x57a7c183}},
    {name='Eliminate Factory Strider',ids={0x8f64fe61}},
    {name='Eliminate Hulk',ids={0x6c55ba02}},
    {name='Erase Terrorist Memorials',ids={0x1407a11d}},
    {name='Exterminate Terminids',ids={0xb7199ebd,0x196d3325}},
    {name='Extract Anomalous Material',ids={0xa4de5010}},
    {name='Gunship Facility',ids={0x75294ef5}},
    {name='Intercept Convoy',ids={0xf981c2c7}},
    {name='Launch ICBM',ids={0xb469db1c}},
    {name='Lidar Station',ids={0xf1969b14}},
    {name='Mobile Radar',ids={0x348c86be}},
    {name='Mortar Emplacement',ids={0xb454d9ca,0x943966ab}},
    {name='Raise Flag of Super Earth',ids={0x47d16d95}},
    {name='Raze Strategic Infrastructure',ids={0xd45f2884}},
    {name='Recover Scientific Specimens',ids={0xc312deae}},
    {name='Recover SSSD',ids={0x2ca0e3a7}},
    {name='Retrieve Mutant Larva',ids={0x3209b101}},
    {name='SEAF Artillery',ids={0x86cfeedb}},
    {name='SEAF SAM Site',ids={0xc46443b2}},
    {name='Secondary Extraction Zone',ids={0x9de117ab,0xece7ef4e}},
    {name='Shrieker Nest',ids={0xb3dd50be}},
    {name='Spore Spewer',ids={0x62f023e9}},
    {name='Stalker Lair',ids={0xf8c79b43}},
    {name='Stratagem Jammer',ids={0x6cac3f28}},
    {name='Terminate Illegal Broadcast',ids={0x4c10b12e}},
    {name='Upload Escape Pod Data',ids={0xfdab51c3}},
}
-- The row key of an objective id, and a row's title by its key.
R.row_of,R.names={},{}
for _,row in ipairs(R.rows)do
    row.id=row.ids[1];R.names[row.id]=row.name
    for _,id in ipairs(row.ids)do R.row_of[id]=row.id end
end
local function step(state)return state*6364136223846793005ULL+1442695040888963407ULL end
local function high(state)return f(tonumber(bit.rshift(state,32)))end
-- i: objective(id) -> record, environment() -> the biome environment byte,
-- disabled(id), context {banned, extra}. mission is
-- src/side_objective_inputs.lua's mission record, counts its difficulty
-- counts and scale the category's side scale or nil.
function R.resolve(seed,difficulty,mission,counts,scale,i)
    assert(type(seed)=='number' and seed>=0 and seed<=4294967295 and seed==math.floor(seed),'Invalid mission seed')
    local out={}
    if difficulty==0 then return out end
    local objective,pool,D=i.objective,mission.pool,difficulty
    local function in_range(record)
        return (record.minimum==0 or record.minimum<=D) and (record.maximum==0 or D<=record.maximum)
    end
    local side=counts.side
    if scale then
        -- The float product rounded as a double (round, 20be08c).
        side=math.floor(f(f(side)*scale)+0.5)
        assert(side>=0 and side<4294967296,'Invalid side objective count')
    end
    -- Minimum entries. Only roles 0 and 1 count towards the sub-step range.
    local taken,primary,primary_set,lo,hi,weight={},nil,false,0,0,0
    for k,e in ipairs(pool)do
        taken[k]=0
        if e.id~=0 and e.weight>0 then
            local record=objective(e.id)
            if in_range(record)then
                if e.role==0 then
                    primary=primary or k
                    if not primary_set and e.minimum~=0 then primary_set=true end
                end
                taken[k]=e.minimum
                if e.role<=1 then
                    local cap=math.min(e.maximum,record.cap)
                    lo=lo+e.minimum;hi=hi+cap
                    if e.minimum<cap then weight=f(weight+e.weight)end
                end
            end
        end
    end
    if not primary_set and primary then taken[primary]=taken[primary]+1 end
    -- Extra sub-steps: the difficulty's place in the mission's range blends
    -- the minimum and maximum totals (roundf, 20bbb78).
    local state=ffi.new('uint64_t',seed)
    if mission.lo<mission.hi then
        local t=f(f((D-mission.lo)%4294967296)/f(mission.hi-mission.lo))
        local target=math.floor(f(f(f(1-t)*f(lo))+f(f(hi)*t))+0.5)%4294967296
        local upper=counts.substeps>lo and counts.substeps or lo
        if target<upper then upper=target end
        local extra=upper-lo
        while extra~=0 and weight>FLOOR do
            state=step(state)
            local r=f(f(high(state)*SCALE)*weight)
            local sum,last,picked=0,nil,false
            for k,e in ipairs(pool)do
                if (e.role<2 or e.role>4) and e.weight>0 then
                    local cap=math.min(e.maximum,objective(e.id).cap)
                    if taken[k]<cap then
                        sum=f(sum+e.weight);last=k
                        if r<=sum then
                            taken[k]=taken[k]+1
                            if cap<=taken[k] then weight=f(weight-e.weight)end
                            picked=true;break
                        end
                    end
                end
            end
            if not picked then
                if not last then break end
                taken[last]=taken[last]+1
            end
            extra=extra-1
        end
    end
    local environment
    local function allowed(record)
        local list=record.environments
        if list[1]==0 then return true end
        environment=environment or i.environment()
        for k=1,4 do
            if list[k]==0 then return false end
            if list[k]==environment then return true end
        end
        return false
    end
    local left={[3]=side,[2]=counts.tactical,[4]=4294967295}
    local pools={[3]={},[2]={},[4]={}}
    local function emit(id,role)out[#out+1]={id=id,role=role}end
    for k,e in ipairs(pool)do
        if e.id~=0 and e.weight>0 then
            local record=objective(e.id)
            if not i.disabled(record.id) and allowed(record) and in_range(record) and not i.context.banned[e.id] then
                for _=1,taken[k]do
                    local role=e.role
                    if left[role]==nil then emit(e.id,role)
                    elseif left[role]~=0 then left[role]=left[role]-1;emit(e.id,role)end
                end
                local list=pools[e.role]
                if list then
                    list[#list+1]={id=record.id,weight=e.weight,cap=math.min(e.maximum,record.cap),count=e.minimum,
                        mask=record.mask,role=e.role}
                end
            end
        end
    end
    -- 1757870: drop entries at their cap or sharing a drawn mask bit
    -- (moving the last into the gap), then draw one.
    local function draw(list,remaining)
        local n=#list
        if n==0 then return end
        local mask=0
        repeat
            if remaining==0 then return end
            local k=1
            while k<=n do
                while not (n<k or (list[k].count<list[k].cap and bit.band(list[k].mask,mask)==0))do
                    list[k]=list[n];n=n-1
                end
                k=k+1
            end
            local total=0
            for j=1,n do total=f(total+list[j].weight)end
            state=step(state)
            if n==0 then return end
            local r=f(f(high(state)*SCALE)*total)
            local sum=0
            for j=1,n do
                local e=list[j];sum=f(sum+e.weight)
                if r<=sum then
                    emit(e.id,e.role);e.count=e.count+1;mask=bit.bor(mask,e.mask);remaining=remaining-1
                    if e.cap<=e.count then list[j]=list[n];n=n-1 end
                    break
                end
            end
        until n==0
    end
    draw(pools[3],left[3]);draw(pools[2],left[2]);draw(pools[4],left[4])
    if i.context.extra then emit(0x68bfbb59,2)end
    return out
end
-- The rows of a resolved list's side and tactical objectives, as a set.
function R.set(list)
    local result={}
    for _,o in ipairs(list)do
        if (o.role==3 or o.role==2) and R.row_of[o.id]then result[R.row_of[o.id]]=true end
    end
    return result
end
-- A resolved list for the log: title (or id) and role, in native order.
function R.describe(list)
    local parts={}
    for _,o in ipairs(list)do parts[#parts+1]=(R.names[R.row_of[o.id]] or string.format('%08x',o.id))..'/'..o.role end
    return #parts>0 and table.concat(parts,', ') or 'none'
end
return R
