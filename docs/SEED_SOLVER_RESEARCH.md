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

## A solver LuaJIT can run: chained 1-D inversions, 2026-10-04

The mod must run the solver itself, on players' machines, with nothing
installed. The lattice above needs exact integers far wider than 64 bits;
`scripts/seed_chain.py` needs only 64-bit arithmetic in its loops:

1. **Root.** For one draw path, take its most selective draw on a mission
   seed m and walk every m in [0, 2^32) whose draw lands in the interval,
   from a random start. By the three-gap theorem consecutive solutions
   differ by one of three fixed steps, so the walk (`Walk`) is one to three
   wrapping uint64 adds per solution. The mission's other draws and
   environment constraints are checked forward on m.
2. **Operation seed.** The y whose position-th draw is m lie in a 2^32 by
   2^32 square of the lattice {(y, A*y mod 2^64)}. A Gauss-reduced basis of
   it is fixed per position, so `Inverter` rounds the square's centre to
   basis coordinates in floating point and checks about 32 nearby points
   exactly (wrapping int64). The whole path is then checked forward on y.
3. **Campaign seed.** The same inversion gives the campaign seeds behind y
   (about 2.3), and the board is predicted as the search predicts it.

Only the setup (the first solution and the two steps of a walk, the reduced
bases) needs the 128-bit Euclid, once per path. `tests/test_seed_chain.py`
checks the walk and the inversion against the exact solver, and the chain's
solutions against the lattice's on paths with mission-seed draws: equal
sets.

`python -B scripts/measure_seed_chain.py` counts the chain's work per filter,
confirms every seed with the Lua predictor, counts brute-force matches over
consecutive seeds, and times the units in LuaJIT
(`scripts/seed_chain_bench.lua`, checked against the Python port's answers
first): 3 ns per walk step, 9 ns per draw check, 190 ns per inversion with
the JIT on, which the v0.16.1 log reports in game. With the JIT off these
are about 25 to 50 times slower. The in-game estimate charges the units at
these timings divided by the share of wall time the search works in game
(389 ms in 1.73 s, v0.16.1), and each board at the measured 1,214 seeds/s.

The search matches one operation, so these filters ask for one matching
operation at difficulty 10. Every solved seed was confirmed by the Lua
predictor (8/8 each).

| Planet 173 filter | Per seed: roots, inversions, boards | Chain in game | Brute force in game |
| --- | --- | --- | --- |
| 59 with Bile Bugs | 3, 4, 1 | 0.001 s | 3 seeds, 0.003 s |
| 59 with Bile Bugs, Upload and Lidar Station | 4,539, 11, 1 | 0.001 s | 28 seeds, 0.02 s |
| 59 (Bile, Upload) with 84 (Hunter, Larva, no Spore) | 25,538, 5,741, 3 | 0.009 s | 4,336 seeds, 3.6 s |
| the same and 65 with Armored Bugs | 403,829, 90,748, 2 | 0.11 s | 47,823 seeds, 39 s |
| 65 with Spore Spewer | no draw path | at once | never |

Planet 268 (missions only): ICBM and Survey 0.001 s against 12 seeds;
ICBM, Survey and Eradicate 0.001 s against 28 seeds. Its "every operation"
filter, outside the use case, takes 0.018 s against 42,659 seeds (35 s)
once the other rows' seed draws are checked against the paths before a
board is predicted.

The rarer the filter, the larger the gain: about 400 times at one match in
4,000 seeds and 350 times at one in 48,000, where brute force takes
seconds to a minute. Almost all of the chain's time is inversions; the
board predictions it still makes are one to three per seed.

Limits that carry over to a port: only one draw narrows the search, so a
filter whose rarity is spread over many wide draws gains less; a path with
no mission-seed draw and no composition draw has no root and scans y (still
with cheap checks); per-ID paths, operation-level rules, families,
modifiers, city scope and special operations are not covered, as above.

## The LuaJIT port, 2026-10-04

Four library modules in `src/`, which the search uses since the next
section's change (**In the search**):

