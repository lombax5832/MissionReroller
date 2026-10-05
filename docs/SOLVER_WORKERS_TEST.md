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
- When workers cannot start (no `lua51.dll`, too little memory, a set-up
  error), the walk runs on the main thread as in v0.34.0.
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
SEED_SOLVER_WORKERS workers=8 text_kb=<kb> worker_heap_kb=<kb> setup_ms=<ms> free_mb=<mb> largest_mb=<mb> processors=16
LUA_SEARCH_PROGRESS ... mode=solver walk_steps=<steps> workers=8
LUA_SEARCH_MATCH seed=<seed> ... mode=solver walk_steps=<steps> workers=8 ...
SEED_SOLVER_WORKERS_END workers=8 walk_steps=<steps> failed=0 capped=0 peak_worker_heap_kb=<kb>
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
| `SEED_SOLVER_WORKERS_END ... failed=<n> error=...` | Workers raised errors; the search walked on with the rest, or ended its solving and scanned seeds in order. |
| `SEED_SOLVER_WORKERS_END ... capped=<n>` | Workers passed the 16 MB heap cap and were stopped. |
| `SEED_SOLVER_WORKERS_SHUTDOWN left_open=<n>` | Workers had not stopped 3 s after quitting began. |
| The frame rate drops during a search | Fewer workers are needed (`max_workers` in `src/seed_solver_workers.lua`). |

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
