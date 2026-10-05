"""Run a Lua test inside the installed game's own lua51.dll (LuaJIT 2.1.0-alpha).

The DLL is loaded into this process only; the game is never started or
touched. HD2_LUA51_DLL, or HD2_GAME_ROOT/bin/lua51.dll, names it.
"""
import ctypes as c
import os
from pathlib import Path

_dll = None


def path():
    configured = os.environ.get('HD2_LUA51_DLL')
    if configured:
        return Path(configured)
    root = os.environ.get('HD2_GAME_ROOT')
    return Path(root) / 'bin' / 'lua51.dll' if root else None


def available():
    p = path()
    return bool(p and p.is_file())


def run(script, *args):
    """Runs script with arg[0..n] in a fresh state; raises on a Lua error."""
    global _dll
    if _dll is None:
        _dll = c.CDLL(str(path()))
        _dll.luaL_newstate.restype = c.c_void_p
        _dll.luaL_openlibs.argtypes = [c.c_void_p]
        _dll.luaL_loadbuffer.argtypes = [c.c_void_p, c.c_char_p, c.c_size_t, c.c_char_p]
        _dll.lua_pcall.argtypes = [c.c_void_p, c.c_int, c.c_int, c.c_int]
        _dll.lua_tolstring.argtypes = [c.c_void_p, c.c_int, c.c_void_p]
        _dll.lua_tolstring.restype = c.c_char_p
        _dll.lua_close.argtypes = [c.c_void_p]
    script = Path(script)
    values = [script.as_posix()] + [str(a) for a in args]
    chunk = ('arg = {' + ', '.join('[%d] = %r' % (i, a) for i, a in enumerate(values)) + '}\n').encode()
    chunk += script.read_bytes()
    state = _dll.luaL_newstate()
    _dll.luaL_openlibs(state)
    try:
        status = _dll.luaL_loadbuffer(state, chunk, len(chunk), ('@' + script.name).encode())
        if status == 0:
            status = _dll.lua_pcall(state, 0, 0, 0)
        if status:
            message = _dll.lua_tolstring(state, -1, None) or b'<no message>'
            raise AssertionError('game lua51.dll: ' + message.decode(errors='replace'))
    finally:
        _dll.lua_close(state)
