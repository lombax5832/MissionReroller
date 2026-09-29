"""Offline differential oracles for composition stages with explicit input seams.

Only development uses Unicorn. Dependencies at each stage's boundary are supplied
as synthetic resolved inputs; this does not validate campaign input decoding.
"""
import argparse
import os
from pathlib import Path
import random
import struct
import subprocess
import sys
from fixture_memory import FixtureMemory
from validate_lua_identity import lua

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent/'tools/seed-emulator-deps'))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_CODE
from unicorn.x86_const import *


def main(folder):
    memory = FixtureMemory(folder); base = int(memory.meta['game'], 16)
    engine = Uc(UC_ARCH_X86, UC_MODE_64)
    mapped = set()
    for address, data in memory.pages.items():
        executable = (base+0x11e3000 <= address < base+0x11e7000 or
                      base+0x2088000 <= address < base+0x2089000)
        engine.mem_map(address, 4096, 5 if executable else 1)
        engine.mem_write(address, data); mapped.add(address)
    scratch = 0x10000000000
    engine.mem_map(scratch, 0x200000, 3)
    def put(address, data):
        for page in range(address & ~4095, (address+len(data)+4095) & ~4095, 4096):
            if not scratch <= page < scratch+0x200000 and page not in mapped:
                engine.mem_map(page, 4096, 1); mapped.add(page)
        engine.mem_write(address, data)
    def word(a, n): put(a, struct.pack('<I', n))
    def quad(a, n): put(a, struct.pack('<Q', n))
    def f32(a, n): put(a, struct.pack('<f', n))
    def u32(a): return struct.unpack('<I', engine.mem_read(a, 4))[0]
    def u64(a): return struct.unpack('<Q', engine.mem_read(a, 8))[0]
    sp = scratch+0x1fff08; stop = base+0x11e3250-1
    handlers = {}
    def hook(uc, address, size, user):
        fn = handlers.get(address-base)
        if fn:
            result = fn(); stack = uc.reg_read(UC_X86_REG_RSP)
            uc.reg_write(UC_X86_REG_RAX, result)
            uc.reg_write(UC_X86_REG_RIP, u64(stack)); uc.reg_write(UC_X86_REG_RSP, stack+8)
    engine.hook_add(UC_HOOK_CODE, hook)
    for rva in (0x11f96e0,0x174a610,0x174a6e0,0x11ebb40,0x11e4cd0):
        page=(base+rva)&~4095
        if page not in mapped:
            engine.mem_map(page,4096,5);mapped.add(page)
        else: engine.mem_protect(page,4096,5)
    def invoke(rva, args):
        quad(sp, stop)
        for i, value in enumerate(args[4:]): quad(sp+0x28+i*8, value)
        for reg, value in zip((UC_X86_REG_RCX, UC_X86_REG_RDX, UC_X86_REG_R8, UC_X86_REG_R9), args[:4]):
            engine.reg_write(reg, value)
        engine.reg_write(UC_X86_REG_RSP, sp)
        engine.emu_start(base+rva, stop, timeout=1_000_000, count=200_000)
        assert engine.reg_read(UC_X86_REG_RIP) == stop
        return engine.reg_read(UC_X86_REG_RAX)
    rand = random.Random(68005100)
    cases = dict(eligibility=[], category=[], finalization=[])
    metadata = scratch; env = scratch+0x1000; biome_set = scratch+0x2000
    biome_entries = scratch+0x3000; biome_data = scratch+0x4000; allowed_ptr = scratch+0x9000
    quad(env+0x10, biome_set); quad(biome_set+0x20, biome_entries)
    for index in range(256):
        enabled = index%5 != 0
        handlers.clear(); handlers[0x11f96e0] = lambda: int(enabled)
        mission = dict(faction=rand.choice([0,2,3,4]), minimum=rand.randrange(1,6),
                       maximum=rand.randrange(6,11), category=rand.randrange(1,5), enabled=enabled,
                       biomes=rand.choice([[0],[1],[2,3],[4,0],[5]]))
        context = dict(faction=rand.choice([2,3,4]), difficulty=rand.randrange(1,11),
                       environment_present=index%7 != 0, biomes=rand.sample(range(1,6), index%4))
        category = rand.choice([0,0,mission['category'],6])
        put(metadata, bytes(0x380)); word(metadata+8, mission['faction'])
        word(metadata+12, mission['minimum']); word(metadata+16, mission['maximum'])
        put(metadata+0x34, bytes([mission['category']]))
        quad(metadata+0x368, allowed_ptr); word(metadata+0x370, len(mission['biomes']))
        put(allowed_ptr, bytes(mission['biomes']))
        word(biome_set+0x28, len(context['biomes']))
        for i, biome in enumerate(context['biomes']):
            at = biome_data+i*0x1200; put(at, bytes(0x1200))
            quad(biome_entries+i*0x38+0x30, at)
            f32(at+0x940, 1); put(at+0x958, bytes([biome]))
        result = invoke(0x11e6800, [metadata,100,0xffffffff,123,metadata,context['faction'],
                                  context['difficulty'],category,env if context['environment_present'] else 0]) & 255
        cases['eligibility'].append(dict(mission=mission,context=context,category=category,result=bool(result)))

    root = scratch+0xa000; manager = scratch+0xb000
    quad(base+0x3326340, root); quad(root+0xae288, manager); quad(manager+0x2d0, 0)
    operation = scratch+0xc0000; campaign = scratch+0xd0000; missions = scratch+0x100000
    template = scratch+0x120000; state_ptr = scratch+0x121000; output = scratch+0x122000
    # Supply a deterministic metadata table. Eligibility itself is tested above.
    for id in range(162):
        word(base+0x3773420+id*0x380, 1000+id)
        put(base+0x3773420+id*0x380+0x34, bytes([id%4+1]))
    for index in range(256):
        pool = rand.sample(range(16), index%12)
        candidates = [dict(id=id, category=id%4+1) for id in pool]
        rules = [dict(category=cat, minimum=rand.choice([0,0,1,2]),maximum=rand.choice([0,1,2,3]),
                      weight=rand.choice([0,0.1,1,3])) for cat in rand.sample(range(1,5),index%5)]
        used = rand.choices(range(16), k=index%4)
        usage = {cat:sum(id%4+1==cat for id in used) for cat in range(1,5)}
        put(operation, bytes(92)); put(operation+88, bytes([len(used)])); word(missions+0x61f8,len(used))
        for i,id in enumerate(used): put(operation+85+i,bytes([i]));word(missions+i*76+48,id)
        put(template, bytes(0x490));word(template,123)
        for i,id in enumerate(pool):word(template+0x38+i*8,1000+id)
        word(template+0x208,len(rules))
        for i,r in enumerate(rules):
            at=template+0x178+i*16;put(at,bytes([r['category']]))
            word(at+4,r['minimum']);word(at+8,r['maximum']);f32(at+12,r['weight'])
        state = rand.getrandbits(64);quad(state_ptr,state)
        handlers.clear();handlers[0x174a6e0]=lambda:0;handlers[0x174a610]=lambda:0
        def eligible():
            stack=engine.reg_read(UC_X86_REG_RSP)
            meta=u64(stack+0x28); cat=u64(stack+0x40)&255
            return int(cat==0 or bytes(engine.mem_read(meta+0x34,1))[0]==cat)
        handlers[0x11e6800]=eligible
        count=invoke(0x11e5100,[missions,campaign,operation,template,100,2,0,10,state_ptr,output]) & 0xffffffff
        assert count<=32
        selected=[u32(output+i*4) for i in range(count)]
        cases['category'].append(dict(candidates=candidates,rules=rules,usage=[usage[i] for i in range(1,5)],
                                      state=struct.pack('<Q',state).hex(),selected=selected,
                                      after=bytes(engine.mem_read(state_ptr,8)).hex()))
    for index in range(256):
        handlers.clear();handlers[0x174a6e0]=lambda:0;handlers[0x174a610]=lambda:0
        handlers[0x11ebb40]=lambda:10
        pool=rand.sample(range(8),index%9)
        explicit_index=rand.randrange(8) if index%4==0 else None
        explicit_hash=2000+explicit_index if explicit_index is not None else (9999 if index%7==0 else 0)
        budget=index%7;seed=rand.getrandbits(32);templates=[]
        costs={id:rand.randrange(0,5) for id in range(8)}
        for id in range(13):
            at=base+0x32e94d0+id*0x50
            word(at,3000+id);word(at+4,costs.get(id,1))
        for id in range(25):
            at=base+0x32fef10+id*0x490;put(at,bytes(0x490))
            word(at,2000+id);word(at+8,2)
            weight=rand.choice([0,0.1,1,3]);f32(at+0x20,weight)
            modifiers=[]
            for j,mod_id in enumerate(rand.sample(range(8),index%9)):
                mod_weight=rand.choice([0,0.1,1,4])
                word(at+0x138+j*8,3000+mod_id);f32(at+0x13c+j*8,mod_weight)
                modifiers.append(dict(id=3000+mod_id,cost=costs[mod_id],weight=mod_weight))
            templates.append(dict(index=id,hash=2000+id,weight=weight,modifiers=modifiers))
        put(base+0x328d2a0+9*0x330,bytes(0x330))
        word(base+0x328d2a0+9*0x330+0x10c,budget)
        def template_candidates():
            target=u64(engine.reg_read(UC_X86_REG_RSP)+0x40)
            for j,id in enumerate(pool):word(target+j*4,id)
            return len(pool)
        handlers[0x11e4cd0]=template_candidates
        put(operation,bytes(92));word(operation+8,explicit_hash);word(operation+12,seed)
        put(operation+32,bytes([10]));word(operation+36,2)
        invoke(0x11e3250,[operation])
        selected=u32(operation+0x38);count=bytes(engine.mem_read(operation+0x44,1))[0]
        assert count<=2
        modifiers=[u32(operation+0x3c+j*4) for j in range(count)]
        cases['finalization'].append(dict(seed=seed,budget=budget,explicit_hash=explicit_hash,
            templates=templates,pool=pool,selected=selected,modifiers=modifiers,
            valid=bytes(engine.mem_read(operation+0x34,1))[0]!=0))
    target=ROOT/'artifacts/composition-choices-oracle.lua';target.write_text('return '+lua(cases),encoding='ascii')
    subprocess.run([os.environ.get('HD2_LUAJIT',str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe')),
                    str(ROOT/'tests/test_composition_choices.lua'),str(ROOT/'src'),str(target)],check=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('fixture',type=Path);main(p.parse_args().fixture)
