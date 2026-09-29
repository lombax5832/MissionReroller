-- HD2-Addon: mods/ipodalexei/mission_reroller_input_inventory
if rawget(_G,'MissionRerollerInputInventory') then return end
local M={read_only=true};_G.MissionRerollerInputInventory=M
local loader=rawget(_G,'CowboyBingusModLoader')
if not loader or (loader.api or 0)<1 or (loader.version or 0)<16 then M.status='unsupported_loader';return end
local log
pcall(function()log=loader.open_log('MissionRerollerInputInventory.log')end)
local function emit(s)if log then pcall(function()log:write(s..'\n');log:flush()end)end end
local function names(path,t,depth,seen)
    emit(path..'='..type(t))
    if type(t)~='table' or seen[t] then return end
    seen[t]=true
    local keys={};local count=0
    for k in next,t do
        count=count+1;assert(count<=2048,'Namespace budget exceeded')
        if type(k)=='string' and #k<=96 and k:match('^[%w_]+$') then keys[#keys+1]=k end
    end
    table.sort(keys)
    for _,k in ipairs(keys) do
        local v=rawget(t,k);emit(path..'.'..k..'='..type(v))
        if depth>0 and k=='__index' and type(v)=='table' then names(path..'.__index',v,depth-1,seen)end
    end
    local meta=getmetatable(t)
    if depth>0 and type(meta)=='table' then
        local index=rawget(meta,'__index')
        if type(index)=='table' then names(path..'.metatable_index',index,depth-1,seen)end
    end
end
local ok,err=pcall(function()
    emit('UI input inventory v0.1.0; names/types only; no engine function calls or memory access')
    local e=rawget(_G,'stingray')
    for _,n in ipairs({'Window','Application','Gui','Input','Mouse','Keyboard','UI','Noesis'}) do
        names('stingray.'..n,type(e)=='table' and rawget(e,n) or nil,2,{})
        names('global.'..n,rawget(_G,n),2,{})
    end
    emit('INVENTORY_COMPLETE')
end)
M.status=ok and 'complete' or tostring(err)
if not ok then emit('INVENTORY_FAILED '..tostring(err)) end
if log then pcall(function()log:close()end)end
