# Seed solver in the search: in-game test

The search now takes its candidate seeds from the seed solver when it can
seed the request, instead of trying seeds one after another
([SEED_SOLVER_RESEARCH.md](SEED_SOLVER_RESEARCH.md), **In the search**).
Every candidate is still predicted and checked by the same matcher, and a
match is published and selected as before, so what a player sees is the
same except for speed: a rare request should match in about a second where
it used to take tens of seconds or the 180 s limit. Requests the solver
cannot seed (a city, no mission checked, and a few others) search as before.

Not yet run.

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
4. **Frame rate.** During steps 2 and 3 the game keeps running smoothly
   (the map can be panned while it searches).
   - Pass: `max_slice_ms=` in each `LUA_SEARCH_MATCH` line around 16 to 20
     and `setup_ms=` on the `SEED_SOLVER` line under a few hundred ms (it
     is spread over frames).
   - Fail: a visible hitch when the search starts, or `max_slice_ms=`
     above 40.
5. **Night.** Choose NIGHT on the TIME OF DAY header, check two mission
   types and press REROLL OPERATIONS.
   - Pass: `DAYNIGHT_SEARCH side=night ...`, `SEED_SOLVER ...
     daynight_ids=<valid>/<total>` with valid above 0, `DAYNIGHT_MATCH ...
     holds=true`, `LUA_SEARCH_MATCH ... mode=solver`, `DAYNIGHT_VERIFIED
     row=<r> holds=true` and `PUBLICATION_STATE_VERIFIED`. Hover each
     mission: SEST shows night (before 06:00 or after 18:00).
   - Also fine: `daynight_ids=0/<total>`: no operation of that difficulty
     can be at night now; the search runs to its limit without a match.
     Try DAY, or another planet.
6. **Fallback.** With the cursor on a city or megafactory marker, open the
   dialog (it reads `This city or megafactory only`), check a mission and
   press REROLL OPERATIONS.
   - Pass: `SEED_SOLVER_OFF reason=city scope ...; scanning seeds in order`,
     then the usual match lines without `mode=`.
   - Fail: any error after `SEED_SOLVER_OFF`.

## Log lines

Pass: `SEED_SOLVER paths=` for steps 2, 3 and 5; `mode=solver` on their
`LUA_SEARCH_MATCH` lines; `SEED_SOLVER_OFF reason=city scope` for step 6;
`PUBLICATION_STATE_VERIFIED` after every match.

Fail, and send the log: `SEED_SOLVER_OFF reason=` with a Lua error or
`Prediction input budget exceeded` for an ordinary request,
`Search and complete predictions differ`, `Prediction inputs changed;
restart search` repeating, or any `STOPPED:` line.
