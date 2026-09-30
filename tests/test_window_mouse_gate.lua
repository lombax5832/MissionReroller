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
-- The game takes its flags back, as after a resolution change: a held gate
-- reapplies its own and counts the drift instead of failing.
flag=true;cursor=false;calls=0
assert(gate:acquire() and gate.drifts==0)
flag=true;assert(gate:held() and flag==false and gate.drifts==1 and gate.reason=='mouse_focus=true show_cursor=true reapplied')
cursor=false;assert(gate:held() and cursor==true and gate.drifts==2 and gate.reason:find('show_cursor=false',1,true))
assert(gate:held() and gate.drifts==2,'no drift, no count')
assert(gate:release() and flag==true and cursor==false,'release restores what acquire saved')
-- Flags that no longer stick, or another window, lose ownership.
local sticky=true
api.set_mouse_focus=function(handle,value)assert(handle==w);calls=calls+1;if sticky then flag=value end end
assert(gate:acquire());sticky=false;flag=true
assert(gate:held()==false and gate.drifts==1,'a reapply that does not stick fails')
sticky=true;assert(gate:release())
local identity=123
local moved=factory(api,function()return identity end)
assert(moved:acquire());identity=124
assert(moved:held()==false and moved.reason=='window identity changed')
assert(not pcall(function()moved:release()end),'a changed window is not restored')
moved:forget();identity=125;flag=true
assert(moved:acquire() and moved:release(),'forgotten handle: the gate works on the new window')
print('window mouse gate save/restore, drift reapply and identity change: passed')
