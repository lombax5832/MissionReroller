-- Bounded input decoder for the ordered, deduplicated effect list in 12df110.
local O=...
return function(read,u,pointer,game,board)
    local campaign=board+O.board.campaign
    local function word(a)return u(read(a,4),0)end
    local function count(a,max)local n=word(a);assert(n<=max,'Campaign effect count exceeds capacity');return n end
    local function ptr(a)return assert(pointer(read(a,8)),'Missing campaign pointer')end
    local manager=ptr(game+O.rva.effect_manager)
    local function special_template(hash)
        local entries=pointer(read(board+O.board.special_templates,8));if not entries then return nil end
        local n=count(board+O.board.special_template_count,4096);if n==0 then return nil end
        local ids=ptr(board+O.board.special_template_ids)
        for i=0,n-1 do if word(ids+i*4)==hash then return pointer(read(entries+i*8,8))end end
    end
    local function binding(planet,id)
        for i=0,count(campaign+O.campaign.operation_binding_count,512)-1 do
            local row=campaign+O.campaign.operation_bindings+i*24
            if word(row)==planet and word(row+4)==id then return special_template(word(row+8))end
        end
    end
    local function collect(planet,operation,class)
        local session=ptr(game+O.rva.session);local root=ptr(game+O.rva.ui_root)
        if read(session+O.session.gate,1):byte()~=0 or read(root+O.ui_root.loading_gate,1):byte()~=0 or read(root+O.ui_root.transition_gate,1):byte()~=0 then return {}end
        local total=count(manager+O.effect_manager.count,1024)
        local selected,seen={},{}
        local function add(id)
            if seen[id] or #selected>=128 then return end
            for i=0,total-1 do
                local row=manager+i*52
                if word(row)==id then
                    if class==0 or word(row+4)==class then
                        selected[#selected+1]=read(row,52);seen[id]=true
                    end
                    return
                end
            end
        end
        if planet~=4294967295 then
            assert(planet>=0 and planet<512,'Invalid effect planet')
            for i=0,count(campaign+O.campaign.planet_effect_list_count,4)-1 do
                local row=campaign+O.campaign.planet_effect_lists+i*44
                if word(row)==planet then
                    for j=0,count(row+36,8)-1 do add(word(row+4+j*4))end
                end
            end
            local stats=campaign+planet*O.campaign.planet_stride
            for i=0,count(stats+O.campaign.planet_effect_count,32)-1 do add(word(stats+O.campaign.planet_effects+i*4))end
            local definition=campaign+planet*O.campaign.definition_stride
            for i=0,count(definition+0xc8,4)-1 do add(word(definition+0xb8+i*4))end
            if operation~=4294967295 then
                local template=binding(planet,operation)
                if template then
                    local n=count(template+0x60,1024)
                    if n>0 then
                        local ids=ptr(template+0x58)
                        for i=0,n-1 do
                            local hash=word(ids+i*4)
                            for j=0,total-1 do
                                local row=manager+j*52
                                if word(row+8)==hash then add(word(row));break end
                            end
                        end
                    end
                end
            end
        end
        for i=0,count(campaign+O.campaign.event_count,8)-1 do
            local event=campaign+O.campaign.events+i*O.event.size
            local n=count(event+O.event.planet_count,32);local applies=n==0
            if not applies and planet~=4294967295 then
                for j=0,n-1 do if word(event+O.event.planets+j*4)==planet then applies=true;break end end
            end
            if applies then for j=0,count(event+O.event.effect_count,3)-1 do add(word(event+O.event.effects+j*4))end end
        end
        return selected
    end
    return {collect=collect,binding=binding}
end
