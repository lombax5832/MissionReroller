# Mission Reroller

A Helldivers 2 Lua addon started by Bingus Shared Loader. It ports the game's
operation generator to Lua, searches campaign seeds in-game until the
predicted war-table board matches the player's mission, modifier and enemy
force filters, then writes the seed, verifies the regenerated board and
selects the matching operation. `README.md` is the player-facing description.

This repo sits in the HD2 modding workspace (`..`). Shared tooling is in
`../tools/`; `../dumps/` and `../extracted/` and this repo's `artifacts/` hold
material derived from the game: keep them out of git and out of every release.

Supported game: Steam build **25480438**. The pinned hashes are asserted in
`src/experiment_adapter.lua` (search `hash mismatch`):

- `game.dll`: `2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E`
- `helldivers2.exe`: `F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06`

The install path is `$env:HD2_GAME_ROOT`; LuaJIT is `$env:HD2_LUAJIT`.

## How the mod works

The loader owns the game's Wwise startup script. At startup it scans deployed
patch archives for Lua resources whose first line is
`-- HD2-Addon: mods/<author>/<entry>` and `require`s each one. Full contract:
`../BingusSharedLoader/docs/AUTHORING.md`.

The release entry runs in the game's LuaJIT VM with FFI:

- **Guard first.** `if rawget(_G,'MissionRerollerExperiment') then return end`.
- **Check the loader.** `CowboyBingusModLoader.api >= 1` and `.version >= 16`.
- **Wrap, never replace.** Save the global `update` / `shutdown`, install
  wrappers that call the originals and return every value they return.
- **Log through the loader** to `MissionRerollerExperiment.log` via
  `CowboyBingusModLoader.open_log`, which returns a file in
  `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs` or nil; wrap every write in
  `pcall`. The first frame logs the version and every loaded Lua mod.
- **Memory access is in-process only**, through `ReadProcessMemory` /
  `WriteProcessMemory` on the game's own process via FFI. Writes go only to
  existing private read/write pages (check with `VirtualQuery`), never to code.
  GameGuard is active: never attach an external debugger or tool to the game.
  `tests/test_package.py` lists the APIs the release must never contain.
- **Guard build-specific offsets** with the module hashes above and byte
  signatures (`src/window_signatures.lua`, `src/selection_signatures.lua`).
  On anything unexpected, log `STOPPED: <reason>`, release the mouse gate and
  write nothing further; the README troubleshooting table relies on it.
- **Share the VM politely.** All addons share one LuaJIT VM and the first
  `ffi.cdef` of a name wins. Call Win32 functions another addon may declare
  the way `src/window_cursor.lua` does (resolve by address, unnamed function
  pointers, `void *` parameters); `tests/test_ffi_conflicts.lua` reproduces
  the clash.
- **Stay inside the frame budget.** Long work runs as coroutines that yield
  after a 16 ms slice (the seed search, `src/identity_probe_runtime.lua`).
- **Keyboard input reaches every addon and the game.** The default shortcut
  is F7 because Fast Enter Hellpod uses F8, and it acts only with the galactic
  map on top of the screen stack. Mod Bindings Menu, when installed, rebinds
  it on the MODS tab (`src/mod_binding.lua`).

## Names that must not change

Every release since v0.4.0 ships as module
`mods/ipodalexei/mission_reroller_experiment` with the `MODULE` and `GUID` in
`scripts/build_combined.py`, global `MissionRerollerExperiment` and log
`MissionRerollerExperiment.log`. Mod managers match on the GUID, so a new ZIP
replaces the old one.

## Project layout

```
src/                         library modules and runtimes, joined at build time
src/mods/ipodalexei/         mission_reroller.lua is the inert core; the rest are research entries
scripts/build.py             release: NAME, VERSION, SUMMARY; MODULE/GUID from build_combined
scripts/build_*.py           research builds, listed in scripts/README.md
scripts/check_live_*.py      live-memory checks through Memory Explorer
tests/                       Python drivers and LuaJIT tests
docs/HISTORY.md              development log, newest first
docs/*_TEST.md, *RESEARCH.md one file per in-game test or research topic
artifacts/                   gitignored captures and oracles, main checkout only
releases/                    gitignored built ZIPs
```

### How the entry is assembled

No single file in `src/` is the shipped entry. `scripts/build.py` calls
`build_identity_probe.source(search, publish, dialog, version)`, which joins
`src/` into one plaintext chunk:

