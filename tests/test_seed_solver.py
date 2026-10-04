"""Checks scripts/seed_solver.py against brute force and the LCG itself.

    python -B tests/test_seed_solver.py

Needs no capture or game files; outside the release gate, like the other
research tools.
"""
import itertools
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import seed_solver as S  # noqa: E402

r = random.Random(25480438)

# The LCG and its jump-ahead agree with stepping.
for _ in range(50):
    seed, planet = r.randrange(S.M32), r.randrange(300)
    rng = S.Rng(seed, planet)
    outs = [rng.next() for _ in range(12)]
    assert outs == [S.output((seed + planet) % S.M32, p) for p in range(1, 13)]

# One interval constraint: exact against brute force.
for _ in range(3000):
    m = r.randint(2, 400)
    a, b, lo = r.randrange(m), r.randrange(m), r.randrange(m)
    hi, n = r.randint(lo, m - 1), r.randint(1, 600)
    assert list(S.solve_affine(a, b, m, lo, hi, n)) == [x for x in range(n) if lo <= (a * x + b) % m <= hi]

# Box enumeration: exact against brute force on small lattices.
for _ in range(300):
    n = r.randint(1, 4)
    basis = [[0] * n for _ in range(n)]
    for j in range(n):
        for i in range(j, n):
            basis[j][i] = r.randint(-30, 30) if i > j else r.choice([1, 2, 3, 5, 7, 16])
    shift = [r.randint(-50, 50) for _ in range(n)]
    widths = [r.randint(1, 12) for _ in range(n)]
    want = []
    for v in itertools.product(*[range(w) for w in widths]):
        z = S._solve_rational(basis, [v[i] - shift[i] for i in range(n)])
        if all(x.denominator == 1 for x in z):
            want.append(tuple(v))
    assert sorted(tuple(v) for v in S.enumerate_box(basis, shift, widths)) == sorted(want)

# Campaign inversion returns the seed that produced an output.
for _ in range(200):
    seed, planet, position = r.randrange(S.M32), r.randrange(300), r.randint(1, 60)
    value = S.output((seed + planet) % S.M32, position)
    assert seed in S.campaign_seeds_for(value, position, planet)


def forward(y, constraints):
    for kind, position, lo, hi in constraints:
        v = S.output(y, position)
        if kind == 'mission':
            v = S.output((v + y) % S.M32, 1)
        if not lo <= v <= hi:
            return False
    return True


# Chained constraints: a seed's own draws, widened a little, are solved back.
# The system expects a handful of solutions, so it is enumerated completely:
# the seed must be among them and every solution must pass forward.
checked = 0
for trial in range(40):
    y = r.randrange(S.M32)
    constraints = []
    for position in range(1, r.randint(3, 5)):
        kind = r.choice(['direct', 'mission'])
        v = S.output(y, position)
        if kind == 'mission':
            v = S.output((v + y) % S.M32, 1)
        half = r.choice([1 << 18, 1 << 20])
        constraints.append((kind, position, max(0, v - half), min(S.M32 - 1, v + half)))
    system = S.operation_system({'constraints': constraints})
    if system.expected() > 2000:
        continue
    found = [s['y'] for s in system.solve()]
    assert y in found, (trial, y, constraints)
    assert all(forward(v, constraints) for v in found)
    assert len(found) == len(set(found))
    checked += 1
assert checked >= 20, checked

# The same with the campaign stream in front: the row's draws tie x to y.
class Board:
    pool, planet, active = 35, 268, None

    def draw_positions(self, row):
        return 2 * row + 1, 2 * row + 2


board = Board()
for trial in range(20):
    seed, row = r.randrange(S.M32), r.randint(0, 29)
    rng = S.Rng(seed, board.planet)
    for _ in range(2 * row):
        rng.next()
    op_id, y = rng.index(board.pool), rng.next()
    v = S.output(y, 1)
    constraints = [('direct', 1, max(0, v - (1 << 14)), min(S.M32 - 1, v + (1 << 14)))]
    system = S.operation_system({'constraints': constraints}, (board, row, op_id))
    found = [(s['x'] - board.planet) % S.M32 for s in system.solve()]
    assert seed in found, (trial, seed)
    for x in found:  # each solution draws op_id first and passes forward
        rng = S.Rng(x, board.planet)
        for _ in range(2 * row):
            rng.next()
        assert rng.index(board.pool) == op_id and forward(rng.next(), constraints)
print('test_seed_solver: passed')
