-- Decode one operation's bounded level graph through an injected read function.
local O=...
return function(read,u,game)
    local ffi=require('ffi')
    local function address_text(address)return string.format('%.0f',tonumber(ffi.cast('uintptr_t',address)))end
    return function(definitions,operation)
        local parts={}
        local function take(address,size)
            local bytes=read(address,size);assert(bytes and #bytes==size,'Short level input')
            parts[#parts+1]=address_text(address)..':'..size..':'..bytes;return bytes
        end
        local function word(address)return u(take(address,4),0)end
        local category=operation.category
        assert(category>=0 and category==math.floor(category),'Invalid operation category')
        assert(operation.id>=0 and operation.id<256 and operation.id==math.floor(operation.id),'Invalid operation ID')
        local special=category<14 and take(game+O.rva.categories+category*0xa8+9,1):byte()~=0
        local count=word(definitions+(special and O.definitions.special_pool_count or O.definitions.pool_count))
        assert(count<=(special and 8 or 64),'Invalid level pool size')
        local levels={}
        if operation.id<count then
            local start=word(definitions+(special and O.definitions.special_pool_start or O.definitions.pool_start))
            assert(start+operation.id<512,'Level map index exceeds capacity')
            local first=word(definitions+O.definitions.level_roots+(start+operation.id)*4)
            if first~=4294967295 then
                local nodes=word(definitions+O.definitions.node_count)
                assert(nodes<=512 and first<nodes,string.format(
                    'Invalid level root: root=%u nodes=%u id=%d category=%d special=%s start=%u definitions=%s',
                    first,nodes,operation.id,category,tostring(special),start,address_text(definitions)))
                levels[1]=first
                local row=definitions+first*0x88
                local n=word(row+0x78);assert(n<=24,'Too many level edges')
                for i=0,n-1 do
                    local edge=word(row+0x18+i*4);assert(edge<12288,'Level edge outside fixed graph capacity')
                    local pair=take(definitions+O.definitions.edges+edge*0x30,8)
                    local neighbor=u(pair,0);if neighbor==first then neighbor=u(pair,4)end
                    assert(neighbor<nodes,'Invalid adjacent level')
                    local kind=word(definitions+neighbor*0x88+0x14)
                    if kind==(special and 4 or 6)then levels[#levels+1]=neighbor end
                    assert(#levels<=16,'Level candidate capacity exceeded')
                end
            end
        end
        return levels,special,table.concat(parts)
    end
end
