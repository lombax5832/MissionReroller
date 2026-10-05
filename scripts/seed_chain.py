"""Research prototype: solve campaign seeds by chained 1-D inversions.

The lattice solver in seed_solver.py needs exact integers far beyond 64 bits,
which the game's LuaJIT does not have. This variant needs only the exact 1-D
solver (seed_solver.solve_affine, at most 128-bit products) and forward
checks, so it can be ported to LuaJIT:

1. Root. For one draw path (seed_solver.Planet.paths) pick its most
   selective draw on a mission seed m and enumerate every m in [0, 2^32)
   whose draw lands in the interval, from a random start. The mission's
   other draws and environment constraints are checked forward on m.
2. Operation seed. Each surviving m is the position-th output of the
   operation stream: the operation seeds y with that output (about one per
   m) come from the same 1-D solver, and the whole path is checked forward
   on y.
3. Campaign seed. Each y is the row's seed draw on the campaign stream: the
   campaign seeds behind it (about 2.3) come from the 1-D solver again, and
   the full board is checked forward, as the search checks it.

A path without mission-seed draws is rooted at its narrowest operation-
stream draw instead. Only the root narrows the search; everything else is a
filter, so this is weaker than a lattice for very rare joint conditions, but
each candidate costs a few LCG steps rather than a board prediction.

Standard library only. `Chain.counts` records the work done, for
scripts/measure_seed_chain.py.
"""
from __future__ import annotations

import math
import random
from fractions import Fraction

import seed_solver as S

M32, M64 = S.M32, S.M64
JUMP = [S.jump(p) for p in range(64)]


DRAWS = [0]  # draws evaluated by the forward checks, for the cost estimate


def out_at(state0, position):
    DRAWS[0] += 1
    a, c = JUMP[position]
    return ((a * state0 + c) % M64) >> 32


def roots(position, lo, hi, start):
    """Every 32-bit start s whose position-th output is in [lo, hi],
    ascending from `start` and wrapping round once (exact Euclid per
    solution; Walk gives the same sequence with uint64 adds)."""
    a, c = JUMP[position]
    first, last = lo << 32, (hi << 32) | (M32 - 1)
    for s in S.solve_affine(a, (c + a * start) % M64, M64, first, last, M32 - start):
        yield s + start
    for s in S.solve_affine(a, c, M64, first, last, start):
        yield s


class Walk:
    """The 32-bit starts whose position-th output lies in [lo, hi], in
    ascending order, with only 64-bit wrapping adds per solution.

    By the three-gap theorem, the steps between consecutive s whose state
    a*s + c mod 2^64 returns to an interval of width W are q1, q2 or q1+q2:
    q1 is the least t > 0 moving the state forward by less than W, q2 the
    least moving it back by less than W. From a solution, the next is the
    nearest of q1 and q2 that stays inside, else q1+q2. Only the setup
    (first solution, q1, q2) needs the 128-bit Euclid."""

    def __init__(self, position, lo, hi):
        self.a, self.c = JUMP[position]
        self.lo, self.width = lo << 32, (hi - lo + 1) << 32
        a, w = self.a, self.width
        if w >= M64:
            self.steps = None  # every s
            return
        q1 = S._first(a, M64, 1, w - 1)
        q2 = S._first(a, M64, M64 - w + 1, M64 - 1)
        d1, d2 = a * q1 % M64, M64 - a * q2 % M64  # forward by d1, back by d2
        order = [(q1, d1, 1), (q2, d2, -1)]
        order.sort()
        self.steps = order, (q1 + q2, (d1 - d2) % M64)

    def __call__(self, start=0, limit=M32):
        """Solutions in [start, limit). Yields (s, offset of its state in
        the interval); the offset is what the uint64 walk carries."""
        a, c, lo, w = self.a, self.c, self.lo, self.width
        if self.steps is None:
            for s in range(start, limit):
                yield s, (a * s + c - lo) % M64
            return
        left = (lo - c - a * start) % M64  # a*t mod 2^64 in [left, left + w)
        t = 0 if left + w > M64 else S._first(a, M64, left, left + w - 1)
        if t is None:
            return
        s = start + t
        off = (a * s + c - lo) % M64  # in [0, w)
        (first, second), (q12, d12) = self.steps
        while s < limit:
            yield s, off
            for q, d, sign in (first, second):
                o = off + d if sign > 0 else off - d
                if 0 <= o < w:
                    s, off = s + q, o
                    break
            else:
                s, off = s + q12, (off + d12) % M64
                assert off < w, 'three-gap step left the interval'


