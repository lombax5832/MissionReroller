# One-shot winning-seed publication test — 0.5.3

This is a supervised research build, not the finished fast-search UI. It replaces
the usual reroller entry using the same module and GUID. The normal filter dialog
is absent from this package. The offline emulator is not included or run in-game.

## Human test

1. Exit the game. Replace the 0.4.1 reroller with
   `releases/Mission-Reroller-Seed-Test-v0.5.3.zip` in Arsenal/HD2MM; do not enable
   both versions. Keep Bingus Shared Loader as the winning startup override.
   Purge/deploy and launch normally.
2. Be alone on your ship. Open the same planet used in the frozen capture
   (internal planet 268), at difficulty 10. Keep the existing active operation;
   do not start or abandon missions during this test.
3. Tell the agent the game is ready and keep the map open. The agent must capture
   and validate this launch's state, then update the candidate data file. No
   additional restart or deployment is needed for data updates.
4. After the agent confirms the candidate is refreshed, wait ten seconds for
   stable data, then press **Ctrl+Shift+F9** once and release.
   Keep the map open. You may alt-tab after pressing the shortcut; progress
   continues while unfocused. There is no filter dialog in this build.
5. Expect one refresh followed by automatic operation selection, containing
   **Geological Survey + Launch ICBM + Eradicate**. No mission should be selected.
   Report what appears; the agent will inspect the logs and live descriptors.

The candidate is seed 569798162, operation row 28, operation seed 1055045283.
It has not yet been published or verified live. If nothing happens, leave the
map open for log inspection rather than repeatedly pressing the shortcut.
Each launch permits only one publication attempt. Rejected preflight checks do
not consume this attempt: update the candidate file and press the shortcut again.
A new launch must not be
used to bypass a reported guard failure without investigating it.

## Publication contract

The in-process adapter writes four bytes at canonical board+0x78e84 using
WriteProcessMemory on GetCurrentProcess. VirtualQuery must identify the existing
target page as committed private PAGE_READWRITE. No module data or code is written.
It then calls the signature-checked owner dirty setter at game.dll RVA 0x12d57e0
with `(board,2)`. This preserves the game's normal refresh path while avoiding
the random seed choice in 0x12d5670 and any shared-RNG mutation.

Preflight retains the existing binary hashes, signatures, map/ready-state,
pending-request and active-record guards. It additionally requires the local
selection owner to equal the single source owner. The destination queue may be
empty: when the source is absent, its next slot and count field must be existing
private writable memory, and the resulting count must remain at most five.
The game's setter performs the bounded insertion. These checks supplement
the human solo-ship requirement; they do not establish multiplayer support.

The candidate is read on each shortcut press from the local workspace file
`artifacts/seed-publication-candidate.txt`. It is parsed as bounded numeric fields
and SHA256 digests, never executed as Lua. The build embeds only this data-file
path, not a prediction tied to the deployment session. The baseline seed and full
operation/mission digests must match the live board before writing.

The captured active-record SHA256 must match before writing. Campaign conditions
may change across deployment/restart; the prototype therefore checks every byte
of every valid generated operation record and every populated mission record
against predicted SHA256 digests before selecting anything. Valid operation
records are prefixed by their uint32 row indices before hashing. Invalid unused
rows and unused mission capacity are excluded. There are no embedded captured
code/data pages or raw descriptor buffers in the ZIP.

A verified board is committed, then the already-researched native selection path
highlights row 28 without selecting a mission. A selection failure after commit
does not undo a correctly verified board. Final selection confirmation is bounded
to five seconds. Full publication waiting is bounded to thirty seconds.

Before commit, mismatch, timeout, shutdown or a caught error requests
restoration of the previous canonical seed and marks it dirty again. Restoration
rechecks identity, ownership, private pages and unchanged active record. If a
different writer has installed a third seed or ownership changed, restoration
refuses to overwrite it and logs RESTORE_FAILED. A restoration log confirms the
canonical write and refresh request, not that the later UI refresh completed.

