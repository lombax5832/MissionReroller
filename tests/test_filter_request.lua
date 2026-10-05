-- The dialog's Filters and view model, plain tables in and out.
-- Usage: luajit tests/test_filter_request.lua <src folder>
local root=arg[1]
local Rules=dofile(root..'/filter_rules.lua')
local R=assert(loadfile(root..'/filter_request.lua'))(nil,Rules);local C=dofile(root..'/filter_catalogue.lua')
local compatibility=dofile(root..'/mission_compatibility.lua');local options=dofile(root..'/search_session.lua').options
local labels={[2]='Constellation 2 (Tag2)',[9]='Predator Strain (Tag9)'}
local spores,gunships=0x1101e25c,0xf6f1b0c7
local function offered(...)
    local group={list={},set={}}
    for i,id in ipairs({...})do group.list[i]={id=id,name='Constellation '..id..' (Tag'..id..')'};group.set[id]=true end
    return group
end
-- Survey (2) goes with Democracy (4), Democracy with Nursery (9); never all three.
local reachable={[compatibility.mask({[2]=true,[4]=true})]=true,[compatibility.mask({[4]=true,[9]=true})]=true}
local terminids={faction=2,slots=3,compatibility=compatibility,
    profiles={{masks=reachable,modifiers={}},{masks=reachable,modifiers={spores}}},
    missions={{id=2,name='Survey'},{id=4,name='Democracy'},{id=9,name='Nursery'}},mission_set={[2]=true,[4]=true,[9]=true},
    modifiers={{id=spores,name='Atmospheric Spores'}},modifier_set={[spores]=true},forced={9,11},
    constellation_groups={[0]=offered(2,4,6),[2]=offered(2,4),[4]=offered(2,6),[9]=offered()}}
local automatons={faction=3,slots=3,missions={{id=4,name='Democracy'}},mission_set={[4]=true},
    modifiers={{id=gunships,name='Gunship Patrols'}},modifier_set={[gunships]=true},forced={},
    constellation_groups={[0]=offered(14,15),[4]=offered(14)}}
local many={faction=4,slots=3,missions={},mission_set={},modifiers={},modifier_set={},forced={},constellation_groups={}}
for id=1,30 do many.missions[id]={id=id,name='Mission '..id};many.mission_set[id]=true end
local function fresh(extra)
    local v={shown=true,fresh=true,retained=false,running=false,queued=false,fixed=false,overdue=false,
        run={caption='Searching seeds',step=2,progress=2731},difficulty=10,limit=1000000}
    for k,x in pairs(extra or {})do v[k]=x end
    return v
end
local function ids(model)local out={};for i,item in ipairs(model.items)do out[i]=item.id end;return table.concat(out,' ')end
local function edit(f,...)for _,action in ipairs({...})do assert(f:toggle(action,terminids)==true,tostring(action))end end

-- An empty request: the missions are open and nothing can start.
local f=R.new(options,C,labels)
local m=f:model(terminids,fresh())
assert(m.section=='missions' and ids(m)=='2 4 9' and m.faction==2 and m.slots==3 and m.scope=='planet' and m.difficulty==10)
assert(m.status=='Choose what the operation must contain' and m.tone=='idle' and m.detail=='' and m.rules==0)
assert(m.ready and not m.can_start and not m.can_clear and not m.locked and not m.running and m.step==nil)
assert(m.summaries.missions=='Any' and m.summaries.modifiers=='Any' and m.summaries.enemies=='Any')
assert(not pcall(f.validate,f,terminids),'An empty request is refused by validation')

