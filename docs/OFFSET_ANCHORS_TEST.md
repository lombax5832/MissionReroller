# Offset anchors and the two stale tables: in-game test

This branch changes what the first frame checks and fixes two addresses.
Nothing else a player sees should change.

## What changed

Two static tables in `src/offsets.lua` held build 25327279 addresses, marked
`unverified=true` so nothing checked them:

| Global | Was | Now | Anchor |
|---|---|---|---|
| `environment_tags` | `0x21df8b8` | `0x21df8d0` | `lea r11` at `0x177e712`, inside `template_environments` |
| `invasion_modifiers` | `0x32ef71c` | `0x32ef77c` | `lea rax` at `0x12676f9`, the table's only reference |

In each build the code addresses its own value, and the 40-byte and
0x120-byte tables are byte-identical between the old and the new address.
Found by an update rehearsal of `scripts/check_offsets.py` against the
25327279 dump. With the old values the tag table read six unrelated words
first, so a campaign effect that adds an environment tag matched the wrong
tag or none, and an invading planet's world modifier was read 0x60 bytes
early. Both feed `src/template_environments.lua`, so predictions of
modifiers and templates that depend on environment tags could be wrong on
such planets.

The first frame now also checks:

- ten more code entries (47 in all): the game functions the Lua ports or
  mirrors, hashed over their whole function, and `planet_lookup` over its
  whole function instead of its first 64 bytes;
- 51 struct fields anchored to one instruction, besides the 26 globals
  (77 anchors in all).

## Setup

Build from this branch (`python -B scripts/build.py`), import the ZIP and the
loader into Arsenal or HD2MM, keep the loader as the winning startup
override, Purge / Deploy, launch. Read `BingusSharedLoader.log` and
`MissionRerollerExperiment.log` from
`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs`.

## Steps

1. Reach the ship and open the galactic map.
   - Pass: `mods/ipodalexei/mission_reroller_experiment: loaded` in
     `BingusSharedLoader.log`, and
     `build=25480438 hashes=verified signatures=47 anchors=77 verified`
     in the mod's log.
   - Fail: `STOPPED: … offset signature <name> mismatch` or
     `STOPPED: … offset anchor <name> mismatch` (send the line), or any
     other `STOPPED:` line.
2. View a planet under an active invasion or defence, press F7, pick a
   mission filter and start a search. Wait for the match to publish.
   - Pass: `PREDICTION_CHECK descriptors_match=true`, then
     `PREDICTION_VERIFIED` and `PUBLICATION_STATE_VERIFIED`.
   - Fail: `PREDICTION_CHECK descriptors_match=false` (send the line and
     the planet), `RESTORE_SEED` or `STOPPED:`.
3. Repeat step 2 on a planet with a planetary hazard listed in its info
   panel, filtering on a modifier if the dialog offers one.
   - Pass and fail as in step 2.
4. Hover a mission of the selected operation.
   - Pass: a `CONSTELLATION_CHECK … agree=` line.
   - Fail: `CONSTELLATION_CHECK_BLOCKED`.

## Result, 2026-10-01

Run by the user with the branch build (banner `Mission Reroller 0.28.0`):

- Step 1 passed: `mods/ipodalexei/mission_reroller_experiment: loaded` and
  `build=25480438 hashes=verified signatures=47 anchors=77 verified`; no
  `STOPPED:` line.
- Steps 2 and 3, as far as the war table allowed: no planet had an active
  invasion, so `invasion_modifiers` was not exercised in game. A search on
  planet 215 requiring two modifiers and Geological Survey ended in
  `PREDICTION_CHECK descriptors_match=true`,
  `PREDICTION_VERIFIED selected_row=27 active_preserved=true` and
  `PUBLICATION_STATE_VERIFIED … map_ui_row_confirmed=true`. The log does not
  show whether that planet had an environment-tag effect.
- Step 4 passed: three `CONSTELLATION_CHECK … agree=true` lines.

Still open: a prediction on an invaded planet, for `invasion_modifiers`.
