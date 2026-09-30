"""Print the mission families for src/search_session.lua from research files.

Development tool. Mission titles come from the mission records of the saved
build 25480438 image (the title key, mission_type.title_key in src/offsets.lua) and the English (US) string
table extracted with Filediver. Neither input is packaged. The first twelve
families keep their established order and names; the rest follow by title.
"""
import json
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import offsets

O = offsets.load()
IMAGE = ROOT.parent / f'dumps/build-{O.build}/game.dll.unpacked.bin'
STRINGS = ROOT.parent / f'extracted/strings-{O.build}/0xd29d9f674db28566.strings.json'
RECORDS, STRIDE, COUNT = O.rva['mission_types'], O.field('mission_type', 'size'), 162
ESTABLISHED = [
    ('Launch ICBM', ['LAUNCH ICBM']),
    ('Geological Survey', ['CONDUCT GEOLOGICAL SURVEY']),
    ('Eradicate forces', ['ERADICATE AUTOMATON FORCES', 'ERADICATE TERMINID SWARM', 'ERADICATE ILLUMINATE FORCES']),
    ('Spread Democracy', ['SPREAD DEMOCRACY']),
    ('Evacuate High-Value Assets', ['EVACUATE HIGH-VALUE ASSETS']),
    ('Retrieve Valuable Data', ['RETRIEVE VALUABLE DATA']),
    ('Search and Destroy', ['SEARCH AND DESTROY']),
    ('Emergency Evacuation', ['EMERGENCY EVACUATION']),
    ('Nuke Nursery', ['NUKE NURSERY']),
    ('Purge Hatcheries', ['PURGE HATCHERIES']),
    ('Destroy Command Bunkers', ['DESTROY COMMAND BUNKERS']),
    ('Retrieve Recon Craft Intel', ['RETRIEVE RECON CRAFT INTEL']),
]
SMALL = {'AND', 'THE', 'OF', 'TO', 'OUT'}
KEEP = {'ICBM', 'TCS+', 'E-711'}


def title_case(text):
    words = []
    for index, word in enumerate(text.split(' ')):
        if word in KEEP:
            words.append(word)
        elif index and word in SMALL:
            words.append(word.lower())
        else:
            words.append('-'.join(part.lower() if part in SMALL and i else part.capitalize()
                                  for i, part in enumerate(word.split('-'))))
    return ' '.join(words)


def main():
    image = IMAGE.read_bytes()
    strings = {row['Key']: row['Value'] for row in json.loads(STRINGS.read_text(encoding='utf-8'))['Items']}
    by_title, unnamed = {}, []
    for kind in range(COUNT):
        at = RECORDS + kind * STRIDE
        if not struct.unpack_from('<I', image, at)[0]:
            continue
        title = strings.get(struct.unpack_from('<I', image, at + O.field('mission_type', 'title_key'))[0])
        if title:
            by_title.setdefault(title, []).append(kind)
        else:
            unnamed.append(kind)
    families = []
    for name, titles in ESTABLISHED:
        kinds = sorted(kind for title in titles for kind in by_title.pop(title))
        families.append((name, kinds))
    for title in sorted(by_title):
        families.append((title_case(title), by_title[title]))
    for name, kinds in families:
        assert all(32 <= ord(c) < 127 and c not in "'\\" for c in name), name
        print("    {name='%s',ids={%s}}," % (name, ','.join(map(str, kinds))))
    print('-- %d families, %d mission types; untitled types: %s' % (
        len(families), sum(len(k) for _, k in families), ','.join(map(str, unnamed))))


if __name__ == '__main__':
    main()
