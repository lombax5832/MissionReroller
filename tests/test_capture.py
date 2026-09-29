"""Synthetic packets only; no game files or live server required."""
import copy
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import unittest
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from inspect_operations import decode_capture
from compare_operations import compare_captures


def fixture():
    ops = bytearray(110 * 92)
    missions = bytearray(3 * 76)
    def put(data, offset, value):
        struct.pack_into('<I', data, offset, value)
    put(ops, 12, 111)
    put(ops, 16, 12)
    put(ops, 32, 10)
    put(ops, 36, 2)
    ops[52] = 1
    ops[84] = ops[88] = 3
    ops[85:88] = bytes([0, 1, 2])
    for i, mission_id in enumerate([5, 7, 9]):
        put(missions, i * 76 + 48, mission_id)
        put(missions, i * 76 + 52, i + 50)
        put(missions, i * 76 + 56, 1)
        put(missions, i * 76 + 60, 10)
        put(missions, i * 76 + 64, 1)
        put(missions, i * 76 + 68, i)
        put(ops, 72 + 4 * i, 1)
    frame = dict(selection=struct.pack('<5I', 12, 12, 0, 0xffffffff, 0).hex(),
                 operations=ops.hex(), operation_cache=struct.pack('<2I', 12, 0).hex(),
                 mission_count=struct.pack('<I', 3).hex(),
                 mission_cache=struct.pack('<I', 12).hex(), missions=missions.hex(),
                 campaign_seed=struct.pack('<I', 20).hex(),
                 screen=struct.pack('<6I', 15, 0, 0, 0, 0, 1).hex())
    return dict(format=2, build=25480438, session='synthetic', session_after='synthetic',
                before=frame, after=copy.deepcopy(frame))


def edit(capture, field, offset, value, size=4):
    for side in ('before', 'after'):
        data = bytearray.fromhex(capture[side][field])
        data[offset:offset + size] = value.to_bytes(size, 'little')
        capture[side][field] = data.hex()


