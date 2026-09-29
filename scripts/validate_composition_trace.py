"""Compare Lua input decoding to intermediate native values from saved replay."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from fixture_memory import FixtureMemory
from validate_lua_identity import lua

ROOT=Path(__file__).resolve().parents[1]


def main(folder):
    memory=FixtureMemory(folder)
    data=dict(game=memory.meta['game'],board=memory.meta['board'],planet=memory.meta['planet'],
              ranges=[dict(address=hex(a),hex=b.hex()) for a,b in memory.pages.items()],
              trace=json.loads((folder/'composition-trace/trace.json').read_text()))
    target=ROOT/'artifacts/composition-trace-oracle.lua'
    target.write_text('return '+lua(data),encoding='ascii')
    subprocess.run([os.environ.get('HD2_LUAJIT',str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe')),
                    str(ROOT/'tests/check_composition_trace.lua'),str(target),str(ROOT/'src')],check=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('fixture',type=Path);main(p.parse_args().fixture)
