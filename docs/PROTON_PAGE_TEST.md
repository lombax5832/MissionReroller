# Planet data checks under Proton

## Status

**Validated in game on 2026-10-03.** The user confirmed the fix worked
with the development build; no log lines were quoted, so which page failed
and which value Proton reported are still unrecorded. Released as v0.32.1.

## The report

A player's v0.31.0 log, under Proton by the player's account:

```
ESCAPE_HELD mappings=3 actions=0:9,0:73,12:0
MODAL_OPEN scope=planet key=F7 screens=15
STOPPED: mods/ipodalexei/mission_reroller_experiment.lua:6067: unexpected target page
ESCAPE_RESTORED buckets=3
MODAL_RELEASE error
```

F7 opened the dialog. On the next frame the dialog read the planet's
snapshot, and one of the four page checks in `snapshot`
(`src/experiment_adapter.lua`) failed. The failure was not caught, so the
mod stopped for the session. To the player, the panel closed at once and
F7 did nothing afterwards.

The message did not say which page failed. The Escape write had just
passed the same check on a private heap page, so the suspect is the only
module-image page: `rng_state`, a variable in `game.dll`'s data section,
which must be `MEM_IMAGE` and `PAGE_READWRITE`. Wine can report a module's
data page as `PAGE_WRITECOPY` (8) where Windows reports `PAGE_READWRITE`
(4). This is unconfirmed.

## What changed

- `page()` takes a name, and its error now gives the values `VirtualQuery`
  returned: `unexpected target page: rng_state state=0x1000 protect=0x8
  type=0x1000000 want=0x1000000 span=true`.
- A module-image page may be `PAGE_WRITECOPY`. Only `rng_state` is checked
  that way, and the mod only reads it. Private pages, every write target
  among them, still need `PAGE_READWRITE`.
- The dialog catches a failed snapshot. It logs `SNAPSHOT_BLOCKED <error>`
  once per distinct error and shows `PLANET DATA UNAVAILABLE`, or keeps the
  retained data as for any short gap. Nothing can start from it. The
  search and the publication take their own snapshots and still stop the
  mod on a failure.

## Test on Proton

1. Deploy the development build with the loader, launch through Proton,
   open the galactic map on a planet and press F7.
2. Pass: the panel stays open and lists the planet's missions, and the log
   has `MODAL_OPEN` with no `STOPPED:` and no `SNAPSHOT_BLOCKED`. Run one
   search to the end: `DIALOG_SEARCH`, then a match published as on
   Windows.
3. If the panel shows `PLANET DATA UNAVAILABLE`: the log's
   `SNAPSHOT_BLOCKED` line names the page and its protection and type.
   Close and reopen with F7: the panel opens again, which shows the mod
   kept running. Send the line; it decides the next change.
4. If a search stops with `STOPPED: … unexpected target page: <name> …`,
   the dialog's checks passed and a later one did not. Send the line.

## Test on Windows

Repeat steps 1 and 2. Pass: the same lines as v0.32.0, and no
`SNAPSHOT_BLOCKED` line.
