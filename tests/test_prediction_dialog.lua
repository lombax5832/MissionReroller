local function up(fn,name,value,set)
    for i=1,100 do local k,v=debug.getupvalue(fn,i);if k==name then if set then debug.setupvalue(fn,i,value)end;return v end;if not k then break end end
    error('Missing upvalue '..name)
end
local ffi=require('ffi')
ffi.cdef[[typedef struct {int32_t x,y;} MRD_POINT;typedef struct {int32_t left,top,right,bottom;} MRD_RECT;]]
local logs={}
CowboyBingusModLoader={api=1,version=18,open_log=function()return {write=function(_,s)logs[#logs+1]=s end,flush=function()end,close=function()end}end}
update=function()return 1,nil,3 end;shutdown=function()return 4,nil,6 end
dofile(arg[1])
local tick=up(update,'tick');local dialog=up(tick,'dialog_tick');local M=MissionRerollerExperiment
local real_context=up(dialog,'context');local real_catalogue=up(dialog,'catalogue_for')
up(dialog,'ffi',ffi,true)
local key,mouse=false,false;local x,y=0,0
local user={GetForegroundWindow=function()return nil end,
    GetAsyncKeyState=function(k)return ((k==1 and mouse)or(k~=1 and key))and -1 or 0 end,
    GetCursorPos=function(p)p[0].x=x;p[0].y=820-y;return 1 end,
    ScreenToClient=function()return 1 end,
    GetClientRect=function(_,r)r[0].right=1200;r[0].bottom=820;return 1 end}
up(dialog,'user32',user,true)
local acquired,released=0,0;local held=false;local last_model,last_selected
up(dialog,'gate',{acquire=function()assert(not held);held=true;acquired=acquired+1;return true end,
    held=function()return held end,release=function()if held then released=released+1 end;held=false;return true end},true)
up(dialog,'panel',{clear=function()end,show=function(_,_,s,_,_,model)last_model=model;last_selected=s end},true)
up(dialog,'face',function()return {}end,true)
local planet=268
local function offered(...)
    local group={list={},set={}}
    for i,id in ipairs({...})do group.list[i]={id=id,name='Constellation '..id};group.set[id]=true end
    return group
end
local compatibility=dofile(arg[2]..'/mission_compatibility.lua')
local city_rows={29,49};local pointed;local catalogue_scope;local in_progress
local reachable={[compatibility.mask({[2]=true,[4]=true})]=true,[compatibility.mask({[4]=true,[9]=true})]=true}
up(dialog,'pointed_region',function()return pointed end,true)
up(dialog,'context',function()
    local decoded={operations={}};for i,row in ipairs(city_rows)do decoded.operations[i]={row=row,difficulty=10}end
    return {planet=planet,context='stable',fingerprint=tostring(planet),on_ship_planet=true,decoded=decoded,active=in_progress},10
end,true)
up(dialog,'catalogue_for',function(_,_,within)
    catalogue_scope=within and within.region
    return {faction=planet==268 and 2 or 3,slots=3,compatibility=compatibility,
        profiles={{masks=reachable,modifiers={}},{masks=reachable,modifiers={0x1101e25c}}},
        missions=planet==268 and {{id=2,name='Survey'},{id=4,name='Democracy'},{id=9,name='Nursery'}} or {{id=4,name='Democracy'}},
        mission_set=planet==268 and {[2]=true,[4]=true,[9]=true} or {[4]=true},
        modifiers=planet==268 and {{id=0x1101e25c,name='Atmospheric Spores'}} or {{id=0xf6f1b0c7,name='Gunship Patrols'}},
        modifier_set=planet==268 and {[0x1101e25c]=true} or {[0xf6f1b0c7]=true},forced=planet==268 and {9} or {},
        constellation_groups=planet==268 and {[0]=offered(2,4,6),[2]=offered(2,4),[4]=offered(2,6),[9]=offered()}
            or {[0]=offered(14,15),[4]=offered(14)}}
end,true)
stingray={Gui={resolution=function()return 1200,820 end},Script={temp_byte_count=function()return 0 end,set_temp_byte_count=function()end}}
local panel=up(dialog,'Panel');local now=0
local function frame(focus)now=now+0.01;dialog(focus~=false,now)end
local function toggle()key=false;frame();key=true;frame();key=false;frame()end
local function click(id)
    local target
    for _,t in ipairs(panel.layout(1200,820,last_model).targets)do if t.id==id then target=t end end
    assert(target);x=target.x+target.w/2;y=target.y+target.h/2
    mouse=false;frame();mouse=true;frame();mouse=false;frame()
end
frame();toggle();assert(acquired==1 and held)
click('start');assert(not M.request_search,'Empty filters must not start')
click(2);frame();assert(last_model.items[3].enabled==false and last_model.items[1].enabled,'Conflicts disabled; checked mission removable')
click(9);assert(not last_selected[9],'Disabled conflict must ignore clicks')
click(2);frame();assert(last_model.items[3].enabled,'Deselecting must re-enable compatible choice')
click(2);click(4);click('start')
assert(M.request_search and M.search_options.required[2] and M.search_options.required[4])
assert(not M.search_options.required[1] and M.search_options.difficulty==10)
M.request_search=nil;M.status='search_running';frame()
assert(last_model.running and last_model.difficulty_locked)
frame(false);assert(not held and not M.cancel_requested,'Alt-tab must preserve search')
toggle();assert(acquired==2 and last_model.running)
click('cancel');assert(M.cancel_requested);M.cancel_requested=nil;M.status='cancelled';frame()
click('close');frame();frame();assert(not held)
toggle();assert(acquired==3 and last_selected[2] and last_selected[4],'Reopening retains filter')
click('start');assert(M.request_search);M.request_search=nil;M.status='search_running';frame()
M.status='publication_test_passed';frame();frame();frame();assert(not held,'Success closes modal')
toggle();assert(acquired==4);click('start');assert(M.request_search,'Can start another search')
M.request_search=nil
M.status='cancelled';frame()
click('modifiers_tab');frame();click('modifier:'..0x1101e25c);frame()
assert(last_model.items[1].mode=='require')
click('modifier:'..0x1101e25c);frame();assert(last_model.items[1].mode=='exclude')
click('start');assert(M.search_options.modifiers[0x1101e25c]=='exclude')
M.request_search=nil;M.status='cancelled';frame()
-- Survey (2) and Democracy (4) are checked: one constellation page each.
local function ids()local out={};for i,item in ipairs(last_model.items)do out[i]=item.id end;return table.concat(out,' ')end
click('constellations_tab');frame()
assert(last_model.pages==2 and last_model.page==1 and ids()=='constellation_group constellation:2:2 constellation:2:4',ids())
assert(last_model.items[1].caption=='FOR: GEOLOGICAL SURVEY' and last_model.items[1].enabled==false)
assert(last_model.items[2].mode==nil and last_model.hint:find('this mission',1,true) and last_model.subtitle:find('Predator Strain',1,true))
click('constellation:2:4');frame();assert(last_model.items[3].mode=='accept' and last_model.items[2].mode==nil and last_model.ready)
click('next_page');frame()
assert(last_model.page==2 and last_model.items[1].caption=='FOR: SPREAD DEMOCRACY' and ids()=='constellation_group constellation:4:2 constellation:4:6',ids())
assert(last_model.items[2].mode==nil and last_model.items[3].mode==nil,'Each mission keeps its own constellations')
click('constellation:4:2');click('constellation:4:6');frame();assert(last_model.items[2].mode=='accept' and last_model.items[3].mode=='accept')
click('constellation:4:6');frame();assert(last_model.items[3].mode=='exclude','A second click excludes the constellation')
click('start');assert(M.request_search)
local sent=M.search_options.constellations.groups
assert(sent[2][4]=='accept' and not sent[2][2] and sent[4][2]=='accept' and sent[4][6]=='exclude' and not sent[0] and M.search_options.required[2])
M.request_search=nil;M.status='cancelled';frame()
click('constellation:4:6');frame();assert(last_model.items[3].mode==nil and sent[4][6]=='exclude','A third click clears it; the request is a copy')
-- Excluding everything a mission can draw is refused.
click('constellation:4:2');click('constellation:4:6');click('constellation:4:6');frame()
assert(last_model.items[2].mode=='exclude' and last_model.items[3].mode=='exclude' and not last_model.ready)
assert(last_model.status=='Every constellation of this mission is excluded',last_model.status)
click('start');assert(not M.request_search)
click('constellation:4:2');click('constellation:4:6');frame();assert(last_model.ready and not last_model.items[2].mode)
-- Unchecking a mission removes its page and its constellations.
click('missions_tab');frame();click(4);click('constellations_tab');frame()
assert(last_model.pages==1 and last_model.items[1].caption=='FOR: GEOLOGICAL SURVEY' and last_model.items[3].mode=='accept')
click('missions_tab');frame();click(4);click('constellations_tab');frame();click('next_page');frame()
assert(last_model.page==2 and not last_model.items[2].mode,'A re-checked mission starts without constellations')
-- A mission without drawable constellations shows an empty page.
click('missions_tab');frame();click(2);click(4);click(9);click('constellations_tab');frame()
assert(last_model.pages==1 and #last_model.items==0,'Nursery offers no constellation here')
-- Without checked missions the single page applies to any one mission.
click('missions_tab');frame();click(9);click('constellations_tab');frame()
assert(last_model.pages==1 and last_model.items[1].caption=='FOR: THE OPERATION' and ids()=='constellation_group constellation:0:2 constellation:0:4 constellation:0:6',ids())
assert(last_model.hint:find('no mission carries any',1,true))
click('constellation:0:6');click('constellation:0:2');click('constellation:0:2');frame()
assert(last_model.items[4].mode=='accept' and last_model.items[2].mode=='exclude')
click('start');assert(M.request_search and M.search_options.constellations.groups[0][6]=='accept'
    and M.search_options.constellations.groups[0][2]=='exclude' and next(M.search_options.required)==nil)
M.request_search=nil;M.status='cancelled';frame()
click('missions_tab');frame();click(2);click('start')
assert(M.request_search and next(M.search_options.constellations.groups)==nil,'Checking a mission discards the any-mission constellations')
M.request_search=nil;M.status='cancelled';frame()
click(4);click('constellations_tab');frame();click('constellation:2:2');click('next_page');frame();click('constellation:4:6')
click('modifiers_tab');frame()
planet=269;frame()
assert(not last_selected[2] and last_selected[4],'Faction changes must prune invalid mission filters')
assert(#last_model.items==1 and last_model.items[1].id=='modifier:'..0xf6f1b0c7 and not last_model.items[1].mode)
click('start');assert(next(M.search_options.modifiers)==nil,'Faction changes must prune old modifier rules')
assert(next(M.search_options.constellations.groups)==nil,'Faction changes must prune constellations and their missions')
M.request_search=nil;M.status='cancelled';frame()
click('constellations_tab');frame()
assert(last_model.pages==1 and last_model.items[1].caption=='FOR: SPREAD DEMOCRACY' and ids()=='constellation_group constellation:4:14',ids())
click('constellation:4:14');frame();assert(last_model.items[2].mode=='accept')
click('clear');frame();assert(ids()=='constellation_group constellation:0:14 constellation:0:15' and not last_model.items[2].mode,'Clear removes missions and constellations')
click('missions_tab');frame();click(4);click('modifiers_tab');frame()
M.request_search=nil
assert(M.search_options.scope==nil and last_model.subtitle:find('this planet',1,true),'Nothing pointed at: whole planet')
-- Opening the dialog on a city's operation limits it to that city.
M.request_search=nil;M.status='cancelled';frame()
local opened=acquired
click('close');frame();frame();assert(not held)
pointed=1;toggle();assert(acquired==opened+1)
assert(catalogue_scope==1 and last_model.subtitle:find('This city or megafactory only',1,true),last_model.subtitle)
assert(logs[#logs]=='MODAL_OPEN scope=region 1\n')
click('start');assert(M.request_search and M.search_options.scope.region==1 and M.search_options.required[4])
M.request_search=nil;M.status='cancelled';frame()
pointed=nil;frame();assert(catalogue_scope==1,'The city is fixed while the dialog stays open')
-- The city's operation in progress cannot be rerolled; other operations can.
local function record(row,level,where)
    local bytes={};for i=1,92 do bytes[i]=0 end
    bytes[1]=row;bytes[17]=where%256;bytes[18]=math.floor(where/256);bytes[33]=level;bytes[53]=1
    local out={};for i,value in ipairs(bytes)do out[i]=string.format('%02x',value)end
    return table.concat(out)
end
in_progress=record(49,10,planet);frame()
assert(not last_model.ready and last_model.status:find('in progress',1,true),last_model.status)
click('start');assert(not M.request_search,'An operation in progress must not start a search')
in_progress=record(49,9,planet);frame();assert(last_model.ready,'Another difficulty of the city can be rerolled')
in_progress=record(29,10,planet);frame();assert(last_model.ready,'An operation outside the city does not block it')
in_progress=record(49,10,planet+1);frame();assert(last_model.ready,'An operation on another planet does not block it')
in_progress=nil;frame()
click('close');frame();frame();toggle()
assert(catalogue_scope==nil and logs[#logs]=='MODAL_OPEN scope=planet\n','Reopening without a city returns to the planet')
click('close');frame();frame();pointed=3;toggle()
assert(catalogue_scope==nil and last_model.subtitle:find('this planet',1,true),'A city of another planet is ignored')
click('start');assert(M.request_search and M.search_options.scope==nil);M.request_search=nil;M.status='cancelled';frame()
pointed=nil
up(dialog,'dialog_release')('test cleanup');assert(not held and released==opened+3)
-- Real context logic: viewed-planet requests, retained presentation through
-- temporary cache/backend gaps, and no stale start or cross-planet display.
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local ship=268;local viewed=269;local ui_planet=269;local unavailable=false
up(real_context,'snapshot',function(preview)
    assert(preview);if unavailable then return nil,'waiting for pending backend requests' end
    return {planet=viewed,selection=word(ship)..word(viewed),fingerprint=ship..':'..viewed}
end,true)
up(real_context,'pointer',function()return 100000 end,true)
up(real_context,'game',0,true)
up(real_context,'read',function(address,n)
    assert(n==4)
    if address==100000+0x4ef8 then return word(ui_planet)end
    assert(address==100000+0x4f14);return word(10)
end,true)
up(dialog,'context',real_context,true)
jit.flush() -- Discard traces compiled against the previous injected context.
M.status='cancelled';frame();toggle();frame()
assert(#last_model.items==1 and last_model.subtitle:find('Automatons',1,true),'Remote planet faction catalogue must populate')
assert(last_model.ready,'Viewed-planet reroll must not require travel')
click('start');assert(M.request_search,'Remote Start must accept the filter');M.request_search=nil;M.status='cancelled';frame()
unavailable=true;frame()
assert(#last_model.items==1 and not last_model.ready and last_model.items[1].enabled==false,'Temporary request wait must retain rows without permitting stale actions: '..#last_model.items..' '..tostring(last_model.ready)..' '..last_model.status)
click('start');assert(not M.request_search)
unavailable=false;frame();assert(last_model.ready and #last_model.items==1)
ship=viewed;frame();assert(last_model.ready,'Same-planet reroll still works')
ui_planet=100;frame();assert(#last_model.items==0 and not last_model.ready,'Mismatched map view must not display stale options')
up(dialog,'dialog_release')('test cleanup')
-- A constellation input failure must leave mission and modifier filters usable.
local built={faction=2,missions={{id=2,name='Survey'}},constellation_groups={}}
up(real_catalogue,'api',{pointer=function()end},true)
up(real_catalogue,'make_composition_inputs',function()return {effects={},config={}}end,true)
up(real_catalogue,'make_constellation_inputs',function()error('Missing global effects')end,true)
up(real_catalogue,'FilterCatalogue',{build=function(_,_,_,_,_,_,tags)assert(tags==nil);return built end,
    constellations=function()error('Inputs failed before this call')end},true)
jit.flush()
local before=#logs
assert(real_catalogue({planet=268,board=0},10)==built and real_catalogue({planet=268,board=0},10)==built)
assert(#logs==before+1 and logs[#logs]:find('CONSTELLATION_CATALOGUE_BLOCKED',1,true) and logs[#logs]:find('Missing global effects',1,true),
    'Constellation failures are logged once and do not block the catalogue')
print('Dialog: city scope, constellation acceptance and exclusion per mission, real mouse router, filters, empty validation, map difficulty, alt-tab, cancel, close, reopen and repeat passed')
