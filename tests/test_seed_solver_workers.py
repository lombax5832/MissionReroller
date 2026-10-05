"""Check the seed solver's worker VMs (src/seed_solver_workers.lua).

Runs tests/test_seed_solver_workers.lua in the workspace LuaJIT and inside
the installed game's own lua51.dll (tests/game_lua.py), each skipped when
missing. With the main checkout's artifacts/planet-live/capture.lua the
real request is checked too.
"""
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import game_lua  # noqa: E402

TEST = ROOT / 'tests' / 'test_seed_solver_workers.lua'


def capture():
    # A worktree's parent checkout keeps artifacts/.
    for base in (ROOT, ROOT.parents[2] if len(ROOT.parents) > 2 else ROOT):
        path = base / 'artifacts' / 'planet-live' / 'capture.lua'
        if path.is_file():
            return path
    print('SKIP: real-request check (no artifacts/planet-live/capture.lua)')
    return None


def main():
    args = [ROOT / 'src']
    cap = capture()
    if cap:
        args.append(cap)
    luajit = os.environ.get('HD2_LUAJIT')
    if luajit and Path(luajit).is_file():
        subprocess.run([luajit, str(TEST), *map(str, args)], check=True)
    else:
        print('SKIP: workspace LuaJIT (HD2_LUAJIT) not found')
    if game_lua.available():
        game_lua.run(TEST, *args)
    else:
        print('SKIP: game lua51.dll not found')
    print('test_seed_solver_workers.py: passed')


if __name__ == '__main__':
    main()
