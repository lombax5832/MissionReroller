local make=dofile(assert(arg[1]))
local calls=0;local confirmed=false
local adapter={select=function()calls=calls+1 end,confirm=function()return confirmed end}
local op={row=28,seed=8,operation_id=2,difficulty=10}
local s={context='same',seed=44,operations={op}}
local sel=make(adapter);sel:start(s,op,0);assert(calls==1)
assert(sel:poll(s,1)=='pending');confirmed=true;assert(sel:poll(s,2)=='selected')
assert(not pcall(function()sel:start(s,op,3)end) and calls==1)
sel=make(adapter);assert(not pcall(function()sel:start(s,{row=28,seed=9,operation_id=2,difficulty=10},0)end))
assert(calls==1,'stale match called selector')
confirmed=false;sel=make(adapter);sel:start(s,op,0);assert(sel:poll(nil,6)=='failed' and calls==2)
sel:poll(s,7);assert(calls==2)
sel=make(adapter);sel:start(s,op,0);assert(sel:poll({context='other',seed=44},1)=='failed')
print('match selection identity, confirmation, no retry, timeout and context: passed')
