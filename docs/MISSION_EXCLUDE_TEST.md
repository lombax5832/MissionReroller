# Excluded missions

## Status

**Validated in game on 2026-10-01** by the user, who confirmed exclusions
work with conflicting missions disabled (commit 3d115d5). The log kept
from the last session (`Mission Reroller 0.28.0 docked dialog`, loader
line `mods/ipodalexei/mission_reroller_experiment: loaded`) holds only
required-mission searches, so no `LUA_SEARCH_EXCLUDED_MISSIONS` line was
captured; the exclusion run's log was overwritten by a later launch.

## What changed

A mission row in the Missions section cycles ANY, REQUIRED, EXCLUDED, like a
modifier row. An excluded mission family takes no slot; the matched operation
must contain no mission of that family, whatever its constellations.

- `src/filter_request.lua` keeps `excluded` beside `selected` and sends it as
  `request.excluded`. A click on an unchecked row requires the mission; a
  row that cannot join the required ones is disabled, as before, and
  ignores clicks. A click on a required row excludes it, or clears it when
  exclusion is impossible. A click on an excluded row clears it. The summary lists exclusions as `not <mission>`.
- `src/filter_catalogue.lua` validation refuses an excluded mission the
  catalogue does not offer, one that is also required, and a value other
  than `true`. Each exclusion counts as a rule, so exclusions alone are a
  valid request. `possible` refuses excluding every mission offered here
  (`Every mission here is excluded`) and passes the exclusions to the
  compatibility check.
- `src/mission_compatibility.lua` accepts a request only when some reachable
  mission mask covers the required families and shares none with the
  excluded ones (`C.disjoint`). Excluding a mission every reachable
  operation contains is therefore refused.
- `src/seed_search.lua` validates and copies `options.excluded`;
  `src/search_session.lua` `S.find` rejects an operation holding any
  excluded family. The search runtime passes the exclusions to the existing
  board check, the seed job, the complete-board confirmation and the
  pre-publication recheck, and includes them in the resume key.

## In-game test

Use any planet at difficulty 4 or above.

1. Open the dialog. In Missions, click a mission the board shows (call it
   A) twice: the row turns red with a red dash in its box, the header summary
   reads `NOT A`, and REROLL OPERATIONS is enabled.
2. Start. The board's operations change, and the operation that opens holds
   no mission A.
3. Click A once more to clear it; require a different mission B and exclude
   A. Start. The opened operation holds B and no A.
4. On a planet where one mission is in every operation (check by excluding
   it: the click skips EXCLUDED and the row returns to ANY), confirm no
   search can start with it excluded.

## Log lines

Pass:

- `LUA_SEARCH_EXCLUDED_MISSIONS <A>` before `LUA_SEARCH_STARTED`, naming
  every excluded mission.
- `LUA_SEARCH_MATCH ... missions=<native>/<seed>/level<n>,...` where no
  native type belongs to A, then the usual publication and selection lines;
  or `EXISTING_MATCH` when the board already had an operation without A.

Fail:

- A match whose opened operation contains A.
- `FILTER_BLOCKED Excluded mission is unavailable on this planet/difficulty`
  or `FILTER_BLOCKED A mission cannot be both required and excluded` after a
  start the dialog allowed.
- `Predicted filter no longer matches` on every attempt.
