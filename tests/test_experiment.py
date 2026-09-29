import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import build_experiment as build
lua=os.environ.get('HD2_LUAJIT',str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe'))
for test,src in [('test_search_session.lua','search_session.lua'),('test_filter_panel.lua','filter_panel.lua')]:
    subprocess.run([lua,str(ROOT/'tests'/test),str(ROOT/'src'/src)],check=True)
with tempfile.TemporaryDirectory() as folder:
    source=build.source()
    assert source.startswith(('-- HD2-Addon: '+build.MODULE+'\n').encode())
    for word in (b'WriteProcessMemory',b'VirtualProtect',b'VirtualAlloc',b'OpenProcess',b'CreateRemoteThread'):
        assert word not in source
    entry=Path(folder)/'experiment.lua';entry.write_bytes(source)
    subprocess.run([lua,str(ROOT/'tests/test_experiment_runtime.lua'),str(entry)],check=True)
    output=build.main(Path(folder)/'experiment.zip')
    with zipfile.ZipFile(output) as z:
        assert len(z.namelist())==4
        assert source in z.read(next(n for n in z.namelist() if n.endswith('.patch_0')))
print('assembled experiment tests: passed')
