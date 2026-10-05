# Mission Reroller development log

This is the log kept during development, newest first. It was the README
until v0.20.2 was published; the [README](../README.md) now describes the
mod for players. Each entry records what was known when it was written, and
the first two were brought up to date on 2026-09-29.

**Not yet validated in game: v0.35.0.** Releases the seed solver's
worker VMs, the one-poll capture, the reachability checks that disable
impossible starts and unreachable enemy forces and side objectives, the
filter catalogue's fix for the game's JIT, and the key state fix:
`GetAsyncKeyState` is now resolved by address and called through an
unnamed function pointer, so another addon's `uint16_t` declaration can no
longer make F7 read as never pressed
([KEY_STATE_TEST.md](KEY_STATE_TEST.md)).

**Not yet validated in game: impossible requests cannot start, and
unreachable enemy forces and side objectives are disabled.** On 2026-10-05
a request the dialog already marked "No seed gives this now" (planet 268,
difficulty 10, Search and Destroy with Light Bugs, Lidar Station and SEAF
Artillery excluded) could still be started and scanned 261,043 seeds in
vain. Begin Search is now disabled for such a request. And for each
checked mission the dialog works out, after the estimate and in the same
4 ms slices, which offered enemy forces and side objectives some draw path
can still give or avoid with the request's other rules
(`SeedSolver.reachability`): a rule only decides whether each kind's step
of a path exists, so it takes the request's feasible kind choices once and
one `mission_paths` per kind and rule, with each kind's side-objective
paths memoised. About 0.3 s of background work per request; on a live
capture of that board it disables Light Bugs, Bug Nursery and Balanced
Terminids for Search and Destroy, and every answer agrees with the full
plan (`tests/reachability_cases.lua`, in `test_seed_solver_search.py` and,
in the game's `lua51.dll`, `test_game_jit.py`). The search's matcher uses
the same predicted enemy forces as the solver, without map stamps, so a
disabled option could never have matched a normal operation. Test plan:
[DIALOG_REACHABILITY_TEST.md](DIALOG_REACHABILITY_TEST.md).

**Fixed 2026-10-05, not yet validated in game: "Eligibility unavailable"
after a few dialog openings.** In game the dialog logged
`FILTER_CATALOGUE_BLOCKED ...: attempt to concatenate field 'effect_id' (a
nil value)` on every opening after two published searches, though the line
before had just stored that field. The game's LuaJIT 2.1.0-alpha
miscompiles the catalogue's loop once it is hot: a field stored on a fresh
table right after a call reads back as the constructor's value (nil, or a
placeholder put there). It reproduces offline only in the game's own
`lua51.dll` with the JIT on, from the tenth build of the catalogue on a
capture; v0.34.0 has it too. The catalogue, the predictor
(`composition_prediction.lua`) and the solver inputs now work out
`effect_id` first and build each operation table in one constructor.
`tests/test_game_jit.py` (in the gate; skipped without the game's DLL or
the captures) builds the catalogue 50 times in the game's DLL.

**Validated in game 2026-10-05 except cancel and quit: the seed solver
walks in worker VMs.** A request one seed in 28 million matches (planet
268, difficulty 10, three missions with their enemy forces, two objectives
and a modifier excluded, by day) was found, published and verified in 8.3
s: `LUA_SEARCH_MATCH ... elapsed_s=8.33 ... walk_steps=315178725 workers=8`,
`SEED_SOLVER_WORKERS_END workers=8 ... failed=0 capped=0
peak_worker_heap_kb=1335`, `PREDICTION_VERIFIED selected_row=29`. That is
about 38 million walk steps a second; on the main thread the same walk
needed about 180 s. Since then, not yet validated in game: the workers split
each job's starts into equal arcs instead of random starts; a running
search shows the seeds it has covered (`0:07 - 348M seeds covered - 1 in
28M match`, logged as `covered=`); the start no longer flashes `0 of
1,000,000 seeds searched`; workers set themselves up on their own
threads, so starting one costs the frame well under a millisecond; and the
request's estimate shows no time until a search has measured this
machine's walk rate (the fixed 800,000 steps/s guess is gone).
Unreleased, on the `worktree-native-solver-research` branch with
`arch/deepening` merged. A search the seed solver seeds now walks in up
to eight worker VMs (fresh LuaJIT VMs from the game's `lua51.dll` on
thread-pool threads at below-normal priority, `src/seed_solver_workers.lua`)
instead of on the main thread. Each walks the whole chain from its own
starts, and hands back seed and row. The main thread applies the Day / Night
check, predicts and matches as before, and yields while the workers have
nothing ready. Paths travel as compact text (`src/seed_solver_codec.lua`).
The pool scans the address space below 2 GB, starts only the workers that
fit beside a 16 MB reserve, starts them over several frames, caps their
heaps, and closes a VM only after its thread has left it. Without workers the
walk stays on the main thread. Offline the workers' candidates equal the
in-process chain's in both LuaJITs. Test plan:
[SOLVER_WORKERS_TEST.md](SOLVER_WORKERS_TEST.md).

**Research, 2026-10-05: native code and worker threads for the seed
solver.** A C port of the solver's job loop runs 5 to 7 times faster than
LuaJIT per core, but no way of running native code in the game fits the
mod's rules (`LoadLibrary`, `VirtualAlloc` and `VirtualProtect` are banned).
The game's `lua51.dll` exports the Lua C API, so extra LuaJIT VMs on worker
threads can walk on several cores: in the game's own `lua51.dll`, offline,
12 workers ran 8 to 14 times one VM with identical candidates. The lattice
inverter now runs in doubles instead of boxed int64, 1.3 to 2.3 times the
walk; not yet validated in game. Measurements, risks and next steps:
[NATIVE_SOLVER_RESEARCH.md](NATIVE_SOLVER_RESEARCH.md). The Worker Thread Probe, a
separate research addon, tests worker VMs and the memory below 2 GB in game.
It ran cleanly on 2026-10-05: no GameGuard reaction, 6.1 million steps/s
per worker, a clean join at shutdown, and only 31.9 MB free below 2 GB
([WORKER_PROBE_TEST.md](WORKER_PROBE_TEST.md)).

