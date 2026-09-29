import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import build_live_search as build
source=build.probe.source(search=True,publish=True)
for forbidden in (b'VirtualProtect',b'VirtualAlloc',b'OpenProcess',b'CreateRemoteThread',b'io.open',b'os.execute',b'io.popen',b'artifacts/',b'candidate_path'):
    assert forbidden not in source,forbidden
lua=os.environ['HD2_LUAJIT']
for test,module in [('test_seed_publication.lua','seed_publication.lua'),('test_ui_operation_selection.lua','ui_operation_selection.lua'),('test_ui_captured_states.lua','ui_operation_selection.lua')]:
    subprocess.run([lua,str(ROOT/'tests'/test),str(ROOT/'src'/module)],check=True)
with tempfile.TemporaryDirectory() as folder:
    entry=Path(folder)/'live.lua';entry.write_bytes(source)
    subprocess.run([lua,str(ROOT/'tests/test_live_search_runtime.lua'),str(entry)],check=True)
    # Only the dialog build accepts a lobby.
    subprocess.run([lua,str(ROOT/'tests/test_lobby_host.lua'),str(entry),'solo'],check=True)
    archive=build.main(Path(folder)/'live.zip')
    with zipfile.ZipFile(archive) as z:
        assert len(z.namelist())==4
        assert source in z.read(next(n for n in z.namelist() if n.endswith('.patch_0')))
print('Live search package passed; no companion or candidate file')
