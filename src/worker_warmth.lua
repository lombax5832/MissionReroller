-- When the seed solver's worker VMs stay warm (src/seed_solver_workers.lua
-- pool.warm): idle VMs hold address space below 2 GB, which the game needs
-- in a mission, so they are kept only on the ship.
--
-- Warm from the moment the galactic map is on top of the screen stack, which
-- happens only on the ship. Cold at once when a loading or transition gate
-- of the UI root is set (a drop into a mission passes a loading screen), and
-- after IDLE_SECONDS without the map on top while no search runs: what the
-- gates read at a drop is not yet recorded in game, so this keeps workers
-- out of a mission even if they stay clear. Warming again costs a few
-- milliseconds the next time the map is opened.
--
-- new() -> {update(now, seen) -> 'warm' | 'cold' | nil, reason}, where
-- seen = {map=<galactic map on top>, loading=<a gate set>, searching=<a
-- search runs>}; nil when nothing changes.
local W={IDLE_SECONDS=120}
function W.new()
    local warm,last_map=false,nil
    local machine={}
    function machine.update(now,seen)
        if seen.map then last_map=now end
        if warm then
            if seen.loading then warm=false;return 'cold','loading or transition gate set' end
            if not seen.searching and not seen.map and now-last_map>=W.IDLE_SECONDS then
                warm=false
                return 'cold',string.format('galactic map closed for %d s',W.IDLE_SECONDS)
            end
        elseif seen.map and not seen.loading then
            warm=true
            return 'warm','galactic map open'
        end
    end
    function machine.warm()return warm end
    return machine
end
return W
