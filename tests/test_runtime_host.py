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
                    ['live_publication_runtime.lua', 'constellation_runtime.lua', 'side_objective_runtime.lua',
                     'prediction_search_runtime.lua', 'prediction_dialog_runtime.lua', 'identity_probe_runtime.lua']),
    }
    for name, (options, runtimes) in variants.items():
        source = probe.source(**options)
        assert source == probe.source(**options), name + ' build is not reproducible'
        assert wrapped('experiment_adapter.lua', probe.ADAPTER) in source, name + ': adapter text changed'
        # Every module receives the offsets' numbers and the board's records as its chunk arguments.
        assert b'\nlocal make_map_screen=(function(...)\n' + (SRC / 'map_screen.lua').read_text().encode() + b'\nend)(O,Board)' in source, name
        # Only the builds that publish carry the guarded write.
        writes = 'publish' in options
        assert (b'host.write=make_guarded_write(host)' in source) == writes, name + ': guarded write'
        assert ((SRC / 'guarded_write.lua').read_text().encode() in source) == writes, name + ': guarded write text'
        for file in runtimes:
            assert source.count(wrapped(file, RUNTIME)) == 1, name + ': ' + file + ' text changed'
        for file in {'live_publication_runtime.lua', 'constellation_runtime.lua', 'side_objective_runtime.lua',
                     'prediction_search_runtime.lua', 'prediction_dialog_runtime.lua'} - set(runtimes):
            assert (SRC / file).read_text().encode() not in source, name + ' carries ' + file
        # No chunk-wide forward declarations for the runtimes to assign.
        assert b'local on_prediction_ready,advance_prediction_search,on_search_match' not in source
    release = build.source()
    assert release == probe.source(**variants['release'][0], log_level=build.LOG_LEVEL)
    # A tagged release keeps info and above; development and research builds keep debug too.
    assert build.LOG_LEVEL == ('info' if build.TAGGED else 'debug')
    assert ("log_level='" + build.LOG_LEVEL + "'").encode() in release
    assert b"log_level='info'" in build.source(log_level='info')
    assert b"log_level='debug'" in probe.source(search=True)
    # The earlier builds' names for the mode are gone from the release.
    for stale in (b'0.8.0', b'independent seed prediction', b'Ctrl+Shift+F9', b'read_only=true',
                  b'no refresh or selection'):
        assert stale not in release, stale
    assert ("banner='Mission Reroller " + build.VERSION + " docked dialog'").encode() in release
    assert b"shortcut='F7 on the galactic map'" in release
    # The identity runtime cools the worker VMs on an error and joins them at shutdown.
    for hook in (b'cool_search_workers=search.cool_search_workers', b'shutdown_search_workers=search.shutdown_search_workers'):
        assert hook in release, hook
    lua = os.environ['HD2_LUAJIT']
    subprocess.run([lua, str(ROOT / 'tests/test_runtime_factories.lua'), str(SRC)], check=True)
    # The host's map screen and guarded write (map_screen.lua, guarded_write.lua).
    subprocess.run([lua, str(ROOT / 'tests/test_map_screen.lua'), str(SRC)], check=True)
    print('Runtime host: unchanged runtime files in every build, no leftover mode text in the release, factories, map screen and guarded write passed')


if __name__ == '__main__':
    main()
