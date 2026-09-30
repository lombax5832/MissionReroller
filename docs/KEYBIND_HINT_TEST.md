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
the game's font. With Mod Bindings Menu installed and a key bound to
Reroll operations on its MODS tab, the cap reads that key instead (see
[Rebinding](#rebinding) below). The sizes come from the BACK widget, so the hint follows
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

## Rebinding

With [Mod Bindings Menu](https://github.com/CowboyBingus/ModBindingsMenu)
v2.0 installed, `src/mod_binding.lua` registers
`ipodalexei.mission_reroller.reroll` as **Reroll operations** under a
**Mission Reroller** header on the MODS tab, without a slot, so the menu
assigns one of its 36 native actions and keeps it for that id across
sessions. Each focused frame the runtime reads the binding with `is_down`
and ORs it with the Ctrl+Shift+F8 chord, so either opens or closes the
panel; the chord is never disabled. Automatically assigned bindings start
unbound.

The menu's API does not report which native action or key a binding got,
so the hint reads both from the game itself:

- The native action comes from the menu's registration record, which v2.0
  keeps in the `state` upvalue of `register_binding` (its own tests read it
  the same way). When that lookup fails the log says `action unknown` and
  the hint keeps the chord.
- The key comes from the game's live binding map, the same structure Mod
  Bindings Menu reads and writes: the input owner at `game+0x347cf18`, its
  256-bucket map at `+686800`, 328-byte buckets of `{u32 code, u32 count,
  16 x 20-byte mappings}`. A mapping's first byte holds the device in its
  low nibble (1 DualSense, 2 Xbox, 3 keyboard, 4 mouse) and the input kind
  in its high nibble (4 button); the input index is the u16 at offset 4.
  Indices run across devices, and keyboard keys are 49 plus the Windows
  virtual-key code: the menu's own log showed the map slot's developer
  defaults as `0`, `16`, `58`, `32` for Cross, XboxA, tab and left click,
  and the Debugmenu Open action's escape and right keys as 76 and 88. The
  key name comes from `stingray.Keyboard.button_name(code)`.
- Addons share one LuaJIT VM, so C function declarations are global and
  the first one wins. Mod Bindings Menu declares `VirtualQuery` with its
  own struct pointer, which stopped the first test build with `bad
  argument #2 to 'VirtualQuery'`. Calls that take our own structs now pass
  `void *`; `tests/test_ffi_conflicts.lua` declares the menu's version
  first and runs the entry's real page check.
- The map is read only after `is_down` has returned a value, because the
  menu removes the actions' developer default mappings on its first
  evaluated frame.

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
7. With Mod Bindings Menu installed: Options > Mouse & Keyboard > MODS shows
   a MISSION REROLLER header with a REROLL OPERATIONS row. Bind F8 to it.
   Back on the map, the cap beside BACK reads `F8`, and F8 alone opens and
   closes the panel; Ctrl+Shift+F8 still does too. Unbind it: the cap
   returns to `CTRL + SHIFT + F8`. Restart the game: the binding and the
   hint are kept.

## What the log should show

`MissionRerollerExperiment.log` starts with `Mission filters: …; key hint
beside BACK at widget <offset>; …`. No `HINT_BLOCKED` line. With Mod
Bindings Menu installed, the first frame on the map adds
`BINDING_REGISTERED ipodalexei.mission_reroller.reroll action <group>:<action>`,
matching the `Registered ipodalexei.mission_reroller.reroll on native action
<group>:<action>` line in `ModBindingsMenu.log`; `action unknown` there means
the hint cannot follow the binding. A `BINDING_FAILED` line carries the
menu's reason, and the chord still works. If one appears,
send it: the text after it names the read or draw call that failed, and the
hint is off until the next launch.

## Evidence and changes

- `src/keybind_hint.lua`: layout and drawing. `tests/test_keybind_hint.lua`
  covers the layout at four scales, metric-driven widths, refusal without
  room, that the drawing is created once per distinct anchor, face,
  resolution and key and destroyed on clear, and that a bound key replaces
  the chord on the cap.
- `src/mod_binding.lua`: the MODS tab binding. `tests/test_mod_binding.lua`
  registers against a stubbed Mod Bindings Menu and names keys from a
  simulated binding map: keyboard, mouse, controller-only, unbound, a moved
  bucket, a failed read, a refused registration, an `is_down` error, a menu
  without `debug`, and a version 1 menu.
- `src/prediction_dialog_runtime.lua`: `back_hint()` reads the widget with
  the same sanity checks the sibling mod applies to the planet frame, and
  the frame hook reads the binding, then shows or clears the hint before
  the dialog's own work. `tests/test_prediction_dialog.lua` covers the hint
  with the dialog closed and open, without a map, without focus, the
  one-time `HINT_BLOCKED`, the binding opening and closing the dialog, a
  held binding toggling once, the chord beside it, and the bound key
  reaching the hint.
- `scripts/survey_map_widgets.py`: the live survey, reads only.
