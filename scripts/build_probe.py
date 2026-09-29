"""Package the manually triggered single-call experiment."""
import sys
from pathlib import Path
import build

MODULE = 'mods/ipodalexei/mission_reroller_probe'
GUID = 'db14ae46-a60b-41aa-b939-f550d4bb6fa8'
VERSION = '0.1.1'
SOURCE = build.ROOT / 'src' / (MODULE + '.lua')

def main(output=None):
    output = Path(output) if output else build.ROOT / 'releases' / f'Mission-Reroller-One-Shot-v{VERSION}.zip'
    build.build_addon(MODULE, SOURCE.read_bytes(), GUID, output,
                      f'Mission Reroller One-Shot v{VERSION} (manual native test)')
    print(output)
    return output

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)