class CaptureTests(unittest.TestCase):
    def test_lua_decoder_agrees(self):
        cases = [('valid', fixture(), True)]
        for key, offset, value in [('operation_cache', 4, 1), ('missions', 40, 2),
                                   ('missions', 56, 2), ('missions', 68, 2),
                                   ('mission_count', 0, 331), ('selection', 8, 2)]:
            c = fixture(); edit(c, key, offset, value)
            cases.append((key + str(offset), c, False))
        c = fixture(); c['after']['campaign_seed'] = '01000000'
        cases.append(('changed', c, False))
        c = fixture(); c['session_after'] = 'another'
        cases.append(('session', c, False))
        c = fixture(); edit(c, 'operations', 89, 0xeeeeee, 3)
        cases.append(('padding', c, True))
        run_lua_cases(cases)

    def test_hover_is_not_regeneration(self):
        a, b = fixture(), fixture()
        edit(b, 'selection', 8, 0xffffffff)
        result = compare_captures(a, b)
        self.assertFalse(result['generation_content_changed'])
        self.assertFalse(result['operation_records_changed'])
        self.assertIsNone(result['highlighted_after'])

    def test_status_is_not_regeneration(self):
        a, b = fixture(), fixture()
        edit(b, 'operations', 72, 2)
        edit(b, 'missions', 56, 2)
        result = compare_captures(a, b)
        self.assertFalse(result['generation_content_changed'])
        self.assertTrue(result['operation_records_changed'])

    def test_seed_and_type_changes_are_reported(self):
        for field, offset, value in [('operations', 12, 222), ('missions', 52, 99),
                                     ('missions', 48, 11)]:
            a, b = fixture(), fixture()
            edit(b, field, offset, value)
            self.assertTrue(compare_captures(a, b)['generation_content_changed'])
        a, b = fixture(), fixture()
        edit(b, 'campaign_seed', 0, 555)
        result = compare_captures(a, b)
        self.assertTrue(result['campaign_seed_changed'])
        self.assertFalse(result['generation_content_changed'])

    def test_different_planets_are_not_compared(self):
        a, b = fixture(), fixture()
        for field, offset in [('selection', 0), ('operations', 16),
                              ('operation_cache', 0), ('mission_cache', 0)]:
            edit(b, field, offset, 13)
        with self.assertRaisesRegex(ValueError, 'same planet'):
            compare_captures(a, b)

    def test_complete_operation(self):
        result = decode_capture(fixture())
        self.assertEqual([m['native_type'] for m in result['operations'][0]['missions']], [5, 7, 9])
        self.assertTrue(result['repeated_reads_agree'])
        self.assertFalse(result['matching_ready'])
        self.assertFalse(result['atomic_snapshot'])

    def test_reject_changed_reads(self):
        c = fixture()
        c['after']['campaign_seed'] = '01000000'
        with self.assertRaisesRegex(ValueError, 'changed'):
            decode_capture(c)

    def test_session_boundary(self):
        c = fixture(); c['session_after'] = 'new-session'
        with self.assertRaisesRegex(ValueError, 'session'):
            decode_capture(c)

    def test_reject_inconsistent_structure(self):
        mutations = [('mission_count', 0, 331), ('operations', 0, 1),
                     ('operations', 85, 9, 1), ('operations', 86, 0, 1),
                     ('operations', 84, 2, 1), ('operations', 88, 4, 1),
                     ('missions', 40, 8), ('missions', 60, 9),
                     ('missions', 68, 2), ('missions', 56, 2),
                     ('missions', 48, 256), ('operation_cache', 0, 13),
                     ('operation_cache', 4, 1, 1), ('mission_cache', 0, 13),
                     ('screen', 0, 14), ('screen', 20, 6),
                     ('selection', 8, 110), ('selection', 8, 1)]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                c = fixture(); edit(c, *mutation)
                with self.assertRaises(ValueError):
                    decode_capture(c)

    def test_padding_is_not_count(self):
        c = fixture()
        edit(c, 'operations', 89, 0xeeeeee, 3)
        self.assertEqual(len(decode_capture(c)['operations'][0]['missions']), 3)

    def test_missing_truncated_and_invalid_hex(self):
        for bad in ('', 'not hex', '00'):
            c = fixture(); c['before']['missions'] = c['after']['missions'] = bad
            with self.assertRaises(ValueError):
                decode_capture(c)


def run_lua_cases(cases):
    """Also callable for optional local captures, which stay outside Git."""
    def lua(value):
        if isinstance(value, bytes):
            return '"' + ''.join('\\%03d' % byte for byte in value) + '"'
        if isinstance(value, str):
            return json.dumps(value)
        if isinstance(value, bool):
            return 'true' if value else 'false'
        if isinstance(value, int):
            return str(value)
        if isinstance(value, list):
            return '{' + ','.join(lua(v) for v in value) + '}'
        if isinstance(value, dict):
            return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in value.items()) + '}'
        raise TypeError(type(value))
    entries, expected = [], []
    for name, capture, accepted in cases:
        if accepted:
            decoded = decode_capture(capture)
            for op in decoded['operations']:
                expected.append('|'.join([name, str(op['row']), str(op['difficulty']),
                    ','.join(str(m['native_type']) for m in op['missions']),
                    ','.join(str(m['seed']) for m in op['missions'])]))
        converted = copy.deepcopy(capture)
        for side in ('before', 'after'):
            converted[side] = {k: bytes.fromhex(v) for k, v in capture[side].items()}
        entries.append(dict(name=name, capture=converted, accept=accepted))
    root = Path(__file__).resolve().parents[1]
    executable = os.environ.get('HD2_LUAJIT', str(root.parent / 'tools/src/LuaJIT/src/luajit.exe'))
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / 'fixtures.lua'
        path.write_text('return ' + lua(entries), encoding='ascii')
        result = subprocess.run([executable, str(root / 'tests/check_lua_snapshot.lua'),
                                 str(root / 'src/mods/ipodalexei/mission_reroller.lua'), str(path)],
                                check=True, capture_output=True, text=True)
    if result.stdout.splitlines() != expected:
        raise AssertionError('Lua and Python snapshot decoders disagree')


if __name__ == '__main__':
    unittest.main()
