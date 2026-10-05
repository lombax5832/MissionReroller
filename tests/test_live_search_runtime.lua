local function up(fn,key,value,set)
    for i=1,100 do local k,v=debug.getupvalue(fn,i);if k==key then if set then debug.setupvalue(fn,i,value)end;return v end;if not k then break end end
    error('Missing upvalue '..key)
end
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function put(s,at,v)return s:sub(1,at)..v..s:sub(at+#v+1)end
local function raw(s)return(s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local logs={}
CowboyBingusModLoader={api=1,version=18,open_log=function()return {write=function(_,s)logs[#logs+1]=s end,flush=function()end,close=function()end}end}
update=function()return 1,nil,3 end;shutdown=function()return 4,nil,6 end
dofile(arg[1]);local tick=up(update,'tick');local advance=up(tick,'advance_live_publication')
local match=up(up(tick,'advance_prediction_search'),'on_search_match')
local game,board=0x10000000,0x20000000
local O=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua').offsets((arg[0]:match('^(.*[/\\])') or '')..'../src')
local selection=word(268)..word(268)..word(4294967295)..word(4294967295)..word(0)
local before={board=board,planet=268,seed=11,selection=selection,active=string.rep('00',92),fingerprint='before',context='same'}
local p={row=0,id=1,seed=888,difficulty=10,category=0,faction=2,explicit_hash=0,template_index=3,modifiers={},valid=true,
    missions={{native_type=59,seed=1,level_index=1},{native_type=81,seed=2,level_index=2},{native_type=65,seed=3,level_index=3}}}
local bytes=string.rep('\0',110*92);bytes=put(bytes,36,word(2))
local actual={row=0,operation_id=1,seed=888,difficulty=10,template_index=3,missions=p.missions}
local after={board=board,planet=268,seed=22,selection=selection,active=before.active,fingerprint='after',context='same',operations=bytes,decoded={operations={actual},highlighted_operation=0}}
local live=before;local canonical=11;local writes,notifications,selected=0,0,0;local difficulty=10;local displayed_planet=268
up(match,'snapshot',function(viewed)assert(viewed==true,'Publication must use viewed-planet snapshots');return live end,true)
-- The map UI shows the planet and difficulty, through the host's map screen.
up(match,'map').viewed=function()return displayed_planet,difficulty end
up(match,'read',function(address,n)
    if address==board+O.board.selection_context then return selection:sub(1,8)end
    if address==board+O.board.seed then return word(canonical)end
    if address==board+O.board.active_operation then return string.rep('\0',92)end
    error('Unexpected read '..address)
end,true)
up(match,'ownership',function(b)assert(b==board);return 'owner'end,true)
-- The code publication relies on is checked through the host before each use.
local verified={}
up(match,'verify_code',function(names)for _,name in ipairs(names)do verified[name]=(verified[name] or 0)+1 end end,true)
local partial=false
up(match,'write_seed',function(b,seed)
    assert(b==board);writes=writes+1;canonical=seed
    if partial then partial=false;error('Simulated partial publication')end
end,true)
up(match,'notify',function(b)assert(b==board);notifications=notifications+1;live=canonical==22 and after or before end,true)
up(advance,'select_match',function(s)
    assert(s==after);selected=selected+1
    up(advance,'selector',{started=1,context='same',planets=s.selection:sub(1,8)},true)
    up(advance,'ui_selection',{confirmed=function()return true end,commit=function()end,restore=function()end},true)
end,true)
-- A run reaches publication from the search. Open it in the session first,
-- as the capture does, once the idle pipeline has settled the last.
local session=up(tick,'reroll_session');local on_match=match
match=function(...)session.settle();session.advance('waiting_for_stable_inputs');session.advance('search_matched');return on_match(...)end
local job={baseline=before,seed=22,operation=p,operations={p}}
match(job,0);assert(writes==1 and notifications==1 and MissionRerollerExperiment.status=='publication_pending')
for _,name in ipairs({'select_operation','select_campaign_row','selection_dispatch','selection_listener','map_click'})do
    assert(verified[name]==1,'Publication checks '..name..' first')
end
advance('tick',1);assert(selected==1 and MissionRerollerExperiment.status=='publication_test_passed')
match(job,2);assert(writes==1,'Only one publication per test session')
local function reset()
    up(on_match,'publication_used',false,true);live=before;canonical=11
end
reset();difficulty=9;match(job,0);assert(writes==1 and MissionRerollerExperiment.status=='publication_blocked');difficulty=10
reset();displayed_planet=4294967295;match(job,0)
assert(writes==1 and MissionRerollerExperiment.status=='publication_blocked')
assert(table.concat(logs):find('Keep the viewed planet open',1,true),'Closed map must report planet, not difficulty')
assert(not up(on_match,'publication_used'),'Closed map must not consume publication allowance')
displayed_planet=268
reset();actual.seed=999;match(job,0);advance('tick',1)
assert(canonical==11 and writes==3 and selected==1 and MissionRerollerExperiment.status=='publication_restored');actual.seed=888
reset();match(job,0);advance('cancel',1);assert(canonical==11 and writes==5 and selected==1)
reset();partial=true;match(job,0);assert(canonical==11 and writes==7 and MissionRerollerExperiment.status=='publication_failed')
reset();match(job,0);canonical=33
assert(not pcall(advance,'cancel',1) and canonical==33,'Restoration must not overwrite an external seed')
-- In game the refused restoration stops the mod; here the run ends and the test goes on.
up(advance,'transaction',nil,true);session.finish('publication_failed')
-- A different user filter must be checked at publication, and the dialog can
-- publish again after a completed attempt without a process restart.
reset();MissionRerollerExperiment.dialog_enabled=true
p.missions={{native_type=28,seed=1,level_index=1}};actual.missions=p.missions
job.rules={required={[4]=true}}
local prior=writes
match(job,0);advance('tick',1);assert(writes==prior+1 and MissionRerollerExperiment.status=='publication_test_passed')
live=before;canonical=11
match(job,2);advance('tick',3);assert(writes==prior+2 and MissionRerollerExperiment.status=='publication_test_passed')
local existing=up(up(tick,'on_prediction_ready'),'on_existing_match')
session.advance('waiting_for_stable_inputs');existing(after,p,4);advance('tick',4)
assert(writes==prior+2 and MissionRerollerExperiment.status=='publication_test_passed','Existing match must select without seed writes')
reset();job.rules.modifiers={[0x1101e25c]='require'}
match(job,0);assert(writes==prior+2 and MissionRerollerExperiment.status=='publication_blocked','Publication must enforce custom modifier rules')
job.rules.modifiers={[0x1101e25c]='exclude'}
match(job,0);advance('tick',1);assert(writes==prior+3 and MissionRerollerExperiment.status=='publication_test_passed')
reset();job.rules.modifiers=nil;job.rules.constellations={groups={[4]={[4]='accept'}}}
match(job,0);assert(writes==prior+3 and MissionRerollerExperiment.status=='publication_blocked','Unresolved constellations must not publish')
p.missions[1].tags={[2]=true}
match(job,0);assert(writes==prior+3 and MissionRerollerExperiment.status=='publication_blocked','Publication must enforce constellation rules')
p.missions[1].tags={[4]=true}
match(job,0);advance('tick',1);assert(writes==prior+4 and MissionRerollerExperiment.status=='publication_test_passed')
job.rules.constellations=nil;p.missions[1].tags=nil;prior=prior+1
reset();job.scope={region=1};local unchanged=writes
match(job,0);assert(writes==unchanged and MissionRerollerExperiment.status=='publication_blocked','Publication must enforce the city')
job.scope=nil
-- Primary/ship planet differs; publication and confirmation must use the
-- viewed planet while preserving both fields and the active operation.
reset();selection=word(100)..word(268)..selection:sub(9);before.selection=selection;after.selection=selection
match(job,0);advance('tick',1);assert(writes==prior+4 and MissionRerollerExperiment.status=='publication_test_passed')
reset();match(job,0)
after.selection=word(101)..selection:sub(5)
advance('tick',1);assert(canonical==11 and MissionRerollerExperiment.status=='publication_restored','Unexpected primary planet change must reject result')
after.selection=selection
local a,b,c=shutdown();assert(a==4 and b==nil and c==6)
assert(not table.concat(logs):find('SESSION_',1,true),'Every phase change follows the session rules: '..tostring(table.concat(logs):match('SESSION_[^%c]*')))
print('Live search: preflight, publish/verify/select, one-shot guard, mismatch rollback, cancel, partial-write recovery and external seed protection passed')
