"""Package the Worker Thread Probe research addon (docs/WORKER_PROBE_TEST.md).

A separate addon with its own module, GUID and log, never part of the
Mission Reroller release. The entry is worker_probe.lua with the source of
src/seed_solver_math.lua put before it as SEED_SOLVER_MATH, which its
worker VMs load. Needs ../BingusSharedLoader or BINGUS_LOADER_ROOT.

    python -B scripts/native_solver/build_worker_probe.py [output.zip]
"""
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LOADER = Path(os.environ.get('BINGUS_LOADER_ROOT', ROOT.parent / 'BingusSharedLoader'))
sys.path.insert(0, str(LOADER / 'scripts'))
from build_addon import build_addon  # noqa: E402

MODULE = 'mods/ipodalexei/worker_thread_probe'
NAME = 'Worker Thread Probe'
VERSION = '0.2.0'
# Generated once for this addon. Keep it for every future build.
GUID = '34c1fcb4-48e3-47b1-bfc2-8f92a685f4af'


def long_string(text):
    level = 0
    while (']' + '=' * level + ']') in text:
        level += 1
    return '[' + '=' * level + '[\n' + text + ']' + '=' * level + ']'


def source():
    math_source = (ROOT / 'src' / 'seed_solver_math.lua').read_text(encoding='utf-8')
    entry = (HERE / 'worker_probe.lua').read_text(encoding='utf-8')
    return ('-- HD2-Addon: ' + MODULE + '\n'
            + 'local SEED_SOLVER_MATH=' + long_string(math_source) + '\n'
            + entry).encode('utf-8')


def release_path():
    return ROOT / 'releases' / f'{NAME.replace(" ", "-")}-v{VERSION}.zip'


def main(output=None):
    output = Path(output) if output else release_path()
    output.parent.mkdir(parents=True, exist_ok=True)
    build_addon(MODULE, source(), GUID, output, f'{NAME} - v{VERSION} (research tool, remove after one run)')
    print(output)
    return output


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)
