"""Feasibility proof for solving campaign seeds from a mission filter.

    python -B scripts/prove_seed_solver.py [--capture <capture.lua>] [--work <dir>]

Replays a saved capture through the mod's own Lua predictor
(scripts/seed_solver_oracle.lua) as ground truth. The default is the
viewed-planet capture artifacts/planet-live/capture.lua (planet 173), which
holds the enemy-tag and side-objective inputs; the older campaign capture
artifacts/level-capture-oracle.lua (planet 268) supports missions only.

1. The Python port of the generator (seed_solver.Planet) reproduces the Lua
   prediction on random campaign seeds: operations, missions and, when the
   capture has them, each mission's enemy tags, side objectives and
   environment.
2. Every operation seed on those boards inverts to its campaign seed.
3. Filters are solved directly: each solved campaign seed is checked by the
   port and then by the Lua predictor. A filter the generator cannot satisfy
   is reported as having no draw path, without any search.
4. The same filters are searched by brute force for comparison.
"""
import argparse
import json
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
        if (base / 'artifacts/planet-live/capture.lua').exists():
            return base / 'artifacts'
    return ROOT / 'artifacts'


def oracle(*args):
    lua = os.environ['HD2_LUAJIT']
    subprocess.run([lua, str(ROOT / 'scripts/seed_solver_oracle.lua'), *map(str, args)], check=True, cwd=ROOT)


def mission_of(entry):
    """A Lua mission entry in the port's shape: (kind, seed, level, tags or
    None, [(objective id, role)], environment)."""
    kind, seed, level = entry[:3]
    if len(entry) < 4:
        return (kind, seed, level)
    tags = entry[3]
    tags = None if tags is False else sorted(tags) if isinstance(tags, list) else []
    objectives = [tuple(o) for o in entry[4]] if isinstance(entry[4], list) else []
    return (kind, seed, level, tags, objectives, entry[5])


def lua_boards(capture, work, seeds):
    listing = work / 'seeds.txt'
    listing.write_text(''.join(f'{s}\n' for s in seeds))
    out = work / 'predicted.json'
    oracle('predict', ROOT / 'src', capture, listing, out)
    boards = {}
    for b in json.loads(out.read_text()):
        for op in b['operations']:
            op['missions'] = [mission_of(m) for m in (op['missions'] or [])]
            op['modifiers'] = op['modifiers'] if isinstance(op['modifiers'], list) else []
        boards[b['seed']] = b['operations']
    return boards


def generated(planet, board):
    """The operations a reroll generates: the preserved operation in
    progress keeps its row whatever the seed, and filters are about the rest."""
    return [op for op in board if not (planet.active and op['row'] == planet.active['row'])]


def check_port(planet, boards):
    ops = missions = bad = 0
    for seed, board in boards.items():
        mine = {o['row']: o for o in planet.board(seed, details=planet.seeded)}
        for o in board:
            if planet.active and o['row'] == planet.active['row']:
                continue
            m = mine[o['row']]
            ops += 1
            missions += len(o['missions'])
            lua = (o['id'], o['seed'], o['template_index'], o['modifiers'], o['missions'])
            py = (m['id'], m['seed'], m['template_index'], m['modifiers'], [tuple(x) for x in m['missions']])
            bad += lua != py
    what = 'missions with enemy tags, side objectives and environments' if planet.seeded else 'missions'
    print(f'1. Port: {len(boards)} boards, {ops} operations, {missions} {what}; '
          f'{bad} differences from the Lua predictor')
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


