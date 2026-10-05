import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import build
source=build.source()
for forbidden in (b'VirtualProtect',b'VirtualAlloc',b'OpenProcess',b'CreateRemoteThread',b'io.open',b'os.execute',b'io.popen',b'candidate_path'):
    assert forbidden not in source,forbidden
# The dialog build draws the docked panel; older builds keep the centred one.
assert b'Docked briefing panel' in source and b'CLEAR SELECTION' not in source
lua=os.environ['HD2_LUAJIT']
subprocess.run([lua,str(ROOT/'tests/test_reroll_session.lua'),str(ROOT/'src/reroll_session.lua')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_search_session.lua'),str(ROOT/'src/search_session.lua')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_filter_catalogue.lua'),str(ROOT/'src')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_filter_request.lua'),str(ROOT/'src')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_filter_rules.lua'),str(ROOT/'src')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_side_objective_prediction.lua'),str(ROOT/'src')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_side_objective_runtime.lua'),str(ROOT/'src')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_day_night.lua'),str(ROOT/'src')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_mission_compatibility.lua'),str(ROOT/'src')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_template_environments.lua'),str(ROOT/'src')],check=True)
subprocess.run([lua,str(ROOT/'tests/test_constellation_inputs.lua'),str(ROOT/'src')],check=True)
# The saved campaign capture exists only in the main checkout's artifacts.
oracle=ROOT/'artifacts/level-capture-oracle.lua'
subprocess.run([lua,str(ROOT/'tests/test_planet_model.lua'),str(ROOT/'src')]+([str(oracle)] if oracle.exists() else []),check=True)
# Recorded native seeds live in the sibling reference checkout; they are read, never copied.
subprocess.run([lua,str(ROOT/'tests/test_constellation_prediction.lua'),str(ROOT/'src'),
    str(ROOT.parent/'KnowYourConstellation/tests/fixtures/seeds.lua')],check=True)
with tempfile.TemporaryDirectory() as folder:
    entry=Path(folder)/'dialog.lua';entry.write_bytes(source)
    subprocess.run([lua,str(ROOT/'tests/test_prediction_dialog.lua'),str(entry),str(ROOT/'src')],check=True)
    # A planet under an invasion, captured in game (main checkout only).
    invasion=ROOT/'artifacts/invasion-live-173/capture.lua'
    if invasion.exists():
        subprocess.run([lua,str(ROOT/'tests/check_viewed_planet.lua'),str(invasion),str(ROOT/'src'),str(entry),
            str(Path(folder)/'missing.txt'),'saved'],check=True)
    subprocess.run([lua,str(ROOT/'tests/test_reroll_handshake.lua'),str(entry),str(ROOT/'src')],check=True)
    subprocess.run([lua,str(ROOT/'tests/test_ffi_conflicts.lua'),str(entry)],check=True)
    subprocess.run([lua,str(ROOT/'tests/test_mod_inventory_entry.lua'),str(entry),build.VERSION],check=True)
    subprocess.run([lua,str(ROOT/'tests/test_constellation_runtime.lua'),str(entry)],check=True)
    subprocess.run([lua,str(ROOT/'tests/test_lobby_host.lua'),str(entry),'lobby'],check=True)
    archive=build.main(Path(folder)/'dialog.zip')
    with zipfile.ZipFile(archive) as z:
        assert len(z.namelist())==4
        assert source in z.read(next(n for n in z.namelist() if n.endswith('.patch_0')))
for test,module in [('test_docked_panel.lua','docked_panel.lua'),('test_keybind_hint.lua','keybind_hint.lua'),('test_mod_inventory.lua','mod_inventory.lua'),('test_mod_binding.lua','mod_binding.lua'),('test_escape_gate.lua','escape_gate.lua'),('test_modal_pointer.lua','modal_pointer.lua'),('test_window_mouse_gate.lua','window_mouse_gate.lua'),('test_window_cursor.lua','window_cursor.lua'),('test_external_edits.lua','external_edits.lua'),('test_solver_estimate.lua','solver_estimate.lua'),('test_seed_solver_plan.lua','seed_solver_search.lua')]:
    subprocess.run([lua,str(ROOT/'tests'/test),str(ROOT/'src'/module)],check=True)
print('Dialog package, docked panel, native cursor gate and click routing passed')
