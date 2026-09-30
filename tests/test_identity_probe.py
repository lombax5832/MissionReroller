"""Verify the diagnostic release cannot publish or execute native generators."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
import build_identity_probe as build


def main():
    source = build.source()
    assert source.startswith(('-- HD2-Addon: '+build.build.RELEASE_MODULE+'\n').encode())
    for forbidden in (b'WriteProcessMemory', b'VirtualProtect', b'VirtualAlloc', b'OpenProcess',
                      b'CreateRemoteThread', b'os.execute', b'io.popen', b'ffi.cast(\'void (*)',
                      b'artifacts/', b'emulate_seed', b'candidate_path', b'io.open'):
        assert forbidden not in source, forbidden
    luajit = os.environ.get('HD2_LUAJIT', str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe'))
    subprocess.run([luajit,str(ROOT/'tests/test_special_inputs.lua'),str(ROOT/'src')],check=True)
    subprocess.run([luajit,str(ROOT/'tests/test_level_inputs.lua'),str(ROOT/'src')],check=True)
    subprocess.run([luajit,str(ROOT/'tests/test_seed_search.lua'),str(ROOT/'src')],check=True)
    with tempfile.TemporaryDirectory() as directory:
        entry = Path(directory)/'probe.lua'
        entry.write_bytes(source)
        subprocess.run([luajit, str(ROOT/'tests/test_identity_probe.lua'), str(entry),
                        str(ROOT/'src/identity_probe.lua')], check=True)
        output = build.main(Path(directory)/'probe.zip')
        with zipfile.ZipFile(output) as package:
            assert len(package.namelist()) == 4
            assert source in package.read(next(name for name in package.namelist() if name.endswith('.patch_0')))
            assert json.loads(package.read('manifest.json'))['Guid'] == build.build.RELEASE_GUID
    print('Read-only Lua probe package passed; no fixture or companion dependency')


if __name__ == '__main__':
    main()
