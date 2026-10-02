-- Usage: luajit test_reroll_handshake.lua <built dialog entry> <src folder>
-- The dialog and the pipeline talk only through the reroll session. Drive the
-- real dialog and the real update tick (capture, comparison, search and
-- selection) with a fake game, and check what the dialog shows at each phase.
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local up=H.up
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local logs={}
CowboyBingusModLoader={api=1,version=18,open_log=function()return {write=function(_,s)logs[#logs+1]=s end,flush=function()end,close=function()end}end}
update=function()return 1,nil,3 end;shutdown=function()return 4,nil,6 end
dofile(arg[1])
local M=MissionRerollerExperiment
local tick=up(update,'tick');local dialog=up(tick,'dialog_tick');local ready=up(tick,'on_prediction_ready')
local advance=up(tick,'advance_live_publication');local existing=up(ready,'on_existing_match')
local session=up(tick,'reroll_session')
local ffi=require('ffi')
local now=0

-- The game: one viewed planet whose board holds an operation at row 3.
local planet_ops={{row=3,operation_id=5,seed=77,difficulty=10,missions={{native_type=0,seed=1,level_index=1}}}}
local selection=word(268)..word(268)..word(4294967295)..word(4294967295)..word(0)
local s={board=0x20000000,planet=268,seed=500,fingerprint='stable',context='same',selection=selection,
    decoded={operations=planet_ops,highlighted_operation=3}}
local composition
local probe={
    capture=function()return {fingerprint='stable',input={pool_count=35},level_graphs={},composition=composition,definitions=0x30000000}end,
    compare=function()return {passed=true,matched=30,observed=30,predicted=30,errors={}}end,
    compare_levels=function()return {passed=true,checked=72,category_draws=3,errors={}}end,
}
up(tick,'probe',probe,true)
local mouse=false
-- The native handles reach every runtime as the adapter's initialize() would hand them.
H.natives(update,{api={time=function()return now end,pointer=function()return nil end},ffi=ffi,
    kernel={GetCurrentProcessId=function()return 42 end},
    user32={GetForegroundWindow=function()return 1 end,GetWindowThreadProcessId=function(_,pid)pid[0]=42 end,
        GetAsyncKeyState=function()return 0 end}})
-- Each runtime holds the host's snapshot; the capture, the search and the publication all see this game.
local function fake_snapshot()return s end
up(tick,'snapshot',fake_snapshot,true);up(ready,'snapshot',fake_snapshot,true);up(advance,'snapshot',fake_snapshot,true)
up(tick,'observe_constellations',nil,true)
-- The search predicts boards through frozen reads; nothing here matches.
up(ready,'read',function(_,n)return string.rep('\0',n)end,true)
up(ready,'Planet',{capture=function(take)return function()take(65536,1);return {passed=true,independent_bases=true}end end,
    bind=function(take)return {predictor=function()return function(seed)
        take(65536,1)
        return {{valid=true,row=3,difficulty=10,missions={{native_type=0,seed=seed,level_index=1}}}}
    end end}end},true)
-- Selecting the matching operation writes the map UI; the fake confirms it.
up(existing,'select_match',function(snap)
    up(advance,'selector',{started=now,context=snap.context,planets=snap.selection:sub(1,8)},true)
    up(advance,'ui_selection',{confirmed=function()return true end,commit=function()end,restore=function()end},true)
end,true)

-- The dialog: a scripted router instead of the mouse, a recording panel.
local compatibility=dofile(arg[2]..'/mission_compatibility.lua')
local reachable={[compatibility.mask({[2]=true})]=true}
local catalogue={faction=2,slots=3,compatibility=compatibility,profiles={{masks=reachable,modifiers={}}},
    missions={{id=2,name='Survey'}},mission_set={[2]=true},modifiers={},modifier_set={},forced={},
    constellation_groups={[0]={list={},set={}},[2]={list={},set={}}}}
up(dialog,'context',function()return s,10 end,true)
up(dialog,'catalogue_for',function()return catalogue end,true)
-- The galactic map is the top screen; its BACK hint is not read.
local map=up(dialog,'map')
map.on_top=function()return true end
map.back_hint=function()return nil end
up(dialog,'cursor',{client=function()return 0,0,1200,820 end},true)
up(dialog,'face',function()return {font='a',material='b',atlas='c'}end,true)
local shown={}
up(dialog,'panel',{clear=function()end,show=function(_,_,_,_,_,model)
    shown[#shown+1]={status=model.status,tone=model.tone,step=model.step,running=model.running,can_start=model.can_start,detail=model.detail}
end},true)
stingray={Gui={resolution=function()return 1200,820 end},Script={temp_byte_count=function()return 0 end,set_temp_byte_count=function()end}}
local action,router
local function open()
    router={opened=true,closing=false}
    function router.step()local a=action;action=nil;return a end
    function router.close()router.opened=false end
    function router.abort()router.opened=false end
    up(dialog,'router',router,true)
end

local function frame()
    now=now+0.25;local a,b,c=update();assert(a==1 and b==nil and c==3)
    assert(not tostring(M.status):find('STOPPED',1,true),M.status)
end
local function last()return shown[#shown]end
-- Frames until the dialog shows the run's result, recording every model.
local function until_idle(limit)
    for _=1,limit or 200 do frame();if not last().running or not router.opened then return last()end end
    error('The dialog still shows a running search: '..tostring(last().status)..' phase='..session.view().phase)
end
-- Did the dialog show this status at this step, in this order?
local function saw(from,list)
    local at=from
    for _,want in ipairs(list)do
        repeat at=at+1 until at>#shown or shown[at].status==want[1] and shown[at].step==want[2] and shown[at].running
        if at>#shown then return false,want[1]end
    end
    return true
end
local function start()
    local mark=#shown
    if not up(dialog,'filters').selected[2] then action=2;frame()end
    assert(up(dialog,'filters').selected[2],'Survey checked')
    action='start';frame()
    assert(M.status=='waiting_for_stable_inputs' and not session.take_request(),'The pipeline took the request in the same frame')
    return mark
end

-- 1. No match: request, capture, comparison, search, exhausted.
open();frame();assert(last().status=='Choose what the operation must contain')
composition={passed=true,operations=1,templates=1,modifiers=1,checked=1,errors={},independent_bases=true,bases=1}
local mark=start()
session.view().request.limit=256
local result=until_idle()
local ok,missing=saw(mark,{{'Checking planet data',1},{'Searching seeds',2}});assert(ok,missing)
assert(M.status=='search_exhausted' and result.status=='No match in 256 seeds; search again to continue' and result.tone=='warn',result.status)
assert(result.can_start,'A finished search can be repeated')

-- 2. Regression: a composition pass without independent operation bases
-- cannot seed a search. It used to leave the dialog running until cancelled.
composition.independent_bases=false
mark=start()
result=until_idle(40)
assert(M.status=='composition_test_passed' and session.view().outcome=='composition_test_passed')
-- Right after an exhausted search: its report does not stand for this run.
assert(result.status=='Seed prediction unavailable for this planet' and result.tone=='bad' and result.can_start,result.status)
assert(table.concat(logs):find('LUA_SEARCH_NOT_STARTED level=true composition=true independent_bases=false',1,true))
composition.independent_bases=true

-- 3. The board already holds a match: selection opens it and the dialog closes.
planet_ops[1].missions[1].native_type=22
mark=start()
result=until_idle()
ok,missing=saw(mark,{{'Checking planet data',1},{'Opening matching operation',4}});assert(ok,missing)
assert(not router.opened,'Success closes the dialog')
assert(M.status=='publication_test_passed' and up(dialog,'report')=='Matching operation selected' and up(dialog,'report_tone')=='good')
assert(table.concat(logs):find('EXISTING_MATCH row=3 seed=500',1,true))

-- 3b. Another mod gave row 3 a new seed (Refresh Operations' F6): its
-- missions match, but no seed gives them, so it is never the match. The
-- search runs, and its frozen baseline excuses the edited row.
do
    local compare,capture=probe.compare,up(ready,'Planet').capture
    probe.compare=function()
        return {passed=false,matched=29,observed=30,predicted=30,matched_rows={5},errors={'row=3 observed=5/78/d10 predicted=5/77/d10'},
            differences={{row=3,kind='value',observed={id=5,seed=78,difficulty=10},predicted={id=5,seed=77,difficulty=10}}}}
    end
    composition={passed=false,operations=1,templates=1,modifiers=1,checked=1,errors={'row=3 base fields mismatch'},
        failed_rows={[3]=true},general=0,independent_bases=true,bases=0}
    local baselines=0
    up(ready,'Planet').capture=function(take)return function()
        take(65536,1);baselines=baselines+1
        return {passed=false,checked=1,failed_rows={[3]=true},general=0,independent_bases=true}
    end end
    local from=#logs
    open();mark=start()
    session.view().request.limit=256
    result=until_idle()
    assert(M.status=='search_exhausted' and router.opened,M.status)
    assert(s.external and s.external[3] and baselines>0,'The search revalidates with the edited row excused')
    local text=table.concat(logs,'',from+1)
    assert(not text:find('EXISTING_MATCH',1,true) and text:find('LUA_IDENTITY_EXTERNAL_EDIT row=3',1,true),text)
    probe.compare,up(ready,'Planet').capture=compare,capture
    composition={passed=true,operations=1,templates=1,modifiers=1,checked=1,errors={},independent_bases=true,bases=1}
    s.external=nil
end

-- 4. Cancel during the capture: the dialog asks, the pipeline answers.
open();planet_ops[1].missions[1].native_type=0
mark=start()
frame();assert(last().running and last().status=='Checking planet data' and last().step==1)
action='cancel';frame();frame()
assert(not last().running and last().status=='Search cancelled' and last().tone=='idle')
assert(M.status=='cancelled' and not session.take_cancel() and not session.view().running)
for _=1,12 do frame()end;assert(M.status=='cancelled','The cancelled capture never completes')

-- 5. A night-only search. Its window follows war time; a match whose side ends
-- within the buffer just before the write is passed over and the search
-- continues after it. The sky itself is tests/test_day_night.lua's.
local refreshed,confirmed=0,{}
local function stub_day_night(real)
    return {BAND=30,MARGIN=5,SLACK=60,WANTED=9000,duration=real.duration,war_time=function()return 84733000+now end,
        load=function(_,_,_,p)return {planet=p,day_length=56553,buffer=9000}end,
        checker=function(P,side)
            assert(side=='night')
            local c={side=side,planet=P}
            function c.refresh(T)assert(T>84733000);refreshed=refreshed+1 end
            -- Every 50th seed puts the operation in the night; 550 not for long.
            function c.accepts(op)return op.missions[1].seed%50==0 end
            function c.confirm(op,T)confirmed[#confirmed+1]=op.missions[1].seed;return op.missions[1].seed~=550 end
            function c.time_of_day()return 1200 end
            return c
        end}
end
local publication=up(up(tick,'advance_prediction_search'),'on_search_match')
up(ready,'DayNight',stub_day_night(up(ready,'DayNight')),true)
up(publication,'DayNight',up(ready,'DayNight'),true)
up(dialog,'sky_view',function()return {note='HOLDS 2H 30M / DAY 15H 42M'}end,true)
map.sky=function()return {env=0,seed=1,viewer=0}end
jit.flush()
local filters=up(dialog,'filters');filters.selected={};filters.time='night'
mark=#logs
action='start';frame()
result=until_idle(400)
text=table.concat(logs,'',mark+1)
assert(text:find('DAYNIGHT_SEARCH side=night day_s=56553 buffer_s=9000 band_min=30 margin_s=5 slack_s=60',1,true),text)
assert(text:find('DAYNIGHT_MATCH side=night row=3 seed=550',1,true) and text:find('holds=false',1,true),'The first match is checked')
assert(text:find('DAYNIGHT_WINDOW_CLOSED row=3 seed=550; searching on',1,true),'and passed over')
assert(text:find('first_seed=551 resumed=true',1,true),'The search continues after it')
assert(text:find('DAYNIGHT_MATCH side=night row=3 seed=600 war_time=',1,true) and text:find('minutes=level1@1200',1,true),'The next match holds')
assert(confirmed[1]==550 and confirmed[2]==600 and refreshed>0,'Checked just before the write')
assert(session.view().request.time=='night' and not tostring(M.status):find('search_',1,true),M.status)

local text=table.concat(logs)
assert(not text:find('SESSION_',1,true),'Every phase change follows the session rules: '..tostring(text:match('SESSION_[^%c]*')))
print('Reroll handshake: request, capture, search, exhausted, existing match, composition without independent bases, cancel and a night-only search passed')
