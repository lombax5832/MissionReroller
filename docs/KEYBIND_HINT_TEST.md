# Key hint beside BACK — v0.21.0

## Status

Implemented and tested offline; not yet active. The hint anchors to the war
table's own BACK hint, a native widget of the map screen object, and the
offset of that widget in the object is not known yet. `HINT_WIDGET` in
`src/prediction_dialog_runtime.lua` is nil, so the v0.21.0 package draws no
hint and logs `key hint beside BACK disabled` at start. Everything else in
the package is v0.20.2.

## What it draws

To the immediate right of BACK, on the same baseline and at the same
height: a key cap reading `CTRL + SHIFT + F8`, then `REROLL OPERATIONS`, in
the game's font. The sizes come from the BACK widget, so the hint follows
the game's UI scale and resolution. It is visible whenever the galactic map
is the top screen and the game has focus, with or without the reroll panel
open, and disappears with the map. A drawing or reading failure disables
the hint for the session and logs `HINT_BLOCKED …` once; the mod continues.

## Finding the widget

Know Your Constellation reads the map screen's planet frame the same way:
the map screen object is the one inline subscriber of a UI manager event
registry (`game+0x3326e68`, entry `+25224`, kind 226), and each of its
widgets is a record with flags at `+0` (0x10 visible), unscaled size at
`+36` and `+40`, inherited opacity at `+84`, scale at `+100` and `+140`, and
the solved bottom-left position at `+148` and `+156` in Gui pixels. The
planet frame is at `+349072`. The BACK hint is another such record; its
offset comes from a live survey:

1. Deploy Memory Explorer beside the loader, launch the game and open the
   galactic map. Leave the map on screen.
2. Run `python -B scripts/survey_map_widgets.py`. It reads the whole map
   screen object once and prints every visible widget-shaped record in the
   bottom quarter and left half of the screen, lowest first, with its
   offset, position, size and scale. Optional arguments change those two
   fractions. All records go to `artifacts/map-widgets.txt`.
3. The BACK hint is the lowest, leftmost row of a plausible size: roughly
   the height of a line of text and a few times as wide. Nested records
   share a corner: a hint is usually a container holding a key glyph and a
   label, so expect two or three rows with the same `y`, and pick the widest
   one, which is the whole hint. Note its `h` and `scale` too.
4. Set `HINT_WIDGET` to that offset, rebuild, and test as below. If the
   hint's height looks wrong compared with BACK, adjust `TEXT` in
   `src/keybind_hint.lua`, which is the text size as a fraction of the
   anchor's height, and `GAP`, the space after BACK.

## Test

1. Open the galactic map. The hint appears right of BACK, aligned with it,
   without covering it. Take a screenshot.
2. Hover planets, open one, and go back to the galaxy. The hint stays put.
3. Press Ctrl+Shift+F8. The hint stays while the panel is open and after it
   closes.
4. Leave the map for the ship. The hint is gone. Return: it is back.
5. Alt-tab away and back. The hint disappears and returns.
6. Change the resolution or UI scale if the game allows it; the hint should
   follow BACK.

## What the log should show

`MissionRerollerExperiment.log` starts with `Mission filters: …; key hint
beside BACK at widget <offset>; …`. No `HINT_BLOCKED` line. If one appears,
send it: the text after it names the read or draw call that failed, and the
hint is off until the next launch.

## Evidence and changes

- `src/keybind_hint.lua`: layout and drawing. `tests/test_keybind_hint.lua`
  covers the layout at four scales, metric-driven widths, refusal without
  room, and that the drawing is created once per distinct anchor, face and
  resolution and destroyed on clear.
- `src/prediction_dialog_runtime.lua`: `back_hint()` reads the widget with
  the same sanity checks the sibling mod applies to the planet frame, and
  the frame hook shows or clears the hint before the dialog's own work.
  `tests/test_prediction_dialog.lua` covers the hint with the dialog closed
  and open, without a map, without focus, and the one-time `HINT_BLOCKED`.
- `scripts/survey_map_widgets.py`: the live survey, reads only.
