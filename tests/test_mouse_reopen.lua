-- Real runtime and router with stubbed OS/render/memory boundaries.
local ffi=require('ffi')
_G.ffi=ffi;initialized=true
local key,focused,mouse=false,true,false
local acquired,released=0,0
local user={GetForegroundWindow=function()return nil end,
 GetWindowThreadProcessId=function(_,p)p[0]=focused and 1 or 2 end,
 GetAsyncKeyState=function(k)return ((k==1 and mouse) or (k~=1 and key)) and -32768 or 0 end}
kernel={GetCurrentProcessId=function()return 1 end}
local now=0;api={time=function()now=now+0.1;return now end}
local board=ffi.cast('uint8_t *',0x20000000);game=board
pointer=function()return board end
read=function(_,n)return string.rep('\0',n)end
u=function(_,at)return at==20 and 1 or 15 end
snapshot=function()return {board=board}end
emit=function()end
Search={options={}}
Panel={layout=function()return {targets={{id=1,x=0,y=0,w=100,h=100}}}end}
stingray={Gui={resolution=function()return 640,480 end},Script={temp_byte_count=function()return 0 end,set_temp_byte_count=function()end}}
make_router=dofile(assert(arg[2]))
update=function()return 'original',nil end
local function up(fn,name,value)
 for i=1,100 do local k,v=debug.getupvalue(fn,i);if not k then break end
  if k==name then if value~=nil then debug.setupvalue(fn,i,value)end;return v end
 end;error('missing '..name)
end
dofile(assert(arg[1]))
local tick=up(update,'tick')
up(tick,'user',user)
up(tick,'cursor',{client=function()return 50,430,640,480 end})
up(tick,'panel',{clear=function()end,show=function()end})
up(tick,'face',function()return {}end)
up(tick,'gate',{acquire=function()acquired=acquired+1;return true end,
 held=function()return true end,release=function()released=released+1;return true end})
local function step()assert(update()=='original')end
step();key=true;step();assert(acquired==1)
key=false;step();mouse=true;step();mouse=false;step()
assert(up(tick,'checks')[1])
key=true;step();key=false;step();step()
key=true;step();assert(acquired==2,'normal close permanently disabled reopening')
assert(up(tick,'checks')[1],'selection lost on reopen')
focused=false;step();focused=true;key=false;step();key=true;step()
assert(acquired==3,'focus-loss close permanently disabled reopening')
print('mouse runtime reopen and selection preservation: passed')
