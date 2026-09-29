# Docked dialog — v0.20.0, quiet data gaps — v0.20.1

## Result, 2026-09-29 session (v0.20.0)

The log shows the panel opened with Ctrl+Shift+F8 and three requests
completed from it on planet 268, each ending in
`PUBLICATION_STATE_VERIFIED … map_ui_row_confirmed=true`: two published a new
seed after 1 and 192 seeds, one selected an operation that already matched.
No `STOPPED` or `BLOCKED` line was written. The log does not show how the
panel looked.

The user reported that the panel sometimes showed `UPDATING PLANET DATA. YOUR
CHOICES ARE KEPT` for a moment and ignored clicks meanwhile. v0.20.1 changes
that; see *Quiet data gaps* below.

## Status

v0.20.1 is not validated in game. Only offline tests were run: the layout,
the retained drawing against a recording engine, and the dialog logic with
the real click router. What those tests cannot show is listed under *Limits*.

Search, prediction, publication, compatibility, the catalogue, the hotkey,
the mouse gate and the click router are unchanged from v0.19.0.

## Quiet data gaps — v0.20.1

The game's planet data is briefly unavailable now and then, for example
while a request to the backend is pending. v0.20.0 dimmed every row, showed
the status above and refused REROLL OPERATIONS until the data returned.

- **A gap is not shown.** The rows, the status and the buttons stay as they
  were, and the request can be edited. It is edited against the list the
  panel already shows.
- **The panel changes only when the data did.** When the data returns
  unchanged, nothing happens. When it returns different, missions and rules
  the planet no longer offers are removed, with `UNAVAILABLE FILTERS CLEARED
  FOR THIS PLANET/DIFFICULTY`, as before. A refresh of the same planet and
  difficulty no longer turns the mission list back to its first page.
- **REROLL OPERATIONS during a gap waits.** The panel shows a search in its
  first step, `1 CHECK PLANET` and `CHECKING PLANET DATA`, and starts it as
  soon as the data returns. The request is validated against that fresh data
  like any other; a search is never started from the retained list. CANCEL
  SEARCH, CLOSE, alt-tab and viewing another planet drop the waiting request.
- **A gap of 1.5 seconds or more is reported** with `UPDATING PLANET DATA.
  YOUR CHOICES ARE KEPT`. The request stays editable. A waiting request is
  given up after 10 seconds; the panel then reads `PLANET DATA DID NOT
  ARRIVE; TRY AGAIN` once the data is back.
- `OPERATION IN PROGRESS …` stays through a gap instead of disappearing for
  its duration.

To test: use the panel for a few minutes and report any moment in which rows
go dim or the status changes without a click. Start a search several times;
if one takes noticeably longer than the usual two seconds before seeds are
counted, note it. The log line `DIALOG_SEARCH` is written when the search
really starts, not when the button is clicked.

## Install

Install `releases/Mission-Reroller-v0.20.1.zip` in place of the previous package,
Purge / Deploy, and restart. Remain alone on your ship for this supervised test.
If the panel is unusable, reinstall `Mission-Reroller-v0.19.0.zip`; the two
builds differ only in the dialog.

## What is new

Ctrl+Shift+F8 opens a panel docked to the right edge of the screen instead of
a centred dialog. The screen is no longer dimmed, so the planet stays visible.
The map still does not react while the panel is open.

- **Header.** The faction in its colour, then `WHOLE PLANET` or `THIS CITY
  ONLY`, and the map difficulty on the right. The mod has no planet names.
- **Three sections**, one open at a time: `1 MISSIONS`, `2 MODIFIERS`,
  `3 ENEMY FORCES`. A closed section shows its summary: the checked missions,
  or the number of rules, or `ANY`. Clicking the open section closes it.
  Missions are open each time the panel opens.
- **Missions.** Two columns, up to 24 per page. `<` and `>` appear in the line
  above the list when the planet offers more. A mission that cannot be added
  is dimmed; pointing at it shows the reason in that line.
