"""Validate Lua calculations against captured/emulated binaries, entirely offline.

Game-derived fixtures are written only under the ignored artifacts directory.
This diagnostic validates operation identity, NOT mission composition or validity.
"""
import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
from fixture_memory import FixtureMemory
import offsets

ROOT = Path(__file__).resolve().parents[1]
O = offsets.load()


def lua(value):
    if isinstance(value, dict):
        return '{' + ','.join(f'[{json.dumps(k)}]={lua(v)}' for k, v in value.items()) + '}'
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    if value is None:
        return 'nil'
    return json.dumps(value)


def identities(data):
    return [dict(row=i, id=data[i*92+24], difficulty=data[i*92+32],
                 seed=struct.unpack_from('<I', data, i*92+12)[0])
            for i in range(110) if data[i*92+52]]


def input_from_fixture(folder):
    memory = FixtureMemory(folder)
    board, game = (int(memory.meta[k], 16) for k in ('board', 'game'))
    planet = memory.meta['planet']
    rng_scale = O.data['code']['rng_scale']['bytes']
    assert memory.read(game+O.rva['rng_scale'], len(rng_scale)//2) == bytes.fromhex(rng_scale)
    definition_id = memory.u32(board+O.field('board', 'campaign')+0x1c+planet*O.field('campaign', 'definition_stride'))
    definitions = None
    for offset in O.field('board', 'definitions'):
        try:
            if memory.u32(board+offset) == definition_id:
                definitions = board+offset
                break
        except ValueError:
            continue
    assert definitions is not None, 'Definitions not cached'
    active = memory.read(board+O.field('board', 'active_snapshot'), 92)
    result = dict(planet=planet, pool_count=memory.u32(definitions+O.field('definitions', 'pool_count')), max_difficulty=10)
    if active[52]:
        result['active'] = dict(row=int.from_bytes(active[:4], 'little'), id=active[24],
                                difficulty=active[32], planet=int.from_bytes(active[16:18], 'little'),
                                seed=int.from_bytes(active[12:16], 'little'))
    return result, memory.u32(board+O.field('board', 'published_seed'))


def main(folder):
    inputs, baseline_seed = input_from_fixture(folder)
    cases = []
    for path in [folder/'predicted-operations.bin', *sorted(folder.glob('seed-*/predicted-operations.bin'))]:
        if not path.exists():
            continue
        seed = baseline_seed if path.parent == folder else int(path.parent.name.removeprefix('seed-'))
        cases.append(dict(input=inputs, seed=seed, expected=identities(path.read_bytes())))
    assert cases, 'No oracle outputs'
    vectors = []
    for seed in (0, 1, 0x7fffffff, 0x80000000, 0xffffffff, 569798162):
        for planet in (0, 268, 511):
            state = (seed+planet) & 0xffffffff
            values = []
            for _ in range(100):
                state = (state*6364136223846793005+1442695040888963407) & 0xffffffffffffffff
                values.append(state >> 32)
            vectors.append(dict(seed=seed, planet=planet, values=values))
    target = ROOT/'artifacts/lua-identity-oracle.lua'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('return '+lua(dict(rng=vectors, cases=cases)), encoding='ascii')
    luajit = os.environ.get('HD2_LUAJIT', str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe'))
    subprocess.run([luajit, str(ROOT/'tests/test_operation_identity.lua'), str(ROOT/'src/generation_rng.lua'),
                    str(ROOT/'src/operation_identity.lua'), str(target)], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fixture', type=Path)
    main(parser.parse_args().fixture)
