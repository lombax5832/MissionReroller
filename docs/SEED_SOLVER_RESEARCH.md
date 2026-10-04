# Solving campaign seeds instead of searching them

Research prototype, offline only: `scripts/seed_solver.py`,
`scripts/seed_solver_oracle.lua`, `scripts/prove_seed_solver.py`,
`tests/test_seed_solver.py`. Nothing here reads game memory or ships in a
release.

## Question

Can a campaign seed that satisfies a filter (missions, enemy forces, side
objectives) be constructed from the generator's code, instead of found by
trying seeds one after another?

## Why it can

Every draw comes from one 64-bit LCG (`src/generation_rng.lua`):
`state = state*6364136223846793005 + 1442695040888963407 mod 2^64`, output
`state >> 32`, started from a 32-bit value. The board uses these streams:

| Stream | Start | Draws |
| --- | --- | --- |
| Campaign | `(campaign seed + planet) mod 2^32` | per generated row: ID index, then operation seed |
| Operation | operation seed `y` | finalizer: template, modifiers; composition (a second stream from the same `y`): category, level, mission seed `m` per slot |
| Mission choice | `(m + y) mod 2^32` | one draw: the mission kind |
| Mission seed | `m` | enemy tags (`constellation_prediction.lua`); separately, side-objective sub-steps, then side, tactical and role-4 draws (`side_objective_prediction.lua`) |
| Environment | `m`, one step | the full 64-bit state modulo two integer weight totals: biome, then its environment byte (`side_objective_inputs.lua`) |

Every choice is a monotone threshold test on one output (float32 cumulative
weights, or `index`), so "this choice comes out this way" is "output `p` lies
in `[lo, hi]`", with the bounds found exactly by bisection
(`seed_solver.partition`). The environment pick is the exception: it tests
`state1 mod total`, a modular interval rather than a threshold.

- **One output equal to a value** (operation seed back to campaign seed) is a
  linear congruence with an interval, solved exactly by a Euclid-like
  recursion (`solve_affine`), about 2.3 campaign seeds per operation seed.
- **Several chained draws** become a box-constrained lattice (`System`):
  each coordinate (`y`, a mission seed `m`, its low half, `u = m + y mod
  2^32`, a draw's offset in its interval, the 64-bit `state1` of `m` and its
  remainders) brings one integer generator, so the basis is triangular and
  exact. `Box` scales the box to a cube and LLL-reduces it (exact integral
  LLL). `Box.every` enumerates every point (Fincke-Pohst from the centre,
  cutting a branch once some coordinate can no longer reach the box);
  `Box.sample` probes small balls around random targets, which finds
  solutions of dense systems quickly and spread across the box where the
  complete walk can wander. The campaign stream joins the same lattice
  through the row's seed draw, so one system yields campaign seeds directly.
- **A filter** becomes a set of draw paths: `Planet.paths` walks the
  composition (template, category, mission kind per slot, usage and count
  rules) and keeps every path that delivers the required kinds, leaving
  later draws free. A required kind with rules delivers only through
  `Planet.mission_paths`, which adds constraints on that mission's own
  stream. No path at all proves the filter impossible.

On both captures the operations of one difficulty differ only in level
tiles, so their paths are identical and the row's ID draw needs no
constraint.

### Mission rules

`search_session.lua` `find()` semantics: a mission meets its enemy-force
rule when it carries an accepted tag (if any is accepted) and no excluded
tag, and its objective rule when it draws every required row and no
excluded one.

- **Enemy tags.** Every combination of the mission's tag draws (one at every
  difficulty on planet 173) is pushed through the fallback, HordeOnly,
  exclusions and disabled tags; the combinations that satisfy the rule are
  constraints on draws 1..n of the mission seed's stream. Exact.
- **Side objectives.** Only the draws a required row depends on are
  constrained: the side (role 3) or tactical (role 2) pool holding the row is
  walked pick by pick until the row is drawn. Sub-steps and pools without a
  required row are skipped by how many draws they spend, one branch per
  possible count. Excluded rows are not constrained. Solutions on a count
  branch that did not happen, or that draw an excluded row later, fail the
  forward check and are dropped; constraining them too multiplied the
  systems a thousandfold for a filter that rejects about two thirds.
- **Environment.** When a required row is allowed only in some environments,
  each (biome, environment) pick becomes two modular constraints on the
  mission seed's `state1`. When every reachable environment gives the same
  paths, the environment is left free.
- Enemy tags and side objectives read the same stream from the same seed, so
  their constraints on one position are intersected.

### Several operations

Joining every row of a difficulty in one lattice gives sparse systems of 35
dimensions or more, which this pure-Python enumerator handles poorly. An
"every operation" filter therefore samples the first generated row's
systems, in short slices round-robin since sampling speed varies a lot
between systems, and checks the other rows forward. The operation in
progress keeps its row whatever the seed (planet 173 has one at difficulty
10, row 27), so these filters cover the operations a reroll generates.

## Ground truth

`scripts/seed_solver_oracle.lua` replays a capture through the real modules
in `src/`: `tables` exports the frozen inputs (template pools, mission
candidates and weights, category rules, level graphs, enemy-tag settings,
objective pools and records, the environment weight tables read back from
the closures `side_objective_inputs.lua` builds), and `predict` writes the
complete predicted board, with each mission's tags, objectives and
environment resolved as `constellation_runtime.lua` and
`side_objective_runtime.lua` resolve them. Every solved seed is checked by
the Python port and then by `predict`.

