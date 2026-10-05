# Worker Thread Probe test

In-game check for [NATIVE_SOLVER_RESEARCH.md](NATIVE_SOLVER_RESEARCH.md),
next step 2. **Run in game 2026-10-05: workers ran and joined cleanly; frame
rate not yet reported.**

## What it answers

1. Can an addon run LuaJIT worker VMs on Windows thread-pool threads in the
   game without GameGuard or the game reacting?
2. How fast is a worker in game, and does the frame rate suffer?
3. How much address space below 2 GB is free in game, and how much do
   workers take? Non-GC64 LuaJIT keeps every heap there, the game's
   included.
4. Do workers stop, join and release their memory cleanly, including at
   shutdown?

## What it does

The Worker Thread Probe is a separate research addon (module
`mods/ipodalexei/worker_thread_probe`, its own GUID, log
`WorkerThreadProbe.log`). It is not part of Mission Reroller, and both can
be installed together. It reads no input and changes nothing in the game.
It reads memory only through `VirtualQuery` and writes no game memory.

Each worker is a fresh LuaJIT VM from the game's own `lua51.dll`, running
on a thread-pool thread at below-normal priority. It runs the seed solver's
walk and inversion from `src/seed_solver_math.lua`, and checks that every
inversion gives back its start. Times count from the first frame:

| Run | Starts | Workers | Length |
| --- | --- | --- | --- |
| 1 | 60 s | 1 | 10 s |
| 2 | 20 s after run 1 closes (about 90 s) | 4 | 10 s |
| 3 | 20 s after run 2 closes (about 2 min) | 1 | until you quit, at most 15 min |

The range below 2 GB is scanned at start-up, before each run, after
set-up, every 2 s while walking, after the walk, and after the worker VMs
close.

## Build

```powershell
$env:BINGUS_LOADER_ROOT = "$PWD\..\..\..\..\BingusSharedLoader"  # in a worktree only
python -B scripts/native_solver/build_worker_probe.py   # releases/Worker-Thread-Probe-v0.1.0.zip
python -B tests/test_worker_probe.py                    # runs it in the workspace LuaJIT and the game's lua51.dll
```

## Steps

1. Import `releases/Worker-Thread-Probe-v0.1.0.zip` into Arsenal or HD2MM
   beside your usual mods, so the memory figures are realistic. Keep Bingus
   Shared Loader last. Purge / Deploy.
2. Launch and go to your ship as usual. Stay alone on the ship, not in a
   lobby or a mission.
3. Wait on the ship until about 2.5 minutes after the title screen. Runs 1
   and 2 happen during this time.
4. While run 3 walks, open the galactic map, move around, and note
   whether the frame rate changes.
5. Quit to the desktop from the game's menu while run 3 is still walking
   (within 15 minutes). This tests the shutdown join.
6. Send back `WorkerThreadProbe.log` and `BingusSharedLoader.log` from
   `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs`, and anything GameGuard
   or the game showed.
7. Remove the probe from the load order and Purge / Deploy.

## Log lines

Success looks like:

```
BingusSharedLoader.log: mods/ipodalexei/worker_thread_probe: loaded
WORKER_PROBE version=0.1.0 jit=true LuaJIT 2.1.0-alpha loader=v18 lua51=0x... processors=<n>
PROBE_MEMORY run=0 phase=startup used_mb=... free_mb=<F> largest_free_mb=<L> regions=<r> scan_ms=<ms> main_heap_kb=...
PROBE_START run=1 workers=1 seconds=10 setup_ms=<ms> worker_heap_kb=<kb>
PROBE_PROGRESS run=1 elapsed_s=... steps=... steps_per_second=<rate> heap_kb=... peak_kb=...
PROBE_DONE run=1 workers=1 steps=... steps_per_second=<rate> peak_worker_heap_kb=<kb> added_mb=<a> held_after_close_mb=<h> pool_priority=0 failed=0
PROBE_DONE run=2 workers=4 ... failed=0
PROBE_START run=3 workers=1 seconds=900 ...
PROBE_DONE run=3 ... failed=0
PROBE_SHUTDOWN joined=1 run=3 waited_ms=<ms>
```

What each figure tells us:

- `free_mb` and `largest_free_mb` at start-up: the budget below 2 GB on
  this machine with these mods, against the loader's earlier 48 MB.
