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

Each worker is set up in about 6 ms (20 ms with 230 KB of paths).

### Heap: the binding constraint

Every worker heap lives below 2 GB, the same scarce range as the game's
own VM:

- LuaJIT x64 non-GC64 reserves every heap segment below 2 GB
  (`lj_alloc.c`: `LJ_ALLOC_MBITS 31`, zero bits on
  `NtAllocateVirtualMemory`), takes segments of at least 128 KB, and gives
  memory back only when more than 2 MB at the top is free.
- No way round it: the game's `lua51.dll` returns NULL from `lua_newstate`
  with a custom allocator; `luaL_newstate` put a worker at `0x0d4d0378`.
  `ffi.new` memory is in the same heap.
- In game on 2026-10-05 ([WORKER_PROBE_TEST.md](WORKER_PROBE_TEST.md)),
  only 31.9 MB was free below 2 GB, the largest block 15.9 MB, with
  2,016 MB in use. The loader had seen about 48 MB earlier
  (`../BingusSharedLoader/docs/TECHNICAL.md`). The loader's
  24 MB heap guard reads only the main VM's `collectgarbage('count')`, so it
  does not see worker heaps.
- A worker that runs out of memory raises an error inside its own
  `pcall`. The danger is the game's VM failing an allocation because
  workers took the range, which would likely crash the game.

Measured in the test process with `worker_threads.lua`, which reports each
worker's peak `collectgarbage('count')` and the address space used below
2 GB (`VirtualQuery`) before set-up, after set-up, after the walk and after
`lua_close`:

| Request (path text per worker) | Workers | Worker heap after set-up / peak | Added below 2 GB, set-up / walk |
| --- | --- | --- | --- |
| tags (small) | 4 | 198 KB / 717 KB | 1.0 / 4.5 MB |
| tags (small) | 12 | 197 KB / 539 KB | 3.0 / 9.5 MB |
| both, with exclusions (230 KB) | 4 | 2,267 KB / 4,936 KB | 14.3 / 24.4 MB |
| both, with exclusions (230 KB) | 12 | 2,267 KB / 4,965 KB | 41.5 / 68.9 MB |
| the same, full collect after set-up, GC pause 110 | 4 | 918 KB / 2,298 KB | 10.3 / 15.8 MB |
| the same, full collect after set-up, GC pause 110 | 12 | 917 KB / 2,341 KB | 28.9 / 45.5 MB |

`lua_close` returned all of it every time. Requests with excluded side
objectives carry about 80 alternatives per mission, and each worker parsing
its own copy of the paths is what fills the heap: 12 such workers would take
more than the 48 MB free. The GC settings cost nothing at 4 workers
(15.8 M/s) and about a tenth at 12.

The design for the mod therefore:

1. **One shared copy of the data.** The main VM compiles the decision
   trees and constraints once into flat FFI arrays, allocated outside the
   Lua heap where they are large (`ffi.new` memory sits below 2 GB too).
   Workers read them
   through a pointer and never build Lua tables from them, so a worker's
   heap is its module code (about 200 KB) plus garbage. Flat arrays also
   suit the JIT better than tables. Not yet measured.
2. **Collect after set-up and tune the GC.** `lua_gc(L, LUA_GCCOLLECT)`
   once the chunk has run, then a GC pause near 110.
3. **Few workers.** 2 to 4, each 1 to 4 MB below 2 GB.
4. **A budget check.** Before starting workers, the main VM scans the
   range below 2 GB with `VirtualQuery` (read-only), and starts them only
   while plenty stays free (for example 32 MB, largest block 8 MB). Workers
   write their `collectgarbage('count')` to the shared buffer each budget;
   the main VM stops them above a cap. The main VM must not call `lua_gc`
   on a worker VM while its thread runs.
5. **Close promptly.** Close each worker VM when its search ends rather
   than keeping it idle, since only `lua_close` returns its segments.

Machine code is separate: each worker's JIT keeps its own code area (512 KB
at most by default) within jump range of `lua51.dll`, where the loader
found 1.86 GB free. Each trace also keeps about 1 KB of records in the
worker's heap, which the figures above include.

### Open questions, only answerable in game

The Worker Thread Probe answered three of these on 2026-10-05: GameGuard
showed no reaction to pool threads in Lua code, the join at shutdown was
clean, and 31.9 MB was free below 2 GB. Workers walked at 6.1 to 7.0
million steps/s each in game (4 workers: 19.3 million). The frame rate is
still open.

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
- **Memory.** How much is free below 2 GB on players' machines, at the
  galactic map, with other mods loaded. The probe should log the
  `VirtualQuery` scan before, during and after its worker runs.
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
2. Done 2026-10-05, clean: the in-game probe: `scripts/native_solver/worker_probe.lua`, built by
   `build_worker_probe.py` as the separate Worker Thread Probe addon and
   checked by `tests/test_worker_probe.py` (in the workspace LuaJIT and in
   the game's `lua51.dll`). It runs three scheduled runs of thread-pool
   worker VMs (1, 4, then 1 until shutdown) with the memory scan, and joins
   them at shutdown. Test plan: [WORKER_PROBE_TEST.md](WORKER_PROBE_TEST.md).
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
python -B scripts/native_solver/worker_threads.py $cap both 1000000 4,12 pool 110   # collect after set-up, GC pause 110
```
