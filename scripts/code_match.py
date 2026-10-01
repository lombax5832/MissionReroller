"""Find code and data of one game build in another, for scripts/check_offsets.py.

    import code_match
    old = code_match.Image('../dumps/build-25480438/game.dll.unpacked.bin')
    new = code_match.Image('../dumps/build-<new>/game.dll.unpacked.bin')
    code_match.find(old, 0x11e3c10, 1104, new)     # RVAs where that code now is
    code_match.closest(old, 0x11e3c10, 1104, new, deltas)  # when it changed

An image is a GameDllDumper dump: file offsets are RVAs. Code is decoded
with Capstone (workspace tools/seed-emulator-deps), and two pieces of code
are the same when they differ only in the 4-byte fields a rebuild moves:
call and jump targets and RIP-relative displacements, in every instruction
form (SSE ones included). Everything else, struct displacements and
immediates among them, must match.
"""
from bisect import bisect_right
import difflib
import hashlib
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
DEPS = next((p / 'tools/seed-emulator-deps' for p in ROOT.parents if (p / 'tools/seed-emulator-deps').is_dir()), None)
if DEPS:
    sys.path.insert(0, str(DEPS))
import capstone  # noqa: E402  (pip install capstone==5.0.7, or the workspace copy)
from capstone import x86  # noqa: E402

_md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
_md.detail = True
_md.skipdata = True  # an undecodable byte becomes data instead of ending the listing
EXECUTABLE = 0x20000000
NUMBER = re.compile(r'0x[0-9a-f]+|\b\d+\b')
_FAMILIES = {}
for _name in ('ax', 'bx', 'cx', 'dx'):
    for _r in ('r' + _name, 'e' + _name, _name, _name[0] + 'l', _name[0] + 'h'):
        _FAMILIES[_r] = 'r' + _name
for _name in ('si', 'di', 'bp', 'sp'):
    for _r in ('r' + _name, 'e' + _name, _name, _name + 'l'):
        _FAMILIES[_r] = 'r' + _name
for _n in range(8, 16):
    for _r in (f'r{_n}', f'r{_n}d', f'r{_n}w', f'r{_n}b'):
        _FAMILIES[_r] = f'r{_n}'


def full(name):
    """A register's 64-bit name (eax -> rax, r9d -> r9); others unchanged."""
    return _FAMILIES.get(name, name)


class Instruction:
    """One decoded instruction: where it is, its bytes, and its numbers."""
    __slots__ = ('rva', 'size', 'bytes', 'text', 'relative', 'rip', 'disp', 'imm', 'disp_offset', 'imm_offset',
                 'mnemonic', 'base', 'index', 'target', 'source', 'writes')

    def __init__(self, insn):
        self.rva, self.size, self.bytes = insn.address, insn.size, bytes(insn.bytes)
        self.text = f'{insn.mnemonic} {insn.op_str}'.strip()
        self.relative = []  # (offset, size) of fields a rebuild moves
        self.rip = None     # the RIP-relative target, when there is one
        self.disp = self.imm = None
        self.disp_offset = self.imm_offset = 0
        self.mnemonic = insn.mnemonic
        self.base = self.index = None  # registers of a non-RIP memory operand, as 64-bit names
        self.target = self.source = None  # a register destination, and the operand it comes from
        self.writes = set()
        if insn.id == 0:  # skipped data
            return
        try:
            self.writes = {full(insn.reg_name(r)) for r in insn.regs_access()[1]}
        except capstone.CsError:
            pass
        ops = insn.operands
        if len(ops) == 2 and ops[0].type == x86.X86_OP_REG:
            self.target = full(insn.reg_name(ops[0].reg))
            if ops[1].type == x86.X86_OP_REG:
                self.source = ('reg', full(insn.reg_name(ops[1].reg)))
            elif ops[1].type == x86.X86_OP_MEM:
                self.source = ('mem',)
            elif ops[1].type == x86.X86_OP_IMM:
                self.source = ('imm',)
        branch = insn.group(capstone.CS_GRP_BRANCH_RELATIVE)
        for op in insn.operands:
            if op.type == x86.X86_OP_MEM:
                if op.mem.base == x86.X86_REG_RIP:
                    self.rip = insn.address + insn.size + op.mem.disp
                    self.relative.append((insn.disp_offset, insn.disp_size))
                else:
                    self.disp = op.mem.disp
                    self.disp_offset = insn.disp_offset
                    if op.mem.base:
                        self.base = full(insn.reg_name(op.mem.base))
                    if op.mem.index:
                        self.index = full(insn.reg_name(op.mem.index))
            elif op.type == x86.X86_OP_IMM:
                if branch:
                    if insn.imm_size == 4:
                        self.relative.append((insn.imm_offset, 4))
                else:
                    self.imm = op.imm
                    self.imm_offset = insn.imm_offset

    def uses(self, value):
        """value is this instruction's struct displacement or immediate (stack slots aside)."""
        return value == self.imm or (value == self.disp and self.base != 'rsp')

    def shape(self):
        """The instruction with its numbers blanked, to align two listings."""
        return NUMBER.sub('#', self.text)


