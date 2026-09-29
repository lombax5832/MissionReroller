-- LuaJIT uint64 arithmetic keeps every bit, including wraparound at 2^64.
local ffi,bit=require('ffi'),require('bit')
local function uint32(n)
    assert(type(n)=='number' and n>=0 and n<=4294967295 and n==math.floor(n),'Invalid uint32')
    return n
end
return function(seed,planet,state_bytes)
    local state=ffi.new('uint64_t',(uint32(seed)+uint32(planet or 0))%4294967296)
    if state_bytes~=nil then
        assert(type(state_bytes)=='string' and #state_bytes==8,'Invalid RNG state')
        local value=ffi.new('uint64_t[1]');ffi.copy(value,state_bytes,8);state=value[0]
    end
    local rng={}
    function rng:state_bytes()
        local value=ffi.new('uint64_t[1]',state);return ffi.string(value,8)
    end
    function rng:next()
        state=state*6364136223846793005ULL+1442695040888963407ULL
        return tonumber(bit.rshift(state,32))
    end
    function rng:index(count)
        assert(type(count)=='number' and count>=1 and count<=64 and count==math.floor(count),'Invalid pool size')
        return math.min(count-1,math.floor(self:next()*(1/4294967296)*count))
    end
    return rng
end
