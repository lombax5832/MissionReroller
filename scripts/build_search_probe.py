"""Package the cooperative all-Lua search without any publication code."""
from pathlib import Path
import sys
import build_identity_probe as probe

VERSION='0.9.1'

def main(output=None):
    output=Path(output) if output else probe.build.ROOT/'releases'/f'Mission-Reroller-Lua-Search-Probe-v{VERSION}.zip'
    probe.build.build_addon(probe.build_combined.MODULE,probe.source(search=True),probe.build_combined.GUID,output,
                           f'Mission Reroller v{VERSION} (read-only Lua search)')
    print(output)
    return output

if __name__=='__main__':main(sys.argv[1] if len(sys.argv)>1 else None)
