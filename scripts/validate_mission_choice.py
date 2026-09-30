"""Offline differential test of the Lua picker against captured native 11e6340.

Synthetic candidate lists and weights; no game-process access or publication.
This tests choice only, not the generation of legal candidates or mission levels.
"""
import argparse
import json
import os
from pathlib import Path
import random
import struct
import subprocess
import sys
from fixture_memory import FixtureMemory
from validate_lua_identity import lua
import offsets

ROOT=Path(__file__).resolve().parents[1]
O=offsets.load()


def pages(name):
    entry=O.data['research'][name]
    return entry['rva'],entry['rva']+entry['size']
sys.path.insert(0,str(ROOT.parent/'tools/seed-emulator-deps'))
from unicorn import Uc,UC_ARCH_X86,UC_MODE_64
from unicorn.x86_const import UC_X86_REG_RIP,UC_X86_REG_RSP,UC_X86_REG_RCX,UC_X86_REG_RDX,UC_X86_REG_R8,UC_X86_REG_R9


def main(folder):
    memory=FixtureMemory(folder)
    base=int(memory.meta['game'],16)
    engine=Uc(UC_ARCH_X86,UC_MODE_64)
    # Only the function's captured code pages are executable; all other captures
    # are read-only data, and test-owned scratch/stack is writable, non-executable.
    for address,data in memory.pages.items():
        start,end=pages('choice_pages')
        engine.mem_map(address,4096,5 if base+start<=address<base+end else 1)
        engine.mem_write(address,data)
    scratch=0x10000000000;stack=scratch+0x10000;stop=base+O.rva['mission_choice']-1
    engine.mem_map(scratch,0x20000,3)
    definitions=scratch;candidate_address=scratch+0x1000;counts_address=scratch+0x2000;output=scratch+0x3000
    rand=random.Random(6020340)
    cases=[]
    ids=[]
    for id in [0,3,7,22,40,55,59,65,81,82,103,108]:
        try: mission_hash=memory.u32(base+O.rva['mission_types']+id*O.field('mission_type','size'))
        except ValueError: continue
        if mission_hash:ids.append(id)
    assert len(ids)>=8,'Need at least eight captured mission types for scalar/vector coverage'
    for index in range(256):
        pool=rand.sample(ids,1+index%len(ids))
        weights={id:rand.choice([0.0,0.1,0.33333334,1.0,2.0,16777216.0,16777218.0]) for id in pool}
        counts={id:rand.randrange(0,5) for id in pool}
        if index%7==0:counts={id:0 for id in pool}
        mission_seed=rand.getrandbits(32);operation_seed=rand.getrandbits(32)
        if index<6:mission_seed=[0,1,0x7fffffff,0x80000000,0xfffffffe,0xffffffff][index]
        raw=bytearray(0x300)
        for i,id in enumerate(pool):
            mission_hash=memory.u32(base+O.rva['mission_types']+id*O.field('mission_type','size'))
            assert mission_hash!=0
            struct.pack_into('<If',raw,0x38+i*8,mission_hash,weights[id])
        engine.mem_write(definitions,bytes(raw))
        engine.mem_write(candidate_address,struct.pack('<'+'I'*len(pool),*pool))
        raw_counts=bytearray(162*4)
        for id,n in counts.items():struct.pack_into('<I',raw_counts,id*4,n)
        engine.mem_write(counts_address,bytes(raw_counts))
        args=[0,0,definitions,0,0,0,10,mission_seed,operation_seed,output,candidate_address,len(pool),0,counts_address]
        sp=stack+0xff08
        engine.mem_write(sp,struct.pack('<Q',stop))
        for i,value in enumerate(args[4:]):engine.mem_write(sp+0x28+i*8,struct.pack('<Q',value))
        for reg,value in zip([UC_X86_REG_RCX,UC_X86_REG_RDX,UC_X86_REG_R8,UC_X86_REG_R9],args[:4]):engine.reg_write(reg,value)
        engine.reg_write(UC_X86_REG_RSP,sp)
        engine.emu_start(base+O.rva['mission_choice'],stop,timeout=1_000_000,count=100_000)
        assert engine.reg_read(UC_X86_REG_RIP)==stop,'Native picker exceeded execution budget'
        selected=struct.unpack('<I',engine.mem_read(output+0x30,4))[0]
        after={id:struct.unpack('<I',engine.mem_read(counts_address+id*4,4))[0] for id in pool}
        cases.append(dict(pool=pool,weights=[weights[id] for id in pool],counts=[counts[id] for id in pool],
                          mission_seed=mission_seed,operation_seed=operation_seed,selected=selected,after=[after[id] for id in pool]))
    target=ROOT/'artifacts/mission-choice-oracle.lua'
    target.write_text('return '+lua(cases),encoding='ascii')
    subprocess.run([os.environ.get('HD2_LUAJIT',str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe')),
                    str(ROOT/'tests/test_mission_choice.lua'),str(ROOT/'src'),str(target)],check=True)
    print('Native leaf replay -> Lua weighted choice: 256 differential cases passed')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('fixture',type=Path)
    main(parser.parse_args().fixture)