**Not yet validated in game: v0.34.0 seed solver search.** Searches
with mission, enemy force, side objective or Day / Night rules now take
their candidates from the seed solver (`src/seed_solver_*.lua`): draw
paths per filter, mission seeds walked by their root draw, inverted to
operation and campaign seeds, each confirmed by the predictor; requests
without paths scan as before. Cities, excluded side objectives, linked
draws and per-row Day / Night shares are covered, mission checks are a
compiled decision tree, and jobs take turns by candidate yield. The dialog
estimates the match share and usual time in the background while the
filter is edited, and a running search shows its clock. Research, audits
and offline measurements: [SEED_SOLVER_RESEARCH.md](SEED_SOLVER_RESEARCH.md);
test plan: [SEED_SOLVER_TEST.md](SEED_SOLVER_TEST.md).

**Not yet validated in game: v0.33.2 brief mod manager description.**
`DESCRIPTION` and `REQUIREMENT` in `scripts/build.py`, the text Arsenal and
HD2MM show for the mod and its option, are cut to three sentences: what it
does, F7 on the galactic map, and Bingus Shared Loader v16+ loaded last.
Nothing in the entry changed.

**Not yet validated in game: v0.33.1 Operation Reroller package name.**
The release package is named Operation Reroller: `RELEASE_NAME` in
`scripts/build.py` sets the mod manager name and `Operation-Reroller-v<ver>.zip`,
and the release workflow uses it for the GitHub release title and the Nexus
file name. The module, `RELEASE_GUID`, global and log are unchanged, so mod
managers treat it as an update of the published mod. The in-game banner and
the MODS tab heading still say Mission Reroller.

**Not yet validated in game: v0.33.0 time of day tiles and mission
changed headers.** The release carries three changes since v0.32.1. Time of
day moved from a dropdown to ANY, DAY and NIGHT tiles on the section's
header, DAY and NIGHT drawn with the galactic map's sun and moon from the
ship UI atlas through `Gui.bitmap_uv`; the chosen tile says how long the
side holds, amber while the sky loads and red when no city holds it. Test
plan: [TIME_OF_DAY_HEADER_TEST.md](TIME_OF_DAY_HEADER_TEST.md). A mission
click that discards enemy force or side objective rules marks the section
header red with `- MISSION CHANGED` until the header or CLEAR is clicked,
and `ANY MISSION` rules no longer dim missions; the user tested it in game
on 2026-10-04 with nothing logged
([MISSION_CHANGED_TEST.md](MISSION_CHANGED_TEST.md)). `src/filter_catalogue.lua`
now counts the copies the remaining side and tactical rows can fill, so
exclusions that leave too few for a mission's slots are refused before a
search starts.

**Validated in game: v0.32.1 page checks under Proton.** A
Proton player's v0.31.0 log stopped on `unexpected target page` right after
`MODAL_OPEN`: the dialog's snapshot failed one of its four page checks, the
error was not caught, and the mod stopped for the session, so the panel
closed at once and F7 did nothing afterwards. `page()` in
`src/experiment_adapter.lua` now takes a name and reports the state,
protection and type `VirtualQuery` returned. A module-image page may be
`PAGE_WRITECOPY`, which Wine can report for a written data page where
Windows reports `PAGE_READWRITE`; only `rng_state` is checked that way and
the mod only reads it, and private pages, every write target among them,
still need `PAGE_READWRITE`. The dialog's `context()` catches a failed
snapshot, logs `SNAPSHOT_BLOCKED <error>` once per distinct error and shows
`PLANET DATA UNAVAILABLE`; the search and publication still stop on a
failure. Test plan: [PROTON_PAGE_TEST.md](PROTON_PAGE_TEST.md). The user
confirmed the fix working in game on 2026-10-03; no log lines were quoted.

**Validated in game: v0.32.0 bundled Know Your Constellation roster.**
Know Your Constellation v4.0 shipped without the `EnemyIntelligence.roster`
export the v0.28.0 tooltips read, so players saw no units. With
CowboyBingus's permission the release now carries that mod's v4.0
`roster.lua` and `roster_data.lua` unchanged in
`src/vendor/know_your_constellation` (upstream `662609f`, pinned by git
blob ID in `tests/test_bundled_roster.py`). `src/bundled_roster.lua` wraps
them as roster api 1, with Know Your Constellation's `from_native` tag
mapping and English unit names. `F.roster` in `src/unit_forecast.lua` takes
an installed export first and falls back to the bundled roster when that
mod is missing, has no export or has disabled itself, still guarded by the
data's build matching `src/offsets.lua`. The log says which:
`KYC_ROSTER ready bundled v4.0 build 25480438 (<why not installed>)`.
Test plan: [BUNDLED_ROSTER_TEST.md](BUNDLED_ROSTER_TEST.md). The user
confirmed it working in game on 2026-10-03; no log lines were quoted.

**Validated in game: side and tactical blocks.** After the v0.31.0
test the user asked to tell side objectives from tactical ones. The SIDE
OBJECTIVES section now lists side objectives under a SIDE label and
tactical ones under TACTICAL, each block in two columns
(`src/docked_panel.lua`). `C.objectives` gives each row its role: side when
any mission type of the group draws it as a side objective (Mobile Radar
and Terminate Illegal Broadcast are side on some types and tactical on
others), else tactical, and sorts side rows first. Matching is unchanged.
The user confirmed the labelled blocks in game on 2026-10-02.

**Validated in game: v0.31.0 side objectives.** A SIDE
OBJECTIVES section requires or excludes side and tactical objectives per
checked mission, or for the operation with `ANY MISSION`. Grilled with the
user on 2026-10-02: briefing objectives only (no sub-steps), all required
present and none excluded, per mission like enemy forces, presence only,
English titles in the catalogue, and the matched objectives logged rather
than shown.
- **Where they come from.** Not map stamps: the descriptor packer `fc2ea0`
  writes objective ids into the mission descriptor through `1756660` /
  `1756730`, from the mission seed, type, difficulty, the planet's biomes
  and its world modifiers. Nothing is on the board, so the search predicts
  them like constellations. Details in
  [SIDE_OBJECTIVE_RESEARCH.md](SIDE_OBJECTIVE_RESEARCH.md).