| Module | Port of | What it does |
| --- | --- | --- |
| `seed_solver_math.lua` | `seed_chain.py` `Walk`, `Inverter`; `seed_solver.py` `_first` | Jump-ahead tables, the 128-bit Euclid (setup only), the three-gap walk, the per-position inversion |
| `seed_solver_inputs.lua` | the oracle's `tables` export | Every normal operation's finalization, composition, enemy-tag, side-objective and environment inputs, from the input objects the predictor uses |
| `seed_solver_paths.lua` | `Planet.paths`, `mission_paths` and the `Objectives` walk | Draw paths for a filter; template, category and kind draws run the real choice modules on a one-output stub generator |
| `seed_solver_chain.lua` | `seed_chain.Chain` | Candidate campaign seeds, resumable in budgets of walk steps for the 16 ms frame slice |

The chain returns candidates; the caller predicts each candidate's board and
keeps the matches, so the mod's predictor remains the judge.
`scripts/seed_solver_capture.lua` replays a capture through `src` for the
oracle and the tests; the oracle's JSON export is unchanged (same inputs
and the same Python paths for every filter on both captures).

`python -B tests/test_seed_solver_lua.py` runs the LuaJIT tests on cases the
Python prototype computes:

- `test_seed_solver_math.lua`: 3,000 Euclid solves, 400 walks from random
  starts and 3,000 inversions at positions 1 to 128 equal Python's.
- `test_seed_solver_paths.lua` (needs the captures): the step-wise enemy-tag
  and side-objective draws resolve 12,240 missions (every kind of every
  operation on planet 173, 8 random seeds each) exactly as
  `constellation_prediction.lua` and `side_objective_prediction.lua` do,
  and the draw paths of every filter equal Python's (3,938 paths).
- `test_seed_solver_chain.lua` (needs the captures): solves each filter in
  LuaJIT and predicts every candidate with the mod's own predictor: 16 seeds
  on planet 173 and 9 on planet 268, all matching; the two impossible
  filters have no path.

LuaJIT work per seed offline, predictor boards included: 2 ms for 59 with
Bile Bugs, Upload and Lidar Station, 6 ms for 59 with 84, 7 ms for 59, 84
and 65, about one to three boards each. In game, with the search working
about a quarter of each frame, that is some tens of milliseconds where the
brute-force search takes 4 s and 39 s for the last two. The planet 173
"every operation" filter (outside the use case) took 38 s per seed, so the
chain test leaves it out.

### Time of day

The Day / Night filter (`src/day_night.lua`) passes an operation when every
mission's level node stays on the chosen side for the buffer. A normal
operation's missions take its level nodes slot by slot
(`mission_level_choice.lua` draws a level only for special graphs), and
every slot below min(total, #levels) holds a mission whenever the template
has candidates. So where an operation's missions stand is fixed by its ID,
not by the seed, and `src/seed_solver_time.lua` decides before the search
which IDs of the difficulty can pass: those whose nodes the checker's
`accepts` passes in the current window. None valid means no seed can match
now. The paths come from the valid operations, and the chain keeps a
candidate only when the identity stage (`operation_identity.lua`) gives
its row a valid ID; with "every operation", every generated row. The check
goes through `accepts`, so it follows the window as the search refreshes it.

`test_seed_solver_chain.lua` adds a night and a day variant of each filter
on a synthetic sky (15.7-hour spin) with the captures' real node
longitudes. On 200 random boards per filter the IDs found valid before the
search agree with the checker on every predicted operation (400 on planet
173, 600 on planet 268). At the test's war time 6 of 30 IDs were valid at
night and 9 by day on planet 173, 9 and 8 of 34 on planet 268; every
solved seed passed the predictor and the checker (73 seeds over both
captures, with and without Day / Night). The cost grows with the share of
IDs ruled out, as brute force's does: 59, 84 and 65 at night took 0.12 s
per seed offline against 0.003 s without it.

Not ported: the sampling lattice (offline reference only), per-ID paths
(`shared_paths` returns nil when operations of a difficulty differ in more
than level tiles), operation-level rules (group 0), and special operations
other than a scoped city (**Cities** below).

## In the search, 2026-10-04

The release build's search takes its candidates from the chain when it can
seed the request, and scans seeds in order otherwise. Nothing else about a
search changed: each candidate is predicted from the frozen reads and judged
by `search_session.find`, a match is confirmed on the complete board and
revalidated, then published as before.

- **Inputs.** `planet_model.lua` `planet.solver(definitions, difficulty,
  seeded)` builds `seed_solver_inputs` for one difficulty through the
  search's frozen reads, so its bytes are revalidated with the predictor's.
  The operation bases are every ID below the definitions' pool count, with
  the category and faction `operation_base_inputs.lua` gives its normal
  rows (it now also returns its identity input). The environment weights
  come from `side_objective_inputs.lua` `environment_tables`, which keeps
  the tables the oracle used to read from closures with `debug.getupvalue`
  (identical on the 1,530 operation and kind pairs of the planet 173
  capture). Enemy-tag and side-objective inputs are read only when the
  request has such rules.
- **Request.** `src/seed_solver_search.lua` `source(spec)` maps each
  required family to the kinds the difficulty's operations can draw (one
  path set per choice of kind), gives each kind its family's enemy-force
  and side-objective groups as rules, solves the difficulty's generated
  rows (the operation in progress excluded) and, with Day / Night, adds the
  ID check of `seed_solver_time.lua` with the live checker. Excluded
  missions, modifier rules and the window's movement are left to the
  predictor: they make candidates less selective, never wrong.
