-- Decode template-environment tags. Unported conditional world modifiers with
-- nonempty tag lists are rejected; empty tag lists cannot affect this result.
return function(read,u,pointer,game,board,effects,biome_definition)
    local ffi=require('ffi')
    local function word(a)return u(read(a,4),0)end
    local function count(a,limit)local n=word(a);assert(n<=limit,'Environment input count exceeds bound');return n end
    local function ptr(a)return assert(pointer(read(a,8)),'Missing environment pointer')end
    local campaign=board+0x101438
    local function world_definition(hash)
        local values=pointer(read(board+0x1f88f0,8));if not values then return nil end
        local n=count(board+0x1f8900,4096);if n==0 then return nil end
        local ids=ptr(board+0x1f88f8)
        for i=0,n-1 do if word(ids+i*4)==hash then return pointer(read(values+i*8,8))end end
    end
    return function(planet,operation,normal_guard)
        if read(board+0x147478,1):byte()~=0 then
            assert(not normal_guard,'Unsupported alternate generation mode');return {1}
        end
        local result,seen={},{}
        local function add(id)
            if id~=0 and id~=9 and not seen[id] and #result<9 then result[#result+1]=id;seen[id]=true end
        end
        local function array(at,offset,limit)
            local n=count(at+offset+8,limit)
            if n>0 then local ids=ptr(at+offset);for i=0,n-1 do add(word(ids+i*4))end end
        end
        if planet<word(board+0x12444c) then
            local biome=biome_definition(planet)
            if biome then array(biome,0x38,256)end
        end
        for _,effect in ipairs(effects.collect(planet,operation,0x60))do
            if u(effect,24)==13 then
                for i=0,9 do if word(game+0x21df8b8+i*4)==u(effect,28) then add(i);break end end
            end
        end
        local function world(hash)
            if hash==0 then return end
            local definition=world_definition(hash)
            if definition then
                if normal_guard then assert(bit.band(read(definition+0x4c,1):byte(),2)==0,'Unsupported operation-suppressing world modifier')end
                assert(count(definition+0x68,256)==0,
                    string.format('Unsupported conditional world-modifier environment tags: hash=%u',hash))
            end
        end
        -- 1267460's global event-condition resolver is not yet ported. A type
        -- 17 command is harmless here only if its definition has no tags.
        local event_manager=ptr(game+0x346d518)
        for i=0,count(event_manager+0x2c80,32)-1 do
            local at=event_manager+i*0x164
            for j=0,count(at+0x50,5)-1 do
                if read(at+j*16,1):byte()==17 then world(word(at+j*16+4))end
            end
        end
        if planet<word(campaign+0x6c044) then
            for _,effect in ipairs(effects.collect(planet,operation,0x47))do if u(effect,24)==13 then world(u(effect,28))end end
            for i=0,count(campaign+0x78d14,4)-1 do
                if word(campaign+0x78c68+i*44)==planet then world(0xd9cab761);break end
            end
            for i=0,count(board+0x17a14c,4)-1 do
                local at=board+0x17a09c+i*44
                if word(at)==0x2cb22ffb then if word(at+4)==planet then world(0xd9cab761)end;break end
            end
            for i=0,count(campaign+0x78c60,64)-1 do
                local at=campaign+0x77a60+i*0x48
                if word(at+4)==planet then world(word(game+0x32ef71c+math.min(word(at+8),3)*0x48));break end
            end
            local objectives=ptr(game+0x347cf08)
            local objective_match=false
            for i=0,count(objectives+0x17a40,16)-1 do
                local at=objectives+0xfc70+i*0x7e0
                for j=0,count(at+0x280,8)-1 do
                    local row=at+j*0x50
                    -- Unrelated objective progress can change every frame.
                    -- Read it only when this objective targets our planet.
                    if word(row+0x48)==1 and word(row+0x4c)==planet then
                      local current,total=ffi.new('uint64_t[1]'),ffi.new('uint64_t[1]')
                      ffi.copy(current,read(row+8,8),8);ffi.copy(total,read(row+0x20,8),8)
                      if current[0]<total[0] then
                        if word(objectives+0xfc40+i*0x7e0)~=0 then world(0x2119a229)end
                        objective_match=true;break
                      end
                    end
                end
                if objective_match then break end
            end
            if #effects.collect(planet,operation,0x49)>0 then
                local biome=planet<word(campaign+0x23014) and biome_definition(planet)
                world(biome and word(biome+0x2d0)==11 and 0x1a667694 or 0x1ac602c5)
            end
            local state=word(campaign+0x46170+planet*0x130);if state>1 then state=0 end
            -- Dependencies between world modifiers can affect their presence.
            -- Checking every nonempty source conservatively rejects unresolved
            -- nonempty tag lists, rather than silently assuming no tags.
            for i=0,3 do
                local at=game+0x32e55e0+state*0x498+i*16;local hash=word(at)
                if hash==0 then break end
                world(hash)
            end
            for i=0,count(board+0x1f897c,8)-1 do
                local at=board+0x1f891c+i*12
                if word(at+4)==planet and word(at+8)==1 then world(word(at))end
            end
        end
        local binding=effects.binding(planet,operation)
        if binding then array(binding,0x20,256)end
        return result
    end
end
