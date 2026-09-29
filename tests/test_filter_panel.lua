local make=dofile(assert(arg[1]))
local created,destroyed,updates=0,0,0
local rects,rect_updates,rect_deletes=0,0,0
local world={};local worlds={1,world}
local e={Application={worlds=function()return worlds end,main_world=function()return 1 end},
    World={create_screen_gui=function()created=created+1;return {}end,destroy_gui=function()destroyed=destroyed+1 end},
    Gui={resolution=function()return 1920,1080 end,material=function()return {}end,
         rect=function()rects=rects+1;return rects end,
         update_rect=function()rect_updates=rect_updates+1 end,
         destroy_rect=function()rect_deletes=rect_deletes+1 end,
         text=function()return {}end,update_text=function()updates=updates+1 end},
    Material={set_scalar=function()end,set_vector2=function()end,set_vector4=function()end,set_texture=function()end},
    IdString64={from_hex=function(s)return s end},Vector2=function(...)return {...}end,
    Vector3=function(...)return {...}end,Color=function(...)return {...}end}
local p=make(e);local f={font='a',material='b',atlas='c'}
assert(p:show({'Title','Filters'},f));assert(created==1)
p:show({'Title','Filters'},f);assert(created==1 and updates==0)
p:show({'Title','Changed'},f);assert(updates==26)
p:show({'Title','Changed'},f,{x=100,y=200});assert(rects==6)
p:show({'Title','Changed'},f,{x=150,y=250});assert(rects==6 and rect_updates==4 and updates==26)
p:show({'Title','Changed'},f);assert(rect_deletes==4)
p:clear();assert(destroyed==1)
p:show({'Title'},f);worlds={1};p:clear();assert(destroyed==1,'do not destroy departed-world handles')
print('filter panel retained lifecycle: passed')