- **Fallback.** `source` returns nil and a reason, and the search scans in
  order, for a request without a required mission (group-0
  rules, exclusions or modifiers only), operations of the difficulty that
  differ in more than their level tiles, special levels or modifier
  missions, a pool smaller than the rows, a difficulty above the cap, a
  draw path set that is empty (special operations may still match), or any
  error while building. If the chain ever ran out, the search would carry
  on in order (`seed_search.lua` `options.source`).
- **Frame budget.** The chain gets 4,096 walk steps per search step (about
  1 ms). Building the paths yields at the slice deadline: `partition`, the
  signature comparison of `shared_paths` and each chain job call the job's
  `pause`, and the job yields once after the set-up. Walk starts come from
  `SeedSolver.starts`, the generator's output of successive values from the
  baseline seed and the clock.
- **Log.** `SEED_SOLVER paths=<n> rows=<r> setup_ms=<ms>` (with
  `daynight_ids=<valid>/<total>` for Day / Night), or `SEED_SOLVER_OFF
  reason=<why> setup_ms=<ms>; scanning seeds in order`; progress and result
  lines end in `mode=solver|scan walk_steps=<n>` when the solver was built.
- **Build.** `source()` in `scripts/build_identity_probe.py` joins the five
  modules into one local, `SeedSolver`, in every search build.

`python -B tests/test_seed_solver_search.py` builds the release entry and
runs its own `on_prediction_ready` / `advance_prediction_search` on the
planet 173 capture (`tests/check_seed_solver_search.lua`), with requests
from the displayed board at difficulty 9 (the operation in progress is at
10): one, two and three missions, an enemy force, a side objective, night
and day on a synthetic sky, and three missions with an enemy force and up to
two side objectives all matched through the solver, each on its first
candidate, and an exclusion-only request fell back to scanning. Set-up took
5 to 65 ms with at most 2 ms between pauses; the longest slice was 16 to
17 ms, as scanning's. The frozen inputs grew from 1,883 to at most 2,225
ranges and 60 KB (limits 20,000 and 2 MB). On this capture every request
was also common enough for scanning to match within 23 candidates; the
speed-up on rare requests is the measurement above. The in-game test is
[SEED_SOLVER_TEST.md](SEED_SOLVER_TEST.md).

### Cities, 2026-10-04

The in-game test of the search ran four solved searches on planet 268
(difficulty 6, three missions with an enemy force and side-objective rules,
one by day): each matched within 7 candidates in 0.42 to 1.13 s, published
and verified, and the city search fell back with `SEED_SOLVER_OFF
reason=city scope`, matching by scan after 3,002 seeds.

A city or megafactory is a campaign event: one operation per difficulty in
rows `30 + region*10 + difficulty - 1`, ID the region, category and faction
from its event, and a special level graph. Three differences from a normal
row, all fixed in draw count:

- **Its seed.** `operation_identity.lua` draws the event rows' seeds after
  every normal row (two draws each), one per event row in event order, the
  preserved row drawing none; `seed_solver_search.lua` `event_position`
  gives the campaign-stream position.
