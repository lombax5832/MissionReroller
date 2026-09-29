-- Capture the supported 11e44d0 campaign-event path without native calls.
-- Reads definitions, never generated operation rows. Unsupported resolution
-- paths fail explicitly rather than guessing event eligibility.
return function(read,u,pointer)
    local ffi=require('ffi')
    return function(board,planet,definitions,include_base)
        local parts={}
        local function take(address,size)
            if size==0 then return ''end
            local bytes=read(address,size)
            assert(type(bytes)=='string' and #bytes==size,'Short special-operation input')
            parts[#parts+1]=string.format('%.0f',tonumber(ffi.cast('uintptr_t',address)))..':'..size..':'..bytes
            return bytes
        end
        local function count(address,limit)
            local n=u(take(address,4),0)
            assert(n<=limit,'Special-operation input count exceeds bound')
            return n
        end
        local function ptr(address)
            local value=pointer(take(address,8))
            return value
        end
        local campaign=board+0x101438
        local n=count(campaign+0x70048,512)
        local relevant={}
        for i=0,n-1 do
            local at=campaign+0x6c048+i*32
            -- Progress counters elsewhere in this record are not generation
            -- inputs and can change independently of the selected planet.
            if u(take(at,4),0)==planet and take(at+20,1):byte()~=0 then
                local fields=take(at+4,8)
                relevant[#relevant+1]={id=u(fields,0),faction=u(fields,4)}
            end
        end
        local output={}
        if #relevant==0 then return output,table.concat(parts)end
        local enabled=take(campaign+0x46050+planet*0x130,1):byte()~=0
        local limit=count(definitions+0xa1834,8)
        local bindings=take(campaign+0x23018,count(campaign+0x26018,512)*24)
        local templates=ptr(board+0x1f8908)
        if not templates then return output,table.concat(parts)end
        local total=count(board+0x1f8918,4096)
        local ids_pointer=ptr(board+0x1f8910)
        assert(total==0 or ids_pointer,'Missing special template IDs')
        local ids=total>0 and take(ids_pointer,total*4) or ''
        for _,event in ipairs(relevant)do
            local template_id
            for at=0,#bindings-24,24 do
                if u(bindings,at)==planet and u(bindings,at+4)==event.id then
                    template_id=u(bindings,at+8);break
                end
            end
            local definition
            if template_id then
                for i=0,total-1 do
                    if u(ids,i*4)==template_id then definition=ptr(templates+i*8);break end
                end
            end
            if definition then
                -- Faction 1 invokes an additional campaign resolver; not ported.
                assert(event.faction~=1,'Unsupported special faction-resolution path')
                if event.faction~=0 and enabled and event.id<limit then
                    local bounds=take(definition+0x30,8)
                    local minimum,maximum=math.max(1,u(bounds,0)),math.min(10,u(bounds,4))
                    if minimum<=maximum then
                        local item={id=event.id,minimum=minimum,maximum=maximum}
                        if include_base then item.faction=event.faction;item.definition=definition end
                        output[#output+1]=item
                    end
                end
            end
        end
        return output,table.concat(parts)
    end
end
