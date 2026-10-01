# Mission Reroller changelog

What changed for players in each published version, newest first. The
release workflow posts a version's bullets, without the heading, as the
GitHub release notes and, as one plain-text line each, the Nexus Mods
changelog. How each change was
made and tested is in the development log, [docs/HISTORY.md](docs/HISTORY.md).

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
