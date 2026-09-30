"""Run Lua on a guarded live capture; write the next missing page when needed."""
import argparse
import os
from pathlib import Path
import subprocess
from fixture_memory import FixtureMemory
from validate_lua_identity import lua
import offsets

ROOT=Path(__file__).resolve().parents[1]
O=offsets.load()

def main(folder):
    memory=FixtureMemory(folder);meta=memory.meta;b=int(meta['board'],16)
    data=dict(game=meta['game'],definitions=meta['definitions'],planet=meta['planet'],
              ranges=[dict(address=hex(a),hex=d.hex()) for a,d in memory.pages.items()],
              cases=[dict(seed=memory.u32(b+O.field('board','seed')),operations=memory.read(b+O.field('board','operations'),110*92).hex(),
                          missions=memory.read(b+O.field('board','missions'),330*76).hex())])
    target=folder/'capture.lua';target.write_text('return '+lua(data),encoding='ascii')
    missing=folder/'missing.txt';missing.write_text('',encoding='ascii')
    result=subprocess.run([os.environ.get('HD2_LUAJIT',str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe')),
        str(ROOT/'tests/check_composition_capture.lua'),str(target),str(ROOT/'src'),str(missing),str(folder/'used.json')],capture_output=True,text=True)
    if missing.read_text():print('MISSING '+missing.read_text())
    else:print(result.stdout+result.stderr)
    return result.returncode

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('folder',type=Path)
    raise SystemExit(main(parser.parse_args().folder))