-- Missions cycle required, excluded, any. A mission that cannot join the
-- required ones is disabled and ignores clicks, as before exclusions.
edit(f,2);m=f:model(terminids,fresh())
assert(m.items[1].mode=='require' and m.items[2].enabled and not m.items[2].mode)
assert(m.items[3].enabled==false and m.items[3].reason and not m.items[3].mode,'A conflict is disabled and says why')
edit(f,9);assert(not f.selected[9] and not f.excluded[9],'A disabled conflict ignores clicks')
-- Exclusion goes through required: Nursery first, then Survey beside it.
edit(f,2,2);assert(not next(f.selected) and not next(f.excluded),'Survey clears through excluded')
edit(f,9,9,2);assert(f.excluded[9] and f.selected[2] and not f.selected[9])
m=f:model(terminids,fresh())
assert(m.items[3].enabled,'An excluded row stays clickable')
assert(m.items[3].mode=='exclude' and m.rules==2 and m.checked==1 and f:rule_count()==2)
assert(m.summaries.missions=='Geological Survey, not Nuke Nursery' and m.status=='Ready to search')
f:validate(terminids)
edit(f,9);assert(not f.excluded[9],'An excluded mission goes back to any')
edit(f,2);assert(not f.selected[2] and f.excluded[2],'A second click excludes')
m=f:model(terminids,fresh());assert(m.items[1].mode=='exclude' and m.can_start,'An exclusion alone is a filter')
edit(f,2);assert(not f.selected[2] and not f.excluded[2],'A third click clears')
-- Democracy (4) is in every reachable operation, so it cannot be excluded:
-- the second click clears it instead.
edit(f,4,4);assert(not f.selected[4] and not f.excluded[4],'A mission every operation holds cannot be excluded')
do
    -- Excluding a mission the request requires, or one every operation
    -- holds, or one not offered here, is refused by validation.
    local function refused(required,excluded,why)
        local ok,err=pcall(C.validate,terminids,{required=required,excluded=excluded})
        assert(not ok and tostring(err):find(why,1,true),tostring(err))
    end
    refused({[2]=true},{[2]=true},'A mission cannot be both required and excluded')
    refused({},{[4]=true},'Incompatible with selected missions or modifier rules')
    refused({},{[1]=true},'Excluded mission is unavailable on this planet/difficulty')
    refused({},{[2]='exclude'},'Excluded mission is unavailable on this planet/difficulty')
    refused({[9]=true},{[2]=true,[4]=true},'Incompatible')
    C.validate(terminids,{required={},excluded={[9]=true}})
    C.validate(terminids,{required={[4]=true},excluded={[2]=true}})
    -- Without compatibility data, excluding every mission offered is still refused.
    local possible,why=C.possible(automatons,{required={},excluded={[4]=true}})
    assert(not possible and why=='Every mission here is excluded')
    assert(not pcall(C.validate,automatons,{required={},excluded={[4]=true}}))
    local alone=R.new(options,C,labels);alone:toggle(4,automatons);alone:toggle(4,automatons)
    assert(not alone.selected[4] and not alone.excluded[4],'The only mission here cannot be excluded')
end
edit(f,2,4);m=f:model(terminids,fresh())
assert(m.status=='Ready to search' and m.can_start and m.can_clear and m.rules==2 and m.checked==2)
assert(m.detail=='Rerolls every unstarted operation of the campaign')
assert(m.summaries.missions=='Geological Survey, Spread Democracy' and f:rule_count()==2)
f:validate(terminids)

-- Modifiers cycle require, exclude, none.
local modifier='modifier:'..spores
edit(f,modifier);assert(f.modifiers[spores]=='require')
edit(f,modifier);assert(f.modifiers[spores]=='exclude')
edit(f,modifier);assert(f.modifiers[spores]==nil)
edit(f,modifier)
assert(f:navigate('section:modifiers'));m=f:model(terminids,fresh())
assert(m.section=='modifiers' and ids(m)==modifier and m.items[1].mode=='require' and m.summaries.modifiers=='1 rule')