- **Port.** `src/side_objective_prediction.lua` (pure) and
  `src/side_objective_inputs.lua` (reads, with per-planet caches so a seed
  costs no reads). `src/template_environments.lua` now also returns the
  world modifiers it collects; they double as the descriptor's list.
- **Evidence.** `scripts/validate_side_objectives.py` emulates `1756660` in
  Unicorn on pages read from the running game and replays the port on the
  same pages: 2,400 random descriptors, 3,524 side and 1,033 tactical
  objectives, no mismatch. It showed `20bbb78` is `roundf`; the first port
  took it for `ceilf`. A live descriptor read of a difficulty 10 Terminid
  Launch ICBM showed the expected 4 side and 1 tactical objectives with a
  repeated Spore Spewer.
- **Filter.** `src/filter_catalogue.lua` offers what each mission type can
  draw on the planet (environment, difficulty, configuration, bans) and
  refuses more required rows than a type's slots or excluding every row of
  a role; the dialog skips such a click. `S.find` takes the groups as its
  last argument. The panel's rows close up to fit the fifth section.
- **Diagnostics.** Hovering a mission logs `SIDE_OBJECTIVE_CHECK ...
  modifiers_agree=... agree=...`; a search logs `LUA_SEARCH_OBJECTIVES` and,
  on a match, `LUA_SEARCH_MATCH_OBJECTIVES`. Test plan in
  [SIDE_OBJECTIVE_FILTER_TEST.md](SIDE_OBJECTIVE_FILTER_TEST.md).
- **In game, 2026-10-02.** Eleven `SIDE_OBJECTIVE_CHECK` lines on planets
  201 and 173 (Geological Survey, Retrieve Valuable Data, Launch ICBM,
  Emergency Evacuation, Spread Democracy, Eradicate, Evacuate High-Value
  Assets) all read `modifiers_agree=true agree=true`, repeats included. A
  search `LUA_SEARCH_OBJECTIVES Launch ICBM=require Lidar Station exclude
  SEAF Artillery` matched seed 787509373 row 27 after two seeds
  (`LUA_SEARCH_MATCH_OBJECTIVES ... 59:[Launch ICBM/0, ..., Lidar
  Station/3, Spore Spewer/3, Stalker Lair/3, Stalker Lair/3, ...]`),
  published (`PUBLICATION_STATE_VERIFIED seed=787509373 row=27`), and the
  hovered mission's game list agreed afterwards. Whether a level can drop
  an objective was not checked.

**Not yet validated in game: v0.30.0 planets under attack.** The release
package of the invaded-planet change below, validated in game from a branch
build on 2026-10-02. That build also carried every v0.29.0 change. The
tagged build itself is still to be checked in game.

**Validated in game: invaded planets.** On a planet under attack,
every search showed "Retrying changed planet data" until the capture
timed out (`LUA_CAPTURE_RETRY planet=173 … Unsupported invasion operation
bases`, 61 failures). The port rejected invasions on purpose since v0.8.0;
this was the first invasion the mod met in game.
- **Invasion operations.** `11e4060`, which `src/offsets.lua` called
  `generate_operation_rows`, is the invasion pass: the normal pass skips an
  invaded planet and this one draws the same rows from the same RNG, with
  the category from the invasion level (new global `invasion_levels`) and
  the invasion's faction. New fields `campaign.invasion_events` and
  `invasion_event_count` name the planet's invasion.
- **Special category.** `174ab50`, checked since v0.8 with no recorded role,
  resolves a special definition's category 14: 8 when the planet's first
  invasion is at level 1, else 9 (or 12). The port assumed 9.
- **Evidence.** A Memory Explorer capture of planet 173 replays exactly: 40
  operations and 96 missions, and the dialog options at every difficulty.
  Analysis and test plan in [INVASION_TEST.md](INVASION_TEST.md). Defence
  events remain unsupported.
- **In game, 2026-10-02.** Searches on invaded planets 173 and 245 passed
  (`LUA_SEED_PREDICTION_PASS planet=173 … bases=40 operations=40
  missions=96`, `PREDICTION_CHECK descriptors_match=true`,
  `PUBLICATION_STATE_VERIFIED seed=102427967 row=39`), and normal planets
  201 and 270 still published.

**Not yet validated in game: v0.29.0 exclude missions.** The release
package of two changes each validated in game from a branch build on
2026-10-01: excluded missions (below) and operations edited by another mod
(the entry after it). The offset anchors since v0.28.0 change no behaviour.
The tagged build itself is still to be checked in game.

**Validated in game: excluded missions.** A mission row cycles ANY,
REQUIRED, EXCLUDED, like a modifier row. An excluded family takes no slot,
and the matched operation holds no mission of it, whatever its
constellations.
- **Disabled conflicts.** A first version let a mission that cannot join
  the required ones go straight to EXCLUDED. The user found that less clear
  than the old dimmed row, so such a row is disabled again and a mission is
  excluded only by clicking it once more after requiring it. A required
  mission every reachable operation holds goes back to ANY instead.
- **Validation.** `src/filter_catalogue.lua` refuses an excluded mission
  the catalogue does not offer, one also required, and excluding every
  mission offered. `src/mission_compatibility.lua` accepts a request only
  when a reachable mission mask covers the required families and is
  disjoint from the excluded ones.
- **Matching.** `S.find` takes the excluded set as its last argument; the
  seed search, the existing-board check (after the external-edit filter),
  the complete-board confirmation and the pre-publication recheck pass it,
  and it is part of the resume key. A search with exclusions logs
  `LUA_SEARCH_EXCLUDED_MISSIONS <names>`.
- **In game, 2026-10-01.** The user confirmed it works with conflicting
  missions disabled. The log kept from that day holds only
  required-mission searches, so no exclusion line was captured. Test plan
  in [MISSION_EXCLUDE_TEST.md](MISSION_EXCLUDE_TEST.md).

**Validated in game: operations edited by another mod.** A player
using Refresh Operations + Missions got `IDENTITY_TEST_MISMATCH`. The user
reproduced it on 2026-10-01: F7 passed, F6 refreshed the selected
operation's missions, and F7 then failed on that row alone
(`LUA_IDENTITY_DETAIL row=28 observed=23/3061063729/d10
predicted=23/1048270963/d10`, campaign seed unchanged, row 29 still
matching). F6 writes a new operation seed without a reroll.
- **Edits are proven per row** (`src/external_edits.lua`): by a baseline,
  the first board seen per planet and campaign seed, recorded once a second
  on the galactic map and after each passing comparison; or, for a changed
  operation seed alone, by a matching row after it. A missing or extra row,
  a changed difficulty or an edited operation in progress still stops the
  run. Checking only on planet selection was considered and rejected: F6
  can run after any earlier check, and v4 refreshes without the planet open.
