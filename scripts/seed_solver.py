"""Research prototype: solve campaign seeds for a mission filter instead of searching.

Every draw the operation generator makes comes from one 64-bit LCG
(src/generation_rng.lua): state' = state*MUL + INC mod 2^64, output = state' >> 32,
seeded with a 32-bit value. A choice is a threshold test on one output, so a
filter becomes a set of constraints "output p of a stream lies in [lo, hi]".
This module turns those constraints into a lattice problem and enumerates the
seeds that satisfy them, then checks each one forward with a port of the
generator (and, in scripts/prove_seed_solver.py, with the mod's Lua predictor).

Nothing here reads game memory or touches the game. Standard library only.
"""
from __future__ import annotations

import itertools
import json
import math
import random
import struct
import time
from fractions import Fraction

MUL = 6364136223846793005
INC = 1442695040888963407
M32 = 1 << 32
M64 = 1 << 64


# ---------------------------------------------------------------- the RNG

def jump(steps):
    """(A, C) with state_steps = A*state_0 + C mod 2^64."""
    a, c = 1, 0
    for _ in range(steps):
        a, c = (a * MUL) % M64, (c * MUL + INC) % M64
    return a, c


def output(state0, position):
    """The value of the position-th next() (1-based) from a 64-bit state."""
    a, c = jump(position)
    return ((a * state0 + c) % M64) >> 32


class Rng:
    """generation_rng.lua: make_rng(seed, planet)."""

    def __init__(self, seed, planet=0):
        self.state = (seed + planet) % M32
        self.draws = 0

    def next(self):
        self.state = (self.state * MUL + INC) % M64
        self.draws += 1
        return self.state >> 32

    def index(self, count):
        return min(count - 1, math.floor(self.next() * (1 / 4294967296) * count))


def f32(x):
    return struct.unpack('<f', struct.pack('<f', x))[0]


def weighted_index(out, weights):
    """The 1-based item a float32 weighted draw (operation_finalization.lua
    draw, mission_category_choice.lua) picks for output `out`, or None."""
    total = 0.0
    for w in weights:
        total = f32(total + f32(w))
    threshold = f32(f32(f32(out) * f32(1 / 4294967296)) * total)
    acc = 0.0
    for i, w in enumerate(weights, 1):
        acc = f32(acc + f32(w))
        if threshold <= acc:
            return i
    return None


def partition(choice, lo=0, hi=M32 - 1):
    """[(value, first, last)] for a choice function monotone in the output.

    The generator's threshold draws are monotone, so each value owns one
    interval; bisection finds the edges exactly. Raises if a value repeats."""
    parts, seen = [], set()
    at = lo
    while at <= hi:
        value = choice(at)
        assert value not in seen, 'choice is not monotone in the output'
        seen.add(value)
        a, b = at, hi
        while a < b:  # last output with the same value
            mid = (a + b + 1) // 2
            if choice(mid) == value:
                a = mid
            else:
                b = mid - 1
        parts.append((value, at, a))
        at = a + 1
    return parts


# --------------------------------------------- one constraint, exact (1-D)

def _first(a, m, lo, hi):
    """Least x >= 0 with lo <= a*x mod m <= hi (0 <= lo <= hi < m), or None.

    Euclid-like recursion: when [lo, hi] holds no multiple of a, the wrap
    count y of a*x obeys the same kind of condition modulo a."""
    a %= m
    if lo == 0:
        return 0
    if a == 0:
        return None
    if 2 * a > m:  # (m-a)x = -ax: keeps the modulus halving
        return _first(m - a, m, m - hi, m - lo)
    k = (lo + a - 1) // a
    if a * k <= hi:
        return k
    s = lo % a
    y = _first((-m) % a, a, s, s + hi - lo)
    if y is None:
        return None
    return (lo + m * y + a - 1) // a


def solve_affine(a, b, m, lo, hi, limit):
    """Every x in [0, limit) with lo <= (a*x + b) mod m <= hi, ascending."""
    assert 0 <= lo <= hi < m
    x0 = 0
    while x0 < limit:
        left = (lo - b - a * x0) % m
        right = left + (hi - lo)
        t = 0 if right >= m else _first(a, m, left, right)
        if t is None:
            return
        x = x0 + t
        if x >= limit:
            return
        yield x
        x0 = x + 1


def states_with_output(position, lo, hi, limit=M32, offset=0):
    """32-bit start states s (s < limit) whose position-th output is in [lo, hi]."""
    a, c = jump(position)
    yield from solve_affine(a, (c + a * offset) % M64, M64, lo << 32, (hi << 32) | (M32 - 1), limit)


def campaign_seeds_for(op_seed, position, planet):
    """Campaign seeds whose position-th draw on `planet` equals op_seed."""
    for x in states_with_output(position, op_seed, op_seed):
        yield (x - planet) % M32


# ------------------------------------------------ many constraints (lattice)

def lll(rows):
    """Integral LLL (Cohen, Algorithm 2.6.7), delta 3/4. Returns H with
    H*rows reduced; rows must be independent. Exact integer arithmetic."""
    n = len(rows)
    b = [list(r) for r in rows]
    h = [[int(i == j) for j in range(n)] for i in range(n)]
    dot = lambda u, v: sum(x * y for x, y in zip(u, v))
    d = [0] * (n + 1)
    lam = [[0] * (n + 1) for _ in range(n + 1)]
    d[0] = 1
    d[1] = dot(b[0], b[0])
    k, kmax = 2, 1

    def red(k, l):
        if 2 * abs(lam[k][l]) > d[l]:
            q = (2 * lam[k][l] + d[l]) // (2 * d[l])
            b[k - 1] = [x - q * y for x, y in zip(b[k - 1], b[l - 1])]
            h[k - 1] = [x - q * y for x, y in zip(h[k - 1], h[l - 1])]
            lam[k][l] -= q * d[l]
            for i in range(1, l):
                lam[k][i] -= q * lam[l][i]

    def swap(k):
        b[k - 1], b[k - 2] = b[k - 2], b[k - 1]
        h[k - 1], h[k - 2] = h[k - 2], h[k - 1]
        for j in range(1, k - 1):
            lam[k][j], lam[k - 1][j] = lam[k - 1][j], lam[k][j]
        l = lam[k][k - 1]
        big = (d[k - 2] * d[k] + l * l) // d[k - 1]
        for i in range(k + 1, kmax + 1):
            t = lam[i][k]
            lam[i][k] = (d[k] * lam[i][k - 1] - l * t) // d[k - 1]
            lam[i][k - 1] = (big * t + l * lam[i][k]) // d[k]
        d[k - 1] = big

    while k <= n:
        if k > kmax:
            kmax = k
            for j in range(1, k + 1):
                u = dot(b[k - 1], b[j - 1])
                for i in range(1, j):
                    u = (d[i] * u - lam[k][i] * lam[j][i]) // d[i - 1]
                if j < k:
                    lam[k][j] = u
                else:
                    d[k] = u
                    assert u != 0, 'dependent lattice basis'
        red(k, k - 1)
        if 4 * d[k] * d[k - 2] < 3 * d[k - 1] ** 2 - 4 * lam[k][k - 1] ** 2:
            swap(k)
            k = max(2, k - 1)
        else:
            for l in range(k - 2, 0, -1):
                red(k, l)
            k += 1
    return h


