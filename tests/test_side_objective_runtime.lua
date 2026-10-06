-- Usage: luajit test_side_objective_runtime.lua <src>
-- The side-objective runtime with a fake host and planet model: the binder
-- gives every mission its objectives and rows, and the hover observer
-- compares a prediction with the preview descriptor's list once per mission.
local src=assert(arg[1])
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local O=H.offsets(src)
local SideObjectives=H.module(src..'/side_objective_prediction.lua')
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local memory={}
local function poke(address,bytes)for i=1,#bytes do memory[address+i-1]=bytes:byte(i)end end
local function read(address,size)
    local out={};for i=0,size-1 do out[#out+1]=string.char(memory[address+i] or 0)end
    return table.concat(out)
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
-- api.pointer decodes bytes; host.pointer reads the pointer at an address.
local function decode(bytes,offset)
    offset=offset or 0
    local value=u(bytes,offset)+u(bytes,offset+4)*4294967296
    return value>=0x10000 and value or nil
end
local function pointer(address)return decode(read(address,8))end
local game,board=0x10000000,0x20000000
poke(game+O.rva.board,word(board)..word(0))
local lidar,artillery,nest=0xf1969b14,0x86cfeedb,0xb3dd50be
local records={}
for _,id in ipairs({1,lidar,artillery,nest})do records[id]={id=id,cap=1,minimum=0,maximum=0,mask=0,environments={0,0,0,0}}end
local function pool(list)
    local out={}
    for i=1,32 do local e=list[i];out[i]=e and {id=e[1],role=e[2],weight=1,group=0,minimum=e[3] or 0,maximum=1} or {id=0,role=0,weight=0,minimum=0,maximum=0}end
    return out
end
local mission={category=1,lo=1,hi=1,pool=pool({{1,0,1},{lidar,3},{artillery,3},{nest,3}}),biomes={0}}
local contexts=0
local inputs={objective=function(id)return records[id] or records[1]end,disabled=function()return false end,
    mission=function()return mission end,counts=function()return {side=2,tactical=0,substeps=0}end,scale=function()end,
    environments=function()return function()return 1 end,{[1]=true}end,
    context=function(planet,effect)contexts=contexts+1;assert(planet==268 and effect==77);return {modifiers={0xa6afd597},banned={},extra=false}end}
local tags={effect_id=function(category,id,planet)assert(category==4 and id==5 and planet==268);return 77 end}
local model={index=268,objective_inputs=function()return inputs end,constellation_inputs=function()return tags end}
local logs,on_top,running={},true,false
local binders={}
local function emit(s)logs[#logs+1]=s end
local host={log={debug=emit,info=emit,warn=emit,error=emit},read=read,pointer=pointer,u=u,O=O,
    reroll_session={view=function()return {running=running}end},map={on_top=function()return on_top end},
    when_initialized=function(bind)binders[#binders+1]=bind end}
local lib={SideObjectives=SideObjectives,Board=H.board(src),Planet={bind=function(_,_,_,_,b,planet)assert(b==board and planet==268);return model end}}
local chunk=assert(loadfile(src..'/side_objective_runtime.lua'))
local env=setmetatable({host=host,lib=lib,hooks={}},{__index=_G,__newindex=function(_,k)error('global '..k)end})
setfenv(chunk,env)
local result=chunk()
assert(type(result.bind_objectives)=='function' and type(result.observe_objectives)=='function' and #binders==1)
assert(logs[1]:find('SIDE_OBJECTIVE_CHECK',1,true))
binders[1]({api={pointer=decode},game=game})
-- The binder: every mission gets its native list and its rows.
local annotate=result.bind_objectives(model)
local op={difficulty=6,effect_id=77,missions={{native_type=59,seed=11},{native_type=59,seed=12}}}
annotate(op)
for _,m in ipairs(op.missions)do
    assert(m.objective_list[1].id==1 and #m.objective_list==3,'Primary and two side objectives')
    local n=0;for row in pairs(m.objectives)do assert(row==lidar or row==artillery or row==nest);n=n+1 end
    assert(n==2,'Two rows')
end
-- A displayed operation names its category and id instead of an effect.
local shown={difficulty=6,missions={{native_type=59,seed=11}}};annotate(shown,4,5)
assert(SideObjectives.describe(shown.missions[1].objective_list)==SideObjectives.describe(op.missions[1].objective_list))
-- The observer: the hovered mission's preview against the prediction.
local seed=11
poke(board+O.board.selection_row,word(3))
local operation=board+O.board.operations+3*92
poke(operation+16,string.char(268%256,1));poke(operation+24,string.char(5));poke(operation+28,word(4));poke(operation+52,string.char(1))
poke(board+O.board.campaign+268*O.campaign.definition_stride+0x18,word(0xabc))
poke(board+O.board.mission_count,word(1))
poke(board+O.board.missions+40,word(3));poke(board+O.board.missions+48,word(59));poke(board+O.board.missions+52,word(seed))
local function preview(ids)
    local d=word(seed)..word(0)..string.char(2,6,0,0)..word(0xabc)..string.rep('\0',10)..string.char(59,0)..'\0'..string.char(#ids)..'\0\0'
    for _,id in ipairs(ids)do d=d..word(id)end
    d=d..string.rep('\0',0xc7-#d)..string.char(1)..word(0xa6afd597)
    poke(board+O.board.mission_preview,d..string.rep('\0',0xe8-#d))
end
local ids={};for _,o in ipairs(op.missions[1].objective_list)do ids[#ids+1]=o.id end
preview(ids)
result.observe_objectives(1)
assert(logs[#logs]:find('SIDE_OBJECTIVE_CHECK planet=268 row=3 type=59 seed=11 difficulty=6',1,true),logs[#logs])
assert(logs[#logs]:find('modifiers=[a6afd597] predicted_modifiers=[a6afd597]',1,true) and logs[#logs]:find('modifiers_agree=true agree=true',1,true),logs[#logs])
local count=#logs
result.observe_objectives(2);assert(#logs==count,'Logged once per mission')
-- A different live list disagrees.
preview({ids[1],0x12345678})
result.observe_objectives(3);assert(logs[#logs]:find('agree=false',1,true) and logs[#logs]:find('live=[00000001,12345678]',1,true),logs[#logs])
-- Quiet while searching, off the map, or throttled.
preview({ids[1]});count=#logs
running=true;result.observe_objectives(4);running=false
on_top=false;result.observe_objectives(5);on_top=true
result.observe_objectives(5.2)
assert(#logs==count,'No check during a search, off the map or within half a second')
result.observe_objectives(6);assert(#logs==count+1)
-- A failure is reported once and never raised.
inputs.counts=function()error('broken counts')end
preview({ids[1],ids[2]})
result.observe_objectives(7);preview({ids[2]});result.observe_objectives(8)
assert(logs[#logs]:find('SIDE_OBJECTIVE_CHECK_BLOCKED',1,true) and not logs[#logs-1]:find('BLOCKED',1,true),logs[#logs])
print('Side objective runtime: binding, displayed operations, preview observer, throttling and fail-quiet diagnostics passed')
