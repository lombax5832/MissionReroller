"""scripts/check_offsets.py against real dumps: the update rehearsal.

    python -B tests/test_check_offsets.py

Needs the workspace dumps (../dumps/build-<build> and the older build at
../dumps/ itself), Capstone (workspace tools/seed-emulator-deps) and numpy,
so it is not part of the release gate; it prints "skipped" without them.
It checks that:

1. src/offsets.lua matches the dump of its own build.
2. Carrying the table to the older build with --reference --write leaves
   every anchored entry matching that build, with the values the older
   build is known to use.
3. A changed struct displacement inside a generator function is reported
   as changed code with the number that changed, and a moved field behind
   an instruction anchor gets its new value.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import offsets

WORKSPACE = next((p for p in ROOT.parents if (p / 'dumps').is_dir()), None)
IMAGES = ('game.dll.unpacked.bin', 'helldivers2.exe.unpacked.bin')
# The older build's values of entries that moved (dumps/README.txt: 25327279).
OLDER = {'environment_tags': 0x21df8b8, 'invasion_modifiers': 0x32ef71c, 'template_environments': 0x177e4e0}


def run(*args):
    result = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/check_offsets.py'), *map(str, args)],
                            capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


def available():
    try:
        import numpy  # noqa: F401
        import code_match  # noqa: F401  (imports Capstone)
    except ImportError as error:
        return f'skipped: {error}'
    if WORKSPACE is None:
        return 'skipped: no dumps folder'
    data = offsets.raw()
    current = WORKSPACE / 'dumps' / f'build-{data["build"]}'
    if not all((current / name).exists() for name in IMAGES) or not all((WORKSPACE / 'dumps' / n).exists() for n in IMAGES):
        return 'skipped: dumps missing'
    return None


def main():
    reason = available()
    if reason:
        print('check_offsets:', reason)
        return
    data = offsets.raw()
    current = WORKSPACE / 'dumps' / f'build-{data["build"]}'
    older = WORKSPACE / 'dumps'
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        # 1. The table matches its own build.
        code, out = run(current)
        assert code == 0 and 'all anchored entries match' in out, out

        # 2. Carried to the older build, everything anchored matches it.
        table = temp / 'offsets.lua'
        shutil.copy(offsets.SOURCE, table)
        code, out = run(older, '--reference', current, '--table', table, '--write')
        assert code == 1 and 'wrote' in out and 'ambiguous' not in out and 'changed, no exact match' not in out, out
        code, out = run(older, '--table', table)
        assert code == 0 and 'all anchored entries match' in out, out
        carried = offsets.raw(table)
        for name, rva in OLDER.items():
            entry = carried['code'].get(name) or carried['globals'][name]
            assert entry['rva'] == rva, f'{name}: {entry["rva"]:#x}, expected {rva:#x}'

        # 3. A synthetic build: one generator displacement and one anchored field changed.
        image = bytearray((current / IMAGES[0]).read_bytes())
        import code_match
        reference = code_match.Image(current / IMAGES[0])
        generator = data['code']['generate_operations']
        target = next(i for i in reference.listing(generator['rva'], generator['size'])
                      if i.disp and i.disp >= 0x100 and i.base not in ('rsp', 'rbp') and i.disp_offset)
        at = target.rva + target.disp_offset
        image[at:at + 4] = (target.disp + 8).to_bytes(4, 'little', signed=True)
        field = data['structs']['board']['mission_count']
        anchor = field['anchor']
        ins = reference.instruction(anchor['rva'])
        at = anchor['rva'] + ins.disp_offset
        image[at:at + 4] = (field['values'][0] + 0x10).to_bytes(4, 'little')
        synthetic = temp / 'synthetic'
        synthetic.mkdir()
        (synthetic / IMAGES[0]).write_bytes(image)
        shutil.copy(current / IMAGES[1], synthetic / IMAGES[1])
        code, out = run(synthetic, '--reference', current)
        assert code == 1, out
        assert 'STALE code generate_operations' in out and 'changed, no exact match' in out, out
        assert f'number {target.disp:#x} -> {target.disp + 8:#x}' in out, out
        expected = f"FIX field board.mission_count values=['{field['values'][0] + 0x10:#x}']"
        assert expected in out, out
    print('check_offsets: own build, carried to the older build, and a synthetic change passed')


if __name__ == '__main__':
    main()
