# Invaded planet test

Planets under an invasion ("under attack") stopped every search with
"Retrying changed planet data" and then a capture timeout
(`LUA_CAPTURE_RETRY … Unsupported invasion operation bases`). The port did
not generate their operations. This build generates them as the game does.

## What the game does

`12d5550` regenerates a planet's board with three passes sharing one RNG:

- `11e3c10`, the normal operations, returns at once for a planet the
  campaign's invasion list (`campaign.invasions`, 0x48 bytes, planet at +4)
  names.
- `11e4060` then fills the same rows with the same draws as the normal
  pass, once per event record (`campaign.invasion_events`, 16 bytes: +4
  planet, +12 invasion id) of the planet. Only the base fields differ:
  - the category is `+0` of the invasion level's row in
    `invasion_levels` (level is the invasion's `+8`, capped at 3); a
    category of 14 generates nothing;
  - the faction is the invasion's `+12` (1 becomes 2);
  - the record writes the invasion's `+0x28` at operation `+0x14` and the
    event record's `+0` at `+0x28`, and -1 at `+0x2c`. No ported step reads
    them.
- `11e44d0`, the special operations, resolves a definition category of 14
  through `174ab50`: 12 when the definition's `+0x18` is not 1, otherwise
  8 when the planet's first invasion is at level 1 (or the special faction
  is 1, which the port rejects), else 9. The port had always assumed 9.

The normal pass's checks (planet enabled, one campaign base, no defence, no
operation-suppressing world modifier) do not apply to an invaded planet.
`src/operation_base_inputs.lua` fails closed on any shape it has not seen:
more than one event record for the planet, an event record without an
invasion listing, an invasion of another planet, or a level whose category
is 14. Defence events stay unsupported.

## Offline evidence

`artifacts/invasion-live-173` is a read-only capture taken through Memory
Explorer on 2026-10-02 of planet 173 at seed 1966000: one level-1 Terminid
invasion (category 4, faction 2) and ten special operations. All 40
operations, their templates, modifiers and 96 missions equal the prediction,
and the dialog's options build at every difficulty (`tests/test_dialog.py`
replays it when the artifact exists).

## In-game test

Install the branch build with the loader, deploy, launch.

1. Start the game.
   - Pass: `mods/ipodalexei/mission_reroller_experiment: loaded` in
     `BingusSharedLoader.log` and
     `build=25480438 hashes=verified signatures=47 anchors=79 verified` in
     `MissionRerollerExperiment.log`.
   - Fail: any `STOPPED:` line (send it).
2. Open a planet under attack, press F7, pick a mission the dialog offers
   and start a search. Wait for the match.
   - Pass: no `LUA_CAPTURE_RETRY`; `PREDICTION_CHECK descriptors_match=true`,
     then `PREDICTION_VERIFIED` and `PUBLICATION_STATE_VERIFIED`, and the
     matching operation is selected.
   - Fail: `LUA_CAPTURE_RETRY … Unsupported invasion …` or
     `LUA_CAPTURE_DETAIL` (send the line), `PREDICTION_CHECK
     descriptors_match=false`, `RESTORE_SEED` or `STOPPED:`.
3. Repeat step 2 on a normal planet.
   - Pass and fail as in step 2.
4. Hover a mission of the selected invasion operation.
   - Pass: a `CONSTELLATION_CHECK … agree=` line.

## Result, 2026-10-02

Run by the user with the branch build (banner `Mission Reroller 0.29.0`):

- Step 1 passed: `mods/ipodalexei/mission_reroller_experiment: loaded` and
  `build=25480438 hashes=verified signatures=47 anchors=79 verified`.
- Step 2 passed on two invaded planets, with no `LUA_CAPTURE_RETRY`:
  - planet 173 (Terminids): `LUA_SEED_PREDICTION_PASS planet=173
    seed=102427943 bases=40 operations=40 missions=96`, a search requiring
    three missions matched at `seed=102427967 row=39`, then
    `PREDICTION_CHECK descriptors_match=true`,
    `PREDICTION_VERIFIED selected_row=39 active_preserved=true` and
    `PUBLICATION_STATE_VERIFIED seed=102427967 row=39
    map_ui_row_confirmed=true`;
  - planet 245 (Automatons): `LUA_SEED_PREDICTION_PASS planet=245 … bases=40
    operations=40 missions=96` three times, each ending in `EXISTING_MATCH`
    and `PUBLICATION_STATE_VERIFIED`.
- Step 3 passed on planets 201 and 270, each published with
  `PREDICTION_CHECK descriptors_match=true` and
  `PUBLICATION_STATE_VERIFIED`.
- Step 4 passed: `CONSTELLATION_CHECK … agree=true` on rows of both invaded
  planets.
