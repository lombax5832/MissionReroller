# Escape closes the dialog

## Status

**Not yet validated in game.** The build, `tests/test_package.py`, the new
`tests/test_escape_gate.lua` and the Escape cases in
`tests/test_prediction_dialog.lua` pass. Not yet released.

## What changed

Escape now closes the reroll panel like **CLOSE** does, cancelling a running
search the same way. It closes only the panel: the war table must not go
BACK on the same press.

Keyboard input reaches the game whatever the dialog does: the mouse gate
only covers the mouse, and the game's Lua has no keyboard counterpart (see
[MOUSE_INPUT.md](MOUSE_INPUT.md) and the input inventory). This change
relies instead on the game's live binding map, the structure
`src/mod_binding.lua` already reads and Mod Bindings Menu already writes:

- On opening, `src/escape_gate.lua` removes every keyboard Escape mapping
  (device 3, button, index 76) from the map's 256 buckets and keeps the
  other mappings in order. Only the changed buckets are written, only after
  their count and the map's bucket count check out, and only into private
  read/write pages. The action code at the head of a bucket is never
  written.
- On closing, each changed bucket is written back exactly as it was, but
  only once Escape is up, so the game never sees the press that closed the
  panel. A bucket that no longer holds what was written (rebound in
  between) is left alone and counted.
- Losing focus, losing input ownership, `STOPPED:` and shutdown put the
  mappings back at once.
- If the map cannot be read or written, the log has `ESCAPE_BLOCKED` once,
  the game keeps Escape for the session, and Escape still closes the panel.

**The main open question:** whether the war table's BACK is one of the
actions in this map at all. If BACK is hard-wired to the key, the log shows
the actions set aside but the map still goes back. The `actions=` list on
the first open also names which native actions have Escape.

## Test

Build with `python -B scripts/build.py`, import the ZIP and the loader, then
Purge / Deploy and launch.

1. **Load.** The startup line reads
   `Mission filters: F7 or the Reroll operations binding on the MODS tab, on the galactic map only; Escape closes; native cursor; ...`.
2. **Open.** On the galactic map, open a planet and press F7. The log shows
   `ESCAPE_HELD mappings=<n> actions=<group:action,...>` just before
   `MODAL_OPEN`. Note `n` and the actions: `mappings=0` means the game binds
   nothing to Escape through this map, and step 3 will go BACK.
3. **Escape closes the panel only.** Press Escape. The panel closes and the
   planet stays open on the war table. Hold Escape for a second before
   letting go: still nothing happens on the map. After release the log shows
   `MODAL_RELEASE closed` and then `ESCAPE_RESTORED buckets=<b>`.
4. **Escape works again.** Press Escape once more. The war table goes BACK
   as usual.
5. **Escape during a search.** Start a search, press Escape. The panel
   closes, the search stops (reopen: **Search cancelled**), the map stays.
6. **Other ways to close.** Open the panel and close it with **CLOSE**, then
   with F7. Each time `ESCAPE_RESTORED` follows, and Escape goes BACK
   afterwards.
7. **Alt-Tab.** Open the panel, Alt-Tab away and back. The log shows
   `MODAL_RELEASE focus lost; search continues` and `ESCAPE_RESTORED`;
   Escape goes BACK on the map again.
8. **ESC menu.** With the panel closed, Escape still opens the game's own
   menu wherever it did before (on the ship, for example).
9. **Mod Bindings Menu** (if installed). Options > Mouse & Keyboard shows
   the same bindings as before the test, including any key on Escape.

## Results to send

- The `ESCAPE_HELD` line from step 2.
- Whether step 3 left the map where it was.
- Any `ESCAPE_BLOCKED`, `ESCAPE_RESTORE_FAILED`, `ESCAPE_RESTORED ... changed=`
  or `STOPPED:` line.
