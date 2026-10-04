"""Measure the chained 1-D solver (seed_chain.py) for a LuaJIT port.

    python -B scripts/measure_seed_chain.py [--capture <capture.lua>] [--work <dir>]

For each filter of prove_seed_solver.filters_for():

1. Solve seeds with seed_chain.Chain and count its work: root solutions
   walked, draws checked forward, inversions, and boards predicted.
2. Confirm every seed with the mod's Lua predictor (seed_solver_oracle.lua).
3. Count brute-force matches over consecutive seeds, as the in-game search
   tries them, for the seeds a match costs.

The units are timed in LuaJIT by seed_chain_bench.lua, on parameters and
answers exported from the Python port. The in-game estimate charges the
units at those timings, scaled by the share of a frame the search works
(WORK_SHARE), and each predicted board at the in-game search rate
(GAME_RATE), both from the v0.16 logs (docs/FAST_SEARCH_TEST.md).
"""
import argparse
import itertools
import json
import os
import random
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import seed_solver as S  # noqa: E402
import seed_chain as C  # noqa: E402
import prove_seed_solver as PR  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
GAME_RATE = 1214  # boards per second of wall time, v0.16.0 log
WORK_SHARE = 389 / 1730  # search work per second of wall time, v0.16.1 log


def u64(x):
    return f'{x % S.M64}ULL'


def i64(x):
    return f'{x}LL' if x >= 0 else f'(-{-x}LL)'


def bench(work):
    """Unit timings in nanoseconds from seed_chain_bench.lua."""
    rng = random.Random(9)
    lo, hi = 1_000_000_000, 1_000_000_000 + int(0.225 * S.M32)
    lo6, hi6 = 2_000_000_000, 2_000_000_000 + int(0.167 * S.M32)
    w = C.Walk(1, lo, hi)
    (first, second), (q12, d12) = w.steps
    steps = 200000
    walked = list(itertools.islice(w(rng.randrange(S.M32), S.M32), steps + 1))
    passing = sum(1 for s, _ in walked[:steps] if lo6 <= C.out_at(s, 6) <= hi6)
    inv = C.Inverter(4)
    values = [rng.randrange(S.M32) for _ in range(1000)]
    a6, c6 = C.JUMP[6]
    lines = [
        'return {',
        f' steps={steps}, width={u64(w.width)}, s0={walked[0][0]}, off0={u64(walked[0][1])},',
        f' q1={first[0]}, d1={u64(first[1])}, sign1={first[2]}, q2={second[0]}, d2={u64(second[1])}, sign2={second[2]},',
        f' q12={q12}, d12={u64(d12)}, last={walked[steps][0]}, passing={passing},',
        f' a6={u64(a6)}, c6={u64(c6)}, lo6={lo6}, hi6={hi6},',
        f' a={u64(inv.a)}, c={u64(inv.c)}, us={i64(inv.u[0])}, vs={i64(inv.v[0])},',
        f' p={inv.inverse[0]!r}, q={inv.inverse[1]!r}, r={inv.inverse[2]!r}, z={inv.inverse[3]!r},',
        f' ri={inv.reach[0]!r}, rj={inv.reach[1]!r},',
        ' values={' + ','.join(map(str, values)) + '},',
        ' answers={' + ','.join('{' + ','.join(map(str, inv(v))) + '}' for v in values) + '},',
        '}',
    ]
    params = work / 'chain_bench_params.lua'
    params.write_text('\n'.join(lines))
    text = subprocess.run([os.environ['HD2_LUAJIT'], str(ROOT / 'scripts/seed_chain_bench.lua'), str(params)],
                          check=True, capture_output=True, text=True).stdout
    print('   LuaJIT units: ' + text.strip())
    return {k: float(v) for k, v in re.findall(r'(\w+_ns)=([\d.]+)', text)}


