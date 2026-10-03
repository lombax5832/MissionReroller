"""The bundled Know Your Constellation roster: the vendored files are the
upstream v4.0 ones byte for byte, and tests/test_bundled_roster.lua passes."""
from pathlib import Path
import hashlib
import os
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'src/vendor/know_your_constellation'
# Git blob IDs at CowboyBingus/KnowYourConstellation 662609f (v4.0), so
# `git ls-tree <commit> src/roster.lua src/roster_data.lua` there shows a match.
UPSTREAM = {'roster.lua': 'ed9dd017d814864599dfdcfb2296eae92d710137',
            'roster_data.lua': 'ed10e911d82f52a1c48b022c36f5086b6a751d07'}


def blob_id(data):
    return hashlib.sha1(b'blob %d\0' % len(data) + data).hexdigest()


def main():
    assert sorted(p.name for p in VENDOR.glob('*.lua')) == sorted(UPSTREAM), 'vendored files'
    for name, expected in UPSTREAM.items():
        assert blob_id((VENDOR / name).read_bytes()) == expected, name + ' differs from upstream v4.0'
    lua = os.environ['HD2_LUAJIT']
    subprocess.run([lua, str(ROOT / 'tests/test_bundled_roster.lua'), str(ROOT / 'src')], check=True)


if __name__ == '__main__':
    main()
