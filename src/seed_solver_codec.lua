-- The seed solver's walk inputs as text, for its worker VMs
-- (src/seed_solver_workers.lua, docs/NATIVE_SOLVER_RESEARCH.md): the draw
-- paths, the rows and the planet, only the fields src/seed_solver_chain.lua
-- reads. A flat stream of numbers parsed with one loop: no Lua constructor
-- to compile, so a worker's heap holds the tables and little else. A
-- mission constraint shared by several paths is written once and decoded
-- as one table, so the chain compiles its check once per worker.
-- The worker VMs load this file as text; keep it free of upvalues from
-- the build (no `...` arguments).
local C={}
local VERSION=1

-- checkpoint, optional, is called after each mission and path (a long
-- request encodes in pieces inside the search's frame slices).
function C.encode(paths,rows,planet,checkpoint)
    checkpoint=checkpoint or function()end
    local out,missions,order={},{},{}
    -- Integers (every value but probabilities and shares) go in as numbers,
    -- which table.concat writes exactly without a string each: encoding
    -- leaves the game's VM little garbage to collect mid-frame.
    local floor=math.floor
    local function put(v)
        if v==floor(v) and v>-2^52 and v<2^52 then out[#out+1]=v
        else out[#out+1]=string.format('%.17g',v)end
    end
    local function mission_index(m)
        if not missions[m]then order[#order+1]=m;missions[m]=#order end
        return missions[m]
    end
    for _,path in ipairs(paths)do
        for _,s in ipairs(path.constraints)do if s.mission then mission_index(s.mission)end end
    end
    local function alternative(a)
        local draws={}
        for q in pairs(a.draws)do draws[#draws+1]=q end
        table.sort(draws)
        put(#draws)
        for _,q in ipairs(draws)do put(q);put(a.draws[q][1]);put(a.draws[q][2])end
        put(#a.mods)
        for _,mod in ipairs(a.mods)do put(mod[1]);put(mod[2]);put(mod[3])end
    end
    put(VERSION);put(planet)
    put(#rows)
    for _,row in ipairs(rows)do put(row.row);put(row.seed_position);put(row.share or 1)end
    put(#order)
    for _,m in ipairs(order)do
        if m.alternatives then
            put(#m.alternatives)
            for _,a in ipairs(m.alternatives)do alternative(a)end
        else
            put(0);alternative(m)
        end
        checkpoint()
    end
    put(#paths)
    for _,path in ipairs(paths)do
        put(path.probability or 1)
        put(#path.constraints)
        for _,s in ipairs(path.constraints)do
            put(s.kind=='mission' and 1 or 0);put(s.position)
            put(s.lo and 1 or 0);put(s.lo or 0);put(s.hi or 0)
            put(s.mission and missions[s.mission] or 0)
        end
        checkpoint()
    end
    return table.concat(out,' ')
end

-- Returns paths, rows, planet.
function C.decode(text)
    local next_number=text:gmatch('%S+')
    local function get()return tonumber(next_number())end
    assert(get()==VERSION,'Unknown solver codec version')
    local planet=get()
    local rows={}
    for i=1,get()do rows[i]={row=get(),seed_position=get(),share=get()}end
    local function alternative()
        local a={draws={},mods={}}
        for _=1,get()do local q=get();a.draws[q]={get(),get()}end
        for i=1,get()do a.mods[i]={get(),get(),get()}end
        return a
    end
    local missions={}
    for i=1,get()do
        local n=get()
        if n==0 then missions[i]=alternative()
        else
            local list={}
            for k=1,n do list[k]=alternative()end
            missions[i]={alternatives=list}
        end
    end
    local paths={}
    for i=1,get()do
        local path={probability=get(),constraints={}}
        for k=1,get()do
            local s={kind=get()==1 and 'mission' or 'stream',position=get()}
            local has_lo,lo,hi=get(),get(),get()
            if has_lo==1 then s.lo,s.hi=lo,hi end
            local m=get()
            if m>0 then s.mission=missions[m]end
            path.constraints[k]=s
        end
        paths[i]=path
    end
    assert(next_number()==nil,'Trailing solver codec data')
    return paths,rows,planet
end
return C
