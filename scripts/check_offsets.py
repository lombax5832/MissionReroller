"""Check src/offsets.lua against unpacked game images, and suggest fixes.

    python -B scripts/check_offsets.py [<dump dir>] [--reference <dump dir>] [--find-anchors]

<dump dir> holds game.dll.unpacked.bin and helldivers2.exe.unpacked.bin from
GameDllDumper (file offsets are RVAs). It defaults to ../dumps/build-<build>
for the build offsets.lua names. --reference is the dump offsets.lua was made
for (the same default); a stale entry is searched for in <dump dir> by its
reference bytes with relative displacements wildcarded, and the new RVA is
printed. --find-anchors prints anchor candidates for globals without one and
for unverified struct fields. Nothing is written; edit offsets.lua by hand.
Exit status 1 when any entry is stale.
"""
import argparse
import hashlib
from pathlib import Path
import re
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import offsets

ROOT = Path(__file__).resolve().parents[1]
IMAGES = {'game': 'game.dll.unpacked.bin', 'exe': 'helldivers2.exe.unpacked.bin'}
TEXT_END = 0x2111000  # the first section of both images is code; past it is data
# REX.W, an opcode without an immediate, and a RIP-relative ModRM: the
# 7-byte form an anchor takes (mov, lea, cmp, add, sub, xor, or, and, test).
RIP_FORM = re.compile(rb'(?=([\x48-\x4f][\x03\x0b\x23\x2b\x33\x39\x3b\x85\x89\x8b\x8d][\x05\x0d\x15\x1d\x25\x2d\x35\x3d]))', re.S)


class Images:
    def __init__(self, folder):
        self.folder = Path(folder)
        self.data = {}

    def __call__(self, module):
        if module not in self.data:
            path = self.folder / IMAGES[module]
            assert path.exists(), f'missing {path}'
            self.data[module] = path.read_bytes()
        return self.data[module]


def rip_target(image, at):
    """The address a 7-byte RIP-relative instruction at `at` refers to."""
    return at + 7 + struct.unpack_from('<i', image, at + 3)[0]