class Image:
    """A dump: its bytes, sections and the x64 function table (.pdata)."""

    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        data = self.data
        pe = struct.unpack_from('<I', data, 0x3c)[0]
        count = struct.unpack_from('<H', data, pe + 6)[0]
        optional = struct.unpack_from('<H', data, pe + 20)[0]
        table = pe + 24 + optional
        self.sections = []
        for i in range(count):
            size, rva, _, _ = struct.unpack_from('<IIII', data, table + i * 40 + 8)
            flags = struct.unpack_from('<I', data, table + i * 40 + 36)[0]
            self.sections.append((rva, rva + size, bool(flags & EXECUTABLE)))
        rva, size = struct.unpack_from('<II', data, pe + 24 + 112 + 3 * 8)  # the exception directory
        records = sorted(struct.unpack_from('<II', data, rva + i * 12) for i in range(size // 12))
        # A function has one record per unwind region (prologue, body,
        # epilogues), back to back; padding separates functions.
        self.starts, self.ends = [], []
        for start, end in records:
            if self.ends and start == self.ends[-1]:
                self.ends[-1] = end
            else:
                self.starts.append(start)
                self.ends.append(end)
        self._listings = {}

    def code(self, rva):
        """rva lies in the first section, the code (later executable ones are the packer's)."""
        start, end, _ = self.sections[0]
        return start <= rva < end

    def function(self, rva):
        """(start, end) of the function containing rva, or None outside the code.

        Leaf functions have no .pdata record; between two records the gap
        (padding and leaf functions) counts as one function.
        """
        if not self.code(rva):
            return None
        i = bisect_right(self.starts, rva) - 1
        if i >= 0 and rva < self.ends[i]:
            return self.starts[i], self.ends[i]
        start = self.ends[i] if i >= 0 else self.sections[0][0]
        end = self.starts[i + 1] if i + 1 < len(self.starts) else self.sections[0][1]
        return start, end

    def functions_near(self, rva, deltas, window=0x400):
        """Function starts within window of rva shifted by each delta."""
        found = set()
        for delta in deltas:
            lo = bisect_right(self.starts, rva + delta - window)
            hi = bisect_right(self.starts, rva + delta + window)
            found.update(self.starts[lo:hi])
        return sorted(found)

    def listing(self, rva, length):
        """The instructions of [rva, rva+length)."""
        key = (rva, length)
        if key not in self._listings:
            raw = self.data[rva:rva + length]
            self._listings[key] = [Instruction(i) for i in _md.disasm(raw, rva)]
        return self._listings[key]

    def rip_users(self, target):
        """RVAs of code-section instructions that address target RIP-relatively."""
        import numpy
        start, end, _ = self.sections[0]
        found = set()
        for k in range(4):
            first = start + k
            count = (end - first) // 4
            disp = numpy.frombuffer(self.data, '<i4', count, first).astype(numpy.int64)
            at = first + 4 * numpy.arange(count, dtype=numpy.int64)
            for imm in (0, 1, 2, 4):  # the displacement ends the instruction, or an immediate follows
                for pos in at[disp + at + 4 + imm == target].tolist():
                    ins = self.covering(pos)
                    if ins and ins.rip == target and ins.rva + ins.size == pos + 4 + imm:
                        found.add(ins.rva)
        return sorted(found)

    def value_users(self, value, limit=None):
        """RVAs of code-section instructions using value as a 4-byte displacement or immediate."""
        import numpy
        start, end, _ = self.sections[0]
        found = []
        for k in range(4):
            first = start + k
            count = (end - first) // 4
            words = numpy.frombuffer(self.data, '<i4', count, first)
            for pos in (first + 4 * numpy.nonzero(words == numpy.int32(value - (1 << 32) if value >= 1 << 31 else value))[0]).tolist():
                ins = self.covering(pos)
                if ins and ins.uses(value) and pos - ins.rva in (ins.disp_offset, ins.imm_offset):
                    found.append(ins.rva)
                    if limit and len(found) >= limit:
                        return sorted(found)
        return sorted(set(found))

    def covering(self, rva):
        """The instruction of rva's function that contains rva, decoded from the function start."""
        span = self.function(rva)
        if span is None:
            return None
        listing = self.listing(span[0], span[1] - span[0])
        i = bisect_right([ins.rva for ins in listing], rva) - 1
        return listing[i] if i >= 0 and rva < listing[i].rva + listing[i].size else None

    def instruction(self, rva):
        listing = self.listing(rva, 16)
        return listing[0] if listing else None


def normalised(image, rva, length):
    """The bytes with every relative field zeroed, and the list of those fields."""
    data = bytearray(image.data[rva:rva + length])
    fields = []
    for ins in image.listing(rva, length):
        for offset, size in ins.relative:
            at = ins.rva - rva + offset
            if at + size <= length:
                data[at:at + size] = bytes(size)
                fields.append((at, size))
    return bytes(data), fields


def shape_hash(image, rva, length):
    """SHA-256 of the normalised bytes: equal when only relative fields differ."""
    return hashlib.sha256(normalised(image, rva, length)[0]).hexdigest()


def pattern(image, rva, length):
    """A regex for the code at rva with its relative fields wildcarded."""
    data, fields = normalised(image, rva, length)
    parts, at = [], 0
    for offset, size in sorted(fields):
        parts.append(re.escape(data[at:offset]))
        parts.append(b'.{%d}' % size)
        at = offset + size
    parts.append(re.escape(data[at:]))
    return re.compile(b''.join(parts), re.S)


def find(reference, rva, length, image):
    """Every RVA in image holding reference's [rva, rva+length), relative fields aside.

    Data (outside the code section) is searched for exactly.
    """
    if reference.code(rva):
        regex = pattern(reference, rva, length)
    else:
        regex = re.compile(re.escape(reference.data[rva:rva + length]), re.S)
    found, start = [], 0
    while (m := regex.search(image.data, start)):
        found.append(m.start())
        start = m.start() + 1
    return found


def align(old, new):
    """Pairs of instructions with the same shape, matched in order (difflib)."""
    matcher = difflib.SequenceMatcher(None, [i.shape() for i in old], [i.shape() for i in new], autojunk=False)
    pairs = []
    for a, b, size in matcher.get_matching_blocks():
        pairs.extend(zip(old[a:a + size], new[b:b + size]))
    return pairs, matcher.ratio()


def closest(reference, rva, length, image, deltas):
    """When the code changed: (rva, similarity) of the best near function, or None.

    Candidates are function starts near rva shifted by each delta seen in
    entries that did move unchanged.
    """
    old = reference.listing(rva, length)
    best = None
    for start in image.functions_near(rva, set(deltas) | {0}):
        end = image.function(start)[1]
        _, ratio = align(old, image.listing(start, max(length, end - start)))
        if best is None or ratio > best[1]:
            best = (start, ratio)
    return best


def changed_numbers(reference, rva, length, image, new_rva, new_length=None):
    """Struct displacements and immediates that differ between two versions of code.

    Returns {(old value, new value): count} over aligned instructions.
    """
    pairs, _ = align(reference.listing(rva, length), image.listing(new_rva, new_length or length))
    changes = {}
    for a, b in pairs:
        for x, y in ((a.disp, b.disp), (a.imm, b.imm)):
            if x is not None and y is not None and x != y:
                changes[(x, y)] = changes.get((x, y), 0) + 1
    return changes


def map_instruction(reference, at, image, new_start, new_end=None):
    """Where the instruction at `at` in reference's function now is in image.

    new_start is that function's start in image. Returns the new RVA or None.
    """
    span = reference.function(at)
    if span is None:
        return None
    old_start, old_end = span
    if new_end is None:
        found = image.function(new_start)
        new_end = found[1] if found else new_start + (old_end - old_start)
    pairs, _ = align(reference.listing(old_start, old_end - old_start), image.listing(new_start, new_end - new_start))
    for a, b in pairs:
        if a.rva == at:
            return b.rva
    return None


def origin(listing, at, register, depth=4, window=48):
    """Where a register's value at listing[at] came from, walking back linearly.

    Returns steps, outermost first: ('global', rva) for a lea of a global,
    ('pointer', rva) for a load from one, then ('add', n) for a lea or add of
    n, ('load', n) for a load from +n, and ('array', 0) where a register
    index was added (a record of an array). Control flow is ignored, so this
    is a hint for choosing anchors, not proof. [] when unknown.
    """
    for i in range(at - 1, max(-1, at - 1 - window), -1):
        ins = listing[i]
        if register not in ins.writes:
            continue
        if ins.target != register or ins.source is None or not depth:
            return []
        if ins.source[0] == 'reg':
            if ins.mnemonic == 'mov':
                return origin(listing, i, ins.source[1], depth - 1, window)
            if ins.mnemonic == 'add':  # base plus a scaled index, either way round
                inner = origin(listing, i, register, depth - 1, window) or origin(listing, i, ins.source[1], depth - 1, window)
                return inner + [('array', 0)] if inner else []
            return []
        if ins.source[0] == 'imm':
            if ins.mnemonic == 'add':
                inner = origin(listing, i, register, depth - 1, window)
                return inner + [('add', ins.imm)] if inner else []
            return []
        if ins.rip is not None:
            return [('global', ins.rip)] if ins.mnemonic == 'lea' else [('pointer', ins.rip)]
        if ins.base:
            inner = origin(listing, i, ins.base, depth - 1, window)
            if not inner and ins.index:
                inner = origin(listing, i, ins.index, depth - 1, window)
            if inner:
                steps = inner + ([('array', 0)] if ins.index else [])
                if ins.mnemonic == 'lea':
                    return steps + ([('add', ins.disp)] if ins.disp else [])
                return steps + [('load', ins.disp or 0)]
        return []
    return []


def describe(steps):
    """origin() steps as text, such as [0x347cee8]+0x101438."""
    names = {'global': '&{:#x}', 'pointer': '[{:#x}]', 'add': '+{:#x}', 'load': '->[+{:#x}]', 'array': '[i]'}
    return ''.join(names[kind].format(n) for kind, n in steps) or '?'


def located(image, rva):
    """(listing of rva's function, index of the instruction at rva), or (None, None)."""
    span = image.function(rva)
    if span is None:
        return None, None
    listing = image.listing(span[0], span[1] - span[0])
    for k, ins in enumerate(listing):
        if ins.rva == rva:
            return listing, k
    return None, None