- **The edited rows are left out** of the level and composition checks, the
  search's frozen baseline and the existing-match check. The check after the
  seed is written still compares the whole board and restores the old seed
  on a difference.
- `identity_test_mismatch` now has a caption, and a mismatch that looks like
  an unproven edit says another mod may have changed the operations.
- Design in [EXTERNAL_EDITS.md](EXTERNAL_EDITS.md), in-game test in
  [EXTERNAL_EDITS_TEST.md](EXTERNAL_EDITS_TEST.md).
- **In game, 2026-10-01.** The user's log, with Refresh Operations
  installed: after ordinary rerolls on planet 201, F6 refreshed
  row 28 and F7 rerolled. The baseline proved the edit, the search ran and
  the regenerated board matched the prediction, so a reroll replaces an
  edited row:

  ```
  BASELINE_RECORDED planet=201 seed=3844731423
  LUA_IDENTITY_EDITED planet=201 seed=3844731423 pool=31 special_events=0 matched=29 live=30 predicted=30 ...
  LUA_IDENTITY_EXTERNAL_EDIT row=28 observed=26/810457775/d10 predicted=26/2434653823/d10 evidence=baseline
  LUA_COMPOSITION_PASS planet=201 operations=30 templates=30 modifiers=30 missions=69 ... edited_rows=1
  LUA_SEARCH_MATCH seed=3844732274 row=28 attempts=851 ...
  PUBLISH_BEGIN previous_seed=3844731423 candidate_seed=3844732274 primary_planet=201 viewed_planet=201
  PREDICTION_CHECK descriptors_match=true reason=nil
  PUBLICATION_STATE_VERIFIED seed=3844732274 row=28 map_ui_row_confirmed=true mission_unselected=true
  ```

  Not yet run: F6 on several operations and an edited operation that
  already matches (cases 2 and 3 of the test), and Refresh Operations'
  plain refresh.

**Validated in game: v0.28.0 Know Your Constellation names and unit
tooltips.** Enemy forces now use Know Your Constellation v4.0's names, and
the three tags a map stamp can add (Bile Bugs, Hunter Swarms, Predator
Strain) carry a `*`. Pointing at an enemy row shows a tooltip left of the
panel, on layers 1016-1018 above Know Your Constellation's box.
- **Units from Know Your Constellation, not a copy.** The tooltip calls
  `EnemyIntelligence.roster`, an export proposed upstream on the fork branch
  `export-roster-api` (api 1: `build`, `from_native`, `title`, `forecast`).
  `src/unit_forecast.lua` uses it only when api is 1, its roster build is
  this game build and Know Your Constellation has not disabled itself, and
  rechecks that on every hover. A roster that raises turns unit tooltips off
  for the session; the mod keeps running. Log lines start with `KYC_ROSTER`.
- **Inputs.** The catalogue's `forecast(tag)` gives the planet-wide tags the
  configuration keeps plus the hovered one, and the spawn weights Know Your
  Constellation applies: category 72 campaign effects and type 15 global
  effects (`constellation_inputs.spawn`), read on the first hover only.
- **Layout.** The panel is docked on the right and Know Your Constellation's
  box hangs under the planet panel on the left, so only the tooltip needed a
  higher layer. It stays inside the window and cuts the small enemies to
  "and N more" when it would not fit.
- **In game, 2026-09-30.** The user confirmed the release build with the
  Know Your Constellation export build: the tooltips show with it installed,
  none without it, and the tooltip's units match the missions the reroll
  generates ([KYC_TOOLTIP_TEST.md](KYC_TOOLTIP_TEST.md)). Confirmed by the
  user's report; no log lines were quoted. Players see the units only once
  a Know Your Constellation release ships the export.

**Validated in game: v0.27.0 day or night.** The panel has a
fourth section, TIME OF DAY: Any time, Day or Night. With Day or Night the
matched operation's missions stay on that side for 2.5 hours after the
reroll, clear of the 30 minutes around dawn and dusk. On planets and moons
whose days are too short the filter holds for half of a side instead, and
the panel says how long. When only a city can match and it is on the wrong
side, the panel counts down to when it will be ready instead of searching.
- **The sky.** A planet's time of day is the angle about its axis between a
  mission's position and its sun, which the game works out from galactic
  war time and a chain of spinning, orbiting bodies (1016c20, 101c7c0,
  1022270, 1017ef0). `src/planet_sky.lua` ports it and reads the viewed
  planet's sky from the war table's own copy; on live captures it matches
  the game within 0.04 degrees, on a planet and on a moon.
  [DAY_NIGHT_RESEARCH.md](DAY_NIGHT_RESEARCH.md) has the research.
- **The search.** Each candidate is checked over a window that follows war
  time, a match again just before the write (a failure logs
  `DAYNIGHT_WINDOW_CLOSED` and the search continues after that seed), in
  publication's preflight, and on the verified board
  (`DAYNIGHT_VERIFIED`).
- **Checks.** Four sky functions join the first-frame signature check; the
  startup line reads `signatures=37`.

The release gate and every capture replay pass. The in-game plan is
[DAY_NIGHT_TEST.md](DAY_NIGHT_TEST.md).

Validated on 2026-09-30: the log shows `Mission Reroller 0.27.0` and
`build=25480438 hashes=verified signatures=37 anchors=24 verified`. Four
searches matched, published and verified, each with `holds=true`,
`DAYNIGHT_VERIFIED holds=true` and `PUBLICATION_STATE_VERIFIED`: night and
day on planet 201 (`day_s=56598 buffer_s=9000`, missions at 01:01 to 01:31
and 09:10 to 10:12), and day and night on planet 100, whose short days cap
the buffer (`day_s=6606 buffer_s=1514`, missions at 09:22 to 10:04 and
21:03 to 21:31). The player confirmed the missions were on the chosen
side. The city steps, the countdown and a twilight drop have not been
run yet.

