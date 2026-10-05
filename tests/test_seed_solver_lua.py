"""Checks the LuaJIT seed solver modules against the Python prototype.

    python -B tests/test_seed_solver_lua.py

Computes cases with scripts/seed_solver.py and scripts/seed_chain.py and runs
the LuaJIT tests on them:

- tests/test_seed_solver_math.lua: src/seed_solver_math.lua (128-bit
  Euclid, three-gap walk, inversion).
- tests/test_seed_solver_paths.lua, for each saved capture in artifacts/:
  src/seed_solver_inputs.lua and src/seed_solver_paths.lua (forward draws
  against the predictor's modules, draw paths against seed_solver.py).

Needs HD2_LUAJIT. The capture checks need the main checkout's artifacts/
and are skipped without them.
"""
import itertools
import os
import random
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import seed_solver as S  # noqa: E402
import seed_chain as C  # noqa: E402

LUAJIT = os.environ['HD2_LUAJIT']


def lua(value):
    """A Python value as a Lua literal: lists become arrays, str stays text."""
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if value is None:
        return 'nil'
    if isinstance(value, int):
        assert abs(value) < 2 ** 53, value
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return '"' + value + '"'
    if isinstance(value, dict):
        return '{' + ','.join(f'[{lua(k)}]={lua(v)}' for k, v in value.items()) + '}'
    return '{' + ','.join(lua(v) for v in value) + '}'


def run(test, *args):
    out = subprocess.run([LUAJIT, str(ROOT / 'tests' / test), *map(str, args)], capture_output=True, text=True)
    sys.stdout.write(out.stdout)
    if out.returncode:
        sys.stderr.write(out.stderr)
        raise SystemExit(f'{test} failed')


def math_cases(r):
    first = []
    for _ in range(3000):
        top = r.random() < 0.5
        m = S.M64 if top else r.randrange(2, S.M64)
        a = r.randrange(m)
        lo = r.choice([0, r.randrange(m)])
        hi = r.choice([lo, min(m - 1, lo + r.randrange(1 << r.randrange(1, 64))), r.randrange(lo, m)])
        x = S._first(a, m, lo, hi)
        first.append([str(a), str(0 if top else m), str(lo), str(hi), 'nil' if x is None else str(x)])
    output = []
    for _ in range(500):
        seed, position = r.randrange(S.M32), r.randint(1, 128)
        output.append([seed, position, S.output(seed, position)])
    walk = []
    for _ in range(400):
        position = r.randint(1, 128)
        count = r.choice([1, 2, 5, 1000, r.randrange(1, 1 << 20), r.randrange(1, S.M32), S.M32])
        lo = r.randrange(S.M32 - count + 1)
        hi, start = lo + count - 1, r.randrange(S.M32)
        want = [s for s, _ in itertools.islice(C.Walk(position, lo, hi)(start), 300)] if count < S.M32 \
            else list(range(start, min(S.M32, start + 300)))
        walk.append([position, lo, hi, start, want])
    invert = []
    for _ in range(3000):
        position = r.randint(1, 128)
        value = r.randrange(S.M32) if r.random() < 0.7 else S.output(r.randrange(S.M32), position)
        invert.append([position, value, list(S.states_with_output(position, value, value))])
    return dict(first=first, output=output, walk=walk, invert=invert)


def path_text(path):
    """A path as tests/test_seed_solver_paths.lua writes it."""
    parts = []
    for step in path['constraints']:
        kind, position, lo, hi = step[:4]
        text = f'{kind}:{position}:{"nil" if lo is None else lo}:{"nil" if hi is None else hi}'
        mission = step[4] if len(step) > 4 else None
        if mission:
            draws = ','.join(f'{p}={a}-{b}' for p, (a, b) in sorted(mission['draws'].items()))
            mods = ','.join(f'{m}:{a}-{b}' for m, a, b in mission['mods'])
            text += f'[{draws}|{mods}]'
        parts.append(text)
    return ';'.join(parts)


def capture_cases(work):
    """(capture, expected paths) for each saved capture present."""
    sys.path.insert(0, str(ROOT / 'scripts'))
    import json
    import prove_seed_solver as PR
    base = PR.artifacts()
    for capture in (base / 'planet-live/capture.lua', base / 'level-capture-oracle.lua'):
        if not capture.exists():
            print(f'test_seed_solver_lua: {capture} missing, its path checks skipped')
            continue
        tables = Path(work) / 'tables.json'
        PR.oracle('tables', ROOT / 'src', capture, tables)
        planet = S.Planet(json.loads(tables.read_text()))
        filters = []
        for f in PR.filters_for(planet):
            # The search matches one operation; an "every operation" filter
            # with mission rules takes tens of seconds per seed, so the chain
            # test solves only the cheaper one without rules.
            if f['scope'] == 'all' and f['rules']:
                continue
            paths = planet.shared_paths(f['difficulty'], f['required'], f['rules'])
            filters.append(dict(name=f['name'], difficulty=f['difficulty'], required=f['required'], rules=f['rules'],
                                scope=f['scope'], paths=[path_text(p) for p in paths]))
        expected = Path(work) / 'expected_paths.lua'
        expected.write_text('return ' + lua(dict(filters=filters)))
        yield capture, expected


def main():
    r = random.Random(25480438)
    C.JUMP = [S.jump(p) for p in range(129)]
    with tempfile.TemporaryDirectory() as work:
        cases = Path(work) / 'math_cases.lua'
        cases.write_text('return ' + lua(math_cases(r)))
        run('test_seed_solver_math.lua', ROOT / 'src', cases)
        for capture, expected in capture_cases(work):
            run('test_seed_solver_paths.lua', ROOT / 'src', capture, expected)
            run('test_seed_solver_chain.lua', ROOT / 'src', capture, expected)
    print('test_seed_solver_lua: passed')


if __name__ == '__main__':
    main()
