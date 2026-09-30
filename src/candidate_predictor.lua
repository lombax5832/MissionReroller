-- Bind the campaign context once; candidate seeds never read displayed rows.
-- The planet model (planet_model.lua) passes its decoded inputs.
return function(make_levels,make_bases,predict)
    return function(read,u,pointer,game,board,definitions,planet,inputs)
        -- Decoded rule values are immutable within this frozen context. Cache
        -- seed-independent queries; their original byte dependencies remain in
        -- the read set and are revalidated before any candidate is accepted.
        local function pack(...)return {n=select('#',...),...}end
        local function memo(name,key)
            local original,cache=inputs[name],{}
            inputs[name]=function(...)
                local k=key(...);local values=cache[k]
                if not values then values=pack(original(...));cache[k]=values end
                return unpack(values,1,values.n)
            end
        end
        memo('biome_definition',function(p)return p end)
        memo('mission',function(id,p,e,t,enabled)return string.format('%d:%d:%u:%u:%d',id,p,e,t or 0,enabled and 1 or 0)end)
        local function operation_key(op,p)return string.format('%d:%d:%d:%d:%u',p,op.difficulty,op.category,op.faction,op.effect_id)end
        memo('templates',operation_key)
        memo('candidates',function(t,op,p)return t..':'..operation_key(op,p)end)
        memo('difficulty',function(d,c)return d..':'..c end)
        memo('extra_mission',function(m,f)return string.format('%u:%d',m,f)end)
        memo('effect_id',function(op,p)return op.category*65536+op.id*512+p end)
        local bases=make_bases(read,u,pointer,game,board,definitions,planet,inputs)
        local levels=make_levels(read,u,game)
        local graphs={}
        local function graph(op)
            local key=op.id..':'..op.category;local value=graphs[key]
            if not value then value=pack(levels(definitions,op));graphs[key]=value end
            return unpack(value,1,value.n)
        end
        -- Operations are generated independently from their own seeds, so a
        -- search may predict only the requested difficulty, and only the
        -- rows it accepts. Every base is still drawn, because the bases
        -- share one random sequence.
        return function(seed,difficulty,accepts)
            local operations,active=bases(seed)
            if difficulty then
                local wanted={}
                for _,op in ipairs(operations)do
                    if op.difficulty==difficulty and (not accepts or accepts(op.row))then wanted[#wanted+1]=op end
                end
                operations=wanted
            end
            local result=predict(operations,planet,inputs,graph,active)
            for _,op in ipairs(result)do assert(op.valid,'Unsupported invalid candidate operation')end
            return result
        end
    end
end
