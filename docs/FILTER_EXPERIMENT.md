# Filtered search experiment 0.3.0

## First live result and follow-up 0.3.1

The user completed the 0.3.0 test with Geological Survey + Spread Democracy
and reported five visible refreshes without a match. The log records planet
268, difficulty 10, exactly five calls and a clean `Five-call session limit
reached` termination. Seed sequence: 2697980623 -> 1436421440 -> 1271928012 ->
2214580143 -> 3769555502 -> 2943248998. The same active-operation record was
logged before each call, and no preservation, publication-timeout or native
guard failure was logged. This validates the bounded nonmatching path in this
supervised session, not general repeated-call safety.

Version 0.3.0 did not log selected filters or candidate mission IDs. The user's
filter selection is therefore user-reported; the complete five-batch matching
decisions cannot be independently reconstructed. Five misses do not establish
that the requested combination is either feasible or impossible.

Version 0.3.1 adds selected-filter names and per-batch candidate mission IDs to
the log, and preserves terminal search results after dialog/focus changes.
Its five-call limit and pacing are unchanged. Tests cover both Geological
Survey variants with Spread Democracy, rejection of a missing requirement,
and terminal-result preservation. The next meaningful matching validation is
a known-present operation yielding zero calls, followed by an audited search;
no additional live call was made to produce this update.

The user authorized extending the successful single-call experiment to bounded
sequential searching and a filter dialog. This package limits the entire game
process to five native reseeds, shared across cancelled/restarted searches. It
uses the previously tested preserving helper and its approved shared-RNG
exception. No manual writes or backend requests are added.

## Next in-game test

Disable the Preflight, One-Shot, and Development packages. Import
`releases/Mission-Reroller-Experiment-v0.3.0.zip`, retain Bingus Shared Loader as
the winning startup override, then Purge / Deploy and relaunch.

Alone on your own ship, select an available planet and wait 15 seconds. Hold
**Ctrl+Shift** when using all these keys:

| Key | Action |
| --- | --- |
| F8 | Open/close the filter dialog |
| F3 / F4 | Move to previous/next mission type |
| F5 | Toggle the highlighted requirement |
| F6 / F7 | Decrease/increase search difficulty (default 10) |
| F9 | Start; confirms you are alone on your own ship |
| F10 | Cancel |

For the first check, select Launch ICBM and Geological Survey. At difficulty
5..10 both must appear in one operation; the third mission is unrestricted.
The search difficulty is an explicit filter and does not change the game's
difficulty selector. Inspect results at that same difficulty in the game.

There is no mouse interaction in this first dialog. Keyboard events are polled,
not captured exclusively; function-key chords avoid reusing mission activation
keys, but conflicting custom game bindings should not be used. The panel must
render successfully before any reseed is permitted. If no dialog appears, do
not keep starting/relaunching; report it so the log can identify the failure.

After starting, stay on the planet until a match, cancellation or limit is
shown (up to three minutes). Do not launch a mission during this test. Report
the displayed result; the agent can read `MissionRerollerExperiment.log`.
No automatic selection or mission launch occurs. A match shows the operation
ID, row and native mission IDs to help compare the visible operations.

## Scope and limits

- The twelve named filters are common mission families mapped from the pinned
  build's mission settings. They are not a complete legal-option catalogue;
  some may be unavailable on the selected planet/difficulty. The UI states this.
- Modifiers and constellations are explicitly unavailable. Forecasting all
  operation missions needs additional inputs beyond the selected preview.
- Existing operations are checked before any call. All selected families must
  be present within the same operation. Extra missions remain unrestricted.
- Each reseed waits for a changed canonical/snapshot seed, rebuilt caches,
  consistent mission references and four stable quarter-second samples. Calls
  are at least five seconds apart; publication times out after 30 seconds.
- Forty stable samples are required before starting. Pending backend requests
  prevent calls. Context change, lost game focus, map closure, active-operation
  change, page/signature failure, UI failure or thread change prevent further
  calls. Cancellation cannot undo a call already issued.
- The active record is checked throughout the experiment after first Start.
  The five-call budget does not reset on cancellation, dialog closure or a new
  search. Relaunch resets process state; do not use that to bypass the test cap.
- General host authority detection and exclusive native thread ownership are
  not proven. This is a supervised solo-ship experiment, not a multiplayer
  release or a claim of server acceptance/game-policy approval.

## Verification

`python -B tests/test_experiment.py` tests the pure controller, retained panel
lifecycle, assembled addon snapshot decoding and an initial ICBM + survey match
with zero native calls. It packages the exact tested plaintext entry. Separate
one-shot tests cover the inherited native guard control flow. Engine rendering
and repeated native publication still require this in-game test.

Sources are split for review/testing and assembled into one plaintext resource;
the release contains no extracted game assets, dumps or external dependencies
beyond Bingus Shared Loader. Rendering API and font-layout facts were researched
from KnowYourConstellation; its implementation is not bundled.
