local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local up=H.up
local logs={};local closed=false
CowboyBingusModLoader={api=1,version=18,open_log=function()return {write=function(_,s)logs[#logs+1]=s end,flush=function()end,close=function()closed=true end}end}
update=function()return 1,nil,3 end;shutdown=function()return 4,nil,6 end
dofile(arg[1]);local tick=up(update,'tick');local ready=up(tick,'on_prediction_ready')
local ffi=require('ffi');local now,down,focused=0,false,false
local s={board=1000000,planet=100,seed=123,fingerprint='stable'}
local good=true;local match=true;local evaluations=0;local live=s;local unavailable='map unavailable'
local narrowed,complete=0,0;local first
local function limited(limit)MissionRerollerExperiment.search_options={difficulty=10,required={[1]=true,[2]=true,[3]=true},limit=limit}end
up(tick,'probe',{},true)
H.natives(update,{api={pointer=function()return nil end,time=function()return now end},
    ffi=ffi,kernel={GetCurrentProcessId=function()return 42 end},
    user32={GetForegroundWindow=function()return 1 end,GetWindowThreadProcessId=function(_,pid)pid[0]=focused and 42 or 1 end,
        GetAsyncKeyState=function()return down and -1 or 0 end}})
local function snapshot()return live,unavailable end
up(tick,'snapshot',snapshot,true);up(ready,'snapshot',snapshot,true)
up(ready,'read',function(_,n)return string.rep('\0',n)end,true)
up(ready,'composition_factory',function(take)return function()take(65536,1);return {passed=good,independent_bases=true}end end,true)
local accepted
up(ready,'candidate_factory',function(take)return function(seed,difficulty,accepts)
    evaluations=evaluations+1;first=first or seed;accepted=accepts
    if difficulty then assert(difficulty==10);narrowed=narrowed+1 else complete=complete+1 end
    for _=1,1200 do take(65536,1)end
    return {{valid=true,row=29,difficulty=10,missions={{native_type=0,seed=seed,level_index=1},
        {native_type=22,seed=seed,level_index=2},{native_type=match and 7 or 28,seed=seed,level_index=3}}}}
end end,true)
-- The capture hands each run to the search. Open it in the session first, as
-- identity_probe_runtime does, once the idle pipeline has settled the last.
local session=up(tick,'reroll_session');local on_ready=ready
ready=function(...)session.settle();session.advance('waiting_for_stable_inputs');return on_ready(...)end
local function frame()
    now=now+0.01;local a,b,c=update();assert(a==1 and b==nil and c==3)
end
frame();ready(s,2000000,now)
for _=1,12 do frame()end
assert(MissionRerollerExperiment.status=='search_matched' and narrowed==1 and complete==1,'Search must progress while unfocused')
assert(MissionRerollerExperiment.search_result.seed==124 and first==124)
assert(table.concat(logs):find('first_seed=124 resumed=false',1,true) and table.concat(logs):find('limit=262144',1,true))
assert(table.concat(logs):find('published=false selected=false',1,true))
assert(table.concat(logs):match('LUA_SEARCH_MATCH [^\n]*elapsed_s=[%d.]+ slices=%d+ work_ms=%d+ context_ms=%d+ jit=true missions='),'Timing is reported')
ready(s,2000000,now);live=nil;unavailable='waiting for pending backend requests'
local count=evaluations
for _=1,150 do frame()end
assert(MissionRerollerExperiment.status=='search_waiting_backend' and evaluations==count)
live=s;for _=1,100 do frame()end
assert(MissionRerollerExperiment.status=='search_matched','Backend drain must resume automatically')
assert(table.concat(logs):find('LUA_SEARCH_WAIT',1,true) and table.concat(logs):find('LUA_SEARCH_RESUMED',1,true))
ready(s,2000000,now);live=nil;frame();now=now+61;frame()
assert(MissionRerollerExperiment.status=='search_cancelled' and MissionRerollerExperiment.search_result.error=='Backend wait time limit reached')
live=s;unavailable='map unavailable'
match=false;limited(256);first=nil;ready(s,2000000,now)
for _=1,1100 do frame()end
assert(MissionRerollerExperiment.status=='search_exhausted' and MissionRerollerExperiment.search_result.attempts==256 and first==124)
assert(MissionRerollerExperiment.search_report=='No match in 256 seeds; search again to continue')
-- The same request continues after the searched range; another request,
-- another seed or a failed search starts again after the campaign seed.
first=nil;ready(s,2000000,now);for _=1,1100 do frame()end
assert(MissionRerollerExperiment.status=='search_exhausted' and first==380,'Unchanged request must continue: '..tostring(first))
assert(table.concat(logs):find('first_seed=380 resumed=true',1,true) and not MissionRerollerExperiment.search_report:find('512',1,true))
limited(16);first=nil;ready(s,2000000,now);for _=1,100 do frame()end
assert(MissionRerollerExperiment.search_result.attempts==16 and first==636,'The budget is not part of the request')
MissionRerollerExperiment.search_options={difficulty=10,required={[1]=true,[2]=true},limit=16}
first=nil;ready(s,2000000,now);for _=1,100 do frame()end;assert(first==124,'Another filter starts again')
limited(16);first=nil;ready(s,2000000,now);for _=1,100 do frame()end;assert(first==124,'Only the last range is kept')
local moved={board=s.board,planet=s.planet,seed=900,fingerprint='stable'}
first=nil;ready(moved,2000000,now);for _=1,100 do frame()end;assert(first==901,'A new campaign seed starts again')
limited(256);match=true;first=nil;ready(s,2000000,now);for _=1,12 do frame()end
assert(MissionRerollerExperiment.status=='search_matched' and not MissionRerollerExperiment.search_report)
assert(accepted(5) and accepted(49) and table.concat(logs):find('region=all',1,true))
-- A city search keeps its own range and never matches the planet's rows.
limited(16);match=false;first=nil;ready(s,2000000,now);for _=1,100 do frame()end
MissionRerollerExperiment.search_options.scope={region=1}
match=true;first=nil;ready(s,2000000,now);for _=1,100 do frame()end
assert(first==124 and MissionRerollerExperiment.status=='search_exhausted','The planet row 29 is outside the city')
assert(accepted(49) and not accepted(29) and not accepted(59) and table.concat(logs):find('region=1',1,true))
assert(MissionRerollerExperiment.search_result.scope.region==1)
-- A city whose operation is in progress is refused before any work.
local function record(row,level,where)
    local out={};for i=1,92 do out[i]='00' end
    out[1]=string.format('%02x',row);out[17]=string.format('%02x',where%256);out[18]=string.format('%02x',math.floor(where/256))
    out[33]=string.format('%02x',level);out[53]='01'
    return table.concat(out)
end
local busy={board=s.board,planet=s.planet,seed=s.seed,fingerprint='stable',active=record(49,10,s.planet)}
count=evaluations;live=busy;ready(busy,2000000,now);frame()
assert(MissionRerollerExperiment.status=='search_failed' and evaluations==count)
assert(MissionRerollerExperiment.search_report:find('in progress',1,true) and table.concat(logs):find('FILTER_BLOCKED operation in progress row=49',1,true))
busy.active=record(49,9,s.planet);ready(busy,2000000,now);for _=1,100 do frame()end
assert(MissionRerollerExperiment.status=='search_exhausted','Another difficulty is searched')
MissionRerollerExperiment.search_options.scope=nil;busy.active=record(29,10,s.planet)
match=true;ready(busy,2000000,now);for _=1,100 do frame()end
assert(MissionRerollerExperiment.status=='search_matched','The whole planet is searched past the operation in progress')
live=s;match=false;limited(16);MissionRerollerExperiment.search_options.scope={region=1}
MissionRerollerExperiment.search_options.scope={region=9}
assert(not pcall(on_ready,s,2000000,now),'An invalid city is refused')
MissionRerollerExperiment.search_options=nil
match=false;ready(s,2000000,now);frame();focused=true;down=true;frame()
assert(MissionRerollerExperiment.status=='search_cancelled','Shortcut must cancel without arming another job')
down=false;frame();ready(s,2000000,now);live=nil;frame()
assert(MissionRerollerExperiment.status=='search_cancelled' and not MissionRerollerExperiment.search_result.seed)
live=s;ready(s,2000000,now);now=now+181;frame();assert(MissionRerollerExperiment.status=='search_cancelled')
good=false;ready(s,2000000,now);frame();assert(MissionRerollerExperiment.status=='search_failed')
good=true;MissionRerollerExperiment.search_options={difficulty=10,required={[4]=true}}
ready(s,2000000,now)
MissionRerollerExperiment.search_options.required={[5]=true}
for _=1,12 do frame()end
assert(MissionRerollerExperiment.status=='search_matched','Custom filter must reach predictor instead of fixed ICBM/Survey/Eradicate')
assert(MissionRerollerExperiment.search_result.required[4],'Running filter is frozen')
-- Packages without the constellation modules must refuse such rules.
MissionRerollerExperiment.search_options={difficulty=10,required={},constellations={groups={[0]={[2]='accept'}}}}
count=evaluations;ready(s,2000000,now);frame()
assert(MissionRerollerExperiment.status=='search_failed' and evaluations==count)
assert(table.concat(logs):find('FILTER_BLOCKED Constellation filters unavailable',1,true))
MissionRerollerExperiment.search_options=nil
ready(s,2000000,now);local a,b,c=shutdown();assert(a==4 and b==nil and c==6 and closed)
assert(MissionRerollerExperiment.status=='search_cancelled')
assert(not table.concat(logs):find('SESSION_',1,true),'Every phase change follows the session rules: '..tostring(table.concat(logs):match('SESSION_[^%c]*')))
print('Search runtime: two-stage prediction, budget, resumed ranges, background progress, matched log, shortcut cancellation, timeout, context loss, baseline rejection and shutdown passed')
