"""Compare the Lua side-objective prediction with the last previewed mission, read through Memory Explorer.

Development tool. The game must be running with the Memory Explorer addon,
the galactic map open with a mission hovered (its preview descriptor holds
the game's objective list), and no other Memory Explorer client. Only reads
are made. Captured pages go to the ignored artifacts folder and are never
packaged. Runs tests/check_side_objective_preview.lua on them.
"""
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
MEMORY_EXPLORER = next((p/'MemoryExplorer' for p in ROOT.parents if (p/'MemoryExplorer/server').is_dir()), ROOT.parent/'MemoryExplorer')
sys.path.insert(0, str(Path(os.environ.get('MEMORY_EXPLORER_ROOT', MEMORY_EXPLORER)) / 'server'))
sys.path.insert(0, str(ROOT / 'scripts'))
import memory_mcp as mcp
import offsets

O = offsets.load()


def main():
    bridge = mcp.Bridge(Path(os.environ['LOCALAPPDATA']) / 'CowboyBingus/Helldivers2/Logs')
    bridge.acquire()
    session = bridge.call('status')['session']
    game = {m['name']: int(m['base'], 16) for m in bridge.call('modules')['modules']}['game.dll']

    def read(address, size):
        reply = mcp.call_tool(bridge, 'hd2_read', {'session': session, 'address': hex(address), 'size': size})
        return bytes.fromhex(reply['hex'])
    board = int.from_bytes(read(game + O.rva['board'], 8), 'little')
    folder = ROOT / 'artifacts/side-objective-preview'
    folder.mkdir(parents=True, exist_ok=True)
    pages = {}
    lua = os.environ.get('HD2_LUAJIT', str(ROOT.parent / 'tools/src/LuaJIT/src/luajit.exe'))
    capture, missing = folder / 'capture.lua', folder / 'missing.txt'
    for _ in range(4000):
        lines = ["return {game='%d',board='%d',ranges={" % (game, board)]
        lines += ["{address='%d',hex='%s'}," % (address, data.hex()) for address, data in pages.items()]
        lines.append('}}')
        capture.write_text('\n'.join(lines), encoding='ascii')
        missing.write_text('', encoding='ascii')
        result = subprocess.run([lua, str(ROOT / 'tests/check_side_objective_preview.lua'), str(capture), str(ROOT / 'src'),
                                 str(missing)], capture_output=True, text=True)
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
    raise SystemExit(main())
