-- Usage: luajit check_seed_solver_search.lua <capture.lua> <src> <built entry>
-- Runs the built entry's own search (prediction_search_runtime.lua
-- on_prediction_ready and advance_prediction_search) on captured campaign
-- memory of the viewed planet (scripts/check_live_planet.py), with the seed
-- solver proposing the candidates (src/seed_solver_search.lua): requests
-- made from the displayed board's missions, with enemy-force,
-- side-objective and Day / Night rules, must match through the solver, and
-- a request the solver cannot seed must fall back to scanning. The runtime
-- confirms each match on the complete prediction, as in game.
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
local reroll_session={view=function()return {request=request}end,report=function()end,progress=function()end,
    result=function()end,advance=function(status)session.status=status end,finish=function(status)session.status=status end}
local clock=os.clock
H.natives(update,{api={pointer=pointer,time=clock},game=game,ffi=ffi})
set(ready,'read',read)
-- The dialog validates its own requests (tests/test_dialog.py); none here.
up(ready,'hooks').validate_search_request=nil
set(ready,'snapshot',function()return snapshot end);set(ready,'emit',emit);set(ready,'reroll_session',reroll_session)
set(advance,'on_search_match',nil)
up(ready,'M').dialog_enabled=false

-- Day / Night on a synthetic sky spinning in 15.7 hours, with the capture's
-- level-node longitudes (tests/test_seed_solver_chain.lua builds the same).
local Real=up(ready,'DayNight')
local NOW=84733314.67
local single=ffi.new('float[1]')
local function float(s,at)ffi.copy(single,s:sub(at+1,at+4),4);return single[0]end
local PlanetSky=H.module(root..'/planet_sky.lua')(H.module(root..'/generation_rng.lua'))
local function sky_planet()
    local Q={0,0,0,1}
    local sky={seed=1,viewer=0,bodies={[0]={before=Q,after=Q,parent=9,distance=500,orbit={90000,90000,0},
        spin={56520,56520,0},phase={0.4,0.4}}}}
    local day=PlanetSky.day_length(sky,NOW)
    local p={planet=planet,sky=sky,definitions=definitions,day_length=day,buffer=PlanetSky.buffer(day,Real.BAND,Real.WANTED)}
    function p.longitude(node)
        local position=read(definitions+node*0x88+4,8)
        return math.deg(math.atan2(float(position,4),float(position,0)))
    end
    return p
end
local DayNight=setmetatable({load=sky_planet,war_time=function()return NOW end},{__index=Real})
set(ready,'DayNight',DayNight)
set(ready,'map',{sky=function()return nil end})

