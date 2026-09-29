# Mouse interaction and modal ownership: work in progress

## Reopening fix 0.2.1

The user confirmed the polished/native-cursor preview works, but closing it
prevented reopening. Normal close and focus-loss paths inherited the original
diagnostic's permanent `done` flag. Version 0.2.1 restores input and returns to
the closed state without disabling updates. Ctrl+Shift+F8 can reopen it, with
checkbox selections retained. The 60-second auto-close uses the same path.
Genuine errors and detected underlying selection changes still stop the probe.

The regression drives the real runtime and pointer router with stubbed OS and
render boundaries. It reproduced the permanent-stop bug, and now passes normal
close/reopen, selection preservation and focus-loss/reopen. Cursor restoration
and closing-release tests also pass. Package: Mouse-Test-v0.2.1; no reseeds.

## Polished preview 0.2.0

The user confirmed 0.1.1 worked, including the mouse interaction test, and
requested visual polish and the native cursor. Version 0.2.0 uses a centered
two-column layout, dimmed backdrop, native font, gold accent, hover highlights,
checkbox squares, selection count, Clear Selection and Close controls. Render
and hit-test bounds come from one layout function, tested at 640x480, 1280x720,
1920x1080 and 3440x1440. The auto-close window is now 60 seconds.

Native Window.show_cursor getter RVA 0x3ffc20 reads window+0x88. Setter wrapper
0x3ffdd0 accepts (window, visible, reposition), invokes 0x614e80, and applies
the existing native cursor through 0x6167f0. The optional reposition argument
is explicitly false. The addon saves visibility, enables it while holding the
mouse-focus gate, then restores it before returning focus. No cursor shape is
replaced and no software cursor is drawn. Private writable checks cover
window+0x80..0x89 (saved cursor coordinates and visibility/focus bytes), and
additional signatures guard these cursor functions. Offline evidence is in
ignored `tools/ghidra-projects/reroller_cursor_*.txt`.

Install `Mission-Reroller-Mouse-Test-v0.2.0.zip` in place of 0.1.1, redeploy and
relaunch. Open on a selected planet with Ctrl+Shift+F8. Verify the native cursor,
hover/selection appearance, Clear Selection, Close, and restored map input.
Rerolls remain disabled in this visual iteration. Native cursor visibility
still requires in-game confirmation; offline tests establish save/restore
logic and layout, not actual rendering.

## Cursor follow-up: mouse test 0.1.1

The user ran 0.1.0 and reported that the underlying HUD did not react, but the
cursor was invisible. The log confirms acquisition and clean restoration with
no detected selection change. No checkbox clicks were logged, so click routing
and closing-click isolation remain unverified in-game.

Mouse test 0.1.1 draws a high-contrast crosshair at the same client-to-render
position used for hit testing. It updates retained rectangles every frame and
removes them with the overlay; no cursor-visibility setter or extra game-memory
mutation is introduced. Panel tests cover cursor creation, movement without
reallocation or text rebuild, and removal. Gate and pointer-router tests pass.

Replace the mouse test with `Mission-Reroller-Mouse-Test-v0.1.1.zip`, redeploy and
relaunch, then repeat Ctrl+Shift+F8 on a selected planet. Verify that the cursor
moves, checkbox clicks toggle only the overlay, Close restores map input, and
the closing click does not select anything beneath it. No rerolls are enabled.

## Current-session inventory and next mouse-only test

The passive inventory completed successfully. Window getter/setter and
get_main_window are exposed; Gui exposes drawing/coordinate APIs, Input exposes
event_queue, and UI/Noesis namespaces are absent. Saved-code argument parser
0x3f6a50 confirms a leading Window userdata argument, followed by the boolean
for set_mouse_focus. This proves call availability/signature, not HUD blocking.

`Mission-Reroller-Mouse-Test-v0.1.0.zip` is a candidate gate experiment. Disable
other Mission Reroller packages, import this ZIP with Bingus Shared Loader,
Purge / Deploy, and relaunch. Select a planet and press Ctrl+Shift+F8. First move
the pointer without clicking: the underlying map should not highlight or react.
If it does react, close with Ctrl+Shift+F8 and report failure. If it does not,
click a checkbox, then the Close control. Verify normal map input returns.
The test also closes after 20 seconds, waiting for a held mouse button to be
released before returning input. It cannot reroll operations.

The test checks installed module hashes, getter/setter/parser byte signatures,
one registered main window, and a committed private read/write page covering
window+0x89 before using the exposed setter. It saves the prior boolean and uses
the same explicit window handle for restoration. It observes map selection
after a half-second settling interval; a changed selection aborts and restores.
Errors, map closure, focus loss and shutdown also attempt restoration. A changed
window identity stops restoration to avoid using a stale handle and is logged.

Log: `MissionRerollerMouseProbe.log`. Offline tests cover the candidate gate's
save/restore contract, click/drag/disabled controls and the closing-release
barrier. The mouse test is separate from the search addon because native HUD
blocking is not yet established. No operating-system global input block,
window-procedure hook, code patch or explicit game-memory write is used.

The requested behavior is a mouse-interactive filter dialog that blocks all
underlying HUD/map interaction while open, restores normal input on close,
and does not leak the closing click's release to a mission card. Simply drawing
above the HUD or polling mouse buttons does not provide that guarantee.

## Completed independent work

`src/modal_pointer.lua` implements press/release matching, disabled controls,
drag-in/drag-out rejection, opening-click suppression and a closing-release
barrier. It requires an input ownership adapter to acquire and confirm exclusive
routing before it will open. Tests pass. It is not wired into a release because
no native ownership adapter has been established. Existing experiments remain
keyboard-only; their mouse behavior has not changed.

## Offline findings, build 25480438

The saved executable registers Window `mouse_focus` and `set_mouse_focus` via
RVA 0x3ff1f0. Getter 0x3ff400 validates a window against the application's
registry and reads byte +0x89. Setter 0x3ff540 validates the window and stores
the supplied boolean at +0x89. This alone does not establish that it suppresses
game.dll's native HUD input, or the correct restoration lifetime. `set_focus`
at 0x3ff670 is a separate operating-system focus path, not a modal UI owner.

The saved game.dll contains Noesis routed mouse/capture event names and native
menu input types. Their presence does not establish a Lua-accessible API.
Earlier API inventory `dumps/stim-aim-visibility-v070.log` contains mouse polling
and Input.event_queue, but does not supply a usable capture/consume contract.
Replacing a Lua polling method would not prove that native HUD callers are
blocked, so that approach is not used.

Raw offline analysis is in ignored workspace files
`tools/ghidra-projects/reroller_mouse_focus*.txt`,
`reroller_mouse_consumers.txt`, and `reroller_window_dispatch.txt`. No setters,
memory writes, native input calls, or additional reseeds were executed.

## Next human step: passive current-session API inventory

Import `Mission-Reroller-Input-Inventory-v0.1.0.zip` with Bingus Shared Loader,
Purge / Deploy, and relaunch normally. No map interaction or reroll is needed.
The addon logs names/types in Window, Application, Gui, Input, Mouse, Keyboard,
UI and Noesis, including table-based inherited members, to
`MissionRerollerInputInventory.log`. It calls none of the discovered methods,
reads no game memory and does not replace callbacks. Say Ready after launch.

This establishes which candidate APIs are actually exposed to this game's Lua
VM. If no ownership API exists, native input routing still needs investigation;
the inventory cannot itself prove input blocking. Do not describe this package
as enabling mouse controls or stopping click-through. It is a prerequisite,
not the finished requested feature.