## Evidence and commands

MissionRerollerExperiment.log records PUBLISH_BEGIN, PREDICTION_CHECK,
PREDICTION_VERIFIED and PUBLICATION_TEST_PASSED, or STOPPED / RESTORE_SEED /
RESTORE_FAILED. BingusSharedLoader.log must also show the module loaded.
PUBLICATION_BLOCKED indicates a preflight/data-file rejection with no seed write;
the mod remains available to retry after the file is refreshed.

```
python -B tests/test_seed_test.py
python -B tests/test_combined.py
python -B scripts/build_seed_test.py artifacts/seed-emulator/current
python -B scripts/refresh_seed_candidate.py artifacts/seed-emulator/current <live-capture.json> <new-fixture-directory>
```

The build requires successful reference and independent-seed validations. It
derives only scalar candidate metadata and comparison digests from the ignored
fixture. Synthetic tests cover one-shot success, mismatch, timeout, context
changes, preflight failure, partial publication recovery, stale restore refusal,
actual adapter write/notify ordering, Windows SHA256, wrapper return values,
duplicate entry guarding and archive contents. They cannot substitute for the
first in-game publication test above.

## First test diagnosis

The 0.5.0 loader and shortcut worked, but preflight rejected the active-record
hash before any write. After relaunch, active bytes at offsets 48, 49 and 53
differed from the frozen capture. Their exact semantics remain unconfirmed;
they were not ignored or masked. This exposed a deployment flaw: a prediction
compiled before a required restart can already be stale when tested.

Version 0.5.1 separates prediction data from deployed code and permits safe
preflight retries. A real-tick regression test blocks stale data, reloads a new
manifest and publishes once without reloading the entry. A read-only capture of
session 21648-909823875, seed 1105479219 was replayed using a separate fixture
with explicit seed/active-record overlays on the old frozen inputs. All 30
operations and 72 missions matched exactly. The original fixture is unchanged;
overlay provenance is retained. The winning seed still produced the intended
operation. Publication itself remains awaiting a live test.

Version 0.5.2 removes focus-loss cancellation at the user's request. Shortcut
activation requires game focus, but an armed attempt, refresh verification and
selection continue in the background. Tests cover losing focus both before and
after publication and successful background verification. The ten-second stable
baseline requirement remains. An empty destination owner queue was also observed
live; the former existing-owner-only check now permits the already-researched
bounded native insertion, with tests for empty, full and existing-owner cases.

## Publication observed; predictor corrected

Session 30908-910857906 published seed 569798162 from 701039216 and preserved
the canonical active operation. The runtime rejected the predicted operation
digest and restored seed 701039216, without attempting selection. The actual
mission digest already matched. Read-only inspection after restoration found
the canonical active record unchanged but the campaign snapshot different at
active-record offsets 48, 49 and 53. The snapshot is the generator input; it
must not be replaced by the canonical record merely because their seeds agree.

The offline refresh tool now preserves these as separate inputs. For a pending
publication, `--publication-reference artifacts/seed-emulator/restore-30908.json`
supplies the exact observed post-refresh snapshot only when all 92 canonical
active bytes match that reference. It does not mask fields or weaken the live
digest check. The baseline replay remains separate and must match the current
live board exactly before a candidate file is written.

The corrected candidate matched both hashes logged during publication:

- Operations: `e523de83653ee79fd012d63e081d1d1c9ddd2fcb0624f537c728dd85b9e770ac`
- Missions: `a9f2c6208f0dc704286ab51fa8c055ffb38203982db1f8b83bfcb7d35d4b5778`

Evidence is in ignored `artifacts/seed-emulator/projected-30908/` including
`publication-digest-validation.json`. Five context regression tests pass,
including canonical-vs-snapshot manifest guarding. The seed-runtime tests pass.
This verifies the prediction against the logged live result, not selection.

