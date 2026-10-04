# Solving campaign seeds instead of searching them

Research prototype, offline only: `scripts/seed_solver.py`,
`scripts/seed_solver_oracle.lua`, `scripts/prove_seed_solver.py`,
`tests/test_seed_solver.py`. Nothing here reads game memory or ships in a
release.

## Question

Can a campaign seed that satisfies a mission filter be constructed from the
generator's code, instead of found by trying seeds one after another?

## Why it can

Every draw comes from one 64-bit LCG (`src/generation_rng.lua`):
`state = state*6364136223846793005 + 1442695040888963407 mod 2^64`, output
`state >> 32`, started from a 32-bit value. The board uses three kinds of
stream:

| Stream | Start | Draws |
| --- | --- | --- |
| Campaign | `(campaign seed + planet) mod 2^32` | per generated row: ID index, then operation seed |
| Operation | operation seed `y` | finalizer: template, modifiers; composition (a second stream from the same `y`): category, level, mission seed per slot |
| Mission choice | `(mission seed + y) mod 2^32` | one draw: the mission kind |

Every choice is a monotone threshold test on one output (float32 cumulative
weights, or `index`), so "this choice comes out this way" is "output `p` lies
in `[lo, hi]`", with the bounds found exactly by bisection
(`seed_solver.partition`). A row's draw positions are fixed: on planet 268
every row draws twice, the preserved row 0 draws nothing, and IDs never fall
back because the pool (35) outnumbers the rows.

- **One output equal to a value** (operation seed back to campaign seed) is a
  linear congruence with an interval, solved exactly by a Euclid-like
  recursion (`solve_affine`), about 2.3 campaign seeds per operation seed.
- **Several chained draws** (a mission seed truncated to 32 bits, added to
  `y`, then drawn again) become a box-constrained lattice: each coordinate
  (`y`, a mission seed `m`, its low half, `u = m + y mod 2^32`, a draw's
  offset in its interval) brings one integer generator, so the basis is
  triangular and exact. `enumerate_box` scales the box to a cube, LLL-reduces
  (exact integral LLL), and enumerates lattice points nearest the centre
  first, cutting a branch when some coordinate can no longer reach the box.
  The campaign stream joins the same lattice through the row's seed draw, so
  one system yields campaign seeds directly.
- **A filter** becomes a set of draw paths: `Planet.paths` walks the
  composition (template, category, mission kind per slot, usage and count
  rules) and keeps every path that delivers the required kinds, leaving
  later draws free. Each path, or each combination of paths over several
  rows, is one lattice. No path at all proves the filter impossible.

On planet 268 the operations of one difficulty differ only in level tiles,
so their paths are identical and the row's ID draw needs no constraint.

## Results, 2026-10-04

Saved planet 268 campaign (`artifacts/level-capture-oracle.lua`, build
25480438), `python -B scripts/prove_seed_solver.py`:

1. The Python port reproduces the mod's Lua predictor on 304 campaign seeds:
   8,816 operations with identical IDs, operation seeds, templates,
   modifiers, mission kinds, mission seeds and levels.
2. Each of those 8,816 operation seeds inverts to its campaign seed
   (27 µs each).
3. Solved filters at difficulty 10. Every solved seed was re-predicted by the
   Lua predictor and matched.

| Filter | Seeds that match | Solver | Lua confirms | Brute force, Python port at about 9,000 seeds/s |
| --- | --- | --- | --- | --- |
| Launch ICBM and Geological Survey in one operation | 1 in 11 | 16 seeds in 0.08 s | 16/16 | 8 seeds |
| ICBM, Survey and Eradicate in one operation | 1 in 21 | 16 seeds in 0.09 s | 16/16 | 1 seed |
| Three category-1 objectives (rules allow two) | none | no draw path, proved at once | | never ends |
| ICBM and Survey in all three operations | 1 in 33,000 | 4 seeds in 33 s, first after 1.9 s | 4/4 | 71k seeds, 7.9 s |
| ICBM, Survey and Eradicate in all three | 1 in 264,000 | 4 seeds in 143 s, first after 104 s | 4/4 | 82k seeds, 9.1 s (about 29 s expected) |

The match fractions come from the lattices' exact volumes. One three-row
system was enumerated completely in a test and gave the predicted count
(958,583 points, 16 s).

## What this shows

- Constructing seeds works and is exact: every solution is right, and an
  impossible filter is recognised without a search.
- Single-operation filters solve in milliseconds.
- In pure Python the enumeration is not yet faster than brute force once
  three operations are joined (34 to 37 dimensions). Its cost grows with the
  dimension, not with how rare the filter is, whereas brute force grows with
  rarity. The in-game Lua search runs at about 1,200 seeds/s, which puts it
  at about 28 s and 220 s for the last two filters.

## Not covered yet

- Side objectives and constellations are drawn from the mission seed. They
  would add the same kind of chained constraint, and they are where filters
  get rare.
- Modifier filters: finalizer draws 2 and 3 have the same form, but
  `Planet.paths` does not branch on them yet.
- Special operations, special level graphs and modifier-driven extra
  missions are rejected by assertions.
- In-game use. The solver would need its tables from the live inputs the
  search already freezes, and a port to LuaJIT (exact 128-bit integer
  arithmetic for the LLL) or precomputation outside the game.

## Next steps, if pursued

1. Speed up enumeration for joined rows: a compiled LLL and enumeration
   (fpylll, or C), or solve each row's operation seeds first and join them
   through the campaign stream with the exact 1-D solver.
2. Add side-objective and constellation constraints, then compare against
   brute force on filters that are rare within one operation.
