# Time of Day header

## Change

Section 5 of the panel, TIME OF DAY, is no longer a dropdown. Its header
holds three buttons, ANY, DAY and NIGHT, with the chosen one filled yellow.
While Day or Night is chosen, one line under the header reads
`STAYS ON THAT SIDE AFTER THE REROLL` on the left and the sky note
(`HOLDS 2H 30M / DAY <length>`) on the right. When the open section's rows
would otherwise drop below their 20-unit minimum (side objectives with 14
or more rows), that line gives way to the list.

The choice is picked from a prototype of four variants (branch
`worktree-prototype-time-of-day`, `prototypes/time-of-day-filter.html`);
the user chose A1, the segmented header with a note line.

## Status

Not validated in game. Offline: `tests/test_docked_panel.lua` (layouts at
four resolutions with a side chosen, the note line's room and fallback, the
chosen side drawn in ink), `tests/test_filter_request.lua` and
`tests/test_prediction_dialog.lua` (clicking `time:night` through the real
router), all through `tests/test_package.py`.

## In-game test

1. Open the galactic map, view a planet, press F7.
   - Pass: `mods/ipodalexei/mission_reroller_experiment: loaded` and no
     `STOPPED:` line. Section 5 shows TIME OF DAY with ANY filled yellow,
     DAY and NIGHT in grey, and no chevron. Sections 1 to 4 still open and
     close.
2. Click NIGHT.
   - Pass: NIGHT turns yellow, ANY goes grey, and a line appears under the
     header: `STAYS ON THAT SIDE AFTER THE REROLL` and
     `HOLDS 2H 30M / DAY <length>`. The log shows
     `DAYNIGHT_PLANET planet=<n> …` once.
   - Fail: nothing changes, the line overlaps the footer, or a `STOPPED:`
     or `panel` error line.
3. Open SIDE OBJECTIVES with Any mission selected on a planet with many
   objectives, NIGHT still chosen.
   - Pass: every row is readable and above the footer; the note line under
     TIME OF DAY may disappear when the list is long.
4. Press REROLL OPERATIONS.
   - Pass: `DAYNIGHT_SEARCH side=night …`, then a `DAYNIGHT_MATCH side=night`
     and `PUBLICATION_STATE_VERIFIED`, as in docs/DAY_NIGHT_TEST.md.
   - During the search the three buttons dim and ignore clicks.
5. Click ANY, then CLEAR with DAY chosen.
   - Pass: each time ANY turns yellow and the note line disappears.
