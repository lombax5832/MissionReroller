# Seed solver in the search: in-game test

The search now takes its candidate seeds from the seed solver when it can
seed the request, instead of trying seeds one after another
([SEED_SOLVER_RESEARCH.md](SEED_SOLVER_RESEARCH.md), **In the search**).
Every candidate is still predicted and checked by the same matcher, and a
match is published and selected as before, so what a player sees is the
same except for speed: a rare request should match in about a second where
it used to take tens of seconds or the 180 s limit. Requests the solver
cannot seed (no mission checked, and a few others) search as before.

## Result, 2026-10-04

Steps 1 to 3, 5 and 6 (then the fallback) passed on planet 268, difficulty
6: four searches matched with `mode=solver` within 7 candidates in 0.42 to
1.13 s, each `PUBLICATION_STATE_VERIFIED`, the day search with
`DAYNIGHT_VERIFIED holds=true` (`daynight_ids=5/35`). The city search on
planet 100 region 2 logged `SEED_SOLVER_OFF reason=city scope` and matched
by scan. `max_slice_ms` was 22 to 27 for the solver and the scan alike.
Cities are solved since; step 7 now checks that, step 8 the fallback, and
step 4 the estimate shown while editing.

## Setup

Build the development package from the `worktree-seed-solver-prototype`
branch: `python -B scripts/build.py` writes
`releases/Operation-Reroller-Dev-v0.33.2.zip`. Import it and the loader into
Arsenal or HD2MM, **disable the published Operation Reroller** (both share
the module, global and log), keep the loader as the winning startup
override, Purge / Deploy, launch. Read `BingusSharedLoader.log` and
`MissionRerollerExperiment.log` from
`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs`. Stay alone on your ship.

A search writes `SEED_SOLVER ...` or `SEED_SOLVER_OFF ...` after
`LUA_SEARCH_STARTED`. Its `LUA_SEARCH_MATCH` line ends in
`mode=solver walk_steps=<n>` when the solver found the seed, or
`mode=scan` when the search fell back to seeds in order after the solver
ran out (not expected). Send the whole log after the session.

## Steps

1. **Start.** Reach the ship and open the galactic map.
   - Pass: `mods/ipodalexei/mission_reroller_experiment: loaded`,
     `Mission Reroller 0.33.2 docked dialog` and
     `build=25480438 hashes=verified ... verified`.
   - Fail: any `STOPPED:` line.
2. **One mission.** View a planet with operations at difficulty 10, press
   F7, check one mission type the dialog offers (Launch ICBM if offered)
   and press REROLL OPERATIONS.
   - Pass: `SEED_SOLVER paths=<n> rows=<r> setup_ms=<ms>`, then
     `LUA_SEARCH_MATCH seed=<s> row=<r> attempts=<a> ... mode=solver
     walk_steps=<n> ...`, `PUBLICATION_STATE_VERIFIED`, and the operation
     opens with the mission.
   - Fail: `SEED_SOLVER_OFF`, `LUA_SEARCH_FAILED`, or an opened operation
     without the mission.
3. **A rare request.** Same planet and difficulty. Check three mission
   types, then in ENEMY FORCES accept one force for the first mission, and
   in SIDE OBJECTIVES require one objective for the second. Press REROLL
   OPERATIONS.
   - Pass: `SEED_SOLVER paths=<n> ...`, `LUA_SEARCH_MATCH_CONSTELLATIONS`
     and `LUA_SEARCH_MATCH_OBJECTIVES` lines that hold the rules,
     `LUA_SEARCH_MATCH ... mode=solver` with `elapsed_s=` a few seconds at
     most, `PUBLICATION_STATE_VERIFIED`; the opened operation's briefing
     shows the force and the objective.
   - Fail: `LUA_SEARCH_EXHAUSTED` or `Search time limit reached` with
     `mode=solver` (send the `SEED_SOLVER` line and the progress lines),
     or a briefing that contradicts the rules.
   - Also note: the request may be impossible (`SEED_SOLVER_OFF reason=no
     draw path`): pick other rules.
   - **Estimate.** While it searches, the line under the progress strip
     reads `<m>:<ss> - 1 IN <n> SEEDS MATCH - ABOUT ...`, the clock counting
     the seconds searched (waits for the game's backend left out, as the
     3 min limit counts them); a scanned search reads `<m>:<ss> - <n> OF
     1,000,000 SEEDS SEARCHED`. The line fits inside the panel. Note it and compare with
     `elapsed_s=`: the estimate is right within a few times either way.
     The `SEED_SOLVER` line's `match=1/<n> expected_steps=<n>` and the
     match line's `walk_steps=` give the numbers behind it. The text fits
     on one line inside the panel.
