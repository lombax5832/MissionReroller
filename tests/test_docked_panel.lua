local P=dofile(assert(arg[1]))
local function list(n,prefix,name)
    local items={}
    for i=1,n do items[i]={id=prefix and prefix..i or i,name=(name or 'Option')..' '..i}end
    return items
end
local function model(section,items,extra)
    local m={section=section,items=items or {},faction=2,scope='planet',difficulty=10,slots=3,checked=0,page=1,pages=1,
        status='Ready to search',tone='idle',detail='',ready=true,can_start=true,can_clear=true,
        summaries={missions='Any',modifiers='Any',enemies='Any'},groups={}}
    for k,v in pairs(extra or {})do m[k]=v end
    return m
end
-- The last n items are tactical objectives, the others side objectives.
local function roles(items,n)
    for i,item in ipairs(items)do item.role=i>#items-n and 'tactical' or 'side' end
    return items
end
local three={{id=2,name='Geological Survey',selected=true},{id=5,name='Evacuate High-Value Assets'},{id=62,name='Neutralize Ground-to-Orbit Defenses'}}
local function running(m)m.running=true;m.locked=true;m.ready=false;m.can_start=false;m.can_clear=false;m.step=2;return m end
local cases={
    {'missions',model('missions',list(22)),32},
    {'paged missions',model('missions',list(24),{page=1,pages=2}),36},
    {'one mission',model('missions',list(1)),11},
    {'modifiers',model('modifiers',list(13,'modifier:')),23},
    {'enemies',model('enemies',list(11,'constellation:2:'),{groups=three}),24},
    {'any mission',model('enemies',list(6,'constellation:0:'),{groups={{id=0,name='Any mission',selected=true}},note='Check a mission',forced='Predator Strain'}),17},
    {'no enemies',model('enemies',{},{groups=three}),13},
    {'all closed',model(nil,{}),10},
    {'running missions',running(model('missions',list(24),{page=2,pages=2})),36},
    {'running modifiers',running(model('modifiers',list(13,'modifier:'))),23},
    {'running enemies',running(model('enemies',list(11,'constellation:2:'),{groups=three})),24},
    {'no catalogue, missions',model('missions',{},{faction=false,locked=true,can_start=false,can_clear=false}),10},
    {'no catalogue, modifiers',model('modifiers',{},{faction=false,locked=true,can_start=false,can_clear=false}),10},
    {'no catalogue, enemies',model('enemies',{},{faction=false,locked=true,can_start=false,can_clear=false}),10},
    {'day',model(nil,{},{time='day',time_note='DAY 15H 42M',time_hold='2h 30m'}),10},
    {'running night',running(model(nil,{},{time='night'})),10},
    {'paged missions at night',model('missions',list(24),{page=1,pages=2,time='night'}),36},
    {'modifiers by day',model('modifiers',list(13,'modifier:'),{time='day'}),23},
    {'many side objectives by day',model('objectives',roles(list(28,'objective:0:'),12),{groups={{id=0,name='Any mission',selected=true}},time='day'}),39},
    {'side objectives',model('objectives',list(22,'objective:2:'),{groups=three,objective_slots='4 SIDE + 1 TACTICAL'}),35},
    {'many side objectives',model('objectives',roles(list(28,'objective:0:'),12),{groups={{id=0,name='Any mission',selected=true}},objective_note='ANY MISSION OF THE OPERATION'}),39},
    {'no side objectives',model('objectives',{},{groups=three}),13},
    {'running side objectives',running(model('objectives',list(9,'objective:2:'),{groups=three})),22},
}
for _,size in ipairs({{1280,720},{1920,1080},{3440,1440},{640,480}})do
    for _,case in ipairs(cases)do
        local name,m=case[1]..' at '..size[1]..'x'..size[2],case[2]
        local b=P.layout(size[1],size[2],m)
        assert(b.x>=0 and b.y>=0 and b.x+b.w<=size[1] and b.y+b.h<=size[2],name)
        assert(math.abs(size[1]-(b.x+b.w)-40*b.s)<1e-6 and math.abs(b.y*2+b.h-size[2])<1e-6,'Docked right, centred: '..name)
        assert(#b.targets==case[3],name..': '..#b.targets..' targets')
        -- Nothing but the footer may reach below the step strip of a search.
        local floor=b.y+(1008-820)*b.s
        for i,t in ipairs(b.targets)do
            assert(t.w>0 and t.h>0 and type(t.enabled)=='boolean',name)
            assert(t.x>=b.x and t.y>=b.y and t.x+t.w<=b.x+b.w and t.y+t.h<=b.y+b.h,name..': target outside the panel')
            local footer=t.id=='start' or t.id=='cancel' or t.id=='clear' or t.id=='close'
            assert(footer or t.y>=floor-1e-6,name..': '..tostring(t.id)..' reaches the footer')
            for j=1,i-1 do
                local a=b.targets[j]
                assert(t.x>=a.x+a.w-1e-6 or a.x>=t.x+t.w-1e-6 or t.y>=a.y+a.h-1e-6 or a.y>=t.y+t.h-1e-6,
                    name..': '..tostring(a.id)..' overlaps '..tostring(t.id))
            end
            local row=type(t.id)=='number' or tostring(t.id):find('^modifier:') or tostring(t.id):find('^constellation:') or tostring(t.id):find('^time:')
                or tostring(t.id):find('^objective:')
            if m.locked then
                assert(t.enabled==(not row and t.id~='start' and t.id~='clear'),name..': locked '..tostring(t.id))
            else assert(t.enabled,name..': '..tostring(t.id))end
        end
        assert(#b.rows==#m.items and #b.groups==((m.section=='enemies' or m.section=='objectives') and #m.groups or 0))
        assert(b.primary.id==(m.running and 'cancel' or 'start'))
    end
end
local b=P.layout(1920,1080,model('missions',list(22)))
assert(b.x==1216 and b.y==36 and b.w==664 and b.h==1008 and b.s==1,'Design geometry')
-- Five section headers close eleven rows up to 33 units apart.
assert(b.rows[1].w==302 and b.rows[1].h==30 and b.rows[12].x==b.rows[1].x+308 and b.rows[2].y==b.rows[1].y-33,'Two columns, filled downwards')
assert(b.rows[11].x==b.rows[1].x and b.rows[22].y==b.rows[11].y,'Columns are balanced')
assert(b.headers[1].h==52 and b.headers[1].y>b.rows[1].y and b.headers[2].y<b.rows[11].y,'The open section holds its rows')
b=P.layout(1920,1080,model('modifiers',list(8,'modifier:')))
assert(b.rows[1].h==38 and b.rows[1].y-b.rows[2].y==42 and b.rows[1].w==610,'Modifier rows')
b=P.layout(1920,1080,model('modifiers',list(13,'modifier:')))
-- Five section headers leave 25 units a row; the 19-unit labels still fit.
assert(b.rows[1].h<38 and b.rows[1].h>=24,'Thirteen modifiers shrink their rows')
-- Side objectives fill two columns and close up when there are many.
b=P.layout(1920,1080,model('objectives',list(10,'objective:2:'),{groups=three}))
assert(b.rows[1].h==32 and b.rows[6].x==b.rows[1].x+308 and b.rows[2].y==b.rows[1].y-35,'Side objectives in two columns')
b=P.layout(1920,1080,model('objectives',roles(list(28,'objective:2:'),12),{groups=three}))
assert(b.rows[1].y-b.rows[2].y<35 and b.rows[1].y-b.rows[2].y>=20,'Many side objectives close up')
assert(not pcall(P.layout,1920,1080,model('objectives',roles(list(33,'objective:2:'),12),{groups=three})),'At most 16 rows')
-- Side objectives, then tactical ones, each a labelled block of two columns.
b=P.layout(1920,1080,model('objectives',roles(list(7,'objective:2:'),3),{groups=three}))
assert(#b.labels==2 and b.labels[1].text=='SIDE' and b.labels[2].text=='TACTICAL','Two labels')
assert(b.rows[3].x==b.rows[1].x+308 and b.rows[2].y==b.rows[1].y-35,'Side objectives in two columns')
assert(b.rows[5].x==b.rows[1].x and b.rows[7].x==b.rows[5].x+308,'Tactical objectives start a new block')
assert(b.rows[5].y<b.rows[2].y-35,'The tactical label sits between the blocks')
b=P.layout(1920,1080,model('objectives',roles(list(3,'objective:2:'),3),{groups=three}))
assert(#b.labels==1 and b.labels[1].text=='TACTICAL','Only tactical objectives')
b=P.layout(1920,1080,model('missions',list(4)));assert(#b.labels==0,'Missions have no labels')
-- The header after an open section follows its last row by the same space,
-- unless the enemy section has note lines to show.
local function gap(m)
    local b=P.layout(1920,1080,m);local row=b.rows[#b.rows]
    for i,section in ipairs(b.headers)do if section.id=='section:'..m.section then return row.y-(b.headers[i+1].y+b.headers[i+1].h)end end
end
local plain=gap(model('modifiers',list(3,'modifier:')))
assert(gap(model('enemies',list(3,'constellation:2:'),{groups=three}))==plain,'No gap under enemies without notes')
assert(gap(model('enemies',list(3,'constellation:2:'),{groups=three,forced='Predator Strain'}))==plain+28,'One note line')
assert(gap(model('enemies',list(3,'constellation:0:'),{groups=three,forced='Predator Strain',note='Check a mission'}))==plain+48,'Two note lines')
-- The time of day is no dropdown: three sides on its header, and a note
-- line under it, above the footer, only while a side is chosen.
b=P.layout(1920,1080,model(nil,{}))
assert(#b.times==3 and b.times[1].id=='time:any' and b.times[3].id=='time:night' and not b.time_meta,'Three sides, no note at any time')
local head=b.headers[5]
for _,side in ipairs(b.times)do
    assert(side.x>=head.x+300 and side.x+side.w<=head.x+head.w and side.y>head.y and side.y+side.h<head.y+head.h,'A side sits right of the title, inside the header')
end
b=P.layout(1920,1080,model(nil,{},{time='night'}))
assert(b.time_meta and b.time_meta+10<820,'The note line ends above the footer')
local plain,noted=P.layout(1920,1080,model('modifiers',list(13,'modifier:'))),P.layout(1920,1080,model('modifiers',list(13,'modifier:'),{time='day'}))
assert(noted.rows[1].h<plain.rows[1].h,'The note line takes its room from the open list')
-- Fourteen rows of side objectives need that room: the note line gives way.
b=P.layout(1920,1080,model('objectives',roles(list(28,'objective:0:'),12),{groups=three,time='day'}))
assert(not b.time_meta and #b.rows==28 and b.rows[1].y-b.rows[2].y>=20,'The note line gives way to a long list')
assert(P.layout(1920,1080,model('objectives',roles(list(20,'objective:0:'),8),{groups=three,time='day'})).time_meta,'A shorter list keeps it')
assert(not pcall(P.layout,1920,1080,model('missions',list(25))),'A page holds 24 missions')
assert(not pcall(P.layout,639,480,model('missions',list(2))),'Viewport too small')
local disabled=model('missions',list(3));disabled.items[2].enabled=false
b=P.layout(1920,1080,disabled);assert(b.rows[1].enabled and not b.rows[2].enabled and b.rows[3].enabled)
b=P.layout(1920,1080,model('missions',list(3),{can_start=false,can_clear=false}))
assert(not b.primary.enabled and not b.clear.enabled and b.close.enabled,'Nothing set: no reroll, no clear')

-- Retained drawing against a recording engine.
local function engine(features)
    local r={created=0,destroyed=0,updates=0,rects=0,texts=0,triangles={},measured=0,attempts=0,live={}}
    local function vector(...)return {...}end
    r.e={Application={worlds=function()return {1,2}end,main_world=function()return 1 end},
        World={create_screen_gui=function()r.created=r.created+1;r.live={};return {}end,
            destroy_gui=function()r.destroyed=r.destroyed+1;r.live={}end},
        Gui={resolution=function()return r.width or 1920,r.height or 1080 end,material=function()return {}end,
            rect=function(_,pos,size,c)r.rects=r.rects+1;local o={kind='rect',pos=pos,size=size,color=c};r.live[#r.live+1]=o;return o end,
            text=function(_,value,_,size,_,pos,c)
                -- The game never shows a text that was created empty.
                assert(value~='','A text is created empty')
                r.texts=r.texts+1;local o={kind='text',value=value,size=size,pos=pos,color=c};r.live[#r.live+1]=o;return o
            end,
            update_rect=function(_,o,pos,size,c)r.updates=r.updates+1;o.pos,o.size,o.color=pos,size,c end,
            update_text=function(_,o,value,_,size,_,pos,c)r.updates=r.updates+1;o.value,o.size,o.pos,o.color=value,size,pos,c end},
        Material={set_scalar=function()end,set_vector2=function()end,set_vector4=function()end,set_texture=function()end},
        IdString64={from_hex=function(s)return s end},
        Vector2=setmetatable({x=function(v)return v[1]end},{__call=function(_,...)return {...}end}),
        Vector3=vector,Color=vector}
    if features=='full' or features=='broken metrics' then
        r.e.Gui.triangle=function(_,a,b,c,layer,colour)
            assert(a[2]==0 and b[2]==0 and c[2]==0 and type(layer)=='number' and type(colour)=='table','Triangles lie in the x/z plane')
            assert((b[1]-a[1])*(c[3]-a[3])-(b[3]-a[3])*(c[1]-a[1])>0,'Counter-clockwise, as the proven triangle')
            local o={kind='triangle',a=a,b=b,c=c,color=colour};r.triangles[#r.triangles+1]=o;r.live[#r.live+1]=o;return o
        end
    end
    if features=='full' then
        r.e.Gui.text_extents=function(_,value,_,size)
            r.measured=r.measured+1
            return {-0.02*size},{#value*size*0.5},{#value*size*0.5+0.03*size}
        end
    elseif features=='broken metrics' then
        r.e.Gui.text_extents=function()r.measured=r.measured+1;return {0},{1e9},{1e9}end
    elseif features=='failing' then
        r.e.Gui.triangle=function()r.attempts=r.attempts+1;error('draw failed')end
        r.e.Gui.text_extents=function()error('metrics failed')end
    end
    function r.find(value)
        for _,o in ipairs(r.live)do if o.kind=='text' and o.value==value then return o end end
    end
    return r
end
local face={font='a',material='b',atlas='c'}
local nowhere={x=0,y=0}
local r=engine('full');local panel=P.new(r.e)
local m=model('modifiers',list(3,'modifier:','Modifier'),{summaries={missions='Geological Survey, Launch ICBM',modifiers='Any',enemies='Any'}})
panel:show({},{},face,nowhere,m);panel:show({},{},face,nowhere,m)
assert(r.updates==0 and r.created==1,'An unchanged state draws nothing')
assert(#r.triangles==6,'Four chevrons and two chamfers')
local rects,texts,measured=r.rects,r.texts,r.measured
assert(measured>0)
for _,o in ipairs(r.live)do
    if o.kind=='text' then assert(o.value==o.value:upper() and not o.value:find('[^\32-\126]'),'Plain capitals: '..o.value)end
end
assert(r.find('TERMINIDS') and r.find('/ WHOLE PLANET') and r.find('REROLL OPERATIONS') and r.find('MODIFIER 2') and r.find('CLOSE'))
assert(r.find('GEOLOGICAL SURVEY, LAUNCH ICBM') and r.find('AT MOST TWO PER OPERATION') and not r.find('ESC'))
local level=assert(r.find('DIFFICULTY 10'))
assert(math.abs(level.pos[1]+#level.value*level.size*0.5+0.05*level.size-(1216+25+610))<1e-6,'Right-aligned on the measured width')
m.items[2].mode='require';m.summaries.modifiers='1 rule'
panel:show({},{},face,nowhere,m)
assert(r.updates>0 and r.destroyed==0 and r.rects==rects and r.texts==texts,'A rule updates the existing rows')
assert(r.find('REQUIRED') and r.find('1 RULE') and #r.triangles==6)
m.items[2].mode='exclude';r.updates=0;panel:show({},{},face,nowhere,m);assert(r.updates>0 and r.find('EXCLUDED') and not r.find('REQUIRED') and r.find('ANY'))
-- Hover and the reason of a row that cannot be chosen.
local spot=P.layout(1920,1080,m).rows[1]
r.updates=0;panel:show({},{},face,{x=spot.x+5,y=spot.y+5},m);assert(r.updates>0,'Hover redraws')
r.updates=0;panel:show({},{},face,{x=spot.x+6,y=spot.y+6},m);assert(r.updates==0,'Movement inside one row does not')
m.items[1].enabled=false;m.items[1].reason='Incompatible with selected missions or modifier rules'
panel:show({},{},face,{x=spot.x+5,y=spot.y+5},m)
assert(r.find('INCOMPATIBLE WITH SELECTED MISSIONS OR MODIFIER RULES') and not r.find('CLICK TO CYCLE: ANY, REQUIRED, EXCLUDED'))
panel:show({},{},face,nowhere,m);assert(r.find('CLICK TO CYCLE: ANY, REQUIRED, EXCLUDED'),'The reason leaves with the pointer')
-- A search: the strip appears, only the counter changes per frame, the strip goes again.
running(m);m.status='Searching seeds';m.tone='busy';m.detail='12 of 1,000,000 seeds searched'
panel:show({},{},face,nowhere,m)
assert(r.find('2 SEARCH SEEDS') and r.find('CANCEL SEARCH') and r.find('12 OF 1,000,000 SEEDS SEARCHED'))
assert(r.destroyed==0,'Starting a search keeps the GUI')
r.updates=0;measured=r.measured;m.detail='4,108 of 1,000,000 seeds searched';panel:show({},{},face,nowhere,m)
assert(r.updates==1 and r.measured==measured and r.find('4,108 OF 1,000,000 SEEDS SEARCHED'),'The counter is one text')
m.running,m.locked,m.step,m.can_start,m.can_clear,m.ready=false,false,nil,true,true,true
m.status='Search cancelled';m.tone='idle';m.detail=''
panel:show({},{},face,nowhere,m)
assert(not r.find('2 SEARCH SEEDS') and not r.find('CANCEL SEARCH') and r.find('SEARCH CANCELLED'),'The strip is hidden after the search')
-- Another section is another set of rows.
local old=r.destroyed
m=model('enemies',list(11,'constellation:2:','Constellation'),{groups=three,forced='Predator Strain, Gloom Strain'})
panel:show({},{[2]=true},face,nowhere,m)
assert(r.destroyed==old+1 and not r.find('MODIFIER 2') and r.find('CONSTELLATION 11'),'A section switch removes the old rows')
assert(r.find('ALWAYS PRESENT:') and r.find('PREDATOR STRAIN, GLOOM STRAIN') and r.find('GEOLOGICAL SURVEY') and #r.triangles==12)
local cut
for _,o in ipairs(r.live)do if o.kind=='text' and o.value:find('^NEUTRALIZE') then cut=o end end
assert(cut and cut.value:find('%.%.%.$') and #cut.value<#'NEUTRALIZE GROUND-TO-ORBIT DEFENSES','Long names are cut to their button')
r.updates=0;panel:show({},{[2]=true},face,nowhere,m);assert(r.updates==0)
m.groups={three[1],three[2]};panel:show({},{[2]=true},face,nowhere,m);assert(r.destroyed==old+2,'Another set of groups is drawn afresh')
m=model('enemies',{},{groups={{id=0,name='Any mission',selected=true}},note='Check a mission to set its own enemies'})
panel:show({},{},face,nowhere,m)
assert(r.find('NO ENEMY FORCES CAN BE CHOSEN HERE') and r.find('CHECK A MISSION TO SET ITS OWN ENEMIES') and r.find('ANY MISSION'))
m=model('missions',list(24,nil,'Mission'),{page=1,pages=2,checked=2});panel:show({},{[3]=true,[7]=true},face,nowhere,m)
assert(r.find('PAGE 1/2   2 OF 3 SLOTS') and r.find('<') and r.find('>') and r.find('MISSION 24'))
m=model('missions',{},{faction=false,locked=true,can_start=false,can_clear=false,status='Open a planet on the war table first',tone='warn'})
panel:show({},{},face,nowhere,m)
assert(r.find('NO PLANET') and r.find('NO PLANET CHOSEN') and r.find('OPEN A PLANET ON THE WAR TABLE FIRST') and not r.find('DIFFICULTY 10'))
-- The time of day: three sides on its header, the chosen one in ink on
-- yellow, and the buffer note on the line under it.
m=model(nil,{},{time='night',time_note='Short days / day 1h 4m',time_hold='14m'})
panel:show({},{},face,nowhere,m)
assert(r.find('TIME OF DAY') and r.find('ANY') and r.find('DAY') and r.find('NIGHT') and not r.find('CHOSEN')
    and r.find('SHORT DAYS / DAY 1H 4M') and r.find('STAYS ON THAT SIDE FOR AT LEAST 14M'),'Time of day header')
-- The side drawn in ink, the panel's darkest colour: exactly the chosen one.
local function inked()
    local found
    for _,o in ipairs(r.live)do
        if o.kind=='text' and (o.value=='ANY' or o.value=='DAY' or o.value=='NIGHT') and o.color[2]==11 then assert(not found,'one inked');found=o.value end
    end
    return found
end
assert(inked()=='NIGHT','Night is chosen')
-- Until the sky is known the line cannot say how long.
m.time_hold=nil;panel:show({},{},face,nowhere,m)
assert(r.find('STAYS ON THAT SIDE AFTER THE REROLL') and not r.find('FOR AT LEAST'),'No hold before the sky')
m.time='day';panel:show({},{},face,nowhere,m);assert(inked()=='DAY','Day is chosen')
local cleared=r.destroyed
m.time='any';m.time_note=nil;panel:show({},{},face,nowhere,m)
assert(inked()=='ANY' and r.destroyed==cleared+1,'Any time drops the note line and redraws')
local hidden=true
for _,o in ipairs(r.live)do if o.kind=='text' and o.value:find('^STAYS ON THAT SIDE') then hidden=false end end
assert(hidden,'No note line at any time')
old=r.destroyed;panel:clear();assert(r.destroyed==old+1)
-- The enemy tooltip: left of the panel, level with the hovered row, above
-- Know Your Constellation's box and inside the window at every size.
local function units(large,small)
    local tip={title='Predator Strain',with='Hive World',large={},small={},footer='Possible encounters.',credit='Unit data: KYC'}
    for i=1,large do tip.large[i]={name='Large '..i,ticks=11-i}end
    for i=1,small do tip.small[i]='Small enemy '..i end
    return tip
end
local function drawn(kind,z)
    local found={}
    for _,o in ipairs(r.live)do
        if o.kind==kind and o.pos[3]==z and (kind~='text' or o.value~='') and (kind~='rect' or o.color[1]~=0 or o.size[1]>1) then found[#found+1]=o end
    end
    return found
end
for _,size in ipairs({{1920,1080},{1024,768},{3440,1440},{640,480}})do
    r=engine('full');r.width,r.height=size[1],size[2];panel=P.new(r.e)
    local tips=0
    m=model('enemies',list(11,'constellation:2:','Constellation'),{groups=three,forced='Hive World',
        tooltip=function(item)tips=tips+1;return item.id=='constellation:2:3' and {title=item.name,note='* The map can add this'} or units(6,30)end})
    local b=P.layout(size[1],size[2],m)
    for _,n in ipairs({1,11})do
        local row=b.rows[n]
        panel:show({},{},face,{x=row.x+4,y=row.y+4},m)
        local body=assert(drawn('rect',1016)[1],'Tooltip body')
        local name=size[1]..'x'..size[2]..' row '..n
        assert(body.pos[1]>=0 and body.pos[2]>=0 and body.pos[1]+body.size[1]<=size[1] and body.pos[2]+body.size[2]<=size[2],name..': inside the window')
        assert(body.pos[1]+body.size[1]<=b.x,name..': left of the panel')
        assert(n==11 or math.abs(body.pos[2]+body.size[2]-(row.y+row.h))<1e-6 or body.pos[2]+body.size[2]>=size[2]-16*b.s-1e-6,name..': level with its row')
        assert(r.find('PREDATOR STRAIN') or r.find('CONSTELLATION '..n),name)
        assert(r.find('LARGE ENEMIES') and r.find('SPAWN RATE') and r.find('LARGE 1') and r.find('WITH HIVE WORLD') and r.find('UNIT DATA: KYC'),name)
        for _,o in ipairs(drawn('text',1018))do
            assert(o.pos[1]>=body.pos[1] and o.pos[1]<body.pos[1]+body.size[1] and o.pos[2]>=body.pos[2] and o.pos[2]<=body.pos[2]+body.size[2],name..': text inside '..o.value)
        end
        -- Ticks: six meters of ten, filled 10 down to 5.
        local lit=0
        for _,o in ipairs(drawn('rect',1017))do if o.size[2]==12*b.s and o.color[2]==240 then lit=lit+1 end end
        assert(lit==10+9+8+7+6+5,name..': meter ticks '..lit)
        local more=false
        for _,o in ipairs(r.live)do if o.kind=='text' and o.value:find('^AND %d+ MORE$') then more=true end end
        assert(not more,name..': the tooltip scales with the window, so thirty enemies fit')
    end
    panel:show({},{},face,nowhere,m);assert(#drawn('rect',1016)==0 and not r.find('LARGE ENEMIES'),'The tooltip leaves with the pointer')
    local row=b.rows[3];panel:show({},{},face,{x=row.x+4,y=row.y+4},m)
    assert(r.find('* THE MAP CAN ADD THIS') and not r.find('LARGE ENEMIES') and #drawn('rect',1016)==1,'A note-only tooltip')
    local calls=tips;panel:show({},{},face,{x=row.x+5,y=row.y+5},m);assert(tips==calls+1 and r.updates>=0)
end
-- More small enemies than the window holds: the last lines become "and N more".
r=engine('full');r.width,r.height=1280,720;panel=P.new(r.e)
m=model('enemies',list(3,'constellation:2:'),{groups=three,tooltip=function()return units(8,400)end})
local row=P.layout(1280,720,m).rows[1];panel:show({},{},face,{x=row.x+4,y=row.y+4},m)
local body,shown,more=assert(drawn('rect',1016)[1]),0,nil
for _,o in ipairs(r.live)do
    if o.kind=='text' and o.pos[3]==1018 then
        more=more or tonumber(o.value:match('^AND (%d+) MORE$'))
        for _ in o.value:gmatch('SMALL ENEMY %d+')do shown=shown+1 end
    end
end
assert(body.pos[2]>=0 and body.pos[2]+body.size[2]<=720 and more and shown+more==400,'Trimmed to the window: '..shown..'+'..tostring(more))
panel:clear()
r=engine('full');panel=P.new(r.e)
m=model('enemies',list(3,'constellation:2:'),{groups=three,tooltip=function()error('roster broke')end})
local row=P.layout(1920,1080,m).rows[1];panel:show({},{},face,{x=row.x+4,y=row.y+4},m)
assert(#drawn('rect',1016)==0 and r.find('OPTION 1'),'A failing tooltip leaves the panel drawn')
m.section='modifiers';m.items=list(3,'modifier:');panel:show({},{},face,{x=row.x+4,y=row.y+4},m)
assert(#drawn('rect',1016)==0,'Only enemy rows have tooltips')
panel:clear()
-- Missions: a required row is ticked yellow, an excluded one struck red.
do
    local function label(value)
        local o=assert(r.find(value),value);return o.color[2]..','..o.color[3]..','..o.color[4]
    end
    r=engine('full');panel=P.new(r.e)
    m=model('missions',{{id=2,name='Geological Survey',mode='require'},{id=9,name='Nuke Nursery',mode='exclude'},{id=4,name='Spread Democracy'}},
        {checked=1,summaries={missions='Geological Survey, not Nuke Nursery',modifiers='Any',enemies='Any'}})
    panel:show({},{[2]=true},face,nowhere,m)
    assert(label('GEOLOGICAL SURVEY')=='255,232,10' and label('NUKE NURSERY')=='255,107,90' and label('SPREAD DEMOCRACY')=='237,241,245')
    assert(r.find('GEOLOGICAL SURVEY, NOT NUKE NURSERY') and r.find('CLICK TO CYCLE: ANY, REQUIRED, EXCLUDED') and r.find('1 OF 3 SLOTS'))
    local dashes=0
    for _,o in ipairs(drawn('rect',995))do
        if o.color[2]==255 and o.color[3]==107 then dashes=dashes+1;assert(o.size[2]<o.size[1],'The excluded mark is a dash')end
    end
    assert(dashes==1,'One excluded row')
    m.items[2].mode=nil;r.updates=0;panel:show({},{[2]=true},face,nowhere,m)
    assert(r.updates>0 and label('NUKE NURSERY')=='237,241,245','Clearing the exclusion redraws the row')
    panel:clear()
end
-- Triangles and metrics are optional, and a failure turns them off.
for _,features in ipairs({'none','failing','broken metrics'})do
    r=engine(features);panel=P.new(r.e)
    for _,case in ipairs(cases)do panel:show({},{[1]=true},face,nowhere,case[2])end
    assert(r.created>1 and r.texts>0,features)
    assert(features=='broken metrics' or #r.triangles==0,features)
    assert(r.measured<=1 and r.attempts<=1,features..': a failed primitive is not retried')
    panel:show({},{},face,nowhere,model('modifiers',list(3,'modifier:')))
    level=assert(r.find('DIFFICULTY 10'))
    assert(level.pos[1]<1216+25+610-#level.value*level.size*0.5 and level.pos[1]>1216+25+305,'Estimated widths keep text inside')
    panel:clear()
end
-- The side-objective section labels its two blocks.
do
    local r=engine('full');local panel=P.new(r.e)
    local items=roles(list(5,'objective:2:','Objective'),2);items[1].mode='require';items[4].mode='exclude'
    panel:show({},{},face,nowhere,model('objectives',items,{groups=three,objective_slots='3 SIDE + 1 TACTICAL'}))
    local side,tactical=r.find('SIDE'),r.find('TACTICAL')
    assert(side and tactical and side.pos[2]>tactical.pos[2],'SIDE above TACTICAL')
    assert(r.find('3 SIDE + 1 TACTICAL') and r.find('OBJECTIVE 5') and r.find('SIDE OBJECTIVES'))
end
print('docked panel: layouts at four resolutions, retained updates, section switch, side and tactical blocks, enemy tooltips inside the window and optional primitives: passed')
