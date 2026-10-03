-- Bounded decoders for the side-objective inputs of 1756730: the objective
-- records, a mission type's objective pool, the difficulty row's counts, the
-- category scale, configuration-disabled objectives, the seeded biome
-- environment (1758d40, 1758fc0) and the world modifiers' bans (1267a00).
-- All reads are injected; composition holds biome_definition and
-- world_modifiers (src/composition_inputs.lua).
local O=...
return function(read,u,pointer,game,board,config,composition)
    local ffi=require('ffi');local scalar=ffi.new('float[1]')
    local single=ffi.new('float[1]')
    local function f(n)single[0]=n;return tonumber(single[0])end
    local function word(a)return u(read(a,4),0)end
    local function float(bytes,at)ffi.copy(scalar,bytes:sub(at+1,at+4),4);return tonumber(scalar[0])end
    local function count(a,limit)local n=word(a);assert(n<=limit,'Side objective input count exceeds bound');return n end
    local function ptr(a)return assert(pointer(read(a,8)),'Missing side objective pointer')end
    local api={}
    local records,by_id
    -- Native searches the 153 records in order and falls back to the first,
    -- an empty record, for an unknown id.
    function api.objective(id)
        if not records then
            local bytes=read(game+O.rva.objective_types,153*0xa0)
            records,by_id={},{}
            for i=0,152 do
                local at=i*0xa0
                local r={id=u(bytes,at),cap=u(bytes,at+0x20),minimum=u(bytes,at+0x24),maximum=u(bytes,at+0x28),
                    mask=bytes:byte(at+0x2d),environments={bytes:byte(at+0x99,at+0x9c)}}
                records[i+1]=r
                if by_id[r.id]==nil then by_id[r.id]=r end
            end
        end
        return by_id[id] or records[1]
    end
    local missions={}
    -- A mission type's category, difficulty range, its 32 objective entries
    -- {id, weight, group, role, minimum, maximum} and its allowed biomes.
    function api.mission(kind)
        assert(kind>=0 and kind<162 and kind==math.floor(kind),'Invalid mission metadata index')
        local result=missions[kind]
        if result then return result end
        local at=game+O.rva.mission_types+kind*O.mission_type.size
        local bytes=read(at,0x40+32*0x18)
        result={category=bytes:byte(0x35),lo=u(bytes,0xc),hi=u(bytes,0x10),pool={},biomes={}}
        for i=0,31 do
            local e=0x40+i*0x18
            result.pool[i+1]={id=u(bytes,e),weight=float(bytes,e+4),group=bytes:byte(e+9),role=u(bytes,e+0xc),
                minimum=u(bytes,e+0x10),maximum=u(bytes,e+0x14)}
        end
        local n=count(at+O.mission_type.biome_count,256)
        if n>0 then
            local allowed=read(ptr(at+O.mission_type.biomes),n)
            for i=1,n do result.biomes[i]=allowed:byte(i)end
        end
        missions[kind]=result;return result
    end
    -- Side, tactical and minimum sub-step counts of the capped difficulty
    -- (11ebb40 caps it from the configuration, as for constellations).
    local cap,rows=nil,{}
    function api.counts(difficulty)
        if rows[difficulty] then return rows[difficulty] end
        if not cap then
            cap=10;local value=config.lookup(config.hash({0xaf218cac,0xfaabbea9}))
            if value and u(value,12)==6 then cap=math.min(10,u(value,16))end
            assert(cap>=1,'Unsupported zero difficulty cap')
        end
        local effective=difficulty==0 and 1 or math.min(difficulty,cap)
        local row=read(game+O.rva.difficulty_rows+(effective-1)*O.difficulty_row.size,0x34)
        rows[difficulty]={side=u(row,0x28),tactical=u(row,0x2c),substeps=u(row,0x30)}
        return rows[difficulty]
    end
    -- The side count's scale for a mission category, or nil when unscaled.
    local scales
    function api.scale(category)
        scales=scales or read(game+O.rva.objective_scales,4*0x50)
        for i=0,3 do if scales:byte(i*0x50+1)==category then return float(scales,i*0x50+4)end end
    end
    -- A boolean configuration entry set to false removes the objective.
    local disabled={}
    function api.disabled(id)
        local result=disabled[id]
        if result==nil then
            local value=config.lookup(config.hash({0x6bc26bf2,id,0xf8d23bd2}))
            result=value~=nil and u(value,12)==7 and value:byte(17)==0
            disabled[id]=result
        end
        return result
    end
    local function flag()
        local owner=pointer(read(game+O.rva.objective_flag,8))
        return owner~=nil and word(owner+0x24)~=0
    end
    -- One integer weight per float weight (x1000, truncated); a pick is one
    -- LCG step from the mission seed, the last entry when none is reached,
    -- and 0 without candidates.
    local function weighted(candidates)
        if #candidates==0 then return function()return 0 end end
        local units,total={},0
        for k,c in ipairs(candidates)do units[k]=math.floor(f(c.weight*1000));total=total+units[k]end
        assert(total>0,'Zero biome weight total')
        local modulus=ffi.new('uint64_t',total)
        return function(seed)
            local target=tonumber((ffi.new('uint64_t',seed)*6364136223846793005ULL+1442695040888963407ULL)%modulus)
            local sum=0
            for k,c in ipairs(candidates)do
                if units[k]~=0 then sum=sum+units[k];if target<=sum then return c.index end end
            end
            return candidates[#candidates].index
        end
    end
    -- environments(planet, kind, modifiers)(seed): the biome environment byte
    -- a mission's objectives are filtered by. The candidates depend only on
    -- the planet, the mission type and the world modifiers, so they are
    -- decoded once and each seed costs two draws.
    -- The second value is the set of environment bytes a seed can give.
    local environments,reachable={},{}
    function api.environments(planet,kind,modifiers)
        local key=planet..':'..kind..':'..table.concat(modifiers,',')
        local result=environments[key]
        if result then return result,reachable[key]end
        -- Native skips the draw for a descriptor without a planet id.
        if word(board+O.board.campaign+planet*O.campaign.definition_stride+0x18)==0 then
            result=function()return 0 end;environments[key],reachable[key]=result,{[0]=true}
            return result,reachable[key]
        end
        local definition=assert(composition.biome_definition(planet),'Missing planet biome definition')
        local allowed=api.mission(kind).biomes
        local list=ptr(definition+0x70)
        local n=count(list+0x28,1024);assert(n>0,'Planet without biomes')
        local entries=ptr(list+0x20)
        local size=O.biome_environment.size
        local present={};for _,hash in ipairs(modifiers)do present[hash]=true end
        local biomes,inner,gives={},{},{}
        for j=0,n-1 do
            local entry=read(entries+j*0x38,0x38);local data=ptr(entries+j*0x38+0x30)
            local rows={}
            for s=0,7 do
                local at=data+O.biome_environment.weight+s*size
                rows[s]={weight=float(read(at,4),0),need=word(data+O.biome_environment.requirement+s*size),
                    id=read(data+O.biome_environment.id+s*size,1):byte()}
            end
            local taken=false
            for _,a in ipairs(allowed)do
                if a==0 then taken=true
                else for s=0,7 do if rows[s].weight>0 and rows[s].id==a then taken=true;break end end end
                if taken then break end
            end
            if taken then biomes[#biomes+1]={index=j,weight=float(entry,0x10)}end
            local candidates={}
            for s=0,7 do
                local row=rows[s]
                if row.weight>0 and (row.need==0 or present[row.need])then
                    for _,a in ipairs(allowed)do
                        if a==0 or a==row.id then candidates[#candidates+1]={index=s,weight=row.weight};break end
                    end
                end
            end
            local pick=weighted(candidates)
            inner[j]=function(seed)return rows[pick(seed)].id end
            gives[j]={}
            for _,c in ipairs(candidates)do gives[j][rows[c.index].id]=true end
            if #candidates==0 then gives[j][rows[0].id]=true end
        end
        local biome=weighted(biomes)
        result=function(seed)return inner[biome(seed)](seed)end
        local set={}
        for _,b in ipairs(#biomes>0 and biomes or {{index=0}})do for id in pairs(gives[b.index])do set[id]=true end end
        environments[key],reachable[key]=result,set
        return result,set
    end
    -- The descriptor inputs of 1756730 for a list of world modifier hashes:
    -- 1267a00 keeps at most eight distinct ones with a definition, whose
    -- lists ban objective ids; the flag appends one objective.
    function api.context_of(hashes)
        local ids,values
        local n=count(board+O.board.world_modifier_count,4096)
        if n>0 then ids,values=read(ptr(board+O.board.world_modifier_ids),n*4),ptr(board+O.board.world_modifier_values)end
        local kept,banned,seen={},{},{}
        for _,hash in ipairs(hashes)do
            if hash~=0 and not seen[hash] and #kept<8 then
                local definition
                for i=0,n-1 do if u(ids,i*4)==hash then definition=pointer(read(values+i*8,8));break end end
                if definition then
                    seen[hash]=true;kept[#kept+1]=hash
                    local m=count(definition+O.world_modifier.banned_objective_count,64)
                    if m>0 then
                        local list=read(ptr(definition+O.world_modifier.banned_objectives),m*4)
                        for i=0,m-1 do banned[u(list,i*4)]=true end
                    end
                end
            end
        end
        return {modifiers=kept,banned=banned,extra=flag()}
    end
    -- The same for a mission of a predicted operation: the planet's active
    -- world modifiers (src/template_environments.lua).
    local contexts={}
    function api.context(planet,effect_id)
        local key=planet..':'..effect_id
        if contexts[key] then return contexts[key] end
        local _,hashes=composition.world_modifiers(planet,effect_id)
        contexts[key]=api.context_of(assert(hashes,'Unsupported alternate generation mode'))
        return contexts[key]
    end
    return api
end
