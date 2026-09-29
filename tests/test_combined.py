import os,sys,tempfile,subprocess,zipfile
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import build_combined as build
lua=os.environ.get('HD2_LUAJIT',str(ROOT.parent/'tools/src/LuaJIT/src/luajit.exe'))
for test,src in [('test_match_selection.lua','match_selection.lua'),('test_search_session.lua','search_session.lua'),
                 ('test_mouse_panel.lua','mouse_panel.lua'),('test_window_mouse_gate.lua','window_mouse_gate.lua'),
                 ('test_modal_pointer.lua','modal_pointer.lua')]:
    subprocess.run([lua,str(ROOT/'tests'/test),str(ROOT/'src'/src)],check=True)
with tempfile.TemporaryDirectory() as folder:
    s=build.source();entry=Path(folder)/'combined.lua';entry.write_bytes(s)
    assert b'WriteProcessMemory' not in s and b'VirtualProtect' not in s
    subprocess.run([lua,str(ROOT/'tests/test_combined_runtime.lua'),str(entry)],check=True)
    output=build.main(Path(folder)/'combined.zip')
    with zipfile.ZipFile(output) as z:
        assert len(z.namelist())==4
        assert s in z.read(next(n for n in z.namelist() if n.endswith('.patch_0')))
print('combined package and control flow: passed')
