# Mission Reroller

A Helldivers 2 mod that rerolls the operations on a planet's war table until
one matches what you want to play: the mission types it must contain, the
operation modifiers it must or must not have, and the enemy forces each
mission must or must not carry. It runs inside the game's Lua VM as an addon
for [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader).

Current release: **v0.20.2**, `releases/Mission-Reroller-v0.20.2.zip`
([GitHub release](https://github.com/lombax5832/MissionReroller/releases/tag/v0.20.2)).

## Requirements

- Helldivers 2 on Steam, build **25480438**. The mod checks the game's module
  hashes and code signatures before it does anything, and stops with a logged
  reason when they do not match. After a game update, wait for a new release.
- Bingus Shared Loader **v16 or newer** (API 1), enabled and deployed as the
  winning startup override. In Arsenal that is the bottom of the default
  order.
- A mod manager that imports patch ZIPs: Arsenal or HD2MM.

## Install

1. Import the loader ZIP and `Mission-Reroller-v0.20.2.zip` into your mod
   manager and enable both.
2. Keep the loader last in the load order, then Purge and Deploy.
3. Launch the game. `BingusSharedLoader.log` in
   `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs` should contain
   `mods/ipodalexei/mission_reroller_experiment: loaded`.

To update, import the new ZIP in place of the old one; every release shares
the same GUID, so your manager treats it as the same mod.

## Use

1. On the war table, view the planet you want to play. You do not have to be
   in orbit: rerolling works for the planet you are viewing. To reroll only
   a city's operations, point at the city's operation marker or select it
   first; the panel header then reads `THIS CITY ONLY`.
2. Press **Ctrl+Shift+F8**. A panel docks to the right edge of the screen.
   The map does not react while it is open.
3. Choose what the operation must contain. The three sections open one at a
   time:
   - **Missions.** Check up to the number of slots an operation has. All
     checked missions must fit in one operation, so a mission that cannot be
     added is dimmed; point at it to read why.
   - **Modifiers.** Click a row to cycle ANY, REQUIRED, EXCLUDED.
   - **Enemy forces.** One button per checked mission, or `ANY MISSION` when
     none is checked. Each constellation cycles ANY, ACCEPTED, EXCLUDED. The
     list shows only what that mission can draw at the map difficulty.
4. Press **REROLL OPERATIONS**. The mod searches campaign seeds inside the
   game, up to 262,144 per request, showing its four steps and the seeds
   searched. On a match it publishes the seed, verifies the regenerated
   board, closes the panel and opens the matching operation. The difficulty
   is the one set on the map.
5. **CANCEL SEARCH** stops a search. **CLEAR** resets the choices. **CLOSE**
   or Ctrl+Shift+F8 closes the panel; Escape does not.

If no seed matches within the budget, the panel reads `No match; search
again to continue`. Searching again with an unchanged request continues
where the last search stopped, and widening the request helps.

### In a lobby

The host of a lobby of up to four can reroll. The game sends the new seed to
every player, so their war tables change too; the other players do not need
the mod. A guest who opens the panel is told `ONLY THE HOST CAN REROLL
OPERATIONS`. Tell your lobby before you reroll. Tested with two players.

## What to know before you use it

- **One seed per campaign.** Rerolling regenerates every unstarted operation
  on every planet, not only the ones you filtered for, for you and for your
  lobby. Operations already in progress are not touched and are reported as
  not rerollable.
- **The mod writes to the game's memory** in its own process, only to
  existing data pages, only after its checks pass, and never to code. It
  makes no network requests of its own; the seed reaches the backend and
  other players through the game's normal synchronisation.
- **No claim is made** that the backend accepts the result or that the
  game's policy allows it. Use it at your own risk.
- **Enemy force exclusions are predictions.** The game can add a
  constellation to a mission through a map stamp after generation. On
  Terminid missions that can be `BugAcid`, `BugPredators` or
  `GM_BugSuperPredators`, so excluding those is not a guarantee. Planet-wide
  forces, such as a strain, cannot be changed by rerolling and are listed as
  always present.
- **Illuminate missions and difficulty 1** draw no constellations, so their
  enemy force lists are empty.
- **The panel takes the mouse only.** Keyboard input still reaches the game.

## Troubleshooting

The mod's log is `MissionRerollerExperiment.log` in
`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs`.

| Symptom | Where to look |
| --- | --- |
| Nothing happens on Ctrl+Shift+F8 | `BingusSharedLoader.log` must show the `loaded` line above. If it does not, the loader is not the winning startup override. |
| The panel shows `OPEN A PLANET ON THE WAR TABLE FIRST` | View a planet, then reopen the panel. |
| The panel shows `UPDATING PLANET DATA` for long | The game is waiting on the backend. Your choices are kept; the search starts on fresh data. |
| The log has a `STOPPED:` line | The mod found something it did not expect and released the mouse without writing anything further. Send the line with a bug report. |
| `game.dll hash mismatch` or `executable hash mismatch` | The game was updated. Wait for a release for the new build. |

When reporting a problem, include both logs and the `Mission Reroller 0.20.2`
line near the top of the mod's log.

## Building from source

Requires Python 3, the `BingusSharedLoader` source next to this folder (or
`BINGUS_LOADER_ROOT`), and LuaJIT (`HD2_LUAJIT`). One dialog test reads
recorded seeds from a `KnowYourConstellation` checkout next to this folder.

```powershell
python -B scripts/build.py          # releases/Mission-Reroller-v<version>.zip
python -B tests/test_package.py     # package checks, then the dialog tests
```

`scripts/README.md` lists the release builder, the research builders kept for
bisecting, and the analysis tools. No game binaries, extracted resources or
research captures enter the package or the repository.

## How it works, and its history

The mod ports the game's operation generator to Lua: from a campaign seed and
the campaign state it predicts every operation a planet would show, so it can
test seeds without touching the game until one matches. The prediction was
validated against thousands of live and recorded operations before the mod
was allowed to write anything.

- [Development log](docs/HISTORY.md), newest first, with links to each
  in-game test.
- [Research status](docs/RESEARCH.md) and
  [remaining native adapter requirements](docs/ADAPTER.md).
- [Seed lifecycle](docs/SEED_LIFECYCLE.md) and
  [operation layout](docs/OPERATION_LAYOUT.md).
- [Constellation research](docs/CONSTELLATION_RESEARCH.md) and the
  [constellation filter test](docs/CONSTELLATION_FILTER_TEST.md).
- [Hosting a lobby](docs/LOBBY_HOST_TEST.md) and the
  [docked dialog](docs/DOCKED_DIALOG_TEST.md).

The reference Know Your Constellation checkout is read by one test; none of
its source or artwork is embedded or redistributed here.
