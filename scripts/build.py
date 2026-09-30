"""Package the Mission Reroller release: the docked dialog, seed search and publication.

The version is the RELEASE_TAG environment variable (v1.2.3) when the release
workflow builds a tag, and DEFAULT_VERSION otherwise.
"""
import json
import os
from pathlib import Path
import re
import sys
import zipfile

sys.dont_write_bytecode = True
import build_core
import build_identity_probe as probe

MODULE = build_core.RELEASE_MODULE
GUID = build_core.RELEASE_GUID
NAME = 'Mission Reroller'
DEFAULT_VERSION = '0.25.0'
# What mod managers show for the mod and its one option.
DESCRIPTION = ('Rerolls the operations on a planet\'s war table until one has the missions, modifiers '
               'and enemy forces you choose. Press F7 on the galactic map to open the panel '
               '(rebindable on the MODS tab with Mod Bindings Menu).')
REQUIREMENT = ('Requires Bingus Shared Loader v16 or newer: enable both, keep the loader last in the '
               'load order, then deploy.')
ROOT = build_core.ROOT


def release_version(tag):
    """The version a tag names (v1.2.3 or 1.2.3), or DEFAULT_VERSION without a tag."""
    if not tag:
        return DEFAULT_VERSION
    match = re.fullmatch(r'v?(\d+\.\d+\.\d+)', tag)
    if not match:
        raise SystemExit(f'RELEASE_TAG {tag!r} is not a version tag like v1.2.3')
    return match.group(1)


VERSION = release_version(os.environ.get('RELEASE_TAG'))


def source():
    """The single plaintext entry the loader runs, assembled from src/."""
    return probe.source(search=True, publish=True, dialog=True, version=VERSION)


def manifest():
    """The manifest.json Arsenal and HD2MM read."""
    title = f'{NAME} v{VERSION}'
    description = DESCRIPTION + ' ' + REQUIREMENT
    return {'Version': 1, 'Guid': GUID, 'Name': title, 'Description': description,
            'Options': [{'Name': NAME, 'Description': description, 'Include': ['Addon']}]}


def replace_manifest(output):
    """Swap the loader's generic manifest.json for this mod's, keeping every other entry as built."""
    with zipfile.ZipFile(output) as package:
        entries = [(info, package.read(info)) for info in package.infolist()]
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as package:
        for info, content in entries:
            if info.filename == 'manifest.json':
                content = (json.dumps(manifest(), indent=2) + '\n').encode()
            package.writestr(info, content)


def release_path():
    return ROOT / 'releases' / f'{NAME.replace(" ", "-")}-v{VERSION}.zip'


def main(output=None):
    output = Path(output) if output else release_path()
    build_core.build_addon(MODULE, source(), GUID, output, NAME)
    replace_manifest(output)
    print(output)
    return output


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)
