local P=dofile(assert(arg[1]))
for _,size in ipairs({{1280,720},{1920,1080},{3440,1440},{640,480}})do
  for _,mode in ipairs({'preview','search'})do
    local b=P.layout(size[1],size[2],mode=='search' and {running=false,ready=true} or nil)
    assert(b.x>=0 and b.y>=0 and b.x+b.w<=size[1] and b.y+b.h<=size[2])
    assert(#b.targets==(mode=='search' and 17 or 14))
    for i,t in ipairs(b.targets)do
        assert(t.x>=b.x and t.y>=b.y and t.x+t.w<=b.x+b.w and t.y+t.h<=b.y+b.h)
        for j=1,i-1 do
            local a=b.targets[j]
            assert(t.x>=a.x+a.w or a.x>=t.x+t.w or t.y>=a.y+a.h or a.y>=t.y+t.h,'overlapping targets')
        end
    end
  end
end
local created,destroyed,updates=0,0,0
local e={Application={worlds=function()return {1,2}end,main_world=function()return 1 end},
 World={create_screen_gui=function()created=created+1;return {}end,destroy_gui=function()destroyed=destroyed+1 end},
 Gui={resolution=function()return 1920,1080 end,material=function()return {}end,
 rect=function()return {}end,text=function()return {}end,
 update_rect=function()updates=updates+1 end,update_text=function()updates=updates+1 end},
 Material={set_scalar=function()end,set_vector2=function()end,set_vector4=function()end,set_texture=function()end},
 IdString64={from_hex=function(s)return s end},Vector2=function(...)return {...}end,
 Vector3=function(...)return {...}end,Color=function(...)return {...}end}
local panel=P.new(e);local options={};for i=1,12 do options[i]={name='Mission '..i}end
local face={font='a',material='b',atlas='c'}
panel:show(options,{},face,{x=0,y=0});panel:show(options,{},face,{x=0,y=0});assert(updates==0 and created==1)
panel:show(options,{[1]=true},face,{x=0,y=0});assert(updates>0)
panel:clear();assert(destroyed==1)
local model={running=false,ready=true,difficulty=10,difficulty_locked=true,calls=0,status='Ready',tab='missions',page=1,pages=1,items={{id=9,name='Nuke Nursery'}}}
panel:show(options,{},face,{x=0,y=0},model)
local old=destroyed
model.tab='modifiers';model.items={{id='modifier:1',name='Atmospheric Spores',mode='require'}}
panel:show(options,{},face,{x=0,y=0},model);assert(destroyed==old+1,'Tab switch must remove old rows')
model.items={};panel:show(options,{},face,{x=0,y=0},model);assert(destroyed==old+2,'Empty faction list must remove previous rows')
model.tab='constellations'
model.items={{id='constellation_group',name='group',enabled=false,caption='FOR: LAUNCH ICBM'},{id='constellation:1:4',name='Hunter Swarms'}}
panel:show(options,{},face,{x=0,y=0},model);updates=0
panel:show(options,{},face,{x=0,y=0},model);assert(updates==0,'Unchanged constellation page is retained')
model.items[2].mode='accept';panel:show(options,{},face,{x=0,y=0},model);assert(updates>0 and destroyed==old+3,'A rule updates the existing row')
updates=0;model.items[2].mode='exclude';panel:show(options,{},face,{x=0,y=0},model);assert(updates>0 and destroyed==old+3)
local page=P.layout(1920,1080,model).targets
assert(page[1].id=='constellation_group' and page[1].enabled==false and page[2].enabled,'The mission header is not clickable')
for _,size in ipairs({{1280,720},{1920,1080},{640,480}})do
    model.items={};for i=1,12 do model.items[i]={id='modifier:'..i,name='Modifier'}end;model.pages=2
    local b=P.layout(size[1],size[2],model)
    for i,t in ipairs(b.targets)do for j=1,i-1 do
        local a=b.targets[j]
        assert(t.x>=a.x+a.w or a.x>=t.x+t.w or t.y>=a.y+a.h or a.y>=t.y+t.h,'Tab/page buttons overlap')
    end end
end
print('polished mouse panel layouts and retained updates: passed')
