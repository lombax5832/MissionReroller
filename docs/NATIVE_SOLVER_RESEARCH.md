# Faster seed solving: native code and worker threads

Research, offline only, 2026-10-05: `scripts/native_solver/`. Nothing here
ran in or touched the game. The game's `lua51.dll` was loaded into a test
process only, the way `../BingusSharedLoader/tests/test_jit_budget_game.py`
does.

## Question

Can C code run as part of the mod, and how much would it speed up the seed
solver ([SEED_SOLVER_RESEARCH.md](SEED_SOLVER_RESEARCH.md))? Is there a
route to the same gains that stays inside the mod's rules?

## Where a search spends its time now

The v0.34.0 log (2026-10-04, `MissionRerollerExperiment.log`) has the JIT on
(`jit=true`) and a hard request walking 48.45 million steps in 13.7 s of
work: 3.5 million steps/s, the offline JIT rate. The search took 27 s, so
half the wall time was the frame share: the search runs 16 ms a frame on
the main thread.

LuaJIT's sampler on `scripts/profile_seed_solver.lua` (planet 173 capture,
tags request) put 61% of the walk in `invert_m`, the lattice inversion in
`src/seed_solver_math.lua`. Its inner loop built a boxed `int64_t` cdata for
every cell (`ffi.new('int64_t', j) * vs`).

## Measurements

All runs: the 12 (path, row) jobs of the planet 173 requests of
`profile_seed_solver.lua` (both, objectives, tags), 1 million walk steps
each from the same random starts. Every row agrees with the LuaJIT
candidates job by job (240, 4,528 and 12,729 candidates). 16 logical
cores.

| Run | both | objectives | tags |
| --- | --- | --- | --- |
| Workspace LuaJIT, v0.34.0 inverter | 2.94 M/s | 2.60 M/s | 1.30 M/s |
| Workspace LuaJIT, double inverter (below) | 3.92 M/s | 3.40 M/s | 2.93 M/s |
| C, 1 thread (`solver_bench.c`, MSVC `/O2`) | 24.1 M/s | 23.2 M/s | 15.1 M/s |
| C, 8 threads | 158 M/s | 136 M/s | 119 M/s |
| C, 16 threads | 231 M/s | 205 M/s | 145 M/s |
| Game `lua51.dll`, main VM | 4.00 M/s | | 1.79 M/s |
| Game `lua51.dll`, 4 worker VMs | 16.0 M/s | | 11.0 M/s |
| Game `lua51.dll`, 12 worker VMs | 34.6 M/s | | 25.6 M/s |
| Game `lua51.dll`, 12 worker VMs, thread pool | 31.6 M/s | | |

C runs 5 to 7 times faster than LuaJIT per core after the inverter fix (9
to 15 times before it). Worker VMs scale close to linearly with cores, and
12 of them beat one C thread.

## The double inverter

Answers lie in a 2^32 by 2^32 square; every cell's s is the corner cell's
plus small multiples of the reduced basis vectors (near 2^32 in size). The
corner lies near the square, so its wrapping int64 value is its true value,
and from there every cell is exact in doubles. Only a cell with
0 <= s < 2^32 is confirmed in uint64. Using `i*us` directly in doubles does
not work: i is near 2^32, so the product is near 2^64 and rounds. The first
attempt did exactly that and found no candidates; the C bench caught it.

`tests/test_seed_solver_lua.py` passes with the change (72 and 25 seeds
confirmed by the predictor).

## Ways native code could run in the game

| Route | What it takes | Verdict |
| --- | --- | --- |
| A DLL (`ffi.load` / `LoadLibrary`) | A DLL on disk: mod managers deploy archive resources, so the mod would have to write it itself (`io.open` is banned). GameGuard guards module loads into the game. | No. `LoadLibrary` and `io.open` are banned by `tests/test_package.py`. |
| Machine code in memory we make executable | `VirtualAlloc` / `VirtualProtect`, then `ffi.cast` to a function pointer. Private executable memory written by a script is what manually mapped cheats look like. | No. Both APIs are banned by `tests/test_package.py`, and the workspace rule is never to write code pages. The ban risk falls on players. |
| The game's own native code | `ffi.cast` of a `game.dll` function. | Not useful: the game has no solver, only the generator, which predicts one board at a time. |
| LuaJIT's JIT in more VMs (worker VMs) | `luaL_newstate` etc. from `lua51.dll`, plus a thread. Machine code comes only from `lua51.dll`'s own JIT, as it does all the time already. | Recommended; measured above. |

