"""Every build carries the adapter and runtime files unchanged, as factories of
explicit inputs; the build's mode is data, never a rewrite of their text."""
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build
import build_identity_probe as probe

SRC = ROOT / 'src'
RUNTIME = 'host,lib,hooks'


def wrapped(file, params):
    return ('(function(' + params + ')\n' + (SRC / file).read_text() + '\nend)(').encode()


def main():
    variants = {
        'probe': ({}, ['identity_probe_runtime.lua']),
        'search': ({'search': True}, ['prediction_search_runtime.lua', 'identity_probe_runtime.lua']),
        'live': ({'search': True, 'publish': True},
                 ['live_publication_runtime.lua', 'prediction_search_runtime.lua', 'identity_probe_runtime.lua']),
        'release': ({'search': True, 'publish': True, 'dialog': True, 'version': build.VERSION},
                    ['live_publication_runtime.lua', 'constellation_runtime.lua', 'prediction_search_runtime.lua',
                     'prediction_dialog_runtime.lua', 'identity_probe_runtime.lua']),
    }
    for name, (options, runtimes) in variants.items():
        source = probe.source(**options)
        assert source == probe.source(**options), name + ' build is not reproducible'
        assert wrapped('experiment_adapter.lua', 'core,config') in source, name + ': adapter text changed'
        for file in runtimes:
            assert source.count(wrapped(file, RUNTIME)) == 1, name + ': ' + file + ' text changed'
        for file in {'live_publication_runtime.lua', 'constellation_runtime.lua', 'prediction_search_runtime.lua',
                     'prediction_dialog_runtime.lua'} - set(runtimes):
            assert (SRC / file).read_text().encode() not in source, name + ' carries ' + file
        # No chunk-wide forward declarations for the runtimes to assign.
        assert b'local on_prediction_ready,advance_prediction_search,on_search_match' not in source
    release = build.source()
    assert release == probe.source(**variants['release'][0])
    # The earlier builds' names for the mode are gone from the release.
    for stale in (b'0.8.0', b'independent seed prediction', b'Ctrl+Shift+F9', b'read_only=true',
                  b'no refresh or selection'):
        assert stale not in release, stale
    assert ("banner='Mission Reroller " + build.VERSION + " docked dialog'").encode() in release
    assert b"shortcut='F7 on the galactic map'" in release
    lua = os.environ['HD2_LUAJIT']
    subprocess.run([lua, str(ROOT / 'tests/test_runtime_factories.lua'), str(SRC)], check=True)
    print('Runtime host: unchanged runtime files in every build, no leftover mode text in the release, factories passed')


if __name__ == '__main__':
    main()
