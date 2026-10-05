"""Run worker_threads.lua inside the installed game's own lua51.dll (LuaJIT 2.1.0-alpha).

Research only (docs/NATIVE_SOLVER_RESEARCH.md). The DLL is loaded into this
process only; the game is never started or touched.

    python -B scripts/native_solver/worker_threads.py <capture.lua> [mode] [steps] [thread counts] [thread|pool]
"""
import ctypes as c
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]


def main():
    capture = Path(sys.argv[1]).resolve()
    mode = sys.argv[2] if len(sys.argv) > 2 else 'both'
    steps = sys.argv[3] if len(sys.argv) > 3 else '1000000'
    counts = sys.argv[4] if len(sys.argv) > 4 else '1,2,3,4,6,12'
    start = sys.argv[5] if len(sys.argv) > 5 else 'thread'
    dll_path = os.environ.get('HD2_LUA51_DLL') or str(Path(os.environ['HD2_GAME_ROOT']) / 'bin/lua51.dll')
    dll = c.CDLL(dll_path)
    dll.luaL_newstate.restype = c.c_void_p
    dll.luaL_openlibs.argtypes = [c.c_void_p]
    dll.luaL_loadbuffer.argtypes = [c.c_void_p, c.c_char_p, c.c_size_t, c.c_char_p]
    dll.lua_pcall.argtypes = [c.c_void_p, c.c_int, c.c_int, c.c_int]
    dll.lua_tolstring.argtypes = [c.c_void_p, c.c_int, c.c_void_p]
    dll.lua_tolstring.restype = c.c_char_p
    dll.lua_close.argtypes = [c.c_void_p]
    state = dll.luaL_newstate()
    dll.luaL_openlibs(state)
    script = HERE / 'worker_threads.lua'
    args = [script.as_posix(), REPO.as_posix(), capture.as_posix(), mode, steps, counts, start]
    chunk = ('arg = {' + ', '.join('[%d] = %r' % (i, a) for i, a in enumerate(args)) + '}\n').encode()
    chunk += script.read_bytes()
    status = dll.luaL_loadbuffer(state, chunk, len(chunk), b'@worker_threads.lua')
    if status == 0:
        status = dll.lua_pcall(state, 0, 0, 0)
    if status:
        message = dll.lua_tolstring(state, -1, None)
        raise RuntimeError((message or b'<no message>').decode(errors='replace'))
    dll.lua_close(state)


if __name__ == '__main__':
    main()
