"""Offline validation of the actual Lua input collector against two equal captures."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from validate_lua_identity import lua

ROOT=Path(__file__).resolve().parents[1]


def main(path):
    capture=json.loads(path.read_text())
    a,b=capture['before'],capture['after']
    assert a['session']==b['session'] and a['complete'] and b['complete']
    assert a['consistent'] and b['consistent']
    assert a['ranges']==b['ranges'], 'Inputs changed between captures'
    data=dict(board=capture['board'],planet=capture['planet'],
              ranges=[dict(address=r['address'],hex=r['result']['hex']) for r in a['ranges']])
    output=ROOT/'artifacts/special-inputs-live.lua'
    output.write_text('return '+lua(data),encoding='ascii')
    subprocess.run([os.environ.get('HD2_LUAJIT',str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe')),
                    str(ROOT/'tests/check_special_capture.lua'),str(output),str(ROOT)],check=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture',type=Path)
    main(parser.parse_args().capture)
