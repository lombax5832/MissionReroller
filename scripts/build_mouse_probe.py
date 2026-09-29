import sys
from pathlib import Path
import build
MODULE='mods/ipodalexei/mission_reroller_mouse_probe'
GUID='958ad855-954c-4ac7-bd24-d979421b75df'
def source():
    root=build.ROOT/'src'
    prefix=(root/'mods/ipodalexei/mission_reroller_preflight.lua').read_text()
    prefix=prefix[:prefix.index('local original_update,original_shutdown=')]
    prefix=prefix.split('\n',1)[1].replace('MissionRerollerPreflight','MissionRerollerMouseProbe')
    prefix=prefix.replace('MRP_MEMORY','MRM_MEMORY').replace('read_only=true','no_reseed_calls=true')
    parts=['-- HD2-Addon: '+MODULE]
    for name,file in [('Search','search_session.lua'),('Panel','mouse_panel.lua'),
                      ('make_gate','window_mouse_gate.lua'),('make_router','modal_pointer.lua'),
                      ('window_signatures','window_signatures.lua')]:
        parts.append('local '+name+'=(function()\n'+(root/file).read_text()+'\nend)()')
    parts.extend([prefix,(root/'mouse_probe_runtime.lua').read_text()])
    return ('\n'.join(parts)+'\n').encode()
def main(output=None):
    output=Path(output) if output else build.ROOT/'releases/Mission-Reroller-Mouse-Test-v0.2.1.zip'
    build.build_addon(MODULE,source(),GUID,output,'Mission Reroller Mouse Test v0.2.1 (no reseeds)')
    print(output);return output
if __name__=='__main__':main(sys.argv[1] if len(sys.argv)>1 else None)
