"""Check src/offsets.lua against unpacked game images, and carry it to a new build.

    python -B scripts/check_offsets.py [<dump dir>] [--reference <dump dir>] [--write]
    python -B scripts/check_offsets.py [<dump dir>] --find-anchors [--reference <dump dir>]

<dump dir> holds game.dll.unpacked.bin and helldivers2.exe.unpacked.bin from
GameDllDumper (file offsets are RVAs). It defaults to ../dumps/build-<build>
for the build offsets.lua names. --reference is the dump offsets.lua was made
for (the same default). docs/UPDATING.md is the runbook.

Without --reference it checks every code entry, anchor and anchored field.
With it, each stale entry is looked up in the new dump (scripts/code_match.py:
code equal up to call targets and RIP displacements), and each line says
what happened:

  moved    the same code at a new RVA; FIX gives the new values
  rebuilt  the same code at the same RVA, only relative targets changed
  ambiguous  several places hold that code; pick one in Ghidra
  changed  no exact match: the code itself changed. The closest function and
           the struct displacements that changed in it are printed; the Lua
           that ports it (see the entry's from note) needs a look
  missing  nothing similar found

Unverified globals are carried too: the instruction that addressed the old
value in the reference build is found in the new one, and its target is the
new value. --write applies every FIX line to src/offsets.lua (review the git
diff; nothing ambiguous or changed is written). --find-anchors prints anchor
candidates for unverified globals and struct fields. With HD2_GAME_ROOT set it
also compares the module hashes with the installed game. Exit status 1 when
any entry is stale.
"""
import argparse
from collections import Counter
import hashlib
import os
from pathlib import Path
import re
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import code_match
import offsets

ROOT = Path(__file__).resolve().parents[1]
IMAGES = {'game': 'game.dll.unpacked.bin', 'exe': 'helldivers2.exe.unpacked.bin'}


class Images:
    def __init__(self, folder):
        self.folder = Path(folder)
        self.loaded = {}

    def __call__(self, module):
        if module not in self.loaded:
            path = self.folder / IMAGES[module]
            assert path.exists(), f'missing {path}'
            self.loaded[module] = code_match.Image(path)
        return self.loaded[module]


def code_length(entry, code=None):
    if 'bytes' in entry:
        return len(entry['bytes']) // 2
    if 'size' in entry:
        return entry['size']
    return 0


def code_ok(entry, image, rva=None):
    rva = entry['rva'] if rva is None else rva
    data = image.data[rva:rva + code_length(entry)]
    if 'bytes' in entry:
        return data.hex() == entry['bytes']
    return hashlib.sha256(data).hexdigest() == entry['sha256']


def field_anchor(entry, data):
    """A struct field's anchor instruction {module, rva, bytes, plus}, or None.

    The instruction's displacement or immediate is the field's value plus
    `plus`: 0, or the value of the field named by via (an offset folded in).
    """
    anchor = entry.get('anchor')
    if not isinstance(anchor, dict):
        return None
    plus = 0
    if anchor.get('via'):
        struct_name, field = anchor['via'].split('.')
        plus = data['structs'][struct_name][field]['values'][0]
    return {'module': anchor.get('module', 'game'), 'rva': anchor['rva'], 'bytes': anchor['bytes'], 'plus': plus}


class Report:
    def __init__(self):
        self.counts = Counter()
        self.fixes = []    # (kind, name, {key: value}) for --write
        self.stale = []

    def line(self, text):
        print(text)

    def fix(self, kind, name, values):
        self.fixes.append((kind, name, values))
        shown = ' '.join(f'{k}={v:#x}' if isinstance(v, int) else
                         f'{k}={[hex(x) for x in v]}' if isinstance(v, list) else f"{k}='{v}'"
                         for k, v in values.items() if k != 'anchor')
        if 'anchor' in values:
            a = values['anchor']
            shown += f" anchor={{rva=0x{a['rva']:x},bytes='{a['bytes']}'}}"
        print(f'  FIX {kind} {name} {shown}')


def relocate_instruction(reference, at, image, deltas):
    """Where the instruction at `at` in reference is in image: (rva, how) or (None, why)."""
    span = reference.function(at)
    if span:
        start, end = span
        found = code_match.find(reference, start, end - start, image)
        if len(found) == 1:
            return found[0] + at - start, 'function moved' if found[0] != start else 'function unchanged'
        if len(found) > 1:
            return None, f'its function {start:#x} is found {len(found)} times'
        best = code_match.closest(reference, start, end - start, image, deltas)
        if best and best[1] >= 0.8:
            new = code_match.map_instruction(reference, at, image, best[0])
            if new is not None:
                return new, f'function changed, closest {best[0]:#x} similarity {best[1]:.2f}'
        return None, f'function {start:#x} not found'
    # No function record (rare): the 64 bytes around it.
    found = code_match.find(reference, at - 32, 64, image)
    if len(found) == 1:
        return found[0] + 32, 'context moved'
    return None, f'{len(found)} matches of its context'


