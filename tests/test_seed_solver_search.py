"""The seed solver inside the release entry's search, on captured memory.

Builds the release entry and runs tests/check_seed_solver_search.lua on the
viewed-planet captures (artifacts/planet-live/capture.lua, written by
scripts/check_live_planet.py, and artifacts/city-live/capture.lua, a planet
with a city): requests from the displayed board, the city's included, must
match through the solver, and one it cannot seed must fall back to scanning.

Needs HD2_LUAJIT and, for the build, ../BingusSharedLoader or
BINGUS_LOADER_ROOT. The captures exist only in the main checkout; a missing
one is skipped.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build  # noqa: E402
import prove_seed_solver as PR  # noqa: E402


def main():
    with tempfile.TemporaryDirectory() as folder:
        entry = Path(folder) / 'entry.lua'
        entry.write_bytes(build.source())
        for name in ('planet-live', 'city-live'):
            capture = PR.artifacts() / name / 'capture.lua'
            if not capture.exists():
                print(f'test_seed_solver_search: {capture} missing, skipped')
                continue
            subprocess.run([os.environ['HD2_LUAJIT'], str(ROOT / 'tests/check_seed_solver_search.lua'), str(capture),
                            str(ROOT / 'src'), str(entry)], check=True)
    print('test_seed_solver_search: passed')


if __name__ == '__main__':
    main()
