"""Checks scripts/seed_chain.py against the exact solver and the lattice.

    python -B tests/test_seed_chain.py

Needs no capture or game files; outside the release gate, like the other
research tools.
"""
import itertools
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import seed_solver as S  # noqa: E402
import seed_chain as C  # noqa: E402

r = random.Random(25480438)

# The three-gap walk gives the exact solver's sequence, from any start.
for _ in range(300):
    position = r.randint(1, 60)
    width = r.choice([1, 2, 3, 100, r.randrange(1, 1 << 20), r.randrange(1, S.M32)])
    lo = r.randrange(S.M32 - width + 1)
    hi, start = lo + width - 1, r.randrange(S.M32)
    walk = [s for s, _ in itertools.islice(C.Walk(position, lo, hi)(start), 2000)]
    a, c = C.JUMP[position]
    exact = [start + s for s in itertools.islice(S.solve_affine(
        a, (c + a * start) % S.M64, S.M64, lo << 32, (hi << 32) | (S.M32 - 1), S.M32 - start), 2000)]
    assert walk == exact, (position, lo, hi, start)

# A narrow interval walked completely has exactly the exact solver's solutions.
for _ in range(5):
    position, lo = r.randint(1, 60), r.randrange(S.M32 - 4)
    walk = [s for s, _ in C.Walk(position, lo, lo + 3)()]
    assert walk == list(S.states_with_output(position, lo, lo + 3)), position

# Inversion: every start with a given output, as the exact solver finds them.
inverters = {}
for _ in range(3000):
    position, value = r.randint(1, 60), r.randrange(S.M32)
    inverters.setdefault(position, C.Inverter(position))
    assert inverters[position](value) == list(S.states_with_output(position, value, value)), (position, value)
for _ in range(500):
    seed, position = r.randrange(S.M32), r.randint(1, 60)
    inverters.setdefault(position, C.Inverter(position))
    assert seed in inverters[position](S.output(seed, position))

# A draw path solved by the chain has the lattice's solutions: a seed's own
# draws, widened, with a mission step carrying mission-seed draws.
checked = 0
for trial in range(40):
    y = r.randrange(S.M32)
    lo1 = max(0, S.output(y, 1) - (1 << 30))
    constraints = [('direct', 1, lo1, min(S.M32 - 1, S.output(y, 1) + (1 << 30)))]
    position = r.randint(2, 4)
    m = S.output(y, position)
    kind = S.output((m + y) % S.M32, 1)
    draws = {}
    for p in r.sample(range(1, 8), 2):
        v = S.output(m, p)
        half = 1 << 13 if not draws else 1 << 28
        draws[p] = (max(0, v - half), min(S.M32 - 1, v + half))
    constraints.append(('mission', position, max(0, kind - (1 << 29)), min(S.M32 - 1, kind + (1 << 29)),
                        {'draws': draws, 'mods': []}))
    path = {'constraints': constraints}
    system = S.operation_system(path)
    if system.expected() > 500:
        continue
    lattice = sorted(s['y'] for s in system.solve())
    chain = sorted(C.Chain(None, random.Random(trial)).operation_seeds(path))
    assert y in chain and chain == lattice, (trial, len(chain), len(lattice))
    assert all(C.path_ok(v, path) for v in chain)
    checked += 1
assert checked >= 20, checked
print('test_seed_chain: passed')
