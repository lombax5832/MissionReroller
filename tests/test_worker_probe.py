"""Check the Worker Thread Probe research addon (docs/WORKER_PROBE_TEST.md).

Builds the ZIP, checks its declaration, forbidden APIs and layout, then runs
tests/test_worker_probe.lua in the workspace LuaJIT and inside the installed
game's own lua51.dll (loaded into this process only; the game is never
started). Either run is skipped when its LuaJIT is missing.
"""
import ctypes as c
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts' / 'native_solver'))
import build_worker_probe as build  # noqa: E402

TEST = ROOT / 'tests' / 'test_worker_probe.lua'
FORBIDDEN = (b'VirtualAlloc', b'VirtualProtect', b'OpenProcess', b'CreateRemoteThread', b'CreateThread',
             b'WriteProcessMemory', b'LoadLibrary', b'io.open', b'os.execute', b'io.popen')


def check_package(directory):
    source = build.source()
    assert source.startswith(('-- HD2-Addon: ' + build.MODULE + '\n').encode())
    for forbidden in FORBIDDEN:
        assert forbidden not in source, forbidden
    assert b'local SEED_SOLVER_MATH=' in source
    output = build.main(Path(directory) / 'probe.zip')
    with zipfile.ZipFile(output) as z:
        names = z.namelist()
        assert 'manifest.json' in names, names
        manifest = z.read('manifest.json').decode()
        assert build.GUID in manifest, manifest
    entry = Path(directory) / 'worker_probe_entry.lua'
    entry.write_bytes(source)
    return entry


def luajit_runs(entry, directory):
    luajit = os.environ.get('HD2_LUAJIT')
    if not luajit or not Path(luajit).is_file():
        print('SKIP: workspace LuaJIT (HD2_LUAJIT) not found')
        return
    for mode in ('run', 'old_loader'):
        out = Path(directory) / ('luajit-' + mode)
        out.mkdir()
        subprocess.run([luajit, str(TEST), str(entry), str(out), mode], check=True)


def game_runs(entry, directory):
    path = os.environ.get('HD2_LUA51_DLL') or (os.environ.get('HD2_GAME_ROOT') and
                                                str(Path(os.environ['HD2_GAME_ROOT']) / 'bin/lua51.dll'))
    if not path or not Path(path).is_file():
        print('SKIP: game lua51.dll not found')
        return
    dll = c.CDLL(path)
    dll.luaL_newstate.restype = c.c_void_p
    dll.luaL_openlibs.argtypes = [c.c_void_p]
    dll.luaL_loadbuffer.argtypes = [c.c_void_p, c.c_char_p, c.c_size_t, c.c_char_p]
    dll.lua_pcall.argtypes = [c.c_void_p, c.c_int, c.c_int, c.c_int]
    dll.lua_tolstring.argtypes = [c.c_void_p, c.c_int, c.c_void_p]
    dll.lua_tolstring.restype = c.c_char_p
    dll.lua_close.argtypes = [c.c_void_p]
    for mode in ('run', 'old_loader'):
        out = Path(directory) / ('game-' + mode)
        out.mkdir()
        args = [TEST.as_posix(), entry.as_posix(), out.as_posix(), mode]
        chunk = ('arg = {' + ', '.join('[%d] = %r' % (i, a) for i, a in enumerate(args)) + '}\n').encode()
        chunk += TEST.read_bytes()
        state = dll.luaL_newstate()
        dll.luaL_openlibs(state)
        status = dll.luaL_loadbuffer(state, chunk, len(chunk), b'@test_worker_probe.lua')
        if status == 0:
            status = dll.lua_pcall(state, 0, 0, 0)
        if status:
            message = dll.lua_tolstring(state, -1, None) or b'<no message>'
            raise AssertionError('game lua51.dll (' + mode + '): ' + message.decode(errors='replace'))
        dll.lua_close(state)
        sys.stdout.flush()


def main():
    with tempfile.TemporaryDirectory() as directory:
        entry = check_package(directory)
        luajit_runs(entry, directory)
        game_runs(entry, directory)
    print('test_worker_probe.py: passed')


if __name__ == '__main__':
    main()