Captures, both build 25480438, in the main checkout's `artifacts/`:

- `planet-live/capture.lua`: planet 173 (Terminids), viewed-planet capture
  with the tag and objective inputs. Default.
- `level-capture-oracle.lua`: planet 268, campaign capture from before the
  tag and objective inputs were read; missions only.

## Results, 2026-10-04

`python -B scripts/prove_seed_solver.py` (planet 173) and
`--capture <artifacts>/level-capture-oracle.lua` (planet 268), on this
machine:

1. The Python port reproduces the Lua predictor on 304 campaign seeds per
   capture: on planet 173, 8,816 operations and 20,976 missions with
   identical IDs, operation seeds, templates, modifiers, mission kinds,
   mission seeds and levels, enemy tags, side and tactical objectives and
   environments; on planet 268, 8,816 operations and 21,584 missions.
2. Each of those operation seeds inverts to its campaign seed (about 30 µs).
3. Every solved seed was re-predicted by the Lua predictor and matched. The
   brute force runs the Python port over consecutive seeds, predicting only
   the requested difficulty as the in-game search does (which runs at about
   1,200 seeds/s); its count is the seeds tried before the first match.

Planet 173, difficulty 10 (59 Launch ICBM, 84 Emergency Evacuation,
65 Eradicate):

| Filter | Solver | Lua confirms | Brute force, about 3,400 seeds/s |
| --- | --- | --- | --- |
| 59 with Bile Bugs | 16 seeds in 0.12 s | 16/16 | 5 seeds |
| 59 with Bile Bugs, Upload Escape Pod Data and Lidar Station | 16 seeds in 0.31 s | 16/16 | 48 seeds |
| 59 (Bile Bugs, Upload) with 84 (Hunter Swarms, Retrieve Mutant Larva, no Spore Spewer) | 14 seeds in 1.4 s, 0.10 s each | 14/14 | 4,109 seeds, 1.2 s |
| the same and 65 with Armored Bugs | 9 seeds in 1.2 s, 0.13 s each | 9/9 | 54,010 seeds, 16 s |
| 59 and 84 as above in every generated operation (rows 28 and 29) | 3 seeds in 300 s, first after 30 s | 3/3 | none in 404,439 seeds (120 s); about 4.6 million expected, 23 min |
| 65 with Spore Spewer | no draw path, proved at once: Eradicate's side-objective scale is 0 here (4,724 predicted type-65 missions draw only the primary) | | never ends |

Planet 268, difficulty 10 (missions only):

| Filter | Solver | Lua confirms | Brute force, about 8,000 seeds/s |
| --- | --- | --- | --- |
| Launch ICBM and Geological Survey in one operation | 16 seeds in 0.09 s | 16/16 | 8 seeds |
| ICBM, Survey and Eradicate in one operation | 16 seeds in 0.10 s | 16/16 | 1 seed |
| Three category-1 objectives (rules allow two) | no draw path, proved at once | | never ends |
| ICBM and Survey in all three operations | 4 seeds in 1.35 s, first after 0.08 s | 4/4 | 70,916 seeds, 8.5 s |

The match fractions the script prints are sums of path volumes. They are
upper estimates once mission rules are involved: count branches and
forward-checked exclusions overlap, and the first brute-force matches came
later than they suggest.

## What this shows

- Enemy-force and side-objective conditions solve the same way as
  missions: the Python port of their draws is exact, every solved seed
  passed the mod's own predictor, and a condition the game cannot produce
  is recognised without a search.
- The solver's cost per seed stays near 0.1 s as a filter inside one
  operation gets rarer, while brute force grows with rarity: 12 times
  faster where brute force first matched after about 4,000 seeds, and about
  120 times where it first matched after about 54,000 (single runs, so
  these ratios are indications). Against the in-game search's 1,200
  seeds/s the margin is about three times larger again.
- Filters across every operation of a difficulty are the weak spot. Sampling
  one row and checking the others forward found a 1-in-4.6-million filter in
  about 100 s per seed, where brute force needs over 20 minutes in Python
  and about an hour in game, but it is far from the milliseconds of a
  single operation.

## Not covered yet

- Operation-level rules (group 0: a tag or objective on any mission of the
  operation), mission families with several kinds, excluded families,
  modifier filters, city scope and time of day. Modifier draws (finalizer
  draws 2 and 3) have the same form as the others.
- Special operations, special level graphs and modifier-driven extra
  missions are rejected by assertions.
- Excluded rows and tags beyond the constrained draws are only checked
  forward, so a filter made mostly of exclusions gains little.
- In-game use. The solver would need its tables from the live inputs the
  search already freezes, and a port to LuaJIT (exact 128-bit integer
  arithmetic for the LLL) or precomputation outside the game.

## Next steps, if pursued

1. A compiled lattice enumerator (fpylll, or C) for the joined-row systems,
   which would let every operation of a difficulty be solved in one lattice
   instead of sampled and checked.
2. Operation-level rules, mission families and modifier filters, to cover
   every filter the dialog offers.
3. Decide how it would run for players: precomputed outside the game from a
   captured context, or ported to LuaJIT inside the 16 ms frame budget.