def brute(planet, f, budget, start, want):
    """(seeds tried, matches) over consecutive seeds."""
    started, seed, tried, matches = time.perf_counter(), start, 0, 0
    details = bool(f['rules'])
    while time.perf_counter() - started < budget and matches < want:
        tried += 1
        board = planet.board(seed, f['difficulty'], details=details)
        matches += planet.matches(board, f['difficulty'], f['required'], f['rules'], f['scope'])
        seed = (seed + 1) % S.M32
    return tried, matches


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--capture', type=Path, default=PR.artifacts() / 'planet-live/capture.lua')
    parser.add_argument('--work', type=Path, default=PR.artifacts() / 'seed-chain')
    parser.add_argument('--budget', type=float, default=120, help='chain seconds per filter')
    parser.add_argument('--brute-seconds', type=float, default=120)
    parser.add_argument('--only', help='run only filters whose name contains this')
    parser.add_argument('--every', action='store_true',
                        help='also run the "every operation" filters; the search matches one operation')
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)

    tables = args.work / 'tables.json'
    PR.oracle('tables', ROOT / 'src', args.capture, tables)
    planet = S.Planet(json.loads(tables.read_text()))
    ns = bench(args.work)

    filters = [f for f in PR.filters_for(planet) if (not args.only or args.only in f['name'])
               and (args.every or f['scope'] == 'any')]
    rng = random.Random(25480438)
    for f in filters:
        print(f'Filter at difficulty {f["difficulty"]}: {f["name"]}', flush=True)
        chain = C.Chain(planet, random.Random(rng.randrange(1 << 30)))
        C.DRAWS[0] = 0
        started = time.perf_counter()
        f['seeds'] = chain.solve(f['difficulty'], f['required'], f['rules'], f['scope'],
                                 want=8 if f['scope'] == 'any' else 2,
                                 deadline=started + args.budget, clock=time.perf_counter)
        f['python'] = time.perf_counter() - started
        f['counts'] = dict(chain.counts, draws=C.DRAWS[0])
        print(f'   chain: {len(f["seeds"])} seeds in {f["python"]:.1f} s of Python; {f["counts"]}', flush=True)

    every = sorted({s for f in filters for s in f['seeds']})
    if every:
        lua = PR.lua_boards(args.capture, args.work, every)
        for f in filters:
            bad = [s for s in f['seeds'] if not planet.matches(PR.generated(planet, lua[s]), f['difficulty'],
                                                               f['required'], f['rules'], f['scope'])]
            print(f'   Lua predictor confirms {len(f["seeds"]) - len(bad)}/{len(f["seeds"])}: {f["name"]}')
            assert not bad, f'Lua predictor rejects {bad}'

    print('In-game estimates per seed (chain: units at LuaJIT timings / work share + boards at the game rate; '
          'brute force: seeds per match at the game rate)')
    for f in filters:
        c, hits = f['counts'], max(1, len(f['seeds']))
        if not f['seeds']:
            print(f'   {f["name"]}: no seed (no draw path or none within the budget)')
            continue
        work = (c['roots'] * ns['walk_ns'] + c['draws'] * ns['draw_ns'] + c['inversions'] * ns['invert_ns']) * 1e-9
        chain_s = (work / WORK_SHARE + c['boards'] / GAME_RATE) / hits
        tried, matches = brute(planet, f, args.brute_seconds, rng.randrange(S.M32), want=20)
        per_match = tried / matches if matches else None
        brute_s = per_match / GAME_RATE if per_match else None
        per = {k: c[k] / hits for k in ('roots', 'draws', 'inversions', 'boards')}
        shown = ', '.join(f'{k} {v:,.0f}' for k, v in per.items())
        b = (f'brute force {per_match:,.0f} seeds per match ({matches} in {tried:,}), {brute_s:.2f} s'
             if per_match else f'brute force no match in {tried:,} seeds (over {tried / GAME_RATE:.0f} s)')
        print(f'   {f["name"]}: per seed {shown}; chain {chain_s:.3f} s; {b}', flush=True)
        f['estimate'] = dict(chain_s=chain_s, brute_s=brute_s, per_match=per_match, brute_tried=tried)
    (args.work / 'measured.json').write_text(json.dumps(
        [{k: v for k, v in f.items() if k != 'rules'} for f in filters], indent=1, default=str))


if __name__ == '__main__':
    main()
