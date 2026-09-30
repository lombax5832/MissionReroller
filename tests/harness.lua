-- Helpers for LuaJIT tests of an assembled entry.
-- Load with: local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local H={}

-- The closure variable `name` of fn; with set, replaces it by value.
function H.up(fn,name,value,set)
    for i=1,255 do
        local k,v=debug.getupvalue(fn,i)
        if k==name then if set then debug.setupvalue(fn,i,value)end;return v end
        if not k then break end
    end
    error('Missing upvalue '..name,2)
end

-- Hands the adapter and every runtime the native handles (api, game, ffi,
-- kernel, user32) as the adapter's initialize() would on the first frame,
-- without running it. The runtimes see nil for a key left out.
function H.natives(update,natives)
    local initialize=H.up(H.up(H.up(update,'tick'),'prepare'),'initialize')
    for i=1,255 do
        local k=debug.getupvalue(initialize,i)
        if not k then break end
        if natives[k]~=nil then debug.setupvalue(initialize,i,natives[k])end
        if k=='initialized' then debug.setupvalue(initialize,i,true)end
    end
    for _,bind in ipairs(H.up(initialize,'binders'))do bind(natives)end
end

return H
