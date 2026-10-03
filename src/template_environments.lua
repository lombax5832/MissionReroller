-- Decode template-environment tags (177e5b0): biome, campaign effects, the
-- active world modifiers (1267460) and the operation's binding.
local O=...
return function(read,u,pointer,game,board,effects,biome_definition)
    local ffi=require('ffi')
    local function word(a)return u(read(a,4),0)end
    local function count(a,limit)local n=word(a);assert(n<=limit,'Environment input count exceeds bound');return n end
    local function ptr(a)return assert(pointer(read(a,8)),'Missing environment pointer')end
    local campaign=board+O.board.campaign
    local function world_definition(hash)
        local values=pointer(read(board+O.board.world_modifier_values,8));if not values then return nil end
        local n=count(board+O.board.world_modifier_count,4096);if n==0 then return nil end
        local ids=ptr(board+O.board.world_modifier_ids)
        for i=0,n-1 do if word(ids+i*4)==hash then return pointer(read(values+i*8,8))end end
    end
    return function(planet,operation,normal_guard)
        if read(board+O.board.alternate_generation,1):byte()~=0 then
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
        if planet<word(campaign+O.campaign.planet_count) then
            local biome=biome_definition(planet)
            if biome then array(biome,0x38,256)end
        end
        for _,effect in ipairs(effects.collect(planet,operation,0x60))do
            if u(effect,24)==13 then
                for i=0,9 do if word(game+O.rva.environment_tags+i*4)==u(effect,28) then add(i);break end end
            end
        end
        -- The active world modifiers, as 1267460 collects them: at most eight
        -- definitions in order. The caller adds each one's tags to the result.
        local present,definitions={},{}
        local function has(hash)for i=1,#present do if present[i]==hash then return true end end end
        local function keep(hash,definition)
            if normal_guard then assert(bit.band(read(definition+0x4c,1):byte(),2)==0,'Unsupported operation-suppressing world modifier')end
            present[#present+1]=hash;definitions[#definitions+1]=definition
        end
        local owner=word(campaign+O.campaign.planet_faction+planet*O.campaign.planet_stride)
        -- 12672b0: unless its flags say otherwise, a modifier on a planet held
        -- by faction 1 applies only while a campaign base lists the planet
        -- (campaign.bases, planet at +8).
        local function world(hash)
            if hash==0 then return end
            local definition=world_definition(hash)
            if not definition then return end
            if bit.band(read(definition+O.world_modifier.flags,1):byte(),1)==0 and planet<=word(campaign+O.campaign.campaign_planet_count) and owner==1 then
                local listed=false
                for i=0,count(campaign+O.campaign.base_count,1024)-1 do
                    if word(campaign+O.campaign.bases+8+i*20)==planet then listed=true;break end
                end
                if not listed then return end
            end
            if #present<8 and not has(hash) then keep(hash,definition)end
        end
        -- 12e1210: an event targets one planet, sector or owner, or every
        -- planet, and optionally only while a given owner holds the planet.
        local function applies(at)
            if planet>=word(campaign+O.campaign.planet_count) then return false end
            local kind,target,holder=read(at+0x54,1):byte(),word(at+0x58),word(at+0x5c)
            local scoped=kind==0 and target==planet or kind==1 and target==word(campaign+O.campaign.planet_region+planet*O.campaign.planet_stride)
                or kind==2 and target==owner or kind==3
            return scoped and (holder==0 or holder==owner)
        end
        -- Type 17 commands of applicable events skip 12672b0's checks and limit.
        local event_manager=ptr(game+O.rva.global_effects)
        for i=0,count(event_manager+O.global_effects.count,32)-1 do
            local at=event_manager+i*O.global_effects.size
            if applies(at) then
                for j=0,count(at+0x50,5)-1 do
                    local hash=word(at+j*16+4)
                    if read(at+j*16,1):byte()==17 and hash~=0 and not has(hash) then
                        local definition=world_definition(hash)
                        if definition then keep(hash,definition)end
                    end
                end
            end
        end
        if planet<word(campaign+O.campaign.campaign_planet_count) then
            for _,effect in ipairs(effects.collect(planet,operation,0x47))do if u(effect,24)==13 then world(u(effect,28))end end
            for i=0,count(campaign+O.campaign.planet_effect_list_count,4)-1 do
                if word(campaign+O.campaign.planet_effect_lists+i*44)==planet then world(0xd9cab761);break end
            end
            for i=0,count(board+O.board.world_marker_count,4)-1 do
                local at=board+O.board.world_markers+i*44
                if word(at)==0x2cb22ffb then if word(at+4)==planet then world(0xd9cab761)end;break end
            end
            for i=0,count(campaign+O.campaign.invasion_count,64)-1 do
                local at=campaign+O.campaign.invasions+i*0x48
                if word(at+4)==planet then world(word(game+O.rva.invasion_modifiers+math.min(word(at+8),3)*0x48));break end
            end
            local objectives=ptr(game+O.rva.objectives)
            local objective_match=false
            for i=0,count(objectives+O.objectives.count,16)-1 do
                local at=objectives+O.objectives.entries+i*O.objectives.size
                for j=0,count(at+O.objectives.entry_rows,8)-1 do
                    local row=at+j*0x50
                    -- Unrelated objective progress can change every frame.
                    -- Read it only when this objective targets our planet.
                    if word(row+0x48)==1 and word(row+0x4c)==planet then
                      local current,total=ffi.new('uint64_t[1]'),ffi.new('uint64_t[1]')
                      ffi.copy(current,read(row+8,8),8);ffi.copy(total,read(row+0x20,8),8)
                      if current[0]<total[0] then
                        if word(objectives+O.objectives.active+i*O.objectives.size)~=0 then world(0x2119a229)end
                        objective_match=true;break
                      end
                    end
                end
                if objective_match then break end
            end
            if #effects.collect(planet,operation,0x49)>0 then
                local biome=planet<word(campaign+O.campaign.planet_count) and biome_definition(planet)
                world(biome and word(biome+O.biome.kind)==11 and 0x1a667694 or 0x1ac602c5)
            end
            local state=word(campaign+O.campaign.planet_state+planet*O.campaign.planet_stride);if state>1 then state=0 end
            -- Each entry may require one modifier already present and forbid
            -- another; a flagged entry is skipped where campaign.planet_enabled is set.
            for i=0,3 do
                local at=game+O.rva.state_modifiers+state*O.state_modifiers.size+i*16;local hash=word(at)
                if hash==0 then break end
                local required,excluded=word(at+4),word(at+8)
                if (read(at+12,1):byte()==0 or read(campaign+O.campaign.planet_enabled+planet*O.campaign.planet_stride,1):byte()==0)
                    and (required==0 or has(required)) and not (excluded~=0 and has(excluded)) then world(hash)end
            end
            -- Planet overrides: type 1 adds a modifier, type 2 removes it the
            -- way the game does, moving the last entry into the freed slot.
            for i=0,count(board+O.board.planet_override_count,8)-1 do
                local at=board+O.board.planet_overrides+i*12
                if word(at+4)==planet then
                    local kind,hash=word(at+8),word(at)
                    if kind==1 then world(hash)
                    elseif kind==2 then
                        local j=1
                        while j<=#present do
                            if present[j]==hash then
                                local n=#present
                                present[j],definitions[j]=present[n],definitions[n]
                                present[n],definitions[n]=nil,nil
                            end
                            j=j+1
                        end
                    end
                end
            end
        end
        for _,definition in ipairs(definitions)do array(definition,0x60,256)end
        local binding=effects.binding(planet,operation)
        if binding then array(binding,0x20,256)end
        -- The active world modifiers also travel on the mission descriptor
        -- (1267a00), where src/side_objective_inputs.lua reads them.
        return result,definitions,present
    end
end
