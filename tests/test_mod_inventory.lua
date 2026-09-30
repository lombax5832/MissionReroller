local I=dofile(assert(arg[1]))
assert(I.global_name('mods/cowboybingus/mod_bindings_menu')=='ModBindingsMenu')
assert(I.global_name('mods/ipodalexei/mission_reroller_experiment')=='MissionRerollerExperiment')
assert(I.global_name('mods/codex/gun_calibration2')=='GunCalibration2')
-- A metatable on a mod's global must never run.
local trap=setmetatable({},{__index=function()error('metatable ran')end})
local G={
    CowboyBingusModLoader={version=17,api=1,modules={
        ['mods/cowboybingus/mod_bindings_menu']='loaded',
        ['mods/ipodalexei/mission_reroller_experiment']='loaded',
        ['mods/alomare/skip_intro_animation']='loaded',
        ['mods/cowboybingus/vehicle_stability']='not installed',
        ['mods/ipodalexei/broken']='load failed: boom\nline two',
        ['mods/ipodalexei/returns_table']='loaded'}},
    HD2ModLoader={modules={['mods/other/legacy']='loaded',['mods/alomare/skip_intro_animation']='loaded'}},
    ModBindingsMenu={api=1,VERSION='2.0'},
    MissionRerollerExperiment={version='0.21.0'},
    SkipIntroAnimation=trap,
    package={loaded={['mods/ipodalexei/returns_table']={version=3}}},
}
local lines=I.lines(G)
local expected={
    'LOADER Bingus Shared Loader version=17 api=1',
    'LOADER HD2ModLoader version=unknown api=unknown',
    'MODS started=5 other=1',
    'MOD mods/alomare/skip_intro_animation version=unknown status=loaded',
    'MOD mods/cowboybingus/mod_bindings_menu version=2.0 status=loaded',
    'MOD mods/ipodalexei/broken version=unknown status=load failed: boom | line two',
    'MOD mods/ipodalexei/mission_reroller_experiment version=0.21.0 status=loaded',
    'MOD mods/ipodalexei/returns_table version=3 status=loaded',
    'MOD mods/other/legacy version=unknown status=loaded',
}
assert(#lines==#expected,table.concat(lines,'\n'))
for i,line in ipairs(expected)do assert(lines[i]==line,lines[i]..' ~= '..line)end
-- No loader: only the count.
local empty=I.lines({})
assert(#empty==1 and empty[1]=='MODS started=0 other=0')
print('test_mod_inventory: names, versions, statuses, both loaders and metatables passed')
