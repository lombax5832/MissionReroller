"""Feasibility proof for solving campaign seeds from a mission filter.

    python -B scripts/prove_seed_solver.py [--capture <oracle.lua>] [--work <dir>]

Uses the saved planet 268 campaign capture (main checkout artifacts) and the
mod's own Lua predictor (scripts/seed_solver_oracle.lua) as ground truth:

1. The Python port of the generator (seed_solver.Planet) reproduces the Lua
   prediction on random campaign seeds.
2. Every operation seed on those boards inverts to its campaign seed.
3. Filters are solved directly: each solved campaign seed is checked by the
   port and then by the Lua predictor. A filter the generator cannot satisfy
   is reported as having no draw path, without any search.
4. The same filters are searched by brute force for comparison.
"""
import argparse
import itertools
import json
import math
import os
import random
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import seed_solver as S  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def artifacts():
    for base in [ROOT, *ROOT.parents]:
        if (base / 'artifacts/level-capture-oracle.lua').exists():
            return base / 'artifacts'
    return ROOT / 'artifacts'


def oracle(*args):
    lua = os.environ['HD2_LUAJIT']
    subprocess.run([lua, str(ROOT / 'scripts/seed_solver_oracle.lua'), *map(str, args)], check=True, cwd=ROOT)


def lua_boards(capture, work, seeds):
    listing = work / 'seeds.txt'
    listing.write_text(''.join(f'{s}\n' for s in seeds))
    out = work / 'predicted.json'
    oracle('predict', ROOT / 'src', capture, listing, out)
    return {b['seed']: b['operations'] for b in json.loads(out.read_text())}


def matches(board, difficulty, required):
    """Rows at `difficulty` whose missions include every required kind."""
    return [op['row'] for op in board if op['difficulty'] == difficulty
            and all(k in [m[0] for m in (op['missions'] or [])] for k in required)]


def ok(board, difficulty, required, scope):
    """`any`: some operation at the difficulty holds every required kind;
    `all`: every operation there does."""
    rows = [op for op in board if op['difficulty'] == difficulty]
    hits = matches(board, difficulty, required)
    return bool(hits) if scope == 'any' else len(hits) == len(rows)


def check_port(planet, boards):
    ops = bad = 0
    for seed, board in boards.items():
        mine = {o['row']: o for o in planet.board(seed)}
        for o in board:
            if planet.active and o['row'] == planet.active['row']:
                continue
            m = mine[o['row']]
            ops += 1
            mods = o['modifiers'] if isinstance(o['modifiers'], list) else []
            lua = (o['id'], o['seed'], o['template_index'], mods, [tuple(x) for x in (o['missions'] or [])])
            py = (m['id'], m['seed'], m['template_index'], m['modifiers'], [tuple(x) for x in m['missions']])
            bad += lua != py
    print(f'1. Port: {len(boards)} boards, {ops} operations, {bad} differences from the Lua predictor')
    assert bad == 0


def check_inversion(planet, boards):
    started = time.perf_counter()
    count = candidates = 0
    for seed, board in boards.items():
        for o in board:
            if planet.active and o['row'] == planet.active['row']:
                continue
            _, at = planet.draw_positions(o['row'])
            found = list(S.campaign_seeds_for(o['seed'], at, planet.planet))
            assert seed in found, (seed, o['row'])
            count += 1
            candidates += len(found)
    took = time.perf_counter() - started
    print(f'2. Inversion: {count} operation seeds each gave back their campaign seed '
          f'({candidates / count:.2f} candidates per seed, {took / count * 1e6:.0f} us each)')