Native C would add a further 5 to 7 times per core over worker VMs, but no
route to it fits the mod's rules or is safe for players.

## Worker VMs

The game's `bin/lua51.dll` is stock LuaJIT 2.1.0-alpha, non-GC64
(`../BingusSharedLoader/docs/TECHNICAL.md`). It is not packed and exports
the whole Lua C API (138 exports, among them `luaL_newstate`,
`luaL_openlibs`, `luaL_loadbuffer`, `lua_pcall`, `lua_close`, `lua_gc`,
`luaJIT_setmode`). `game.dll` and `helldivers2.exe` export no Lua functions.
On Windows `ffi.C` resolves names in the DLL LuaJIT runs from, so the mod's
VM can call these with no `LoadLibrary`.

`scripts/native_solver/worker_threads.lua`, run inside the game's
`lua51.dll` by `worker_threads.py`:

1. The mod's VM builds the paths as the search does and turns them into Lua
   constructor text.
2. Per worker: `luaL_newstate`, `luaL_openlibs`, and one chunk with the
   sources of `seed_solver_math.lua` and `seed_solver_chain.lua`, the path
   text, the worker's jobs and the address of a shared FFI result buffer.
   The chunk creates an FFI callback in the worker VM, keeps it in a
   global, and returns its address.
3. The mod's VM starts an OS thread on it: `CreateThread`, or
   `TrySubmitThreadpoolCallback` so the thread starts in `ntdll` and only
   calls the callback. Each worker VM is used by its thread alone, which
   LuaJIT supports; nothing is shared with the game's VM but FFI memory.
4. The worker writes its results to the buffer and raises a done flag; the
   mod's VM polls the flags (once a frame in game) and closes the VM after
   the thread ends.

Each worker is set up in about 6 ms. Its Lua heap is about 200 KB after
set-up and stays under 4.3 MB while walking, garbage included. That matters:
a non-GC64 heap must live below 2 GB, where about 48 MB was free in game.

### Open questions, only answerable in game

- **GameGuard.** Starting threads in the game process is new for this
  workspace. Execution in LuaJIT machine code is not: every compiled trace
  on the main thread runs there. The thread pool keeps each thread's start
  address in `ntdll`. Whether GameGuard reacts to either is unknown until a
  supervised probe runs.
- **Frame rate.** The walk should get fewer workers than cores (2 to 4) at
  below-normal priority, and run only while the galactic map is open, where
  the game is light.
- **Life cycle.** Searches end, are cancelled, and the game shuts down
  while workers run. Workers must check a stop flag in the shared buffer
  between budgets, and `shutdown` must wait for them before `lua_close`. A
  worker VM must never be closed or collected while its thread runs.
- **Memory.** Set each worker's GC pause lower, and cap the workers' total
  heap, so the game's own below-2-GB heap is never starved.
- **Shared VM etiquette.** Declare `CreateThread`,
  `TrySubmitThreadpoolCallback` and the `lua_*` functions the way
  `src/window_cursor.lua` does, since the first `ffi.cdef` of a name wins.

## Expected effect

On the logged hard request (48.45 million steps, 27 s), assuming 4 to
4.5 million steps/s per worker in game: 4 workers would take about 3 s,
8 workers about 1.5 s. The frame share no longer limits the walk, and the
main thread keeps only set-up, candidate boards and publication.

## Next steps

1. Ship the double inverter (on this branch): 1.3 to 2.3 times the walk
   with no other change.
2. An in-game probe, as a research build: one thread-pool worker VM that
   counts for ten seconds, logs from the main VM, and is stopped and closed
   on `shutdown`. Its test plan names the log lines; the user runs it and
   watches for any GameGuard reaction.
3. If the probe is clean, move the chain's walk into worker VMs:
   candidates go back to the main VM to be predicted and confirmed as now.
4. Keep native C out of the mod. `solver_bench.c` stays as the bound for
   what a core can do.

## Reproduce

```powershell
$cap = '..\artifacts\planet-live\capture.lua'   # main checkout
& $env:HD2_LUAJIT scripts/native_solver/dump_jobs.lua $cap both 1000000 $env:TEMP\jobs-both.txt
cl /O2 /nologo scripts\native_solver\solver_bench.c   # in a VS x64 prompt
.\solver_bench.exe $env:TEMP\jobs-both.txt 16 4
python -B scripts/native_solver/worker_threads.py $cap both 1000000 1,2,4,12 thread
python -B scripts/native_solver/worker_threads.py $cap both 1000000 1,4,12 pool
```
