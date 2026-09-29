"""Replay the city scope on live campaign memory, read through Memory Explorer.

Development tool. The game must be running with the Memory Explorer addon, the
galactic map open on a planet with a city or megafactory, and no other Memory
Explorer server connected. Only reads are made, through the addon's bridge.
Captured pages go to the ignored artifacts folder and are never packaged.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / 'MemoryExplorer/server'))
sys.path.insert(0, str(ROOT / 'scripts'))
import memory_mcp as mcp
import build_dialog


def main(difficulty='10'):
    bridge = mcp.Bridge(Path(os.environ['LOCALAPPDATA']) / 'CowboyBingus/Helldivers2/Logs')
    bridge.acquire()
    session = bridge.call('status')['session']
    modules = {m['name']: int(m['base'], 16) for m in bridge.call('modules')['modules']}
    game = modules['game.dll']

    def read(address, size):
        reply = mcp.call_tool(bridge, 'hd2_read', {'session': session, 'address': hex(address), 'size': size})
        return bytes.fromhex(reply['hex'])
    board = int.from_bytes(read(game + 0x347cee8, 8), 'little')
    folder = ROOT / 'artifacts/city-live'
    folder.mkdir(parents=True, exist_ok=True)
    pages = {}
    lua = os.environ.get('HD2_LUAJIT', str(ROOT.parent / 'tools/src/LuaJIT/src/luajit.exe'))
    with tempfile.TemporaryDirectory() as temporary:
        entry = Path(temporary) / 'dialog.lua'
        entry.write_bytes(build_dialog.probe.source(search=True, publish=True, dialog=True))
        missing = Path(temporary) / 'missing.txt'
        capture = folder / 'capture.lua'
        for _ in range(4000):
            lines = ["return {game='%d',board='%d',ranges={" % (game, board)]
            lines += ["{address='%d',hex='%s'}," % (address, data.hex()) for address, data in pages.items()]
            lines.append('}}')
            capture.write_text('\n'.join(lines), encoding='ascii')
            missing.write_text('', encoding='ascii')
            result = subprocess.run([lua, str(ROOT / 'tests/check_city_scope.lua'), str(capture), str(ROOT / 'src'),
                                     str(entry), str(missing), str(difficulty)], capture_output=True, text=True)
            if result.returncode == 3:
                page = int(missing.read_text(), 16)
                assert page not in pages, 'Repeated page request'
                pages[page] = read(page, 4096)
                continue
            print(result.stdout + result.stderr)
            print('session %s, %d pages captured' % (session, len(pages)))
            return result.returncode
    raise SystemExit('Capture did not converge')


if __name__ == '__main__':
    raise SystemExit(main(*sys.argv[1:]))