Two panel fixes followed that run, before publication. The CHOSEN word
showed only beside Night, most likely because a text the game creates
empty stays blank after it is given a value; the words beside Day and Any
time started empty. Every time of day row now holds CHOSEN, clear unless
chosen, and the panel draws any empty text as a clear placeholder. The enemy section also kept room for two note
lines under its rows even with none to show, which left a gap above TIME
OF DAY; it now keeps room only for the lines it shows.

**Not yet validated in game: v0.25.0 every offset in one file.** Players
should see no change; the log's startup line becomes
`build=25480438 hashes=verified signatures=33 anchors=24 verified`.
- **`src/offsets.lua`.** The build, both module hashes, 33 code entries
  (bytes or SHA-256), 26 module-relative globals and 129 struct fields,
  strides and sizes used to be literals spread over about 30 files, several
  copied between runtimes. They now live in one table, each with a note of
  where it came from, and the code reads them through `O` (`O.rva.board`,
  `O.board.seed`). A game update is an edit of that file.
- **Checked on the first frame.** The adapter checks every code entry, and
  for 24 globals the RIP-relative instruction that addresses them, before
  anything runs; a stale one stops the mod with
  `offset signature <name> mismatch` or `offset anchor <name> mismatch`.
  The window and selection signature files and the identity probe's
  generator hashes are now entries of the table. 45 struct fields are
  anchored to a checked function that uses them; the rest are marked
  `unverified=true`.
- **Updating.** `scripts/check_offsets.py` checks the table against a game
  dump, suggests new RVAs for stale entries from the previous build's dump,
  and finds anchors. [UPDATING.md](UPDATING.md) is the runbook.
  `tests/test_offsets.py`, in the release gate, fails on an offset literal
  anywhere else in `src/`.
- **Research builds removed.** The keyboard experiment, combined dialog,
  seed test, one-shot probe, preflight, input inventory and mouse probe
  builds held most of the duplicated offsets and are gone; git history
  keeps them. The release module and GUID moved to `build_core.py`
  unchanged.

Every capture replay in `artifacts/` gives the same result as before the
change, and all test drivers pass. The in-game plan is
[OFFSETS_TEST.md](OFFSETS_TEST.md).

**Not yet validated in game: v0.24.0 runtimes on a host, one reroll session.**
This release restructures the code; players should see only the fix below.
- **Runtimes on a host.** The adapter and the five runtimes used to be
  appended raw into one chunk. They shared about 125 locals through the
  order they were appended in, and the build patched their source text with
  a chain of string replaces, some of which could fail silently. Each one now
  runs as a function of `host`, `lib` and `hooks`. The build's mode is data
  (`build_identity_probe.config()`) and no runtime text is rewritten. The
  main chunk went from 127 locals to 57. `tests/test_runtime_host.py` checks
  that every runtime file is embedded unchanged and creates each one with a
  fake host.
- **One reroll session.** `src/reroll_session.lua` is now the only writer of
  the run's phase, and the dialog reads its `view()` instead of keeping its
  own lists of final statuses.
- **Fix: runs that never ended.** A comparison could pass without a search
  being seeded (`composition_test_passed` without independent operation
  bases, or a capture missing level or composition data). The dialog then
  showed "running" until the player cancelled. That path now ends with
  **Seed prediction unavailable for this planet** and logs
  `LUA_SEARCH_NOT_STARTED`.
- **Other fixes.** Cleanup after `STOPPED:` no longer overwrites the status,
  and a new search clears the previous search's report.
- **Log.** `LUA_SEARCH_STARTED` and `LUA_SEARCH_MATCH` print the real
  `read_only=false`.
- **Tooling.** `.gitattributes` keeps `.lua` files LF on checkout, which
  fixes `test_core_package`, `test_preflight` and `test_probe` wherever
  `core.autocrlf` is on. `scripts/emulate_seed.py` now finds
  `tools/seed-emulator-deps` from a worktree.

All 17 test drivers pass. The in-game plan is
[RUNTIME_HOST_TEST.md](RUNTIME_HOST_TEST.md).

**Validated in game: v0.23.0 no hitch when a search starts.** Before a
search the mod checks the board every 0.5 s until four checks agree, each
check capturing it twice. A capture is about 50 ms of reads offline, and
both ran in one frame, so the first seconds after `Reroll operations`
stalled several times. Each check now runs as a coroutine whose reads yield
once the 16 ms slice of the seed search is used; the stability rules are
unchanged. On the saved city capture one capture takes 3 to 4 frames, the
longest about 20 ms, and equals the unsliced capture byte for byte.
`tests/test_identity_probe.lua` covers a check spread over frames and a
restart during one. Tested in game on 2026-09-30: clicking `Reroll
operations` no longer freezes the frame.

**Validated in game: v0.22.1 options on Brilliance and Fronteria.** On
those planets the panel showed `NO PLANET CHOSEN` and the log repeated
`FILTER_CATALOGUE_BLOCKED ... Unsupported conditional world-modifier
environment tags: hash=3778107369`. The environment decoder refused any
world modifier with environment tags because it did not know which world
modifiers are active. It now ports the game's collector (1267460): events
apply by planet, sector, owner or everywhere (12e1210); state-table entries
require or exclude other modifiers; planet overrides add or remove them; a
faction-1 planet takes unflagged modifiers only while listed (12672b0). The
tags of each active modifier join the environment, as in 177e4e0.
`tests/test_template_environments.lua` covers each rule on synthetic
memory, and `scripts/check_live_planet.py` replays the viewed planet from
live memory: the board prediction and the options at every difficulty.
Tested in game on 2026-09-30: both planets list their options.

**Validated in game: v0.22.0 mod list in the log.** On the first frame the
log lists the loaders (`LOADER`) and every Lua mod they started or failed to
start (`MODS`, then one `MOD` line each, sorted by name). Bingus Shared
Loader records no versions, so a version is the `version` field of the mod's
`require` result or of its global, named after the entry's last path segment
(`mod_bindings_menu` becomes `ModBindingsMenu`); otherwise `unknown`. Our own
global now carries `version`. On 2026-09-30 the log listed the loader
(version 17) and three started mods, each with its version:
`skip_intro_animation` 2, `memory_explorer` 0.2.0 and ours 0.22.0.