- `added_mb` per run, against the 1 to 4 MB per worker measured offline;
  `held_after_close_mb` should be near 0.
- `steps_per_second`: about 5 million per worker offline; run 2 should be
  close to four times run 1.
- `scan_ms`: what a memory check before each search would cost in game.
- `waited_ms` at shutdown: how long quitting waits for a worker (offline,
  about 1 ms).

Failure looks like:

| Sign | Meaning |
| --- | --- |
| The game closes, or GameGuard shows a message, right after `PROBE_START` | GameGuard or the game rejects pool threads in Lua code. Stop: worker VMs are not viable. Note the last log line. |
| `STOPPED: <reason>` | The probe failed safely and started nothing more. The reason says where (a missing export, `luaL_newstate failed`, a set-up error). |
| `failed=1 error=...` | A worker raised an error; `error=` holds its message. |
| `PROBE_SUBMIT_FAILED` | The thread pool refused the work item. |
| `PROBE_SHUTDOWN joined=0` | The worker did not stop within 3 s at shutdown; its VM was left open for the process exit to discard. |
| `PROBE_ABANDONED` | A second failure after `STOPPED`; worker VMs were left alone. |
| No `PROBE_SHUTDOWN` line after run 3 started | The game did not call `shutdown`, or ended first. |
| Frame rate drops in run 2 or 3 | Fewer workers or a lower priority are needed. |

## v0.2.0: eight workers

Same addon and GUID; replace v0.1.0 with
`releases/Worker-Thread-Probe-v0.2.0.zip`. Runs: one worker for 10 s at
60 s (baseline), eight for 30 s, then eight until you quit (at most 15
min). The probe now logs the game's frame times: `frames`,
`frame_avg_ms` and `frame_max_ms` on every `PROBE_PROGRESS` line (the
second before it), and `PROBE_FRAMES idle=1 ...` every 5 s while no worker
runs, as a baseline. The steps are the same as above: stay on the ship,
and during the long run open the galactic map and move around before
quitting from the menu.

What to compare: `frame_avg_ms` and `frame_max_ms` with eight workers
against the idle lines and the one-worker run; `steps_per_second` with
eight against one; `added_mb` (about 2.5 MB expected for eight); and
`waited_ms` at shutdown with eight workers.

## Result

2026-10-05, v0.1.0, on the user's machine with their usual mods (16 logical
processors, Bingus Shared Loader v17). The game was on the ship. After run
3 had walked 56 s, a normal window close quit the game. The log is kept as
`artifacts/worker-probe/WorkerThreadProbe-2026-10-05.log` (main checkout).

- **No reaction.** `mods/ipodalexei/worker_thread_probe: loaded`. GameGuard
  showed nothing, the game kept running through all three runs, and it
  quit normally. No `STOPPED` line, and nothing new in
  `BingusSharedLoader.log`.
- **Speed.** Run 1: one worker, 61.3 million steps in 10.00 s,
  `steps_per_second=6126320`. Run 2: four workers,
  `steps_per_second=19269228`, 3.1 times run 1. Run 3: 6.98 million
  steps/s over 56 s. That beats the 5.0 million offline, probably because
  the game's cores were idle on the ship.
- **Correctness.** `failed=0` in every run: every one of 648 million
  inversions gave its start back.
- **Memory below 2 GB.** At start-up: `used_mb=2016.0 free_mb=31.9
  largest_free_mb=15.9 regions=18`. That is less than the loader's earlier
  48 MB, and the largest block is half of it. Workers took
  `added_mb=0.3` (one) and `1.0` (four), with a peak worker heap of 121 to
  126 KB, and released everything (`held_after_close_mb=0.0`). The main
  VM's heap was about 3.6 MB after start-up (27 MB at the first frame,
  before the game's own collection).
- **Scan cost.** `scan_ms` 0.16 to 0.91 over 18 to 26 regions: cheap
  enough to check before every search.
- **Shutdown.** `PROBE_SHUTDOWN joined=1 run=3 waited_ms=0`, after
  `PROBE_DONE run=3 ... failed=0`.
- **Not yet known:** the frame rate during runs 2 and 3, which needs the
  user's observation.
- **Minor:** `lua51=?`. The handle came back in a form whose `tostring`
  has no `0x`, probably because another addon declared `GetModuleHandleA`
  first with an integer return. The lookups worked regardless.
