"""Validate the level input decoder and stage replay on saved board outputs."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from fixture_memory import FixtureMemory
from validate_lua_identity import lua,input_from_fixture

ROOT=Path(__file__).resolve().parents[1]


def main(folder):
    memory=FixtureMemory(folder)
    board=int(memory.meta['board'],16)
    _,seed=input_from_fixture(folder)
    data=dict(game=memory.meta['game'],definitions=hex(board+0x22b1a8),
              ranges=[dict(address=hex(a),hex=b.hex()) for a,b in memory.pages.items()],cases=[])
    for path in [folder/'predicted-operations.bin',*sorted(folder.glob('seed-*/predicted-operations.bin'))]:
        if not path.exists():continue
        candidate=seed if path.parent==folder else int(path.parent.name.removeprefix('seed-'))
        data['cases'].append(dict(seed=candidate,operations=path.read_bytes().hex(),
                                 missions=(path.parent/'predicted-missions.bin').read_bytes().hex()))
    target=ROOT/'artifacts/level-capture-oracle.lua';target.write_text('return '+lua(data),encoding='ascii')
    subprocess.run([os.environ.get('HD2_LUAJIT',str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe')),
                    str(ROOT/'tests/check_level_capture.lua'),str(target),str(ROOT)],check=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('fixture',type=Path);main(p.parse_args().fixture)