- **Modifiers.** One row each, cycling ANY, REQUIRED, EXCLUDED on a click. The
  box is empty, filled yellow, or red with a bar.
- **Enemy forces.** A row of buttons, one per checked mission, or `ANY
  MISSION` when none is checked. They replace the `<` `>` pages and the
  `FOR: …` row. Each constellation cycles ANY, ACCEPTED, EXCLUDED. Only the
  name is shown, without the game's tag; the log still has the tag.
  Constellations that are always present are listed below the rows.
- **Footer.** A status line, a detail line and three buttons. During a search
  four steps are shown, `1 CHECK PLANET` to `4 OPEN OPERATION`, with the
  number of seeds searched out of 262,144.
- **REROLL OPERATIONS is disabled until something is set.** v0.19.0 accepted
  the click and answered `Choose at least one mission, modifier rule or
  constellation`.
- **CLEAR** is disabled when nothing is set, during a search and while planet
  data is missing.
- All text is in capitals.

The rules themselves mean what they meant in v0.19.0; see
[constellations per mission](CONSTELLATION_FILTER_TEST.md) and
[cities](CITY_SCOPE_TEST.md).

Status wording that changed:

| Situation | v0.19.0 | v0.20.0 |
| --- | --- | --- |
| Nothing set | `Select missions; difficulty follows the map` | `CHOOSE WHAT THE OPERATION MUST CONTAIN` |
| Something set | the same | `READY TO SEARCH` |
| No planet shown | `Choose a planet and map difficulty` | `OPEN A PLANET ON THE WAR TABLE FIRST` |
| Planet data updating | `Updating planet data; filters retained` | nothing for 1.5 seconds (v0.20.1), then `UPDATING PLANET DATA. YOUR CHOICES ARE KEPT` |
| Operation in progress | `This operation is in progress; its missions cannot be rerolled` | `OPERATION IN PROGRESS. FINISH OR ABANDON IT TO REROLL` |

Search results, errors and the reasons for dimmed missions keep their text.
A result such as `SEARCH CANCELLED` stays until the request is edited.

## Test

Report what differs from the description, with a screenshot if possible.

1. View a planet and press Ctrl+Shift+F8. The panel is at the right edge,
   full height, with a yellow bar on its right side. The rest of the screen
   is not dimmed.
2. Text: every line is readable, in the game's font, inside its row or
   button, and not overlapping other text. Look at the longest mission
   names and at the summary of the missions section.
3. The three section headers each show a number, a title, a summary and a
   small triangle: pointing up on the open section, down on the others.
   The REROLL OPERATIONS button has two cut corners, top right and bottom
   left. Say so if the triangles or the cut corners are missing, misplaced
   or drawn in front of text.
4. Move the pointer over rows and buttons. They lighten. The map behind the
   panel does not react, also left of the panel.
5. With nothing checked REROLL OPERATIONS and CLEAR are dim and do nothing.
6. Check two missions. The summary names them, the line above the list counts
   the slots, and the status reads `READY TO SEARCH`. Point at a dimmed
   mission and read the reason.
7. Open `2 MODIFIERS` and click one row three times: REQUIRED, EXCLUDED, ANY.
   The box and the word on the right follow.
8. Open `3 ENEMY FORCES`. There is one button per checked mission. Switch
   between them and set one constellation to ACCEPTED on each. Uncheck all
   missions: the single button reads `ANY MISSION`.
9. On a planet that offers more than 24 missions, `<` and `>` change the page.
10. Start a search. The button turns red and reads CANCEL SEARCH, the steps
    appear, and the seed count rises. Rows are dim and do not react; the
    section headers, CANCEL SEARCH and CLOSE do.
11. After a match the panel closes and the operation opens, as before.
12. Close with CLOSE and with Ctrl+Shift+F8. Map input returns, and the click
    that closed the panel does not select anything on the map.