def check_code(data, images, reference, report):
    """Code entries. Returns {name: new rva} and the RVA deltas seen per module."""
    code, where, deltas = data['code'], {}, {'game': Counter(), 'exe': Counter()}
    for name, entry in sorted(code.items()):
        if 'within' in entry:
            continue
        image = images(entry['module'])
        if code_ok(entry, image):
            where[name] = entry['rva']
            report.counts['code ok'] += 1
            continue
        report.stale.append(name)
        if not reference:
            report.line(f'STALE code {name} rva={entry["rva"]:#x}')
            report.counts['code stale'] += 1
            continue
        old, length = reference(entry['module']), code_length(entry)
        found = code_match.find(old, entry['rva'], length, image)
        if len(found) > 1 and not old.code(entry['rva']):
            # A constant found twice: keep the copy the reference build's code addressed.
            addressed = set()
            for at in old.rip_users(entry['rva'])[:8]:
                new, _ = relocate_instruction(old, at, image, deltas[entry['module']])
                ins = image.instruction(new) if new is not None else None
                if ins and ins.rip in found:
                    addressed.add(ins.rip)
            if len(addressed) == 1:
                found = sorted(addressed)
        if len(found) == 1:
            new = found[0]
            where[name] = new
            deltas[entry['module']][new - entry['rva']] += 1
            how = 'moved' if new != entry['rva'] else 'rebuilt'
            report.counts[f'code {how}'] += 1
            report.line(f'STALE code {name} rva={entry["rva"]:#x}: {how}, same logic')
            values = {'rva': new}
            raw = image.data[new:new + length]
            values.update({'bytes': raw.hex()} if 'bytes' in entry else {'sha256': hashlib.sha256(raw).hexdigest()})
            report.fix('code', name, values)
        elif found:
            report.counts['code ambiguous'] += 1
            report.line(f'STALE code {name} rva={entry["rva"]:#x}: ambiguous, candidates='
                        + ','.join(hex(r) for r in found[:8]) + (f' (+{len(found) - 8})' if len(found) > 8 else ''))
        else:
            report.counts['code changed'] += 1
            report.line(f'STALE code {name} rva={entry["rva"]:#x}: changed, no exact match')
    # Changed code, once the deltas of the code that moved are known.
    for name, entry in sorted(code.items()):
        if 'within' in entry or name in where or not reference or not entry['module']:
            continue
        old, image, length = reference(entry['module']), images(entry['module']), code_length(entry)
        if not old.code(entry['rva']) or code_match.find(old, entry['rva'], length, image):
            continue
        best = code_match.closest(old, entry['rva'], length, image, deltas[entry['module']])
        if not best or best[1] < 0.5:
            report.line(f'  {name}: nothing similar near its old place; find it from its from note: {entry["from"]}')
            continue
        start, ratio = best
        report.line(f'  {name}: closest function {start:#x} similarity {ratio:.2f}; review the port ({entry["from"]})')
        for (a, b), n in sorted(code_match.changed_numbers(old, entry['rva'], length, image, start).items()):
            report.line(f'    number {a:#x} -> {b:#x} ({n}x)')
    for name, entry in sorted(code.items()):
        if 'within' not in entry:
            continue
        outer = code[entry['within']]
        if entry['within'] in where:
            new = entry['rva'] + where[entry['within']] - outer['rva']
            where[name] = new
            if new == entry['rva']:
                report.counts['code ok'] += 1
            else:
                report.counts['code moved'] += 1
                report.line(f'STALE code {name} rva={entry["rva"]:#x}: moved with {entry["within"]}')
                report.fix('code', name, {'rva': new})
        else:
            report.counts['code stale'] += 1
            report.line(f'STALE code {name}: {entry["within"]} is stale')
    return where, deltas


