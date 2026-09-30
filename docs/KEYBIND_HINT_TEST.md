# Key hint beside BACK — v0.21.0

## Status

Validated in game on 2026-09-29: the user confirmed the hint on screen
beside BACK. The hint anchors to the war table's own BACK hint, a native
widget of the map screen object. The survey below ran the same day with the
galactic map open on a 3440x1440 screen and found it at offset 1696;
`HINT_WIDGET` is set to that. Everything else in the package is v0.20.2,
plus the [input ownership fix](INPUT_OWNERSHIP.md).

## Survey result, 2026-09-29

The map screen lays its UI out in a 1920x1080 design space. On 3440x1440
the root widget (offset 56) is 1920x1080 at scale 1.333, placed at x=440,
so the canvas is centred with 440 px bars either side. Every widget carries
the same scale.

The screen has exactly two key hints, one block each: BACK at the bottom
left and one at the bottom right (offset 9248, local x -56 from the right).
The BACK block, in design units:

| Offset | Record | Local position | Size | Notes |
| --- | --- | --- | --- | --- |
| 1696 | hint container | 56, 16 | 135.97 x 32 | `HINT_WIDGET`. Screen 514.7, 21.3; 181.3 x 42.7 px |
| 1968 | inner container | 0, 0 | 135.97 x 32 | same rectangle |
| 2240, 2856 | key cap | 0, 0 | 57.9 x 32 | colour fields 1.0: a light cap |
| 3248 | cap text | 8, -6.4 | 41.9 x 15.75 | colour fields 0.2: dark text on the cap |
| 4400 | label text | 72.9, 16 | 59.07 x 15.75 | BACK, colour 1.0: white |
| 6136 to 6752 | gamepad glyph | 0, 0 | 40 x 40 | opacity 0 with a keyboard |

`src/keybind_hint.lua` copies those proportions: 8 units of padding in the
cap, 15 units between cap and label, text 15.75/32 of the container height,
a light cap with dark text and a white label. It leaves 32 units after the
game's hint.

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
