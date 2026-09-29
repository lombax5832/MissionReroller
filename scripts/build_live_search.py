"""Build the supervised Lua search, publication and selection checkpoint."""
from pathlib import Path
import sys
import build_identity_probe as probe

VERSION='0.10.1'
def main(output=None):
    output=Path(output) if output else probe.build.ROOT/'releases'/f'Mission-Reroller-Live-Search-v{VERSION}.zip'
    source=probe.source(search=True,publish=True)
    probe.build.build_addon(probe.build_combined.MODULE,source,probe.build_combined.GUID,output,
                           f'Mission Reroller v{VERSION} (supervised Lua search and selection)')
    print(output)
    return output
if __name__=='__main__':main(sys.argv[1] if len(sys.argv)>1 else None)