- `src/mods/ipodalexei/mission_reroller.lua` is embedded with
  `MissionReroller` renamed to `MissionRerollerExperimentCore`.
- Each library module is wrapped as `local name=(function() <file> end)()`,
  so a module file ends in `return <value>`. A new module needs a line in the
  list in `source()`; `source()` also collects them into a `lib` table.
- The build's mode is data: `config()` in `build_identity_probe.py` gives
  `read_only`, `preview_prediction`, `version`, the startup `banner`, the
  `shortcut` name and a few log phrases. The chunk declares it as
  `local config={...}`. No source text is rewritten.
- `experiment_adapter.lua` runs as `local host=(function(core,config) <file>
  end)(core,config)` and ends in `return {M=M,config=config,emit=...}`: the
  runtimes' host. It returns nothing when another copy runs or the loader is
  too old, and the chunk then stops (`if not host then return end`).
- Each `*_runtime.lua` runs as `(function(host,lib,hooks) <file>
  end)(host,lib,{...})`. A runtime file starts by copying what it uses out of
  `host`, `lib` and `hooks` into locals of the same names, and ends in
  `return {<its entry points>}`. `source()` passes those tables on as the
  next runtime's `hooks`; a runtime left out of a build leaves its hooks nil.
  The one back edge, `validate_search_request` from the dialog to the search,
  is added to `search_hooks` after the dialog is created.
- The native handles (`api`, `game`, `ffi`, `kernel`, `user32`) exist only
  after `initialize()` on the first frame. A runtime registers
  `host.when_initialized(function(n) ... end)` to receive them.
- The runtimes are created in the order of their startup log lines:
  publication, constellations, search, dialog, identity probe (which wraps
  `update` / `shutdown`).
- `tests/test_runtime_host.py` (run by `test_package.py`) checks every build
  carries these files unchanged, and `tests/test_runtime_factories.lua`
  creates each one with a fake host that allows no other globals. Lua tests
  reach into an assembled entry with `tests/harness.lua`: `H.up` for a
  closure variable, `H.natives(update,{...})` to hand every runtime fake
  native handles as `initialize()` would.
- Status changes go through `src/reroll_session.lua`, created on the host as
  `host.reroll_session` right after the adapter. Runtimes call `advance` /
  `finish` / `settle` / `fail`; the dialog calls `start` / `cancel` / `view`.
  Nothing else writes `M.status`. A new status needs a row in its phase
  table; an unlisted one raises in tests and logs `SESSION_REJECTED` in game.

`build_combined.py`, `build_experiment.py` and `build_seed_test.py` are older
research builds: they append the adapter inline through
`build_core.inline_adapter()`, which drops its host return so their runtimes
share its locals. The research builders reuse these modules, so a change to a
shared module can break their tests too.

## Build and test

```powershell
$env:BINGUS_LOADER_ROOT = "$PWD\..\..\..\..\BingusSharedLoader"  # in a worktree only
python -B scripts/build.py          # releases/Mission-Reroller-v<VERSION>.zip
python -B tests/test_package.py     # package checks, then tests/test_dialog.py
```

- `test_package.py` is the release gate. For other modules, find the driving
  test with `grep <module>.lua tests/*.py` and run that Python file; each Lua
  test's first lines give its arguments (usually the `src` folder, a module
  path, or a built entry): `& $env:HD2_LUAJIT tests/<test>.lua <args>`.
- The build needs `../BingusSharedLoader` (or `BINGUS_LOADER_ROOT`);
  `test_dialog.py` reads recorded seeds from `../KnowYourConstellation`.
- In a worktree, `ROOT.parent` is `.claude/worktrees`: the build needs
  `BINGUS_LOADER_ROOT`, and `test_constellation_prediction.lua` skips its
  recorded-seed check without saying so. Run the gate once from the main
  checkout before a release.
- `test_identity_probe.py`, `test_live_search.py` and `test_search_probe.py`
  replay captures from `artifacts/`, which exists only in the main checkout.

Done when the build succeeds, the tests pass, and in-game
`BingusSharedLoader.log` shows
`mods/ipodalexei/mission_reroller_experiment: loaded` and the user confirms
the change works.

## Installing and testing in-game

The user does this; agents cannot launch the game. Import the mod ZIP and the
loader into Arsenal or HD2MM, keep the loader as the winning startup override
(bottom of the default Arsenal order), Purge / Deploy, launch. Read
`BingusSharedLoader.log` and `MissionRerollerExperiment.log` from the Logs
folder above.