-- Sections: one open at a time; the open one closes.
assert(f:navigate('section:modifiers'));m=f:model(terminids,fresh());assert(m.section==nil and #m.items==0)
assert(f:navigate('section:enemies'))
assert(not f:navigate('start') and not f:navigate(2) and not f:navigate(nil),'Only pages, sections and groups navigate')
assert(f:toggle('start',terminids)==false and f:toggle(nil,terminids)==false and f:toggle('group:4',terminids)==false)

-- Constellations: one group per checked mission, cycling accept, exclude, none.
m=f:model(terminids,fresh())
assert(m.group==2 and ids(m)=='constellation:2:2 constellation:2:4' and m.items[1].name=='Constellation 2')
assert(#m.groups==2 and m.groups[1].name=='Geological Survey' and m.groups[1].selected and not m.groups[2].selected)
assert(m.forced=='Predator Strain, tag 11' and m.note==nil,m.forced)
assert(m.items[2].tag==4 and m.items[2].title=='Constellation 4' and not m.items[2].stamped,'Rows carry their tag and title')
do
    -- A tag a map stamp can add is marked; the title stays plain for the tooltip.
    local marked=R.new(options,C,labels,{[4]=true});marked.selected=f.selected;marked:navigate('section:enemies')
    local rows=marked:model(terminids,fresh()).items
    assert(rows[2].name=='Constellation 4 *' and rows[2].title=='Constellation 4' and rows[2].stamped)
    assert(rows[1].name=='Constellation 2' and not rows[1].stamped)
end
edit(f,'constellation:2:4');assert(f.constellations[2][4]=='accept')
edit(f,'constellation:2:4');assert(f.constellations[2][4]=='exclude')
edit(f,'constellation:2:4');assert(f.constellations[2]==nil,'A group without rules goes away')
edit(f,'constellation:2:4')
assert(f:navigate('group:4'));m=f:model(terminids,fresh())
assert(m.group==4 and ids(m)=='constellation:4:2 constellation:4:6' and not m.items[1].mode)
edit(f,'constellation:4:2','constellation:4:6','constellation:4:6')
m=f:model(terminids,fresh());assert(m.summaries.enemies=='3 rules' and m.rules==6)
-- Excluding all a mission can draw is refused.
edit(f,'constellation:4:2')
m=f:model(terminids,fresh())
assert(not m.ready and not m.can_start and m.status=='Every constellation of this mission is excluded' and m.tone=='bad')
assert(not f:possible(terminids) and not pcall(f.validate,f,terminids))
edit(f,'constellation:4:2','constellation:4:2','constellation:4:6');assert(f:possible(terminids) and f.constellations[4][2]=='accept' and f.constellations[4][6]==nil)

-- The request is a copy of the filters.
local request=f:to_request({region=1,extra=true},9)
assert(request.difficulty==9 and request.scope.region==1 and request.scope.extra==nil)
assert(request.required[2] and request.required[4] and request.modifiers[spores]=='require')
assert(request.constellations.groups[2][4]=='accept' and request.constellations.groups[4][2]=='accept')
assert(next(request.excluded)==nil)
request.required[9]=true;request.constellations.groups[2][4]='exclude'
assert(not f.selected[9] and f.constellations[2][4]=='accept')
do
    local x=R.new(options,C,labels);x:toggle(9,terminids);x:toggle(9,terminids);x:toggle(2,terminids)
    local copied=x:to_request(nil,10);copied.excluded[2]=true
    assert(copied.excluded[9] and copied.required[2] and not x.excluded[2],'Excluded missions are copied')
end
assert(f:to_request(nil,10).scope==nil)

-- Unchecking a mission drops its constellations; checking it again starts clean.
edit(f,4);assert(f.constellations[4]==nil)
m=f:model(terminids,fresh());assert(m.group==2 and #m.groups==1,'A group that went away is not selected again')
edit(f,4);assert(f.constellations[4]==nil)
-- Without checked missions the single group 0 applies. Survey clears through
-- excluded; Democracy, in every operation, clears at once.
edit(f,2,2,4);m=f:model(terminids,fresh())
assert(not next(f.selected) and not next(f.excluded))
assert(m.group==0 and m.groups[1].name=='Any mission' and m.note=='Check a mission to set its own enemies')
local section=f.section
f:navigate('section:enemies');f:navigate('section:enemies');assert(not next(f.changed),'Clicking the header clears the mark')
edit(f,'constellation:0:6');edit(f,2)
assert(next(f:to_request(nil,10).constellations.groups)==nil,'Checking a mission discards the any-mission rules')
m=f:model(terminids,fresh())
assert(m.changed.enemies and not m.changed.objectives and m.summaries.enemies=='Any - Mission changed','The discard marks the enemy section')
assert(m.summaries.objectives=='Any','Only the section that lost rules')
assert(f:navigate('section:enemies'));m=f:model(terminids,fresh())
assert(not m.changed.enemies and m.summaries.enemies=='Any','Clicking the header clears the mark')
f.section=section
-- Unchecking a mission without rules marks nothing.
edit(f,2,2);assert(not next(f.changed),'No rules, no mark')
-- Unchecking a mission with rules marks its section.
edit(f,4,'constellation:4:2',4);assert(f.changed.enemies,'Unchecking discards the mission rules')
edit(f,'clear');assert(not next(f.changed),'Clear drops the mark')
edit(f,2)
-- Any-mission rules a check would discard do not disable the mission.
do
    local x=R.new(options,C,labels)
    for _,tag in ipairs({2,4,6})do x:toggle('constellation:0:'..tag,terminids);x:toggle('constellation:0:'..tag,terminids)end
    local mx=x:model(terminids,fresh())
    assert(not x:possible(terminids) and mx.tone=='bad','Every any-mission constellation excluded')
    for _,item in ipairs(mx.items)do assert(item.enabled,'Mission '..item.id..' stays enabled')end
    assert(x:toggle(2,terminids) and x.selected[2] and x.changed.enemies and x:possible(terminids))
end

-- A catalogue of another faction prunes what it does not offer.
edit(f,2,2,9,9,2);assert(f.excluded[9] and f.selected[2])
edit(f,4,'constellation:2:2');assert(f:navigate('group:4'));f:model(terminids,fresh());edit(f,'constellation:4:6')
assert(f:prune(automatons,true)==true)
assert(not f.selected[2] and f.selected[4] and not f.excluded[9] and f.modifiers[spores]==nil and f.constellations[2]==nil and next(f.constellations[4] or {})==nil)
assert(f:prune(automatons,false)==false,'Nothing left to prune')
f.excluded[9]=true
f:toggle('clear',automatons);assert(not next(f.selected) and not next(f.excluded) and not next(f.modifiers) and not next(f.constellations))

-- Pages of 24 missions; a refresh of the same view keeps the page.
assert(f:navigate('section:missions'));m=f:model(many,fresh())
assert(m.pages==2 and m.page==1 and #m.items==24 and m.items[24].id==24)
f:navigate('next_page');f:navigate('next_page');m=f:model(many,fresh());assert(m.page==2 and #m.items==6 and m.items[1].id==25)
f:prune(many,false);assert(f.page==2)
f:prune(many,true);assert(f.page==1)
f:navigate('previous_page');assert(f.page==1)
f:navigate('next_page');m=f:model(automatons,fresh());assert(m.pages==1 and m.page==1,'A shorter list clamps the page')
f.page=2;f:open();assert(f.section=='missions' and f.page==1,'Opening starts on the first mission page')

-- Nothing to show: no items and no faction, and the request is locked.
m=f:model(automatons,fresh({shown=false,fresh=false}))
assert(#m.items==0 and m.faction==nil and m.slots==nil and m.locked and not m.ready)
m=f:model(automatons,fresh({fresh=false,retained=true}))
assert(#m.items==1 and not m.locked and m.ready,'Retained data keeps the request editable')

-- Status precedence, highest first.
local g=R.new(options,C,labels);edit(g,2)
local bad=R.new(options,C,labels);edit(bad,'constellation:0:2','constellation:0:4','constellation:0:6','constellation:0:6','constellation:0:4','constellation:0:2')
local cases={
    {g,{running=true,fixed=true,report='R'},'Searching seeds','busy',2,'2,731 of 1,000,000 seeds searched'},
    {g,{queued=true,fixed=true,fresh=false,retained=true},'Checking planet data','busy',1,'Starting search'},
    {g,{fixed=true,overdue=true},'Operation in progress. Finish or abandon it to reroll','warn'},
    {bad,{overdue=true,fresh=false,retained=true},'Updating planet data. Your choices are kept','warn'},
    {bad,{fresh=false,why='Waiting'},'Every constellation here is excluded','bad'},
    {g,{fresh=false,why='Choose a planet and map difficulty',report='R'},'Open a planet on the war table first','warn'},
    {g,{fresh=false,why='Only the host can reroll operations',report='R'},'Only the host can reroll operations','warn'},
    {g,{fresh=false,report='R',tone='good'},'R','warn'},
    {g,{fresh=false},'Waiting for planet data','warn'},
    {g,{report='Search cancelled',tone='idle'},'Search cancelled','idle'},
    {g,{},'Ready to search','idle',nil,'Rerolls every unstarted operation of the campaign'},
    {g,{report='Unavailable filters cleared',tone='warn'},'Unavailable filters cleared','warn',nil,''},
}
for i,case in ipairs(cases)do
    local model=case[1]:model(terminids,fresh(case[2]))
    assert(model.status==case[3] and model.tone==case[4],i..': '..model.status..' '..model.tone)
    assert(model.step==case[5],i..': step '..tostring(model.step))
    if case[6] then assert(model.detail==case[6],i..': '..model.detail)end
end
m=g:model(terminids,fresh({running=true}))
assert(m.running and m.locked and not m.can_start and not m.can_clear)
-- A solved search shows how strict its filter is and how long it usually
-- takes, in place of the seed count.
local function solving(e,elapsed,progress)
    local v=fresh({running=true});v.run={caption='Searching seeds',step=2,progress=progress or 3,estimate=e,elapsed=elapsed}
    return g:model(terminids,v).detail
end
-- Before a search, the request's estimate replaces the general line once
-- worked out (src/solver_estimate.lua).
for _,case in ipairs({
    {nil,'Rerolls every unstarted operation of the campaign'},
    {'pending','Working out how strict this is'},
    {{match=1/23456,seconds=4.4},'1 in 23,000 seeds match - expect about 4 s'},
    -- No walk rate measured yet on this machine: no time.
    {{match=1/23456},'1 in 23,000 seeds match'},
    {{match=0,seconds=math.huge},'No seed gives this now'},
    {{unavailable='no required mission'},'Rerolls every unstarted operation of the campaign'},
})do
    local text=g:model(terminids,fresh({estimate=case[1]})).detail
    assert(text==case[2],tostring(text))
end
-- A request the solver proves no seed meets cannot be started.
do
    local m=g:model(terminids,fresh({estimate={impossible=true}}))
    assert(not m.can_start and m.ready and m.tone=='bad' and m.status=='No seed gives this now. Change a rule to search',
        m.status)
    assert(g:model(terminids,fresh({estimate={match=1/23456}})).can_start,'A possible request can start')
end
-- A search that has not tried a seed yet keeps the request's estimate from
-- before the search.
do
    local v=fresh({running=true,estimate={match=1/23456,seconds=4.4}})
    v.run={caption='Searching seeds',step=2,progress=0,elapsed=0.3}
    local text=g:model(terminids,v).detail
    assert(text=='0:00 - 1 in 23,000 seeds match - about 4 s',text)
    v=fresh({queued=true,estimate={match=1/23456,seconds=4.4}})
    text=g:model(terminids,v).detail
    assert(text=='1 in 23,000 seeds match - about 4 s',text)
end
-- A running search starts its line with the time it has searched.
for _,case in ipairs({
    {{match=0.6,seconds=0.4},0.1,'0:00 - Most seeds match - under a second'},
    {{match=1/23456,seconds=4.4},1.7,'0:01 - 1 in 23,000 seeds match - about 4 s'},
    {{match=1/7.3,seconds=12},30,'0:30 - 1 in 7 seeds match - about 12 s'},
    {{match=1/1234567,seconds=150},75.2,'1:15 - 1 in 1,200,000 seeds match - about 3 min'},
    {{match=1e-9,seconds=900},179.9,'2:59 - 1 in 1,000,000,000 seeds match - over the 3 min limit'},
    {{match=1/23456,seconds=4.4},nil,'1 in 23,000 seeds match - about 4 s'},
    {{match=1/23456},1.7,'0:01 - 1 in 23,000 seeds match'},
    {nil,12.4,'0:12 - 2,731 of 1,000,000 seeds searched',2731},
    -- No seed tried yet: no count of zero, only the start.
    {nil,0.2,'0:00 - Starting search',0},
    -- With the seeds the solver has covered: the count, then the strictness.
    {{match=1/28177468,seconds=1.8,covered=348e6},7.4,'0:07 - 348M seeds covered - 1 in 28M match'},
    {{match=1/28177468,seconds=1.8,covered=2.36e6},0.6,'0:00 - 2.4M seeds covered - 1 in 28M match'},
    {{match=1/23456,seconds=4.4,covered=4321},1.2,'0:01 - 4,321 seeds covered - 1 in 23K match'},
    {{match=1e-9,seconds=900,covered=1.24e9},65,'1:05 - 1.2B seeds covered - 1 in 1B match'},
    {{match=0.6,seconds=0.4,covered=12},0.1,'0:00 - 12 seeds covered - most seeds match'},
})do
    local text=solving(case[1],case[2],case[4])
    assert(text==case[3],text)
end
m=g:model(terminids,fresh({fixed=true}))
assert(not m.ready and not m.can_start and not m.locked and m.can_clear,'An operation in progress blocks the start, not editing')
m=g:model(terminids,fresh({scope={region=1}}));assert(m.scope=='city')

-- The time of day: one side, a rule of its own, and the sky decides the start.
local t=R.new(options,C,labels)
m=t:model(terminids,fresh())
assert(m.time=='any' and m.summaries.time=='Any','The time of day sits on its header, outside the sections')
assert(t:toggle('time:night',terminids) and t.time=='night' and t:rule_count()==1)
m=t:model(terminids,fresh())
assert(m.time=='night' and m.summaries.time=='Night' and m.rules==1)
assert(not m.can_start and m.status=='Waiting for the sky of the viewed planet' and m.tone=='warn' and m.time_sky=='pending','Without the sky nothing starts')
m=t:model(terminids,fresh({sky={hold='2h 30m'}}))
assert(m.can_start and m.status=='Ready to search' and m.time_hold=='2h 30m' and not m.time_sky,'A night-only request can start')
m=t:model(terminids,fresh({sky={hold='2h 30m',blocked='Night here in 1h 40m'}}))
assert(not m.can_start and m.status=='Night here in 1h 40m' and m.tone=='bad' and m.can_clear and m.time_sky=='blocked','A city without night blocks the start')
-- A search shows its own status: the tile keeps its hold, never waiting or blocked.
m=t:model(terminids,fresh({running=true,sky={hold='2h 30m'}}))
assert(m.time_hold=='2h 30m' and not m.time_sky,'A search keeps the hold')
m=t:model(terminids,fresh({running=true}))
assert(not m.time_sky and m.status=='Searching seeds','A search without its sky is not waiting')
m=t:model(terminids,fresh({queued=true,sky={hold='2h 30m',blocked='Night here in 1h 40m'}}))
assert(not m.time_sky,'A queued start is not blocked on the tile')
m=t:model(terminids,fresh({fixed=true,sky={blocked='Night here in 1h 40m'}}))
assert(m.status=='Operation in progress. Finish or abandon it to reroll','An operation in progress comes first')
t:validate(terminids)
local request=t:to_request(nil,10)
assert(request.time=='night' and next(request.required)==nil)
assert(t:toggle('time:day',terminids) and t.time=='day' and t:to_request(nil,10).time=='day')
assert(t:toggle('time:any',terminids) and t.time==nil and t:rule_count()==0 and t:to_request(nil,10).time==nil)
m=t:model(terminids,fresh({sky={blocked='ignored'}}))
assert(m.status=='Choose what the operation must contain' and not m.time_sky,'Any time ignores the sky')
edit(t,'time:day',2);assert(t:rule_count()==2)
edit(t,'clear');assert(t.time==nil and t:rule_count()==0,'Clear resets the time of day')
assert(not pcall(C.validate,terminids,{required={},time='dusk'}),'Only day or night')
-- Side objectives: per checked mission or the operation, cycling any,
-- required, excluded; a mode the catalogue rules out is skipped.
do
    local lidar,artillery,sam,broadcast=0xf1969b14,0x86cfeedb,0xc46443b2,0x4c10b12e
    local function group(kinds,...)
        local g={list={},set={},kinds=kinds}
        for i,id in ipairs({...})do g.list[i]={id=id,name='Objective '..id};g.set[id]=true end
        return g
    end
    local survey={[22]={side=1,tactical=1,rows={[lidar]=3,[artillery]=3,[broadcast]=2},entries={{row=lidar,role=3,copies=1,mask=0},
        {row=artillery,role=3,copies=1,mask=0},{row=broadcast,role=2,copies=1,mask=0}}}}
    local c={faction=2,slots=3,compatibility=nil,missions={{id=2,name='Survey'},{id=4,name='Democracy'}},mission_set={[2]=true,[4]=true},
        modifiers={},modifier_set={},forced={},constellation_groups={[0]=offered(),[2]=offered(),[4]=offered()},
        objective_groups={[0]=group({},lidar,artillery,sam,broadcast),[2]=group(survey,lidar,artillery,broadcast),
            [4]=group({[28]={side=0,tactical=0,rows={},entries={}}})}}
    local o=R.new(options,C,labels)
    local function act(...)for _,a in ipairs({...})do assert(o:toggle(a,c)==true,a)end end
    o:navigate('section:objectives')
    local m=o:model(c,fresh())
    assert(m.section=='objectives' and #m.groups==1 and m.groups[1].name=='Any mission' and #m.items==4)
    assert(m.objective_note=='ANY MISSION OF THE OPERATION' and m.summaries.objectives=='Any')
    act('objective:0:'..lidar,'objective:0:'..sam,'objective:0:'..sam)
    local request=o:to_request(nil,10)
    assert(request.objectives.groups[0][lidar]=='require' and request.objectives.groups[0][sam]=='exclude')
    assert(o:rule_count()==2 and o:model(c,fresh()).summaries.objectives=='2 rules' and o:model(c,fresh()).can_start)
    act('objective:0:'..sam);assert(o.objectives[0][sam]==nil,'Excluded goes back to any')
    -- Checking a mission discards the any-mission rules and marks the section.
    act(2);m=o:model(c,fresh())
    assert(o.objectives[0]==nil and m.group==2 and m.objective_slots=='1 SIDE + 1 TACTICAL' and m.objective_note==nil)
    assert(m.changed.objectives and not m.changed.enemies and m.summaries.objectives=='Any - Mission changed')
    o:navigate('section:objectives');o:navigate('section:objectives');assert(not next(o.changed))
    c.objective_groups[2].list[3].role=2
    m=o:model(c,fresh())
    assert(m.items[1].role=='side' and m.items[3].role=='tactical','Rows carry their role for the panel')
    -- The seed solver's reachability disables a row no draw path meets in
    -- either mode, with the reason; without it nothing is ruled out.
    m=o:model(c,fresh({reachable={ok=true,tag=function()return true end,
        objective=function(g,row)return not (g==2 and row==broadcast)end}}))
    for _,item in ipairs(m.items)do
        if item.id=='objective:2:'..broadcast then assert(item.enabled==false and item.reason:find('never gets'),tostring(item.reason))
        else assert(item.enabled~=false,item.id)end
    end
    act('objective:2:'..broadcast);assert(not (o.objectives[2] or {})[broadcast],'A refused row ignores clicks')
    m=o:model(c,fresh())
    for _,item in ipairs(m.items)do assert(item.enabled~=false,item.id)end
    act('objective:2:'..lidar)
    -- One side slot: Artillery can no longer be required, only excluded.
    m=o:model(c,fresh())
    for _,item in ipairs(m.items)do
        if item.id=='objective:2:'..artillery then assert(item.enabled and item.reason:find('Too many'),item.reason)end
    end
    act('objective:2:'..artillery);assert(o.objectives[2][artillery]=='exclude','Skips the impossible requirement')
    act('objective:2:'..broadcast);assert(o.objectives[2][broadcast]=='require','Tactical slot is separate')
    o:validate(c)
    request=o:to_request(nil,10)
    assert(request.objectives.groups[2][lidar]=='require' and request.objectives.groups[2][artillery]=='exclude')
    -- A fresh catalogue drops rows it no longer offers; unchecking drops the group.
    local smaller={};for k,v in pairs(c)do smaller[k]=v end
    smaller.objective_groups={[0]=group({}),[2]=group(survey,lidar),[4]=group({})}
    assert(o:prune(smaller) and o.objectives[2][lidar]=='require' and o.objectives[2][artillery]==nil)
    act(2,2);assert(next(o.objectives)==nil,'Unchecked mission loses its side objectives')
    assert(o.changed.objectives,'Unchecking marks the side objectives')
    -- A mission without side objectives shows none.
    act(4);o.group_choice=4;m=o:model(c,fresh());assert(#m.items==0 and m.objective_slots=='0 SIDE + 0 TACTICAL')
    act('clear');assert(next(o.objectives)==nil and o:rule_count()==0 and not next(o.changed))
end
-- Enemy forces of a checked mission: the seed solver's reachability
-- disables a tag no draw path gives or avoids, and a click skips the modes it
-- refuses. A request with no path itself, and the any-mission group, keep
-- every option.
do
    local f=R.new(options,C,labels)
    edit(f,2);f:navigate('section:enemies')
    local refused={['2:2:accept']=true,['2:2:exclude']=true,['2:4:accept']=true}
    local reach={ok=true,tag=function(g,t,mode)return not refused[g..':'..t..':'..mode]end,objective=function()return true end}
    local m=f:model(terminids,fresh({reachable=reach}))
    assert(ids(m)=='constellation:2:2 constellation:2:4')
    assert(m.items[1].enabled==false and m.items[1].reason:find('never gets'),'Neither mode has a path')
    assert(m.items[2].enabled and m.items[2].reason,'Only excluding has a path')
    edit(f,'constellation:2:4');assert(f.constellations[2][4]=='exclude','The click skips accept')
    edit(f,'constellation:2:2');assert(f.constellations[2][2]==nil,'A refused tag ignores clicks')
    m=f:model(terminids,fresh())
    assert(m.items[1].enabled and m.items[2].enabled,'Without reachability nothing is disabled')
    m=f:model(terminids,fresh({reachable={ok=false,tag=function()return false end,objective=function()return false end}}))
    assert(m.items[1].enabled and m.items[2].enabled,'A request without a path keeps every option')
    local any=R.new(options,C,labels);any:navigate('section:enemies')
    m=any:model(terminids,fresh({reachable={ok=true,tag=function()return false end,objective=function()return false end}}))
    for _,item in ipairs(m.items)do assert(item.enabled,'The any-mission group is not solved')end
end
print('Filter request: toggles, conflicts, groups, pruning, pages, request copy, status precedence, side objectives, reachability and time of day passed')
