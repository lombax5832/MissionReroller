# Seed solver worker VMs test

In-game check of the seed solver's walk in worker VMs
([NATIVE_SOLVER_RESEARCH.md](NATIVE_SOLVER_RESEARCH.md), probe results in
[WORKER_PROBE_TEST.md](WORKER_PROBE_TEST.md)). **Run in game 2026-10-05: a
request matched by one seed in 28 million was found, published and verified
in 8.3 s. Cancel and quit during a search not yet exercised.**

## What changed

A search that the seed solver can seed (`SEED_SOLVER paths=...`) no longer
walks on the game's main thread. Up to eight worker VMs from the game's own
`lua51.dll` (half the logical processors, at most eight) walk the chain on
thread-pool threads at below-normal priority, each from its own random
starts, and hand candidates back. The main thread keeps everything else as
before: Day / Night acceptance of each candidate, prediction, matching,
validation, publication.

- `src/seed_solver_workers.lua`: the pool. It scans the address space
  below 2 GB before a search and starts only as many workers as fit beside
  a 16 MB reserve. The first worker starts with the search; the rest start
  over the next frames, about 2 ms of set-up per frame. A worker whose heap
  passes 16 MB is stopped. A worker VM is closed only after its thread has
  left it.
- `src/seed_solver_codec.lua`: the paths as compact text, shared missions
  written once. On the planet 173 exclusion request that is 86 KB, and a
  worker's heap is 0.5 MB after set-up and 1.4 MB at its peak.
- The workers share each job's random base and split its starts into
  equal arcs, one each, so between them they walk every start once; the
  space counts as covered only when every worker has finished its arcs.
- A worker loads its modules and decodes the paths on its own thread from
  read-only buffers, so starting one costs the game's frame well under a
  millisecond whatever the request.
- When workers cannot start (no `lua51.dll`, too little memory), the walk
  runs on the main thread as in v0.34.0. A worker that fails or is capped
  leaves its arcs unwalked; the search then scans seeds in order.
- Cancelling or finishing a search stops its workers; quitting the game
  waits up to 3 s for them.

## Build

```powershell
$env:BINGUS_LOADER_ROOT = "$PWD\..\..\..\..\BingusSharedLoader"  # in a worktree only
python -B scripts/build.py          # releases/Operation-Reroller-Dev-v0.34.0.zip
python -B tests/test_package.py     # includes tests/test_seed_solver_workers.py
```

## Steps

1. Remove the Worker Thread Probe. Install
   `releases/Operation-Reroller-Dev-v0.34.0.zip` and enable it instead of
   the published Operation Reroller (same module, global and log), with
   Bingus Shared Loader last. Purge / Deploy, launch, and stay alone on the
   ship.
2. **Easy request.** Open the galactic map, press F7, ask for one or two
   missions on a planet, and search. It should match within a second.
3. **Hard request.** Ask for three missions of one operation, each with its
   enemy force, and exclude Lidar Station and SEAF Artillery. On
   2026-10-04 such a request (planet 268, difficulty 6, by day) walked 48.45
   million steps in 27 s on the main thread. Note the time and whether the
   frame rate holds while it runs.
4. **Cancel.** Start another hard request and press F7 again after a few
   seconds.
5. **Quit during a search.** Start a hard request and quit the game from
   the menu while it runs.
6. Send `MissionRerollerExperiment.log` and `BingusSharedLoader.log`.

## Log lines

Success:

```
SEED_SOLVER_WORKERS_READY max_workers=8 processors=16
SEED_SOLVER paths=<n> rows=<r> setup_ms=<ms> match=1/<k> expected_steps=<s>
SEED_SOLVER_WORKERS workers=8 text_kb=<kb> setup_ms=<ms> free_mb=<mb> largest_mb=<mb> processors=16
LUA_SEARCH_PROGRESS ... mode=solver walk_steps=<steps> workers=8 covered=<seeds>
LUA_SEARCH_MATCH seed=<seed> ... mode=solver walk_steps=<steps> workers=8 covered=<seeds> ...
SEED_SOLVER_WORKERS_END workers=8 walk_steps=<steps> failed=0 capped=0 worker_heap_kb=<kb> peak_worker_heap_kb=<kb>
```

