# Mission changed headers

## Change

Enemy force and side objective rules belong to a checked mission, or to
`ANY MISSION` while none is checked. A mission click that discards them
used to do so silently: checking the first mission discards the
`ANY MISSION` rules, and unchecking a mission discards its own. Now the
header of each section that lost rules (ENEMY FORCES, SIDE OBJECTIVES)
turns red, with the summary in white ending in `- MISSION CHANGED`, until
the player clicks that header or CLEAR. Closing the panel, a search and a
planet change keep the mark; it never blocks REROLL OPERATIONS. A click
that discards nothing marks nothing.

A mission is no longer dimmed because of `ANY MISSION` rules that checking
it would discard. Before, excluding every enemy force under `ANY MISSION`
dimmed every mission, so the player could not check one to start over.

The red is the excluded rows' red at a brighter wash, stronger under the pointer. Nothing is
logged: the header is the whole notice.

## Status

Tested in game by the user on 2026-10-04 with the brighter red; no log
lines prove it, since nothing is logged. Offline: `tests/test_filter_request.lua` (marks for
both sections, only the section that lost rules, no mark without rules,
cleared by its header and CLEAR, a mission not dimmed by rules it
discards), `tests/test_docked_panel.lua` (red header, white summary, an
open section stays yellow) and `tests/test_prediction_dialog.lua` (through
the real router, kept across a search), all through `tests/test_package.py`.

## In-game test

1. Open the galactic map, view a Terminid or Automaton planet, press F7.
   - Pass: `mods/ipodalexei/mission_reroller_experiment: loaded` in
     `BingusSharedLoader.log` and no `STOPPED:` line in
     `MissionRerollerExperiment.log`.
2. With no mission checked, open ENEMY FORCES and accept one constellation.
   Open SIDE OBJECTIVES and require one. Open MISSIONS and check a mission.
   - Pass: the ENEMY FORCES and SIDE OBJECTIVES headers are red, their
     summaries white and reading `ANY - MISSION CHANGED`. MISSIONS stays
     yellow, MODIFIERS and TIME OF DAY unchanged.
   - Fail: no red, or the text cut so `MISSION CHANGED` cannot be read.
3. Point at the red ENEMY FORCES header, then away.
   - Pass: it turns a stronger red under the pointer and back.
4. Close the panel with F7 and open it again.
   - Pass: both headers are still red.
5. Click ENEMY FORCES.
   - Pass: it opens yellow; MISSION CHANGED is gone from it. SIDE
     OBJECTIVES stays red. Click MISSIONS: ENEMY FORCES stays plain.
6. Uncheck the mission (click it until it reads ANY) with no rules of its
   own.
   - Pass: no header turns red.
7. Check a mission, open ENEMY FORCES and accept a constellation on its
   page, go back to MISSIONS and uncheck it.
   - Pass: ENEMY FORCES turns red with `ANY - MISSION CHANGED`. Press CLEAR:
     every header is plain.
8. With no mission checked, open ENEMY FORCES and exclude every
   constellation on `ANY MISSION`. The status line reads
   `Every constellation here is excluded`. Open MISSIONS.
   - Pass: missions are not dimmed; checking one works and turns ENEMY
     FORCES red.