**Next in-game test: [v0.21.0 input ownership after a resolution change](INPUT_OWNERSHIP.md).**
Changing the resolution and then opening the dialog stopped the mod with
`Modal input ownership lost`: the game had put back a window flag the mouse
gate had set. The gate now takes its flags back and counts the drift, a lost
ownership closes the dialog instead of stopping the mod, and the log names
the flag that moved. Not yet tested after a resolution change.

**Validated in game: [v0.22.0 F7 on the map only](KEYBIND_HINT_TEST.md#rebinding).**
The shortcut is F7 instead of Ctrl+Shift+F8, and a key bound on the MODS
tab replaces it. It only acts with the galactic map on top of the screen
stack and its BACK hint shown, so the options page, and presumably the ESC
menu, block it. Ignored presses log the screen stack, which will confirm
the ESC menu's screen type. On 2026-09-30, without Mod Bindings Menu
installed, F7 opened the panel on the map three times (`MODAL_OPEN
scope=planet key=F7 screens=15`) with no `STOPPED` line, so F7 works
without the menu. Whether the ESC menu blocks it is still unconfirmed.
The default moved from F8 to F7 because the Fast Enter Hellpod mod uses F8
by default, and keyboard input reaches every addon and the game, so one press
would have triggered both.

**Validated in game: [v0.21.0 rebinding on the MODS tab](KEYBIND_HINT_TEST.md#rebinding).**
With Mod Bindings Menu installed the mod registers Reroll operations under
a Mission Reroller header on the game's MODS binding tab; the bound key
opens and closes the panel beside Ctrl+Shift+F8, and the hint beside BACK
names it, read from the game's live binding map. The first in-game try
stopped the mod with `bad argument #2 to 'VirtualQuery'`: addons share one
LuaJIT VM, the first C declaration of a function wins, and Mod Bindings
Menu declares VirtualQuery with its own struct. The mod now passes a void
pointer to VirtualQuery (the cursor calls go through `src/window_cursor.lua`,
below), and
`tests/test_ffi_conflicts.lua` reproduces the conflict. On retest the user
confirmed that a key bound on the MODS tab works and is kept.

**Validated in game: [v0.21.0 key hint beside BACK](KEYBIND_HINT_TEST.md).**
A `CTRL + SHIFT + F8  REROLL OPERATIONS` hint drawn to the right of the war
table's own BACK hint, anchored to that native widget so it follows the
game's scale. A live survey through Memory Explorer found the widget at
offset 1696 of the map screen object; the user confirmed the hint on
screen. Search, prediction and publication are those of v0.20.2.

**Not yet validated in game: v0.20.3 cursor reads shared with other addons.**
A user's log ended with `STOPPED: ... bad argument #1 to 'GetCursorPos'
(cannot convert 'struct 2306 [1]' to 'struct 1129 *')` the moment the dialog
opened. LuaJIT keeps the first `ffi.cdef` of a function name for the whole
VM and ignores later ones, and every addon shares that VM. Another addon had
declared `GetCursorPos` with its own POINT struct first, so the dialog's own
struct was rejected. `src/window_cursor.lua` now resolves `GetCursorPos`,
`ScreenToClient` and `GetClientRect` by address and calls them through
unnamed function pointers with untyped parameters, which no other
declaration can change. The dialog, the combined test build and the mouse
test build use it. `tests/test_window_cursor.lua` reproduces the clash
against the real user32 and passes. Nothing else changed.

**Validated in game: [v0.20.2 hosting a lobby](LOBBY_HOST_TEST.md).**
Tested in a lobby of two on 2026-09-29: the host rerolled and the other
player saw the rerolled operation. The mod no longer stops when the session
has more than one player. The host of a lobby of up to four can reroll; a
guest is told that only the host can. The game then sends the new seed to
every player, so their war tables change too. Lobbies of three and four have
not been exercised, and what several of the fields mean in a lobby is
inferred from the game's code. The earlier builds still require one player.

**Working in game: [v0.20.1 quiet data gaps](DOCKED_DIALOG_TEST.md).**
Confirmed by the user. A brief gap in the
planet data no longer dims the dialog, changes its status or blocks clicks.
REROLL OPERATIONS pressed during a gap waits and starts on fresh data. The
dialog changes only when the returned data differs. A gap of 1.5 seconds or
more is still reported.

**Validated by log: [v0.20.0 docked dialog](DOCKED_DIALOG_TEST.md).**
Three requests were completed from the panel in game and verified. The log
does not show how the panel looked. The dialog is a panel
docked to the right edge of the screen, without dimming the map. Missions,
modifiers and enemy forces are three sections, one open at a time, and a
closed section shows its summary. Enemy forces are chosen per checked mission
with a row of buttons instead of pages. REROLL OPERATIONS is disabled until a
mission or a rule is set, and a search shows its four steps and the seeds
searched. Escape is not handled, because the dialog blocks the mouse only.
Search, prediction and publication are those of v0.19.0.

**Validated in game: [v0.19.0 constellation exclusion](CONSTELLATION_FILTER_TEST.md)
and [all mission types and cities](CITY_SCOPE_TEST.md).**
Each constellation cycles ANY, ACCEPT, EXCLUDE per checked mission, or for the
whole operation when no mission is checked; any number can be excluded.
The dialog lists every mission type that has a title, 126 types in 74
families, instead of twelve families. Opening it with the cursor on a city's
operation marker, or with that operation selected, limits the options and
the search to that city. v0.18.0 published and selected a city operation in
game three times. An operation in progress is reported as not rerollable.
The user validated constellation exclusion in game in a separate session.

**Working in game: [v0.16.0 fast seed search](FAST_SEARCH_TEST.md).**
The search validates its inputs once a second and before a match instead of
after every seed, and predicts only the map difficulty until a seed matches.
The first logged search covered 2,731 seeds at 1,214 per second, against
about 11 per second before; the saved campaign replays at about 14,000 per
second of pure work offline. The budget is 262,144 seeds and an unchanged
request continues where the last search stopped. v0.16.1 adds timing and
stamp diagnostics only. Continuation after an exhausted search has not been
exercised in game.

**Working in game: [v0.15.0 constellations per mission](CONSTELLATION_FILTER_TEST.md).**
A third dialog tab accepts base enemy constellations for each checked mission
separately, or for any one mission when none is checked. Each list shows only
what that mission can draw. Tags are predicted for every candidate mission
from its seed; hovering missions afterwards logs what the loaded preview
added. Two per-mission searches were published and eight hovered missions
agreed with the prediction inputs. The constellation the game then uses has
not been confirmed independently.

**Validated by log: [v0.13.0 viewed-planet rerolling](VIEWED_PLANET_TEST.md).**
Two remote publications were verified with the ship elsewhere. The dialog
retains its contents through temporary data waits, disabling actions until
fresh data returns; that visual fix still awaits the user's confirmation.

**Validated preview: [v0.12.2 viewed-planet filters](FACTION_FILTER_TEST.md).**
Filters populate for the planet being viewed even when the ship is elsewhere.
Remote previews explicitly disable rerolling until the ship arrives.
Incompatible mission choices are dimmed and disabled as you select filters;
hover for a reason. Checked missions remain removable. The check includes
eligible templates, category limits, slots and selected modifier rules.
Mission and modifier choices come from eligible templates on the selected
planet at the map difficulty. Modifiers cycle Any / Require / Exclude and
combine with mission requirements. Invalid selections are cleared when the
planet or difficulty changes. The v0.11.0 dialog was confirmed working in game.

**Validated in-game: [v0.11.0 mission filter dialog](DIALOG_SEARCH_TEST.md).**
Ctrl+Shift+F8 opens the restored mouse dialog with the native cursor and HUD
input blocking. Checked mission families feed the Lua seed search; existing
matches are selected without a refresh. Uses map difficulty and allows repeated
searches without restarting. Search throughput is unchanged. Modifier and
constellation filters remain future work.

**Validated in-game: [v0.10.x live Lua search](LIVE_SEARCH_TEST.md).**
The all-Lua search now publishes one matching seed, verifies the regenerated
board, and opens the matched operation using the tested native/UI selection
path. Start alone on your ship, viewing the planet it orbits at difficulty 10.
This checkpoint uses the fixed ICBM + Survey + Eradicate filter and permits one
publication per game session. The user confirmed success from both planet
overview and an already-selected operation.

**Current test: [v0.9.1 automatic backend waiting](LUA_PREDICTION_TEST.md#v091-automatic-backend-wait).**
The read-only search now pauses for temporary pending backend requests instead
of cancelling. It resumes automatically after a quiet interval and full input
revalidation. Planet 100 already produced an in-game match with v0.9.0 after
45 candidates; planet 268's logged search was cancelled after 20 candidates.

**Next test: [v0.9.0 cooperative Lua seed search](LUA_PREDICTION_TEST.md#v090-cooperative-search-checkpoint).**
After validating the displayed board, the probe searches up to 256 candidate
seeds for ICBM + Geological Survey + Eradicate on difficulty 10. Rule bytes are
cached without replacement and revalidated before accepting each candidate.
Search yields between work batches, supports cancellation and alt-tab, and
stops on context changes. It logs a match without refreshing or selecting it.
The packaged search found seed 4 / row 29 in the saved ordinary-planet context;
the offline native emulator confirmed that result. In-game search testing is pending.

**Validated in-game: [v0.8.0 independent seed prediction](LUA_PREDICTION_TEST.md#v080-independent-seed-prediction).**
Operation bases now come from campaign state and the seed, with the active
operation preserved. The packaged predictor matches 31 saved boards and a fresh
planet-100 capture without using displayed operation bases as inputs. The pure
bounded filter-search controller is implemented and tested offline; it is not
connected to the game UI or publication yet. v0.8.0 remains a read-only probe.
At seed 1764573301, planet 100 passed with 40 operation bases and 96 missions;
planet 268 passed twice with 30 bases and 72 missions. All comparison stages
passed without retries, timeouts or mismatches. Support remains limited to the
tested campaign branches.

**Previous diagnostic: v0.7.1.** The v0.7.0 in-game run loaded and verified its
signatures, but capture failed on both planets with `attempt to compare number
with nil` in the eligibility difficulty check. Saved captures still pass; the
root cause is not established. v0.7.1 adds input diagnostics and a failure stack
trace. It now passes twice on each planet at seed 373592754: planet 100 has
40 identities, templates and modifier sets plus 96 mission descriptors;
planet 268 has 30 identities, templates and modifier sets plus 72 descriptors.
All four runs passed without retries, timeouts or mismatches. This completes
the combined checkpoint for these inputs, but does not establish the earlier
failure's cause or prove it fixed.

[Combined composition scope](LUA_PREDICTION_TEST.md#v070-combined-composition-checkpoint).
Mission eligibility, category selection, and operation finalization now run
together in Lua. The combined predictor matched 2,232 mission descriptors across
31 saved boards and 96 descriptors on a fresh planet-100 capture, including
templates and modifiers. v0.7.1 also passes the planet-100 in-game check above.
It uses operation base fields as inputs, but independently generates mission
seeds, types, and levels. This read-only checkpoint does not enable seed searching.

[Validated in-game: Lua probe v0.6.5](LUA_PREDICTION_TEST.md#v065-pointer-cache-key-fix).
The root failure was reproduced: the game renders pointer values as the same
`[cdata (deleted)]` string, causing different reads to share a cache entry.
Version 0.6.5 keys reads by numeric address and size, and formats fingerprint
addresses numerically. With opaque pointer formatting, all 96 saved live levels
on planet 100, 72 on planet 268, and 2,232 saved oracle levels pass. Strict bounds
and bounded retries remain. In-game checks now pass twice on each planet for
seed 33257715: 30 operation identities and 72 levels on planet 268; 40 identities
and 96 levels on planet 100, including the special operation rows. No retries,
timeouts, mismatches, or stops occurred. This checkpoint is complete.
This verifies level selection using observed mission seeds to resolve the
unported category draw; it is not yet independent full mission prediction.

[Validated in-game: read-only Lua predictor v0.6.2](LUA_PREDICTION_TEST.md#v062-special-operation-checkpoint).
Both planet tests passed for seed 929426942: all 40 operation identities on
planet 100 (including ten special rows), and all 30 on planet 268. The loader,
build hashes, and code signatures passed. This validates the viewed-planet fix
and supported special-event input collection inside the game's Lua VM.
The v0.6.5 checkpoint also verifies the level graph and level selection in-game.

The weighted mission picker also matches 256 offline native-function cases.
The v0.7.0 combined eligibility/finalization checkpoint is ready for testing. Prediction stays
entirely inside Lua. Mission-filter searching and publication are not enabled in
this diagnostic build. The original 30-row identity check already passed in-game.

Previous dialog package: [combined mouse search v0.4.1](COMBINED_TEST.md).
It combines the native-cursor dialog and bounded search, then selects the
matched operation without selecting a mission. In-game checks confirmed an
existing match with zero reseeds and a new match after one reseed. Both preserved
the active operation and released the dialog after selection.

Version 0.4.1 removes the session call cap and lowers the minimum interval to
one second, while waiting for each stable refresh. The three-minute search
timeout and Cancel remain. This faster cadence awaits in-game validation.

For network observation, use the [Windows capture workflow](NETWORK_CAPTURE.md).
It records NIC traffic and sampled socket ownership alongside reroll log events;
it does not attach to the game or require a new addon package.

The [offline seed evaluator](OFFLINE_SEED_EVALUATOR.md) reproduced two
independent live seeds, each with 30 operations and 72 missions byte-for-byte,
using the same frozen inputs. It can search without refreshing the game.
The separate [one-shot publication test v0.5.3](SEED_PUBLICATION_TEST.md)
reads a prediction file refreshed after launch, then publishes one predicted
seed with Ctrl+Shift+F9. The first 0.5.0 attempt correctly blocked stale captured
state before writing; 0.5.1 fixes the need to repackage prediction data and lets
preflight rejection be retried. Version 0.5.2 continues work while alt-tabbed and
handles the empty owner queue with bounded native insertion. It temporarily
replaces the dialog build. Corrected prediction and seed publication have now
matched live; v0.5.3 adds the normal click's local map-selection fields to address
the missing visible operation view. The user confirmed that v0.5.3 visibly
selected the correct operation; logs confirmed both predicted digests, preserved
active-operation bytes and no mission selection. Automatic prediction/filter
integration is still pending; this remains a one-shot research build.

Earlier test: [filtered search experiment 0.3.0](FILTER_EXPERIMENT.md), with an
in-game keyboard filter dialog and a five-call session limit. It supported twelve
common mission families. This is separate from the inert Development ZIP.

Completed in-game milestone: [single native reseed experiment](ONE_SHOT.md).
Probe 0.1.1 made exactly one native call, changed the displayed missions, and
preserved the canonical active operation. Disable the diagnostic after this
test. Repeated searches, general host detection, backend acceptance and complete
filter integration remain unverified.

**Not a finished mod.** The current combined package has passed supervised
mouse-dialog, bounded-search and automatic-selection checks. The complete
legal-option catalogue, modifier/constellation integration and a native
war-table entry button remain unfinished. The Development ZIP is still an
inert core, with no button or rerolls.

## Intended behavior

Select an available planet and difficulty, click **Reroll operations**, and
choose required mission types, operation modifiers and enemy constellations.
The mod should evaluate candidate seeds inside Lua, then publish a verified seed
whose normal game-generated operation matches. Required mission types apply across a single operation:
Launch ICBM + Geological Survey permits any third mission. Extra modifiers or
tags remain unrestricted unless a future explicit exclusion filter is added.

Constellations are sets of tags on individual missions. Each checked mission
has its own rules: it must carry one of the accepted constellations and none
of the excluded ones. Without checked missions, one mission of the operation
must carry an accepted one and no mission an excluded one. Modifier filters
require all selected modifiers. An empty selection imposes no requirement.

Native generation and backend acceptance must be established before calling
results vanilla-valid. That would not establish approval under game policy.
This project presently makes neither claim.

## What works offline

- Canonical-ID filters, validated against a supplied complete option catalogue.
- Full-operation matching, with unknown data distinct from a negative result.
- Initial-batch matching, one in-flight request, paced retry after complete
  results, cancellation, context invalidation, attempt limits and timeouts.
- Bingus Shared Loader plaintext addon packaging with stable GUID.
- Matching Lua and Python decoders for complete operation mission lists, with
  two-pass consistency checks. Both were replayed against four read-only live
  captures (120 operation records) with identical mission types and seeds.
- Optional title hints from external game research files, and a comparison tool
  that distinguishes hover/status changes from operation-content changes.

The packaged entry exposes its development core as `MissionReroller` and logs
`unsupported_native_adapter`. It leaves update/shutdown untouched and performs
no memory access, native calls or network requests. The controller is not
connected to the game loop. A loader `loaded` line confirms discovery only.

## Build and test

Requires the adjacent `BingusSharedLoader` source (or `BINGUS_LOADER_ROOT`) and
LuaJIT (`HD2_LUAJIT` or the workspace tool path).

```powershell
python -B scripts/build.py
python -B tests/test_package.py
```

When this was written the output was
`releases/Mission-Reroller-Development-v0.2.0.zip`, the inert core. Since
2026-09-29 `scripts/build.py` builds the release package and
`scripts/build_core.py` the core; see the [README](../README.md) and
[scripts/README.md](../scripts/README.md). No game binaries, extracted
resources or research captures enter any package.

## Research and remaining work

- [Research status](RESEARCH.md)
- [Native adapter requirements](ADAPTER.md)
- [Constellation reference investigation](CONSTELLATION_RESEARCH.md)
- [Constellation filter test](CONSTELLATION_FILTER_TEST.md)
- [Fast seed search test](FAST_SEARCH_TEST.md)
- [City and megafactory test](CITY_SCOPE_TEST.md)
- [Native reroll investigation](NATIVE_REROLL_RESEARCH.md)
- [Complete operation layout](OPERATION_LAYOUT.md)
- [Seed lifecycle](SEED_LIFECYCLE.md)
- [In-game validation](LIVE_VALIDATION.md)

The installed binaries matched build 25480438 during research on 2026-09-28.
The workspace's older 25327279 offsets must not be assumed compatible. The
reference KnowYourConstellation checkout lives beside this repository; none of
its source or artwork is embedded or redistributed here.