def check_globals(data, images, reference, deltas, report):
    for name, entry in sorted(data['globals'].items()):
        anchor, image = entry.get('anchor'), images(entry['module'])
        if not anchor:
            if reference:
                carry_unverified_global(name, entry, images, reference, deltas, report)
            else:
                report.counts['global unverified'] += 1
            continue
        at = anchor['rva']
        ins = image.instruction(at)
        if image.data[at:at + len(anchor['bytes']) // 2].hex() == anchor['bytes'] and ins and ins.rip == entry['rva']:
            report.counts['global ok'] += 1
            continue
        report.stale.append(name)
        if not reference:
            report.counts['global stale'] += 1
            report.line(f'STALE global {name} rva={entry["rva"]:#x}')
            continue
        new, how = relocate_instruction(reference(entry['module']), at, image, deltas[entry['module']])
        ins = image.instruction(new) if new is not None else None
        if ins is None or ins.rip is None:
            report.counts['global missing'] += 1
            report.line(f'STALE global {name} rva={entry["rva"]:#x}: anchor not found ({how})')
            continue
        report.counts['global moved'] += 1
        report.line(f'STALE global {name} rva={entry["rva"]:#x}: anchor {how}')
        report.fix('global', name, {'rva': ins.rip, 'anchor': {'rva': new, 'bytes': ins.bytes.hex()}})


def carry_unverified_global(name, entry, images, reference, deltas, report):
    """An unverified global: what the reference build's code addressed, found in the new build."""
    old = reference(entry['module'])
    users = rip_users(old, entry['rva'])
    if not users:
        report.counts['global unverified'] += 1
        report.line(f'UNVERIFIED global {name} rva={entry["rva"]:#x}: no instruction addresses it in the reference build')
        return
    targets = Counter()
    for at in users[:8]:
        new, _ = relocate_instruction(old, at, images(entry['module']), deltas[entry['module']])
        ins = images(entry['module']).instruction(new) if new is not None else None
        if ins and ins.rip is not None:
            targets[ins.rip] += 1
    if not targets:
        report.counts['global unverified'] += 1
        report.line(f'UNVERIFIED global {name} rva={entry["rva"]:#x}: its {len(users)} references were not found')
    elif list(targets) == [entry['rva']]:
        report.counts['global unverified'] += 1
    else:
        report.stale.append(name)
        report.counts['global moved'] += 1
        report.line(f'STALE global {name} rva={entry["rva"]:#x} (unverified): the reference build\'s '
                    f'instructions now address ' + ', '.join(f'{t:#x} ({n}x)' for t, n in targets.most_common()))
        if len(targets) == 1:
            report.fix('global', name, {'rva': next(iter(targets))})


def rip_users(image, target):
    """RVAs of code-section instructions that address target RIP-relatively."""
    return image.rip_users(target)


def check_fields(data, images, reference, where, deltas, report):
    code = data['code']
    for struct_name, fields in sorted(data['structs'].items()):
        for field, entry in sorted(fields.items()):
            label, values = f'{struct_name}.{field}', entry['values']
            anchor = entry.get('anchor')
            if not anchor:
                report.counts['field unverified'] += 1
                continue
            instruction = field_anchor(entry, data)
            if instruction:
                check_instruction_field(label, values, instruction, images, reference, deltas, report)
                continue
            owner = code[anchor]
            image = images(owner['module'])
            rva = where.get(anchor, owner['rva'])
            listing = image.listing(rva, code_length(owner))
            missing = [v for v in values if not any(i.uses(v) for i in listing)]
            if missing and values[0] not in missing:
                # Slots of an array the code walks: the first value plus a stride it uses.
                strides = {i.imm for i in listing if i.imm and i.imm > 0}
                missing = [v for v in missing if not any((v - values[0]) % s == 0 and 0 < (v - values[0]) // s <= 8
                                                         for s in strides)]
            if not missing:
                report.counts['field ok'] += 1
                continue
            report.stale.append(label)
            report.counts['field stale'] += 1
            report.line(f'STALE field {label}: {anchor} at {rva:#x} no longer uses ' + ','.join(hex(v) for v in missing))
            if reference:
                old = reference(owner['module'])
                changes = code_match.changed_numbers(old, owner['rva'], code_length(owner), image, rva)
                for v in missing:
                    seen = {b: n for (a, b), n in changes.items() if a == v}
                    if seen:
                        report.line(f'  {hex(v)} became ' + ', '.join(f'{b:#x} ({n}x)' for b, n in seen.items()))
                if len(missing) == len(values) == 1:
                    seen = [b for (a, b) in changes if a == values[0]]
                    if len(seen) == 1:
                        report.fix('field', label, {'values': seen})


def check_instruction_field(label, values, anchor, images, reference, deltas, report):
    image = images(anchor['module'])
    at, raw = anchor['rva'], bytes.fromhex(anchor['bytes'])
    ins = image.instruction(at)
    number = values[0] + anchor['plus']
    if image.data[at:at + len(raw)] == raw and ins and ins.uses(number):
        report.counts['field ok'] += 1
        return
    report.stale.append(label)
    if not reference:
        report.counts['field stale'] += 1
        report.line(f'STALE field {label}={values[0]:#x}: its anchor instruction changed')
        return
    old_image = reference(anchor['module'])
    old = old_image.instruction(at)
    new, how = relocate_instruction(old_image, at, image, deltas[anchor['module']])
    ins = image.instruction(new) if new is not None else None
    if ins is None or old is None or old.text.split()[0] != ins.text.split()[0]:
        report.counts['field missing'] += 1
        report.line(f'STALE field {label}={values[0]:#x}: anchor not found ({how})')
        return
    value = (ins.disp if old.disp == number else ins.imm) - anchor['plus']
    if anchor['plus'] and value != values[0]:
        report.line(f'  folded offset: {value:#x} assumes the via field kept its value; check it')
    report.counts['field moved'] += 1
    report.line(f'STALE field {label}={values[0]:#x}: anchor {how}, now {ins.text}')
    report.fix('field', label, {'anchor': {'rva': new, 'bytes': ins.bytes.hex()}, 'values': [value]})


def find_anchors(data, images, reference):
    """Anchor candidates for unverified globals and struct fields."""
    code = data['code']
    spans = {(e['module'], e['rva'], e['rva'] + code_length(e)) for e in code.values() if 'within' not in e}
    deltas = {'game': Counter(), 'exe': Counter()}
    for name, entry in sorted(data['globals'].items()):
        if entry.get('anchor'):
            continue
        image = images(entry['module'])
        rva = entry['rva']
        if reference:  # the value as the reference build's code addressed it
            old = reference(entry['module'])
            for at in rip_users(old, rva)[:4]:
                new, _ = relocate_instruction(old, at, image, deltas[entry['module']])
                ins = image.instruction(new) if new is not None else None
                if ins and ins.rip is not None:
                    rva = ins.rip
                    break
        users = [u for u in rip_users(image, rva) if anchorable(image.instruction(u))]
        inside = [u for u in users if any(m == entry['module'] and a <= u < b for m, a, b in spans)]
        pick = (inside or users or [None])[0]
        if pick is None:
            print(f'global {name}={rva:#x}: no RIP-relative instruction ending in its displacement addresses it')
        else:
            moved = f' (was {entry["rva"]:#x})' if rva != entry['rva'] else ''
            print(f"global {name}: rva=0x{rva:x}{moved} anchor={{rva=0x{pick:x},bytes='{image.instruction(pick).bytes.hex()}'}} "
                  f'({len(users)} references, {len(inside)} inside code entries)')
    for struct_name, fields in sorted(data['structs'].items()):
        path = struct_path(data, struct_name)
        for field, entry in sorted(fields.items()):
            if entry.get('anchor'):
                continue
            label = f'{struct_name}.{field}'
            for value in entry['values']:
                if reference:
                    carry_field(data, images, reference, path, label, value)
                    continue
                found = field_candidates(data, images, path, value)
                if not found:
                    where = 'its struct has no known base; ' if path is None else ''
                    print(f'field {label}={value:#x}: no candidate ({where}see its from note)')
                    continue
                confirmed = [c for c in found if c['confirmed']]
                best = found[0]
                via = f",via='{best['via']}'" if best['via'] else ''
                module = f",module='{best['module']}'" if best['module'] != 'game' else ''
                print(f"field {label}={value:#x}: anchor={{rva=0x{best['rva']:x},bytes='{best['ins'].bytes.hex()}'{via}{module}}} "
                      f"({best['ins'].text}; base {best['origin']}; {len(confirmed)} of {len(found)} candidates confirmed)")


def carry_field(data, images, reference, path, label, value):
    """A field's value in the new build: its confirmed users in the reference build, found again."""
    old = [c for c in field_candidates(data, reference, path, value) if c['confirmed']][:6]
    if not old:
        print(f'field {label}={value:#x}: no confirmed instruction in the reference build; see its from note')
        return
    module = old[0]['module']
    folded = path[2][-1][0] if path and path[2] else 0  # the struct's offset in its parent
    results = Counter()
    picks = {}
    for c in old:
        new, how = relocate_instruction(reference(module), c['rva'], images(module), Counter())
        ins = images(module).instruction(new) if new is not None else None
        if ins is None or ins.mnemonic != c['ins'].mnemonic:
            continue
        plus = folded if c['via'] else 0
        number = ins.disp if c['ins'].disp == value + plus else ins.imm
        if number is None:
            continue
        now = number - plus
        results[now] += 1
        picks.setdefault(now, (new, ins, c['via']))
    if not results:
        print(f'field {label}={value:#x}: its {len(old)} reference instructions were not found in the new build')
        return
    now, n = results.most_common(1)[0]
    at, ins, via = picks[now]
    state = 'unchanged' if now == value else f'now {now:#x}'
    note = f",via='{via}'" if via else ''
    print(f"field {label}={value:#x}: {state} ({n} of {len(old)} reference instructions agree) "
          f"anchor={{rva=0x{at:x},bytes='{ins.bytes.hex()}'{note}}} ({ins.text})")
    if len(results) > 1:
        print('  disagreeing: ' + ', '.join(f'{v:#x} ({k}x)' for v, k in results.most_common()[1:]))


def anchorable(ins):
    """An anchor ends in its RIP displacement, so tests can read its target from the bytes."""
    return ins is not None and ins.rip is not None and ins.imm is None and ins.relative and \
        ins.relative[-1] == (ins.size - 4, 4)


def struct_path(data, name, seen=()):
    """How code reaches a struct: (module, root global RVA, [(offset, field name)]) or None.

    The root is the global named like the struct (or its plural); a struct
    named like another struct's field lies at that field's offset.
    """
    for glob in (name, name + 's'):
        if glob in data['globals']:
            entry = data['globals'][glob]
            return entry['module'], entry['rva'], []
    for parent, fields in sorted(data['structs'].items()):
        if name in fields and parent not in seen:
            outer = struct_path(data, parent, seen + (name,))
            if outer:
                return outer[0], outer[1], outer[2] + [(fields[name]['values'][0], f'{parent}.{name}')]
    return None


def origin_matches(steps, root, offsets):
    """origin() steps are the root global followed by these offsets (array indexing aside)."""
    steps = [s for s in steps if s[0] != 'array']
    return (len(steps) == len(offsets) + 1 and steps[0][0] in ('global', 'pointer') and steps[0][1] == root
            and all(s[1] == o for s, (o, _) in zip(steps[1:], offsets)))


def field_candidates(data, images, path, value):
    """Instructions using a field's offset, best first.

    The offset may appear alone or folded with the struct's last offset from
    its parent (via). A candidate is confirmed when its base register comes
    from the struct's root global through the expected offsets.
    """
    code_spans = [(e['module'], e['rva'], e['rva'] + code_length(e)) for e in data['code'].values() if 'within' not in e]
    module = path[0] if path else 'game'
    image = images(module)
    forms = [(value, None, path[2] if path else [])]
    if path and path[2]:
        last, name = path[2][-1]
        forms.append((value + last, name, path[2][:-1]))
    found = {}
    for number, via, offsets in forms:
        sites = set()
        if path:  # functions that load the root global, where small offsets can be told apart
            for at in rip_users(image, path[1]):
                span = image.function(at)
                if span:
                    sites.update(i.rva for i in image.listing(span[0], span[1] - span[0]) if i.uses(number))
        if number >= 0x1000:
            sites.update(image.value_users(number))
        for at in sorted(sites):
            listing, k = code_match.located(image, at)
            if listing is None:
                continue
            ins = listing[k]
            if not ins.uses(number):
                continue
            origins = [code_match.origin(listing, k, r) for r in (ins.base, ins.index) if r]
            confirmed = bool(path) and any(origin_matches(o, path[1], offsets) for o in origins)
            inside = any(m == module and a <= at < b for m, a, b in code_spans)
            found.setdefault(at, {'rva': at, 'ins': ins, 'via': via, 'module': module, 'confirmed': confirmed,
                                  'inside': inside, 'origin': ' / '.join(code_match.describe(o) for o in origins) or 'none'})
    return sorted(found.values(), key=lambda c: (not c['confirmed'], not c['inside'], c['via'] is not None, c['rva']))


def installed_hashes(data):
    """Compare hashes with the installed binaries, as api.module_hash computes them."""
    root = os.environ.get('HD2_GAME_ROOT')
    if not root:
        return True
    ok = True
    for module, relative in (('game', 'data/game/game.dll'), ('exe', 'bin/helldivers2.exe')):
        path = Path(root) / relative
        if not path.exists():
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest().upper()
        if digest != data['hashes'][module]:
            ok = False
            print(f"STALE hash {module}: installed {path} is {digest}")
    manifest = Path(root).parents[1] / 'appmanifest_553850.acf'
    if manifest.exists():
        build = re.search(r'"buildid"\s+"(\d+)"', manifest.read_text(errors='replace'))
        if build and int(build.group(1)) != data['build']:
            ok = False
            print(f'STALE build: the installed game is build {build.group(1)}')
    return ok


def write(fixes, path=offsets.SOURCE):
    """Apply FIX lines to offsets.lua's text, entry by entry."""
    text = path.read_text(encoding='utf-8')
    for kind, name, values in fixes:
        if kind in ('code', 'global'):
            # An entry may continue on following lines (bytes=...); it ends in '},'.
            m = re.search(r'^    %s=\{module=(?:.*\n)*?.*\},?$' % re.escape(name), text, re.M)
        else:
            struct_name, field = name.split('.')
            block = re.search(r'^    %s=\{\n(.*?)^    \},' % re.escape(struct_name), text, re.M | re.S)
            m = block and re.compile(r'^        %s=\{.*$' % re.escape(field), re.M).search(text, block.start(1), block.end(1))
        assert m, f'{name} not found in {path}'
        line = m.group(0)
        if 'anchor' in values:
            a = values['anchor']
            old = re.search(r'anchor=\{[^}]*\}', line)
            if old:  # keep its other keys (via, module)
                new = re.sub(r'\brva=0x[0-9a-f]+', f"rva=0x{a['rva']:x}", old.group(0), count=1)
                new = re.sub(r"\bbytes='[0-9a-f]+'", f"bytes='{a['bytes']}'", new, count=1)
                line = line[:old.start()] + new + line[old.end():]
            else:
                line = line.replace('unverified=true', f"anchor={{rva=0x{a['rva']:x},bytes='{a['bytes']}'}}", 1)
        if 'rva' in values:
            line = re.sub(r'\brva=0x[0-9a-f]+', f'rva=0x{values["rva"]:x}', line, count=1)
        for key in ('bytes', 'sha256'):
            if key in values:
                line = re.sub(r"\b%s='[0-9a-f]+'" % key, f"{key}='{values[key]}'", line, count=1)
        if 'values' in values:
            line = re.sub(r'=\{(0x[0-9a-f]+,)+', '={' + ''.join(f'0x{v:x},' for v in values['values']), line, count=1)
        text = text[:m.start()] + line + text[m.end():]
    path.write_text(text, encoding='utf-8', newline='')
    print(f'wrote {len(fixes)} fixes to {path}; review git diff, then run tests/test_offsets.py')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('dump', nargs='?')
    parser.add_argument('--reference')
    parser.add_argument('--find-anchors', action='store_true')
    parser.add_argument('--write', action='store_true', help='apply the FIX lines to src/offsets.lua')
    parser.add_argument('--table', default=str(offsets.SOURCE), help='another copy of offsets.lua (tests)')
    args = parser.parse_args(argv)
    table = Path(args.table)
    data = offsets.raw(table)
    # The workspace's dumps/, found upward so a worktree resolves it too.
    workspace = next((p for p in ROOT.parents if (p / 'dumps').is_dir()), ROOT.parent)
    default = workspace / 'dumps' / f'build-{data["build"]}'
    images = Images(args.dump or default)
    reference = Images(args.reference or default)
    if reference.folder.resolve() == images.folder.resolve():
        reference = None
    if args.find_anchors:
        find_anchors(data, images, reference)
        return 0
    report = Report()
    where, deltas = check_code(data, images, reference, report)
    check_globals(data, images, reference, deltas, report)
    check_fields(data, images, reference, where, deltas, report)
    print('counts: ' + ', '.join(f'{k}={n}' for k, n in sorted(report.counts.items())))
    unverified = report.counts['global unverified'] + report.counts['field unverified']
    if report.stale:
        print(f'{len(report.stale)} stale; {unverified} unverified entries are not checked (docs/UPDATING.md)')
    else:
        print(f'all anchored entries match {images.folder}; {unverified} unverified entries are not checked')
    if args.write and report.fixes:
        write(report.fixes, table)
    # The installed game may be newer than the dump; say so, without failing the dump check.
    if not installed_hashes(data):
        print('the installed game is not the build offsets.lua names; see docs/UPDATING.md')
    return 1 if report.stale else 0


if __name__ == '__main__':
    sys.exit(main())