class Inverter:
    """The 32-bit starts s whose position-th output equals a given value,
    from a fixed reduced basis of the lattice {(s, A*s mod 2^64)}: the
    answers lie in a 2^32 by 2^32 square of a lattice of determinant 2^64,
    so a few basis combinations around the square's centre, found with
    floating point and checked exactly in 64 bits, hold every one."""

    def __init__(self, position):
        self.a, self.c = JUMP[position]
        u, v = (1, self.a), (0, M64)
        dot = lambda p, q: p[0] * q[0] + p[1] * q[1]
        while True:  # Gauss (Lagrange) reduction, exact
            if dot(u, u) > dot(v, v):
                u, v = v, u
            k = round(Fraction(dot(u, v), dot(u, u)))
            if k == 0:
                break
            v = (v[0] - k * u[0], v[1] - k * u[1])
            if dot(v, v) >= dot(u, u):
                break
        self.u, self.v = u, v
        det = u[0] * v[1] - u[1] * v[0]
        self.inverse = (v[1] / det, -u[1] / det, -v[0] / det, u[0] / det)  # (s, t) -> (i, j)
        half = M32 / 2
        p, q, r, z = self.inverse
        self.reach = (abs(p) * half + abs(r) * half + 1, abs(q) * half + abs(z) * half + 1)

    def __call__(self, value, counts=None):
        a, c, (us, ut), (vs, vt) = self.a, self.c, self.u, self.v
        target = ((value << 32) - c) % M64  # A*s mod 2^64 in [target, target + 2^32)
        cs, ct = M32 / 2, target + M32 / 2
        p, q, r, z = self.inverse
        ci, cj = cs * p + ct * r, cs * q + ct * z
        ri, rj = self.reach
        out = []
        for i in range(math.floor(ci - ri), math.ceil(ci + ri) + 1):
            for j in range(math.floor(cj - rj), math.ceil(cj + rj) + 1):
                s = (i * us + j * vs) % M64  # what wrapping int64 arithmetic gives
                if counts is not None:
                    counts['probes'] += 1
                if s < M32 and ((a * s + c) % M64) >> 32 == value:
                    out.append(s)
        return sorted(set(out))


def mission_ok(m, mission):
    for p, (a, b) in mission['draws'].items():
        if not a <= out_at(m, p) <= b:
            return False
    if mission['mods']:
        state1 = (m * S.MUL + S.INC) % M64
        for modulus, a, b in mission['mods']:
            if not a <= state1 % modulus <= b:
                return False
    return True


def path_ok(y, path):
    """Every constraint of a draw path (seed_solver._constrain) on y."""
    for step in path['constraints']:
        kind, position, lo, hi = step[:4]
        if kind in ('final', 'direct'):
            if not lo <= out_at(y, position) <= hi:
                return False
            continue
        m = out_at(y, position)
        if lo is not None and not lo <= out_at((m + y) % M32, 1) <= hi:
            return False
        mission = step[4] if len(step) > 4 else None
        if mission and not mission_ok(m, mission):
            return False
    return True


def plan(path):
    """The root of a path: ('mission', step index, draw position, lo, hi),
    ('stream', None, position, lo, hi) or None when nothing constrains it.
    The root is the draw that leaves the fewest candidates to invert."""
    best, cost = None, None
    for n, step in enumerate(path['constraints']):
        kind, position, lo, hi = step[:4]
        if kind in ('final', 'direct'):
            # Every root solution is a y to check: weight it like an inversion.
            option, c = ('stream', None, position, lo, hi), (hi - lo + 1) * 8
        else:
            mission = step[4] if len(step) > 4 else None
            if not mission or not mission['draws']:
                continue
            p, (a, b) = min(mission['draws'].items(), key=lambda d: d[1][1] - d[1][0])
            rest = S.Planet._mass({q: d for q, d in mission['draws'].items() if q != p}, mission['mods'])
            # Root solutions cost one cheap check; survivors cost an inversion.
            option, c = ('mission', n, p, a, b), (b - a + 1) * (1 + 8 * rest)
        if cost is None or c < cost:
            best, cost = option, c
    return best


