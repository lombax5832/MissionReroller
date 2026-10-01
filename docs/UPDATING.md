# Updating to a new game build

Every build-specific constant the mod reads is in
[`src/offsets.lua`](../src/offsets.lua): the build number, both module
hashes, the code the mod calls or relies on, the module-relative globals,
the struct fields, strides and sizes of 0x100 or more, and a `research`
section of RVAs only the Python tools use. Nothing else in `src/` may hold
one; `tests/test_offsets.py` fails if it does.

Each entry carries an **anchor**: the evidence that ties its value to game
code, which `scripts/check_offsets.py` uses to find the value again in the
next build. A game update is therefore: dump the new build, let
`check_offsets.py` carry the table across, then review what it could not.

## What the mod does on an update

On the first frame the adapter compares the SHA-256 of `game.dll` and
`helldivers2.exe` with `hashes`. After an update they differ and the log
says `STOPPED: … game.dll hash mismatch`; the mod reads nothing else. With
matching hashes it then checks every `code` entry and every anchor
instruction, and stops with `offset signature <name> mismatch` or
`offset anchor <name> mismatch` naming the stale entry. The startup line
`build=<n> hashes=verified signatures=<n> anchors=<n> verified` means all of
them passed.

## Anchors

| Entry | Anchor | Checked by |
|---|---|---|
| code | its `bytes`, or `size` and `sha256` | first frame; `check_offsets.py` |
| global | `anchor={rva,bytes}`: an instruction that addresses the global RIP-relatively and ends in that displacement | first frame; `test_offsets.py` (target); `check_offsets.py` |
| field | `anchor='<code entry>'`: that code uses every value as a displacement or immediate (or the first plus multiples of a stride it uses) | `check_offsets.py` |
| field | `anchor={rva,bytes}`: one instruction whose displacement or immediate is the value; `via='<struct>.<field>'` when the compiler folded that parent offset in; `module='exe'` in the executable | first frame; `test_offsets.py` (encoding); `check_offsets.py` |
| field | `sum='<struct>.<field>+0x98'`: other fields plus constants, recomputed when they move | `test_offsets.py`; `check_offsets.py` |

`unverified=true` marks an entry no anchor has been found for; nothing
checks it, which is how two stale tables once survived a game update.
Offsets below 0x100 inside a record stay inline in the Lua; they are
covered by the code entries of the functions that read those records (see
step 3).

## Steps

1. **Dump the new build.** Run `../GameDllDumper` once in game and move the
   two `*.unpacked.bin` images into `../dumps/build-<new>/`. Validate them
   with `../GameDllDumper/scripts/inspect_dump.py`. Keep the previous
   build's dump: it is the reference the next step reads anchors from.
   Done when both images are in the new folder and validate.

2. **Carry the table across.**

   ```powershell
   python -B scripts/check_offsets.py ..\dumps\build-<new> --reference ..\dumps\build-<old> --write
   python -B scripts/check_offsets.py ..\dumps\build-<new>
   ```

   The first command reports each stale entry and writes every `FIX` it is
   sure of into `src/offsets.lua`: new RVAs, bytes, SHA-256s, anchors and
   field values. Code counts as the same when it differs only in call
   targets and RIP displacements (`scripts/code_match.py`). Done when the
   second command prints `all anchored entries match`, apart from the
   entries step 3 handles, and the `git diff` of `src/offsets.lua` reads as
   moved code and nothing else.

3. **Review what was not written.** Each report line says why:

   - `ambiguous`: several places hold the code. Pick one in Ghidra
     (`../tools/ghidra-projects`, a new project for the build; see
     `AGENTS.md`) and edit the entry.
   - `changed`: the function's code changed. The line names the closest
     function and each struct displacement that changed (`number 0x2788 ->
     0x2790`), followed by the `src/` lines that use the old number: those
     are the inline offsets to update. The entry's `from` note names the
     Lua module that ports the function; compare its logic with the new
     decompilation before trusting predictions again, then set the entry's
     new `rva` and `sha256`.
   - `missing`, `anchor not found`: find the value from its `from` note.
   - `disagreeing`, `folded offset`: the instructions behind one value
     disagree, or a `via` field moved too; confirm the value in Ghidra.
   - `UNVERIFIED`: an entry without an anchor. Carry it from the old build:

     ```powershell
     python -B scripts/check_offsets.py ..\dumps\build-<new> --reference ..\dumps\build-<old> --find-anchors
     ```

     prints each one's value in the new build with an anchor; add the
     anchor and drop `unverified=true`.
   - `COMMENT`: a function RVA in a `src/` comment moved; the line gives
     the new one.

   Done when every line is resolved and step 2's second command prints
   `all anchored entries match`.

4. **Set the build.** Change `build` and both `hashes` in `src/offsets.lua`
   (the SHA-256 of the files on disk, as `api.module_hash` computes them;
   with `HD2_GAME_ROOT` set, `check_offsets.py` prints them on `STALE hash`
   lines), and `M.SUPPORTED_BUILD` in
   `src/mods/ipodalexei/mission_reroller.lua`, which `test_offsets.py`
   requires to match. Update the supported build in `AGENTS.md` and the
   README.

5. **Run the checks.** `python -B tests/test_package.py` must pass, and
   `python -B tests/test_check_offsets.py` too (it carries the table to the
   newest other dump under `../dumps/`). The capture oracles in
   `artifacts/` were recorded on the old build; re-record them with the
   `scripts/validate_*.py` tools when a generator function `changed`.

6. **Test in game** with a test plan under `docs/`, as for any release. The
   startup line must show `hashes=verified` and the signature and anchor
   counts.

## Adding an offset

Add the entry to `src/offsets.lua` and read it through `O`
(`O.rva.<name>`, `O.<struct>.<field>`) in a module (`local O=...`) or a
runtime (`host.O`). Give it a `from` note and an anchor:

```powershell
python -B scripts/check_offsets.py --find-anchors
```

prints a candidate for every global and field still marked `unverified`,
best first: one whose base register comes from the struct's global through
the expected offsets is `confirmed`. A struct's base is the global named
like it (or its plural), or the field named like it in another struct
(`board.campaign` for `campaign`). Prefer a confirmed candidate or a code
entry the value's `from` function already has; otherwise check the
candidate in Ghidra before using it, or leave `unverified=true`. When the
Lua ports or mirrors a game function, give that function a code entry, so
that a change to it is reported. Then run `python -B scripts/check_offsets.py`
and `python -B tests/test_offsets.py`.