Next HITL: relaunch the existing 0.5.2 build to reset its consumed one-attempt
limit, open the same planet at difficulty 10 while alone on ship, and report
ready. Refresh the candidate for that launch using the publication reference
above before the user presses Ctrl+Shift+F9. No repackaging or reinstall is
required. In-process automatic prediction remains a separate implementation
milestone after successful publication/selection validation.

## Corrected publication passed; visual selection unresolved

Session 20888-911370843 published seed 569798162 from 4068588566. Both live
digests matched the corrected prediction, and the user saw the matching operation.
The native selection call returned with canonical row 28 and mission -1;
the displayed snapshot confirmed the same. Subsequent read-only inspection still
showed row 28 in both copies, with the expected operation seed 1055045283.

However, the user reported that the operation was not visibly selected. Therefore
the 0.5.2 log label PUBLICATION_TEST_PASSED is too broad: it establishes record
verification and internal selection state, not a visible map transition. Do not
report automatic UI selection as validated from that label. The remaining
investigation must compare map behavior before and after a normal operation
click, including whether background completion affects the visible response.
No additional reseed is needed to investigate this; the correct operation exists.

## Map UI selection test — 0.5.3

Clean operation-open/overview captures in session 20888-911370843 found local UI
operation rows at UI manager+0x4f00 and +0x4f0c, with corresponding processed
state at +0x4f98 and +0x4fa4. The manager pointer is game+0x3326aa0. The previous
small capture ended at +0x4eff, just before these fields. Broad captures are
under ignored `ui-clicked-20888/` and `ui-overview-20888/`.

Saved-image research found that a normal click writes selected row and clears
the adjacent hover field before calling the already-used campaign selector.
The Ghidra project's current image base/function positions differ from earlier
saved research, so its addresses were not adopted directly. Read-only live code
capture and offline disassembly established this build's actual sequence:

- RVA 0x148c032 forms UI manager+0x4ef8 and saves it in a local slot.
- RVA 0x148c33e retrieves that pointer into RBX.
- RVA 0x148c348 writes the row to [RBX+8], then -1 to [RBX+0xc].
- RVA 0x148c353 calls campaign selector 0x12d1d40.

The new adapter mirrors those two local stores as one eight-byte in-process
WriteProcessMemory operation at UI+0x4f00, after checking the click-site signature,
private writable page, UI planet and UI difficulty. It then uses the existing
campaign selector. Confirmation requires both campaign row and local/current plus
processed UI row. Failure conditionally restores the local pair only if still
owned by this attempt; it never overwrites a later user selection. Successful
intentional selection persists. No mission or active-operation bytes are written.

The click handler also calls a layout routine afterward. That routine requires
additional UI objects and has not been invoked by this prototype. Whether normal
UI updates complete the visual transition from the mirrored fields is the next
in-game test; the code does not claim visual success solely from memory values.
The log label is now PUBLICATION_STATE_VERIFIED with visual confirmation required.

Synthetic tests cover UI planet/difficulty mismatch, exact field writes,
processed-state confirmation, restoration and later user-selection preservation.
The seed publication/runtime/package suite passes. Next HITL: install 0.5.3,
relaunch, open the same planet at difficulty 10, report ready for candidate refresh,
then use Ctrl+Shift+F9. Background progress remains enabled.

### Successful end-to-end test — 2026-09-28

Session 24072-913054796, planet 268, difficulty 10: the user confirmed that
v0.5.3 correctly selected the matching operation in the visible game UI.
The log records publication from seed 3008511054 to 569798162, exact matching
operation/mission digests, row 28 selected, map UI state confirmed, mission
unselected, and the canonical active operation preserved. No rollback occurred.
The additional layout routine was not needed for this tested transition.

This validates the complete supervised path: offline prediction, one winning
seed publication, full-record verification, and visible operation selection.
It does not yet validate other planets/campaign contexts, arbitrary filters,
or automatic generation inside the script mod. The next development milestone
is integrating automatic context capture and prediction with the filter dialog.
