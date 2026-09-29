local lines={};local closed=0
CowboyBingusModLoader={api=1,version=16,open_log=function()return {
    write=function(_,s)lines[#lines+1]=s end,flush=function()end,close=function()closed=closed+1 end}end}
local function forbidden()error('Discovered API called')end
stingray={Window={set_mouse_focus=forbidden},Mouse=setmetatable({},{__index={button=forbidden}}),
    Gui={rect=forbidden},Application={worlds=forbidden}}
local update_before=function()end;update=update_before
dofile(assert(arg[1]))
local out=table.concat(lines)
assert(out:find('INVENTORY_COMPLETE',1,true),out)
assert(out:find('stingray.Mouse.metatable_index.button=function',1,true),out)
assert(out:find('stingray.Window.set_mouse_focus=function',1,true),out)
assert(update==update_before and closed==1)
dofile(arg[1]);assert(closed==1)
print('passive input inventory: passed')
