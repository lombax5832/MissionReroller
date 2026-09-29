"""Differential test of level choice against captured native 11e6020, offline."""
import argparse
import os
from pathlib import Path
import random
import struct
import subprocess
import sys
from fixture_memory import FixtureMemory
from validate_lua_identity import lua

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'tools/seed-emulator-deps'))
from unicorn import Uc,UC_ARCH_X86,UC_MODE_64
from unicorn.x86_const import UC_X86_REG_RIP,UC_X86_REG_RSP,UC_X86_REG_RCX,UC_X86_REG_RDX,UC_X86_REG_R8,UC_X86_REG_R9,UC_X86_REG_RAX


def main(folder):
    memory=FixtureMemory(folder);base=int(memory.meta['game'],16)
    engine=Uc(UC_ARCH_X86,UC_MODE_64)
    for address,data in memory.pages.items():
        executable=base+0x11e6000<=address<base+0x11e7000 or base+0x2088000<=address<base+0x2089000
        engine.mem_map(address,4096,5 if executable else 1);engine.mem_write(address,data)
    scratch=0x10000000000;engine.mem_map(scratch,0x200000,3)
    definitions=scratch;missions=scratch+0xc0000;operation=scratch+0xc8000;state_address=scratch+0xd0000
    sp=scratch+0x1fff08;stop=base+0x11e6020-1
    def word(a,n):engine.mem_write(a,struct.pack('<I',n))
    rand=random.Random(6020);cases=[]
    for case_index in range(320):
        special=case_index%2==1;category=8 if special else 0
        levels=list(range(8,9+case_index%8))
        slot=case_index%5
        used=rand.sample(levels,rand.randrange(min(len(levels),3)+1))
        state=rand.getrandbits(64)
        raw_operation=bytearray(92)
        raw_operation[24]=2;struct.pack_into('<I',raw_operation,28,category)
        raw_operation[88]=len(used)
        for i,level in enumerate(used):raw_operation[85+i]=i;word(missions+i*76+44,level)
        engine.mem_write(operation,bytes(raw_operation))
        word(definitions+0xa1834,4);word(definitions+0xa183c,35)
        word(definitions+0xa1818,380);word(definitions+0xa1820,400)
        word(definitions+0xa100c+((380 if special else 400)+2)*4,8)
        word(definitions+0x11004,512)
        word(definitions+8*0x88+0x78,len(levels)-1)
        for i,level in enumerate(levels[1:]):
            word(definitions+8*0x88+0x18+i*4,i)
            word(definitions+0x11008+i*0x30,level if i%2 else 8)
            word(definitions+0x1100c+i*0x30,8 if i%2 else level)
            word(definitions+level*0x88+0x14,4 if special else 6)
        engine.mem_write(state_address,struct.pack('<Q',state))
        engine.mem_write(sp,struct.pack('<Q',stop))
        engine.mem_write(sp+0x28,struct.pack('<Q',slot));engine.mem_write(sp+0x30,struct.pack('<Q',definitions))
        for reg,value in zip([UC_X86_REG_RCX,UC_X86_REG_RDX,UC_X86_REG_R8,UC_X86_REG_R9],[missions,0,state_address,operation]):engine.reg_write(reg,value)
        engine.reg_write(UC_X86_REG_RSP,sp)
        engine.emu_start(base+0x11e6020,stop,timeout=1_000_000,count=100_000)
        assert engine.reg_read(UC_X86_REG_RIP)==stop,'Native level picker exceeded budget'
        result=engine.reg_read(UC_X86_REG_RAX)&0xffffffff
        cases.append(dict(levels=levels,special=special,slot=slot,used=used,state=struct.pack('<Q',state).hex(),
                          result=result,after=bytes(engine.mem_read(state_address,8)).hex()))
    target=ROOT/'artifacts/level-choice-oracle.lua';target.write_text('return '+lua(cases),encoding='ascii')
    subprocess.run([os.environ.get('HD2_LUAJIT',str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe')),
                    str(ROOT/'tests/test_level_choice.lua'),str(ROOT/'src'),str(target)],check=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('fixture',type=Path);main(p.parse_args().fixture)
