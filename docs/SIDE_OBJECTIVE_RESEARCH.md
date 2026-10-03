# Side objective research

How build 25480438 chooses a mission's side objectives, and how the Lua port
in `src/side_objective_prediction.lua` and `src/side_objective_inputs.lua`
reproduces it. Every RVA refers to the `game.dll` dump in
`../dumps/build-25480438/`; the constants are in `src/offsets.lua`.

## What a side objective is

A mission descriptor (200 bytes, the war table's preview at
`board.mission_preview`) carries the mission's objectives as objective ids:
the count at +0x1d and up to 32 `u32` ids from +0x20. The descriptor packer
`fc2ea0` fills them by calling `1756660`, which packs the descriptor's
inputs and calls `1756730`. The list is built whenever a descriptor is
built (hover, selection, drop); it is not stored on the board.

Map stamps are not objectives. The level step `GenerateMissionStampList`
(`f8e530`) only places the stamps whose tags match each chosen objective id.

Objective records: `objective_types`, 153 records of 0xa0 bytes. +0 id,
+8 internal name (`Objective_gen_radar_station`), +0x10 faction, +0x20 the
most copies in one mission, +0x24/+0x28 lowest and highest difficulty (0:
no limit), +0x2c mask byte (kinds sharing a bit exclude each other), +0x34
title key in strings table `0xd29d9f674db28566`, +0x98 up to four biome
environment bytes (first 0: any).

A mission type's pool: `mission_type` +0x40, 32 entries of 0x18 bytes
`{id, weight f32, group, role, minimum, maximum}`. Roles: 0 primary, 1
sub-steps (launch codes, power), 2 tactical, 3 side, 4 a third pool that no
mission of this build fills. The filter offers roles 3 and 2, one row per
title (`R.rows`).

## Inputs

`1756660` passes `{seed +0, planet id +0xc, type +0x1a, faction +8,
difficulty +9, flag +0xc6}` and the world modifiers of the descriptor
(+0xc8, count +0xc7), which `1267a00` resolves through the board's world
modifier map, keeping at most eight distinct ones with a definition. Its
12672b0-style gate runs with planet -1 and never removes one. The list is
the planet's active world modifiers, which `src/template_environments.lua`
already collects for template environments (`1267460`).

Nothing else: no level index, terrain, time or server data.

## The draw (`1756730`)

1. **Counts.** The difficulty row of the capped difficulty (`11ebb40`, the
   same configuration cap as constellations) gives side objectives at
   +0x28, tactical at +0x2c and the minimum sub-step total at +0x30:

   | Difficulty | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
   |---|---|---|---|---|---|---|---|---|---|---|
   | Side | 0 | 1 | 1 | 2 | 2 | 3 | 3 | 4 | 4 | 4 |
   | Tactical | 0 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |

   `objective_scales` (four rows of 0x50 bytes) scales the side count by
   category: 0 for category 2 (Eradicate, Evacuate High-Value Assets, Rapid
   Acquisition), 1 for 6, 7 and 8. Rounded with `round` (`20be08c`).
2. **Minimum entries.** Every entry with an id, a positive weight and the
   difficulty in its record's range takes its minimum count. Roles 0 and 1
   add their minimum and their cap (min of entry maximum and record +0x20)
   to two totals, and their weight to the sub-step weight while below the
   cap. Without a role 0 minimum the first role 0 entry gets one.
3. **Extra sub-steps.** With the mission type's difficulty range lo < hi
   (+0xc, +0x10): `t = (D-lo)/(hi-lo)`, target `roundf((1-t)*min + max*t)`
   (`20bbb78` is `roundf`, not `ceilf`: 2,400 emulated cases decide it),
   capped by the row's minimum. Each extra step draws a role 0/1 entry below
   its cap by weight, from a 64-bit LCG seeded by the mission seed, while
   the weight left exceeds 1e-6.
4. **Biome environment.** With a planet id: `1758d40` draws one of the
   planet's biomes (planet definition +0x70, entries of 0x38 bytes, weight
   +0x10) among those that allow the mission type's biomes, `1758fc0` one of
   that biome's eight environments (`biome_environment`), skipping one whose
   `requirement` world modifier is absent. Weights become integers (x1000)
   and each pick is `(seed*A+C) mod total` from the mission seed, not the
   shared LCG.
5. **Pools.** An entry is dropped if the configuration disables it
   (boolean at `{0x6bc26bf2, id, 0xf8d23bd2}`), its environment bytes miss
   the biome environment, the difficulty is outside its range, or a world
   modifier bans it (`world_modifier.banned_objectives`). Otherwise its
   minimum copies are emitted (side and tactical ones use up slots) and it
   joins the side, tactical or role 4 pool with its minimum as its count.
6. **Draws** (`1757870`, side, then tactical, then role 4, one LCG state):
   entries at their cap or sharing a drawn mask bit are dropped by moving
   the last entry into their place, the float weights are summed in order,
   one step of the LCG picks an entry by cumulative weight, its count and
   the mask grow, and an entry at its cap is replaced by the last. An empty
   pool still costs one LCG step while slots remain.
7. **Flag.** If `[objective_flag]+0x24` is set, `0x68bfbb59` is appended as
   a tactical objective. It read 0 in every session seen; its purpose is
   unknown.

## Validation

`scripts/validate_side_objectives.py` emulates `1756660` in Unicorn on
memory paged in from the running game, for random mission types, planets,
difficulties, seeds and world modifier lists (including `0x493afbe6`, the
only modifier with a ban list in this session: it bans the Illuminate
Cognitive Disruptor). `tests/check_side_objective_oracle.lua` replays the
port on the same pages.

- 2026-10-02: 400 cases (seed 2) and 2,000 cases (seed 3), 3,524 side and
  1,033 tactical objectives: 0 mismatches.
- The first run used `ceilf` for step 3 and missed 2 of 20 cases with one
  sub-step too many; floor missed 47 of 400.

`scripts/check_live_side_objectives.py` compares the whole pipeline,
including the world modifier collection, with the last previewed mission.
In game, hovering a mission logs `SIDE_OBJECTIVE_CHECK`; see
[SIDE_OBJECTIVE_FILTER_TEST.md](SIDE_OBJECTIVE_FILTER_TEST.md).

## Unknown

- Whether an objective is dropped when its level finds no matching stamp
  (the game has a "Failed to find a stamp with matching tags" message).
- What sets the `objective_flag` object's +0x24.
- Whether the descriptor's world modifier list always equals the
  template-environment collection; `SIDE_OBJECTIVE_CHECK` logs both.
