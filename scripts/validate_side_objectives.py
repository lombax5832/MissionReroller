"""Research-only oracle for the Lua side-objective port (src/side_objective_prediction.lua).

Emulates the game's descriptor objective packer 1756660 in Unicorn for random
mission descriptors, on memory paged in on demand from the running game
through Memory Explorer (read-only; emulated writes stay local), then replays
the Lua port on the same pages (tests/check_side_objective_oracle.lua) until
it needs no further page. The game must be running with the Memory Explorer
addon and no other Memory Explorer client. Captures go to the ignored
artifacts folder and are never packaged.

    python -B scripts/validate_side_objectives.py [cases] [random seed]
"""
import os
from pathlib import Path
import random
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
DEPS = next((p/'tools/seed-emulator-deps' for p in ROOT.parents if (p/'tools/seed-emulator-deps').is_dir()), ROOT.parent/'tools/seed-emulator-deps')
sys.path.insert(0, str(DEPS))
MEMORY_EXPLORER = next((p/'MemoryExplorer' for p in ROOT.parents if (p/'MemoryExplorer/server').is_dir()), ROOT.parent/'MemoryExplorer')
sys.path.insert(0, str(Path(os.environ.get('MEMORY_EXPLORER_ROOT', MEMORY_EXPLORER)) / 'server'))
sys.path.insert(0, str(ROOT / 'scripts'))
from unicorn import Uc, UcError, UC_ARCH_X86, UC_MODE_64, UC_HOOK_MEM_UNMAPPED
from unicorn.x86_const import UC_X86_REG_RSP, UC_X86_REG_RCX, UC_X86_REG_RDX, UC_X86_REG_R8, UC_X86_REG_RIP, UC_X86_REG_RAX, UC_X86_REG_GS_BASE
import memory_mcp as mcp
import offsets

O = offsets.load()
CODE = O.data['research']['code_section']
SCRATCH = 0x10000000000
STACK = SCRATCH + 0x100000
STOP = SCRATCH + 0x300000
TEB = SCRATCH + 0x400000
EXTRA = 0x68bfbb59


