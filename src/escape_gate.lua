-- Takes Escape away from the game while the reroll dialog is open, so the
-- key closes the dialog instead of going BACK on the war table. Keyboard
-- input reaches the game whatever the dialog does; what the game does with
-- a key comes from its live binding map (src/mod_binding.lua describes it).
-- Holding removes every keyboard Escape mapping from the map's buckets and
-- remembers each changed bucket; releasing writes each one back, but only
-- if the bucket still holds what was written, so a change made by the game
-- or Mod Bindings Menu in between is never overwritten.
-- env: buckets() returning the first bucket's address after checking the
-- map, read(address,n) and write(address,bytes) that fail by raising,
-- u(bytes,offset). No other engine calls: tests drive it on a fake map.
local E={ESCAPE=76,KEYBOARD=3,BUTTON=4,BUCKETS=256,BUCKET=328,MAPPING=20,SLOTS=16}
function E.escape(mapping)
    local first=mapping:byte(1)
    return first%16==E.KEYBOARD and math.floor(first/16)%16==E.BUTTON
        and mapping:byte(5)+mapping:byte(6)*256==E.ESCAPE
end
-- The bucket without its Escape mappings, the rest kept in order, or nil
-- when it has none. Freed slots are zeroed; slots past the old count are kept.
function E.strip(blob,u)
    local count=u(blob,4)
    assert(count<=E.SLOTS,'Binding bucket count out of range')
    local kept,removed={},0
    for i=0,count-1 do
        local mapping=blob:sub(9+i*E.MAPPING,8+(i+1)*E.MAPPING)
        if E.escape(mapping)then removed=removed+1 else kept[#kept+1]=mapping end
    end
    if removed==0 then return nil end
    local n=#kept
    local head=blob:sub(1,4)..string.char(n%256,math.floor(n/256)%256,0,0)
    return head..table.concat(kept)..string.rep('\0',removed*E.MAPPING)..blob:sub(9+count*E.MAPPING),removed
end
function E.new(env)
    local self={held=false,actions=nil,removed=0}
    local saved
    -- Removes Escape everywhere and returns the number of mappings removed,
    -- 0 when the game binds nothing to it. Raises before writing anything
    -- when the map cannot be read.
    function self:hold()
        assert(not self.held,'Escape already held')
        local base=env.buckets()
        local heads=env.read(base,E.BUCKETS*E.BUCKET)
        local changes,actions,removed={},{},0
        for i=0,E.BUCKETS-1 do
            local blob=heads:sub(i*E.BUCKET+1,(i+1)*E.BUCKET)
            local stripped,n=E.strip(blob,env.u)
            if stripped then
                local code=env.u(blob,0)
                changes[#changes+1]={address=base+i*E.BUCKET,before=blob,after=stripped}
                actions[#actions+1]=math.floor(code/65536)..':'..code%65536
                removed=removed+n
            end
        end
        -- Held before the first write, so a failed write still leaves the
        -- buckets already written for release to put back.
        saved={};self.held,self.actions,self.removed=true,table.concat(actions,','),removed
        for _,c in ipairs(changes)do
            -- The action code at +0 is never written.
            env.write(c.address+4,c.after:sub(5))
            saved[#saved+1]=c
        end
        return removed
    end
    -- Puts back each bucket still as written. Returns the buckets restored
    -- and the buckets left alone because they changed.
    function self:release()
        if not self.held then return 0,0 end
        local restored,skipped=0,0
        for _,c in ipairs(saved)do
            if env.read(c.address,E.BUCKET)==c.after then
                env.write(c.address+4,c.before:sub(5));restored=restored+1
            else skipped=skipped+1 end
        end
        saved=nil;self.held=false
        return restored,skipped
    end
    return self
end
return E
