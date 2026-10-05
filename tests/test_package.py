"""Validate the release package: declaration, forbidden APIs, ZIP layout, then the dialog tests."""
from pathlib import Path
import json
import struct
import subprocess
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build
from archive import ARCHIVE, resource_hash


def test_package():
    source = build.source()
    marker = ('-- HD2-Addon: ' + build.MODULE + '\n').encode()
    assert source.startswith(marker)
    assert b'\0' not in source and b'\x1b' not in source
    assert b"rawget(_G,'MissionRerollerExperiment')" in source
    assert ('Mission Reroller ' + build.VERSION + ' docked dialog').encode() in source
    # The release reads and writes the game's own process through the loader's
    # FFI, but never allocates, reprotects, opens processes or runs programs.
    for forbidden in (b'VirtualAlloc', b'VirtualProtect', b'OpenProcess', b'CreateRemoteThread',
                      b'LoadLibrary', b'io.open', b'os.execute', b'io.popen', b'candidate_path'):
        assert forbidden not in source, forbidden
    with tempfile.TemporaryDirectory() as folder:
        output = build.main(Path(folder) / 'release.zip')
        with zipfile.ZipFile(output) as package:
            assert sorted(package.namelist()) == sorted([
                'manifest.json', 'Addon/' + ARCHIVE,
                'Addon/' + ARCHIVE + '.stream', 'Addon/' + ARCHIVE + '.gpu_resources'])
            manifest = json.loads(package.read('manifest.json'))
            assert manifest['Guid'] == build.GUID
            assert manifest['Name'] == build.NAME + ' v' + build.VERSION
            assert 'Bingus Shared Loader v16' in manifest['Description']
            assert manifest['Options'] == [{'Name': build.NAME, 'Description': manifest['Description'],
                                            'Include': ['Addon']}]
            archive = package.read('Addon/' + ARCHIVE)
        assert struct.unpack_from('<I', archive)[0] == 0xF0000011
        assert struct.pack('<Q', resource_hash(build.MODULE)) in archive
        offset = archive.index(marker)
        assert struct.unpack_from('<II', archive, offset - 8) == (len(source), 2)
        assert archive[offset:offset + len(source)] == source


def test_release_version():
    assert build.release_version(None) == build.release_version('') == build.DEFAULT_VERSION
    assert build.release_version('v1.22.3') == build.release_version('1.22.3') == '1.22.3'
    for tag in ('main', 'v1.2', 'v1.2.3-rc1'):
        try:
            build.release_version(tag)
        except SystemExit:
            continue
        raise AssertionError(tag)


def test_build_identity():
    # A tag publishes under the GUID every released ZIP has carried; a local
    # build shows up as a separate mod in the mod manager.
    assert build.GUID == (build.build_core.RELEASE_GUID if build.TAGGED else build.DEVELOPMENT_GUID)
    assert build.NAME == (build.RELEASE_NAME if build.TAGGED else build.DEVELOPMENT_NAME)
    assert build.DEVELOPMENT_GUID not in (build.build_core.RELEASE_GUID, build.build_core.GUID)
    assert build.DEVELOPMENT_NAME != build.RELEASE_NAME


def test_dialog():
    subprocess.run([sys.executable, '-B', str(ROOT / 'tests/test_dialog.py')], check=True)


def test_runtime_host():
    subprocess.run([sys.executable, '-B', str(ROOT / 'tests/test_runtime_host.py')], check=True)


def test_offsets():
    subprocess.run([sys.executable, '-B', str(ROOT / 'tests/test_offsets.py')], check=True)


def test_bundled_roster():
    subprocess.run([sys.executable, '-B', str(ROOT / 'tests/test_bundled_roster.py')], check=True)


def test_release_notes():
    subprocess.run([sys.executable, '-B', str(ROOT / 'tests/test_release_notes.py')], check=True)


def test_seed_solver_workers():
    subprocess.run([sys.executable, '-B', str(ROOT / 'tests/test_seed_solver_workers.py')], check=True)


if __name__ == '__main__':
    test_package()
    test_release_version()
    test_offsets()
    test_release_notes()
    test_runtime_host()
    test_bundled_roster()
    test_seed_solver_workers()
    test_dialog()
    print('test_package: passed')