Write a test plan in `docs/` for anything that needs an in-game check: what
to do, and which log lines prove it worked or failed.

## Release workflow

1. Work on a branch in a worktree; merge into `main` as
   `Merge the <change> into main`.
2. Release commit `Release <ver>: <what changed>`: bump `VERSION` in
   `scripts/build.py`, update the version strings in `README.md`, add a
   `docs/HISTORY.md` entry at the top marked **Not yet validated in game**.
3. After the user's in-game test, commit `Record the v<ver> in-game result`,
   changing the entry to **Validated in game** with the date and the log lines
   that prove it. Only the user's logs count as validation.
4. Publish by pushing a tag `v<ver>` on the commit to ship
   (`git tag v<ver>; git push origin v<ver>`). `.github/workflows/release.yml`
   then checks the tag against `VERSION`, builds, runs `test_package.py`,
   creates the GitHub release with the ZIP and adds a new version of the
   main file on Nexus Mods (mod 16762). The notes for both are the
   `docs/HISTORY.md` entries for that version (`scripts/release_notes.py`).
   A tag publishes to players, so only the user decides when to push one.
   The workflow pins the loader, KnowYourConstellation and LuaJIT commits;
   bump them there when a newer loader should ship.

Read `docs/HISTORY.md` before reworking a subsystem; it records why things
are the way they are.

## Live memory research

Use the Memory Explorer addon (`../MemoryExplorer`, read-only bridge) and
`scripts/check_live_*.py` while the user runs the game. Only one bridge
client may connect; when the lock is held, stop rather than remove it. Save
captures under `artifacts/`; session addresses stay out of the repository.
`../GameDllDumper/` produces the unpacked binaries when a new build needs
dumping (the on-disk ones are WinLicense-packed).

## Tools

Installed under `../tools/`; versions and paths in `../tools/README.md`.

- **Ghidra** (`../tools/ghidra/ghidra_12.1.4_PUBLIC`). This mod's projects in
  `../tools/ghidra-projects` are `HD2-25480438` (analysed `game.dll` dump from
  `../dumps/build-25480438/`) and `HD2exe-25480438`. The `HD2` / `HD2exe`
  projects are an older build; every RVA in `docs/` refers to 25480438. Run
  scripts headless against a saved project:

  ```
  support/analyzeHeadless.bat ../tools/ghidra-projects HD2-25480438 -process game.dll.unpacked.bin -noanalysis -scriptPath ../tools/ghidra-scripts -postScript DecompileFunctions.java <out.txt> <depth> <rva> [<rva> ...]
  ```

  Scripts in `../tools/ghidra-scripts`: `DecompileFunctions` (RVAs plus
  callees to a depth), `FindGlobalWriters`, `FindMemberAccess`,
  `FindSmallReferences`, `InspectRefresh`, `InspectSeed`, `FindDlLoader`.
  Set `MAXMEM=12G`. Keep generated output outside this repo.
- **Filediver** (`../tools/filediver/filediver-cli/filediver.exe`) extracts
  game archives. Always pass `--gamedir $env:HD2_GAME_ROOT` and an `-o` under
  `../extracted/`. Include patterns match `known_name.type`, so use
  `-i "dir/*"`; unnamed resources match `*.type`.
- **LuaJIT** (`$env:HD2_LUAJIT`, pinned commit, `msvcbuild.bat nogc64`).
  If a rebuild fails with `'minilua' is not recognized`, clear
  `NoDefaultCurrentDirectoryInExePath`.

## Game facts worth knowing

- The campaign has one seed. Rerolling regenerates every unstarted operation
  on every planet; in-progress operations are kept. In a lobby only the host
  may reroll, and the game syncs the seed to every player.
- Constellations can be added to a mission by a map stamp after generation,
  so enemy force exclusions are predictions. Illuminate missions and
  difficulty 1 draw none. See `docs/CONSTELLATION_RESEARCH.md`.
- World modifiers with environment tags depend on events, state-table rules
  and planet overrides; `src/template_environments.lua` ports the collector.
- The game is an entity-component system; gameplay definitions ship in
  protected `data/game/*.dl_bin` files and the game halts on modified copies,
  so change behaviour at runtime from Lua.
- Resource names hash with Murmur64A seed 0 (`archive.py` `resource_hash`).
