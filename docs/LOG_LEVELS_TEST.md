# Log levels test

In-game check of the log levels. **Not yet run in game.**

## What changed

Every line of `MissionRerollerExperiment.log` starts with its level, padded
to six characters: `DEBUG `, `INFO  `, `WARN  `, `ERROR `. The runtimes
write through `host.log.debug/info/warn/error` (`src/experiment_adapter.lua`)
instead of `host.emit`. The build's `log_level` (`config.log_level`) is the
lowest level written:

- a tagged release (`RELEASE_TAG` set, `build.LOG_LEVEL='info'`) writes
  `INFO`, `WARN` and `ERROR`;
- a development build (Operation Reroller Dev) and the research builds write
  `DEBUG` too.

`INFO` tells the story of a session a player sends with a bug report: the
banner, the build check, the loader and mod list, `KYC_ROSTER`,
`BINDING_REGISTERED`, `SHORTCUT_IGNORED`, the search request
(`LUA_SEARCH_MODIFIERS`, `LUA_SEARCH_EXCLUDED_MISSIONS`,
`LUA_SEARCH_CONSTELLATIONS`, `LUA_SEARCH_OBJECTIVES`, `LUA_SEARCH_STARTED`),
its outcome (`LUA_SEARCH_MATCH`, `LUA_SEARCH_CANCELLED`,
`LUA_SEARCH_EXHAUSTED`, `EXISTING_MATCH`), the seed write
(`PUBLISH_BEGIN`) and its verification (`PUBLICATION_STATE_VERIFIED`).
`WARN` marks a feature that turned off (`*_BLOCKED`, `TIME_ICONS off`,
`ESCAPE_HELD mappings=0`, `BINDING_FAILED`, `KYC_ROSTER_FAILED`, solver and
worker fallbacks), a mismatch with its details, a rolled-back publication
(`RESTORE_SEED`, `PUBLICATION_RESTORED`) and `LUA_SEARCH_FAILED`. `ERROR`
is `STOPPED:`, `SESSION_REJECTED` and the failed restores. Everything else,
including the modal, Escape, estimate, worker warmth, solver, day/night and
hover-check lines and the startup feature sentences, is `DEBUG`.

On the 2026-10-05 development log of one search and publication, 84 lines,
the release keeps 27, and 16 of those are the loader and mod list.

## Test 1: development build

1. `python -B scripts/build.py`, deploy
   `releases/Operation-Reroller-Dev-v<version>.zip` with the loader, launch.
2. Open the galactic map, view a planet, press F7, choose a mission, search
   and let it publish.

Passes when every line of `MissionRerollerExperiment.log` starts with one of
the four levels and the log has the same lines as before with the prefix:
`DEBUG MODAL_OPEN`, `DEBUG ESTIMATE`, `DEBUG SEED_SOLVER`, `INFO  LUA_SEARCH_MATCH`,
`INFO  PUBLICATION_STATE_VERIFIED`.

## Test 2: tagged build

1. `$env:RELEASE_TAG='v<version>'; python -B scripts/build.py; Remove-Item Env:RELEASE_TAG`,
   disable the development package, deploy
   `releases/Operation-Reroller-v<version>.zip`, launch.
2. Repeat the search of test 1.

Passes when the log has no `DEBUG` line, and has, in order: the banner, the
`build=... verified` line, `LOADER`, `MODS`, one `MOD` line per mod,
`KYC_ROSTER`, `BINDING_REGISTERED` (with Mod Bindings Menu), then the
search request lines, `LUA_SEARCH_STARTED`, `LUA_SEARCH_MATCH`,
`PUBLISH_BEGIN` and `PUBLICATION_STATE_VERIFIED`. Fails on any `DEBUG`
line, or a missing line from that list.
