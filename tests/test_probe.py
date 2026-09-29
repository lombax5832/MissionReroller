"""Validate one-shot control flow with a substituted native invocation."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build_probe as build

source = build.SOURCE.read_bytes()
assert source.startswith(('-- HD2-Addon: ' + build.MODULE + '\n').encode())
for forbidden in (b'WriteProcessMemory', b'VirtualProtect', b'VirtualAlloc',
                  b'OpenProcess', b'CreateRemoteThread', b'os.execute', b'io.popen'):
    assert forbidden not in source, forbidden
assert source.count(b"ffi.cast('void (*)(void *, uint8_t, uintptr_t, uint8_t)'") == 1
with tempfile.TemporaryDirectory() as tmp:
    output = build.main(Path(tmp) / 'probe.zip')
    with zipfile.ZipFile(output) as z:
        assert len(z.namelist()) == 4
        archive = z.read(next(n for n in z.namelist() if n.endswith('.patch_0')))
        assert source in archive
lua = os.environ.get('HD2_LUAJIT', str(ROOT.parent / 'tools/src/LuaJIT/src/luajit.exe'))
for case in ('success', 'timeout', 'active_change', 'queue', 'queue_clears', 'page'):
    subprocess.run([lua, str(ROOT / 'tests/test_probe.lua'), str(build.SOURCE), case], check=True)
print('one-shot package and control-flow tests: passed')
