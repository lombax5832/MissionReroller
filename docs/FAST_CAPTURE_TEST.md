# One-poll capture — test plan

**Not yet validated in game.**

## What changed

Before a search the dialog shows **Checking planet data** while the mod
reads the viewed planet's board. Until now it polled the board every 0.5 s
and waited for four polls in a row to agree, each poll capturing the board
twice: at least 1.5 s before the first seed, longer than many solves.

Now:

- The run's first poll starts in the frame the request arrives.
- One poll whose two captures agree is enough when the board matches the
  prediction (identity, levels and composition). The search re-reads every
  input into its frozen read set, revalidates it every second and before a
  match, and compares the board's fingerprint every slice, so a board that
  changes after the capture still stops the search.
- Anything short of an exact match, rows another mod edited included, is
  confirmed the old way before it is reported: the run keeps capturing until
  four polls 0.5 s apart agree, then reports the result. A read taken while
  the map changed therefore never ends a run as a mismatch.
- `LUA_IDENTITY_*` lines add `capture_s` (request to result, in seconds) and
  `polls` (polls since the request).

## Install

Build `releases/Operation-Reroller-Dev-v<version>.zip` from this branch and
deploy it in place of the published mod (the Dev package has its own GUID;
enable only one). Purge / Deploy, launch, stay alone on your ship.

## Steps and the log lines that prove them

Read `MissionRerollerExperiment.log` after each step.

1. **Easy search.** Open the galactic map, view a planet, pick a filter that
   matches often (one mission type) and start. The dialog should pass
   **Checking planet data** almost at once.
   - Pass: `LUA_IDENTITY_PASS ... capture_s=0.<small> polls=1` (expect
     under about 0.3 s), then `LUA_SEARCH_STARTED` and `LUA_SEARCH_MATCH`.
   - Fail: `polls=4` or more with no `LUA_IDENTITY_RECHECK` before it.
2. **Existing match.** Search again for something the board already holds.
   The dialog should go straight to **Opening matching operation**.
   - Pass: `LUA_IDENTITY_PASS ... polls=1`, then `EXISTING_MATCH`.
3. **Start right after switching planet.** Click another planet and press
   **Reroll operations** immediately, several times.
   - Pass: each run ends in `LUA_IDENTITY_PASS`, or in
     `LUA_IDENTITY_RECHECK ...` followed by `LUA_IDENTITY_PASS ... polls=` 4
     or more. No `LUA_IDENTITY_MISMATCH` on a planet that passes on retry.
   - Fail: the search stops with `Search context changed` or
     `Frozen baseline prediction mismatch` noticeably more often than before.
4. **Edited board (optional, needs Refresh Operations).** Press its F6 on
   the viewed planet, then search.
   - Pass: `LUA_IDENTITY_RECHECK identity differs after one poll`, then
     `LUA_IDENTITY_EDITED ... polls=` 4 or more and the search runs as
     before (EXTERNAL_EDITS_TEST.md).

Compare `elapsed_s` on `LUA_SEARCH_MATCH` with the 0.48 s easy solve in the
2026-10-05 log: the time from **Reroll operations** to the match should now
be about `capture_s` plus that.