def solve(planet, difficulty, required, scope, want, budget):
    """Campaign seeds for a filter, solved one draw-path system at a time."""
    rows = [r for r in range((difficulty - 1) * 3, difficulty * 3)
            if not (planet.active and planet.active['row'] == r)]
    shared = planet.shared_paths(difficulty, required)
    jobs = []
    if shared is not None:  # every ID has the same paths: the ID draw is free
        if scope == 'any':
            jobs = [(path['probability'], [(row, None, path)]) for path in shared for row in rows]
        else:
            for combo in itertools.product(shared, repeat=len(rows)):
                jobs.append((math.prod(p['probability'] for p in combo),
                             [(row, None, path) for row, path in zip(rows, combo)]))
    else:
        assert scope == 'any', 'per-ID paths are only combined for one row here'
        for (d, op_id), op in planet.ops.items():
            if d == difficulty:
                for path in planet.paths(op, required):
                    jobs += [(path['probability'] / planet.pool, [(row, op_id, path)]) for row in rows]
    jobs.sort(key=lambda j: -j[0])
    covered = sum(p for p, _ in jobs)
    print(f'   {len(jobs)} draw-path systems ({"IDs free" if shared is not None else "per ID"}); '
          f'they hold a fraction {covered:.3g} of all campaign seeds')
    if not jobs:
        return [], 0.0, covered
    started = time.perf_counter()
    first = None
    seeds, systems, dims = [], 0, 0
    per_system = max(1, want // 8)
    for _, picks in jobs:
        if len(seeds) >= want or time.perf_counter() - started > budget:
            break
        system = S.campaign_system(planet, picks)
        systems += 1
        dims = max(dims, len(system.rows))
        for solution in system.solve(limit=per_system):
            seed = (solution['x'] - planet.planet) % S.M32
            if ok(planet.board(seed, difficulty), difficulty, required, scope):  # forward check
                seeds.append(seed)
                if first is None:
                    first = time.perf_counter() - started
            if len(seeds) >= want:
                break
    took = time.perf_counter() - started
    print(f'   solved {len(seeds)} seeds from {systems} systems (up to {dims} dimensions) in {took:.2f} s, '
          f'first after {first if first is not None else float("nan"):.2f} s')
    return seeds, took, covered


def brute(planet, difficulty, required, scope, budget, start):
    started = time.perf_counter()
    seed, tried = start, 0
    while time.perf_counter() - started < budget:
        tried += 1
        if ok(planet.board(seed, difficulty), difficulty, required, scope):
            return seed, tried, time.perf_counter() - started
        seed = (seed + 1) % S.M32
    return None, tried, time.perf_counter() - started


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--capture', type=Path, default=artifacts() / 'level-capture-oracle.lua')
    parser.add_argument('--work', type=Path, default=artifacts() / 'seed-solver')
    parser.add_argument('--brute-seconds', type=float, default=120)
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)

    tables = args.work / 'tables.json'
    oracle('tables', ROOT / 'src', args.capture, tables)
    planet = S.Planet(json.loads(tables.read_text()))

    rng = random.Random(25480438)
    sample = [planet.t['capture_seed'], 0, 1, S.M32 - 1] + [rng.randrange(S.M32) for _ in range(300)]
    boards = lua_boards(args.capture, args.work, sample)
    check_port(planet, boards)
    check_inversion(planet, boards)

    filters = [
        ('ICBM and Survey in one operation', 10, [59, 81], 'any'),
        ('ICBM, Survey and Eradicate in one operation', 10, [59, 81, 65], 'any'),
        ('three objectives of one category (rules allow two)', 10, [59, 81, 63], 'any'),
        ('ICBM and Survey in every operation', 10, [59, 81], 'all'),
        ('ICBM, Survey and Eradicate in every operation', 10, [59, 81, 65], 'all'),
    ]
    solved = {}
    for name, difficulty, required, scope in filters:
        print(f'3. Filter at difficulty {difficulty}: {name} {required}')
        seeds, took, covered = solve(planet, difficulty, required, scope, want=16 if scope == 'any' else 4,
                                     budget=300)
        solved[name] = (difficulty, required, scope, seeds, took, covered)

    every = sorted({s for *_, seeds, _, _ in solved.values() for s in seeds})
    if every:
        lua = lua_boards(args.capture, args.work, every)
        for name, (difficulty, required, scope, seeds, _, _) in solved.items():
            good = sum(1 for s in seeds if ok(lua[s], difficulty, required, scope))
            print(f'   Lua predictor confirms {good}/{len(seeds)} solved seeds: {name}')
            assert good == len(seeds)

    for name, (difficulty, required, scope, seeds, took, covered) in solved.items():
        if not seeds:
            continue
        found, tried, spent = brute(planet, difficulty, required, scope, args.brute_seconds, rng.randrange(S.M32))
        rate = tried / spent
        head = f'4. Brute force, {name}: '
        tail = f'({spent:.2f} s at {rate:.0f} seeds/s; about {1 / covered:.3g} expected); ' \
               f'solver {took / len(seeds):.3f} s per seed'
        print(head + (f'no match in {tried} seeds ' if found is None else f'match after {tried} seeds ') + tail)
    (args.work / 'solved.json').write_text(json.dumps(
        {name: {'difficulty': d, 'kinds': k, 'scope': sc, 'seeds': s}
         for name, (d, k, sc, s, _, _) in solved.items()}, indent=1))


if __name__ == '__main__':
    main()
