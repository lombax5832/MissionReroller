# Bundled roster test

What changed, and what to check in game before the change ships:

- The enemy-force tooltips list units without Know Your Constellation. The
  release bundles that mod's v4.0 `roster.lua` and `roster_data.lua`
  (`src/vendor/know_your_constellation`, with CowboyBingus's permission),
  and `src/bundled_roster.lua` exposes them as the roster api 1 that
  `src/unit_forecast.lua` already reads from `EnemyIntelligence.roster`.
- Order: an installed Know Your Constellation whose roster export passes
  the checks of the [tooltip test](KYC_TOOLTIP_TEST.md) comes first. When it
  is missing, has no export (release v4.0) or has disabled itself, the
  bundled roster is used, as long as its data's build is `src/offsets.lua`
  `build`.
- A roster that raises still turns unit tooltips off for the session.

## Steps

1. Install the loader and the release ZIP **without** Know Your
   Constellation. Launch, open the galactic map, choose a Terminid planet at
   difficulty 7 or more, press F7 and open ENEMY FORCES.
2. Point at a row without a `*`: the box shows LARGE ENEMIES with meters,
   SMALL AND MEDIUM ENEMIES, the footer and
   `UNIT DATA: KNOW YOUR CONSTELLATION`. Point at a `*` row: the same, ending
   with the orange map-stamp note.
3. Accept a constellation, reroll, play or inspect the selected mission:
   the units should match what spawns (meters are estimates).
4. Install Know Your Constellation v4.0 as well (no roster export) and
   repeat steps 1-2: the same boxes, and Know Your Constellation's own box
   still shows on the left.
5. Optional, with the Know Your Constellation build that exports its roster
   (fork branch `export-roster-api`): the tooltips use that export instead.

## Log lines

`MissionRerollerExperiment.log`, on the first frame of the dialog:

- Step 1, no Know Your Constellation:
  `KYC_ROSTER ready bundled v4.0 build 25480438 (not installed)`
- Step 4, release v4.0 without the export:
  `KYC_ROSTER ready bundled v4.0 build 25480438 (revision v4.0 has no roster api 1)`
- Step 5, with the export: `KYC_ROSTER ready revision <rev> build 25480438`
- Failed: `KYC_ROSTER off: ...`, or
  `KYC_ROSTER_FAILED <error>; unit tooltips off for this session`.
  Neither stops the mod; `STOPPED:` must not appear.

## Result

Not yet run.
