# Viewed-planet publication and stable dialog — v0.13.0

## Result, 2026-09-28 session

Remote publication passed in the logged session. With the ship at planet 268
the log shows two complete remote runs, for viewed planets 199 (seed
3209039047, row 28) and 253 (seed 3209039091, row 29). Each has
`PUBLISH_BEGIN primary_planet=268`, `PUBLISH_RETURN active_preserved=true`,
`PREDICTION_CHECK descriptors_match=true` and `PUBLICATION_STATE_VERIFIED
map_ui_row_confirmed=true mission_unselected=true`. A same-planet run on 268
passed as well. On planet 253 a search with a modifier exclusion exhausted
its 256 seeds; the same missions without that rule matched. Backend waits
paused and resumed searches without cancelling them.

Not established by that log: the existing-match path without a seed write
was not exercised, and the dialog blanking fix is visual, so it still needs
the user's confirmation.

## Test

Install `releases/Mission-Reroller-v0.13.0.zip` in place of the previous package,
Purge / Deploy, and restart. Remain alone on your ship for this supervised test.

1. View an available planet that your ship is not orbiting. Open the dialog
   with Ctrl+Shift+F8. Start should now be enabled for compatible filters.
2. Choose a modifier/mission filter not met by its current operations. Search,
   then verify that operations refresh and the matching operation opens without
   travel or selecting an individual mission.
3. Confirm the ship remains at its original planet and any active operation is
   preserved. Repeat with an existing match; that should require no seed write.
4. Leave the dialog open while idle. Brief cache/backend waits should retain
   its rows with an updating status, not flash an empty list. Start and row
   actions are disabled during these waits. Switching to another planet or
   difficulty must still remove old choices until the new catalogue is ready.

This is the existing campaign seed publication path, not an isolated modifier
edit for one planet. The shared seed can change unstarted operations on other
planets when regenerated. Active-operation bytes remain explicitly protected.
Unsupported campaign-generation branches continue to stop without publishing.

## Evidence and changes

Read-only MCP session 26252-971175453 confirmed canonical and display selection
fields [268,157], while UI+0x4ef8 was 157 and difficulty was 10. Saved native
analysis at RVA 0x12d1d40 passes both existing planet fields unchanged to
0x12d18f0, selecting the operation with mission=-1. No travel function or planet
field write has been introduced. Native refresh rebuilds its caches normally;
the verifier waits for a consistent cache of the requested viewed planet.

Publication preflight, board verification and selection confirmation now read
viewed-planet snapshots. Canonical/display planet pairs must still agree;
the requested planet must equal the viewed field and UI planet. Both planet
fields must remain unchanged through regeneration and selection. Ownership,
private-page checks, signatures, backend waiting, active-record preservation,
full predicted descriptor verification, and conditional rollback remain enabled.

The dialog independently reads UI planet/difficulty even when the guarded
snapshot is temporarily unavailable. A matching catalogue can be retained for
presentation only; it cannot authorize Start or a row action. A different UI
context cannot reuse the old rows. This addresses the empty-list rebuild caused
by transient snapshot gaps; visual confirmation is still required.

Tests cover different primary/viewed planet publication, unexpected primary
planet change rollback, modifier checks, successful selection confirmation,
remote dialog Start, transient-gap row retention with actions disabled,
recovery and mismatched UI rejection. The dialog harness flushes JIT traces
after replacing warmed test dependencies via debug.setupvalue; production does
not swap those dependencies. Eight repeated harness runs passed after that fix.
Remote in-game publication is the next human validation step.
