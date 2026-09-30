# Host-injected runtimes and the reroll session — v0.24.0

## Status

**Not yet validated in game.** The build and all 17 test drivers pass on
v0.24.0.

## What changed

Players should notice no difference except in one rare case, described in the
second item below.

- **Runtimes take a host.** `experiment_adapter.lua` and each
  `*_runtime.lua` now run as functions of explicit inputs (`host`, `lib`,
  `hooks`). Before, they were concatenated into one chunk and shared its
  locals, and the build rewrote their source text. The chunk now has 57
  locals where it had 127.
- **One writer of the phase.** `src/reroll_session.lua` is the only code that
  changes `M.status`. The dialog reads its `view()` instead of keeping its
  own list of which statuses are final.
  - If the comparison passes but a search cannot be seeded, the run now ends
    with **Seed prediction unavailable for this planet** and logs
    `LUA_SEARCH_NOT_STARTED`. Before, the dialog stayed on "running" until the
    player cancelled.
  - Cleanup after `STOPPED:` no longer overwrites the status.
  - Starting a search clears the previous search report.
- **Log.** `LUA_SEARCH_STARTED` and `LUA_SEARCH_MATCH` now print
  `read_only=false` in the release. They used to print a stale
  `read_only=true`.

## Test

Build with `python -B scripts/build.py`, import the ZIP and the loader, then
Purge / Deploy and launch.

1. **Load.** `BingusSharedLoader.log` shows
   `mods/ipodalexei/mission_reroller_experiment: loaded`.
   `MissionRerollerExperiment.log` starts with
   `Mission Reroller 0.24.0 docked dialog; supervised live publication; F7 on the galactic map; background progress enabled`
   and `build=25480438 hashes=verified helper_signature=verified`.
2. **A match.** On the galactic map, open a planet, press F7, check one
   common mission type and start the search.
   - The dialog shows **Checking planet data**, then **Searching seeds**,
     **Refreshing operations**, **Opening matching operation** and finally
     **Matching operation selected**.
   - The log shows `LUA_SEARCH_STARTED ... read_only=false`, then
     `LUA_SEARCH_MATCH`, and the publication and selection lines as in
     v0.23.0.
3. **No match.** Search for a rare combination with a small budget, or let
   it run out. The dialog ends at **No match; search again to continue**.
   Start again: the old "No match in N seeds" report must not reappear while
   the new run is checking planet data.
4. **Cancel.** Start a search and cancel it from the dialog. The dialog shows
   **Search cancelled** and the log shows `LUA_SEARCH_CANCELLED`. Start again
   to confirm that a new run works.
5. **Alt-tab** during a search. The search continues, as in v0.23.0.

In every run, the log must contain no `SESSION_REJECTED` and no `STOPPED:`.
If it contains `SESSION_REJECTED <what>`, the pipeline reported a phase
change that the session does not allow: record the full line.
