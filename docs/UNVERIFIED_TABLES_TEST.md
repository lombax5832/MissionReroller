# Environment tag and invasion tables: in-game test

Two static tables in `src/offsets.lua` held build 25327279 addresses, marked
`unverified=true` so nothing checked them:

| Global | Was | Now | Anchor |
|---|---|---|---|
| `environment_tags` | `0x21df8b8` | `0x21df8d0` | `lea r11` at `0x177e712`, inside `template_environments` |
| `invasion_modifiers` | `0x32ef71c` | `0x32ef77c` | `lea rax` at `0x12676f9`, the table's only reference |

In each build the code addresses its own value, and the 40-byte and
0x120-byte tables are byte-identical between the old and the new address.
Found by an update rehearsal of `scripts/check_offsets.py` against the
25327279 dump.

What the old values did: the tag table read six unrelated words first, so a
campaign effect that adds an environment tag matched the wrong tag or none;
an invading planet's world modifier was read 0x60 bytes early. Both feed
`src/template_environments.lua`, so predictions of modifiers and templates
that depend on environment tags could be wrong on such planets. Planets
without those effects or an invasion are unaffected.

## Setup

Build from this branch (`python -B scripts/build.py`), import the ZIP and the
loader into Arsenal or HD2MM, keep the loader as the winning startup
override, Purge / Deploy, launch. Read `BingusSharedLoader.log` and
`MissionRerollerExperiment.log` from
`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs`.

## Steps

1. Reach the ship and open the galactic map.
   - Pass: `build=25480438 hashes=verified signatures=37 anchors=26 verified`
     (two more anchors than v0.28.0).
   - Fail: `STOPPED: … offset anchor environment_tags mismatch` or
     `… invasion_modifiers mismatch`, or any other `STOPPED:` line.
2. View a planet under an active invasion or defence, press F7, pick a
   mission filter and start a search. Wait for the match to publish.
   - Pass: `PREDICTION_CHECK descriptors_match=true`, then
     `PREDICTION_VERIFIED` and `PUBLICATION_STATE_VERIFIED`.
   - Fail: `PREDICTION_CHECK descriptors_match=false` (send the line and
     the planet), `RESTORE_SEED` or `STOPPED:`.
3. Repeat step 2 on a planet with a planetary hazard listed in its info
   panel, filtering on a modifier if the dialog offers one.
   - Pass and fail as in step 2.
