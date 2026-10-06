-- Usage: check_game_jit.lua <capture.lua> <src> <built entry> [builds]
-- Builds the dialog's filter catalogue (prediction_dialog_runtime.lua
-- catalogue_for, src/filter_catalogue.lua) on captured campaign memory again
-- and again, every difficulty, so its loops compile. Run inside the game's
-- own lua51.dll (tests/test_game_jit.py): LuaJIT 2.1.0-alpha's compiled loop
-- read a field stored after a call back as the table constructor's value
-- (nil, or a placeholder), and the dialog showed "Eligibility unavailable"
-- from the third or so opening of a session. The pinned LuaJIT never did.
local fixture=dofile(arg[1]);local root=arg[2];local ffi=require('ffi')
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local pages={}
for _,r in ipairs(fixture.ranges)do pages[tonumber(r.address)]=raw(r.hex)end
local function read(a,n)
    a=tonumber(ffi.cast('uintptr_t',a))
    local pieces={};local remaining=n;local at=a
    while remaining>0 do
        local page=math.floor(at/4096)*4096;local offset=at-page
        local data=assert(pages[page],string.format('Missing capture page 0x%x',page))
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
local function slot(fn,name)
    for i=1,200 do local key=debug.getupvalue(fn,i);if key==name then return i end;if not key then break end end
end
local function up(fn,name)
    local i=assert(slot(fn,name),'Missing upvalue '..name)
    local _,value=debug.getupvalue(fn,i);return value
end
local function set(fn,name,value)debug.setupvalue(fn,assert(slot(fn,name),'Missing upvalue '..name),value)end
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local O=H.offsets(root)
CowboyBingusModLoader={api=1,version=18,open_log=function()return nil end}
update=function()end
dofile(arg[3])
local tick=up(update,'tick')
local ready,advance=up(tick,'on_prediction_ready'),up(tick,'advance_prediction_search')
local Planet,Search,SeedSolver=up(ready,'Planet'),up(ready,'Search'),up(ready,'SeedSolver')
local FilterRules=up(ready,'FilterRules')

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
local decoded={operations={}}
for row=0,109 do
    local at=row*92
    if bytes:byte(at+53)~=0 and bytes:byte(at+17)+bytes:byte(at+18)*256==planet then
        local op={row=row,operation_id=bytes:byte(at+25),seed=u(bytes,at+12),difficulty=bytes:byte(at+33),
            template_index=u(bytes,at+56),faction=u(bytes,at+36),missions={},modifiers={}}
        for n=1,bytes:byte(at+89)do
            local offset=bytes:byte(at+85+n)*76
            op.missions[n]={seed=u(missions,offset+52),native_type=u(missions,offset+48),level_index=u(missions,offset+44)}
        end
        for i=1,bytes:byte(at+69)do op.modifiers[i]=u(bytes,at+56+i*4)end
        decoded.operations[#decoded.operations+1]=op
    end
end
local snapshot={board=board,planet=planet,seed=seed,operations=bytes,decoded=decoded,fingerprint='capture',context='capture',
    active=nil}

-- The runtime's host services, pointed at the capture.
local logs={}
local function emit(line)logs[#logs+1]=line end
local request
local session={status=nil}
local estimate
local reroll_session={view=function()return {request=request}end,report=function()end,progress=function()end,
    estimate=function(e)estimate=e or estimate end,
    result=function()end,advance=function(status)session.status=status end,finish=function(status)session.status=status end}
local clock=os.clock
H.natives(update,{api={pointer=pointer,time=clock},game=game,ffi=ffi})
set(ready,'read',read)
-- The dialog validates its own requests (tests/test_dialog.py); none here.
local validate=up(ready,'hooks').validate_search_request
set(ready,'snapshot',function()return snapshot end);set(ready,'log',{debug=emit,info=emit,warn=emit,error=emit});set(ready,'reroll_session',reroll_session)
set(advance,'on_search_match',nil)
up(ready,'M').dialog_enabled=false
local catalogue_for=up(validate,'catalogue_for')
set(catalogue_for,'read',read)
local difficulties={}
for _,op in ipairs(decoded.operations)do difficulties[op.difficulty]=true end
local list={};for d in pairs(difficulties)do list[#list+1]=d end;table.sort(list)
local builds=tonumber(arg[4]) or 50
for i=1,builds do
    for _,d in ipairs(list)do
        local ok,result=pcall(catalogue_for,snapshot,d,nil,function(row)return row<30 end)
        assert(ok and result,string.format('Catalogue build %d, difficulty %d: %s',i,d,tostring(result)))
    end
end
print(string.format('Game JIT: catalogue built %d times for difficulties %s on %s (%s, JIT %s)',builds,
    table.concat(list,','),arg[1]:match('([^/\\]+)[/\\][^/\\]+$') or arg[1],jit.version,tostring(jit.status())))
