local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local up=H.up
local ffi=require('ffi')
local logs={}
CowboyBingusModLoader={api=1,version=18,open_log=function()return {write=function(_,s)logs[#logs+1]=s end,flush=function()end,close=function()end}end}
update=function()return 1,nil,3 end;shutdown=function()return 4,nil,6 end
dofile(arg[1])
local tick=up(update,'tick');local dialog=up(tick,'dialog_tick');local M=MissionRerollerExperiment
-- The pipeline's side of the handshake, played through the real session as
-- identity_probe_runtime does: take the request and report phases.
local session=up(dialog,'reroll_session')
-- held: a start the pipeline has taken from the session and not yet run.
local held_request=false
local function requested()held_request=held_request or session.take_request();return held_request end
local function drop()requested();held_request=nil end
local function take()assert(requested(),'No request to take');held_request=nil;session.advance('waiting_for_stable_inputs')end
local function options()return session.view().request end
local real_context=up(dialog,'context');local real_catalogue=up(dialog,'catalogue_for')
local key,mouse,esc=false,false,false;local x,y=0,0
local user={GetForegroundWindow=function()return nil end,
    GetAsyncKeyState=function(k)return ((k==1 and mouse)or(k==0x76 and key)or(k==0x1B and esc))and -1 or 0 end}
-- The native handles the runtimes get from the adapter on the first frame.
H.natives(update,{user32=user,game=0,api={pointer=function()end}})
-- The galactic map is the top screen with its BACK hint shown, unless a test
-- says otherwise. The runtimes read the map through the host's map screen;
-- the test replaces its reads.
local map_top,map_anchor,stack=true,{x=48,y=32,w=118,h=40,scale=1},{15}
local map=up(dialog,'map')
map.on_top=function()return map_top end
map.back_hint=function()return map_top and map_anchor or nil end
map.screens=function()return stack end
up(dialog,'cursor',{client=function()return x,820-y,1200,820 end},true)
local acquired,released=0,0;local held=false;local last_model,last_selected
up(dialog,'gate',{acquire=function()assert(not held);held=true;acquired=acquired+1;return true end,
    held=function()return held end,release=function()if held then released=released+1 end;held=false;return true end},true)
-- The packaged panel draws every model the runtime builds, into a recording engine.
local drawn={}
local function object()local o={};drawn[#drawn+1]=o;return o end
local real=up(dialog,'Panel').new({Application={worlds=function()return {1,2}end,main_world=function()return 1 end},
    World={create_screen_gui=function()drawn={};return {}end,destroy_gui=function()drawn={}end},
    Gui={resolution=function()return 1200,820 end,material=function()return {}end,
        rect=function()return object()end,update_rect=function()end,
        text=function(_,value)local o=object();o.value=value;return o end,update_text=function(_,o,value)o.value=value end,
        triangle=function()return object()end,
        text_extents=function(_,value,_,size)return {0},{#value*size*0.5},{#value*size*0.5}end},
    Material={set_scalar=function()end,set_vector2=function()end,set_vector4=function()end,set_texture=function()end},
    IdString64={from_hex=function(s)return s end},
    Vector2=setmetatable({x=function(v)return v[1]end},{__call=function(_,...)return {...}end}),
    Vector3=function(...)return {...}end,Color=function(...)return {...}end})
local function shown(value)
    for _,o in ipairs(drawn)do if o.value==value then return true end end
    return false
end
up(dialog,'panel',{clear=function()real:clear()end,show=function(_,options,s,face,pointer,model)
    last_model=model;last_selected=s;real:show(options,s,face,pointer,model)
end},true)
up(dialog,'face',function()return {font='a',material='b',atlas='c'}end,true)
local planet=268
local function offered(...)
    local group={list={},set={}}
    for i,id in ipairs({...})do group.list[i]={id=id,name='Constellation '..id..' (Tag'..id..')'};group.set[id]=true end
    return group
end
local compatibility=dofile(arg[2]..'/mission_compatibility.lua')
local city_rows={29,49};local pointed;local catalogue_scope;local in_progress
local reachable={[compatibility.mask({[2]=true,[4]=true})]=true,[compatibility.mask({[4]=true,[9]=true})]=true}
-- The operation row under the cursor: the first of the pointed city's rows.
map.pointed_row=function()return pointed and 30+pointed*10 end
up(dialog,'context',function()
    local decoded={operations={}};for i,row in ipairs(city_rows)do decoded.operations[i]={row=row,difficulty=10}end
    return {planet=planet,context='stable',fingerprint=tostring(planet),on_ship_planet=true,decoded=decoded,active=in_progress},10
end,true)
local many,many_set={},{}
for id=1,30 do many[id]={id=id,name='Mission '..id};many_set[id]=true end
up(dialog,'catalogue_for',function(_,_,within)
    catalogue_scope=within and within.region
    if planet==270 then
        return {faction=4,slots=3,missions=many,mission_set=many_set,modifiers={},modifier_set={},forced={},constellation_groups={}}
    end
    return {faction=planet==268 and 2 or 3,slots=3,compatibility=compatibility,
        profiles={{masks=reachable,modifiers={}},{masks=reachable,modifiers={0x1101e25c}}},
        missions=planet==268 and {{id=2,name='Survey'},{id=4,name='Democracy'},{id=9,name='Nursery'}} or {{id=4,name='Democracy'}},
        mission_set=planet==268 and {[2]=true,[4]=true,[9]=true} or {[4]=true},
        modifiers=planet==268 and {{id=0x1101e25c,name='Atmospheric Spores'}} or {{id=0xf6f1b0c7,name='Gunship Patrols'}},
        modifier_set=planet==268 and {[0x1101e25c]=true} or {[0xf6f1b0c7]=true},forced=planet==268 and {9} or {},
        constellation_groups=planet==268 and {[0]=offered(2,4,6),[2]=offered(2,4),[4]=offered(2,6),[9]=offered()}
            or {[0]=offered(14,15),[4]=offered(14)},
        forecast=function(tag)return {faction=2,difficulty=10,tags={9,tag},zone={[5]=2},war={}}end}
end,true)
stingray={Gui={resolution=function()return 1200,820 end},Script={temp_byte_count=function()return 0 end,set_temp_byte_count=function()end}}
local panel=up(dialog,'Panel');local now=0
local function frame(focus)now=now+0.01;dialog(focus~=false,now)end
local function toggle()key=false;frame();key=true;frame();key=false;frame()end
local function find(id)
    for _,t in ipairs(panel.layout(1200,820,last_model).targets)do if t.id==id then return t end end
end
local function click(id)
    local target=assert(find(id),id)
    x=target.x+target.w/2;y=target.y+target.h/2
    mouse=false;frame();mouse=true;frame();mouse=false;frame()
end
local function ids()local out={};for i,item in ipairs(last_model.items)do out[i]=item.id end;return table.concat(out,' ')end
local function tabs()
    local out={};for i,group in ipairs(last_model.groups)do out[i]=group.name..(group.selected and '*' or '')end
    return table.concat(out,' | ')
end
frame();toggle();assert(acquired==1 and held)
assert(last_model.section=='missions' and ids()=='2 4 9','Missions are open when the dialog opens')
assert(shown('CHOOSE WHAT THE OPERATION MUST CONTAIN') and shown('TERMINIDS') and shown('/ WHOLE PLANET') and shown('DIFFICULTY 10')
    and shown('SURVEY') and shown('0 OF 3 SLOTS') and shown('REROLL OPERATIONS') and shown('CLOSE') and not shown('CANCEL SEARCH'))
assert(last_model.faction==2 and last_model.scope=='planet' and last_model.difficulty==10 and last_model.slots==3)
assert(last_model.status=='Choose what the operation must contain' and last_model.tone=='idle' and last_model.detail=='')
assert(last_model.ready and not last_model.can_start and not last_model.can_clear and last_model.rules==0)
assert(find('start').enabled==false and find('clear').enabled==false and find('close').enabled,'Nothing set: no reroll and no clear')
assert(not find('up') and not find('down') and not find('cancel'),'Difficulty follows the map')
click('start');assert(not requested(),'Empty filters must not start')
click(2);frame()
assert(last_model.items[3].enabled and last_model.items[3].reason and last_model.items[1].mode=='require','A conflict can still be excluded')
click(9);frame();assert(not last_selected[9] and last_model.items[3].mode=='exclude','A conflicting mission goes straight to excluded')
assert(last_model.summaries.missions=='Geological Survey, not Nuke Nursery' and last_model.rules==2 and last_model.checked==1)
assert(shown('GEOLOGICAL SURVEY, NOT NUKE NURSERY') and shown('1 OF 3 SLOTS') and last_model.can_start)
click('start')
assert(requested() and options().required[2] and options().excluded[9] and not options().required[9],'Exclusions reach the request')
take();session.finish('cancelled');frame()
-- Nursery back to any; Survey cycles through excluded to any.
click(9);click(2);frame();assert(last_model.items[1].mode=='exclude' and not last_selected[2])
click(2);frame();assert(not last_model.items[1].mode and not last_model.items[3].mode and last_model.rules==0)
click(2);click(4);frame()
assert(last_model.can_start and last_model.can_clear and last_model.rules==2 and last_model.checked==2)
assert(last_model.status=='Ready to search' and last_model.detail=='Rerolls every unstarted operation of the campaign')
assert(last_model.summaries.missions=='Geological Survey, Spread Democracy' and last_model.summaries.modifiers=='Any'
    and last_model.summaries.enemies=='Any')
-- One section is open at a time; the open one closes on a click.
click('section:missions');frame();assert(last_model.section==nil and #last_model.items==0 and last_selected[2])
click('section:modifiers');frame();assert(last_model.section=='modifiers' and ids()=='modifier:'..0x1101e25c)
click('section:modifiers');frame();assert(last_model.section==nil)
click('section:missions');frame();assert(last_model.section=='missions' and ids()=='2 4 9')
click('start')
assert(requested() and options().required[2] and options().required[4])
assert(not options().required[1] and options().difficulty==10)
take();frame()
assert(last_model.running and last_model.status=='Checking planet data' and last_model.step==1)
session.advance('capture_retry');frame();assert(last_model.status=='Retrying changed planet data' and last_model.step==1)
session.advance('search_running');session.progress(2731);frame()
assert(last_model.running and last_model.locked and not last_model.can_start and not last_model.can_clear)
assert(last_model.status=='Searching seeds' and last_model.tone=='busy' and last_model.step==2)
assert(last_model.detail=='2,731 of 1,000,000 seeds searched',last_model.detail)
assert(shown('SEARCHING SEEDS') and shown('2,731 OF 1,000,000 SEEDS SEARCHED') and shown('2 SEARCH SEEDS') and shown('CANCEL SEARCH')
    and shown('GEOLOGICAL SURVEY, SPREAD DEMOCRACY') and shown('2 OF 3 SLOTS'))
assert(find('cancel').enabled and find('close').enabled and find('clear').enabled==false and not find('start'))
assert(find(2).enabled==false and find(9).enabled==false and find('section:modifiers').enabled,'A search locks the rows, not the sections')
click(2);assert(last_selected[2],'A running search ignores the rows')
click('clear');assert(last_selected[2] and last_selected[4],'A running search cannot be cleared')
click('section:modifiers');frame();assert(last_model.section=='modifiers' and find('modifier:'..0x1101e25c).enabled==false)
click('modifier:'..0x1101e25c);frame();assert(last_model.items[1].mode==nil)
click('section:missions');frame()
for _,case in ipairs({{'search_waiting_backend',2,'Waiting for game requests'},{'search_matched',2,'Checking planet data'},
    {'publication_pending',3,'Refreshing operations'},{'selection_pending',4,'Opening matching operation'}})do
    session.advance(case[1]);frame();assert(last_model.running and last_model.step==case[2] and last_model.status==case[3],case[1])
end
session.progress(0);frame()
frame(false);assert(not held and not session.take_cancel(),'Alt-tab must preserve search')
toggle();assert(acquired==2 and last_model.running)
click('cancel');assert(session.take_cancel());session.finish('cancelled');frame()
assert(not last_model.running and last_model.status=='Search cancelled' and last_model.tone=='idle' and last_model.can_start)
click('section:modifiers');frame()
click('close');frame();frame();assert(not held)
toggle();assert(acquired==3 and last_selected[2] and last_selected[4],'Reopening retains filter')
assert(last_model.section=='missions','Reopening starts on the missions')
click('start');assert(requested());take();session.advance('search_running');frame()
session.finish('publication_test_passed');frame();frame();frame();assert(not held,'Success closes modal')
toggle();assert(acquired==4);click('start');assert(requested(),'Can start another search')
take();session.finish('cancelled');frame()
click('section:modifiers');frame();click('modifier:'..0x1101e25c);frame()
assert(last_model.items[1].mode=='require' and last_model.summaries.modifiers=='1 rule' and last_model.rules==3)
assert(last_model.status=='Ready to search','Editing the request discards the last report')
click('modifier:'..0x1101e25c);frame();assert(last_model.items[1].mode=='exclude')
click('start');assert(options().modifiers[0x1101e25c]=='exclude')
take();session.finish('cancelled');frame()
-- Survey (2) and Democracy (4) are checked: one group of constellations each.
click('section:enemies');frame()
assert(tabs()=='Geological Survey* | Spread Democracy' and last_model.group==2 and ids()=='constellation:2:2 constellation:2:4',tabs()..' '..ids())
assert(last_model.items[1].name=='Constellation 2 *' and last_model.items[2].name=='Constellation 4 *'
    and last_model.items[1].title=='Constellation 2','The game tag is not displayed; tags a map stamp can add are marked')
do
    -- Without Know Your Constellation a marked row's tooltip is its note alone.
    local function logged(prefix)for _,line in ipairs(logs)do if line:sub(1,#prefix)==prefix then return line end end end
    assert(logged('KYC_ROSTER off: not installed'),'The first frame logs the missing roster')
    local tip=assert(last_model.tooltip(last_model.items[1]))
    assert(tip.title=='Constellation 2' and tip.note and not tip.large,'A note-only tooltip')
    -- With it, the mission's units through its exported roster, in its tag IDs.
    local asked
    EnemyIntelligence={revision='v4.0',status='ready',roster={api=1,build=25480438,
        from_native=function(tag)return tag==1 and 31 or tag-1 end,
        forecast=function(snapshot,zone)asked={snapshot=snapshot,zone=zone}
            return {large={{name='Bile Titans',ticks=7}},small={'Warriors','Scavengers'}}end}}
    tip=last_model.tooltip(last_model.items[2])
    assert(tip.large[1].name=='Bile Titans' and tip.large[1].ticks==7 and tip.small[2]=='Scavengers' and tip.with=='Predator Strain')
    assert(table.concat(asked.snapshot.tags,',')=='8,3' and asked.snapshot.faction==2 and asked.snapshot.difficulty==10 and asked.zone[5]==2)
    assert(logged('KYC_ROSTER ready revision v4.0 build 25480438'))
    -- Its build check failing hides the units; a roster that raises turns them off.
    EnemyIntelligence.status='disabled: Unsupported game module'
    assert(not last_model.tooltip(last_model.items[2]).large and logged('KYC_ROSTER off: revision v4.0 disabled: Unsupported game module'))
    EnemyIntelligence.status='ready';EnemyIntelligence.roster.forecast=function()error('broken table')end
    assert(not last_model.tooltip(last_model.items[1]).large and logged('KYC_ROSTER_FAILED'))
    EnemyIntelligence.roster.forecast=function()return {large={},small={}}end
    assert(not last_model.tooltip(last_model.items[2]).large,'Off for the rest of the session')
    EnemyIntelligence=nil
end
assert(find('group:2').enabled and find('group:4').enabled and not find('previous_page') and not find('next_page'))
assert(last_model.items[1].mode==nil and last_model.note==nil and last_model.forced=='Predator Strain',last_model.forced)
click('constellation:2:4');frame();assert(last_model.items[2].mode=='accept' and last_model.items[1].mode==nil and last_model.ready)
assert(last_model.summaries.enemies=='1 rule')
click('group:4');frame()
assert(tabs()=='Geological Survey | Spread Democracy*' and last_model.group==4 and ids()=='constellation:4:2 constellation:4:6',tabs()..' '..ids())
assert(last_model.items[1].mode==nil and last_model.items[2].mode==nil,'Each mission keeps its own constellations')
click('constellation:4:2');click('constellation:4:6');frame();assert(last_model.items[1].mode=='accept' and last_model.items[2].mode=='accept')
click('constellation:4:6');frame();assert(last_model.items[2].mode=='exclude','A second click excludes the constellation')
assert(last_model.summaries.enemies=='3 rules')
click('start');assert(requested())
local sent=options().constellations.groups
assert(sent[2][4]=='accept' and not sent[2][2] and sent[4][2]=='accept' and sent[4][6]=='exclude' and not sent[0] and options().required[2])
take();session.advance('search_running');frame()
assert(last_model.group==4 and find('constellation:4:2').enabled==false and find('group:2').enabled,'A search locks the rules, not the groups')
click('constellation:4:2');frame();assert(last_model.items[1].mode=='accept')
click('group:2');frame();assert(last_model.group==2 and ids()=='constellation:2:2 constellation:2:4')
click('group:4');frame()
session.finish('cancelled');frame()
click('constellation:4:6');frame();assert(last_model.items[2].mode==nil and sent[4][6]=='exclude','A third click clears it; the request is a copy')
-- Excluding everything a mission can draw is refused.
click('constellation:4:2');click('constellation:4:6');click('constellation:4:6');frame()
assert(last_model.items[1].mode=='exclude' and last_model.items[2].mode=='exclude' and not last_model.ready and not last_model.can_start)
assert(last_model.status=='Every constellation of this mission is excluded' and last_model.tone=='bad',last_model.status)
assert(find('start').enabled==false)
click('start');assert(not requested())
click('constellation:4:2');click('constellation:4:6');frame();assert(last_model.ready and not last_model.items[1].mode)
-- Unchecking a mission removes its group and its constellations.
click('section:missions');frame();click(4);click('section:enemies');frame()
assert(tabs()=='Geological Survey*' and last_model.items[2].mode=='accept')
click('section:missions');frame();click(4);click('section:enemies');frame()
assert(tabs()=='Geological Survey* | Spread Democracy','A group that went away is not selected again')
click('group:4');frame()
assert(last_model.group==4 and not last_model.items[1].mode and not last_model.items[2].mode,'A re-checked mission starts without constellations')
-- A mission without drawable constellations shows an empty list.
click('section:missions');frame();click(2);click(2);click(4);click(9);click('section:enemies');frame()
assert(tabs()=='Nuke Nursery*' and #last_model.items==0,'Nursery offers no constellation here')
-- Without checked missions the single group applies to any one mission.
click('section:missions');frame();click(9);click('section:enemies');frame()
assert(tabs()=='Any mission*' and last_model.group==0 and ids()=='constellation:0:2 constellation:0:4 constellation:0:6',ids())
assert(last_model.note=='Check a mission to set its own enemies' and last_model.summaries.modifiers=='1 rule')
click('constellation:0:6');click('constellation:0:2');click('constellation:0:2');frame()
assert(last_model.items[3].mode=='accept' and last_model.items[1].mode=='exclude' and last_model.can_start)
click('start');assert(requested() and options().constellations.groups[0][6]=='accept'
    and options().constellations.groups[0][2]=='exclude' and next(options().required)==nil)
take();session.finish('cancelled');frame()
click('section:missions');frame();click(2);click('start')
assert(requested() and next(options().constellations.groups)==nil,'Checking a mission discards the any-mission constellations')
take();session.finish('cancelled');frame()
click(4);click('section:enemies');frame();click('constellation:2:2');click('group:4');frame();click('constellation:4:6')
click('section:modifiers');frame()
planet=269;frame()
assert(not last_selected[2] and last_selected[4],'Faction changes must prune invalid mission filters')
assert(#last_model.items==1 and last_model.items[1].id=='modifier:'..0xf6f1b0c7 and not last_model.items[1].mode)
assert(last_model.status=='Unavailable filters cleared for this planet/difficulty' and last_model.tone=='warn' and last_model.faction==3)
click('start');assert(next(options().modifiers)==nil,'Faction changes must prune old modifier rules')
assert(next(options().constellations.groups)==nil,'Faction changes must prune constellations and their missions')
take();session.finish('cancelled');frame()
click('section:enemies');frame()
assert(tabs()=='Spread Democracy*' and ids()=='constellation:4:14' and last_model.forced=='',ids())
click('constellation:4:14');frame();assert(last_model.items[1].mode=='accept')
click('clear');frame();assert(ids()=='constellation:0:14 constellation:0:15' and not last_model.items[1].mode,'Clear removes missions and constellations')
assert(not next(last_selected) and not last_model.can_start and not last_model.can_clear and find('start').enabled==false)
assert(last_model.status=='Choose what the operation must contain')
drop()
click('start');assert(not requested(),'A cleared request must not start')
-- More missions than one page holds.
planet=270;frame();click('section:missions');frame()
assert(last_model.pages==2 and last_model.page==1 and #last_model.items==24 and last_model.items[24].id==24)
assert(find('previous_page').enabled and find('next_page').enabled)
click('next_page');frame();assert(last_model.page==2 and #last_model.items==6 and last_model.items[1].id==25)
click('next_page');frame();assert(last_model.page==2)
click(30);frame();assert(last_selected[30] and last_model.summaries.missions=='Destroy Exospire')
click('previous_page');frame();assert(last_model.page==1 and #last_model.items==24)
click('previous_page');frame();assert(last_model.page==1)
click('next_page');frame();click(30);frame();assert(not next(last_selected))
planet=269;frame();assert(last_model.pages==1 and last_model.page==1 and ids()=='4' and not find('next_page'))
click(4);click('section:modifiers');frame()
assert(options().scope==nil and last_model.scope=='planet','Nothing pointed at: whole planet')
-- Opening the dialog on a city's operation limits it to that city.
session.finish('cancelled');frame()
-- Closing the dialog cancels a running search, and says so when it reopens.
click('start');assert(requested());take();session.advance('search_running');frame()
click('close');assert(session.take_cancel(),'Close cancels the search')
session.finish('cancelled');frame();frame();assert(not held)
toggle();assert(held and not last_model.running and last_model.status=='Search cancelled' and last_model.can_start)
local opened=acquired
click('close');frame();frame();assert(not held)
pointed=1;toggle();assert(acquired==opened+1)
assert(catalogue_scope==1 and last_model.scope=='city' and last_model.section=='missions',last_model.scope)
assert(logs[#logs]=='MODAL_OPEN scope=region 1 key=F7 screens=15\n',logs[#logs])
click('start');assert(requested() and options().scope.region==1 and options().required[4])
take();session.finish('cancelled');frame()
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
assert(not last_model.can_start and last_model.tone=='warn' and not last_model.locked and find('start').enabled==false and find(4).enabled)
click('start');assert(not requested(),'An operation in progress must not start a search')
in_progress=record(49,9,planet);frame();assert(last_model.ready,'Another difficulty of the city can be rerolled')
in_progress=record(29,10,planet);frame();assert(last_model.ready,'An operation outside the city does not block it')
in_progress=record(49,10,planet+1);frame();assert(last_model.ready,'An operation on another planet does not block it')
in_progress=nil;frame()
click('close');frame();frame();toggle()
assert(catalogue_scope==nil and logs[#logs]=='MODAL_OPEN scope=planet key=F7 screens=15\n','Reopening without a city returns to the planet')
click('close');frame();frame();pointed=3;toggle()
assert(catalogue_scope==nil and last_model.scope=='planet','A city of another planet is ignored')
click('start');assert(requested() and options().scope==nil);take();session.finish('cancelled');frame()
pointed=nil
up(dialog,'dialog_release')('test cleanup');assert(not held and released==opened+3)
-- Real context logic: viewed-planet requests, retained presentation through
-- temporary cache/backend gaps, and no stale start or cross-planet display.
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local ship=268;local viewed=269;local ui_planet=269;local unavailable=false;local guest=false
up(real_context,'snapshot',function(preview)
    assert(preview);if guest then return nil,'Only the host can reroll operations' end
    if unavailable then return nil,'waiting for pending backend requests' end
    return {planet=viewed,selection=word(ship)..word(viewed),fingerprint=ship..':'..viewed,sc=3}
end,true)
map.viewed=function()return ui_planet,10 end
up(dialog,'context',real_context,true)
jit.flush() -- Discard traces compiled against the previous injected context.
session.finish('cancelled');frame();toggle();frame()
assert(#last_model.items==1 and last_model.faction==3,'Remote planet faction catalogue must populate')
assert(last_model.ready,'Viewed-planet reroll must not require travel')
click('start');assert(requested(),'Remote Start must accept the filter');take();session.finish('cancelled');frame()
-- A short gap in the planet data is not shown: nothing is dimmed, the status
-- stays, and the request can be edited.
local before={status=last_model.status,tone=last_model.tone,detail=last_model.detail}
unavailable=true;frame()
assert(#last_model.items==1 and last_model.ready and last_model.items[1].enabled~=false and not last_model.items[1].reason,
    'A short gap must not dim the rows: '..last_model.status)
assert(not last_model.locked and last_model.can_start and last_model.can_clear and last_model.faction==3 and last_selected[4])
assert(last_model.status==before.status and last_model.tone==before.tone and last_model.detail==before.detail,
    'A short gap must not change the status: '..last_model.status)
assert(not last_model.running and find(4).enabled and find('start').enabled and find('clear').enabled)
click(4);frame();assert(not last_selected[4] and not last_model.can_start,'The request is edited during a gap')
click(4);frame();assert(last_selected[4] and last_model.can_start and last_model.status=='Ready to search')
click('section:modifiers');frame()
assert(last_model.section=='modifiers' and #last_model.items==1 and find(last_model.items[1].id).enabled)
click('section:missions');frame()
-- A start during the gap waits, shown as a search in its first step. It never
-- starts from the retained data.
click('start');frame()
assert(not requested(),'Retained data must not start a search')
assert(last_model.running and last_model.locked and last_model.step==1 and last_model.tone=='busy'
    and last_model.status=='Checking planet data' and last_model.detail=='0 of 1,000,000 seeds searched',last_model.status)
assert(find('cancel').enabled and not find('start') and find(4).enabled==false and find('clear').enabled==false)
assert(shown('CANCEL SEARCH') and shown('1 CHECK PLANET') and shown('CHECKING PLANET DATA'))
local searches=#logs
unavailable=false;frame()
assert(requested() and options().required[4] and options().difficulty==10,'Fresh data starts the waiting search')
assert(#logs==searches+1 and logs[#logs]=='DIALOG_SEARCH planet=269 region=all difficulty=10 players=3\n' and last_model.running)
take();session.finish('cancelled');frame()
-- Cancel, close, another planet and a lasting gap each drop a waiting start.
unavailable=true;frame();click('start');frame();assert(last_model.running)
click('cancel');frame()
assert(not last_model.running and not session.take_cancel() and last_model.status=='Search cancelled' and last_model.can_start)
unavailable=false;frame();frame();assert(not requested(),'A cancelled request does not start later')
unavailable=true;frame();click('start');frame();assert(last_model.running)
click('close');frame();frame();assert(not held and not session.take_cancel())
unavailable=false;toggle();frame()
assert(held and not requested() and not last_model.running and last_model.status=='Search cancelled')
unavailable=true;frame();click('start');frame();assert(last_model.running)
ui_planet=100;frame();assert(not last_model.running and #last_model.items==0,'Another planet drops the waiting start')
ui_planet=269;unavailable=false;frame()
assert(not requested() and last_model.status=='Planet changed; search not started' and last_model.tone=='warn' and last_model.can_start)
unavailable=true;frame();click('start');frame();assert(last_model.running)
frame(false);toggle();unavailable=false;frame()
assert(not requested() and not last_model.running and last_model.status=='Search cancelled','Alt-tab drops the waiting start')
-- A gap that lasts is reported, and still does not block the request.
unavailable=true;for _=1,160 do frame()end
assert(last_model.status=='Updating planet data. Your choices are kept' and last_model.tone=='warn')
assert(not last_model.locked and last_model.can_start and find(4).enabled and find('start').enabled)
click('start');frame();assert(last_model.running and last_model.status=='Checking planet data')
for _=1,1010 do frame()end
assert(not last_model.running and not requested() and last_model.status=='Updating planet data. Your choices are kept')
unavailable=false;frame()
assert(not requested() and last_model.status=='Planet data did not arrive; try again' and last_model.tone=='warn')
assert(last_model.ready and #last_model.items==1 and last_model.can_start and not last_model.locked)
-- Refreshed data of the same planet keeps the page; only its content counts.
planet=270;ship=267;frame()
assert(last_model.pages==2 and last_model.page==1 and last_selected[4])
click('next_page');frame();assert(last_model.page==2)
ship=266;frame();assert(last_model.page==2 and #last_model.items==6,'A refresh must not turn the page back')
planet=269;ship=268;frame();assert(last_model.pages==1 and last_model.page==1 and #last_model.items==1)
ship=viewed;frame();assert(last_model.ready,'Same-planet reroll still works')
-- A guest of a lobby is told so at once. It is not a gap: nothing is offered
-- and nothing waits.
guest=true;frame()
assert(last_model.status=='Only the host can reroll operations' and last_model.tone=='warn',last_model.status)
assert(last_model.locked and #last_model.items==0 and not last_model.can_start and not last_model.running and last_selected[4])
assert(find('start').enabled==false and find('close').enabled and shown('ONLY THE HOST CAN REROLL OPERATIONS'))
click('start');frame();assert(not requested() and not last_model.running,'A guest cannot queue a search')
guest=false;frame();assert(last_model.ready and #last_model.items==1 and last_model.can_start and not requested())
ui_planet=100;frame();assert(#last_model.items==0 and not last_model.ready,'Mismatched map view must not display stale options')
assert(last_model.locked and last_model.faction==nil and not last_model.can_start and find('start').enabled==false and find('close').enabled)
ui_planet=600;frame()
assert(last_model.status=='Open a planet on the war table first' and last_model.tone=='warn' and #last_model.items==0 and last_model.locked)
assert(shown('OPEN A PLANET ON THE WAR TABLE FIRST') and shown('NO PLANET') and shown('NO PLANET CHOSEN') and not shown('DEMOCRACY'))
up(dialog,'dialog_release')('test cleanup')
-- The key hint follows the BACK hint every focused frame, whether or not the
-- dialog is open, disappears with the map or the focus, and a failure
-- disables it for the session without stopping the mod.
local hint_anchor,hint_last,hint_shown,hint_cleared,hint_keys={x=48,y=32,w=118,h=40,scale=1},nil,0,0,nil
up(dialog,'hint',{show=function(_,anchor,f,keys)assert(f.font=='a');hint_last=anchor;hint_shown=hint_shown+1;hint_keys=keys end,
    clear=function()hint_last=nil;hint_cleared=hint_cleared+1 end},true)
map.back_hint=function()return hint_anchor end
frame();assert(hint_last==hint_anchor and hint_shown==1 and hint_keys==nil,'Hint shown on the map with the dialog closed, with the chord')
toggle();assert(hint_last==hint_anchor and hint_shown>1,'Hint stays while the dialog is open')
-- The MODS tab binding opens and closes the dialog, only while focused. A
-- bound key replaces F7 and reaches the hint; unbound or unreadable, F7 works.
local pulse,bound_keys,bind_state,stepped=false,nil,'unbound',0
up(dialog,'binding',{step=function()stepped=stepped+1;return pulse end,keys=function()return bound_keys,bind_state end},true)
frame();assert(hint_keys==nil and held,'Unbound: the hint shows F7')
toggle();assert(not held,'Unbound: F7 closes the dialog')
bound_keys,bind_state='g','bound';frame();assert(hint_keys=='g','The bound key reaches the hint')
toggle();assert(not held,'Bound: F7 does nothing')
pulse=true;frame();pulse=false;frame();assert(held,'The binding opens the dialog')
pulse=true;frame();pulse=false;frame();assert(not held,'The binding closes the dialog')
pulse=true;frame();frame();frame();assert(held,'A held binding toggles once');pulse=false;frame()
bound_keys,bind_state=nil,'unknown';toggle();assert(not held,'An unreadable binding keeps F7')
local before=stepped;frame(false);assert(stepped==before,'The binding is not read without focus')
frame();assert(stepped==before+1)
-- Off the map, as with the options or ESC menu above it, neither key acts,
-- and the screens are logged once per distinct stack.
map.back_hint=function()return map_top and map_anchor or nil end
local logged=#logs
map_top,stack=false,{15,26};toggle();assert(not held,'F7 ignored off the map')
assert(#logs==logged+1 and logs[#logs]=='SHORTCUT_IGNORED screens=15,26\n',logs[#logs])
pulse=true;frame();pulse=false;frame();assert(not held and #logs==logged+1,'The binding is ignored off the map, logged once')
map_top,stack=true,{15};toggle();assert(held,'Back on the map F7 opens it')
map_top=false;toggle();assert(held,'Off the map F7 does not close it either')
key=true;frame();map_top=true;frame();key=false;frame();assert(held,'A key held while returning to the map does not act')
map_anchor=nil;toggle();assert(held,'The map without its BACK hint does not act');map_anchor={x=48,y=32,w=118,h=40,scale=1}
toggle();assert(not held)
up(dialog,'binding',nil,true);frame();assert(hint_keys==nil)
map.back_hint=function()return hint_anchor end
hint_anchor=nil;frame();assert(hint_last==nil and hint_cleared>=1,'Hint cleared when the BACK hint is gone')
hint_anchor={x=48,y=32,w=118,h=40,scale=1};frame();assert(hint_last==hint_anchor)
-- Losing focus clears the hint in the frame and again when the dialog is released.
local cleared=hint_cleared;frame(false);assert(hint_last==nil and hint_cleared>cleared,'Hint cleared without focus')
frame();assert(hint_last==hint_anchor)
map.back_hint=function()error('Widget moved')end
local logged,shown_before=#logs,hint_shown
frame();assert(hint_last==nil and #logs==logged+1 and logs[#logs]:find('HINT_BLOCKED',1,true) and logs[#logs]:find('Widget moved',1,true),
    'A hint failure is logged once')
frame();frame();assert(hint_shown==shown_before and #logs==logged+1,'A blocked hint is never retried')
assert(not tostring(M.status):find('STOPPED',1,true),'A hint failure does not stop the mod')
up(dialog,'dialog_release')('hint cleanup')
-- Input ownership lost while the dialog is open, as after a resolution
-- change: the dialog closes and restores the window, the mod goes on, and
-- the shortcut opens it again.
local gate=up(dialog,'gate');local real_held=gate.held;local lost=false
gate.held=function()return real_held() and not lost end
gate.reason='mouse_focus=true show_cursor=true reapplied'
toggle();assert(held,'Dialog open before the loss')
local opened_logs,released_before=#logs,released
lost=true;frame()
assert(not held and released==released_before+1,'The window was restored')
assert(logs[opened_logs+1]:find('MODAL_INPUT_LOST',1,true) and logs[opened_logs+1]:find('ownership lost',1,true)
    and logs[opened_logs+1]:find('reapplied',1,true),'The loss and the flags are logged')
assert(logs[#logs]:find('MODAL_RELEASE input ownership lost',1,true),logs[#logs])
assert(not tostring(M.status):find('STOPPED',1,true),'The mod continues')
lost=false;gate.reason=nil;toggle();assert(held,'The dialog opens again')
-- With no planet shown that message yields to the planet prompt; it is kept for when one is.
assert(up(dialog,'report')=='Dialog closed: input ownership lost. Press the shortcut to reopen','The loss is reported')
up(dialog,'dialog_release')('ownership cleanup');gate.held=real_held
-- Escape closes the dialog. The game's Escape mappings are taken away while
-- it is open and come back only once the key is up, so the war table never
-- sees the press. A simulated gate stands in for src/escape_gate.lua.
local escape_gate,holds,releases={held=false,actions=''},0,0
function escape_gate:hold()assert(not self.held);holds=holds+1;self.held=true;self.actions='1:9';return 1 end
function escape_gate:release()if not self.held then return 0,0 end;self.held=false;releases=releases+1;return 1,0 end
up(up(dialog,'restore_escape'),'escape',escape_gate,true)
local logged=#logs
toggle();assert(held and escape_gate.held and holds==1,'Opening takes Escape from the game')
assert(logs[logged+1]=='ESCAPE_HELD mappings=1 actions=1:9\n' and logs[logged+2]:find('MODAL_OPEN',1,true),logs[logged+1])
esc=true;frame();frame();assert(not held,'Escape closes the dialog')
frame();assert(escape_gate.held and releases==0,'Escape stays away from the game while it is down')
esc=false;frame();assert(not escape_gate.held and releases==1 and logs[#logs]=='ESCAPE_RESTORED buckets=1\n','Released, Escape goes back to the game')
esc=true;frame();esc=false;frame();assert(not held and holds==1,'Escape does nothing with the dialog closed')
esc=true;toggle();assert(held,'Escape held while opening does not close it');esc=false;frame();assert(held)
esc=true;frame();frame();esc=false;frame();assert(not held and not escape_gate.held and holds==2)
toggle();esc=true;frame();frame();assert(not held and escape_gate.held)
toggle();assert(held and holds==3,'Reopened before Escape is up, the map stays as held')
esc=false;frame();assert(held and escape_gate.held,'Releasing Escape with the dialog open keeps it')
esc=true;frame();frame();esc=false;frame();assert(not held and not escape_gate.held)
toggle();esc=true;frame(false);assert(not held and not escape_gate.held,'Losing focus gives Escape back at once')
esc=false;frame()
-- Clicking CLOSE or pressing F7 gives Escape back as well.
toggle();click('close');frame();assert(not held and not escape_gate.held)
toggle();toggle();assert(not held and not escape_gate.held and releases==6)
-- A map that cannot be changed leaves Escape to the game for the session;
-- the key still closes the dialog.
escape_gate.hold=function()error('Unexpected binding map size',0)end
logged=#logs
toggle();assert(held and logs[logged+1]:find('ESCAPE_BLOCKED Unexpected binding map size',1,true),logs[logged+1])
esc=true;frame();frame();esc=false;frame();assert(not held,'Escape still closes the dialog')
toggle();toggle();assert(not held)
local blocked=0;for i=logged+1,#logs do if logs[i]:find('ESCAPE_BLOCKED',1,true)then blocked=blocked+1 end end
assert(blocked==1,'A blocked map is not retried')
assert(not tostring(M.status):find('STOPPED',1,true),'A blocked map does not stop the mod')
up(up(dialog,'restore_escape'),'escape',nil,true);up(up(dialog,'hold_escape'),'escape_blocked',false,true)
-- The time of day: the viewed planet's sky decides the start, and a city
-- waits for its side. The sky and its arithmetic are src/day_night.lua's
-- (tests/test_day_night.lua); here they are stubbed.
local sky_view=up(dialog,'sky_view')
local real_day_night=up(sky_view,'DayNight')
local wait,loads=0,0
up(sky_view,'DayNight',{BAND=30,WANTED=9000,duration=real_day_night.duration,war_time=function()return 1000 end,
    load=function(_,_,_,p,ref)loads=loads+1;return {planet=p,sky={seed=ref.seed},day_length=56553,buffer=9000}end,
    wait=function(_,nodes,side)assert(side=='night' and #nodes==2,'the city missions');return wait end},true)
map.sky=function()return {env=0,seed=77,viewer=0}end
up(dialog,'context',function()
    local decoded={operations={{row=29,difficulty=10,missions={{level_index=1}}},
        {row=49,difficulty=10,missions={{level_index=5},{level_index=6}}}}}
    return {planet=planet,context='stable',fingerprint='time',decoded=decoded},10
end,true)
-- Compiled traces keep the replaced functions as constants.
jit.flush()
pointed=nil;toggle();assert(held)
click('clear');click('section:time');frame()
assert(ids()=='time:any time:day time:night' and last_model.items[1].mode=='chosen')
click('time:night');frame();frame()
assert(last_model.summaries.time=='Night' and last_model.rules==1 and last_model.items[3].mode=='chosen')
assert(last_model.can_start and last_model.status=='Ready to search' and shown('HOLDS 2H 30M / DAY 15H 42M'),last_model.status)
local sky_logged=false
for _,line in ipairs(logs)do if line:find('DAYNIGHT_PLANET planet='..planet..' day_s=56553 buffer_s=9000',1,true)then sky_logged=true end end
assert(loads==1 and sky_logged,'The sky is loaded once and logged')
toggle();pointed=1;toggle()
wait=6000;now=now+2;frame()
assert(last_model.scope=='city' and not last_model.can_start and last_model.status=='Night here in 1h 40m' and last_model.tone=='bad',last_model.status)
click('start');assert(not requested(),'A city without night must not start')
wait=nil;now=now+2;frame();assert(last_model.status=='No city here stays in night for 2h 30m',last_model.status)
wait=0;now=now+2;frame();assert(last_model.can_start,last_model.status)
click('start');assert(requested() and options().time=='night' and options().scope.region==1)
take();session.finish('cancelled');frame();assert(not last_model.running)
click('clear');assert(up(dialog,'filters').time==nil,'Clear resets the time of day')
toggle();assert(not held);pointed=nil
up(sky_view,'DayNight',real_day_night,true)
-- A constellation input failure must leave mission and modifier filters usable.
local built={faction=2,missions={{id=2,name='Survey'}},constellation_groups={}}
-- The planet model returns the catalogue and the tag input failure
-- (tests/test_planet_model.lua); the dialog logs the failure once.
up(real_catalogue,'Planet',{bind=function(_,_,_,_,board,planet)
    assert(board==0 and planet==268)
    return {catalogue=function(s,d)assert(s.planet==268 and d==10);return built,'Missing global effects' end}
end},true)
jit.flush()
local before=#logs
assert(real_catalogue({planet=268,board=0},10)==built and real_catalogue({planet=268,board=0},10)==built)
assert(#logs==before+1 and logs[#logs]:find('CONSTELLATION_CATALOGUE_BLOCKED',1,true) and logs[#logs]:find('Missing global effects',1,true),
    'Constellation failures are logged once and do not block the catalogue')
assert(not table.concat(logs):find('SESSION_',1,true),'Every phase change followed the session rules')
print('Dialog: sections, groups, paging, locked states, city scope, constellation acceptance and exclusion per mission, real mouse router, filters, empty request, map difficulty, alt-tab, cancel, close, Escape, reopen, repeat, key hint and time of day passed')
