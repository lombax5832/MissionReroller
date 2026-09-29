-- 7bb8c0 key folding and the primary/fallback tables from 12e7990.
return function(read,u,pointer,manager)
    local ffi=require('ffi');local bit=require('bit')
    local function mul(a,b)return tonumber(ffi.cast('uint32_t',ffi.new('uint64_t',a)*b))end
    local function hash(path)
        local value=0
        for _,word in ipairs(path)do
            if value==0 then value=word
            else
                local k=mul(word,0x5bd1e995)
                value=bit.bxor(mul(value,0x5bd1e995),mul(bit.bxor(bit.rshift(k,24),k)%4294967296,0x5bd1e995))%4294967296
            end
        end
        return value
    end
    local function lookup(key)
        for _,offset in ipairs({0x12078,0xc050})do
            local header=read(manager+offset,20)
            local count=u(header,8)
            assert(count<=65536 and (count==0 or bit.band(count,count-1)==0),'Invalid configuration table capacity')
            if count~=0 then
                local entries=assert(pointer(header),'Missing configuration entries')
                local empty,multiplier=u(header,12),u(header,16)
                local start=mul(multiplier,key)
                for probe=0,count-1 do
                    local at=entries+((start+probe)%count)*48
                    local id=u(read(at,4),0)
                    if id==key then return read(at+8,24)end
                    if id==empty then break end
                end
            end
        end
    end
    return {hash=hash,lookup=lookup,boolean=function(path,default)
        local value=lookup(hash(path))
        if value and u(value,12)==7 then return value:byte(17)~=0 end
        return default
    end}
end