- **Its levels.** `mission_level_choice.lua` takes `levels[1]` for the
  first mission and makes one `rng:index(#levels)` draw for each later one,
  its retries over used levels drawing nothing more. The paths
  (`P.paths(op, required, rules, level_ok)`) place each later mission seed
  one draw further on.
- **Day / Night.** The levels are drawn, so the ID check does not apply.
  With `level_ok(node)` (the live checker on one node) each level draw
  becomes a constraint: its outcome intervals by raw index, the retry
  replayed over the levels already used, kept when the resulting node
  passes; the first mission's level must pass too. Missions after the last
  required one are left free, so a few candidates still fail the
  predictor's check.

`planet.solver(definitions, difficulty, seeded, region)` builds the city's
one operation; `source` solves its one row. On the planet 100 capture
(region 2, row 54, difficulty 5) one, two and three of its missions each
matched on the first candidate, two by day on the third or fourth (102
paths); at night there was no path, every level the missions can take
being on the day side then, and scanning agreed (no match in 5,000 seeds).
The scoped scan only predicts the city's row, so it is fast (15,000 seeds/s
offline, 4,467 in game): the solver matters for a city with rare rules or a
Day / Night window, much less for missions alone.

### The estimate in the dialog, 2026-10-04

While the solver searches, the line under the progress strip shows how
strict the filter is and how long such a search usually takes, in place of
the seed count: `1 in 23,000 seeds match - expect about 4 s` (`Most seeds
match`, `expect under a second`, `over the 3 min limit`, and `, running
long` once a search has taken twice its estimate).

- **Strictness.** The paths are disjoint outcomes of the draws, so their
  probabilities add to q, the share of one row's operation seeds that
  follow one; with r generated rows (1 for a city) a campaign seed matches
  with 1 - (1 - q)^r, times the share of valid IDs for Day / Night. On
  2,000 random seeds per filter the predicted and sampled counts agreed
  (424 and 414, 92 and 98, 181 and 182, 92 and 83). Parts of a filter the
  paths leave out are not counted.
- **Time.** A job yields about p/r candidates per walk step (r the share of
  values its root draw takes); jobs take turns of 4,096 steps, most likely
  path first, so `seed_solver_chain.lua` `expected_steps` sums one cycle of
  truncated exponential waits. The walk's solutions cluster, and the first
  candidate came after 0.8 to 3.4 times that many steps on the captures'
  filters, so the search uses twice it. The runtime divides by the walk
  rate measured once 200,000 steps have run (800,000 steps a second until
  then, the rate the in-game searches showed) and adds the set-up and
  0.3 s for the match's confirmation.
- **Log.** `SEED_SOLVER ... match=1/<n> expected_steps=<n>`; the match line's
  `walk_steps=` is the actual count.
- The scan has no estimate: it runs only for requests without paths.
- **Before the search.** `src/solver_estimate.lua` works the same estimate
  out while the player edits the filter: one coroutine, 4 ms a frame,
  yielding inside its live reads and the path building. The planet's
  solver inputs are kept per snapshot, difficulty, scope and whether rules
  need the seeded inputs, so most edits rebuild only the paths; an edit
  during the paths restarts them, one during the input read retargets it.
  The line under a request ready to search reads `Working out how strict
  this is`, then the estimate, or `No seed gives this now` when there is no
  path and no other operation could match (a city, or no campaign event at
  the difficulty; Day / Night with no valid ID). The time uses the walk rate
  the last search measured. The dialog logs `ESTIMATE match=1/<n>
  seconds=<s>` (or `none` / `unavailable`) when it changes.
  `tests/check_seed_solver_search.lua` runs the built dialog's estimator on
  both captures before each search: its share and steps equal the search's
  `SEED_SOLVER` line in every solved case (night, day and the city
  included), worked out in 6 to 79 slices of 4 ms from cold inputs.

## Next steps, if pursued

1. The in-game test ([SEED_SOLVER_TEST.md](SEED_SOLVER_TEST.md)).
2. A compiled lattice enumerator (fpylll, or C) for the joined-row systems,
   which would let every operation of a difficulty be solved in one lattice
   instead of sampled and checked.
3. Operation-level rules (group 0) and per-ID paths, so fewer requests fall
   back to scanning.
