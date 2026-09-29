local factory=dofile(assert(arg[1]))
local flag=true;local calls=0;local w={}
local cursor=false
local api={get_main_window=function()return w end,
    mouse_focus=function(handle)assert(handle==w);return flag end,
    set_mouse_focus=function(handle,value)assert(handle==w);calls=calls+1;flag=value end,
    show_cursor=function(handle)assert(handle==w);return cursor end,
    set_show_cursor=function(handle,value,warp)assert(handle==w and warp==false);cursor=value end}
local gate=factory(api,function()return 123 end)
assert(gate:acquire() and not flag and gate:held())
assert(cursor)
assert(gate:release() and flag and calls==2)
assert(not cursor)
assert(gate:release() and calls==2)
flag=false
assert(not pcall(function()gate:acquire()end))
assert(calls==2,'preexisting disabled focus must not be changed')
print('window mouse gate save/restore: passed')
