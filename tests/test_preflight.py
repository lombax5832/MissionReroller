"""Check the independently packaged read-only diagnostic and callback failure path."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build_preflight as build

source = build.SOURCE.read_bytes()
assert source.startswith(('-- HD2-Addon: ' + build.MODULE + '\n').encode())
for forbidden in (b'WriteProcessMemory', b'VirtualProtect', b'VirtualAlloc',
                  b'OpenProcess', b'CreateRemoteThread', b'GetAsyncKeyState',
                  b'void (*', b'void(*)', b'os.execute', b'io.popen'):
    assert forbidden not in source, forbidden
with tempfile.TemporaryDirectory() as tmp:
    output = build.main(Path(tmp) / 'preflight.zip')
    with zipfile.ZipFile(output) as z:
        assert len(z.namelist()) == 4
        archive = z.read(next(n for n in z.namelist() if n.endswith('.patch_0')))
        assert source in archive
lua = os.environ.get('HD2_LUAJIT', str(ROOT.parent / 'tools/src/LuaJIT/src/luajit.exe'))
subprocess.run([lua, str(ROOT / 'tests/test_preflight.lua'), str(build.SOURCE)], check=True)
subprocess.run([lua, str(ROOT / 'tests/test_preflight_snapshot.lua'), str(build.SOURCE)], check=True)
print('read-only preflight package: passed')
