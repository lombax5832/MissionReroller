"""Package the development core; native reroll and war-table UI are unavailable."""
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
LOADER = Path(os.environ.get('BINGUS_LOADER_ROOT', ROOT.parent / 'BingusSharedLoader'))
sys.path.insert(0, str(LOADER / 'scripts'))
from build_addon import build_addon

MODULE = 'mods/ipodalexei/mission_reroller'
NAME = 'Mission Reroller Development'
VERSION = '0.2.0'
GUID = 'dffa499a-e5de-48ef-9c5a-70f5fa96edc6'


def entry_path():
    return ROOT / 'src' / (MODULE + '.lua')


def inline_adapter():
    """experiment_adapter.lua for the older research builds, which append it
    inline so their runtimes share its locals: the default mode, and without
    the host table that build_identity_probe.source() returns from it."""
    text = (ROOT / 'src' / 'experiment_adapter.lua').read_text()
    body, marker, host = text.rpartition('\n-- Runtime host:')
    assert marker and text.count(marker) == 1 and host.count('\nreturn {') == 1, 'adapter host return moved'
    return 'local config={}\n' + body + '\n'


def release_path():
    return ROOT / 'releases' / f'{NAME.replace(" ", "-")}-v{VERSION}.zip'


def main(output=None):
    output = Path(output) if output else release_path()
    build_addon(MODULE, entry_path().read_bytes(), GUID, output,
                f'{NAME} - v{VERSION} (no native rerolls or UI)')
    print('Built development core: ' + str(output))
    return output


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)