def main(count='400', rng_seed='1'):
    count, rng = int(count), random.Random(int(rng_seed))
    bridge = mcp.Bridge(Path(os.environ['LOCALAPPDATA']) / 'CowboyBingus/Helldivers2/Logs')
    bridge.acquire()
    session = bridge.call('status')['session']
    game = {m['name']: int(m['base'], 16) for m in bridge.call('modules')['modules']}['game.dll']
    pages = {}

    def live(address, size):
        reply = mcp.call_tool(bridge, 'hd2_read', {'session': session, 'address': hex(address), 'size': size})
        return bytes.fromhex(reply['hex'])

    def page(address):
        address &= ~4095
        if address not in pages:
            pages[address] = live(address, 4096)
        return pages[address]

    def read(address, size):
        out = b''
        while size > 0:
            n = min(size, 4096 - (address & 4095))
            out += page(address)[address & 4095:(address & 4095) + n]
            address += n
            size -= n
        return out

    def u32(address):
        return struct.unpack('<I', read(address, 4))[0]

    def u64(address):
        return struct.unpack('<Q', read(address, 8))[0]
    board = u64(game + O.rva['board'])
    campaign = board + O.field('board', 'campaign')
    planets = u32(campaign + O.field('campaign', 'planet_count'))
    stride = O.field('campaign', 'definition_stride')
    keys = [p for p in range(min(planets, 512)) if u32(campaign + p * stride + 0x18)]
    world_count = u32(board + O.field('board', 'world_modifier_count'))
    world_ids = u64(board + O.field('board', 'world_modifier_ids'))
    world = [u32(world_ids + 4 * i) for i in range(world_count)]
    viewed = u32(board + O.field('board', 'selection') + 4)
    chosen = ([viewed] if viewed in keys else []) + rng.sample(keys, min(5, len(keys)))

    uc = Uc(UC_ARCH_X86, UC_MODE_64)
    mapped = set()

    def absent(engine, access, address, size, value, context):
        start = address & ~4095
        try:
            data = page(start)
        except Exception:
            return False
        code = game + CODE['rva'] <= start < game + CODE['rva'] + CODE['size']
        engine.mem_map(start, 4096, 7 if code else 3)
        engine.mem_write(start, data)
        mapped.add(start)
        return True
    uc.hook_add(UC_HOOK_MEM_UNMAPPED, absent)
    for address, size in ((SCRATCH, 0x10000), (STACK, 0x100000), (STOP, 0x1000), (TEB, 0x2000)):
        uc.mem_map(address, size)
    uc.mem_write(TEB + 0x30, struct.pack('<Q', TEB))
    uc.reg_write(UC_X86_REG_GS_BASE, TEB)

    def emulate(planet, kind, difficulty, seed, modifiers):
        descriptor = bytearray(0xe8)
        struct.pack_into('<I', descriptor, 0, seed)
        descriptor[8] = u32(game + O.rva['mission_types'] + kind * O.field('mission_type', 'size') + 8) & 0xff
        descriptor[9] = difficulty
        struct.pack_into('<I', descriptor, 0xc, u32(campaign + planet * stride + 0x18))
        struct.pack_into('<H', descriptor, 0x1a, kind)
        descriptor[0xc7] = len(modifiers)
        for i, hash in enumerate(modifiers):
            struct.pack_into('<I', descriptor, 0xc8 + 4 * i, hash)
        uc.mem_write(SCRATCH, bytes(descriptor))
        uc.mem_write(SCRATCH + 0x1000, b'\xa5' * 0x400)
        stack = STACK + 0xfff08
        uc.mem_write(stack, struct.pack('<Q', STOP))
        uc.reg_write(UC_X86_REG_RSP, stack)
        uc.reg_write(UC_X86_REG_RCX, SCRATCH)
        uc.reg_write(UC_X86_REG_RDX, SCRATCH + 0x1000)
        uc.reg_write(UC_X86_REG_R8, SCRATCH + 0x1200)
        uc.emu_start(game + O.rva['objective_inputs'], STOP, timeout=20_000_000, count=50_000_000)
        if uc.reg_read(UC_X86_REG_RIP) != STOP:
            raise RuntimeError('Emulation stopped before return')
        n = uc.reg_read(UC_X86_REG_RAX) & 0xff
        ids = struct.unpack('<64I', bytes(uc.mem_read(SCRATCH + 0x1000, 0x100)))
        roles = struct.unpack('<64I', bytes(uc.mem_read(SCRATCH + 0x1200, 0x100)))
        if n > 32 or ids[n] != 0xa5a5a5a5:
            raise RuntimeError('Unexpected objective count %d' % n)
        return [(ids[i], roles[i]) for i in range(n)]

    cases = []
    lists = [[], [0x493afbe6], [0xa6afd597, 0x2119a229]]
    for _ in range(count):
        kind = rng.randrange(162)
        record = game + O.rva['mission_types'] + kind * O.field('mission_type', 'size')
        lo, hi = u32(record + 0xc), u32(record + 0x10)
        low, high = max(1, min(lo, 10)), max(1, min(hi, 10))
        difficulty = rng.randint(min(low, high), max(low, high)) if rng.random() < 0.85 else rng.randint(1, 10)
        modifiers = rng.choice(lists) if rng.random() < 0.6 else rng.sample(world, rng.randint(1, 3))
        planet = rng.choice(chosen)
        seed = rng.getrandbits(32)
        try:
            expected = emulate(planet, kind, difficulty, seed, modifiers)
        except (UcError, RuntimeError) as error:
            print('case skipped: planet=%d kind=%d difficulty=%d seed=%d: %s rip=%x' % (
                planet, kind, difficulty, seed, error, uc.reg_read(UC_X86_REG_RIP)))
            continue
        cases.append((planet, kind, difficulty, seed, modifiers, expected))
    folder = ROOT / 'artifacts/side-objectives'
    folder.mkdir(parents=True, exist_ok=True)
    with open(folder / 'cases.lua', 'w', encoding='ascii') as out:
        out.write('return {\n')
        for planet, kind, difficulty, seed, modifiers, expected in cases:
            out.write('{planet=%d,kind=%d,difficulty=%d,seed=%d,modifiers={%s},expected={%s}},\n' % (
                planet, kind, difficulty, seed, ','.join(str(m) for m in modifiers),
                ','.join('{%d,%d}' % pair for pair in expected)))
        out.write('}\n')
    sides = sum(1 for case in cases for _, role in case[5] if role == 3)
    print('emulated %d cases (%d side objectives, %d extra flags), %d pages' % (
        len(cases), sides, sum(1 for case in cases for oid, _ in case[5] if oid == EXTRA), len(pages)))
    lua = os.environ.get('HD2_LUAJIT', str(ROOT.parent / 'tools/src/LuaJIT/src/luajit.exe'))
    capture, missing = folder / 'capture.lua', folder / 'missing.txt'
    for _ in range(20000):
        lines = ["return {game='%d',board='%d',ranges={" % (game, board)]
        lines += ["{address='%d',hex='%s'}," % (address, data.hex()) for address, data in sorted(pages.items())]
        lines.append('}}')
        capture.write_text('\n'.join(lines), encoding='ascii')
        missing.write_text('', encoding='ascii')
        result = subprocess.run([lua, str(ROOT / 'tests/check_side_objective_oracle.lua'), str(capture), str(ROOT / 'src'),
                                 str(folder / 'cases.lua'), str(missing)], capture_output=True, text=True)
        if result.returncode == 3:
            address = int(missing.read_text(), 16)
            assert address not in pages, 'Repeated page request'
            page(address)
            continue
        print(result.stdout + result.stderr)
        print('session %s, %d pages captured' % (session, len(pages)))
        return result.returncode
    raise SystemExit('Capture did not converge')


if __name__ == '__main__':
    raise SystemExit(main(*sys.argv[1:]))
