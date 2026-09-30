# v0.25.0 central offsets: in-game test

v0.25.0 reads every address from `src/offsets.lua` and checks all of its
code entries and global anchors on the first frame. Nothing a player sees
should change. v0.24.0 (runtimes on a host) is still unvalidated; this run
covers it too, so also follow [RUNTIME_HOST_TEST.md](RUNTIME_HOST_TEST.md)
steps 2 to 4 if time allows.

## Setup

Import `releases/Mission-Reroller-v0.25.0.zip` and the loader into Arsenal
or HD2MM, keep the loader as the winning startup override, Purge / Deploy,
launch. Read `BingusSharedLoader.log` and `MissionRerollerExperiment.log`
from `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs`.

## Steps

1. Reach the ship and open the galactic map.
   - Pass: `BingusSharedLoader.log` shows
     `mods/ipodalexei/mission_reroller_experiment: loaded`; the mod's log
     shows `Mission Reroller 0.25.0 docked dialog` and
     `build=25480438 hashes=verified signatures=33 anchors=24 verified`,
     then `LUA_IDENTITY_READY signatures=verified`.
   - Fail: `STOPPED: … offset signature <name> mismatch` or
     `offset anchor <name> mismatch` (send the line), or any other
     `STOPPED:` line.
2. View a planet, press F7, pick one mission filter and start a search.
   Wait for the match to publish and the operation to be selected.
   - Pass: `PUBLISH_BEGIN`, `PUBLISH_RETURN active_preserved=true`,
     `PREDICTION_CHECK descriptors_match=true`, `PREDICTION_VERIFIED`, and
     `PUBLICATION_STATE_VERIFIED … map_ui_row_confirmed=true`. The war table
     shows the matching operation selected.
   - Fail: `PUBLICATION_BLOCKED … signature changed`, `RESTORE_SEED`, or
     `STOPPED:`.
3. Hover a mission of the selected operation.
   - Pass: a `CONSTELLATION_CHECK … agree=` line (the constellation reads
     go through the level controller and stamp offsets).
   - Fail: `CONSTELLATION_CHECK_BLOCKED`.
4. Open the panel again and close it with Escape.
   - Pass: the key hint sits beside BACK; `ESCAPE_HELD` then
     `ESCAPE_RESTORED`; the war table does not go back.

The startup counts in step 1 are the number of `code` entries and of
anchored `globals` in `src/offsets.lua`; they change when entries are
added.
