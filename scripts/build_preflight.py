"""Package the read-only in-game preflight, separately from the development core."""
import sys
from pathlib import Path
import build

MODULE = 'mods/ipodalexei/mission_reroller_preflight'
GUID = '55866ece-5740-4f1b-bbcb-ae8ee168f58a'
VERSION = '0.1.1'
SOURCE = build.ROOT / 'src' / (MODULE + '.lua')


def main(output=None):
    output = Path(output) if output else build.ROOT / 'releases' / f'Mission-Reroller-Preflight-v{VERSION}.zip'
    build.build_addon(MODULE, SOURCE.read_bytes(), GUID, output,
                      f'Mission Reroller Preflight v{VERSION} (read only)')
    print(output)
    return output


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)
