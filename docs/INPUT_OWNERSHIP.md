# Input ownership after a resolution change — v0.21.0

## What happened

On 2026-09-29, with v0.21.0, the user changed the game's resolution from
3440x1440 to 1920x1080 and then pressed Ctrl+Shift+F8. The log reads:

```
MODAL_OPEN scope=planet
STOPPED: mods/ipodalexei/mission_reroller_experiment.lua:2270: Modal input ownership lost
MODAL_RELEASE error
```

The dialog opened, and on its first step the mouse gate no longer held: the
game had put back one of the two window flags the gate had just set, mouse
focus (`window+0x89`) or native cursor visibility (`window+0x88`). Any error
in the frame stops the mod for the session, so the mod looked broken until a
restart. Read afterwards through Memory Explorer, the window registry still
held one window, on a private read/write page, with focus 1 and cursor 0:
the restored state, and nothing that explains the flip. The Ghidra notes in
`tools/ghidra-projects/reroller_mouse_*` and `reroller_cursor_*` list only
the Lua setters as writers of those bytes, so the game's own writer on the
resize path is not identified.

## What changed

- `src/window_mouse_gate.lua`: a held gate that finds a flag changed
  underneath it reapplies its own with the same calls as acquire, on the
  same handle, and counts the drift in `drifts` with the finding in
  `reason`. It reports lost ownership only when the flags no longer stick
  or the window identity changed. A failed acquire puts back what it
  changed and leaves the gate free. `forget()` drops a handle that release
  refused to touch, so a new window can be acquired.
- `src/prediction_dialog_runtime.lua`: a failing step no longer stops the
  mod. It logs `MODAL_INPUT_LOST <error> (<reason>)`, restores the window,
  releases the dialog with `MODAL_RELEASE input ownership lost`, keeps a
  running search, and reports `Dialog closed: input ownership lost. Press
  the shortcut to reopen`. `MODAL_RELEASE` lines carry `reasserted=<n>
  last=<reason>` when drifts happened while the dialog was open.

## Test

1. Open the galactic map, open the dialog, close it. Change the resolution
   in the game's settings, return to the map.
2. Press F7 on the galactic map. The dialog should open and work: the cursor is
   visible, rows react, the map behind does not. Search once.
3. Close it. Change the resolution back and repeat step 2.
4. Read `MissionRerollerExperiment.log`. Expected: no `STOPPED`, and either
   nothing unusual or `MODAL_RELEASE closed reasserted=<n> last=…`. The
   `last=` text names which flag the game flipped and settles the cause.
   `MODAL_INPUT_LOST` means the reapply did not stick; send the line.
5. If the dialog does not blank the HUD's mouse input after a change (a
   click that reaches the map), say so: that would mean the game reapplies
   its flags after the mod each frame, and a different fix is needed.

## Evidence and changes

- `tests/test_window_mouse_gate.lua`: drift reapply and counting, a reapply
  that does not stick, a changed window, `forget()`, and a failed acquire
  leaving the gate free.
- `tests/test_prediction_dialog.lua`: ownership lost while open releases
  the dialog, restores the window, logs the loss and the reason, does not
  stop the mod, and the shortcut opens the dialog again.
