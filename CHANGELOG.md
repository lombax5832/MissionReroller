# Mission Reroller changelog

What changed for players in each published version, newest first. The
release workflow posts a version's bullets, without the heading, as the
GitHub release notes and, as one plain-text line each, the Nexus Mods
changelog. How each change was
made and tested is in the development log, [docs/HISTORY.md](docs/HISTORY.md).

## v0.33.2 Shorter description

- The description shown in Arsenal and HD2MM is now a short summary: what
  the mod does, the F7 shortcut and the loader it needs.

## v0.33.1 Operation Reroller name

- The mod is now called Operation Reroller in Arsenal and HD2MM, and its
  download is Operation-Reroller-v0.33.1.zip. It replaces Mission Reroller
  in your mod manager as an update; nothing in game changes.

## v0.33.0 Time of day tiles

- Time of day is now picked with three tiles on its section heading, Any,
  Day and Night, with the galactic map's sun and moon on Day and Night,
  instead of a dropdown.
- The chosen Day or Night tile says how long the mission stays on that side
  after the reroll, at least 2h 30m, or less on planets and moons with short
  days. It turns amber while the planet's sky loads and red when no city on
  the planet can hold that side.
- Checking the first mission discards the rules set under Any mission, and
  unchecking a mission discards its own. The Enemy forces or Side objectives
  heading that lost rules now turns red and says Mission changed until you
  click it or Clear.
- A mission is no longer dimmed by Any mission rules that checking it would
  discard, so excluding every enemy force no longer locks out every mission.
- Excluding so many side objectives that a mission cannot fill its slots is
  now refused up front, instead of starting a search that could never match.

## v0.32.1 Proton fix

- Fixed the reroll panel closing as soon as it opened when playing through
  Proton on Linux or Steam Deck, after which the shortcut did nothing until
  the game was restarted.
- If the panel cannot read the planet's data it now says Planet data
  unavailable and stays open, instead of shutting the mod down.

## v0.32.0 Enemy units without Know Your Constellation

- Pointing at an enemy force now shows the units a mission with it can
  spawn, with a spawn-rate meter for each large enemy, even without Know
  Your Constellation installed. The unit data is Know Your Constellation's
  own, included with CowboyBingus's permission.
- With a Know Your Constellation installed that shares its roster, that
  copy is still used first.

## v0.31.0 Side objectives

- New Side objectives section: require or exclude side objectives such as
  Lidar Station, SEAF Artillery, Stalker Lair or Stratagem Jammer, per
  checked mission or for the whole operation. A mission must have every
  required one and none of the excluded ones.
- Tactical objectives such as Terminate Illegal Broadcast and Upload Escape
  Pod Data are in the same section, listed under their own Tactical heading
  below the side objectives.
- The list shows only what each mission can draw on the viewed planet at the
  map difficulty, with its number of side and tactical objectives. A row
  that no longer fits is dimmed; point at it to read why.
- The panel's rows sit a little closer together to make room for the new
  section.

## v0.30.0 Planets under attack

- Planets under attack (invasions) can now be rerolled. Searching on one
  used to show Retrying changed planet data and end in a capture timeout.
- Special operations on a planet under attack now match the game's board.
- Defended planets are still not supported.

## v0.29.0 Exclude missions

- Missions can now be excluded. Click a mission row to cycle Any, Required,
  Excluded; the matched operation will contain no excluded mission.
- Excluded missions take no slot, and excluding missions alone is enough to
  start a search.
- A mission that cannot be added next to the missions you require stays
  dimmed, as before; point at it to read why.
- A mission that every operation on the planet contains cannot be excluded,
  so its row goes from Required straight back to Any.
- Works alongside mods that refresh an operation's missions without a
  reroll, such as Refresh Operations + Missions. Rerolling no longer stops
  with a mismatch after such a refresh, and the refreshed operation is
  replaced by the reroll like any other.

## v0.28.0 Know Your Constellation names and unit tooltips

- Enemy forces use the same names as Know Your Constellation, for example
  Spore Burst Strain, Cyborg Legion, Appropriators and Balanced Terminids.
- Bile Bugs, Hunter Swarms and Predator Strain are marked with an asterisk:
  the map can still add them after a reroll, so excluding them is not a
  guarantee. Point at one to read why.
- With a Know Your Constellation version that shares its forecast
  installed, pointing at an enemy force shows the enemies a mission would
  have with it and the planet's always-present forces: large enemies with a
  spawn-rate meter, then the rest, most common first.

## v0.27.0 Day or night

- New TIME OF DAY section in the panel: Any time, Day or Night.
- With Day or Night, the matched operation's missions stay on that side for
  2.5 hours after the reroll, clear of the 30 minutes around dawn and dusk.
- On planets and moons whose days are too short for that, the filter holds
  for half of a day or night instead, and the panel says how long.
- When only a city can match and it is on the wrong side, the panel counts
  down to when it will be ready instead of searching.

## v0.24.0 Fixes

- Fixed the panel showing NO PLANET CHOSEN on planets such as Brilliance and
  Fronteria; their options now list normally.
- Fixed the game stuttering for a few seconds after clicking Reroll
  operations.
- Fixed a search that could show "running" forever; it now ends with "Seed
  prediction unavailable for this planet".

## v0.22.0 Works alongside other mods

- Fixed potential conflict preventing this mod from working when other mods
  are installed.
- Added support for Mod Bindings Menu.
- Default keybind changed to F7.
