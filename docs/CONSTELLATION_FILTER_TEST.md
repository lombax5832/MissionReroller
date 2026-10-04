# Constellations per mission — v0.15.0, exclusion — v0.19.0

## Result, 2026-09-29 session (v0.16.0)

Two searches with one constellation per checked mission matched and were
published: Armored Column for Launch ICBM and Spread Democracy on planet 253,
Armored Bugs for Geological Survey and Spread Democracy on planet 268.

Eight hovered missions produced `CONSTELLATION_CHECK` lines, six of them in
the two matched operations. All read `agree=true`:

- The level data is at controller offset `2c8`, as the native code reads it.
- No mission carried explicit tags, as the descriptor builder predicts.
- No first stamp contributed a tag, although up to 68 stamps were placed.
- Planet 253 carries the planet-wide tag 21 (`GM_BotCyborgs`), which the
  search had included in every prediction there.

The stamp survey found 851 stamp records in 14 sets. Seven records carry a
tag, all in one set: `BugAcid` four times, `BugPredators` once and
`GM_BugSuperPredators` twice. Stamps can therefore carry base constellations.
A checked constellation that was predicted is still present, but checking
all constellations but one does not guarantee the remaining one is absent.
Which missions place a stamp of that set first is not known yet. v0.16.1
logs the first stamp's fields even when it contributes nothing, and lists
tagged stamps placed later.

These checks compare the search's inputs with what the game loaded. They do
not independently confirm the constellation the game then uses; Know Your
Constellation was not installed in that session. The any-mission page was
not exercised.

## Result, 2026-09-29 session (v0.19.0 exclusion)

The user validated constellation exclusion in game in a separate session: a
search with excluded constellations matched and opened an operation that
did not carry them. No log from that session was reviewed for this note, so
the stamp caveat under *What this test decides* still stands as written.

## Install

Install `releases/Mission-Reroller-v0.19.0.zip`, which contains these filters and
the [fast seed search](FAST_SEARCH_TEST.md), in place of the previous package.
Purge / Deploy, and restart. Remain alone on your ship for this supervised test.
Mission and modifier filters, viewed-planet rerolling and automatic selection
are unchanged from v0.13.0. v0.14.0 applied constellation rules to the whole
operation; it was never tested in game and is superseded by this build.

## What is new

The dialog has a third tab, **CONSTELLATIONS**. Constellations are chosen for
each checked mission separately.

- With missions checked, the tab has one page per checked mission. The first
  row names the mission, for example `FOR: LAUNCH ICBM`. The `<` and `>` buttons
  switch between checked missions.
- Each constellation cycles ANY > ACCEPT > EXCLUDE when clicked (v0.19.0;
  v0.15.0 to v0.18.0 had a check box that meant ACCEPT).
- ACCEPT: the operation must contain that mission carrying one of the
  accepted constellations. With none accepted, any is fine.
- EXCLUDE: that mission must carry none of the excluded constellations. Any
  number can be excluded, and both kinds of rule combine.
- With no mission checked, the single page reads `FOR: THE OPERATION`. One
  mission of the operation must carry an accepted constellation, and no
  mission of the operation may carry an excluded one.
- Excluding everything a mission can draw is refused with `Every
  constellation of this mission is excluded`, because a mission always draws
  one. It is allowed when the game can remove a drawn constellation again.
- Unchecking a mission discards its rules. Checking the first mission
  discards the rules of the operation page. The section's header then turns
  red and reads `- MISSION CHANGED` until it is clicked
  (docs/MISSION_CHANGED_TEST.md).

Each page lists only what that mission can draw: the weighted base
constellations of the mission's own faction at the map difficulty, without any
the mission's own record or the game configuration removes afterwards. The
name in brackets is the game's tag, for example `Hunter Swarms (BugPredators)`.
In the saved tables Terminid missions draw from six constellations and
Automaton missions from five at difficulty 2 and above. Illuminate missions and
difficulty 1 draw none, so their pages are empty.

Constellations active on the whole planet, such as a strain, are shown in the
subtitle. Rerolling cannot change them, so they cannot be checked.

An exclusion is as reliable as the prediction of the level stamp allows; see
*What this test decides* below.

## Test

1. View a Terminid or Automaton planet at difficulty 2 or higher and open the
   dialog with Ctrl+Shift+F8. Check two missions, for example Launch ICBM and
   Search and Destroy.
2. Open CONSTELLATIONS. Accept one constellation for the first mission, press
   `>` and exclude two for the second. Start the search.
3. After the matching operation opens, **hover each of its missions for a
   second or two**, then a few missions of other operations. If Know Your
   Constellation is installed, compare its panel with your choices.
