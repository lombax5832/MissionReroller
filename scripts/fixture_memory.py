"""Offline, strict read-only access to ignored capture pages (no process access)."""
import json
import struct


class FixtureMemory:
    def __init__(self, folder):
        self.meta = json.loads((folder / 'meta.json').read_text())
        self.pages = {}
        for path in (folder / 'pages').glob('*.json'):
            record = json.loads(path.read_text())
            assert record['session'] == self.meta['session'], 'Mixed sessions'
            start = int(record['address'], 16)
            data = bytes.fromhex(record['hex'])
            assert start % 4096 == 0 and len(data) % 4096 == 0
            for offset in range(0, len(data), 4096):
                address = start + offset
                assert address not in self.pages, 'Overlapping pages'
                self.pages[address] = data[offset:offset + 4096]

    def read(self, address, size):
        output = bytearray()
        while size:
            page, offset = address & ~4095, address & 4095
            count = min(size, 4096 - offset)
            if page not in self.pages:
                raise ValueError(f'Missing captured page {page:#x}')
            output.extend(self.pages[page][offset:offset + count])
            address += count
            size -= count
        return bytes(output)

    def u32(self, address):
        return struct.unpack('<I', self.read(address, 4))[0]
