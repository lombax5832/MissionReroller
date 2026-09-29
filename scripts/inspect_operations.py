"""Decode bounded Memory Explorer captures, never open or modify the game.

Research output only: these records do not establish legal-option completeness,
host authority, full constellation forecasts or a native reroll adapter.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

BUILD = 25480438
OP_SIZE, OP_CAPACITY = 92, 110
MISSION_SIZE, MISSION_CAPACITY = 76, 330
FIELDS = ('selection', 'operations', 'operation_cache', 'mission_count',
          'mission_cache', 'missions', 'campaign_seed', 'screen')
# Unpacked reference dump, not the installed packed module.
DUMP_SHA256 = '9771f97b0d0810b96f95df2938956972821bb05cb3d1f05ab2af5fa2c4e0d34e'


def u32(data, offset=0):
    return struct.unpack_from('<I', data, offset)[0]


def unpack_frame(frame):
    if not isinstance(frame, dict) or set(frame) != set(FIELDS):
        raise ValueError('Unexpected capture fields')
    result = {}
    for key in FIELDS:
        value = frame[key]
        if not isinstance(value, str) or len(value) > OP_CAPACITY * OP_SIZE * 8:
            raise ValueError('Invalid bounded hex field: ' + key)
        try:
            result[key] = bytes.fromhex(value)
        except ValueError as exc:
            raise ValueError('Invalid hex: ' + key) from exc
    sizes = dict(selection=20, operations=OP_SIZE * OP_CAPACITY,
                 operation_cache=8, mission_count=4, mission_cache=4,
                 campaign_seed=4, screen=24)
    for key, size in sizes.items():
        if len(result[key]) != size:
            raise ValueError('Incorrect byte count: ' + key)
    count = u32(result['mission_count'])
    if count > MISSION_CAPACITY or len(result['missions']) != count * MISSION_SIZE:
        raise ValueError('Invalid mission array length')
    return result


def decode_capture(capture):
    if capture.get('format') != 2 or capture.get('build') != BUILD:
        raise ValueError('Unsupported capture format/build')
    if not isinstance(capture.get('session'), str) or not capture['session']:
        raise ValueError('Missing capture session')
    if capture.get('session_after') != capture['session']:
        raise ValueError('Game session changed')
    before, after = unpack_frame(capture['before']), unpack_frame(capture['after'])
    if before != after:
        raise ValueError('State changed between read passes; capture again')
    frame = before
    screen_count = u32(frame['screen'], 20)
    if not 1 <= screen_count <= 5 or u32(frame['screen'], 4 * (screen_count - 1)) != 15:
        raise ValueError('Galactic map is not the top screen')
    planet = u32(frame['selection'])
    if planet >= 512:
        raise ValueError('No valid selected planet')
    if (u32(frame['operation_cache']) != planet or frame['operation_cache'][4] != 0
            or u32(frame['mission_cache']) != planet):
        raise ValueError('Operation/mission cache is stale or rebuilding')
    selected = u32(frame['selection'], 8)
    if selected != 0xffffffff and selected >= OP_CAPACITY:
        raise ValueError('Invalid selected operation index')
    operations, used = [], set()
    rows, missions = frame['operations'], frame['missions']
    mission_count = u32(frame['mission_count'])
    for index in range(OP_CAPACITY):
        op = rows[index * OP_SIZE:(index + 1) * OP_SIZE]
        if op[52] == 0:
            continue
        if op[52] != 1:
            raise ValueError('Unknown operation validity flag')
        if struct.unpack_from('<H', op, 16)[0] != planet:
            continue
        if u32(op) != index:
            raise ValueError('Operation row identity mismatch')
        difficulty = op[32]
        count = op[88]  # +84 is a separate status count, not this count.
        if not 1 <= difficulty <= 10 or not 1 <= count <= 3 or op[84] != count:
            raise ValueError('Unsupported operation shape')
        decoded = []
        for slot in range(count):
            mi = op[85 + slot]
            if mi >= mission_count or mi in used:
                raise ValueError('Invalid or duplicate mission reference')
            used.add(mi)
            m = missions[mi * MISSION_SIZE:(mi + 1) * MISSION_SIZE]
            if u32(m, 40) != index or u32(m, 60) != difficulty or u32(m, 68) != slot:
                raise ValueError('Mission owner, difficulty or slot mismatch')
            if u32(m, 56) != u32(op, 72 + 4 * slot):
                raise ValueError('Mission status disagrees with its operation')
            native_type = u32(m, 48)
            if native_type >= 256:
                raise ValueError('Unknown native mission type')
            decoded.append(dict(row=mi, slot=slot, native_type=native_type,
                                seed=u32(m, 52), level_index=u32(m, 44),
                                status=u32(m, 56), kind=u32(m, 64)))
        operations.append(dict(row=index, operation_id=op[24], difficulty=difficulty,
                               seed=u32(op, 12), template_index=u32(op, 56),
                               faction=u32(op, 36), status_count=op[84], missions=decoded))
    if not operations:
        raise ValueError('No readable operations for this planet')
    if selected != 0xffffffff and not any(o['row'] == selected for o in operations):
        raise ValueError('Selected operation is not in this planet snapshot')
    fingerprint = hashlib.sha256(b''.join(frame[key] for key in FIELDS)).hexdigest()
    return dict(research_only=True, matching_ready=False, build=BUILD,
                repeated_reads_agree=True, atomic_snapshot=False,
                fingerprint=fingerprint, planet_index=planet,
                highlighted_operation=None if selected == 0xffffffff else selected,
                campaign_seed=u32(frame['campaign_seed']), operations=operations)


def add_names(result, dump_path, strings_path):
    """Optional historical title hints from external research files, not assets."""
    dump = dump_path.read_bytes()
    if hashlib.sha256(dump).hexdigest() != DUMP_SHA256:
        raise ValueError('Unpacked reference dump hash mismatch')
    source = json.loads(strings_path.read_text(encoding='utf-8'))
    strings = {row['Key']: row['Value'] for row in source['Items']}
    for operation in result['operations']:
        for mission in operation['missions']:
            at = 0x3773420 + mission['native_type'] * 896 + 0x340
            key = u32(dump, at)
            mission['title_hash'] = f'{key:08x}'
            mission['title_hint'] = strings.get(key)
    result['title_source'] = 'Saved dump and external extracted strings; verify names in-game'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--dump', type=Path)
    parser.add_argument('--strings', type=Path)
    parser.add_argument('--difficulty', type=int, choices=range(1, 11))
    args = parser.parse_args()
    if bool(args.dump) != bool(args.strings):
        parser.error('--dump and --strings must be provided together')
    result = decode_capture(json.loads(args.capture.read_text(encoding='utf-8')))
    if args.dump:
        add_names(result, args.dump, args.strings)
    if args.difficulty:
        result['operations'] = [o for o in result['operations'] if o['difficulty'] == args.difficulty]
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
