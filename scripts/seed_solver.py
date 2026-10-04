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

import math
import struct
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


def enumerate_box(basis, shift, widths, limit=None):
    """Yield every v = shift + sum_j z_j*basis[j] (z integer) with
    0 <= v_i < widths[i]. basis is square and independent (rows are vectors).

    Each coordinate is scaled to a unit interval, the basis is LLL-reduced,
    and the points inside the ball around the box centre are enumerated
    (Fincke-Pohst) and checked exactly. With `limit`, stop after that many."""
    n = len(basis)
    scaled = [[(basis[j][i] << 64) // widths[i] for i in range(n)] for j in range(n)]
    h = lll(scaled)
    red = [[sum(h[r][j] * basis[j][i] for j in range(n)) for i in range(n)] for r in range(n)]
    centre = [Fraction(w, 2) for w in widths]
    z = _solve_rational(red, [c - s for c, s in zip(centre, shift)])
    z0 = [round(v) for v in z]
    p0 = [shift[i] + sum(z0[j] * red[j][i] for j in range(n)) for i in range(n)]
    bf = [[red[j][i] / widths[i] for i in range(n)] for j in range(n)]
    q = [float(Fraction(p0[i]) / widths[i] - Fraction(1, 2)) for i in range(n)]
    # Gram-Schmidt of the scaled reduced rows.
    star, norm, mu = [], [], [[0.0] * n for _ in range(n)]
    for j in range(n):
        v = list(bf[j])
        for k in range(j):
            mu[j][k] = sum(x * y for x, y in zip(bf[j], star[k])) / norm[k]
            v = [x - mu[j][k] * y for x, y in zip(v, star[k])]
        star.append(v)
        norm.append(sum(x * x for x in v))
    tau = [sum(x * y for x, y in zip(q, star[k])) / norm[k] for k in range(n)]
    radius2 = n / 4 * (1 + 1e-9) + 1e-9
    delta = [0] * n
    found = 0
    # Coordinates no row below k can change are fixed once rows k..n-1 are
    # chosen: check them there instead of at every leaf. Without this, a
    # dense sublattice that leaves a mission draw untouched is walked in
    # full for every wrong choice of that draw.
    settled = [[i for i in range(n) if all(red[j][i] == 0 for j in range(k))] for k in range(n)]

    def inside(k):
        for i in settled[k]:
            v = p0[i] + sum(delta[j] * red[j][i] for j in range(k, n))
            if not 0 <= v < widths[i]:
                return False
        return True

    # The general form of the same test. Once rows k..n-1 are chosen, the
    # point is fixed outside span(star[0..k-1]); what the lower rows add lies
    # in that span with length at most sqrt(budget left), so it moves
    # coordinate i by at most reach[k][i]*sqrt(budget). A branch that cannot
    # bring every coordinate back into the box is cut. In many dimensions the
    # ball is far larger than the box, and this cut is what keeps the walk
    # near the solutions.
    reach = [[math.sqrt(sum(star[l][i] ** 2 / norm[l] for l in range(k))) for i in range(n)] for k in range(n)]
    slack = 0.5 + 1e-6

    def walk(k, budget, acc):
        nonlocal found
        if k < 0:
            v = [p0[i] + sum(delta[j] * red[j][i] for j in range(n)) for i in range(n)]
            if all(0 <= v[i] < widths[i] for i in range(n)):
                found += 1
                yield v
            return
        centre_k = -(tau[k] + sum(delta[j] * mu[j][k] for j in range(k + 1, n)))
        span = math.sqrt(max(budget, 0.0) / norm[k])
        # Nearest values first (Schnorr-Euchner): points close to the box
        # centre are inside it, so a dense system yields at once.
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
            if any(abs(a) - r * left > slack for a, r in zip(nxt, out)):
                continue
            if inside(k):
                yield from walk(k - 1, budget - used, nxt)
                if limit is not None and found >= limit:
                    return
        delta[k] = 0

    yield from walk(n - 1, radius2, [0.0] * n)


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

    def solve(self, limit=None):
        n = len(self.rows)
        basis = [[self.rows[i][0].get(j, 0) for i in range(n)] for j in range(n)]
        shift = [self.rows[i][1] for i in range(n)]
        widths = [self.rows[i][2] for i in range(n)]
        for v in enumerate_box(basis, shift, widths, limit):
            yield dict(zip(self.names, v))

    def expected(self):
        """Lattice points expected in the box: volume / determinant."""
        vol = 1
        det = 1
        for i, (terms, _, width) in enumerate(self.rows):
            vol *= width
            det *= abs(terms[i])
        return vol / det


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

    def board(self, seed, difficulty=None):
        """Predicted operations; with `difficulty`, only that difficulty's,
        as the in-game search predicts."""
        result = []
        for row in self.rows(seed):
            if row.get('preserved') or (difficulty is not None and row['difficulty'] != difficulty):
                continue
            op = self.ops[(row['difficulty'], row['id'])]
            template, modifiers, missions = self.compose(op, row['seed'])
            result.append(dict(row=row['row'], id=row['id'], seed=row['seed'], difficulty=row['difficulty'],
                               template_index=template['index'] if template else None,
                               modifiers=modifiers, missions=missions))
        return result

    # path enumeration --------------------------------------------------
    def shared_paths(self, difficulty, required):
        """The draw paths for `required` at a difficulty, when every operation
        ID there has the same ones (IDs differing only in level tiles), else
        None: the row's ID then has to be constrained as well."""
        found = None
        for (d, _), op in self.ops.items():
            if d != difficulty:
                continue
            paths = self.paths(op, required)
            if found is None:
                found = paths
            elif paths != found:
                return None
        return found

    def paths(self, op, required):
        """Every draw path through one operation's composition that yields all
        `required` kinds, as constraint lists for the operation seed y:
        ('direct', position, lo, hi) on the composition stream, or
        ('mission', position, lo, hi): the position-th output m, then the
        first output of the stream seeded (m + y) mod 2^32 lies in [lo, hi].
        Draws after the last required mission are left free. The finalizer
        stream is constrained only when the template choice is not forced."""
        assert not op['special'] and not op['extra'], 'special levels and modifier missions are outside this prototype'
        templates = op['templates']
        weights = [t['weight'] for t in templates]
        out = []
        for i, first, last in partition(lambda o: weighted_index(o, weights)):
            if i is None:
                continue
            base = [] if (first, last) == (0, M32 - 1) else [('final', 1, first, last)]
            template = templates[i - 1]
            self._walk(op, template, required, 0, 1, {}, {}, [], base, 1.0 * (last - first + 1) / M32, out)
        out.sort(key=lambda p: -p['probability'])
        return out

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
                if kind not in missing and op['total'] - slot - 1 < len(missing):
                    continue  # this slot must deliver a missing kind
                c2 = dict(counts)
                if pool is not None:
                    c2[kind] = c2.get(kind, 0) + 1
                u2 = dict(usage)
                cat = op['category_of'][kind]
                u2[cat] = u2.get(cat, 0) + 1
                q = p * (1 if mstep is None else (mstep[3] - mstep[2] + 1) / M32)
                self._walk(op, template, required, slot + 1, seed_position + 1, u2, c2, kinds + [kind],
                           cons + ([mstep] if mstep else []), q, out)


def _constrain(s, y, path, tag=''):
    for n, (kind, position, lo, hi) in enumerate(path['constraints']):
        if kind == 'final' or kind == 'direct':
            # Finalizer and composition streams both start at y.
            s.output_in(f'{kind}{n}{tag}', y, position, lo, hi)
        else:
            m = s.high(f'm{n}{tag}', y, position)
            u = s.add32(f'u{n}{tag}', m, y)
            s.output_in(f'kind{n}{tag}', u, 1, lo, hi)


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
