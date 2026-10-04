# Time of Day tiles

## Change

Section 5 of the panel, TIME OF DAY, is no longer a dropdown. Three tiles
sit on its header, right of the title: ANY, DAY and NIGHT. DAY and NIGHT
carry the galactic map's sun and moon icons. DAY and NIGHT have a second line:
`DAYLIGHT` and `DARK`. The chosen tile is yellow and its
second line says how long the side holds: `AT LEAST 2H 30M`, less on short
days (`AT LEAST 14M`). While the planet's sky loads it is amber and reads
`WAITING`; when no city can hold that side it is red and reads
`NO CITY HOLDS`, beside the status line's reason. The header keeps its
height, so the open section's rows never lose room.

The layout is A5 of a prototype (branch `worktree-prototype-time-of-day`,
`prototypes/time-of-day-filter.html`).

## The icons

The sun and moon are 48-pixel squares on page `18edbed388a3d706`
(4096x2048) of the ship UI texture atlas `b4a883566f3f243a`, package
`packages/content/atlas_ship`: the sun at (3582,1848), the moon at
(3742,1848). Their own textures are `7eeed068a1eca3ed` and
`7db22ccc01a327ac`, which `game.dll` keeps side by side in one UI settings
struct (written at 1256c5d). Each is a white square with the picture cut
out, so on a tile it reads as a small badge. The panel draws them with
`Gui.bitmap_uv` through the shared UI material `gui_diffuse_map`
(`57fcf14ad069020b`) with the page on its `diffuse_map` slot (`3aa8b87e`).
None of this ran in game before this change: the call's argument order,
the V direction and whether the atlas page is loaded are what step 1
checks. Any failure turns the icons off for good and leaves the labels.

## Status

Not validated in game. Offline: `tests/test_docked_panel.lua` (layouts at
four resolutions with a side chosen, the tiles inside the header, the icon
rectangles, amber and red, labels without icons),
`tests/test_filter_request.lua` and `tests/test_prediction_dialog.lua`
(clicking `time:night` through the real router), all through
`tests/test_package.py`.

## In-game test

1. Open the galactic map, view a planet, press F7.
   - Pass: `mods/ipodalexei/mission_reroller_experiment: loaded`,
     `TIME_ICONS drawn` and no `STOPPED:` line. Section 5 shows TIME OF DAY
     with three tiles: ANY (yellow, one line), DAY with a sun
     (`DAYLIGHT`) and NIGHT with a moon (`DARK`). The moon's thick side is
     at the lower right, as on the galactic map. Sections 1 to 4 still open
     and close.
   - Icons wrong: `TIME_ICONS off reason=…` (send the reason), no picture,
     another picture, a picture upside down, or a square that is all white
     or all black. The tiles must still work without them.
   - First build, 2026-10-04: the icons showed, then vanished after a
     click or when the pointer left a tile, and a white square appeared in
     the screen's lower left corner. `Gui.update_bitmap_uv` misplaced them.
     The second build deleted (`Gui.destroy_bitmap`) and redrew each icon
     instead, with the same result. The third draws each icon once per
     panel GUI and never changes it; choosing another side rebuilds the GUI.
2. Point at DAY, then away; point at NIGHT, then away.
   - Pass: the sun and moon stay on their tiles through every hover, and
     no square appears anywhere else on the screen.
3. Click NIGHT.
   - Pass: NIGHT turns yellow with a dark moon badge and reads
     `AT LEAST 2H 30M` (less on a short-day planet), ANY goes dark. The log
     shows `DAYNIGHT_PLANET planet=<n> …` once.
   - Fail: nothing changes, or a `STOPPED:` or panel error line.
4. Open each of sections 1 to 4 with NIGHT still chosen.
   - Pass: every row is readable and above the footer; the tiles do not
     move.
5. Press REROLL OPERATIONS.
   - Pass: `DAYNIGHT_SEARCH side=night …`, then a `DAYNIGHT_MATCH side=night`
     and `PUBLICATION_STATE_VERIFIED`, as in docs/DAY_NIGHT_TEST.md.
   - During the search the three tiles dim and ignore clicks, and NIGHT
     keeps `AT LEAST 2H 30M`: no amber `WAITING`.
6. Choose City scope on a planet where a city is past its side (see
   docs/DAY_NIGHT_TEST.md), DAY chosen.
   - Pass: the DAY tile turns red and reads `NO CITY HOLDS` while the status
     line gives the wait.
7. Click ANY, then CLEAR with DAY chosen.
   - Pass: each time ANY turns yellow and DAY reads `DAYLIGHT` again.