4. Clear the selection, check no mission, exclude two constellations on the
   `THE OPERATION` page and search again. No mission of the match should
   carry either.
5. Confirm a mission-only search still works as in v0.13.0.

A given constellation is drawn for roughly one mission in five. Two missions
with one constellation each therefore match about one in twenty-five of the
operations that contain both missions. With the v0.16.0 budget of 262,144
seeds such requests are within reach. Checking more constellations per
mission widens the search.

## What the log should show

`MissionRerollerExperiment.log` in the Logs folder:

- `LUA_SEARCH_CONSTELLATIONS Launch ICBM=accept 4, Search and Destroy=accept
  any exclude 2|8` when a search starts, or `operation=…`. Numbers are the
  game's tag indices:
  2 BugAcid, 3 BugArmored, 4 BugPredators, 6 BugFodder, 7 BugCrawlers,
  8 BugBalanced, 14 BotAssault, 15 BotPhalanx, 16 BotArtillery, 18 BotPanzer,
  19 BotBalanced.
- `LUA_SEARCH_MATCH_CONSTELLATIONS row=… missions=59:4,68:2,65:6` with each
  mission of the match as mission type and predicted tags, followed by the
  usual publication lines.
- One `CONSTELLATION_CHECK` line per hovered mission. `predicted` is what the
  search used. `full` adds what the loaded mission preview contributed.
- One `CONSTELLATION_STAMP_SURVEY` line per session.

Failures: `CONSTELLATION_CATALOGUE_BLOCKED` (the tab stays empty, other filters
keep working), `FILTER_BLOCKED` (a request was refused before searching) and
`CONSTELLATION_CHECK_BLOCKED` (the observer stopped; nothing else is affected).

## What this test decides

The search predicts the campaign tags, the seeded base draw, the conditional
`HordeOnly` tag and both exclusion lists. It cannot predict one input: the tag
of the first stamp placed when the game generates the mission's level. For
Terminid and Automaton missions that stamp can only add a tag, never change
the base draw. A mission predicted to carry a checked constellation therefore
still carries it.

What the stamp can do is add a constellation, including one you excluded.
The `CONSTELLATION_CHECK` lines show whether that happens: `agree=true` means
the loaded mission added nothing to the prediction. The survey of v0.16.0
found seven stamp records carrying `BugAcid`, `BugPredators` or
`GM_BugSuperPredators`, so an exclusion of those on Terminid missions is not
guaranteed until it is known which missions place such a stamp first.

The v0.18.0 session added a finding. A map preview leaves the mission
controller unloaded, and the native resolver reads the first stamp only when
it is loaded. Seven of twelve hovered missions had a first stamp record that
was therefore not read. v0.19.0 reads its tag in a preview as well, marks
the line `preview`, and counts the tag in `full`, because the mission will
carry it once played. Until such lines exist, `agree=true` shows only that
the preview added nothing.

The check also validates the prediction inputs themselves in the running game
and reports whether the level data sits at controller offset `2c8`, as the
native code reads it, or `288`, as the reference reader does.

## Evidence and changes

Offline analysis of the saved build 25480438 image, read-only, no native calls:

- `0x177dd80` clears the tag list, then calls `0x11deda0` (campaign effects of
  class 0x28 and kind 13, then 32 global entries filtered by `0x12e1210`) and
  `0x177deb0`. Afterwards it removes every tag whose configuration key
  `{0xe165f457, 0xec4e3719, tag hash}` exists.
- `0x177deb0` adds the level's explicit tags and first stamp tag, calls
  `0x1758000` with the faction and difficulty stored in the mission
  descriptor, adds `HordeOnly` for category 2 missions with the matching
  resource, and removes the mission record's exclusions up to the first empty
  slot.
- `0x1758000` clamps difficulty with `0x11ebb40`, filters the eight candidates,
  draws with the 64-bit LCG seeded by the mission seed, and applies the
  fallback unless a blocker is present.
- The local descriptor builder `0x12d27b0` takes the descriptor faction from
  the mission record and passes a null explicit-tag array to the packer
  `0xfc2ea0`, so locally generated missions carry no explicit tags.

The Lua port matches an independent implementation over the saved static
tables on 23,780 cases (`scripts/validate_constellation_choice.py`,
`tests/check_constellation_oracle.lua`) and the five native captures recorded
in the sibling reference project, which are read at test time and not copied.
The same check builds the per-mission lists from the saved tables. The
packaged search tags candidates through the frozen reader, so tag inputs are
revalidated with the rest before a match is accepted. Publication re-checks
the constellations in its preflight.

The observer and survey only read memory. They are wrapped so that a failure
is logged once and never stops the mod or a search. Display names are
descriptive labels chosen for this mod; the bracketed game tag is
authoritative. In-game validation is the next step.
