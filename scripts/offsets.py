"""src/offsets.lua for the Python tools, read through LuaJIT (scripts/offsets_json.lua).

    import offsets
    O = offsets.load()
    O.rva['board']              # a code entry's or global's RVA
    O.field('board', 'seed')    # a struct field: a number, or a list of numbers
    O.research['generate_missions']

offsets.lua stays the only place the numbers live; nothing here repeats one.
"""
from functools import lru_cache
import json
import os
from pathlib import Path
import subprocess
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'src' / 'offsets.lua'


def raw(path=SOURCE):
    """The whole table as JSON data: code, globals, structs, research."""
    lua = os.environ.get('HD2_LUAJIT')
    assert lua, 'Set HD2_LUAJIT to the pinned LuaJIT to read src/offsets.lua'
    output = subprocess.run([lua, str(ROOT / 'scripts' / 'offsets_json.lua'), str(path)],
                            check=True, capture_output=True, text=True).stdout
    return json.loads(output)


def values(entry):
    """A struct field's number, or its list of numbers."""
    numbers = entry['values'] if isinstance(entry, dict) else entry
    return numbers[0] if len(numbers) == 1 else list(numbers)


@lru_cache(maxsize=None)
def load(path=SOURCE):
    data = raw(path)
    rva = {name: entry['rva'] for section in ('code', 'globals') for name, entry in data[section].items()}
    structs = {name: {field: values(entry) for field, entry in fields.items()}
               for name, fields in data['structs'].items()}
    research = {name: entry['rva'] for name, entry in data.get('research', {}).items()}
    return SimpleNamespace(data=data, build=data['build'], hashes=data['hashes'], rva=rva,
                           structs=structs, research=research,
                           field=lambda struct, field: structs[struct][field])
