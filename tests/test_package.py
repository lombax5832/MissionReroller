"""Validate discovery and archive boundaries, then exercise Lua behavior."""
from pathlib import Path
import json
import os
import struct
import subprocess
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build
from archive import ARCHIVE, resource_hash


def test_package():
    source = build.entry_path().read_bytes()
    marker = ('-- HD2-Addon: ' + build.MODULE + '\n').encode()
    assert source.startswith(marker)
    assert b'\0' not in source and b'\x1b' not in source
    assert b"rawget(_G, 'MissionReroller')" in source
    # This development package must remain unable to perform native actions.
    for forbidden in (b'VirtualAlloc', b'VirtualProtect', b'WriteProcessMemory',
                      b'ReadProcessMemory', b'CreateRemoteThread', b'OpenProcess',
                      b'LoadLibrary', b"require('ffi')", b'os.execute', b'io.popen'):
        assert forbidden not in source, forbidden
    with tempfile.TemporaryDirectory() as folder:
        output = build.main(Path(folder) / 'development.zip')
        with zipfile.ZipFile(output) as package:
            assert sorted(package.namelist()) == sorted([
                'manifest.json', 'Addon/' + ARCHIVE,
                'Addon/' + ARCHIVE + '.stream', 'Addon/' + ARCHIVE + '.gpu_resources'])
            manifest = json.loads(package.read('manifest.json'))
            assert manifest['Guid'] == build.GUID
            assert manifest['Options'][0]['Include'] == ['Addon']
            archive = package.read('Addon/' + ARCHIVE)
        assert struct.unpack_from('<I', archive)[0] == 0xF0000011
        assert struct.pack('<Q', resource_hash(build.MODULE)) in archive
        offset = archive.index(marker)
        assert struct.unpack_from('<II', archive, offset - 8) == (len(source), 2)
        assert archive[offset:offset + len(source)] == source


def test_lua():
    lua = os.environ.get('HD2_LUAJIT', str(ROOT.parent / 'tools/src/LuaJIT/src/luajit.exe'))
    subprocess.run([lua, str(ROOT / 'tests/test_reroller.lua'), str(build.entry_path())], check=True)


def test_capture_reader():
    subprocess.run([sys.executable, '-B', str(ROOT / 'tests/test_capture.py')], check=True)


if __name__ == '__main__':
    test_package()
    test_lua()
    test_capture_reader()
    print('test_package: passed')