def _solve_rational(rows, target):
    """z with sum_j z_j * rows[j] = target, exactly (rows square, independent)."""
    n = len(rows)
    # Columns of the system are the rows; build augmented [rows^T | target].
    a = [[Fraction(rows[j][i]) for j in range(n)] + [Fraction(target[i])] for i in range(n)]
    for col in range(n):
        piv = next(r for r in range(col, n) if a[r][col] != 0)
        a[col], a[piv] = a[piv], a[col]
        p = a[col][col]
        a[col] = [v / p for v in a[col]]
        for r in range(n):
            if r != col and a[r][col] != 0:
                f = a[r][col]
                a[r] = [v - f * w for v, w in zip(a[r], a[col])]
    return [a[i][n] for i in range(n)]


class Box:
    """The points v = shift + sum_j z_j*basis[j] (z integer) with
    0 <= v_i < widths[i]; basis is square and independent (rows are vectors).

    Each coordinate is scaled to a unit interval and the basis LLL-reduced
    once. points() enumerates the lattice points in a ball around a target
    (Fincke-Pohst, nearest values first) and checks each exactly; the ball
    around the box centre with radius sqrt(n)/2 holds the whole box, so
    every() is complete. sample() probes small balls around random targets
    instead: when a system holds many solutions spread unevenly, the
    complete walk can wander a long time in parts of the ball outside the
    box, while a small ball anywhere in the box usually holds one."""

    def __init__(self, basis, shift, widths):
        n = self.n = len(basis)
        self.widths = widths
        scaled = [[(basis[j][i] << 64) // widths[i] for i in range(n)] for j in range(n)]
        h = lll(scaled)
        red = self.red = [[sum(h[r][j] * basis[j][i] for j in range(n)) for i in range(n)] for r in range(n)]
        centre = [Fraction(w, 2) for w in widths]
        z = _solve_rational(red, [c - s for c, s in zip(centre, shift)])
        z0 = [round(v) for v in z]
        self.p0 = [shift[i] + sum(z0[j] * red[j][i] for j in range(n)) for i in range(n)]
        self.base = [float(Fraction(self.p0[i], widths[i])) for i in range(n)]  # p0 in unit coordinates
        bf = [[red[j][i] / widths[i] for i in range(n)] for j in range(n)]
        # Gram-Schmidt of the scaled reduced rows.
        star, norm, mu = [], [], [[0.0] * n for _ in range(n)]
        for j in range(n):
            v = list(bf[j])
            for k in range(j):
                mu[j][k] = sum(x * y for x, y in zip(bf[j], star[k])) / norm[k]
                v = [x - mu[j][k] * y for x, y in zip(v, star[k])]
            star.append(v)
            norm.append(sum(x * x for x in v))
        self.star, self.norm, self.mu = star, norm, mu
        # Coordinates no row below k can change are fixed once rows k..n-1
        # are chosen: check them there instead of at every leaf.
        self.settled = [[i for i in range(n) if all(red[j][i] == 0 for j in range(k))] for k in range(n)]
        # The general form of the same test. Once rows k..n-1 are chosen,
        # the point is fixed outside span(star[0..k-1]); what the lower rows
        # add lies in that span with length at most sqrt(budget left), so it
        # moves coordinate i by at most reach[k][i]*sqrt(budget). A branch
        # that cannot bring every coordinate back into the box is cut.
        self.reach = [[math.sqrt(sum(star[l][i] ** 2 / norm[l] for l in range(k))) for i in range(n)]
                      for k in range(n)]

    def points(self, target, radius2, limit=None, deadline=None):
        """In-box lattice points within sqrt(radius2) of `target` (unit
        coordinates). Raises TimeoutError past `deadline`."""
        n, red, p0, widths = self.n, self.red, self.p0, self.widths
        star, norm, mu, reach, settled = self.star, self.norm, self.mu, self.reach, self.settled
        q = [b - t for b, t in zip(self.base, target)]
        tau = [sum(x * y for x, y in zip(q, star[k])) / norm[k] for k in range(n)]
        # The walk tracks v/W - target; the box is [-target, 1 - target).
        lo = [-t - 1e-6 for t in target]
        hi = [1 - t + 1e-6 for t in target]
        delta = [0] * n
        state = {'found': 0, 'nodes': 0}

        def inside(k):
            for i in settled[k]:
                v = p0[i] + sum(delta[j] * red[j][i] for j in range(k, n))
                if not 0 <= v < widths[i]:
                    return False
            return True

        def walk(k, budget, acc):
            state['nodes'] += 1
            if deadline is not None and state['nodes'] % 4096 == 0 and time.perf_counter() > deadline:
                raise TimeoutError
            if k < 0:
                v = [p0[i] + sum(delta[j] * red[j][i] for j in range(n)) for i in range(n)]
                if all(0 <= v[i] < widths[i] for i in range(n)):
                    state['found'] += 1
                    yield v
                return
            centre_k = -(tau[k] + sum(delta[j] * mu[j][k] for j in range(k + 1, n)))
            span = math.sqrt(max(budget, 0.0) / norm[k])
            values = sorted(range(math.ceil(centre_k - span), math.floor(centre_k + span) + 1),
                            key=lambda v: abs(v - centre_k))
            row, out = star[k], reach[k]
            for value in values:
                delta[k] = value
                c = value - centre_k
                used = c * c * norm[k]
                if used > budget:
                    continue
                left = math.sqrt(max(budget - used, 0.0))
                nxt = [a + c * s for a, s in zip(acc, row)]
                if any(a + r * left < l or a - r * left > h for a, r, l, h in zip(nxt, out, lo, hi)):
                    continue
                if inside(k):
                    yield from walk(k - 1, budget - used, nxt)
                    if limit is not None and state['found'] >= limit:
                        return
            delta[k] = 0

        yield from walk(n - 1, radius2, [0.0] * n)

    def every(self, limit=None, deadline=None):
        """Every in-box point (the ball around the centre holds the box)."""
        try:
            yield from self.points([0.5] * self.n, self.n / 4 * (1 + 1e-9) + 1e-9, limit, deadline)
        except TimeoutError:
            return

    def sample(self, expected, limit, deadline=None, rng=None):
        """Distinct in-box points from probes around random targets. The
        probe radius starts where a ball holds about two lattice points of
        a system with `expected` points per box, and grows while probes
        come back empty."""
        rng = rng or random.Random(0)
        n = self.n
        unit_ball = math.pi ** (n / 2) / math.gamma(n / 2 + 1)
        radius = min(math.sqrt(n) / 2, (2 / (max(expected, 1e-9) * unit_ball)) ** (1 / n))
        seen, misses = set(), 0
        while len(seen) < limit:
            if deadline is not None and time.perf_counter() > deadline:
                return
            target = [rng.random() for _ in range(n)]
            got = False
            try:
                for v in self.points(target, radius * radius, limit=4, deadline=deadline):
                    key = tuple(v)
                    if key not in seen:
                        seen.add(key)
                        got = True
                        yield v
                        if len(seen) >= limit:
                            return
            except TimeoutError:
                return
            misses = 0 if got else misses + 1
            if misses >= 8 and radius < math.sqrt(n) / 2:
                radius = min(math.sqrt(n) / 2, radius * 1.25)
                misses = 0


def enumerate_box(basis, shift, widths, limit=None, deadline=None):
    """Every v = shift + sum_j z_j*basis[j] (z integer) with
    0 <= v_i < widths[i] (Box.every)."""
    yield from Box(basis, shift, widths).every(limit, deadline)


class System:
    """Builds a box-constrained lattice one coordinate at a time.

    Every coordinate brings one new integer generator, so the coordinate x
    generator matrix is lower triangular and the lattice has full rank. An
    expression is (terms {generator: coefficient}, constant)."""

    def __init__(self):
        self.rows = []      # coordinate i: (terms, constant, width)
        self.names = []

    def _add(self, name, terms, const, own, width):
        g = len(self.rows)
        terms = dict(terms)
        terms[g] = terms.get(g, 0) + own
        self.rows.append((terms, const, width))
        self.names.append(name)
        return g

    def var(self, name, width=M32):
        """A free value in [0, width): the coordinate is its generator."""
        g = self._add(name, {}, 0, 1, width)
        return ({g: 1}, 0), g

    @staticmethod
    def _affine(expr, a, c):
        terms, const = expr
        return ({g: (a * v) % M64 for g, v in terms.items()}, (a * const + c) % M64)

    def output_in(self, name, state, position, lo, hi):
        """next()^position of a stream whose 64-bit start is `state` lies in [lo, hi]."""
        terms, const = self._affine(state, *jump(position))
        self._add(name, terms, (const - (lo << 32)) % M64, M64, (hi - lo + 1) << 32)

    def high(self, name, state, position):
        """A new variable equal to the position-th output of the stream."""
        value, g = self.var(name)
        terms, const = self._affine(state, *jump(position))
        terms = dict(terms)
        terms[g] = (terms.get(g, 0) - M32) % M64
        self._add(name + '.low', terms, const, M64, M32)
        return value

    def add32(self, name, x, y):
        """(x + y) mod 2^32 as a new coordinate."""
        terms = dict(x[0])
        for g, v in y[0].items():
            terms[g] = terms.get(g, 0) + v
        const = x[1] + y[1]
        g = self._add(name, terms, const, M32, M32)
        # The value is the whole coordinate, x + y + 2^32*g, not g alone.
        terms[g] = terms.get(g, 0) + M32
        return (terms, const)

    def state(self, name, x, position):
        """The full 64-bit state after `position` steps from start x, as a new
        coordinate in [0, 2^64)."""
        terms, const = self._affine(x, *jump(position))
        g = self._add(name, terms, const, M64, M64)
        terms = dict(terms)
        terms[g] = terms.get(g, 0) + M64
        return (terms, const)

    def mod_in(self, name, state, modulus, lo, hi):
        """state mod modulus lies in [lo, hi] (state a coordinate in [0, 2^64))."""
        terms, const = state
        self._add(name, terms, const - lo, -modulus, hi - lo + 1)

    def solve(self, limit=None, deadline=None, sample=False, rng=None):
        """Solutions as {coordinate name: value}. With `sample`, distinct
        solutions from random probes (Box.sample) instead of the complete,
        centre-out walk; a system expecting few points is walked anyway."""
        n = len(self.rows)
        basis = [[self.rows[i][0].get(j, 0) for i in range(n)] for j in range(n)]
        shift = [self.rows[i][1] for i in range(n)]
        widths = [self.rows[i][2] for i in range(n)]
        box = Box(basis, shift, widths)
        expected = self.expected()
        if sample and limit is not None and expected >= 8:
            points = box.sample(expected, limit, deadline, rng)
        else:
            points = box.every(limit, deadline)
        for v in points:
            yield dict(zip(self.names, v))

    def expected(self):
        """Lattice points expected in the box: volume / determinant."""
        vol = 1
        det = 1
        for i, (terms, _, width) in enumerate(self.rows):
            vol *= width
            det *= abs(terms[i])
        return vol / det


# ------------------------------------- mission-seed draws, in Python
# Ports of src/constellation_prediction.lua, side_objective_inputs.lua's
# environment pick and src/side_objective_prediction.lua. All three start a
# stream at the mission seed m (state = m).

def add_tag(tags, tag):
    if tag not in tags and len(tags) < 16:
        tags.append(tag)


def constellation_pool(settings, initial):
    """The candidates the draws choose between, and whether any draw can run."""
    tags = []
    for t in initial:
        add_tag(tags, t)
    empty = not tags
    pool = [row for row in settings['candidates']
            if row['id'] != 0 and (not row['only_when_empty'] or empty)]
    total = 0.0
    for row in pool:
        total = f32(total + row['weight'])
    return tags, pool, total


def pick_tag(pool, out):
    """The tag one draw adds for output `out`, or None."""
    i = weighted_index(out, [row['weight'] for row in pool])
    return pool[i - 1]['id'] if i else None


def finish_tags(tags, settings, kind, disabled):
    """Fallback, HordeOnly, exclusions and disabled tags after the draws."""
    tags = list(tags)
    fallback = settings['fallback']
    if fallback != 0 and fallback not in tags:
        blocked = False
        for blocker in settings['blockers']:
            if blocker == 0:
                break
            if blocker in tags:
                blocked = True
                break
        if not blocked:
            add_tag(tags, fallback)
    if kind['horde']:
        add_tag(tags, 1)
    for tag in kind['exclusions'] or []:
        if tag in tags:
            i = tags.index(tag)
            tags[i] = tags[-1]
            tags.pop()
    tags = [t for t in tags if t not in disabled]
    return sorted(t for t in tags if t != 0)


def constellation_tags(kind, initial, disabled, seed):
    """Constellations.resolve(...).list, or None when the mission's faction
    has no tags (constellation_runtime.lua leaves those unresolved)."""
    settings = kind['settings']
    if not settings:
        return None
    tags, pool, total = constellation_pool(settings, initial)
    rng = Rng(seed)
    for _ in range(settings['draws']):
        if not pool or total <= 0:
            break
        tag = pick_tag(pool, rng.next())
        if tag is not None:
            add_tag(tags, tag)
    return finish_tags(tags, settings, kind, disabled)


def environment_pick(table, state1):
    units, indices = table['units'], table['indices']
    if not units:
        return 0
    target = state1 % sum(units)
    acc = 0
    for unit, index in zip(units, indices):
        if unit != 0:
            acc += unit
            if target <= acc:
                return index
    return indices[-1]


def environment(kind, seed):
    """The biome environment byte the mission's objectives are filtered by:
    two picks of (one LCG step from the seed) modulo integer weight totals."""
    tables = kind['environment']
    if not tables:
        return 0
    state1 = (seed * MUL + INC) % M64
    biome = environment_pick(tables['biome'], state1)
    inner = next(t for t in tables['inner'] if t['biome'] == biome)
    return inner['ids'][environment_pick(inner, state1)]


class Objectives:
    """side_objective_prediction.lua R.resolve, split so the solver can walk
    its draws: setup() does everything before the first draw."""

    FLOOR = f32(1e-6)

    def __init__(self, records, rows):
        self.records = records          # pool id -> objective record
        self.row_of = rows              # objective id -> filter row

    def setup(self, kind, difficulty, counts, context, environment_value):
        rec_of = self.records
        mission = kind['objectives']
        pool = mission['pool']
        d = difficulty

        def in_range(r):
            return (r['minimum'] == 0 or r['minimum'] <= d) and (r['maximum'] == 0 or d <= r['maximum'])

        side = counts['side']
        if mission['scale'] is not False and mission['scale'] is not None:
            side = math.floor(f32(f32(side) * mission['scale']) + 0.5)
        taken, primary, primary_set, lo, hi, weight = [], None, False, 0, 0, 0.0
        for k, e in enumerate(pool):
            taken.append(0)
            if e['id'] != 0 and e['weight'] > 0:
                r = rec_of[e['id']]
                if in_range(r):
                    if e['role'] == 0:
                        primary = k if primary is None else primary
                        if not primary_set and e['minimum'] != 0:
                            primary_set = True
                    taken[k] = e['minimum']
                    if e['role'] <= 1:
                        cap = min(e['maximum'], r['cap'])
                        lo += e['minimum']
                        hi += cap
                        if e['minimum'] < cap:
                            weight = f32(weight + e['weight'])
        if not primary_set and primary is not None:
            taken[primary] += 1
        extra = 0
        if mission['lo'] < mission['hi']:
            t = f32(f32((d - mission['lo']) % M32) / f32(mission['hi'] - mission['lo']))
            target = math.floor(f32(f32(f32(1 - t) * f32(lo)) + f32(f32(hi) * t)) + 0.5) % M32
            upper = counts['substeps'] if counts['substeps'] > lo else lo
            if target < upper:
                upper = target
            extra = upper - lo
        return dict(pool=pool, taken=taken, weight=weight, extra=extra, side=side, in_range=in_range,
                    context=context, environment=environment_value)

    def substep_choices(self, s):
        """(entries eligible for a sub-step draw with their weights) in pool order."""
        out = []
        for k, e in enumerate(s['pool']):
            if (e['role'] < 2 or e['role'] > 4) and e['weight'] > 0:
                cap = min(e['maximum'], self.records[e['id']]['cap'])
                if s['taken'][k] < cap:
                    out.append((k, e['weight'], cap))
        return out

    def substep_pick(self, s, out):
        """The entry one sub-step draw picks (the last on no hit), or None
        when nothing is eligible: the draw is spent and the loop stops."""
        r = f32(f32(f32(out) * f32(1 / 4294967296)) * s['weight'])
        acc, last = 0.0, None
        for k, w, cap in self.substep_choices(s):
            acc = f32(acc + w)
            last = (k, w, cap)
            if r <= acc:
                return last
        return last and (last[0], None, None)

    def substep_apply(self, s, picked):
        k, w, cap = picked
        s['taken'][k] += 1
        if w is not None and cap <= s['taken'][k]:
            s['weight'] = f32(s['weight'] - w)

    def substep(self, s, out):
        """One sub-step draw; False when the loop stops after it."""
        picked = self.substep_pick(s, out)
        if picked is None:
            return False
        self.substep_apply(s, picked)
        return True

    def emit_minimums(self, s, emitted):
        """The minimum entries and the draw pools (roles 3, 2, 4)."""
        env = s['environment']

        def allowed(r):
            lst = r['environments']
            if lst[0] == 0:
                return True
            for k in range(4):
                if lst[k] == 0:
                    return False
                if lst[k] == env:
                    return True
            return False

        left = {3: s['side'], 2: s['counts_tactical'], 4: M32 - 1}
        pools = {3: [], 2: [], 4: []}
        for k, e in enumerate(s['pool']):
            if e['id'] != 0 and e['weight'] > 0:
                r = self.records[e['id']]
                if not r['disabled'] and allowed(r) and s['in_range'](r) and e['id'] not in s['context']['banned']:
                    for _ in range(s['taken'][k]):
                        role = e['role']
                        if role not in left:
                            emitted.append((e['id'], role))
                        elif left[role] != 0:
                            left[role] -= 1
                            emitted.append((e['id'], role))
                    if e['role'] in pools:
                        pools[e['role']].append(dict(id=r['id'], weight=e['weight'], cap=min(e['maximum'], r['cap']),
                                                     count=e['minimum'], mask=r['mask'], role=e['role']))
        return left, pools

    @staticmethod
    def draw_step(lst, n, mask):
        """The filtering pass before a draw: returns the live count."""
        k = 0
        while k < n:
            while not (n - 1 < k or (lst[k]['count'] < lst[k]['cap'] and (lst[k]['mask'] & mask) == 0)):
                lst[k] = lst[n - 1]
                n -= 1
            k += 1
        return n

    @staticmethod
    def draw_pick(lst, n, out):
        total = 0.0
        for j in range(n):
            total = f32(total + lst[j]['weight'])
        r = f32(f32(f32(out) * f32(1 / 4294967296)) * total)
        acc = 0.0
        for j in range(n):
            acc = f32(acc + lst[j]['weight'])
            if r <= acc:
                return j
        return None

    @staticmethod
    def draw_apply(lst, n, j, mask, remaining, emitted):
        e = lst[j]
        emitted.append((e['id'], e['role']))
        e['count'] += 1
        mask |= e['mask']
        remaining -= 1
        if e['cap'] <= e['count']:
            lst[j] = lst[n - 1]
            n -= 1
        return n, mask, remaining

    def resolve(self, kind, difficulty, counts, context, environment_value, seed):
        """R.resolve: [(objective id, role)] in native order."""
        out = []
        if difficulty == 0:
            return out
        rng = Rng(seed)
        s = self.setup(kind, difficulty, counts, context, environment_value)
        s['counts_tactical'] = counts['tactical']
        extra = s['extra']
        while extra != 0 and s['weight'] > self.FLOOR:
            if not self.substep(s, rng.next()):
                break
            extra -= 1
        left, pools = self.emit_minimums(s, out)
        for role in (3, 2, 4):
            lst = [dict(e) for e in pools[role]]
            n, mask, remaining = len(lst), 0, left[role]
            if n == 0:
                continue
            while True:
                if remaining == 0:
                    break
                n = self.draw_step(lst, n, mask)
                value = rng.next()
                if n == 0:
                    break
                j = self.draw_pick(lst, n, value)
                if j is not None:
                    n, mask, remaining = self.draw_apply(lst, n, j, mask, remaining, out)
                if n == 0:
                    break
        if context['extra']:
            out.append((0x68bfbb59, 2))
        return out

    def rows(self, objectives):
        """R.set: the filter rows of the side (3) and tactical (2) objectives."""
        return {self.row_of[i] for i, role in objectives if role in (2, 3) and i in self.row_of}


# ------------------------------------------------ the generator, in Python
# A port of the stages the prototype inverts, fed by the tables
# scripts/seed_solver_oracle.lua exports. Checked against the Lua predictor.

class Planet:
    def __init__(self, tables):
        self.t = tables
        self.planet = tables['planet']
        self.pool = tables['pool_count']
        self.max_difficulty = tables['max_difficulty']
        self.active = tables.get('active') or None
        assert not tables.get('specials'), 'special operations are outside this prototype'
        self.ops = {(o['difficulty'], o['id']): o for o in tables['operations']}
        for o in tables['operations']:
            o['category_of'] = {k: c for k, c in o['mission_categories']}
            for tpl in o['templates']:
                tpl['weight_of'] = {k: w for k, w in tpl['weights']}
            # Mission-seed inputs, when the export has them.
            o['kind_of'] = {k['kind']: k for k in o.get('kinds', [])}
            if 'context' in o:
                o['context']['banned'] = set(o['context']['banned'] or [])
                o['initial_tags'] = list(o['initial_tags'] or [])
        self.disabled_tags = set(tables.get('disabled_tags') or [])
        records = {r['pool_id']: r for r in tables.get('objectives', [])}
        rows = {r['id']: r['row'] for r in tables.get('objective_rows', [])}
        self.objectives = Objectives(records, rows)
        self.row_names = {r['row']: r['name'] for r in tables.get('objective_rows', [])}
        self.tag_names = {t: n for t, n in tables.get('tag_names', [])}
        self.kind_names = {k: n for k, n in tables.get('kind_names', [])}
        self.seeded = all('kinds' in o for o in tables['operations'])

    def mission_details(self, op, kind, seed):
        """(enemy tags or None, [(objective id, role)], environment) of a mission."""
        info = op['kind_of'][kind]
        tags = constellation_tags(info, op['initial_tags'], self.disabled_tags, seed)
        env = environment(info, seed)
        objectives = self.objectives.resolve(info, op['difficulty'], op['counts'], op['context'], env, seed)
        return tags, objectives, env

    # operation_identity.lua --------------------------------------------
    def rows(self, seed):
        rows = {}
        if self.active:
            a = self.active
            rows[a['row']] = dict(row=a['row'], id=a['id'], seed=a['seed'], difficulty=a['difficulty'], preserved=True)

        def mark(difficulty, mask):
            first = (difficulty - 1) * 3
            for r in range(first, first + 4):
                if r in rows:
                    mask.add(rows[r]['id'])

        def choose(rng, mask):
            start = rng.index(self.pool)
            for off in range(self.pool):
                i = (start + off) % self.pool
                if i not in mask:
                    return i
            return None

        every = set()
        for d in range(1, self.max_difficulty + 1):
            mark(d, every)
        rng = Rng(seed, self.planet)
        for d in range(1, self.max_difficulty + 1):
            used = set()
            mark(d, used)
            for r in range((d - 1) * 3, d * 3):
                if r not in rows:
                    i = choose(rng, every)
                    if i is None:
                        i = choose(rng, used)
                    if i is not None:
                        rows[r] = dict(row=r, id=i, seed=rng.next(), difficulty=d)
                        every.add(i)
                        used.add(i)
        return [rows[r] for r in sorted(rows)]

    def draw_positions(self, row):
        """Campaign-stream positions of a generated row's ID and seed draws,
        assuming no ID fallback (true while the pool outnumbers the rows)."""
        before = sum(1 for r in range(row) if not (self.active and self.active['row'] == r))
        return 2 * before + 1, 2 * before + 2

    # operation_finalization.lua, mission composition -------------------
    def finalize(self, op, seed):
        rng = Rng(seed)
        templates = op['templates']
        i = weighted_index(rng.next(), [t['weight'] for t in templates]) if templates else None
        if i is None:
            return None, []
        template = templates[i - 1]
        budget = op['budget']
        pool = list(template['modifiers'])
        modifiers = []
        while pool and len(modifiers) < 2:
            j = 0
            while j < len(pool):
                if pool[j]['cost'] > budget:
                    pool[j] = pool[-1]
                    pool.pop()
                else:
                    j += 1
            if not pool:
                break
            k = weighted_index(rng.next(), [p['weight'] for p in pool]) - 1
            item = pool[k]
            modifiers.append(item['id'])
            budget -= item['cost']
            pool[k] = pool[-1]
            pool.pop()
        return template, modifiers

    @staticmethod
    def category_step(template, usage):
        """mission_category_choice.lua up to its draw: (forced category, or
        None with the categories and weights a draw chooses between)."""
        rules = template['rules']
        if not rules:
            return 0, None
        for rule in rules:
            if rule['minimum'] != 0 and usage.get(rule['category'], 0) < rule['minimum']:
                return rule['category'], None
        available, seen = [], set()
        for cand in template['candidates']:
            cat = cand['category']
            if cat in seen:
                continue
            blocked = False
            for rule in rules:
                if rule['category'] == cat:
                    blocked = rule['maximum'] != 0 and usage.get(cat, 0) >= rule['maximum']
                    break
            if not blocked:
                available.append(cat)
                seen.add(cat)
        if len(available) == 1:
            return available[0], None
        if len(available) > 1:
            weights = []
            for cat in available:
                w = next((r['weight'] for r in rules if r['category'] == cat), None)
                weights.append((cat, w))
            listed = [(c, w) for c, w in weights if w is not None]
            total = 0.0
            for _, w in listed:
                total = f32(total + f32(w))
            if total > 0:
                return None, listed
        return 0, None

    @staticmethod
    def pick_category(listed, out):
        i = weighted_index(out, [w for _, w in listed])
        return listed[i - 1][0] if i else 0

    @staticmethod
    def eligible(template, category):
        sel = [c['id'] for c in template['candidates'] if category == 0 or c['category'] == category]
        if not sel and category != 0:
            sel = [c['id'] for c in template['candidates']]
        return sel

    @staticmethod
    def mission_pool(eligible, weights, counts):
        """mission_weighted_choice.lua: the kinds a draw chooses between, or
        a single kind chosen without a draw."""
        minimum = min(counts.get(k, 0) for k in eligible)
        if len(eligible) == 1:
            return eligible[0], None
        return None, [(k, weights[k]) for k in eligible if counts.get(k, 0) == minimum and k in weights]

    @staticmethod
    def pick_mission(listed, out):
        i = weighted_index(out, [w for _, w in listed])
        assert i, 'No weighted mission candidate'
        return listed[i - 1][0]

    def compose(self, op, seed):
        """Missions of one operation: [(kind, mission seed, level)]."""
        template, modifiers = self.finalize(op, seed)
        if template is None:
            return None, modifiers, []
        assert not op['special'] and not op['extra'], 'special levels and modifier missions are outside this prototype'
        levels = op['levels']
        rng = Rng(seed)
        usage, counts, missions = {}, {}, []
        for slot in range(op['total']):
            forced, listed = self.category_step(template, usage)
            category = forced if listed is None else self.pick_category(listed, rng.next())
            eligible = self.eligible(template, category)
            if not eligible or slot >= len(levels):
                continue
            level = levels[slot]
            mseed = rng.next()
            kind, pool = self.mission_pool(eligible, template['weight_of'], counts)
            if pool is not None:
                kind = self.pick_mission(pool, Rng(mseed, seed).next())
                counts[kind] = counts.get(kind, 0) + 1
            cat = op['category_of'][kind]
            usage[cat] = usage.get(cat, 0) + 1
            missions.append((kind, mseed, level))
        return template, modifiers, missions

    def board(self, seed, difficulty=None, details=False):
        """Predicted operations; with `difficulty`, only that difficulty's,
        as the in-game search predicts. With `details`, each mission also
        carries its enemy tags, objectives and environment."""
        result = []
        for row in self.rows(seed):
            if row.get('preserved') or (difficulty is not None and row['difficulty'] != difficulty):
                continue
            op = self.ops[(row['difficulty'], row['id'])]
            template, modifiers, missions = self.compose(op, row['seed'])
            if details:
                missions = [m + self.mission_details(op, m[0], m[1]) for m in missions]
            result.append(dict(row=row['row'], id=row['id'], seed=row['seed'], difficulty=row['difficulty'],
                               template_index=template['index'] if template else None,
                               modifiers=modifiers, missions=missions))
        return result

    # mission-seed paths ------------------------------------------------
    @staticmethod
    def _merge(a, b):
        """Intersect two {position: (lo, hi)} maps; None when empty."""
        out = dict(a)
        for p, (lo, hi) in b.items():
            if p in out:
                lo, hi = max(lo, out[p][0]), min(hi, out[p][1])
                if lo > hi:
                    return None
            out[p] = (lo, hi)
        return out

    @staticmethod
    def _mass(draws, mods):
        p = 1.0
        for lo, hi in draws.values():
            p *= (hi - lo + 1) / M32
        for modulus, lo, hi in mods:
            p *= (hi - lo + 1) / modulus
        return p

    @staticmethod
    def _environment_branches(info):
        """[(environment value, [(modulus, lo, hi)])]: every (biome, inner
        pick) pair as constraints on state1 mod each weight total."""
        tables = info['environment']
        if not tables:
            return [(0, [])]

        def ranges(table):
            units, indices = table['units'], table['indices']
            if not units:
                return None, [(0, None)]
            total, acc, out, first = sum(units), 0, [], True
            for unit, index in zip(units, indices):
                if unit != 0:
                    lo = 0 if first else acc + 1
                    acc += unit
                    first = False
                    out.append((index, (lo, acc)))
            return total, out

        out = []
        t1, biomes = ranges(tables['biome'])
        for biome, r1 in biomes:
            inner = next(t for t in tables['inner'] if t['biome'] == biome)
            t2, picks = ranges(inner)
            for pick, r2 in picks:
                mods = []
                if t1 is not None and r1 is not None and (r1[1] - r1[0] + 1) < t1:
                    mods.append((t1, *r1))
                if t2 is not None and r2 is not None and (r2[1] - r2[0] + 1) < t2:
                    mods.append((t2, *r2))
                out.append((inner['ids'][pick], mods))
        return out

    def _tag_paths(self, op, info, rule):
        """[{position: (lo, hi)}] for enemy-tag draws that satisfy `rule`
        (tag -> 'accept' | 'exclude'), as search_session.lua satisfies()."""
        if not rule:
            return [{}]
        settings = info['settings']
        if not settings:
            return []  # unresolved tags never satisfy a rule
        tags0, pool, total = constellation_pool(settings, op['initial_tags'])
        draws = settings['draws'] if pool and total > 0 else 0
        parts = partition(lambda o: pick_tag(pool, o)) if draws else []
        wanted = [t for t, mode in rule.items() if mode != 'exclude']
        out = []
        for combo in itertools.product(parts, repeat=draws):
            tags = list(tags0)
            for tag, _, _ in combo:
                if tag is not None:
                    add_tag(tags, tag)
            final = set(finish_tags(tags, settings, info, self.disabled_tags))
            if any(mode == 'exclude' and t in final for t, mode in rule.items()):
                continue
            if wanted and not any(t in final for t in wanted):
                continue
            out.append({i + 1: (a, b) for i, (_, a, b) in enumerate(combo) if (a, b) != (0, M32 - 1)})
        return out

    def _objective_paths(self, op, info, rule, env):
        """[{position: (lo, hi)}] for side-objective draws that emit every
        required row. Only the draws a required row depends on are
        constrained: sub-steps and pools holding no required row are skipped
        by how many draws they spend (one branch per possible count), and
        excluded rows are left to the forward check. Every solution is
        checked forward, so this trades some rejections for far fewer
        lattices; a count branch that is not taken is simply rejected."""
        O = self.objectives
        if not rule:
            return [{}]
        need = {r for r, mode in rule.items() if mode == 'require'}
        avoid = {r for r, mode in rule.items() if mode == 'exclude'}
        s = O.setup(info, op['difficulty'], op['counts'], op['context'], env)
        s['counts_tactical'] = op['counts']['tactical']
        emitted = []
        left, pools = O.emit_minimums(s, emitted)
        rows = O.rows(emitted)
        if rows & avoid:
            return []  # a fixed objective is excluded
        offered = {r for role in (3, 2) for r in O.rows([(e['id'], role) for e in pools[role]])}
        if not need <= rows | offered:
            return []  # a required row can never be drawn here
        out = []
        for count in sorted(self._substep_counts(s)):
            self._draw_walk(pools, left, [3, 2], rows, need, count + 1, {}, out)
        return out

    def _substep_counts(self, s):
        """How many draws the sub-step loop can spend (1756730)."""
        O = self.objectives
        counts = set()

        def walk(s, extra, spent):
            if extra == 0 or s['weight'] <= O.FLOOR:
                counts.add(spent)
                return
            for picked, _, _ in partition(lambda o: O.substep_pick(s, o)):
                if picked is None:
                    counts.add(spent + 1)
                    continue
                t = dict(s, taken=list(s['taken']))
                O.substep_apply(t, picked)
                walk(t, extra - 1, spent + 1)

        walk(s, s['extra'], 0)
        return counts

    def _role_counts(self, lst, remaining):
        """How many draws one pool's loop can spend (1757870)."""
        O = self.objectives
        counts = set()

        def walk(lst, n, mask, remaining, spent):
            if remaining == 0:
                counts.add(spent)
                return
            lst = [dict(e) for e in lst]
            n = O.draw_step(lst, n, mask)
            if n == 0:
                counts.add(spent + 1)
                return
            for j, _, _ in partition(lambda o: O.draw_pick(lst, n, o)):
                if j is None:
                    continue
                l2 = [dict(e) for e in lst]
                n2, mask2, rem2 = O.draw_apply(l2, n, j, mask, remaining, [])
                if n2 == 0:
                    counts.add(spent + 1)
                else:
                    walk(l2, n2, mask2, rem2, spent + 1)

        if lst and remaining:
            walk(lst, len(lst), 0, remaining, 0)
        else:
            counts.add(0)
        return counts

    def _draw_walk(self, pools, left, roles, rows, need, position, draws, out, state=None):
        """Walk 1757870 draws of the side (3) then tactical (2) pools until
        every required row is drawn."""
        O = self.objectives
        if need <= rows:
            out.append(draws)
            return
        if state is None:
            if not roles:
                return  # pools exhausted without every required row
            role = roles[0]
            lst = [dict(e) for e in pools[role]]
            if not need & O.rows([(e['id'], role) for e in lst]):
                # Nothing required comes from this pool: only its draw count matters.
                for spent in sorted(self._role_counts(lst, left[role])):
                    self._draw_walk(pools, left, roles[1:], rows, need, position + spent, draws, out)
                return
            if not lst:
                return self._draw_walk(pools, left, roles[1:], rows, need, position, draws, out)
            state = (role, lst, len(lst), 0, left[role])
        role, lst, n, mask, remaining = state
        if remaining == 0:
            return self._draw_walk(pools, left, roles[1:], rows, need, position, draws, out)
        lst = [dict(e) for e in lst]
        n = O.draw_step(lst, n, mask)
        if n == 0:  # the draw is spent and the pool ends
            return self._draw_walk(pools, left, roles[1:], rows, need, position + 1, draws, out)
        for j, a, b in partition(lambda o: O.draw_pick(lst, n, o)):
            d = self._merge(draws, {position: (a, b)})
            if j is None or d is None:
                continue
            l2 = [dict(e) for e in lst]
            emitted = []
            n2, mask2, rem2 = O.draw_apply(l2, n, j, mask, remaining, emitted)
            new = O.rows(emitted)
            if n2 == 0:
                self._draw_walk(pools, left, roles[1:], rows | new, need, position + 1, d, out)
            else:
                self._draw_walk(pools, left, roles, rows | new, need, position + 1, d, out,
                                (role, l2, n2, mask2, rem2))

    def mission_paths(self, op, kind, rule):
        """Constraint sets on one mission's seed stream that satisfy `rule`
        ({'tags': {...}, 'objectives': {...}}): [{draws, mods, probability}]."""
        info = op['kind_of'][kind]
        rule = rule or {}
        tag_paths = self._tag_paths(op, info, rule.get('tags'))
        if not tag_paths:
            return []
        objective_rule = rule.get('objectives')
        envs = self._environment_branches(info) if objective_rule else [(None, [])]
        if objective_rule and len({e for e, _ in envs}) == 1:
            envs = [(envs[0][0], [])]  # one reachable environment: no constraint
        cache = {}
        for env, _ in envs:
            if env not in cache:
                cache[env] = self._objective_paths(op, info, objective_rule, env)
        if len(cache) > 1 and all(paths == next(iter(cache.values())) for paths in cache.values()):
            envs = [(next(iter(cache)), [])]  # the environment changes nothing here
        out = []
        for env, mods in envs:
            for objective_draws in cache[env]:
                for tag_draws in tag_paths:
                    draws = self._merge(tag_draws, objective_draws)
                    if draws is not None:
                        out.append(dict(draws=draws, mods=mods, probability=self._mass(draws, mods)))
        out.sort(key=lambda p: -p['probability'])
        return out

    # path enumeration --------------------------------------------------
    def shared_paths(self, difficulty, required, rules=None):
        """The draw paths for `required` at a difficulty, when every operation
        ID there has the same ones (IDs differing only in level tiles), else
        None: the row's ID then has to be constrained as well."""
        # Paths depend on an operation's inputs, not its ID, its effect id or
        # its level tiles (only their count): equal inputs, equal paths.
        derived = ('id', 'effect_id', 'levels', 'category_of', 'kind_of')

        def signature(op):
            plain = {k: v for k, v in op.items() if k not in derived}
            plain['levels'] = len(op['levels'])
            return json.dumps(plain, sort_keys=True, default=sorted)

        ops = [op for (d, _), op in self.ops.items() if d == difficulty]
        if len({signature(op) for op in ops}) != 1:
            return None
        return self.paths(ops[0], required, rules)

    # filter matching, as search_session.lua find() ----------------------
    def satisfies(self, mission, rule):
        """One mission (kind, seed, level, tags, objectives, env) against its
        rules: an accepted tag if any is accepted, no excluded tag, every
        required objective row and no excluded one."""
        if not rule:
            return True
        tags, objectives = mission[3], mission[4]
        trule = rule.get('tags') or {}
        if trule:
            if tags is None:
                return False
            if any(mode == 'exclude' and t in tags for t, mode in trule.items()):
                return False
            wanted = [t for t, mode in trule.items() if mode != 'exclude']
            if wanted and not any(t in tags for t in wanted):
                return False
        rows = self.objectives.rows(objectives)
        for row, mode in ((rule or {}).get('objectives') or {}).items():
            if (mode == 'require') != (row in rows):
                return False
        return True

    def matches(self, board, difficulty, required, rules=None, scope='any'):
        """`any`: some operation at the difficulty has a mission of every
        required kind meeting its rules; `all`: every operation there does.
        Missions must carry details (board(..., details=True))."""
        rules = rules or {}
        hits = total = 0
        for op in board:
            if op['difficulty'] != difficulty:
                continue
            total += 1
            found = {m[0] for m in op['missions'] if m[0] in required and self.satisfies(m, rules.get(m[0]))}
            hits += set(required) <= found
        return hits > 0 if scope == 'any' else total > 0 and hits == total

    def paths(self, op, required, rules=None):
        """Every draw path through one operation's composition that yields all
        `required` kinds, as constraint lists for the operation seed y:
        ('direct', position, lo, hi) on the composition stream, or
        ('mission', position, lo, hi): the position-th output m, then the
        first output of the stream seeded (m + y) mod 2^32 lies in [lo, hi].
        Draws after the last required mission are left free. The finalizer
        stream is constrained only when the template choice is not forced.

        `rules` maps a required kind to its mission rules ({'tags': {tag:
        'accept'|'exclude'}, 'objectives': {row: 'require'|'exclude'}}); a
        slot of that kind delivers it only through a mission_paths() branch,
        added to its ('mission', ...) step as a fifth element."""
        assert not op['special'] and not op['extra'], 'special levels and modifier missions are outside this prototype'
        templates = op['templates']
        weights = [t['weight'] for t in templates]
        self._rules = rules or {}
        self._mission_cache = {}
        out = []
        for i, first, last in partition(lambda o: weighted_index(o, weights)):
            if i is None:
                continue
            base = [] if (first, last) == (0, M32 - 1) else [('final', 1, first, last)]
            template = templates[i - 1]
            self._walk(op, template, required, 0, 1, {}, {}, [], base, 1.0 * (last - first + 1) / M32, out)
        out.sort(key=lambda p: -p['probability'])
        return out

    def _deliveries(self, op, kind, missing):
        """(delivers, mission step extra, probability) branches for one slot."""
        rule = self._rules.get(kind)
        if kind not in missing or not rule:
            return [(kind in missing, None, 1.0)]
        if kind not in self._mission_cache:
            self._mission_cache[kind] = self.mission_paths(op, kind, rule)
        branches = [(True, dict(draws=mp['draws'], mods=mp['mods']), mp['probability'])
                    for mp in self._mission_cache[kind]]
        # The slot may also hold the kind without meeting its rules.
        return branches + [(False, None, 1.0)]

    def _walk(self, op, template, required, slot, position, usage, counts, kinds, constraints, probability, out):
        missing = [k for k in required if k not in kinds]
        if not missing:
            out.append(dict(template=template['index'], kinds=list(kinds), constraints=list(constraints),
                            probability=probability))
            return
        if slot >= op['total'] or op['total'] - slot < len(missing):
            return
        forced, listed = self.category_step(template, usage)
        branches = []
        if listed is None:
            branches.append((forced, position, None))
        else:
            for category, first, last in partition(lambda o: self.pick_category(listed, o)):
                branches.append((category, position + 1, ('direct', position, first, last)))
        for category, at, step in branches:
            p = probability * (1 if step is None else (step[3] - step[2] + 1) / M32)
            cons = constraints + ([step] if step else [])
            eligible = self.eligible(template, category)
            if not eligible or slot >= len(op['levels']):
                self._walk(op, template, required, slot + 1, at, usage, counts, kinds, cons, p, out)
                continue
            seed_position = at
            kind, pool = self.mission_pool(eligible, template['weight_of'], counts)
            if pool is None:
                choices = [(kind, None)]
            else:
                choices = [(k, ('mission', seed_position, a, b)) for k, a, b in
                           partition(lambda o: self.pick_mission(pool, o))]
            for kind, mstep in choices:
                c2 = dict(counts)
                if pool is not None:
                    c2[kind] = c2.get(kind, 0) + 1
                u2 = dict(usage)
                cat = op['category_of'][kind]
                u2[cat] = u2.get(cat, 0) + 1
                q = p * (1 if mstep is None else (mstep[3] - mstep[2] + 1) / M32)
                for delivers, mission, mp in self._deliveries(op, kind, missing):
                    if not delivers and op['total'] - slot - 1 < len(missing):
                        continue  # this slot must deliver a missing kind
                    step = mstep
                    if mission is not None:
                        lo, hi = (mstep[2], mstep[3]) if mstep else (None, None)
                        step = ('mission', seed_position, lo, hi, mission)
                    self._walk(op, template, required, slot + 1, seed_position + 1, u2, c2,
                               kinds + [kind] if delivers else kinds, cons + ([step] if step else []), q * mp, out)


def _constrain(s, y, path, tag=''):
    for n, step in enumerate(path['constraints']):
        kind, position, lo, hi = step[:4]
        if kind == 'final' or kind == 'direct':
            # Finalizer and composition streams both start at y.
            s.output_in(f'{kind}{n}{tag}', y, position, lo, hi)
            continue
        # A mission: its seed m is the position-th composition draw. The kind
        # draw starts at (m + y) mod 2^32; enemy tags, the environment and
        # side objectives start at m itself.
        m = s.high(f'm{n}{tag}', y, position)
        if lo is not None:
            u = s.add32(f'u{n}{tag}', m, y)
            s.output_in(f'kind{n}{tag}', u, 1, lo, hi)
        mission = step[4] if len(step) > 4 else None
        if mission:
            for p, (a, b) in sorted(mission['draws'].items()):
                s.output_in(f'm{n}.{p}{tag}', m, p, a, b)
            if mission['mods']:
                state1 = s.state(f'm{n}.s1{tag}', m, 1)
                for i, (modulus, a, b) in enumerate(mission['mods']):
                    s.mod_in(f'm{n}.env{i}{tag}', state1, modulus, a, b)


def operation_system(path, campaign=None):
    """The lattice for one path. Without `campaign`, the unknown is the
    operation seed y alone. With campaign=(planet_model, row, op_id), the
    unknown is the campaign stream start x, tied to y through the row's seed
    draw; an op_id other than None requires the row's ID draw to start there."""
    if campaign:
        planet, row, op_id = campaign
        return campaign_system(planet, [(row, op_id, path)])
    s = System()
    y, _ = s.var('y')
    _constrain(s, y, path)
    return s


def campaign_system(planet, picks):
    """One lattice for several rows of one board: picks are (row, op_id or
    None, path), all drawn from the campaign stream start x."""
    s = System()
    x, _ = s.var('x')
    for row, op_id, path in picks:
        id_at, seed_at = planet.draw_positions(row)
        if op_id is not None:
            parts = [(v, a, b) for v, a, b in
                     partition(lambda o: min(planet.pool - 1, math.floor(o * (1 / 4294967296) * planet.pool)))
                     if v == op_id]
            (_, a, b), = parts
            s.output_in(f'id@{row}', x, id_at, a, b)
        y = s.high(f'y@{row}', x, seed_at)
        _constrain(s, y, path, f'@{row}')
    return s
