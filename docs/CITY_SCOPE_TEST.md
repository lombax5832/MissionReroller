# Cities and megafactories — v0.17.0, all mission types — v0.18.0

## Result, 2026-09-29 session (v0.17.0)

The log shows `MODAL_OPEN scope=region 0` on planet 253 and `scope=planet`
with the cursor elsewhere, so the city is recognised in game. The user then
reported that the city's operation held Halt Cyborg Production and Sabotage
Air Base and that the dialog offered neither. Two causes were found through
the read-only bridge:

- The dialog knew twelve mission families. v0.18.0 knows every mission type
  that has a title: 126 types in 74 families.
- That operation, row 39, was the operation in progress. The game keeps its
  seed and missions whatever the campaign seed becomes, so no search can
  change it. v0.18.0 says so and does not start a search for it.

## Result, 2026-09-29 session (v0.18.0)

City operations are now published and selected in game. On planet 253 three
searches limited to region 0 matched, published and selected row 39, each
with `PUBLICATION_STATE_VERIFIED … map_ui_row_confirmed=true`:

| Missions required | Seeds |
| --- | --- |
| Spread Democracy, Halt Cyborg Production | 6 |
| Spread Democracy, Halt Cyborg Production, Neutralize Ground-to-Orbit Defenses | 25 |
| Spread Democracy, Halt Cyborg Production, Sabotage Air Base | 284 |

Two of those families were not in the list before v0.18.0. The log also
shows `MODAL_OPEN scope=region 2` on another planet.

## Install

Install `releases/Mission-Reroller-v0.19.0.zip` in place of the previous package,
Purge / Deploy, and restart. Remain alone on your ship for this supervised test.
This build contains the [fast seed search](FAST_SEARCH_TEST.md), its timing
lines and the [per-mission constellations](CONSTELLATION_FILTER_TEST.md).

## What is new

A city or megafactory appears on the planet as its own operation marker. Open
the dialog with Ctrl+Shift+F8 **while the cursor is on that marker**, or after
selecting that operation, and the dialog is limited to that city:

- The subtitle reads `… / This city or megafactory only`.
- Missions, modifiers and constellations list only what that city's operation
  can have at the map difficulty.
- The search accepts only that city's operation, and opens it on a match.

The city is fixed when the dialog opens and kept until it closes. Open the
dialog with the cursor elsewhere and nothing selected, or with an ordinary
operation selected, and it covers the whole planet as before, cities included.

After a match the city's operation is selected, so reopening the dialog stays
on that city.

## Test

1. View a planet with a city or megafactory at a difficulty where its marker
   is shown. Put the cursor on the marker and press Ctrl+Shift+F8.
2. Confirm the subtitle names the city scope and the mission list is shorter
   than the planet's.
3. Check one mission, optionally a constellation for it, and search. The
   city's operation should refresh and open.
4. Hover the missions of that operation for the constellation check.
5. Close the dialog, move the cursor off the city with nothing selected, and
   reopen. The subtitle should name the planet again.

## What the log should show

- `MODAL_OPEN scope=region 1` for a city, `MODAL_OPEN scope=planet` otherwise.
- `DIALOG_SEARCH planet=… region=1 difficulty=…` and
  `LUA_SEARCH_STARTED planet=… region=1 …`.
- `LUA_SEARCH_MATCH … row=49 …` with a row between `30 + 10 × region` and
  `39 + 10 × region`, then the usual publication and verification lines.

## Limits

- The operation in progress cannot be rerolled. For a city that is its only
  operation at that difficulty, so the dialog reports `This operation is in
  progress; its missions cannot be rerolled` and Start stays disabled until
  the operation is completed or abandoned, or another difficulty is shown.
  With the whole planet in scope the other operations are searched as usual.
- A listed mission can be unreachable in practice. The list shows what the
  operation's templates allow; how often the game draws it is not computed.
- A seed is shared by the whole campaign. Rerolling for a city also changes
  the unstarted operations of the planet and of other planets.
- Cities whose campaign records use the unported resolution paths still stop
  without publishing, as before.

## Evidence

Read-only Memory Explorer session 43884-983360859, build 25480438. No writes
and no native calls were made for this research.

- A recording of the map fields while the user hovered and clicked a city
  marker showed no separate city field. The hovered operation row is at map
  UI `+0x4f04` and the selected row at `+0x4f00`; both took the city's
  operation row (49 on planet 114, 59 on planet 100). A click writes the same
  two fields and calls the same selector as for an ordinary operation.
- The campaign's region records at `campaign+0x6c048` hold planet, region,
  owner and availability. They are the inputs the predictor already reads for
  what it calls special operations. Region `r` owns rows `30 + 10r` to
  `39 + 10r`, one per difficulty (`0x11e44d0`).
- `scripts/check_live_city_scope.py` replayed the packaged code on the live
  campaign memory of planet 114 (40 operations, region 1), then still with
  the twelve-family list of v0.17.0:
  the displayed board, city operations included, equals its prediction; the
  city offers Eradicate, Search and Destroy and Destroy Command Bunkers with
  one modifier, against nine families and five modifiers for the planet; a
  search limited to the city matched row 49 after 21 seeds; and the narrowed
  prediction equals the complete one on 200 further seeds.
- Unit tests cover the row ranges, scope validation, the scoped catalogue and
  its effects, the dialog's capture of the city at opening, a city of another
  planet, the resumed range per scope and the publication preflight.

## Mission list

`scripts/list_mission_families.py` builds the list in `src/search_session.lua`
from the mission records of the saved image (title key at record `+0x340`)
and the English (US) string table extracted with Filediver for this build.
Types are grouped by title; the three Eradicate titles stay one family. 36 of
the 162 records have no title in any language. None of them is referenced by
an operation template or an operation modifier, so the game cannot generate
them. The titles are in the package as plain names; no game file is.

The live replay on planet 253 found a name for all 92 displayed missions and
found each one offered for its scope. The city offers Eradicate forces, Halt
Cyborg Production, Neutralize Ground-to-Orbit Defenses, Sabotage Air Base,
Sabotage Supply Bases, Search and Destroy and Spread Democracy; the planet
offers 22 families. The dialog pages through them twelve at a time.

A planet with several available cities has not been tested.
