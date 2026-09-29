# Combined mouse search and automatic operation selection — 0.4.1

This replaces the separate search and mouse previews with a single addon.
The user requested automatically selecting a matched operation. The intended
result is an operation highlighted in the map, with no mission selected or
launched and the current active operation record preserved.

## First test: zero reseeds

1. Disable earlier Mission Reroller packages, including Mouse Test and Input
   Inventory. Import `Mission-Reroller-v0.4.1.zip`, keep Bingus Shared Loader as
   the winning startup override, Purge / Deploy and relaunch.
2. Alone on your own ship, select a planet. Inspect an operation and note one
   or two mission types already present together. Leave the game on its map.
3. Open with Ctrl+Shift+F8. Set the dialog difficulty to the same difficulty
   you inspected, and check those mission requirements. Wait for readiness.
4. Click **Reroll Operations**. Existing operations are checked first, so this
   should use zero reseeds. A matching operation should become selected and
   the dialog should close automatically. The mission remains unselected.
5. Report whether the correct operation is visibly selected and whether the
   ordinary cursor/map controls work. Do not launch a mission during this test.

Log: `MissionRerollerExperiment.log`. The expected final evidence is
`SELECTION_CONFIRMED ... mission_unselected=true active_preserved=true` without
any `RESEED` line. If several operations satisfy the filter, the first matching
row may be selected rather than the particular example you inspected.

## Confirmed in-game result — 2026-09-28

On build 25480438, planet 268 at difficulty 10, the user tested both paths:

- Spread Democracy already existed in the selected operation. The current
  batch matched row 27, operation ID 23, with zero reseeds. Reselecting that
  operation produced no visible change, as expected.
- Launch ICBM was absent from the current batch. One reseed produced a match
  at row 27, operation ID 13, which the game automatically selected.

Both attempts logged `SELECTION_CONFIRMED` with `mission_unselected=true`
and `active_preserved=true`, followed by modal release. The user confirmed
the refreshed operation was visibly selected. These checks validate the two
tested single-mission filters; multi-requirement live selection and broader
session conditions remain separate checks.

## Search behavior

The same twelve common mission families are available; they are not a complete
legal-option catalogue. Modifiers and constellation filters remain unavailable.
All checked families must be present in the same operation. The difficulty
control filters records; it does not directly change the game's difficulty
selector. Use the same difficulty in both interfaces for this test.

The dialog uses native cursor visibility and the mouse-focus gate confirmed by
the prior UI tests. Start/Cancel, +/- difficulty, Clear and Close are clickable.
Filters and difficulty are disabled during a search/selection attempt. Close
cancels further work, consumes the closing release and restores native input.
Filters survive reopening. Version 0.4.1 removes the five-call session cap at
the user's request and reduces the minimum call interval to one second. Calls
still require completed publication and four stable quarter-second samples;
one second is a lower bound, not a guaranteed rate. Pacing survives cancelling
and restarting a search. The counter reports total calls in this process.
The 30-second refresh timeout and three-minute search limit remain. A new
search can be started after the time limit without relaunching the game.
Selection has a separate five-second
confirmation timeout and is never retried automatically.

Next live check: select two mission types and verify that searching continues
beyond five total calls when needed, then selects an operation containing both.
Also check Cancel stops further rerolls. The faster cadence has passed offline
tests but still needs this in-game check. The successes recorded above used
version 0.4.0 with the earlier limits.

## Native selection boundary

Saved-image analysis recovered operation-only wrapper RVA **0x12d1d40** with
Win64 arguments `(unused, uint32 row)`. It checks canonical board owner
`board+0x1f8078` against `session+0xb398`, then calls common selection routine
0x12d18f0 with the current planet values, matched row, **mission=-1**, and zero
remaining flags. This bypasses the branch that copies an operation into the
active record or requests mission activation. The common routine publishes
the selection through event dispatcher 0xb98cc0 and normal replication path
0xbe1800. Listener 0x12db270 updates the displayed selection and native UI.

The adapter checks module hashes and selection byte signatures, current row
identity/seed/difficulty, unchanged planet and publication state, nonzero local
owner equality, and private writable canonical/display selection pages. It
checks active-operation bytes and mission=-1 immediately after the call, then
waits for a consistent snapshot naming the matched row before closing.
It never writes guessed row fields, launches a mission, or selects a mission.

This is a recovered internal routine, not a supported public API. The two live
checks above confirmed selection in the tested session. Normal native selection
publishes selection state; it is not a purely local visual effect. Continue
testing alone on your own ship. No backend-acceptance or game-policy claim is
made. Broader session conditions remain unverified.

Raw research is in ignored `tools/ghidra-projects/reroller_select*.txt` and
`reroller_selection*.txt`. Release content remains one plaintext addon with
no dumps/extracted assets. `python -B tests/test_combined.py` tests packaging,
the assembled mouse-start/match/select/close flow with a substituted native
selector, stale identities, selection timeouts, search limits, modal release,
cursor restoration and layout. No native game call is executed by those tests.