- The hard request's `walk_steps` over its `elapsed_s` is the walk rate:
  about 3.5 million steps/s on the main thread on 2026-10-04; eight workers
  walked 31 to 35 million in the probe.
- `free_mb` is the address space below 2 GB at the search's start (about 30
  MB on 2026-10-05).
- Cancelling logs `LUA_SEARCH_CANCELLED ...` and then
  `SEED_SOLVER_WORKERS_END ... failed=0`.
- Quitting during a search logs `LUA_SEARCH_CANCELLED ... reason=Cancelled
  by shortcut or shutdown` and `SEED_SOLVER_WORKERS_END ...`, and no
  `SEED_SOLVER_WORKERS_SHUTDOWN` line.

Failure:

| Line | Meaning |
| --- | --- |
| `SEED_SOLVER_WORKERS_OFF reason=...` | The pool could not be made (for example `lua51.dll not loaded`); every search walks on the main thread. |
| `SEED_SOLVER_WORKERS workers=0 reason=...; walking on the main thread` | This search's workers did not start: too little memory below 2 GB, or a set-up error. The search still runs. |
| `SEED_SOLVER_WORKERS workers=0 reason=estimated 1 in <k>, not rarer than 1 in 100000; walking on the main thread` | Expected, not a failure: a request the estimate puts at 1 in 100,000 or commoner walks on the main thread; the warm workers stay idle. |
| `SEED_SOLVER_WORKERS_END ... failed=<n> error=...` | Workers raised errors; the search walked on with the rest, or ended its solving and scanned seeds in order. |
| `SEED_SOLVER_WORKERS_END ... capped=<n>` | Workers passed the 16 MB heap cap and were stopped. |
| `SEED_SOLVER_WORKERS_SHUTDOWN left_open=<n>` | Workers had not stopped 3 s after quitting began. |
| `SEED_SOLVER_WORKERS_WARMED idle=<n> ... error=...` | Warming stopped on a worker that failed to load its modules; searches make fresh workers as before. |
| `SEED_SOLVER_WORKERS_WARMED idle=<n>` with `<n>` below `max_workers` | Warming stopped because too little address space below 2 GB was left; searches use the idle workers and make the rest as memory allows. |
| No `SEED_SOLVER_WORKERS_COLD` within 10 s of dropping into a mission | Neither the gates nor the 10 s backstop fired: send the log. |
| The frame rate drops during a search | Fewer workers are needed (`max_workers` in `src/seed_solver_workers.lua`). |

## Second build: arcs, seeds covered, no zero count

Changes after the first result:

- **Arcs.** The workers split each job's starts evenly instead of starting
  at independent random points, so no start is walked twice.
- **Seeds covered.** A running search's line reads like
  `0:07 - 348M seeds covered - 1 in 28M match`: the seeds an in-order scan
  would have checked for the same chance of a match (each job's steps at
  its expected candidates per step, over the share of seeds that match).
  Logged as `covered=<seeds>` on the progress and match lines.
- **No zero count.** Pressing Begin Search no longer shows `0 of 1,000,000
  seeds searched` while the search starts: the line keeps the estimate the
  request showed before the search, or reads `Starting search`, until the
  search has its own count or estimate.
- **Set-up off the main thread**, as above.
- **No time until measured.** The estimate under a request no longer
  guesses a time from a fixed rate: it reads like `1 in 28,000,000 seeds
  match` until a solver search in this game has walked at least 200,000
  steps over more than half a second of work, and from then on adds
  `expect about ...` at the rate measured on this machine. The log reads
  `ESTIMATE match=1/<k> seconds=unmeasured` until then.

Check: the line under a running solver search shows seeds covered growing;
the start shows no zero count; before the first long search the request
shows no time, and after it shows one; the hard request still matches;
`LUA_SEARCH_MATCH ... covered=` is about `walk_steps` times the match odds
over the expected steps (as a rough check: the 2026-10-05 search would have
read about 350 million).

## Third build: warm workers on the ship

Run in game 2026-10-05 (see Third build result below). The worker VMs stay warm on the ship and are closed in
a mission (`src/worker_warmth.lua`, `pool.warm` in
`src/seed_solver_workers.lua`):

