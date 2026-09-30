"""Package the Mission Reroller release: the docked dialog, seed search and publication."""
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import build_core
import build_combined
import build_identity_probe as probe

# The module and GUID are those of every published Mission Reroller ZIP since
# v0.4.0; keep them so mod managers treat a new version as an update.
MODULE = build_combined.MODULE
GUID = build_combined.GUID
NAME = 'Mission Reroller'
VERSION = '0.20.2'
SUMMARY = ('docked dialog; alone or hosting a lobby; all mission types; city scope; '
           'fast seed search; mission, modifier and constellation filters')
ROOT = build_core.ROOT


def source():
    """The single plaintext entry the loader runs, assembled from src/."""
    return probe.source(search=True, publish=True, dialog=True, version=VERSION)


def release_path():
    return ROOT / 'releases' / f'{NAME.replace(" ", "-")}-v{VERSION}.zip'


def main(output=None):
    output = Path(output) if output else release_path()
    build_core.build_addon(MODULE, source(), GUID, output, f'{NAME} v{VERSION} ({SUMMARY})')
    print(output)
    return output


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)
