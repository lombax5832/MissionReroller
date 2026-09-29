"""Combined mouse dialog, bounded native search, and operation-only selection."""
import sys
from pathlib import Path
import build
MODULE='mods/ipodalexei/mission_reroller_experiment'
GUID='1b378e53-cb80-44f0-a05c-909834932ea1'
VERSION='0.4.1'
def source():
    root=build.ROOT/'src'
    core=build.entry_path().read_text().replace('MissionReroller','MissionRerollerExperimentCore')
    parts=['-- HD2-Addon: '+MODULE,"if rawget(_G,'MissionRerollerExperiment') then return end",
           'local core=(function()\n'+core+'\nend)()']
    for name,file in [('Search','search_session.lua'),('Panel','mouse_panel.lua'),
                      ('make_gate','window_mouse_gate.lua'),('make_router','modal_pointer.lua'),
                      ('window_signatures','window_signatures.lua'),
                      ('selection_signatures','selection_signatures.lua'),('make_selection','match_selection.lua')]:
        parts.append('local '+name+'=(function()\n'+(root/file).read_text()+'\nend)()')
    parts.extend((root/file).read_text() for file in ['experiment_adapter.lua','combined_runtime.lua','combined_loop.lua'])
    return ('\n'.join(parts)+'\n').encode()
def main(output=None):
    output=Path(output) if output else build.ROOT/'releases'/f'Mission-Reroller-v{VERSION}.zip'
    build.build_addon(MODULE,source(),GUID,output,f'Mission Reroller v{VERSION} (supervised experiment)')
    print(output);return output
if __name__=='__main__':main(sys.argv[1] if len(sys.argv)>1 else None)