- **Warm.** The first time the galactic map is on top of the screen
  stack (only possible on the ship), the pool makes up to `max_workers`
  idle VMs, one per frame, each loading its modules on its own thread. An
  idle VM holds no thread. A rare request starts on them, so it skips
  making VMs and loading modules. When it ends they are closed (a VM that
  walked keeps its peak heap until closed) and fresh idle VMs are made.
- **Cold.** At once when a loading or transition gate of the UI root is
  set, or a read of them fails, and also after 10 s without the map on
  top while no search runs. Cold closes the idle VMs; a search that still
  runs loses its workers and scans on. What the gates read at a drop has
  not been recorded, so the 10 s backstop keeps workers out of a mission
  whichever way the gates go. The cold line logs the screen ids and gate
  bytes to find out.
- **Warm again** the next time the map is opened, after any mission or
  return to the ship.
- A `STOPPED:` error cools the pool too, since the mod's frame no longer
  runs. Quitting now joins the workers (the release build did not pass
  the shutdown join to the frame wrapper before).

Steps:

1. Install the build as above, launch, and open the galactic map on the
   ship.
2. Run the hard request twice. The second should start its walk sooner.
3. Close the map, stay on the ship for more than 10 seconds, open it
   again.
4. Drop into a mission, play a minute, return to the ship (finish or
   abandon), open the map and run the hard request once more.
5. Quit the game from the ship with the map closed.

Success:

```
SEED_SOLVER_WORKERS_READY max_workers=8 processors=16
SEED_SOLVER_WORKERS_WARM reason=galactic map open screens=<ids ending in 15> loading_gate=0 transition_gate=0 transition=0000000000000000
SEED_SOLVER_WORKERS_WARMED idle=8 max_workers=8
SEED_SOLVER_WORKERS workers=8 warm=8 text_kb=<kb> setup_ms=<ms> ...
SEED_SOLVER_WORKERS_END workers=8 ... failed=0 capped=0 ...
SEED_SOLVER_WORKERS_COLD reason=galactic map closed for 10 s closed=8 screens=<ids> ...
SEED_SOLVER_WORKERS_COLD reason=loading or transition gate set closed=<n> screens=<ids> loading_gate=<n> transition_gate=<n> transition=<hex>
```

- `warm=8` on the hard request's workers line: all eight were idle VMs.
  `setup_ms` there should be lower than in a cold search.
- After each search a new `SEED_SOLVER_WORKERS_WARMED idle=8` follows, and
  the next search's `free_mb` stays near the first one's (the first build
  of this kept the walked VMs: 29.9, then 8.9 MB and `workers=0`).
- Step 3 logs the 10 s cold line, then a new `WARM` line when the map
  opens again.
- Step 4 should log the gate cold line when the drop's loading screen
  starts (if the gates are set then, and the 10 s line otherwise), and a
  new `WARM` on the map after returning. Report which, with the screen ids.
- Step 5 logs no `SEED_SOLVER_WORKERS_SHUTDOWN` line.

## Result

2026-10-05, the user's machine (16 logical processors), planet 268,
difficulty 10, by day. The request was Launch ICBM, Geological Survey and
Search and Destroy, each with its enemy force (3), Lidar Station and SEAF
Artillery excluded, and one modifier excluded. The log is kept as
`artifacts/solver-workers/MissionRerollerExperiment-2026-10-05.log`.

```
SEED_SOLVER_WORKERS workers=8 text_kb=70 worker_heap_kb=405 setup_ms=5.4 free_mb=31.9 largest_mb=15.9 processors=16
SEED_SOLVER paths=4 rows=2 setup_ms=195 match=1/28177468 expected_steps=50978248 daynight_ids=6/35
LUA_SEARCH_MATCH seed=694937979 row=29 attempts=1 ... max_slice_ms=22.362 elapsed_s=8.33 slices=954 work_ms=305 context_ms=1007 jit=true mode=solver walk_steps=315178725 workers=8 ...
SEED_SOLVER_WORKERS_END workers=8 walk_steps=315592421 failed=0 capped=0 peak_worker_heap_kb=1335
PREDICTION_VERIFIED selected_row=29 active_preserved=true
PUBLICATION_STATE_VERIFIED seed=694937979 row=29 map_ui_row_confirmed=true mission_unselected=true
```