4. **Estimate while editing.** Before pressing REROLL in step 3, watch the
   line under the button as you check missions and rules.
   - Pass: it reads `WORKING OUT HOW STRICT THIS IS` for a moment (well
     under a second), then `1 IN <n> SEEDS MATCH - EXPECT ...`, and changes
     with each edit; the map stays smooth while you edit. The log has an
     `ESTIMATE match=1/<n> seconds=<s>` line per change, and the search's
     `SEED_SOLVER ... match=1/<n>` agrees with the last one.
   - Fail: the line stays on `WORKING OUT` for seconds, a hitch on each
     click, or `ESTIMATE_BLOCKED`.
5. **Frame rate.** During steps 2 and 3 the game keeps running smoothly
   (the map can be panned while it searches).
   - Pass: `max_slice_ms=` in each `LUA_SEARCH_MATCH` line about what a
     scanned search shows (22 to 27 on 2026-10-04) and `setup_ms=` on the `SEED_SOLVER` line under a few hundred ms (it
     is spread over frames).
   - Fail: a visible hitch when the search starts, or `max_slice_ms=`
     above 40.
6. **Night.** Choose NIGHT on the TIME OF DAY header, check two mission
   types and press REROLL OPERATIONS.
   - Pass: `DAYNIGHT_SEARCH side=night ...`, `SEED_SOLVER ...
     daynight_ids=<valid>/<total>` with valid above 0, `DAYNIGHT_MATCH ...
     holds=true`, `LUA_SEARCH_MATCH ... mode=solver`, `DAYNIGHT_VERIFIED
     row=<r> holds=true` and `PUBLICATION_STATE_VERIFIED`. Hover each
     mission: SEST shows night (before 06:00 or after 18:00).
   - Also fine: `SEED_SOLVER_OFF reason=no operation passes Day / Night`:
     no operation of that difficulty can be at night now. The dialog said
     `No seed gives this now` before the search unless a city has an
     operation at that difficulty; the scan looks for the city's and runs
     to its limit otherwise. Try DAY, or another planet.
7. **City.** With the cursor on a city or megafactory marker, open the
   dialog (it reads `This city or megafactory only`), check two of its
   missions, choose DAY or NIGHT and press REROLL OPERATIONS.
   - Pass: `SEED_SOLVER paths=<n> rows=1 ...`, `LUA_SEARCH_MATCH ...
     row=<30 + region*10 + difficulty - 1> ... mode=solver`, then
     `DAYNIGHT_VERIFIED holds=true` and `PUBLICATION_STATE_VERIFIED`; the
     city's operation opens on that side. The match comes on the first
     candidate or nearly (`after 1 candidates`); before the audit fixes
     about 4 in 10 candidates failed here.
   - Also fine: `SEED_SOLVER_OFF reason=no draw path`: none of the levels
     the city's missions can take is on that side now. The scan then runs
     to its limit without a match; try the other side.
   - Fail: `SEED_SOLVER_OFF` with any other reason, or a match outside the
     city.
8. **Fallback.** Check no mission, exclude one in its section, and press
   REROLL OPERATIONS.
   - Pass: `SEED_SOLVER_OFF reason=no required mission ...; scanning seeds
     in order`, then the usual match lines without `mode=`.
   - Fail: any error after `SEED_SOLVER_OFF`.

## Log lines

Pass: `SEED_SOLVER paths=` for steps 2, 3, 6 and 7; `ESTIMATE` lines for
step 4; `mode=solver` on the `LUA_SEARCH_MATCH` lines; `SEED_SOLVER_OFF
reason=no required mission` for step 8;
`PUBLICATION_STATE_VERIFIED` after every match.

Fail, and send the log: `SEED_SOLVER_OFF reason=` with a Lua error or
`Prediction input budget exceeded` for an ordinary request,
`Search and complete predictions differ`, `Prediction inputs changed;
restart search` repeating, or any `STOPPED:` line.
