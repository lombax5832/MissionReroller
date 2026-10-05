"""The release entry's hot loops under the game's own LuaJIT 2.1.0-alpha JIT.

Runs tests/check_game_jit.lua inside the installed game's lua51.dll
(tests/game_lua.py; the game is never started) on the viewed-planet captures,
artifacts/planet-live and artifacts/city-live. The pinned LuaJIT compiles
differently: a loop that passes there failed in game with "attempt to
concatenate field 'effect_id' (a nil value)".

Needs HD2_GAME_ROOT (or HD2_LUA51_DLL) and, for the build, ../BingusSharedLoader
or BINGUS_LOADER_ROOT. The captures exist only in the main checkout; a missing
DLL or capture is skipped.
"""
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT / 'tests'))
import build  # noqa: E402
import game_lua  # noqa: E402
import prove_seed_solver as PR  # noqa: E402


def main():
    if not game_lua.available():
        print('test_game_jit: no game lua51.dll, skipped')
        return
    with tempfile.TemporaryDirectory() as folder:
        entry = Path(folder) / 'entry.lua'
        entry.write_bytes(build.source())
        for name in ('planet-live', 'city-live'):
            capture = PR.artifacts() / name / 'capture.lua'
            if not capture.exists():
                print(f'test_game_jit: {capture} missing, skipped')
                continue
            game_lua.run(ROOT / 'tests/check_game_jit.lua', capture, ROOT / 'src', entry)
            sys.stdout.flush()
    print('test_game_jit: passed')


if __name__ == '__main__':
    main()
