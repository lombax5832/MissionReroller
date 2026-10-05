-- Usage: luajit tests/test_worker_warmth.lua src/worker_warmth.lua
-- When the worker VMs stay warm (src/worker_warmth.lua): warm on the
-- galactic map, not while a gate is set; cold at once on a gate, and after
-- IDLE_SECONDS away from the map unless a search runs; warm again on the map.
local W=dofile(arg[1])
assert(W.IDLE_SECONDS==120)
local m=W.new()
local function at(now,map,loading,searching)return m.update(now,{map=map,loading=loading,searching=searching})end
-- Cold until the map is seen; the map behind a set gate does not warm.
assert(at(0,false,false)==nil and not m.warm(),'cold before the map')
assert(at(1,true,true)==nil and not m.warm(),'a set gate keeps it cold')
local action,reason=at(2,true,false)
assert(action=='warm' and reason=='galactic map open' and m.warm(),'the map warms')
assert(at(3,true,false)==nil,'warm once')
-- A gate set while warm cools at once, map or not.
action,reason=at(4,true,true)
assert(action=='cold' and reason=='loading or transition gate set' and not m.warm(),'a gate cools')
assert(at(5,false,true)==nil,'cold once')
-- Back on the ship: the map warms again.
assert(at(200,true,false)=='warm','the map warms again')
-- Away from the map: warm until IDLE_SECONDS have passed since it was last seen.
assert(at(201,false,false)==nil and at(319.9,false,false)==nil and m.warm(),'warm within the idle time')
-- A running search holds the workers past it.
assert(at(330,false,false,true)==nil and m.warm(),'a search keeps them warm')
action,reason=at(331,false,false,false)
assert(action=='cold' and reason=='galactic map closed for 120 s','idle time cools')
-- The map seen again restarts the idle time.
assert(at(400,true,false)=='warm')
assert(at(510,false,false)==nil and at(515,true,false)==nil and at(634,false,false)==nil and m.warm(),'the map restarts the idle time')
assert(at(635,false,false)=='cold')
-- Each machine keeps its own state.
assert(not W.new().warm())
print('Worker warmth: warm on the map, gates, idle time, searches and rewarming passed')
