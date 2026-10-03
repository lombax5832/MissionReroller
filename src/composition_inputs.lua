-- Independent mission metadata and enable-rule inputs. All reads are injected
-- so live and frozen captures use identical bounded decoding.
-- The planet model (planet_model.lua) passes its configuration and effects.
local O=...
return function(read,u,pointer,game,board,config,effects,eligible,make_environments)
    local ffi=require('ffi');local scalar=ffi.new('float[1]')
    local function word(a)return u(read(a,4),0)end
    local function count(a,limit)local n=word(a);assert(n<=limit,'Composition input count exceeds bound');return n end
    local function ptr(a)return assert(pointer(read(a,8)),'Missing composition pointer')end
    local function float(a)ffi.copy(scalar,read(a,4),4);return tonumber(scalar[0])end
    local campaign=board+O.board.campaign
    local api={}
    function api.enable(metadata,planet,operation,template,class,prefix)
        local hash=word(metadata);local enabled=read(metadata+4,1):byte()~=0
        for _,effect in ipairs(effects.collect(planet,operation,class))do
            if u(effect,24)==13 and u(effect,36)==15 and u(effect,28)==hash then enabled=effect:byte(41)~=0;break end
        end
        enabled=config.boolean({prefix,hash,0xf8d23bd2},enabled)
        if template and template~=0 then enabled=config.boolean({0x3c559dc9,template,0xf28cfc63,hash,0xf8d23bd2},enabled)end
        return enabled
    end
    function api.biome_definition(planet)
        local root=ptr(game+O.rva.ui_root)
        local manager=pointer(read(ptr(root+O.ui_root.level_controller)+O.level_controller.stamp_manager,8))
        if not manager then return nil end
        local n=count(manager+0xb0,4096)
        local values=pointer(read(manager+0x18,8))
        if n>0 then
            local keys=ptr(manager+0x20);local key=word(campaign+planet*O.campaign.definition_stride+0x18)
            for i=0,n-1 do if word(keys+i*4)==key then return pointer(read(assert(values)+i*8,8))end end
        end
        if values then return pointer(read(values,8))end
    end
    function api.biomes(planet,allowed)
        local definition=api.biome_definition(planet)
        if not definition then return {},false end
        if allowed and (allowed[1]==0 or #allowed==0) then return {},true end
        local environment=ptr(definition+0x70)
        local n=count(environment+0x28,1024);local result={}
        if n>0 then
            local entries=ptr(environment+0x20)
            for i=0,n-1 do
                local data=ptr(entries+i*0x38+0x30)
                for j=0,7 do
                    if float(data+O.biome_environment.weight+j*O.biome_environment.size)>0 then
                        local biome=read(data+O.biome_environment.id+j*O.biome_environment.size,1):byte();result[#result+1]=biome
                        for _,legal in ipairs(allowed or {})do if legal==0 or legal==biome then return result,true end end
                    end
                end
            end
        end
        return result,true
    end
    function api.mission(id,planet,operation,template,resolve_enable)
        assert(id>=0 and id<162,'Invalid mission metadata index')
        local at=game+O.rva.mission_types+id*O.mission_type.size
        local result={id=id,hash=word(at),faction=word(at+8),minimum=word(at+12),maximum=word(at+16),category=read(at+0x34,1):byte()}
        if resolve_enable then
            result.enabled=api.enable(at,planet,operation,template,0x4b,0xaf218cac)
            local allowed=ptr(at+O.mission_type.biomes);local n=count(at+O.mission_type.biome_count,256)
            result.biomes={}
            -- Native always reads the first restriction byte, even at count 0.
            if read(allowed,1):byte()==0 then result.biomes[1]=0
            else for i=0,n-1 do result.biomes[#result.biomes+1]=read(allowed+i,1):byte()end end
        end
        return result
    end
    function api.candidates(template_index,operation,planet)
        local template=game+O.rva.templates+template_index*O.template.size
        local hash=word(template);local present=api.biome_definition(planet)~=nil
        local context={faction=operation.faction,difficulty=operation.difficulty,biomes={},environment_present=present}
        local candidates,weights,rules={},{},{}
        for i=0,31 do
            local mission_hash=word(template+0x38+i*8)
            if mission_hash~=0 then
                for id=0,161 do
                    if word(game+O.rva.mission_types+id*O.mission_type.size)==mission_hash then
                        local m=api.mission(id,planet,operation.effect_id,hash,false)
                        assert(type(m.minimum)=='number' and type(m.maximum)=='number' and type(context.difficulty)=='number',
                            string.format('[COMPOSITION_INPUT] planet=%s row=%s template=%s mission=%s minimum=%s maximum=%s difficulty=%s operation_difficulty=%s',
                                tostring(planet),tostring(operation.row),tostring(template_index),tostring(id),tostring(m.minimum),
                                tostring(m.maximum),tostring(context.difficulty),tostring(operation.difficulty)))
                        if (m.faction==0 or m.faction==context.faction) and m.minimum<=context.difficulty and context.difficulty<=m.maximum and present then
                            m=api.mission(id,planet,operation.effect_id,hash,true)
                            if m.enabled then context.biomes=api.biomes(planet,m.biomes)end
                            if eligible(m,context,0)then candidates[#candidates+1]={id=id,category=m.category}end
                        end
                        if weights[id]==nil then weights[id]=float(template+0x3c+i*8)end
                        break
                    end
                end
            end
        end
        for i=0,count(template+O.template.rule_count,9)-1 do
            local at=template+O.template.rules+i*16
            rules[#rules+1]={category=read(at,1):byte(),minimum=word(at+4),maximum=word(at+8),weight=float(at+12)}
        end
        return candidates,weights,rules
    end
    local environments=make_environments and make_environments(read,u,pointer,game,board,effects,api.biome_definition)
    -- The planet's active world modifiers for an operation's effects, as
    -- definitions and hashes in native order; nil in alternate generation.
    function api.world_modifiers(planet,effect_id)
        local _,definitions,hashes=assert(environments,'Environment decoder unavailable')(planet,effect_id)
        return definitions,hashes
    end
    function api.template(index)
        assert(index>=0 and index<25,'Invalid operation template index')
        local at=game+O.rva.templates+index*O.template.size
        local result={index=index,hash=word(at),weight=float(at+0x20),modifiers={}}
        for i=0,7 do
            local hash=word(at+O.template.modifiers+i*8);if hash==0 then break end
            for j=0,12 do
                local mod=game+O.rva.operation_modifiers+j*0x50
                if word(mod)==hash then
                    result.modifiers[#result.modifiers+1]={id=hash,cost=word(mod+4),weight=float(at+O.template.modifier_weights+i*8)};break
                end
            end
        end
        return result
    end
    function api.templates(operation,planet)
        local tags=assert(environments,'Environment decoder unavailable')(planet,operation.effect_id)
        local selected={}
        for i=0,24 do
            local at=game+O.rva.templates+i*O.template.size
            if word(at+12)<=operation.difficulty and operation.difficulty<=word(at+16)
                and word(at+20)==operation.category and word(at+8)==operation.faction then
                local matches=false
                for j=0,count(at+O.template.tag_row_count,16)-1 do
                    local row=at+O.template.tag_rows+j*40;local n=count(row+36,9)
                    if n==0 or (n==1 and word(row)==0) then matches=#tags==0
                    elseif n==#tags then
                        matches=true
                        for k=0,n-1 do
                            local found=false;for _,tag in ipairs(tags)do if tag==word(row+k*4) then found=true;break end end
                            if not found then matches=false;break end
                        end
                    end
                    if matches then break end
                end
                if matches and api.enable(at,planet,operation.effect_id,nil,0x5f,0x3c559dc9) then
                    assert(operation.category~=6,'Unsupported defense-event template gate')
                    selected[#selected+1]=api.template(i)
                end
            end
        end
        return selected
    end
    function api.difficulty(difficulty,category)
        local limit=10;local value=config.lookup(config.hash({0xaf218cac,0xfaabbea9}))
        if value and u(value,12)==6 then limit=math.min(10,u(value,16))end
        assert(limit>=1,'Unsupported zero difficulty cap')
        local effective=difficulty==0 and 1 or math.min(difficulty,limit)
        local at=game+O.rva.difficulty_rows+(effective-1)*O.difficulty_row.size
        local missions=1
        if category<14 and read(game+O.rva.categories+category*0xa8+8,1):byte()~=0 then missions=word(at+O.difficulty_row.missions)end
        assert(missions<=3,'Mission count exceeds operation capacity')
        return word(at+O.difficulty_row.budget),missions
    end
    function api.effect_id(operation,planet)
        if operation.category<14 and read(game+O.rva.categories+operation.category*0xa8+9,1):byte()~=0 then
            for i=0,count(campaign+O.campaign.operation_binding_count,512)-1 do
                local at=campaign+O.campaign.operation_bindings+i*24
                if word(at)==planet and word(at+4)==operation.id then return operation.id end
            end
        end
        return 4294967295
    end
    function api.explicit(hash)
        for i=0,24 do if word(game+O.rva.templates+i*O.template.size)==hash then return api.template(i)end end
    end
    function api.extra_mission(modifier,faction)
        if faction<2 or faction>4 then return nil end
        for i=0,12 do
            local at=game+O.rva.operation_modifiers+i*0x50
            if word(at)==modifier then
                local hash=word(at+0x28+(faction-2)*4)
                if hash~=0 then
                    for id=0,161 do if word(game+O.rva.mission_types+id*O.mission_type.size)==hash then return id end end
                    error('Unknown modifier mission type')
                end
                return nil
            end
        end
        error('Unknown operation modifier')
    end
    api.effects=effects;api.config=config
    return api
end
