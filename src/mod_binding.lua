-- The reroll shortcut on Mod Bindings Menu's MODS tab, so the player can
-- rebind it in the game's own options. The binding is registered lazily,
-- read every frame like a key, and its bound key is named for the hint
-- beside BACK. The menu has no default keys for automatic bindings, so the
-- runtime uses F8 while this binding has none, and without the menu.
local B={}
B.ID,B.LABEL,B.CATEGORY='ipodalexei.mission_reroller.reroll','Reroll operations','Mission Reroller'
-- Steam build 25480438, as Mod Bindings Menu v2.0 reads them: the game's
-- input owner, and its 256-bucket map of live bindings. A bucket is
-- {u32 action code, u32 count, 16 x 20-byte mappings}; a mapping's first
-- byte holds the device in its low nibble and the input kind in its high
-- nibble, and the input index is the u16 at offset 4. Indices run across
-- devices: DualSense 0-15, Xbox 16-31, mouse 32-48, then keyboard keys as
-- 49 plus the Windows virtual-key code (tab 58, escape 76, right 88).
B.INPUT_OWNER,B.BINDING_MAP,B.BUCKETS,B.BUCKET=0x347cf18,686800,256,328
B.KEYBOARD,B.MOUSE,B.BUTTON,B.KEYBOARD_BASE=3,4,4,49
-- env: read(address,n) and pointer(address) that fail by raising, u(bytes,offset),
-- game (module base), menu() returning the ModBindingsMenu global or nil,
-- keyboard (stingray.Keyboard or nil), emit(line).
function B.new(env)
    local self={status='absent',reason=nil,ready=false}
    local code,bucket,last_blob,last_keys
    -- Version 2.0 keeps its records in the state upvalue of register_binding
    -- and does not report the native action through its API.
    local function registry_code(menu)
        local getupvalue=type(debug)=='table' and debug.getupvalue
        if type(getupvalue)~='function' then return nil end
        for i=1,60 do
            local name,value=getupvalue(menu.register_binding,i)
            if name==nil then break end
            if type(value)=='table' and type(value.registry)=='table' then
                local record=value.registry[B.ID]
                if type(record)=='table' and type(record.group)=='number' and type(record.action)=='number' then
                    return record.group*65536+record.action
                end
                return nil
            end
        end
        return nil
    end
    local function register(menu)
        local slot=(tonumber(menu.version) or 1)>=2 and 0 or 2
        local ok,accepted,reason=pcall(menu.register_binding,B.ID,B.LABEL,slot,{category=B.CATEGORY})
        if ok and accepted==true then
            self.status='registered'
            local found,value=pcall(registry_code,menu)
            code=found and value or nil
            env.emit('BINDING_REGISTERED '..B.ID..(code and ' action '..math.floor(code/65536)..':'..code%65536 or ' action unknown'))
        else
            self.status,self.reason='failed',tostring(ok and reason or accepted)
            env.emit('BINDING_FAILED '..self.reason)
        end
    end
    -- Whether the binding is activated this frame. Registers on the first
    -- frame the menu is present; a refused registration is not retried.
    function self:step()
        local menu=env.menu()
        if type(menu)~='table' or menu.api~=1 or type(menu.register_binding)~='function' then return false end
        if self.status=='absent' then register(menu) end
        if self.status~='registered' then return false end
        local ok,down=pcall(menu.is_down,B.ID)
        if not ok then self.status,self.reason='failed',tostring(down);env.emit('BINDING_FAILED '..self.reason);return false end
        self.ready=down~=nil
        return down==true
    end
    local function find_bucket()
        local owner=env.pointer(env.game+B.INPUT_OWNER)
        local buckets=env.pointer(owner+B.BINDING_MAP)
        if env.u(env.read(owner+B.BINDING_MAP+8,4),0)~=B.BUCKETS then return nil end
        local heads=env.read(buckets,B.BUCKETS*B.BUCKET)
        for i=0,B.BUCKETS-1 do
            if env.u(heads,i*B.BUCKET)==code then return buckets+i*B.BUCKET end
        end
        return nil
    end
    local function decode(blob)
        local count=env.u(blob,4)
        if count>16 then return nil end
        local keys,other={},false
        for i=0,count-1 do
            local at=8+i*20
            local first=blob:byte(at+1)
            local device,kind=first%16,math.floor(first/16)%16
            if kind==B.BUTTON then
                local index=blob:byte(at+5)+blob:byte(at+6)*256
                if device==B.KEYBOARD then
                    local vk=index-B.KEYBOARD_BASE
                    local name
                    if vk>=1 and vk<=255 and env.keyboard and type(env.keyboard.button_name)=='function' then
                        local ok,value=pcall(env.keyboard.button_name,vk)
                        if ok and type(value)=='string' and value~='' then name=value end
                    end
                    keys[#keys+1]=name or ('KEY '..vk)
                elseif device==B.MOUSE then keys[#keys+1]='MOUSE '..(index-32+1)
                else other=true end
            end
        end
        if #keys>0 then return table.concat(keys,' / ') end
        if other then return 'CONTROLLER' end
        return false
    end
    -- The bound keys' names and 'bound', or nil and 'unbound' when the
    -- binding has no keys, or nil and 'unknown' while the menu is absent,
    -- not ready, or the binding's native action or map cannot be read. Only
    -- read once the menu reports native input ready, after it has removed
    -- developer defaults.
    function self:keys()
        if self.status~='registered' or not self.ready or not code then return nil,'unknown' end
        local ok,keys=pcall(function()
            if not bucket or env.u(env.read(bucket,4),0)~=code then bucket=find_bucket() end
            if not bucket then return nil end
            local blob=env.read(bucket,B.BUCKET)
            if blob==last_blob then return last_keys end
            last_blob,last_keys=blob,decode(blob)
            return last_keys
        end)
        if not ok then bucket,last_blob,last_keys=nil,nil,nil;return nil,'unknown' end
        if keys==nil then return nil,'unknown' end
        if keys==false then return nil,'unbound' end
        return keys,'bound'
    end
    return self
end
return B
