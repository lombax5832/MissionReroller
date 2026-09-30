-- Usage: luajit check_viewed_planet.lua <capture.lua> <src> <built entry> <missing page file>
-- Replays captured campaign memory of the viewed planet: the displayed board
-- equals its prediction, and the dialog's options build at every difficulty.
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
            local out=assert(io.open(arg[4],'w'));out:write(string.format('0x%x',page));out:close()
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
local function up(fn,name)
    for i=1,100 do local key,value=debug.getupvalue(fn,i);if key==name then return value end;if not key then break end end
    error('Missing upvalue '..name)
end
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local O=H.offsets(root)
local function module(name)return H.module(root..'/'..name..'.lua')end
CowboyBingusModLoader={api=1,version=18,open_log=function()return nil end}
update=function()end
dofile(arg[3])
local ready=up(up(update,'tick'),'on_prediction_ready')
local Planet=up(ready,'Planet')
local game=ffi.cast('uint8_t*',tonumber(fixture.game));local board=tonumber(fixture.board)
local planet=u(read(board+O.board.selection,8),4);assert(planet<512,'No viewed planet')
local seed=u(read(board+O.board.seed,4),0)
local key=read(board+O.board.campaign+0x1c+planet*O.campaign.definition_stride,4);local definitions
for _,offset in ipairs(O.board.definitions)do
    if read(board+offset,4)==key then definitions=board+offset;break end
end
assert(definitions,'Planet definitions are not cached')
local bytes=read(board+O.board.operations,110*92)
local count=u(read(board+O.board.mission_count,4),0);assert(count<=330)
local missions=count>0 and read(board+O.board.missions,count*76) or ''
local decoded={operations={}};local levels,seen={},{}
for row=0,109 do
    local at=row*92
    if bytes:byte(at+53)~=0 and bytes:byte(at+17)+bytes:byte(at+18)*256==planet then
        local op={row=row,operation_id=bytes:byte(at+25),seed=u(bytes,at+12),difficulty=bytes:byte(at+33),
            template_index=u(bytes,at+56),faction=u(bytes,at+36),missions={},modifiers={}}
        for slot=1,bytes:byte(at+89)do
            local offset=bytes:byte(at+85+slot)*76
            op.missions[slot]={seed=u(missions,offset+52),native_type=u(missions,offset+48),level_index=u(missions,offset+44)}
        end
        for i=1,bytes:byte(at+69)do op.modifiers[i]=u(bytes,at+56+i*4)end
        decoded.operations[#decoded.operations+1]=op
        if not seen[op.difficulty]then seen[op.difficulty]=true;levels[#levels+1]=op.difficulty end
    end
end
table.sort(levels)
assert(#decoded.operations>0,'The viewed planet has no operations')
local snapshot={board=board,planet=planet,seed=seed,operations=bytes,decoded=decoded}
print(string.format('planet=%d seed=%u operations=%d difficulties=[%s]',planet,seed,#decoded.operations,table.concat(levels,',')))
local model=Planet.bind(read,u,pointer,game,board,planet)
local inputs=model.inputs()
local environments=module('template_environments')(read,u,pointer,game,board,inputs.effects,inputs.biome_definition)
local shown={}
for _,op in ipairs(decoded.operations)do
    local tags=table.concat(environments(planet,op,true),',')
    if not shown[tags]then shown[tags]=true;print('environment tags: ['..tags..'] (row '..op.row..')')end
end
local predict=model.predictor(definitions)
local ok,why=module('verify_predicted_board')(snapshot,predict(seed),u)
assert(ok,'Displayed board differs from its prediction: '..tostring(why))
print('Displayed board equals its prediction')
local function names(list)local out={};for i,item in ipairs(list)do out[i]=item.name end;return table.concat(out,'; ')end
for _,difficulty in ipairs(levels)do
    local result,err=model.catalogue(snapshot,difficulty)
    assert(not err,tostring(err))
    assert(result.faction and #result.missions>0,'No options at difficulty '..difficulty)
    print(string.format('difficulty %d faction %d: missions: %s | modifiers: %s',difficulty,result.faction,names(result.missions),names(result.modifiers)))
end
print('Viewed planet: board prediction and dialog options passed on captured campaign memory')
