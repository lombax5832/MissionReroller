# Know Your Constellation tooltip test

What changed, and what to check in game before the change ships:

- Constellation rows use Know Your Constellation v4.0's names
  (`src/constellation_prediction.lua`), for example Spore Burst Strain,
  Cyborg Legion, Appropriators, Balanced Terminids and Horde.
- Bile Bugs, Hunter Swarms and Predator Strain carry a `*`: a map stamp can
  add them after generation (CONSTELLATION_FILTER_TEST.md), so excluding
  them is a prediction. Their tooltip says so.
- Pointing at a constellation row shows a tooltip left of the panel. With a
  Know Your Constellation that exports `EnemyIntelligence.roster` (api 1,
  roster build equal to `src/offsets.lua` `build`), it lists the units of a
  mission holding that constellation plus the planet's always-present tags,
  with campaign (category 72) and war (type 15) spawn weights, computed by
  that mod's own roster. Nothing of it is copied (`src/unit_forecast.lua`).
- The tooltip draws on layers 1016-1018, above Know Your Constellation's box
  (1011-1015). The panel keeps its layers: it is docked on the right, and
  that box hangs under the planet panel on the left, so the two do not meet.

Needs the release ZIP and, for the unit part, the Know Your Constellation
build with the roster export (branch `export-roster-api` of the fork,
built with `--allow-untested`).

## Steps

1. Install the loader, Mission Reroller and the Know Your Constellation test
   build. Launch, open the galactic map, choose a Terminid planet at
   difficulty 7 or more, press F7 and open ENEMY FORCES.
2. Point at a row without a `*`. A box appears left of the panel, its top
   level with the row: the name in gold, `WITH <always-present forces>` when
   the planet has any, LARGE ENEMIES with ten-tick meters, SMALL AND MEDIUM
   ENEMIES, the footer and `UNIT DATA: KNOW YOUR CONSTELLATION`.
3. Point at `PREDATOR STRAIN *` or `HUNTER SWARMS *`: the same box ends with
   the orange map-stamp note.
4. Point at the last row, then move off the rows: the box stays inside the
   window and disappears with the pointer. Point at the ALWAYS PRESENT line:
   no box.
5. Start a search and point at a row while it runs: the box still shows.
6. Accept a constellation, reroll, and point at the mission the reroller
   selects. Know Your Constellation's own box should name the same enemies
   (meters may differ by the map's own stamps and mission exclusions, which
   the tooltip cannot know).
7. Repeat steps 2-4 with the game window at 1920x1080, a 4:3 window
   (1024x768) and an ultrawide one (3440x1440).
8. Uninstall Know Your Constellation (or install release v4.0, which has no
   export). Rows still carry their `*`; only the starred rows show a box,
   holding the name and the note.

## Log lines

`MissionRerollerExperiment.log`:

- Worked, with the export:
  `KYC_ROSTER ready revision v4.0 build 25480438`
- Without the mod: `KYC_ROSTER off: not installed`
- Release v4.0 without the export: `KYC_ROSTER off: revision v4.0 has no roster api 1`
- Unsupported game build:
  `KYC_ROSTER off: revision v4.0 disabled: ...`, and no unit boxes.
- Failed: `KYC_ROSTER_FAILED <error>; unit tooltips off for this session`
  (the roster raised or returned something unexpected), or
  `KYC_ROSTER_INPUT <error>` (the spawn weights could not be read; that box
  shows no units). Neither stops the mod; `STOPPED:` must not appear.

`EnemyIntelligence.log` keeps its usual status lines; the export adds none.

## Result

2026-09-30, reported by the user, with Mission Reroller `4f8e09c` and the
Know Your Constellation fork `export-roster-api` at `18213aa` (deployed
patch byte-identical to that build):

- With Know Your Constellation installed, the tooltips show (steps 1-2).
- Without it, they do not (step 8).

Not yet recorded: the log lines above, the starred rows' note-only box
without Know Your Constellation, the window sizes (step 7) and the check
against Know Your Constellation's own box after a reroll (step 6). Not
validated in game until the user's logs are recorded here.
