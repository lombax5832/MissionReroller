# F7 beside other addons' key declarations

## Status

Not yet validated in game.

## The report

A player on v0.33.2 with Mod Bindings Menu v3 and nine Lua mods (among them
`codex/loadouts`, `codex/solo_vehicle_driver`, `driverhud/driver_hud` and
`dsh/first_person`) saw nothing on F7 and could not find Reroll operations
on the MODS tab. Their log registered the binding (`BINDING_REGISTERED ...
action 10:3`, a valid automatic action of Mod Bindings Menu v3) and recorded
baselines on the map, but had no `MODAL_OPEN` and no `SHORTCUT_IGNORED`: the
dialog never saw a press, on the map or off it, and nothing failed.

## Suspected cause

All addons share one LuaJIT VM. The first `ffi.cdef` of a function name
wins and later ones are silently ignored (checked with the pinned LuaJIT).
The adapter declared `int16_t GetAsyncKeyState(int)` and tests `< 0`. If an
addon that loads first declares it `uint16_t` or `unsigned short`, a held
key reads 32768, the test is never true, and F7 does nothing without an
error. The reporter's extra mods are not installed here, so which one (if
any) declares it that way is unconfirmed.

The adapter now resolves `GetAsyncKeyState`, `GetForegroundWindow` and
`GetWindowThreadProcessId` by address (`import_user32` in
`src/experiment_adapter.lua`), as `src/window_cursor.lua` does for the
cursor. `tests/test_ffi_conflicts.lua` declares the unsigned versions first.

## In-game test

1. Install the dev build beside the same mods as before, including Mod
   Bindings Menu. Deploy and launch.
2. Open the galactic map, view a planet, press F7.
   - Works: `MODAL_OPEN scope=planet key=F7 screens=...` (or `key=<name>`
     when a key is bound on the MODS tab), and the panel opens.
   - Off the map, a press logs `SHORTCUT_IGNORED screens=...`.
3. Options, Controls, MODS tab: a MISSION REROLLER header with
   Reroll operations. If it is missing, `ModBindingsMenu.log` should say
   `Registered ipodalexei.mission_reroller.reroll on native action ...` and
   `Filled MODS tab: N bindings in M sections.`
4. Note the hint beside BACK on the map: it names the key the mod listens to
   (`F7` unless a key is bound).

Failed if F7 still logs nothing on the map: then send
`MissionRerollerExperiment.log`, `ModBindingsMenu.log`,
`ModBindingsMenu.assignments` and what the hint beside BACK shows.
