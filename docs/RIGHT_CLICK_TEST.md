# Right click cycles filters backwards: not yet tested in game

## Change

A filter row cycles ANY, REQUIRED (ACCEPTED for enemy forces), EXCLUDED on
a left click. A right click now cycles the other way: ANY, EXCLUDED,
REQUIRED, ANY. It skips a state that is ruled out, as a left click does. A
mission whose requirement is ruled out, so that it can't join the required
ones, stays disabled for both buttons. A right click on anything else
(time tiles, section headers, mission tabs, page arrows, REROLL, CLEAR,
CLOSE, empty space) does nothing. A press with both buttons down does
nothing. The hints read `LEFT/RIGHT CLICK TO CYCLE: ...`, and the enemy
forces section shows one below its rows for the first time.

No log line records a click: the evidence is what the rows show, plus the
absence of failure lines.

## Test

Build `releases/Operation-Reroller-Dev-v0.35.1.zip` from the
`right-click-cycle` branch. Enable it instead of the published Operation
Reroller (they share a module), Purge / Deploy, launch. Open a planet on
the galactic map and press F7.

1. **Missions.** Right-click an unchecked mission: it turns EXCLUDED (red).
   Right-click again: REQUIRED (yellow). Again: unchecked. Left-click still
   goes unchecked, REQUIRED, EXCLUDED.
2. **Skips.** Require a mission so that another one becomes disabled (greyed,
   with a reason). Right-clicking the disabled one does nothing. If a
   mission is in every operation (a left click goes REQUIRED, then straight
   back to unchecked), a right click on it goes straight to REQUIRED.
3. **Modifiers.** Right-click a modifier: EXCLUDED, REQUIRED, ANY.
4. **Enemy forces.** Check a mission, open ENEMY FORCES. The hint
   `LEFT/RIGHT CLICK TO CYCLE: ANY, ACCEPTED, EXCLUDED` sits under the rows,
   below ALWAYS PRESENT when that line is shown. Right-click a row:
   EXCLUDED, ACCEPTED, ANY.
5. **Side objectives.** Right-click a row: EXCLUDED, REQUIRED, ANY.
6. **Discarded rules.** Check a mission, set one of its enemy forces, then
   right-click the mission back to unchecked. The ENEMY FORCES header turns
   red, as it does after a left click.
7. **Buttons.** With a filter set, right-click REROLL OPERATIONS, CLEAR,
   CLOSE, a section header, a time tile and a page arrow: nothing changes
   and the dialog stays open. Hold left on a row, press right, release
   both: the row does not change.
8. **Hint width.** On MISSIONS with two pages (`PAGE 1/2   n OF 3 SLOTS`
   on the right), check whether the hint is complete or cut with `...`.
   Report which, and the resolution.
9. **The game.** A right click while the dialog is open must not reach the
   galactic map behind it.

## Proof

- `BingusSharedLoader.log`: `mods/ipodalexei/mission_reroller_experiment: loaded`.
- `MissionRerollerExperiment.log`: no `STOPPED:` and no `MODAL_INPUT_LOST`
  during the test.
- Steps 1 to 9 behave as described. Step 8 is a report, not a pass or fail.
