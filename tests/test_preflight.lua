local entry=assert(arg[1])
local writes={}
CowboyBingusModLoader={api=1,version=16,open_log=function()
    return {write=function(_,s)writes[#writes+1]=s end,flush=function()end,close=function()end}
end}
local updates=0
update=function(a)updates=updates+1;return a,nil,3,nil end
shutdown=function()return nil,7,nil end
-- A deliberately unavailable FFI must stop diagnostics without harming callbacks.
package.loaded.ffi=nil
package.preload.ffi=function()error('test FFI unavailable')end
dofile(entry)
local function pack(...)return {n=select('#',...),...}end
local r=pack(update(42))
assert(r.n==4 and r[1]==42 and r[2]==nil and r[3]==3 and r[4]==nil)
assert(MissionRerollerPreflight.status:find('PREFLIGHT_STOP',1,true))
local logs=#writes
update(43);assert(#writes==logs and updates==2)
local wrapper=update;dofile(entry);assert(update==wrapper)
local s=pack(shutdown());assert(s.n==3 and s[1]==nil and s[2]==7 and s[3]==nil)
MissionRerollerPreflight=nil;CowboyBingusModLoader.version=15
dofile(entry);assert(MissionRerollerPreflight.status=='unsupported_loader' and update==wrapper)
print('preflight lifecycle: passed')
