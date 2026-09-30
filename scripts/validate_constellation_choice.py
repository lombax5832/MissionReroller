"""Write an offline oracle for the Lua constellation port from the saved image.

The expected tags come from this independent implementation of 1758000 and
177deb0 over the static tables of the ignored build 25480438 memory image.
The oracle is an ignored artifact; it is not packaged.
"""
from pathlib import Path
import random
import struct
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import offsets

O = offsets.load()
IMAGE = ROOT.parent / f'dumps/build-{O.build}/game.dll.unpacked.bin'
HASHES, DIFFICULTY, MISSIONS, CATEGORIES = (O.rva[name] for name in ('enemy_tags', 'difficulty_rows', 'mission_types', 'categories'))
ROW, RECORD = O.field('difficulty_row', 'size'), O.field('mission_type', 'size')
CANDIDATES = dict(zip((2, 3, 4), O.field('difficulty_row', 'constellation_candidates')))
FALLBACK = dict(zip((2, 3, 4), O.field('difficulty_row', 'constellation_blockers')))
HORDE = -0x7a83d32e807d87b7


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def resolve(image, faction, difficulty, kind, seed, initial):
    def u32(at):
        return struct.unpack_from('<I', image, at)[0]
    tags = []

    def add(tag):
        if tag not in tags and len(tags) < 16:
            tags.append(tag)
    for tag in initial:
        add(tag)
    row = DIFFICULTY + (difficulty - 1) * ROW
    empty, pool, total = not tags, [], 0.0
    for i in range(8):
        tag, weight, only_empty = struct.unpack_from('<IfB', image, row + CANDIDATES[faction] + i * 12)
        if tag and (not only_empty or empty):
            pool.append((tag, weight))
            total = f32(total + weight)
    state = seed
    for _ in range(u32(row + O.field('difficulty_row', 'constellation_draws'))):
        if not pool or total <= 0:
            break
        state = (state * 0x5851F42D4C957F2D + 0x14057B7EF767814F) & 0xffffffffffffffff
        target = f32(f32(f32(float(state >> 32)) * 2.0 ** -32) * total)
        reached = 0.0
        for tag, weight in pool:
            reached = f32(reached + weight)
            if target <= reached:
                add(tag)
                break
    fallback = u32(row + FALLBACK[faction] + 32)
    if fallback and fallback not in tags:
        blocked = False
        for i in range(8):
            blocker = u32(row + FALLBACK[faction] + i * 4)
            if not blocker:
                break
            blocked = blocked or blocker in tags
        if not blocked:
            add(fallback)
    record = MISSIONS + kind * RECORD
    if image[record + 0x34] == 2 and struct.unpack_from('<q', image, record + O.field('mission_type', 'horde_tag'))[0] == HORDE:
        add(1)
    for i in range(8):
        excluded = u32(record + 0x14 + i * 4)
        if not excluded:
            break
        if excluded in tags:
            tags.remove(excluded)
    return sorted(tag for tag in tags if tag)


def main(output=None):
    image = IMAGE.read_bytes()
    output = Path(output) if output else ROOT / 'artifacts/constellation-oracle.lua'
    chooser = random.Random(25480438)
    kinds = {2: [], 3: [], 4: []}
    for kind in range(162):
        record = MISSIONS + kind * RECORD
        faction = struct.unpack_from('<I', image, record + 8)[0]
        if struct.unpack_from('<I', image, record)[0] and faction in kinds:
            special = image[record + 0x34] == 2 or any(struct.unpack_from('<8I', image, record + 0x14))
            kinds[faction].append((not special, kind))
    cases = []
    for faction, available in kinds.items():
        chosen = [kind for _, kind in sorted(available)[:8]]
        assert chosen, 'No mission records for faction %d' % faction
        blockers = [struct.unpack_from('<I', image, DIFFICULTY + FALLBACK[faction] + i * 4)[0] for i in range(8)]
        for difficulty in range(1, 11):
            for kind in chosen:
                excluded = [x for x in struct.unpack_from('<8I', image, MISSIONS + kind * RECORD + 0x14) if x]
                initials = [[], [9], [31, 10]] + [[x] for x in excluded[:1]] + [[x] for x in blockers[:1] if x]
                seeds = [0, 1, 0x7fffffff, 0x80000000, 0xffffffff] + [chooser.getrandbits(32) for _ in range(24)]
                for initial in initials:
                    for seed in seeds:
                        cases.append((faction, difficulty, kind, seed, initial,
                                      resolve(image, faction, difficulty, kind, seed, initial)))
    ranges = [(HASHES, 32 * 4), (DIFFICULTY, 10 * ROW), (MISSIONS, 162 * RECORD), (CATEGORIES, 14 * 0xa8)]
    lines = ['return {build=%d,ranges={' % O.build]
    for rva, size in ranges:
        lines.append("{rva=%d,hex='%s'}," % (rva, image[rva:rva + size].hex()))
    lines.append('},cases={')
    for faction, difficulty, kind, seed, initial, expected in cases:
        lines.append('{%d,%d,%d,%d,{%s},{%s}},' % (faction, difficulty, kind, seed,
                                                     ','.join(map(str, initial)), ','.join(map(str, expected))))
    lines.append('}}')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text('\n'.join(lines) + '\n')
    print('Constellation oracle: %d cases -> %s' % (len(cases), output))
    return output


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)
