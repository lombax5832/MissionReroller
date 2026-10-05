# Dialog reachability test

In-game check of two dialog changes made after a search on 2026-10-05 scanned
261,043 seeds for a request the seed solver had already proven impossible
(`SEED_SOLVER_OFF reason=no draw path`, planet 268, difficulty 10, Search
and Destroy with Light Bugs and Lidar Station / SEAF Artillery excluded).

## What changed

- **Begin Search is off for an impossible request.** When the estimate says
  no seed gives the request now (`ESTIMATE none: no draw path`), the status
  reads `No seed gives this now. Change a rule to search` and Begin Search
  is disabled. The search's matcher uses the same predicted enemy forces
  and side objectives as the solver (no map stamps), so such a search could
  only scan in vain.
- **Unreachable options are disabled.** For each checked mission, after the
  estimate the dialog works out in the background which offered enemy
  forces and side objectives some draw path can still give or avoid, with
  the request's other rules (`SeedSolver.reachability` in
  `src/seed_solver_search.lua`). An option no path meets in either mode is
  greyed out with `This mission never gets this here at this difficulty`;
  a click skips a mode no path meets. Nothing is disabled for the
  any-mission group, while it is worked out, when a campaign event row of
  the difficulty could still match, or when the request itself has no path
  (so it can be edited back).

## Build

```powershell
$env:BINGUS_LOADER_ROOT = "$PWD\..\..\..\..\BingusSharedLoader"  # in a worktree only
python -B scripts/build.py
python -B tests/test_package.py
```

## Steps

1. Install the dev ZIP, Purge / Deploy, launch, stay alone on the ship.
2. Open the galactic map on a Terminid planet (268 on 2026-10-05), press F7,
   set difficulty 10.
3. Check Geological Survey, Spread Democracy and Search and Destroy. On each,
   exclude Lidar Station and SEAF Artillery in Side objectives, and accept
   Armored Bugs for the first two in Enemies.
4. Open Enemies for Search and Destroy and wait a second. On the 2026-10-05
   board Light Bugs, Bug Nursery and Balanced Terminids were greyed out;
   hovering one shows the reason. Clicking one does nothing.
5. Uncheck the side-objective exclusions: after a moment the enemy forces
   are enabled again.
6. Make a request with no path (accept Light Bugs on Search and Destroy
   before excluding the objectives, then exclude them): the status reads
   `No seed gives this now. Change a rule to search`, Begin Search does
   nothing, and every option stays enabled.
7. Run one normal search to check nothing else changed.

## Log lines

- `ESTIMATE none: no draw path` for step 6, and no `LUA_SEARCH_STARTED`
  after pressing Begin Search.
- No `ESTIMATE_BLOCKED` or `FILTER_CATALOGUE_BLOCKED` lines.

Which options are greyed out depends on the board: the planet, its
operations and the campaign effects. `tests/reachability_cases.lua` records
the 2026-10-05 board (`artifacts/planet-268`), where every answer agreed
with the solver's full plan.
