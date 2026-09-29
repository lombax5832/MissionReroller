"""Build the mouse dialog backed by the verified in-process seed search."""
from pathlib import Path
import sys
import build_identity_probe as probe

VERSION='0.20.0'
def main(output=None):
    output=Path(output) if output else probe.build.ROOT/'releases'/f'Mission-Reroller-v{VERSION}.zip'
    probe.build.build_addon(probe.build_combined.MODULE,probe.source(search=True,publish=True,dialog=True),
        probe.build_combined.GUID,output,f'Mission Reroller v{VERSION} (docked dialog; all mission types; city scope; fast seed search; mission, modifier and constellation filters)')
    print(output)
    return output
if __name__=='__main__':main(sys.argv[1] if len(sys.argv)>1 else None)
