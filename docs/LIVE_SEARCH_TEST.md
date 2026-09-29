# Live Lua search, publication and selection — v0.10.1

The user subsequently confirmed that v0.10.1 works from planet overview as
well. Both overview and selected-operation entry points are now visually
validated. The v0.11.0 dialog integration is described in DIALOG_SEARCH_TEST.md.

Package: `releases/Mission-Reroller-Live-Search-v0.10.1.zip`.
This connects the verified Lua predictor and bounded search to the previously
tested v0.5.3 seed-publication and map-selection path. No companion process,
candidate file, offline emulator or captured game bytes are needed at runtime.

## Human test

### v0.10.0 selected-operation success

The user confirmed visible refresh and automatic selection in session
22836-967517250, starting with an operation already selected. Logs show seed
1725057555 -> 1725057612, 57 candidates, descriptor verification, row 29,
preserved active operation, and confirmed processed map UI. This validates
the all-Lua search/publication/selection integration for that starting state.
The user reports failure from planet overview. A successful-state read-only
capture is saved under ignored artifacts/ui-selected-22836.json; comparison
with the user's overview is saved in artifacts/ui-overview-22836.json. Both
captures have UI planet 268 and difficulty 10; overview has operation row -1
in UI and campaign, whereas selected state has row 29. Replaying both through
the real UI selection adapter passes. The observed overview already satisfies
the existing guard; the earlier failure has not been reproduced in this state.
The next live attempt should start from this overview with v0.10.1 diagnostics.
Do not infer that the user
closed the map from the earlier planet sentinel alone, or remove the guard
without establishing the alternate UI state.

v0.10.1 improves publication diagnostics only. The v0.10.0 log found a matching
seed after 57 candidates but blocked before any write on a combined UI guard.
Read-only live inspection then showed UI planet -1 (none), previous planet 268,
and difficulty 10. Saved native deselection code confirms this field pattern.
This does not establish whether the planet was already closed when the match
was found; the next attempt logs both actual UI values separately. No planet
guard was relaxed. A closed-map regression test passes without writes or
consuming the publication allowance. Search slices reached 94–110 ms in this
session; frame-time optimization remains outstanding.

1. Replace the previous Mission Reroller probe with this package. Keep Bingus
   Shared Loader winning startup, Purge / Deploy, and restart the game.
2. Be alone on your ship. Open the **planet your ship is orbiting** and display
   **difficulty 10** on the galactic map. Leave the map at the planet overview.
3. Press **Ctrl+Shift+F9 once**. The fixed filter is Launch ICBM + Geological
   Survey + Eradicate. Wait for the search and refresh; allow up to five minutes
   including bounded backend waits. Alt-tab is supported.
4. On success the operations refresh, then the matched operation's mission view
   opens automatically. No individual mission is selected. Check that all three
   required mission families appear and report the visible result.

The shortcut cancels an active search or pending publication. This supervised
build allows one attempted seed publication per game session; restart to test
another publication. A preflight rejection before any publication does not use
that allowance. The older filter dialog is not included in this checkpoint.
Other viewed planets remain available to the read-only predictor, but publication
requires ship, viewed, canonical and map-UI planets to agree. Difficulty must
already be 10; the mod does not change that setting on the user's behalf.

## Behavior and guards

The v0.9.1 backend wait behavior remains enabled. That change passed local tests
but is not yet confirmed in-game; the user explicitly requested moving on with
it included rather than running another read-only checkpoint.

After all baseline checks pass, search starts from campaign seed + 1 with a
256-candidate limit. Immutable rule bytes are revalidated before accepting each
candidate. Context changes cancel the search. The canonical active operation is
preserved. Current campaign support restrictions remain in effect; unsupported
defense/invasion and unresolved conditional generation paths stop cleanly.

A match is handed to the one-shot publication transaction. Preflight requires
the original snapshot, local sole source owner, matching canonical/viewed/ship
planet, displayed difficulty and known module/function signatures. Writes use
the game's own process and only checked existing private read/write pages.
The seed write and owner notification reuse the tested native path.

The game regenerates the board. Verification compares every operation's
ID, seed, difficulty, category, faction, explicit template hash, chosen template,
modifier list and each mission's type, seed and level. This is full prediction
descriptor verification, not a byte-for-byte comparison of unpredicted padding
or other fields. Active-operation bytes must remain unchanged.

On prediction mismatch, timeout, cancellation or partial-write failure, the
transaction attempts to restore the prior seed. Restoration refuses to
overwrite an external seed change, changed owner or changed active operation.
After successful board verification the transaction commits. The selection
adapter updates the two normal map-click UI fields and invokes the normal
operation selector. Both native highlighted-operation state and processed map-UI
row are checked; the mission remains unselected. If selection fails after the
board was verified, the verified seed remains installed and a conditional UI
restore is attempted, allowing manual selection of the matching operation.

## Validation before packaging

- The actual live-search package still matches 32 native-oracle boards with
  2,304 mission descriptors, and its cooperative search finds native-confirmed
  seed 4 / row 29 in the saved ordinary-planet context.
- Publication tests cover successful verify/select, difficulty preflight,
  one-publication limit, prediction mismatch rollback, cancellation,
  partial-write recovery and refusal to overwrite an external seed.
- Existing transaction tests cover timeout, context change, preflight rejection
  and restoration failure. UI tests cover planet/difficulty guards, exact write
  fields, processed-state confirmation and conditional restoration.
- Read-only search and predictor regression tests continue to pass. The package
  excludes fixtures and external candidate files and contains no external-process
  attachment, code patching or allocation APIs.

Expected log sequence: baseline PASS records, `LUA_SEARCH_STARTED`, optional
`LUA_SEARCH_WAIT` / `LUA_SEARCH_RESUMED`, `LUA_SEARCH_MATCH`, `PUBLISH_BEGIN`,
`PUBLISH_RETURN`, `PREDICTION_CHECK descriptors_match=true`,
`PREDICTION_VERIFIED`, then `PUBLICATION_STATE_VERIFIED`. Preserve any
`PUBLICATION_BLOCKED`, `RESTORE_SEED`, `RESTORE_FAILED` or `STOPPED` diagnostics.
Successful logs still require the user's visible confirmation of selection.
