-- Immutable bytes with bounded, cooperative capture and full revalidation.
-- New branches may extend the read set; old bytes are never replaced.
return function(read,checkpoint,limits)
    local ffi=require('ffi');limits=limits or {}
    local entries,index={},{};local total=0
    local self={}
    function self.read(address,size)
        checkpoint()
        local at=tonumber(ffi.cast('uintptr_t',address))
        local key=string.format('%.0f:%d',at,size)
        local entry=index[key]
        if entry then return entry.bytes end
        assert(type(size)=='number' and size>=0 and size==math.floor(size),'Invalid frozen read size')
        assert(#entries<(limits.entries or 20000) and total+size<=(limits.bytes or 2097152),'Prediction input budget exceeded')
        local bytes=read(address,size)
        assert(type(bytes)=='string' and #bytes==size,'Short frozen prediction read')
        entry={address=address,size=size,bytes=bytes};entries[#entries+1]=entry;index[key]=entry;total=total+size
        return bytes
    end
    function self:validate()
        for _,entry in ipairs(entries)do
            checkpoint()
            assert(read(entry.address,entry.size)==entry.bytes,'Prediction inputs changed; restart search')
        end
        return #entries,total
    end
    function self:stats()return #entries,total end
    return self
end
