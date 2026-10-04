# Mission Reroller

A Helldivers 2 mod that rerolls the operations on a planet's war table until
one matches what you want to play: the mission types it must or must not
contain, the operation modifiers it must or must not have, the enemy forces each
mission must or must not carry, the side objectives each mission must or must
not have, and whether it lands in the day or the night. It runs inside the game's Lua VM as an addon
for [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader).

Download the latest release from
[GitHub](https://github.com/lombax5832/MissionReroller/releases/latest) or
[Nexus Mods](https://www.nexusmods.com/helldivers2/mods/16762).

## Requirements

- Helldivers 2 on Steam, build **25480438**. The mod checks the game's module
  hashes and code signatures before it does anything, and stops with a logged
  reason when they do not match. After a game update, wait for a new release.
- Bingus Shared Loader **v16 or newer** (API 1), enabled and deployed as the
  winning startup override. In Arsenal that is the bottom of the default
  order.
- A mod manager that imports patch ZIPs: Arsenal or HD2MM.
- Optional: [Mod Bindings Menu](https://github.com/CowboyBingus/ModBindingsMenu)
  v2.0 or newer, to rebind the shortcut on the game's own MODS binding tab.

## Install

1. Import the loader ZIP and the `Mission-Reroller-v<version>.zip` into your mod
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
2. Press **F7** on the galactic map. A panel docks to the right edge of the
   screen. The map does not react while it is open. The shortcut does
   nothing anywhere else, including with the options or ESC menu open over
   the map. A key hint beside the war table's BACK hint shows the shortcut.
   With Mod Bindings Menu installed, the mod also registers **Reroll
   operations** under Mission Reroller on the MODS tab of Options > Mouse &
   Keyboard. Bind a key there and it replaces F7, and the hint shows it.
   While that row has no key, F7 stays the shortcut.
3. Choose what the operation must contain. The five sections open one at a
   time:
   - **Missions.** Click a row to cycle ANY, REQUIRED, EXCLUDED. Require up
     to the number of slots an operation has; all required missions must fit
     in one operation. An excluded mission takes no slot, and the matched
     operation contains none of it. A mission that cannot be added next to
     the required ones is dimmed; point at it to read why. A mission every
     operation here contains cannot be excluded, so its click skips
     EXCLUDED.
   - **Modifiers.** Click a row to cycle ANY, REQUIRED, EXCLUDED.
   - **Enemy forces.** One button per checked mission, or `ANY MISSION` when
     none is checked. Each constellation cycles ANY, ACCEPTED, EXCLUDED. The
     list shows only what that mission can draw at the map difficulty, named
     as Know Your Constellation names them. A `*` marks a constellation the
     map can still add after the reroll; point at it to read why. Pointing
     at any constellation shows the enemies a mission would have with it and
     the planet's always-present forces: large enemies with their spawn-rate
     meter and the others most common first, from
     [Know Your Constellation](https://github.com/CowboyBingus/KnowYourConstellation)'s
     roster. An installed version of that mod that shares its roster is used
     first; otherwise Mission Reroller uses the copy of its v4.0 roster it
     bundles.
   - **Side objectives.** One button per checked mission, or `ANY MISSION`
     when none is checked. Each side objective, such as Lidar Station or
     SEAF Artillery, cycles ANY, REQUIRED, EXCLUDED. The mission must have
     every required one and none of the excluded ones; with `ANY MISSION`,
     each required one must be on some mission of the operation and no
     mission may have an excluded one. Side objectives are listed under
     SIDE and the tactical objectives (Terminate Illegal Broadcast, Upload
     Escape Pod Data and the like) under TACTICAL; a few are side on some
     missions and tactical on others, and `ANY MISSION` lists those under
     SIDE. The list shows only what that mission can draw on this planet at
     the map difficulty. The line under the buttons shows how many side and
     tactical objectives the mission has; a row that no longer fits, or that
     would leave nothing to draw, is dimmed, and pointing at it says why.
   - **Time of day.** ANY, DAY or NIGHT, picked straight from the section's
     heading. With Day or Night, every mission of the match stays on that
     side for 2.5 hours after the reroll, clear of dusk and dawn. The line
     under the heading shows how long it holds and how long the planet's
     day is; on planets and moons with short days it holds for less, and
     says so. With a very long list of side objectives open, that line
     makes room for the list.
4. Press **REROLL OPERATIONS**. The mod searches campaign seeds inside the
   game, up to 1,000,000 per request, showing its four steps and the seeds
   searched. On a match it publishes the seed, verifies the regenerated
   board, closes the panel and opens the matching operation. The difficulty
   is the one set on the map.
5. **CANCEL SEARCH** stops a search. **CLEAR** resets the choices. **CLOSE**,
   Escape or the shortcut closes the panel. Escape closes only the panel: the
   war table does not go back as well.

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
- **Side objectives follow the game's own draw.** The mod computes them
  from each mission's seed the way the game does when it builds the mission.
  Eradicate, Evacuate High-Value Assets and Rapid Acquisition, and every
  mission at difficulty 1, have none. Hovering a mission on the war table
  logs a `SIDE_OBJECTIVE_CHECK` line comparing the prediction with the
  game's list.
- **Day and night move, cities do not.** Each planet turns under its sun,
  so a mission's time of day changes as you play. The war table shows the
  local time when you hover a planet (`SEST`). A reroll moves most missions
  but not a city's, so when only a city can match and it is on the wrong
  side, the panel says when it will be ready (`NIGHT HERE IN 3H 10M`) instead
  of searching. Dusk and dawn, 30 minutes either side of 18:00 and 06:00,
  count as neither.
- **The panel takes the mouse and Escape only.** Other keys still reach the
  game. While the panel is open the game's own Escape bindings are set aside
  and come back when it closes and Escape is released.

## Troubleshooting

The mod's log is `MissionRerollerExperiment.log` in
`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs`.

| Symptom | Where to look |
| --- | --- |
| Nothing happens on F7 | `BingusSharedLoader.log` must show the `loaded` line above. If it does not, the loader is not the winning startup override. The shortcut only works with the galactic map on screen; a `SHORTCUT_IGNORED` line in the mod's log lists the screens that were open. If you bound a key on the MODS tab, F7 no longer opens the panel. |
| The MODS tab has no Mission Reroller section | The mod's log has a `BINDING_FAILED` line with the reason Mod Bindings Menu gave, such as all 36 bindings in use. F7 still works. |
| The hint beside BACK shows F7 after binding another key | The hint reads the game's live binding once Mod Bindings Menu reports native input ready. If it never changes, send the `BINDING_REGISTERED` line from the mod's log. |
| The panel shows `OPEN A PLANET ON THE WAR TABLE FIRST` | View a planet, then reopen the panel. |
| The panel shows `WAITING FOR THE SKY OF THE VIEWED PLANET` with a time of day chosen | The war table has not drawn the planet yet. Wait a moment with the planet in view. A `DAYNIGHT_BLOCKED` line in the mod's log gives the reason if it stays. |
| The panel shows `UPDATING PLANET DATA` for long | The game is waiting on the backend. Your choices are kept; the search starts on fresh data. |
| The panel shows `PLANET DATA UNAVAILABLE` | A check of the game's memory failed, so the panel offers nothing to search. The mod's log has a `SNAPSHOT_BLOCKED` line naming the check and the values found. Send it with a bug report, and say if you play through Proton or on Linux. |
| Escape also takes the war table back | The mod's log has an `ESCAPE_BLOCKED` line with the reason, or `ESCAPE_HELD mappings=0` if the game has no Escape binding to set aside. Send the line. The panel still closes on Escape. |
| The panel shows `OPERATIONS DIFFER FROM THE PREDICTION; SEE THE LOG` or says another mod may have changed these operations | The planet's operations are not the ones its seed gives. Mods that refresh operations without a reroll, such as Refresh Operations' F6, cause this when they changed the planet before Mission Reroller saw it: open the planet for a moment before using them, and Mission Reroller accepts their changes (`LUA_IDENTITY_EXTERNAL_EDIT` lines). Otherwise send the `LUA_IDENTITY_DETAIL` and `LUA_IDENTITY_NOT_EXTERNAL` lines. |
| The log has a `STOPPED:` line | The mod found something it did not expect and released the mouse without writing anything further. Send the line with a bug report. |
| `game.dll hash mismatch` or `executable hash mismatch` | The game was updated. Wait for a release for the new build. |
| `offset signature <name> mismatch` or `offset anchor <name> mismatch` | The game files are the supported build, but the code the mod relies on differs in memory, usually because another mod changed it. Send the line with a list of your mods. |

When reporting a problem, include both logs. Near the top, the mod's log
names its version (`Mission Reroller <version> docked dialog`) and, from the
first frame, every Lua mod the loaders started: a `MODS` count, then one
`MOD <name> version=<version> status=<status>` line each. A version reads
`unknown` when that mod does not publish one.

## Building from source

Requires Python 3, the `BingusSharedLoader` source next to this folder (or
`BINGUS_LOADER_ROOT`), and LuaJIT (`HD2_LUAJIT`). One dialog test reads
recorded seeds from a `KnowYourConstellation` checkout next to this folder.

```powershell
python -B scripts/build.py          # releases/Mission-Reroller-Dev-v<version>.zip
python -B tests/test_package.py     # package checks, then the dialog tests
```

A local build is named Mission Reroller Dev and has its own GUID, so your mod
manager lists it beside the published mod; enable only one of the two. Setting
`RELEASE_TAG=v<version>` builds the published package instead.

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
  [constellation filter test](docs/CONSTELLATION_FILTER_TEST.md);
  [Know Your Constellation tooltip test](docs/KYC_TOOLTIP_TEST.md) and the
  [bundled roster test](docs/BUNDLED_ROSTER_TEST.md).
- [Hosting a lobby](docs/LOBBY_HOST_TEST.md) and the
  [docked dialog](docs/DOCKED_DIALOG_TEST.md).

The unit tooltips call the roster that an installed Know Your Constellation
exports, or else the copy of Know Your Constellation v4.0's `roster.lua` and
`roster_data.lua` in `src/vendor/know_your_constellation`, included with
CowboyBingus's permission. No other part of that mod's source, data or
artwork is embedded or redistributed here; the reference checkout is read by
one test.
