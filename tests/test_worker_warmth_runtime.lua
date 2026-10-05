-- Usage: luajit tests/test_worker_warmth_runtime.lua <built entry>
-- Warm worker VMs in the assembled entry (prediction_search_runtime.lua
-- tick_workers): the galactic map warms the pool and logs the screens and
-- gates, a full pool logs once, a set gate or a failed read cools it, and
-- a STOPPED error cools it through the identity runtime's hook.
local H=dofile((arg[0]:match('^(.*[/\\])') or '')..'harness.lua')
local up=H.up
local logs={}
CowboyBingusModLoader={api=1,version=18,open_log=function()return {write=function(_,s)logs[#logs+1]=s end,flush=function()end,close=function()end}end}
update=function()end;shutdown=function()end
dofile(arg[1])
local tick=up(update,'tick')
local advance=up(tick,'advance_prediction_search')
local tick_workers=up(advance,'tick_workers')
local function logged(pattern)
    for _,line in ipairs(logs)do if line:find(pattern)then return line end end
end
-- The frame's native handles: only their presence matters here.
up(tick_workers,'ffi',{},true)
local fake={max_workers=2,idle=0,warm_now=false,calls={}}
function fake.warm(on)fake.calls[#fake.calls+1]=on;fake.warm_now=on;local n=on and 0 or fake.idle;if not on then fake.idle=0 end;return n end
function fake.tick()if fake.warm_now and fake.idle<fake.max_workers then fake.idle=fake.idle+1 end;return 0 end
function fake.reap()return 0 end
function fake.state()return {idle=fake.idle,retired=0,warm=fake.warm_now,full=false}end
up(tick_workers,'worker_pool',fake,true)
local map=up(tick_workers,'map')
local on_top,gate,fail=true,false,false
map.stack=function()if fail then error('missing pointer')end;return 'stack' end
map.on_top=function()return on_top end
map.screens=function()return on_top and {15} or {3},1 end
map.gates=function()return gate,'loading_gate='..(gate and 1 or 0)..' transition_gate=0 transition=0000000000000000' end

-- The map on top warms the pool; it then fills over the next frames.
tick_workers(1)
assert(fake.calls[1]==true,'the map warms the pool')
assert(logged('^SEED_SOLVER_WORKERS_WARM reason=galactic map open screens=15 loading_gate=0'),'warm line')
tick_workers(1.01)
assert(fake.idle==2 and logged('^SEED_SOLVER_WORKERS_WARMED idle=2 max_workers=2'),'warmed line once full')
local lines=#logs
for t=1.3,3,0.3 do tick_workers(t)end
assert(#logs==lines and #fake.calls==1,'nothing more while warm and full')
-- A search used the idle workers and they were closed: warmed again once
-- fresh ones replace them.
local function count(pattern)local n=0;for _,line in ipairs(logs)do if line:find(pattern)then n=n+1 end end;return n end
fake.idle=0
tick_workers(3.1);tick_workers(3.2)
assert(fake.idle==2 and count('^SEED_SOLVER_WORKERS_WARMED idle=2')==2,'warmed again after a search')
-- A set gate cools it at once, with the idle workers it closed.
gate=true;on_top=false
tick_workers(4)
assert(fake.calls[2]==false,'a gate cools the pool')
assert(logged('^SEED_SOLVER_WORKERS_COLD reason=loading or transition gate set closed=2 screens=3 loading_gate=1'),'cold line')
-- Back on the ship, then a failed read: counted as loading.
gate=false;on_top=true
tick_workers(5);assert(fake.calls[3]==true,'warm again')
fail=true
tick_workers(6)
assert(fake.calls[4]==false and logged('COLD reason=loading or transition gate set closed=%d read failed: '),'a failed read cools')
-- A STOPPED error: the frame stops running, so the hook cools the pool.
fail=false;tick_workers(7);assert(fake.calls[5]==true)
up(update,'tick',function()error('boom')end,true)
update()
assert(fake.calls[6]==false,'a STOPPED error cools the pool')
print('Worker warmth runtime: warm on the map, warmed once and again after a search, gate and failed-read cooling, cooled on STOPPED passed')
