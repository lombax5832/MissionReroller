-- The dialog's Filters and view model, plain tables in and out.
-- Usage: luajit tests/test_filter_request.lua <src folder>
local root=arg[1]
local R=dofile(root..'/filter_request.lua');local C=dofile(root..'/filter_catalogue.lua')
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

-- Missions: a conflict stays unchecked and is shown disabled.
edit(f,2);m=f:model(terminids,fresh())
assert(m.items[1].enabled and m.items[2].enabled and m.items[3].enabled==false and m.items[3].reason)
edit(f,9);assert(not f.selected[9],'A conflicting mission stays unchecked')
edit(f,2);assert(not f.selected[2],'A second click unchecks')
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
request.required[9]=true;request.constellations.groups[2][4]='exclude'
assert(not f.selected[9] and f.constellations[2][4]=='accept')
assert(f:to_request(nil,10).scope==nil)

-- Unchecking a mission drops its constellations; checking it again starts clean.
edit(f,4);assert(f.constellations[4]==nil)
m=f:model(terminids,fresh());assert(m.group==2 and #m.groups==1,'A group that went away is not selected again')
edit(f,4);assert(f.constellations[4]==nil)
-- Without checked missions the single group 0 applies.
edit(f,2,4);m=f:model(terminids,fresh())
assert(m.group==0 and m.groups[1].name=='Any mission' and m.note=='Check a mission to set its own enemies')
edit(f,'constellation:0:6');edit(f,2)
assert(next(f:to_request(nil,10).constellations.groups)==nil,'Checking a mission discards the any-mission rules')

-- A catalogue of another faction prunes what it does not offer.
edit(f,4,'constellation:2:2');assert(f:navigate('group:4'));f:model(terminids,fresh());edit(f,'constellation:4:6')
assert(f:prune(automatons,true)==true)
assert(not f.selected[2] and f.selected[4] and f.modifiers[spores]==nil and f.constellations[2]==nil and next(f.constellations[4] or {})==nil)
assert(f:prune(automatons,false)==false,'Nothing left to prune')
f:toggle('clear',automatons);assert(not next(f.selected) and not next(f.modifiers) and not next(f.constellations))

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
    {g,{queued=true,fixed=true,fresh=false,retained=true},'Checking planet data','busy',1,'0 of 1,000,000 seeds searched'},
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
m=g:model(terminids,fresh({fixed=true}))
assert(not m.ready and not m.can_start and not m.locked and m.can_clear,'An operation in progress blocks the start, not editing')
m=g:model(terminids,fresh({scope={region=1}}));assert(m.scope=='city')

-- The time of day: one side, a rule of its own, and the sky decides the start.
local t=R.new(options,C,labels)
t.section='time'
m=t:model(terminids,fresh())
assert(ids(m)=='time:any time:day time:night' and m.items[1].mode=='chosen' and not m.items[2].mode and m.summaries.time=='Any')
assert(t:toggle('time:night',terminids) and t.time=='night' and t:rule_count()==1)
m=t:model(terminids,fresh())
assert(m.items[3].mode=='chosen' and m.summaries.time=='Night' and m.rules==1)
assert(not m.can_start and m.status=='Waiting for the sky of the viewed planet' and m.tone=='warn','Without the sky nothing starts')
m=t:model(terminids,fresh({sky={note='HOLDS 2H 30M / DAY 15H 42M'}}))
assert(m.can_start and m.status=='Ready to search' and m.time_note=='HOLDS 2H 30M / DAY 15H 42M','A night-only request can start')
m=t:model(terminids,fresh({sky={note='x',blocked='Night here in 1h 40m'}}))
assert(not m.can_start and m.status=='Night here in 1h 40m' and m.tone=='bad' and m.can_clear,'A city without night blocks the start')
m=t:model(terminids,fresh({fixed=true,sky={blocked='Night here in 1h 40m'}}))
assert(m.status=='Operation in progress. Finish or abandon it to reroll','An operation in progress comes first')
t:validate(terminids)
local request=t:to_request(nil,10)
assert(request.time=='night' and next(request.required)==nil)
assert(t:toggle('time:day',terminids) and t.time=='day' and t:to_request(nil,10).time=='day')
assert(t:toggle('time:any',terminids) and t.time==nil and t:rule_count()==0 and t:to_request(nil,10).time==nil)
m=t:model(terminids,fresh({sky={blocked='ignored'}}))
assert(m.status=='Choose what the operation must contain','Any time ignores the sky')
edit(t,'time:day',2);assert(t:rule_count()==2)
edit(t,'clear');assert(t.time==nil and t:rule_count()==0,'Clear resets the time of day')
assert(not pcall(C.validate,terminids,{},{},nil,'dusk'),'Only day or night')
print('Filter request: toggles, conflicts, groups, pruning, pages, request copy, status precedence and time of day passed')
