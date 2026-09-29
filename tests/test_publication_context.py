"""Canonical protection and generator snapshot are distinct inputs."""
import sys
import unittest
import hashlib
import json
import struct
import tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from refresh_seed_candidate import context_records,publication_snapshot
from build_seed_test import candidate_from_fixture

class ContextTests(unittest.TestCase):
    def setUp(self):
        self.c=b'\x01\0\0\0'+bytes(range(92))
        self.s=self.c[:52]+b'\0'+self.c[53:]
        self.ref=dict(canonical=self.c.hex(),snapshot=self.s.hex())
    def test_distinct_records_are_preserved(self):
        self.assertEqual(context_records(self.ref),(self.c,self.s))
    def test_only_seed_is_rebased(self):
        fresh=b'\x02\0\0\0'+self.c[4:]
        self.assertEqual(publication_snapshot(fresh,fresh,self.ref),fresh[:4]+self.s[4:])
        self.assertEqual(publication_snapshot(fresh,fresh,None),fresh)
    def test_changed_active_record_is_rejected(self):
        changed=self.c[:-1]+b'\xff'
        with self.assertRaises(AssertionError):publication_snapshot(changed,changed,self.ref)
    def test_seed_disagreement_is_rejected(self):
        with self.assertRaises(AssertionError):context_records(dict(self.ref,snapshot=(b'\x02'+self.s[1:]).hex()))

    def test_manifest_protects_canonical_not_projected_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory);(folder/'pages').mkdir();(folder/'seed-33').mkdir()
            def save(path,value):(folder/path).write_text(json.dumps(value))
            save('meta.json',dict(board='0x10000000',planet=268))
            save('validation.json',dict(matched=True,seed=11))
            save('seed-33/validation.json',dict(matched=True,seed=33))
            save('search-result.json',dict(status='found',published=False,seed=33,
                operation=dict(row=28,difficulty=10,seed=123)))
            canonical=b'c'*92;snapshot=b's'*92
            save('pages/context.json',dict(address=hex(0x10000000+0x17a2c0),hex=snapshot.hex()))
            operations=bytearray(110*92);operations[28*92+52]=1;operations[28*92+32]=10
            struct.pack_into('<I',operations,28*92+12,123)
            missions=bytearray(0x6200);struct.pack_into('<I',missions,0x61f8,1)
            (folder/'seed-33/predicted-operations.bin').write_bytes(operations)
            (folder/'seed-33/predicted-missions.bin').write_bytes(missions)
            save('expected.json',dict(seed_hex='0b000000',canonical_active_hex=canonical.hex(),
                operations=operations.hex(),missions=missions.hex()))
            candidate=candidate_from_fixture(folder)
            self.assertEqual(candidate['active_hash'],hashlib.sha256(canonical).hexdigest())
            self.assertNotEqual(candidate['active_hash'],hashlib.sha256(snapshot).hexdigest())

if __name__=='__main__':unittest.main()
