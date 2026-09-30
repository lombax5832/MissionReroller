local H=dofile(assert(arg[1]))
-- Layout: to the right of the anchor, on its baseline, at its height, at every scale.
for _,case in ipairs({{1920,1080,{x=48,y=32,w=118,h=40,scale=1}},{1280,720,{x=32,y=21,w=79,h=27,scale=0.667}},
        {3440,1440,{x=64,y=43,w=157,h=53,scale=1.333}},{640,480,{x=16,y=10,w=40,h=14,scale=0.333}}})do
    local width,height,a=case[1],case[2],case[3]
    local b=H.layout(a,width,height)
    local name=width..'x'..height
    assert(b.fits,name)
    assert(math.abs(b.x-(a.x+a.w+32*a.scale))<1e-6 and b.y==a.y and b.h==a.h,name..': beside the anchor')
    assert(b.cap.x==b.x and b.cap.y==a.y and b.cap.h==a.h and b.cap.w>0,name..': cap')
    assert(b.keys.x>b.cap.x and b.keys.x<b.cap.x+b.cap.w and b.keys.cy==a.y+a.h/2,name..': keys inside the cap')
    assert(b.label.x>b.cap.x+b.cap.w and b.label.cy==b.keys.cy,name..': label after the cap')
    assert(math.abs(b.x+b.w-(b.label.x+b.label.w))<1e-6,name..': box ends with the label')
    assert(b.size>0 and b.size<a.h and b.border>=1,name..': text smaller than the anchor')
end
-- Text metrics from the engine widen the cap; the gap and padding scale with the anchor.
do
    local a={x=100,y=50,w=100,h=40,scale=2}
    local narrow=H.layout(a,1920,1080,function(text,size)return #text*size*0.4 end)
    local wide=H.layout(a,1920,1080,function(text,size)return #text*size*0.8 end)
    assert(wide.cap.w>narrow.cap.w and wide.w>narrow.w,'metrics decide the widths')
    assert(math.abs(narrow.keys.x-narrow.cap.x-16)<1e-6,'padding scales')
    assert(math.abs(narrow.label.x-(narrow.cap.x+narrow.cap.w)-30)<1e-6,'label space scales')
end
assert(not H.layout({x=1800,y=32,w=118,h=40,scale=1},1920,1080).fits,'no room to the right')
assert(not H.layout({x=48,y=-5,w=118,h=40,scale=1},1920,1080).fits,'below the screen')

-- Drawing: a recording engine counts what is created and destroyed.
local drawn,created,destroyed={},0,0
local function object(kind,value)local o={kind=kind,value=value};drawn[#drawn+1]=o;return o end
local resolution={1920,1080}
local e={Application={worlds=function()return {1,2}end,main_world=function()return 1 end},
    World={create_screen_gui=function()created=created+1;drawn={};return {id=created}end,destroy_gui=function()destroyed=destroyed+1;drawn={}end},
    Gui={resolution=function()return resolution[1],resolution[2]end,material=function()return {}end,
        rect=function()return object('rect')end,text=function(_,value)return object('text',value)end,
        text_extents=function(_,value,_,size)return {0},{#value*size*0.5},{#value*size*0.5}end},
    Material={set_scalar=function()end,set_vector2=function()end,set_vector4=function()end,set_texture=function()end},
    IdString64={from_hex=function(s)return s end},
    Vector2=setmetatable({x=function(v)return v[1]end},{__call=function(_,...)return {...}end}),
    Vector3=function(...)return {...}end,Color=function(...)return {...}end}
local function shown(value)for _,o in ipairs(drawn)do if o.kind=='text' and o.value==value then return true end end;return false end
local function rects()local n=0;for _,o in ipairs(drawn)do if o.kind=='rect' then n=n+1 end end;return n end
local hint=H.new(e)
local face={font='a',material='b',atlas='c'}
local anchor={x=48,y=32,w=118,h=40,scale=1}
assert(hint:show(anchor,face)==true and created==1)
assert(shown('F7') and shown('REROLL OPERATIONS') and rects()==5,'cap, four edges and two texts')
assert(hint:show(anchor,face)==true and created==1 and destroyed==0,'an unchanged anchor draws nothing new')
assert(hint:show({x=48.04,y=32,w=118,h=40,scale=1},face)==true and created==1,'sub-pixel jitter is ignored')
assert(hint:show({x=60,y=32,w=118,h=40,scale=1},face)==true and created==2 and destroyed==1,'a moved anchor redraws')
assert(hint:show({x=60,y=32,w=118,h=40,scale=1},{font='d',material='b',atlas='c'})==true and created==3,'a new face redraws')
resolution={1280,720}
assert(hint:show({x=60,y=32,w=118,h=40,scale=1},{font='d',material='b',atlas='c'})==true and created==4,'a new resolution redraws')
-- Metrics need a GUI, so a hint without room is created to be measured and destroyed again.
assert(hint:show({x=1200,y=32,w=118,h=40,scale=1},face)==false and created==5 and destroyed==5 and #drawn==0,'no room: nothing stays drawn')
hint:clear();assert(destroyed==5,'clearing an empty hint destroys nothing')
assert(hint:show(anchor,face)==true and created==6)
hint:clear();assert(destroyed==6 and #drawn==0)
hint:clear();assert(destroyed==6)
-- The cap reads the bound key when one is given, and the chord otherwise.
assert(hint:show(anchor,face,'NUMPAD 5')==true and created==7 and shown('NUMPAD 5') and not shown('F7'),'a bound key replaces F7')
assert(hint:show(anchor,face,'NUMPAD 5')==true and created==7,'the same key draws nothing new')
assert(hint:show(anchor,face)==true and created==8 and shown('F7'),'unbound again: F7 returns')
assert(H.layout(anchor,1920,1080,nil,'NUMPAD 5').cap.w>H.layout(anchor,1920,1080).cap.w,'the cap fits its text')
print('test_keybind_hint: layout and drawing passed')