13. Open it on a city's operation marker: the header reads `THIS CITY ONLY`.
14. If the display is not 16:9, check that the panel still sits 40 design
    pixels from the right edge and that nothing is cut off.

## What the log should show

`MissionRerollerExperiment.log` has the same lines as v0.19.0. Two differ:

- At start: `Mission Reroller 0.20.1 docked dialog; …` and
  `Mission filters: Ctrl+Shift+F8; native cursor; docked panel; …`.
- `MODAL_OPEN`, `DIALOG_SEARCH`, `LUA_SEARCH_…` and the publication lines are
  unchanged. Constellations are logged with the game's tag as before.

A drawing error stops the mod with `STOPPED: …` and releases the mouse, as in
earlier builds. Send that line if it appears.

## Limits

- **Escape does not close the panel.** The mock-up showed an `ESC` key on
  CLOSE. The gate the dialog holds is a mouse gate
  (`src/window_mouse_gate.lua` changes mouse focus and the cursor only), so
  the game would receive Escape as well and act on the war table. The button
  reads `CLOSE` and the key is not handled.
- **Triangles and text measuring are new to this mod.** `Gui.triangle` and
  `Gui.text_extents` are listed in the input inventory log of an earlier
  session, and a sibling mod has drawn a visible triangle, but with a GUI
  that is redrawn every frame. This panel keeps its objects. If either call
  is missing or fails once, the panel continues without it: no triangles on
  the headers, square corners on the button, and text placed from an
  estimated width, which leaves right-aligned text a little short of the
  edge and makes long names smaller than needed.
- **Text size and position are estimates.** Offline the width of a glyph is
  unknown. Text that is too wide for its place is first drawn up to 20%
  smaller and then cut with `...`. The vertical position of text in its row
  assumes capitals about 0.7 of the font size high, as the v0.19.0 dialog did.
- **One font weight.** The mock-up used bold for titles and the status line.
  The game font is drawn through one material, in one weight.
- **No dimming.** The map stays bright behind the panel. The mouse gate is
  the same as before, but whether an undimmed map invites clicks that then
  do nothing is for the user to judge.
- **The corners of the button are cut with an opaque colour** close to the
  footer's. The panel is slightly translucent, so over a bright scene the two
  small triangles can look darker than the footer around them.
- **Rows shrink when a list is long.** Twelve or more modifiers, or eleven
  constellations, use lower rows so that the list ends above the footer
  of a running search. This was only seen in the offline rendering.
- **Below 1920×1080 the text is small.** Everything scales with the smaller
  of width/1920 and height/1080.
- **Which side the game keeps free** on the planet screen was not checked.
  The panel covers the right third of the screen.

## Offline evidence

- `tests/test_docked_panel.lua`: click targets inside the panel and not
  overlapping at 1280×720, 1920×1080, 3440×1440 and 640×480, for each open
  section, 24 missions with paging, 13 modifiers, 3 groups with 11
  constellations, a running search and no planet; nothing but the footer
  reaches below the step strip; an unchanged state draws nothing; a rule
  change updates existing rows; the seed counter updates one text; a section
  switch removes the old rows; missing, failing or implausible
  `Gui.triangle` / `Gui.text_extents` cause no error and are not retried.
- `tests/test_prediction_dialog.lua`: the dialog logic with the real click
  router and the packaged panel drawing every frame into a recording engine.
  It covers the sections, the groups, paging, the disabled REROLL OPERATIONS
  and CLEAR, locked rows during a search and while data is retained, and
  every safety case of v0.19.0: no start from retained data, pruning when
  the planet changes, validation before a search, alt-tab, cancel, close,
  city scope and the operation in progress.
- `tests/test_dialog.py` runs both and checks that the package holds the
  docked panel and not the centred one. Older builds still package
  `src/mouse_panel.lua`, which is unchanged.
- The panel was rendered offline from the recorded draw calls and compared
  with the mock-up at 1920×1080. That rendering uses a desktop font, not
  the game's.
