-- Pure Lua port of the choice portion of 11e6340. Eligibility and level
-- generation are separate stages; this function requires their candidate list.
return function(make_rng)
    local ffi=require('ffi')
    local single=ffi.new('float[1]')
    local function f32(n)single[0]=n;return tonumber(single[0])end
    local function uint(n)return type(n)=='number' and n>=0 and n<=4294967295 and n==math.floor(n)end
    return function(candidates,weights,counts,mission_seed,operation_seed)
        assert(#candidates>=1 and #candidates<=162,'Invalid mission candidate count')
        assert(uint(mission_seed) and uint(operation_seed),'Invalid mission seed')
        local minimum=4294967295
        for _,id in ipairs(candidates)do
            assert(uint(id) and id<162,'Invalid mission type')
            local used=counts[id] or 0;assert(uint(used),'Invalid mission usage count')
            minimum=math.min(minimum,used)
        end
        -- Native singleton fast path does not increment the usage counter.
        if #candidates==1 then return candidates[1]end
        local total=0
        for _,id in ipairs(candidates)do
            if (counts[id] or 0)==minimum and weights[id]~=nil then
                local weight=f32(weights[id])
                assert(weight>=0 and weight<math.huge,'Invalid mission weight')
                total=f32(total+weight)
            end
        end
        assert(total<math.huge,'Mission weight sum overflow')
        local random=f32(make_rng(mission_seed,operation_seed):next())
        local threshold=f32(f32(random*f32(1/4294967296))*total)
        local accumulated=0
        for _,id in ipairs(candidates)do
            if (counts[id] or 0)==minimum and weights[id]~=nil then
                accumulated=f32(accumulated+f32(weights[id]))
                if threshold<=accumulated then
                    counts[id]=((counts[id] or 0)+1)%4294967296
                    return id
                end
            end
        end
        error('No weighted mission candidate')
    end
end
