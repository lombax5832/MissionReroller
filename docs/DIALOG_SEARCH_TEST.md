# Mission dialog with Lua seed search — v0.11.0

Package: `releases/Mission-Reroller-v0.11.0.zip`. Replace the previous experiment
package; do not enable both. Keep Bingus Shared Loader winning startup, Purge /
Deploy, and restart the game. The addon module and package GUID are unchanged.

## In-game test

1. Alone on your ship, open the planet it orbits, with either its overview or
   an operation selected. Set the desired map difficulty before opening filters.
2. Press **Ctrl+Shift+F8**. Check mouse visibility, checkbox clicks, and that
   the game UI beneath the dialog does not respond to clicks.
3. Choose mission families, then click **REROLL OPERATIONS**. Every checked
   family must occur in one operation; other mission slots are unrestricted.
   An existing matching operation is selected without refreshing the seed.
4. If a new seed is needed, the local Lua predictor searches up to 256 candidates,
   publishes one match, verifies the regenerated board and opens its operation.
   The dialog closes on confirmed selection. No individual mission is selected.
5. Reopen with the same shortcut and try another filter, without restarting.
   Also test cancelling and reopening. Alt-tab hides/releases the dialog but
   allows work to continue; the shortcut reopens it after returning.

The map difficulty appears as MAP D in the dialog; change it on the map, not
during a search. Empty filters and more families than available mission slots
are rejected. The twelve restored mission families are the previous dialog's
catalogue; faction-specific impossibilities may exhaust the search. Modifier
and constellation filters are not yet connected. No match within 256 candidates
leaves the board unchanged. The same unchanged seed/filter retries the same range.

## Implementation and validation

The previously confirmed v0.10.x predictor, publication and UI-selection path
is retained. Dialog requests provide a copied mission filter and map difficulty
to both search and publication verification. Current operations are checked
first. Each search takes a fresh guarded snapshot; completed publications no
longer impose a restart requirement in the dialog build. Read-only checkpoint
builds and the old one-publication live test retain their defaults.

The prior window mouse gate, native cursor and click-release router are reused.
Closing/cancelling explicitly stops the pending work; losing OS focus only
releases modal input and clears the rendering. Shutdown/errors restore modal
ownership and pending publication using the established cleanup path.

Search quantum, candidate budget and timing are unchanged: the user accepts
the observed frame-time dips in exchange for search throughput.

Tests: `tests/test_dialog.py`, `tests/test_live_search.py`,
`tests/test_search_probe.py`, `tests/test_identity_probe.py`. These exercise
real dialog/router logic with mocked OS/render boundaries, custom filter
propagation and copying, existing matches without seed writes, repeated
publication, guarded rollback, focus loss, cancellation and reopen, as well
as archive contents. In-game visual confirmation of this integration is pending.
