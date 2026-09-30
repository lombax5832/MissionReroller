# Mission Reroller

The workspace `../AGENTS.md` covers the loader contract, memory-access rules,
tools and in-game testing. This file adds what is specific to this mod.

The mod ports the game's operation generator to Lua, searches campaign seeds
in-game until the predicted board matches the player's filters, then writes
the seed, verifies the regenerated board and selects the matching operation.

## Pinned build

This mod targets Steam build **25480438**, not the workspace default. The
hashes are asserted in `src/experiment_adapter.lua` (search `hash mismatch`).
Offline research uses `../dumps/build-25480438/` and the `HD2-25480438`
Ghidra project; every RVA in `docs/` refers to that dump.

## Names that must not change

The release ships as `mods/ipodalexei/mission_reroller_experiment` with the
`MODULE` and `GUID` from `scripts/build_combined.py`, global
`MissionRerollerExperiment`, log `MissionRerollerExperiment.log`. Every
release since v0.4.0 uses them, so mod managers treat a new ZIP as an update.

## How the entry is assembled

No single file in `src/` is the shipped entry. `scripts/build.py` calls
`build_identity_probe.source(search, publish, dialog, version)`, which
concatenates `src/` into one plaintext chunk:

- `src/mods/ipodalexei/mission_reroller.lua` is the inert core, embedded with
  `MissionReroller` renamed to `MissionRerollerExperimentCore`. The other
  entries in that folder are research builds.
- Each library module is wrapped as `local name=(function() <file> end)()`,
  so a module file ends in `return <value>`. A new module needs a line in the
  list in `source()`.
- The `*_runtime.lua` files and `experiment_adapter.lua` are appended raw and
  share the chunk's locals.
- `source()` rewrites text in them: `read_only=false` must occur exactly once
  in `experiment_adapter.lua`, and version banners such as
  `0.8.0 independent seed prediction` and `Ctrl+Shift+F9` in
  `identity_probe_runtime.lua` are replaced in a chain. Editing one of those
  strings silently breaks the later replacements; check the built entry.

The research builders in `scripts/README.md` assemble the same modules, so a
change to a shared module can break their tests too.

## Build and test

```powershell
$env:BINGUS_LOADER_ROOT = "$PWD\..\..\..\..\BingusSharedLoader"  # in a worktree only
python -B scripts/build.py          # releases/Mission-Reroller-v<VERSION>.zip
python -B tests/test_package.py     # package checks, then tests/test_dialog.py
```

- `test_package.py` is the release gate. For other modules, find the driving
  test with `grep <module>.lua tests/*.py` and run that Python file; each Lua
  test's first lines give its arguments (usually the `src` folder, a module
  path, or a built entry).
- In a worktree, `ROOT.parent` is `.claude/worktrees`: the build needs
  `BINGUS_LOADER_ROOT`, and `test_constellation_prediction.lua` skips its
  KnowYourConstellation recorded-seed check without saying so. Run the gate
  once from the main checkout before a release.
- `test_identity_probe.py`, `test_live_search.py` and `test_search_probe.py`
  replay live captures from the gitignored `artifacts/` folder, which exists
  only in the main checkout.
- The forbidden-API list in `test_package.py` is the contract for what the
  release may call; extend it rather than work around it.

## In-game constraints learned the hard way

- **Shared FFI namespace.** All addons share one LuaJIT VM and the first
  `ffi.cdef` of a name wins. Call Win32 functions another addon may declare
  through `src/window_cursor.lua`'s pattern (resolve by address, unnamed
  function pointers, `void *` parameters). `tests/test_ffi_conflicts.lua`
  reproduces the clash.
- **Frame budget.** Long work runs as coroutines that yield after a 16 ms
  slice (see the seed search and `identity_probe_runtime.lua`). A synchronous
  capture of about 50 ms caused visible hitches before v0.23.
- **Keyboard input reaches every addon and the game.** Pick shortcuts that
  other mods do not use by default (F8 clashed with Fast Enter Hellpod), and
  act only when the galactic map is top of the screen stack.
- **Stop cleanly.** On anything unexpected, log `STOPPED: <reason>`, release
  the mouse gate and write nothing further; the README's troubleshooting
  table depends on these log lines.

## Live memory research

Use the Memory Explorer addon (`../MemoryExplorer`, read-only bridge) and the
`scripts/check_live_*.py` tools while the user runs the game. Only one bridge
client may connect; when the lock is held, stop rather than remove it. Save
captures under `artifacts/`; session addresses stay out of the repository.

## Release workflow

1. Work on a branch in a worktree; merge into `main` as
   `Merge the <change> into main`.
2. Release commit `Release <ver>: <what changed>`: bump `VERSION` in
   `scripts/build.py`, update the version string in `README.md`, add a
   `docs/HISTORY.md` entry at the top marked **Not yet validated in game**.
3. After the user's in-game test, commit `Record the v<ver> in-game result`,
   changing the entry to **Validated in game** with the date and the log lines
   that prove it. Only the user's logs count as validation.

`docs/HISTORY.md` is the record of why things are the way they are, newest
first; read it before reworking a subsystem. Feature-specific test plans and
findings are the other files in `docs/`, linked from their history entries.
