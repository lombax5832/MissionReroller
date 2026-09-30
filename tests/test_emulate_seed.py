"""Synthetic emulator checks. No live reads or native game execution."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('emulator',Path(__file__).resolve().parents[1]/'scripts/emulate_seed.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
BASE=0x40000000
O=module.O  # src/offsets.lua, as the emulator reads it


class ReplayTests(unittest.TestCase):
    def fixture(self,folder,code=b'\xc3'):
        (folder/'pages').mkdir()
        (folder/'meta.json').write_text(json.dumps({'session':'test','game':hex(BASE),'board':hex(0x70000000),'planet':268}))
        # The page of the board's operations, and the operation cache after them.
        address=(0x70000000+O.field('board','operations'))&~4095
        (folder/'pages'/f'{address:x}.json').write_text(json.dumps({'session':'test','address':hex(address),'hex':bytes(0x3000).hex()}))
        for rva,body in ((O.rva['reseed_board'],code),(O.research['generate_missions'],b'\xc3')):
            data=bytearray(4096);offset=rva%4096;data[offset:offset+len(body)]=body
            address=(BASE+rva)&~4095
            (folder/'pages'/f'{address:x}.json').write_text(json.dumps({'session':'test','address':hex(address),'hex':data.hex()}))

    def test_synthetic_returns(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);self.fixture(folder)
            self.assertEqual(module.replay(folder)['status'],'complete')

    def test_write_only_changes_emulated_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);target=BASE+0x2200000
            self.fixture(folder,b'\x48\xb8'+struct.pack('<Q',target)+b'\xc7\x00\x07\x00\x00\x00\xc3')
            file=folder/'pages'/f'{target:x}.json'
            original=json.dumps({'session':'test','address':hex(target),'hex':bytes(4096).hex()})
            file.write_text(original)
            result=module.replay(folder)
            self.assertEqual(result['status'],'complete')
            self.assertIn(hex(target),result['emulated_capture_page_writes'])
            self.assertEqual(file.read_text(),original)

    def test_missing_data_is_not_fabricated(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);target=BASE+0x2200000
            self.fixture(folder,b'\x48\xb8'+struct.pack('<Q',target)+b'\x8b\x00\xc3')
            result=module.replay(folder)
            self.assertEqual(result['status'],'missing')
            self.assertEqual(result['missing'][0]['address'],hex(target))

    def test_system_call_stops(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);self.fixture(folder,b'\x0f\x05\xc3')
            result=module.replay(folder)
            self.assertEqual(result['status'],'stopped')
            self.assertIn('System call or interrupt',result['violations'])


if __name__=='__main__':unittest.main()
