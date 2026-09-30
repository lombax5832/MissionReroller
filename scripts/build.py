"""Package the Mission Reroller release: the docked dialog, seed search and publication."""
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import build_core
import build_identity_probe as probe

MODULE = build_core.RELEASE_MODULE
GUID = build_core.RELEASE_GUID
NAME = 'Mission Reroller'
VERSION = '0.25.0'
SUMMARY = ('docked dialog; F7 or rebindable on the MODS tab; loaded mods listed in the log; key hint beside BACK; alone or hosting a lobby; all mission types; '
           'city scope; fast seed search; mission, modifier and constellation filters')
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
