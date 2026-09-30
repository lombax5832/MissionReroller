-- Usage: luajit check_fast_prediction.lua <capture oracle> <src> <built entry>
-- The search predicts only the requested difficulty. This replays saved
-- campaign memory to show that it equals the complete prediction there, then
-- runs the packaged job with a real clock and reports its throughput.
local fixture=dofile(arg[1]);local root=arg[2];local ffi=require('ffi')
local function raw(s)return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
local pages={}
for _,r in ipairs(fixture.ranges)do pages[tonumber(r.address)]=raw(r.hex)end
local reads=0
local function read(a,n)
    reads=reads+1;a=tonumber(ffi.cast('uintptr_t',a))
    local pieces={};local remaining=n;local at=a
    while remaining>0 do
        local page=math.floor(at/4096)*4096;local offset=at-page
        local data=assert(pages[page],string.format('Missing composition page 0x%x',page))
        local count=math.min(remaining,4096-offset);pieces[#pieces+1]=data:sub(offset+1,offset+count)
        at=at+count;remaining=remaining-count
    end
    return table.concat(pieces)
end
local function u(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function pointer(s)local value=ffi.new('uint64_t[1]');ffi.copy(value,s,8);if value[0]==0 then return nil end;return ffi.cast('uint8_t*',value[0])end
local function up(fn,name)
    for i=1,100 do local key,value=debug.getupvalue(fn,i);if key==name then return value end;if not key then break end end
    error('Missing upvalue '..name)
end
CowboyBingusModLoader={api=1,version=18,open_log=function()return nil end}
update=function()end
dofile(arg[3])
local ready=up(up(update,'tick'),'on_prediction_ready')
local Planet=up(ready,'Planet');local make_job=up(ready,'make_search_job')
local Search=dofile(root..'/search_session.lua')
local game=ffi.cast('uint8_t*',tonumber(fixture.game));local definitions=tonumber(fixture.definitions)
local board=definitions-0x22b1a8
local bytes=raw(fixture.cases[1].operations);local planet
for row=0,109 do if bytes:byte(row*92+53)~=0 then planet=bytes:byte(row*92+17)+bytes:byte(row*92+18)*256 end end
local predict=Planet.bind(read,u,pointer,game,board,planet).predictor(definitions)
local function describe(op)
    local parts={op.row,op.id,op.seed,op.difficulty,op.category,op.faction,op.explicit_hash,tostring(op.valid),
        tostring(op.template_index),table.concat(op.modifiers,'/')}
    for _,m in ipairs(op.missions)do parts[#parts+1]=m.native_type..':'..m.seed..':'..m.level_index end
    return table.concat(parts,',')
end
local seeds={}
for _,case in ipairs(fixture.cases)do seeds[#seeds+1]=case.seed end
local state=25480438
for _=1,1500 do state=(state*1103515245+12345)%4294967296;seeds[#seeds+1]=state end
for _,edge in ipairs({0,1,2147483647,2147483648,4294967295})do seeds[#seeds+1]=edge end
local compared,operations=0,0
for _,seed in ipairs(seeds)do
    local complete=predict(seed);local by_difficulty={}
    for _,op in ipairs(complete)do
        by_difficulty[op.difficulty]=by_difficulty[op.difficulty] or {}
        table.insert(by_difficulty[op.difficulty],describe(op))
    end
    for difficulty=1,10 do
        local narrow=predict(seed,difficulty);local expected=by_difficulty[difficulty] or {}
        assert(#narrow==#expected,string.format('seed=%u difficulty=%d operation count %d, complete %d',seed,difficulty,#narrow,#expected))
        for i,op in ipairs(narrow)do
            assert(describe(op)==expected[i],string.format('seed=%u difficulty=%d\nsearch   %s\ncomplete %s',seed,difficulty,describe(op),expected[i]))
            operations=operations+1
        end
        compared=compared+1
    end
end
print(string.format('Search prediction equals the complete prediction: %d seeds, %d difficulty views, %d operations',#seeds,compared,operations))
-- Packaged job with a real clock. A filter that cannot match scans the budget.
local function run(required,limit,first)
    reads=0
    local job=make_job(read,function()end,function(take)
        local bound=Planet.bind(take,u,pointer,game,board,planet).predictor(definitions)
        return function(seed)return bound(seed,10)end,function(seed)return bound(seed)end
    end,{seed=first or 0,limit=limit,difficulty=10,required=required,quantum=4096,clock=os.clock,slice=0.016,batch=256,revalidate=1})
    local frames,longest,started=0,0,os.clock()
    while job.status=='running' do
        local t=os.clock();job:step(function()end);longest=math.max(longest,os.clock()-t);frames=frames+1
    end
    return job,frames,longest,os.clock()-started
end
local job,frames,longest,elapsed=run({[1]=true,[2]=true,[3]=true},65536)
assert(job.status=='matched',job.status..': '..tostring(job.error))
local again=Search.find({operations=predict(job.seed)},10,{[1]=true,[2]=true,[3]=true},{})
assert(again and again.row==job.operation.row and #job.operations>#predict(job.seed,10),'A match must carry the complete board')
print(string.format('Packaged search matched seed=%u row=%d after %d seeds in %d slices',job.seed,job.operation.row,job.attempts,frames))
job,frames,longest,elapsed=run({[1]=true,[9]=true,[11]=true},65536)
assert(job.status=='exhausted' and job.attempts==65536 and job.next_seed==65536,job.status..': '..tostring(job.error))
print(string.format('Packaged search scanned %d seeds in %.2f s of work: %.0f seeds/s, %d slices, longest %.1f ms, %d memory reads',
    job.attempts,elapsed,job.attempts/elapsed,frames,longest*1000,reads))
assert(longest<0.25,'A slice must stay near its time budget')
