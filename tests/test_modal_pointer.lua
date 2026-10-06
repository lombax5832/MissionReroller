local create=dofile(assert(arg[1]))
local owns=false;local acquired,released=0,0
local gate={acquire=function()owns=true;acquired=acquired+1;return true end,
    held=function()return owns end,release=function()owns=false;released=released+1;return true end}
local m=create(gate);local targets={{id='toggle',x=10,y=10,w=20,h=20},{id='disabled',x=40,y=10,w=20,h=20,enabled=false}}
assert(not m:step(15,15,true,targets));m:open()
assert(not m:step(15,15,true,targets),'opening held click must not activate')
assert(not m:step(15,15,false,targets))
assert(not m:step(15,15,true,targets));assert(m:step(15,15,false,targets)=='toggle')
m:step(15,15,true,targets);assert(not m:step(0,0,false,targets),'drag out cancels')
m:step(0,0,true,targets);assert(not m:step(15,15,false,targets),'drag in cannot activate')
m:step(45,15,true,targets);assert(not m:step(45,15,false,targets),'disabled control')
-- The right button clicks only cycle targets, and says so; a press with
-- both buttons down is dropped until both are up.
local rows={{id='row',x=10,y=10,w=20,h=20,cycle=true},{id='start',x=40,y=10,w=20,h=20}}
local function click(x,left,right)m:step(x,15,left,rows,right);return m:step(x,15,false,rows,false)end
local action,reverse=click(15,false,true);assert(action=='row' and reverse==true,'Right click reverses a row')
action,reverse=click(15,true,false);assert(action=='row' and reverse==false,'Left click goes forwards')
assert(not click(45,false,true),'Right click ignores a plain button')
assert(click(45,true,false)=='start','Left click still presses it')
m:step(15,15,true,rows,false);m:step(15,15,true,rows,true);m:step(15,15,false,rows,true)
assert(not m:step(15,15,false,rows,false),'Both buttons cancel the press')
m:step(15,15,false,rows,true);m:step(15,15,true,rows,true);m:step(15,15,true,rows,false)
assert(not m:step(15,15,false,rows,false),'Left held after a chord stays cancelled')
m:step(15,15,false,rows,true);m:step(0,0,false,rows,false);assert(not m:step(0,0,false,rows,false),'Right drag out cancels')
m:step(15,15,true,targets);m:close();assert(owns)
m:step(15,15,false,targets);assert(owns,'consume closing release')
m:step(15,15,false,targets);assert(not owns and released==1)
m:open();m:abort();assert(not owns and released==2)
local bad=create({acquire=function()return false end})
assert(not pcall(function()bad:open()end) and not bad.opened)
print('modal pointer ownership, click and close-release tests: passed')