class Chain:
    def __init__(self, planet, rng=None):
        self.planet = planet
        self.rng = rng or random.Random(0)
        self.counts = dict(roots=0, m_pass=0, y=0, y_pass=0, x=0, boards=0, hits=0, probes=0, inversions=0)
        self.inverters = {}

    def invert(self, position, value):
        if position not in self.inverters:
            self.inverters[position] = Inverter(position)
        self.counts['inversions'] += 1
        return self.inverters[position](value, self.counts)

    @staticmethod
    def walk(position, lo, hi, start):
        """roots() through Walk: the same sequence, wrapping once."""
        w = Walk(position, lo, hi)
        for s, _ in w(start, M32):
            yield s
        for s, _ in w(0, start):
            yield s

    def operation_seeds(self, path):
        """Operation seeds y satisfying every constraint of `path`, from a
        random start, each once."""
        c = self.counts
        root = plan(path)
        start = self.rng.randrange(M32)
        if root is None:
            for y in ((start + i) % M32 for i in range(M32)):
                c['y'] += 1
                c['y_pass'] += 1
                yield y
            return
        kind, n, position, lo, hi = root
        if kind == 'stream':
            for y in self.walk(position, lo, hi, start):
                c['roots'] += 1
                c['y'] += 1
                if path_ok(y, path):
                    c['y_pass'] += 1
                    yield y
            return
        step = path['constraints'][n]
        mission, at = step[4], step[1]
        for m in self.walk(position, lo, hi, start):
            c['roots'] += 1
            if not mission_ok(m, mission):
                continue
            c['m_pass'] += 1
            for y in self.invert(at, m):
                c['y'] += 1
                if path_ok(y, path):
                    c['y_pass'] += 1
                    yield y

    def campaign_seeds(self, row, path):
        """Campaign seeds whose `row` gets an operation seed on `path`."""
        _, at = self.planet.draw_positions(row)
        for y in self.operation_seeds(path):
            for x in self.invert(at, y):
                self.counts['x'] += 1
                yield (x - self.planet.planet) % M32

    def solve(self, difficulty, required, rules, scope, want, slice_size=64, deadline=None, clock=None):
        """Seeds whose board at `difficulty` matches, checked forward on the
        full board. 'any' roots each generated row's paths; 'all' roots the
        first generated row and checks the others forward. Jobs take turns
        in slices of `slice_size` root campaign seeds."""
        P = self.planet
        rows = [r for r in range((difficulty - 1) * 3, difficulty * 3)
                if not (P.active and P.active['row'] == r)]
        paths = P.shared_paths(difficulty, required, rules)
        assert paths is not None, 'per-ID paths are outside this prototype'
        others = []
        if scope == 'all':
            # A matching row follows some path, so the other rows' seed draws
            # are checked against the paths before a board is predicted.
            rows, others = rows[:1], [P.draw_positions(r)[1] for r in rows[1:]]
        jobs = [self.campaign_seeds(row, path) for path in paths for row in rows]
        details = bool(rules)
        found = []
        while jobs and len(found) < want:
            for job in list(jobs):
                for _ in range(slice_size):
                    seed = next(job, None)
                    if seed is None:
                        jobs.remove(job)
                        break
                    start = (seed + P.planet) % M32
                    if not all(any(path_ok(out_at(start, at), path) for path in paths) for at in others):
                        continue
                    self.counts['boards'] += 1
                    board = P.board(seed, difficulty, details=details)
                    if P.matches(board, difficulty, required, rules, scope) and seed not in found:
                        self.counts['hits'] += 1
                        found.append(seed)
                        if len(found) >= want:
                            return found
                if deadline is not None and clock() > deadline:
                    return found
        return found
