-- The packaged entry logs every started mod on its first frame, once, and
-- still returns what the wrapped update returned.
local entry,version=assert(arg[1]),assert(arg[2])
local logs={}
CowboyBingusModLoader={api=1,version=18,modules={
    ['mods/ipodalexei/mission_reroller_experiment']='loading',
    ['mods/cowboybingus/mod_bindings_menu']='loaded',
    ['mods/cowboybingus/vehicle_stability']='not installed'},
    open_log=function()return {write=function(_,s)logs[#logs+1]=s end,flush=function()end,close=function()end}end}
update=function()return 1,nil,3 end
dofile(entry)
local loaded=#logs
for _,line in ipairs(logs)do assert(not line:find('^INFO  MODS? ') and not line:find('^INFO  LOADER '),'nothing is listed before the first frame')end
-- Mods that load after this one are started by the first frame.
CowboyBingusModLoader.modules['mods/ipodalexei/mission_reroller_experiment']='loaded'
ModBindingsMenu={api=1,version='2.0'}
local a,b,c=update()
assert(a==1 and b==nil and c==3,'the wrapped update keeps its results')
local want={'INFO  LOADER Bingus Shared Loader version=18 api=1\n','INFO  MODS started=2 other=0\n',
    'INFO  MOD mods/cowboybingus/mod_bindings_menu version=2.0 status=loaded\n',
    'INFO  MOD mods/ipodalexei/mission_reroller_experiment version='..version..' status=loaded\n'}
for i,line in ipairs(want)do assert(logs[loaded+i]==line,tostring(logs[loaded+i])..' ~= '..line)end
local count=#logs;update()
for i=count+1,#logs do assert(not logs[i]:find('^INFO  MODS? '),'listed once')end
print('test_mod_inventory_entry: first-frame mod list passed')
