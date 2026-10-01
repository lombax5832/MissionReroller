"""src/offsets.lua is the only place an address, RVA or struct offset lives.

Checks the table's shape, checks every anchor against the bytes it names,
and fails when src/ holds an offset anywhere else. Checking the table against
a game dump is scripts/check_offsets.py's job (docs/UPDATING.md).
"""
from pathlib import Path
import re
import struct
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import offsets
import build

SRC = ROOT / 'src'
MODULES = {'game', 'exe'}
# Address arithmetic with a literal: a hex offset or stride of 0x100 or more,
# a decimal one of 1000 or more, or any number added to a module base.
LEAKS = [
    re.compile(r'[+*]\s*0x[0-9a-fA-F]{3,}'),
    re.compile(r'[\w)\]]\s*\+\s*\d{4,}\b(?!\s*\*)'),  # not a byte multiplier: z+16777216*w
    re.compile(r'\b(game|exe)(\(\))?\s*\+\s*\d'),
]
# Lines that match LEAKS without holding an offset, as (file, text).
ALLOWED = set()


def code_length(entry):
    return len(entry['bytes']) // 2 if 'bytes' in entry else entry.get('size', 0)


def rip_target(anchor):
    """A global's anchor is a RIP-relative instruction that ends in its displacement."""
    data = bytes.fromhex(anchor['bytes'])
    assert 6 <= len(data) <= 15 and data[-5] & 0xc7 == 5, anchor
    return anchor['rva'] + len(data) + struct.unpack_from('<i', data, len(data) - 4)[0]


def encodes(data, number):
    """number is a 4-byte displacement or immediate somewhere after the opcode."""
    return struct.pack('<i', number) in data[2:]


def uses_displacement(data, value):
    """value is a [reg+disp32] displacement somewhere in data."""
    needle, start = struct.pack('<I', value), 0
    while (at := data.find(needle, start)) >= 0:
        start = at + 1
        if at >= 1 and data[at - 1] >> 6 == 2 and data[at - 1] & 7 != 4:
            return True
        if at >= 2 and data[at - 2] >> 6 == 2 and data[at - 2] & 7 == 4:
            return True
    return False


def check_table(data):
    code, names = data['code'], set()
    assert isinstance(data['build'], int) and set(data['hashes']) == {'game', 'exe'}
    for section in ('code', 'globals'):
        for name, entry in data[section].items():
            assert name not in names, 'duplicate name ' + name
            names.add(name)
            assert entry['module'] in MODULES and entry['rva'] > 0 and entry['from'], name
    for name, entry in code.items():
        kinds = [k for k in ('bytes', 'sha256', 'within') if k in entry]
        assert len(kinds) == 1, name + ': one of bytes, sha256 or within'
        if 'bytes' in entry:
            assert re.fullmatch(r'(?:[0-9a-f]{2})+', entry['bytes']), name
        elif 'sha256' in entry:
            assert re.fullmatch(r'[0-9a-f]{64}', entry['sha256']) and entry['size'] > 0, name
        else:
            outer = code[entry['within']]
            assert outer['module'] == entry['module'], name
            assert outer['rva'] <= entry['rva'] < outer['rva'] + code_length(outer), name + ' lies outside ' + entry['within']
    anchored = 0
    for name, entry in data['globals'].items():
        assert ('anchor' in entry) != bool(entry.get('unverified')), name + ': an anchor or unverified=true'
        if 'anchor' in entry:
            assert rip_target(entry['anchor']) == entry['rva'], name + ': the anchor addresses another global'
            anchored += 1
    assert anchored > 0
    fields = 0
    for struct_name, entries in data['structs'].items():
        # A struct may share its global's name (O.rva.board, O.board); O
        # reserves only these two.
        assert struct_name not in ('rva', 'build'), struct_name
        for field, entry in entries.items():
            label = struct_name + '.' + field
            values = entry['values']
            assert values and all(isinstance(v, int) and v >= 0x100 for v in values), label + ': offsets below 0x100 stay inline'
            assert ('anchor' in entry) != bool(entry.get('unverified')), label + ': an anchor or unverified=true'
            anchor = entry.get('anchor')
            if isinstance(anchor, dict):
                # One instruction, checked on the first frame like a global's anchor.
                assert len(values) == 1, label + ': an instruction anchors a single value'
                assert set(anchor) <= {'rva', 'bytes', 'via', 'module'} and anchor['rva'] > 0, label
                assert anchor.get('module', 'game') in MODULES, label
                data_bytes = bytes.fromhex(anchor['bytes'])
                assert re.fullmatch(r'(?:[0-9a-f]{2})+', anchor['bytes']) and len(data_bytes) <= 15, label
                plus = 0
                if 'via' in anchor:
                    outer, name = anchor['via'].split('.')
                    plus = data['structs'][outer][name]['values'][0]
                    assert len(data['structs'][outer][name]['values']) == 1, label + ': via names a single value'
                assert encodes(data_bytes, values[0] + plus), label + ': the anchor does not encode it'
            elif anchor is not None:
                owner = code[anchor]
                # Hashed code is checked against a dump by scripts/check_offsets.py.
                if 'bytes' in owner:
                    for value in values:
                        assert uses_displacement(bytes.fromhex(owner['bytes']), value), label + ': ' + anchor + ' does not use it'
            fields += 1
    assert fields > 0
    for name, entry in data.get('research', {}).items():
        assert name not in names and entry['rva'] > 0 and entry['from'], name


def check_release(data):
    release = build.source()
    assert b'\nresearch={' not in release and b'research=' not in release.split(b'local O=', 1)[0], 'research ships'
    for name in data.get('research', {}):
        assert name.encode() + b'={' not in release, name + ' ships'
    core = (SRC / 'mods/ipodalexei/mission_reroller.lua').read_text()
    assert 'M.SUPPORTED_BUILD = %d\n' % data['build'] in core, 'the core decodes another build'


def check_leaks():
    # The forms this file replaced are caught; byte decoding is not.
    for sample in ('pointer(game+0x347cee8)', 'read(b+0x78e84,4)', 'campaign+planet*0x118',
                   'owner+1696', 'pointer(memory.game()+0x3326e68)+25224', 'exe+0x1a10210', 'game+12'):
        assert any(p.search(sample) for p in LEAKS), sample
    for sample in ('a+c*256+d*65536+e*16777216', 'return x+256*y+65536*z+16777216*w', 'u(bytes,k*92+28)',
                   'page(b+O.board.seed,4,0x20000)', 'LEFT+402'):
        assert not any(p.search(sample) for p in LEAKS), sample
    found = []
    for path in sorted(SRC.rglob('*.lua')):
        if path.name == 'offsets.lua':
            continue
        name = path.relative_to(SRC).as_posix()
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split('--', 1)[0]
            if (name, line.strip()) in ALLOWED:
                continue
            if any(p.search(code) for p in LEAKS):
                found.append(f'src/{name}:{number}: {line.strip()}')
    assert not found, 'Offsets belong in src/offsets.lua (docs/UPDATING.md):\n' + '\n'.join(found)


def main():
    data = offsets.raw()
    check_table(data)
    check_release(data)
    check_leaks()
    print('Offsets: table shape, anchors, release without research, and no offset outside src/offsets.lua passed')


if __name__ == '__main__':
    main()
