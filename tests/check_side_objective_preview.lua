-- Usage: luajit check_side_objective_preview.lua <capture.lua> <src> <missing page file>
-- Replays captured memory of the galactic map: the side objectives the Lua
-- port predicts for the last previewed mission, with the planet's world
-- modifiers collected as for a search, equal the preview descriptor's list.
-- A page absent from the capture is written to <missing page file>, exit 3.
local fixture=dofile(arg[1]);local root=arg[2];local ffi=require('ffi')
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local pages={}
for _,r in ipairs(fixture.ranges)do pages[tonumber(r.address)]=raw(r.hex)end
local function read(a,n)
    a=tonumber(ffi.cast('uintptr_t',a))
    local pieces={};local remaining=n;local at=a
    while remaining>0 do
        local page=math.floor(at/4096)*4096;local offset=at-page
        local data=pages[page]
        if not data then
            local out=assert(io.open(arg[3],'w'));out:write(string.format('0x%x',page));out:close()
            os.exit(3)
        end
        local count=math.min(remaining,4096-offset);pieces[#pieces+1]=data:sub(offset+1,offset+count)
        at=at+count;remaining=remaining-count
    end
    return table.concat(pieces)
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function pointer(s,o)
    local value=ffi.new('uint64_t[1]');ffi.copy(value,s:sub((o or 0)+1,(o or 0)+8),8)
    if value[0]<0x10000 then return nil end
    return ffi.cast('uint8_t*',value[0])
end
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local O=H.offsets(root)
local Planet,m=H.planet_model(root)
local Prediction=m.objectives
local game=ffi.cast('uint8_t*',tonumber(fixture.game));local board=tonumber(fixture.board)
local preview=read(board+O.board.mission_preview,0xe8)
local seed,difficulty,kind=u(preview,0),preview:byte(10),preview:byte(27)+preview:byte(28)*256
local live={};for i=0,preview:byte(0x1e)-1 do live[#live+1]=string.format('%08x',u(preview,0x20+i*4))end
local modifiers={};for i=0,preview:byte(0xc8)-1 do modifiers[#modifiers+1]=string.format('%08x',u(preview,0xc8+i*4))end
-- The previewed mission's operation and planet, from the board's missions.
local count=u(read(board+O.board.mission_count,4),0);local rows=read(board+O.board.missions,count*76)
local row
for i=0,count-1 do if u(rows,i*76+48)==kind and u(rows,i*76+52)==seed then row=u(rows,i*76+40)end end
if not row then
    print(string.format('The previewed mission (type %d, seed %u) is not on the board; hover a mission of the planet on screen',kind,seed))
    os.exit(2)
end
local op=read(board+O.board.operations+row*92,92)
local planet=op:byte(17)+op:byte(18)*256
local model=Planet.bind(read,u,pointer,game,board,planet)
local inputs,tags=model.objective_inputs(),model.constellation_inputs()
local context=inputs.context(planet,tags.effect_id(u(op,28),op:byte(25),planet))
local record=inputs.mission(kind)
local environment=inputs.environments(planet,kind,context.modifiers)
local list=Prediction.resolve(seed,difficulty,record,inputs.counts(difficulty),inputs.scale(record.category),
    {objective=inputs.objective,disabled=inputs.disabled,context=context,environment=function()return environment(seed)end})
local predicted,mods={},{}
for _,o in ipairs(list)do predicted[#predicted+1]=string.format('%08x',o.id)end
for _,hash in ipairs(context.modifiers)do mods[#mods+1]=string.format('%08x',hash)end
local agree=table.concat(predicted,',')==table.concat(live,',')
local mods_agree=table.concat(mods,',')==table.concat(modifiers,',')
print(string.format('planet=%d row=%d type=%d seed=%u difficulty=%d environment=%d\n  modifiers live=[%s] predicted=[%s] agree=%s\n  objectives live=[%s]\n  predicted=[%s] (%s)\n  agree=%s',
    planet,row,kind,seed,difficulty,environment(seed),table.concat(modifiers,','),table.concat(mods,','),tostring(mods_agree),
    table.concat(live,','),table.concat(predicted,','),Prediction.describe(list),tostring(agree)))
os.exit(agree and mods_agree and 0 or 1)