def code_bytes(entry, image):
    if 'bytes' in entry:
        return image[entry['rva']:entry['rva'] + len(entry['bytes']) // 2]
    if 'size' in entry:
        return image[entry['rva']:entry['rva'] + entry['size']]
    return None


def code_ok(name, entry, code, image):
    if 'bytes' in entry:
        return code_bytes(entry, image).hex() == entry['bytes']
    if 'sha256' in entry:
        return hashlib.sha256(code_bytes(entry, image)).hexdigest() == entry['sha256']
    outer = code[entry['within']]
    length = len(outer['bytes']) // 2 if 'bytes' in outer else outer['size']
    return outer['rva'] <= entry['rva'] < outer['rva'] + length


def wildcard(data):
    """A regex for code with call/jump targets and RIP displacements wildcarded."""
    pattern, i = [], 0
    while i < len(data):
        if data[i] in (0xe8, 0xe9) and i + 5 <= len(data):
            pattern.append(re.escape(data[i:i + 1]) + b'....')
            i += 5
        elif (i + 7 <= len(data) and 0x40 <= data[i] <= 0x4f and data[i + 2] & 0xc7 == 5):
            pattern.append(re.escape(data[i:i + 3]) + b'....')
            i += 7
        else:
            pattern.append(re.escape(data[i:i + 1]))
            i += 1
    return re.compile(b''.join(pattern), re.S)


def relocate(reference, image, rva, length):
    """RVAs in `image` whose code matches `reference`'s at rva, relative targets aside."""
    pattern = wildcard(reference[rva:rva + length])
    return [m.start() for m in pattern.finditer(image, 0, TEXT_END)][:4]


def rip_references(image):
    """Every 7-byte RIP-relative instruction in the code section, by target."""
    targets = {}
    for m in RIP_FORM.finditer(image, 0, TEXT_END):
        targets.setdefault(rip_target(image, m.start()), []).append(m.start())
    return targets


def displacement_users(data, value):
    """Offsets in data where value is a [reg+disp32] displacement."""
    found, needle, start = [], struct.pack('<I', value), 0
    while (at := data.find(needle, start)) >= 0:
        start = at + 1
        if at >= 1 and data[at - 1] >> 6 == 2 and data[at - 1] & 7 != 4:
            found.append(at)
        elif at >= 2 and data[at - 2] >> 6 == 2 and data[at - 2] & 7 == 4:
            found.append(at)
    return found


def check(data, images, reference):
    code, stale = data['code'], []
    for name, entry in sorted(code.items()):
        image = images(entry['module'])
        if code_ok(name, entry, code, image):
            continue
        stale.append(name)
        length = len(entry['bytes']) // 2 if 'bytes' in entry else entry.get('size', 0)
        hint = ''
        if length and reference:
            hint = ' candidates=' + ','.join(hex(r) for r in relocate(reference(entry['module']), image, entry['rva'], length))
        print(f'STALE code {name} rva={entry["rva"]:#x}{hint}')
    for name, entry in sorted(data['globals'].items()):
        anchor = entry.get('anchor')
        if not anchor:
            continue
        image = images(entry['module'])
        at = anchor['rva']
        if image[at:at + 7].hex() == anchor['bytes'] and rip_target(image, at) == entry['rva']:
            continue
        stale.append(name)
        hint = ''
        if reference:
            old = reference(entry['module'])
            for moved in relocate(old, image, at - 32, 64):
                new = moved + 32
                hint = f' anchor_rva={new:#x} rva={rip_target(image, new):#x} bytes={image[new:new + 7].hex()}'
                break
        print(f'STALE global {name} rva={entry["rva"]:#x}{hint}')
    for struct_name, fields in sorted(data['structs'].items()):
        for field, entry in sorted(fields.items()):
            anchor = entry.get('anchor')
            if not anchor:
                continue
            owner = code[anchor]
            users = displacement_users(code_bytes(owner, images(owner['module'])), entry['values'][0])
            if not users:
                stale.append(f'{struct_name}.{field}')
                print(f'STALE field {struct_name}.{field}={entry["values"][0]:#x}: {anchor} no longer uses it')
    return stale


def find_anchors(data, images):
    """Anchor candidates: references from code entries first, else the first in the image."""
    code = data['code']
    references = {module: rip_references(images(module)) for module in IMAGES}
    spans = [(e['module'], e['rva'], e['rva'] + (len(e['bytes']) // 2 if 'bytes' in e else e.get('size', 0)))
             for e in code.values()]
    for name, entry in sorted(data['globals'].items()):
        if entry.get('anchor'):
            continue
        image = images(entry['module'])
        users = references[entry['module']].get(entry['rva'], [])
        inside = [u for u in users if any(m == entry['module'] and a <= u < b for m, a, b in spans)]
        pick = (inside or users or [None])[0]
        if pick is None:
            print(f'global {name}: no 7-byte RIP-relative reference')
        else:
            print(f"global {name}: anchor={{rva=0x{pick:x},bytes='{image[pick:pick + 7].hex()}'}} "
                  f"({len(users)} references, {len(inside)} inside code entries)")
    for struct_name, fields in sorted(data['structs'].items()):
        for field, entry in sorted(fields.items()):
            if not entry.get('unverified'):
                continue
            value = entry['values'][0]
            if value < 0x1000:
                continue  # too common a displacement to name its user from a match
            for name, owner in sorted(code.items()):
                data_bytes = code_bytes(owner, images(owner['module']))
                if data_bytes and displacement_users(data_bytes, value):
                    print(f"field {struct_name}.{field}={value:#x}: anchor='{name}'")
                    break


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('dump', nargs='?')
    parser.add_argument('--reference')
    parser.add_argument('--find-anchors', action='store_true')
    args = parser.parse_args(argv)
    data = offsets.raw()
    # The workspace's dumps/, found upward so a worktree resolves it too.
    workspace = next((p for p in ROOT.parents if (p / 'dumps').is_dir()), ROOT.parent)
    default = workspace / 'dumps' / f'build-{data["build"]}'
    images = Images(args.dump or default)
    reference = Images(args.reference or default)
    if reference.folder.resolve() == images.folder.resolve():
        reference = None
    if args.find_anchors:
        find_anchors(data, images)
        return 0
    stale = check(data, images, reference)
    total = len(data['code']) + len(data['globals']) + sum(len(f) for f in data['structs'].values())
    print(f'{len(stale)} stale of {total} entries' if stale else f'all anchored entries match {images.folder}')
    return 1 if stale else 0


if __name__ == '__main__':
    sys.exit(main())
