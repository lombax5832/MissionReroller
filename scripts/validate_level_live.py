"""Replay an ignored read-only MCP level capture through Lua and its capture cache."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from validate_lua_identity import lua

ROOT = Path(__file__).resolve().parents[1]


def main(path):
    captured = json.loads(path.read_text())
    def address(value):
        return int(value, 16) if isinstance(value, str) else value
    board = address(captured['board'])
    ranges = [{"address": hex(address(r['address'])), "hex": r['result']['hex']}
              for r in captured['ranges']]
    def read(start, count):
        for r in ranges:
            offset = start-int(r['address'], 16)
            data = bytes.fromhex(r['hex'])
            if offset >= 0 and offset+count <= len(data):
                return data[offset:offset+count].hex()
        raise ValueError(f'Missing captured bytes at {start:#x}')
    guard = next(g for g in captured['guards'] if address(g['address']) == board+0x78e84)
    seed = int.from_bytes(bytes.fromhex(guard['expected_hex'])[:4], 'little')
    data = dict(game=hex(address(captured['game'])),
                definitions=hex(address(captured['definitions'])), ranges=ranges,
                cases=[dict(seed=seed, operations=read(board+0xf7280, 110*92),
                            missions=read(board+0xf9a10, 330*76))])
    target = path.with_suffix('.lua')
    target.write_text('return '+lua(data), encoding='ascii')
    subprocess.run([os.environ.get('HD2_LUAJIT', str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe')),
                    str(ROOT/'tests/check_level_capture.lua'), str(target), str(ROOT)], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    main(parser.parse_args().capture)