-- The operation in progress keeps its missions whatever the seed, so a
-- request it satisfies matches it at once (in game, as an existing match,
-- before any search). Requests come from another difficulty; no match may
-- be it.
local active=read(board+O.board.active_operation,92)
local fixed=active:byte(53)~=0 and active:byte(17)+active:byte(18)*256==planet and u(active,0) or nil
local fixed_difficulty=fixed and active:byte(33)
-- Times the paths and chain set-up apart from the input reads.
-- gap_ms is the longest work between two of its pauses (yield points).
local source_ms,gap_ms,gap_at=0,0,nil
local Timed=setmetatable({source=function(spec)
    local started=clock()
    local pause=spec.checkpoint
    local last,count=started,0
    spec.checkpoint=function()
        local now=clock()
        count=count+1
        if (now-last)*1000>gap_ms then gap_ms,gap_at=(now-last)*1000,count end
        pause()
        last=clock()
    end
    local result,why=SeedSolver.source(spec)
    local now=clock()
    if (now-last)*1000>gap_ms then gap_ms,gap_at=(now-last)*1000,'end' end
    source_ms=(now-started)*1000
    return result,why
end},{__index=SeedSolver})
local function search(name,r,solver,bounded)
    request=r;logs={};session.status=nil;source_ms,gap_ms,gap_at=0,0,nil
    set(ready,'SeedSolver',solver~=false and Timed or nil)
    local started=clock()
    ready(snapshot,definitions,started)
    local current=up(advance,'current_search')
    assert(current,name..': search not started: '..table.concat(logs,'\n'))
    while up(advance,'current_search')do advance(nil,clock())end
    local took=clock()-started
    local text=table.concat(logs,'\n')
    local line=text:match('SEED_SOLVER[^\n]*') or 'no solver line'
    local match=text:match('LUA_SEARCH_MATCH seed=[^\n]*')
    if bounded and not match then
        local attempts=tonumber(text:match('LUA_SEARCH_%u+ attempts=(%d+)'))
        print(string.format('  %s: no match in %d candidates, %.2f s (%.0f seeds/s)',name,attempts,took,attempts/math.max(took,0.001)))
        return text,nil,attempts,took
    end
    assert(session.status=='search_matched' and match,name..': '..tostring(session.status)..'\n'..text)
    local found=tonumber(match:match('seed=(%d+)'))
    assert(tonumber(match:match('row=(%d+)'))~=fixed,name..': matched the operation in progress')
    local attempts=tonumber(match:match('attempts=(%d+)'))
    print(string.format('  %s: %s (paths and chain %.0f ms, longest stretch without a pause %.0f ms at %s); matched seed %u row %s after %d candidates in %.2f s, %s, longest slice %s ms',
        name,line,source_ms,gap_ms,tostring(gap_at),found,match:match('row=(%d+)'),attempts,took,match:match('mode=%w+') or 'mode=none',
        match:match('max_slice_ms=([%d.]+)')))
    print(string.format('    frozen inputs: %s ranges, %s bytes (limits 20000 and 2097152)',match:match('ranges=(%d+)'),
        match:match('bytes=(%d+)')))
    -- The set-up yields within its frame slice (the search's 16 ms).
    assert(gap_ms<=5,string.format('%s: %.0f ms without a pause in the solver set-up',name,gap_ms))
    return text,found,attempts,took
end

-- Requests from the displayed board: a row at the highest difficulty with
-- the most missions, its missions' families and offered rules.
local function family(kind)
    for id,option in ipairs(Search.options)do for _,native in ipairs(option.ids)do if native==kind then return id end end end
end
local best
for _,op in ipairs(decoded.operations)do
    if op.row<30 and op.difficulty~=fixed_difficulty and (not best or op.difficulty>best.difficulty or (op.difficulty==best.difficulty and #op.missions>#best.missions))then
        best=op
    end
end
local difficulty=best.difficulty
local fams={}
for _,m in ipairs(best.missions)do local f=family(m.native_type);if f then fams[#fams+1]=f end end
local model=Planet.bind(read,u,pointer,game,board,planet)
local catalogue=model.catalogue(snapshot,difficulty)
local function required(n)local r={};for i=1,n do r[fams[i]]=true end;return r end
print(string.format('planet=%d seed=%u difficulty=%d row=%d families=%s, in progress: row %s',planet,seed,difficulty,best.row,
    table.concat(fams,','),tostring(fixed)))
jit.flush()
local function case(name,r,expect)
    r.difficulty=difficulty;r.limit=r.limit or 1000000
    local text=search(name,r)
    if expect=='solver' then
        assert(text:find('SEED_SOLVER paths=',1,true) and text:find('mode=solver',1,true),name..': not solved\n'..text)
    else
        assert(text:find('SEED_SOLVER_OFF reason='..expect,1,true),name..': expected fallback '..expect..'\n'..text)
    end
    return text
end
case('one mission',{required=required(1)},'solver')
if #fams>=2 then case('two missions',{required=required(2)},'solver')end
if #fams>=3 then case('three missions',{required=required(3)},'solver')end
local tags=catalogue.constellation_groups[fams[1]]
if tags and tags.list[1]then
    case('one mission with an enemy force',{required=required(1),constellations={groups={[fams[1]]={[tags.list[1].id]='accept'}}}},'solver')
end
local rows=catalogue.objective_groups and catalogue.objective_groups[fams[1]]
if rows and rows.list[1]then
    case('one mission with a side objective',{required=required(1),objectives={groups={[fams[1]]={[rows.list[1].id]='require'}}}},'solver')
end
if #fams>=2 then
    for _,side in ipairs({'night','day'})do
        local ok,err=pcall(case,'two missions at '..side,{required=required(2),time=side},'solver')
        if not ok then
            -- No operation ID of the difficulty may be on that side now.
            assert(tostring(err):find('daynight_ids=0/',1,true),err)
            print('  two missions at '..side..': no operation ID on that side now')
        end
    end
end
-- A request without a required mission is scanned in order.
local other
for id in ipairs(Search.options)do
    local used=false
    for _,f in ipairs(fams)do if f==id then used=true end end
    if not used and catalogue.mission_set[id]then other=id;break end
end
case('an excluded mission only',{required={},excluded={[other]=true}},'no required mission')
-- A selective request: every mission; the first carries only the last
-- enemy force offered for it, the second the last two side objectives
-- offered for it. Solved, then scanned for a bounded count.
local n=math.min(#fams,3)
local hard={difficulty=difficulty,required=required(n),limit=1000000}
local offered=catalogue.constellation_groups[fams[1]]
if offered and offered.list[1]then
    local rules={}
    for i,item in ipairs(offered.list)do rules[item.id]=i==#offered.list and 'accept' or 'exclude'end
    hard.constellations={groups={[fams[1]]=rules}}
end
local wanted=n>=2 and catalogue.objective_groups and catalogue.objective_groups[fams[2]]
if wanted and wanted.list[1]then
    local rules={}
    for i=math.max(1,#wanted.list-1),#wanted.list do rules[wanted.list[i].id]='require'end
    hard.objectives={groups={[fams[2]]=rules}}
end
local text,_,solved,solved_s=search(n..' missions with an enemy force and a side objective',hard)
assert(text:find('mode=solver',1,true),'The selective request was not solved')
hard.limit=20000
local _,found,attempts,took=search('the same, scanning (no solver)',hard,false,true)
print(string.format('  solver: %d candidates in %.2f s; scanning: %d candidates in %.2f s%s',solved,solved_s,attempts,took,
    found and '' or ' without a match'))
print('Seed solver search: requests matched through the solver on captured campaign memory')
