"""Check the read-only cooperative search package and lifecycle."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import build_search_probe as build

def main():
    source=build.probe.source(search=True)
    for forbidden in (b'WriteProcessMemory',b'VirtualProtect',b'VirtualAlloc',b'OpenProcess',b'CreateRemoteThread',
                      b'os.execute',b'io.popen',b'io.open',b'artifacts/',b'emulate_seed',b"ffi.cast('void (*)"):
        assert forbidden not in source,forbidden
    luajit=os.environ['HD2_LUAJIT']
    subprocess.run([luajit,str(ROOT/'tests/test_prediction_search_job.lua'),str(ROOT/'src')],check=True)
    with tempfile.TemporaryDirectory() as folder:
        entry=Path(folder)/'probe.lua';entry.write_bytes(source)
        subprocess.run([luajit,str(ROOT/'tests/test_search_probe_runtime.lua'),str(entry)],check=True)
        output=build.main(Path(folder)/'probe.zip')
        with zipfile.ZipFile(output) as package:
            assert len(package.namelist())==4
            assert source in package.read(next(n for n in package.namelist() if n.endswith('.patch_0')))
    print('Cooperative Lua search package passed; no publication APIs or companion dependency')

if __name__=='__main__':main()