def solve(planet, f, want, budget):
    """Campaign seeds for a filter, solved one draw-path system at a time."""
    difficulty, required, rules, scope = f['difficulty'], f['required'], f['rules'], f['scope']
    details = bool(rules)
    rows = [r for r in range((difficulty - 1) * 3, difficulty * 3)
            if not (planet.active and planet.active['row'] == r)]
    started = time.perf_counter()
    shared = planet.shared_paths(difficulty, required, rules)
    jobs = []
    per_system = max(1, want // 8)
    if shared is not None:  # every ID has the same paths: the ID draw is free
        if scope == 'any':
            jobs = [(path['probability'], [(row, None, path)]) for path in shared for row in rows]
            covered = sum(p for p, _ in jobs)
        else:
            # Joining every row in one lattice makes sparse systems of 35 or
            # more dimensions, which this pure-Python enumerator handles
            # poorly (docs/SEED_SOLVER_RESEARCH.md). Sample the first row's
            # systems instead and check the other rows forward.
            jobs = [(path['probability'], [(rows[0], None, path)]) for path in shared]
            covered = sum(p for p, _ in jobs) ** len(rows)
            per_system = 2000
    else:
        assert scope == 'any', 'per-ID paths are only combined for one row here'
        for (d, op_id), op in planet.ops.items():
            if d == difficulty:
                for path in planet.paths(op, required, rules):
                    jobs += [(path['probability'] / planet.pool, [(row, op_id, path)]) for row in rows]
        covered = sum(p for p, _ in jobs)
    jobs.sort(key=lambda j: -j[0])
    print(f'   {len(jobs)} draw-path systems ({"IDs free" if shared is not None else "per ID"}) in '
          f'{time.perf_counter() - started:.2f} s; about {covered:.3g} of all campaign seeds')
    if not jobs:
        return [], 0.0, covered
    first = None
    seeds, systems, dims = [], 0, 0
    # 'any' tries each system once; 'all' cycles through them in short
    # slices, since how fast a system samples varies a lot between systems.
    cycle = scope == 'all'
    slices = ((r, i, picks) for r in (range(10 ** 9) if cycle else [0]) for i, (_, picks) in enumerate(jobs))
    built = {}
    for r, i, picks in slices:
        if len(seeds) >= want or time.perf_counter() - started > budget:
            break
        if i not in built:
            built[i] = S.campaign_system(planet, picks)
            systems += 1
        system = built[i]
        dims = max(dims, len(system.rows))
        deadline = min(started + budget, time.perf_counter() + (5 if cycle else 10))
        rng = random.Random(r * 7919 + i)
        for solution in system.solve(limit=per_system, deadline=deadline, sample=True, rng=rng):
            seed = (solution['x'] - planet.planet) % S.M32
            if seed in seeds:
                continue
            board = planet.board(seed, difficulty, details=details)
            if planet.matches(board, difficulty, required, rules, scope):  # forward check
                seeds.append(seed)
                if first is None:
                    first = time.perf_counter() - started
            if len(seeds) >= want:
                break
    took = time.perf_counter() - started
    print(f'   solved {len(seeds)} seeds from {systems} systems (up to {dims} dimensions) in {took:.2f} s, '
          f'first after {first if first is not None else float("nan"):.2f} s')
    return seeds, took, covered


def brute(planet, f, budget, start):
    started = time.perf_counter()
    seed, tried = start, 0
    details = bool(f['rules'])
    while time.perf_counter() - started < budget:
        tried += 1
        board = planet.board(seed, f['difficulty'], details=details)
        if planet.matches(board, f['difficulty'], f['required'], f['rules'], f['scope']):
            return seed, tried, time.perf_counter() - started
        seed = (seed + 1) % S.M32
    return None, tried, time.perf_counter() - started


def filters_for(planet):
    """The filters each saved capture is tested with."""
    if planet.planet == 268:
        return [
            dict(name='ICBM and Survey in one operation', difficulty=10, required=[59, 81], rules={}, scope='any'),
            dict(name='ICBM, Survey and Eradicate in one operation', difficulty=10, required=[59, 81, 65], rules={},
                 scope='any'),
            dict(name='three objectives of one category (rules allow two)', difficulty=10, required=[59, 81, 63],
                 rules={}, scope='any'),
            dict(name='ICBM and Survey in every operation', difficulty=10, required=[59, 81], rules={}, scope='all'),
        ]
    assert planet.planet == 173 and planet.seeded, 'no filters defined for this capture'
    row = {name: key for key, name in planet.row_names.items()}
    tag = {name.split(' (')[0]: t for t, name in planet.tag_names.items()}
    upload, larva = row['Upload Escape Pod Data'], row['Retrieve Mutant Larva']
    spore, lidar = row['Spore Spewer'], row['Lidar Station']
    bile, hunter, armored = tag['Bile Bugs'], tag['Hunter Swarms'], tag['Armored Bugs']
    a = {'tags': {bile: 'accept'}, 'objectives': {upload: 'require'}}
    b = {'tags': {hunter: 'accept'}, 'objectives': {larva: 'require', spore: 'exclude'}}
    return [
        dict(name='59 with Bile Bugs', difficulty=10, required=[59], rules={59: {'tags': {bile: 'accept'}}},
             scope='any'),
        dict(name='59 with Bile Bugs, Upload Escape Pod Data and Lidar Station', difficulty=10, required=[59],
             rules={59: {'tags': {bile: 'accept'}, 'objectives': {upload: 'require', lidar: 'require'}}}, scope='any'),
        dict(name='59 (Bile Bugs, Upload) with 84 (Hunter Swarms, Larva, no Spore Spewer)', difficulty=10,
             required=[59, 84], rules={59: a, 84: b}, scope='any'),
        dict(name='59 (Bile, Upload), 84 (Hunter, Larva, no Spore) and 65 (Armored Bugs)', difficulty=10,
             required=[59, 84, 65], rules={59: a, 84: b, 65: {'tags': {armored: 'accept'}}}, scope='any'),
        dict(name='59 (Bile, Upload) with 84 (Hunter, Larva, no Spore) in every operation', difficulty=10,
             required=[59, 84], rules={59: a, 84: b}, scope='all'),
        dict(name='65 with Spore Spewer (65 draws no side objective here)', difficulty=10, required=[65],
             rules={65: {'objectives': {spore: 'require'}}}, scope='any'),
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--capture', type=Path, default=artifacts() / 'planet-live/capture.lua')
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

    filters = filters_for(planet)
    for f in filters:
        names = ', '.join(f'{k} {planet.kind_names.get(k, "")}'.strip() for k in f['required'])
        print(f'3. Filter at difficulty {f["difficulty"]}: {f["name"]} [{names}]')
        f['seeds'], f['took'], f['covered'] = solve(planet, f, want=16 if f['scope'] == 'any' else 4, budget=300)

    every = sorted({s for f in filters for s in f['seeds']})
    if every:
        lua = lua_boards(args.capture, args.work, every)
        failed = []
        for f in filters:
            bad = [s for s in f['seeds'] if not planet.matches(generated(planet, lua[s]), f['difficulty'],
                                                               f['required'], f['rules'], f['scope'])]
            print(f'   Lua predictor confirms {len(f["seeds"]) - len(bad)}/{len(f["seeds"])} solved seeds: {f["name"]}')
            failed += [(f['name'], s) for s in bad]
        assert not failed, f'Lua predictor rejects {failed}'

    for f in filters:
        if not f['seeds']:
            continue
        found, tried, spent = brute(planet, f, args.brute_seconds, rng.randrange(S.M32))
        rate = tried / spent
        head = f'4. Brute force, {f["name"]}: '
        tail = (f'({spent:.2f} s at {rate:.0f} seeds/s; about {1 / f["covered"]:.3g} expected); '
                f'solver {f["took"] / len(f["seeds"]):.3f} s per seed')
        print(head + (f'no match in {tried} seeds ' if found is None else f'match after {tried} seeds ') + tail)
    (args.work / 'solved.json').write_text(json.dumps(
        [{k: v for k, v in f.items() if k != 'rules'} | {'rules': {str(k): v for k, v in f['rules'].items()}}
         for f in filters], indent=1, default=str))


if __name__ == '__main__':
    main()