- **One in 28 million seeds, found in 8.3 s.** The walk took 315 million
  steps, 6.2 times the expected 51 million, at about 38 million steps/s
  over the 8.3 s (a 0.75 s backend wait is not counted). On the main thread
  at 3.5 million steps/s of work and about half the wall time, the same walk
  needed about 180 s, the search's time limit.
- **The main thread was nearly idle:** 305 ms of search work and 1,007 ms
  of context checks in 954 slices. The context check is now most of the
  main thread's share. The longest slice was 22 ms, as before the change.
- **Correct:** the first candidate matched, and the published board was
  verified: prediction, Day / Night, constellation and side objectives all
  agree (`PREDICTION_CHECK descriptors_match=true`,
  `CONSTELLATION_CHECK ... agree=true`, `SIDE_OBJECTIVE_CHECK ... agree=true`).
- **Memory:** 31.9 MB free below 2 GB at the start; each worker held 405 KB
  after set-up and at most 1,335 KB. The pool's estimate charged 1,072 KB
  per worker (512 + 8 × 70 KB), a little under the peak, inside the 16 MB
  reserve.
- After the search the dialog estimated the same request at 1.8 s from the
  measured rate (`ESTIMATE match=1/28177468 seconds=1.8`).
- **Not yet exercised:** cancelling a search with F7, and quitting the game
  during a search.

## Third build result

2026-10-05, the user's machine (16 logical processors), one session.
First run of the third build: walked VMs went back to idle, and after one
search free memory below 2 GB fell from 29.9 to 8.9 MB and the next two
searches were refused workers (`memory below 2 GB: 8.9 MB free`); requests
of 1 in 1.75 million and 1 in 906,000 walked on the main thread for 5.5 and
1.6 s under the 1 in 2 million threshold. Fixed by closing walked VMs and
warming fresh ones, and a threshold of 1 in 100,000. Second run:

```
SEED_SOLVER_WORKERS_WARM reason=galactic map open screens=15 loading_gate=0 transition_gate=0 transition=0000000000000000
SEED_SOLVER_WORKERS_WARMED idle=8 max_workers=8
SEED_SOLVER_WORKERS workers=8 warm=8 text_kb=70 setup_ms=4.5 free_mb=29.9 largest_mb=15.9 processors=16
LUA_SEARCH_MATCH ... elapsed_s=0.70 ... walk_steps=10121025 workers=8          (1 in 1.77 million)
SEED_SOLVER_WORKERS_WARMED idle=8 max_workers=8
SEED_SOLVER_WORKERS workers=8 warm=8 text_kb=68 setup_ms=3.5 free_mb=29.9 ...
LUA_SEARCH_MATCH ... elapsed_s=0.48 ... walk_steps=3434335 workers=8           (1 in 662,000)
SEED_SOLVER_WORKERS workers=8 warm=8 text_kb=16 setup_ms=1.4 free_mb=29.9 ...
LUA_SEARCH_MATCH ... elapsed_s=13.31 ... walk_steps=1081698859 workers=8       (1 in 4.34 billion)
SEED_SOLVER_WORKERS_COLD reason=galactic map closed for 10 s closed=8 screens=14 loading_gate=0 transition_gate=0 transition=0000000000000000
SEED_SOLVER_WORKERS_WARM reason=galactic map open screens=15 ...                (back from a mission)
SEED_SOLVER_WORKERS workers=8 warm=8 text_kb=16 setup_ms=1.5 free_mb=29.9 ...
LUA_SEARCH_MATCH ... elapsed_s=9.39 ... walk_steps=766142945 workers=8         (1 in 2.9 billion)
```

- **Memory holds:** `free_mb=29.9` at every search; every search ended
  `failed=0 capped=0` with peak worker heaps of 1.0 to 1.3 MB.
- **Mission:** the cold line came 10 s after the map was closed to start a
  mission, still on the ship (`screens=14` is the ship with the map
  closed); the map warmed the pool again after the mission. Quitting
  logged no `SEED_SOLVER_WORKERS_SHUTDOWN`.
- **The main thread:** in the 13.3 s search it spent 276 ms on search work
  and 1,678 ms on context checks; the longest slice was 22.5 ms.
- **Not yet exercised:** a loading or transition gate cooling the pool
  (walking to the hellpod takes longer than 10 s), and a fast transition
  from the map such as joining an SOS.
