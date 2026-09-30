# Updating to a new game build

Every build-specific constant the mod reads is in
[`src/offsets.lua`](../src/offsets.lua): the build number, both module
hashes, the code the mod calls or relies on, the module-relative globals,
the struct fields, strides and sizes of 0x100 or more, and a `research`
section of RVAs only the Python tools use. Nothing else in `src/` may hold
one; `tests/test_offsets.py` fails if it does. A game update is therefore an
edit of that one file, checked against a dump before the game is launched.

## What the mod does on an update

On the first frame the adapter compares the SHA-256 of `game.dll` and
`helldivers2.exe` with `hashes`. After an update they differ and the log
says `STOPPED: … game.dll hash mismatch`; the mod reads nothing else. With
matching hashes it then checks every `code` entry and every global's
`anchor`, and stops with `offset signature <name> mismatch` or
`offset anchor <name> mismatch` naming the stale entry. The startup line
`build=<n> hashes=verified signatures=<n> anchors=<n> verified` means all of
them passed.

## Steps

1. **Dump the new build.** Run `../GameDllDumper` once in game and move the
   two `*.unpacked.bin` images into `../dumps/build-<new build>/`. Validate
   them with `../GameDllDumper/scripts/inspect_dump.py`. Keep the previous
   build's dump: it is the reference the next step searches from.
2. **Check the table against the new dump.**

   ```powershell
   python -B scripts/check_offsets.py ..\dumps\build-<new> --reference ..\dumps\build-<old>
   ```

   Each stale entry prints one line. For a code entry, `candidates=` lists
   where the old bytes now match with call targets and RIP displacements
   wildcarded. For a global, the anchor instruction is searched the same way
   and the line gives the new `anchor_rva`, the global's new `rva` it
   addresses, and the new anchor `bytes`. A field anchored to a code entry
   is stale when that code no longer uses the displacement.
3. **Confirm each suggestion in Ghidra** (`../tools/ghidra-projects`, a new
   project for the build; see `AGENTS.md`). The `from` note of every entry
   names the function or document it came from. Update `rva`, `bytes` (or
   `size` and `sha256`), `anchor` and field values in `src/offsets.lua`.
4. **Recheck the unverified fields.** A field marked `unverified=true` has
   no anchor, so step 2 cannot see it move. Look each one up from its
   struct's `from` note, or find an anchor for it:

   ```powershell
   python -B scripts/check_offsets.py ..\dumps\build-<new> --find-anchors
   ```

   prints candidate anchors for unanchored globals and for unverified fields
   of 0x1000 or more that a code entry uses as a displacement.
5. **Set the build.** Change `build` and both `hashes` in `src/offsets.lua`
   (the hashes are the SHA-256 of the files on disk, as `api.module_hash`
   computes them), and `M.SUPPORTED_BUILD` in
   `src/mods/ipodalexei/mission_reroller.lua`, which `test_offsets.py`
   requires to match. Update the supported build in `AGENTS.md` and the
   README.
6. **Run the checks.** `python -B scripts/check_offsets.py ..\dumps\build-<new>`
   must print `all anchored entries match`, and `python -B tests/test_package.py`
   must pass. The capture oracles in `artifacts/` were recorded on the old
   build; re-record them with the `scripts/validate_*.py` tools when a
   generator function changed.
7. **Test in game** with a test plan under `docs/`, as for any release. The
   startup line must show `hashes=verified` and the signature and anchor
   counts.

## Adding an offset

Add the entry to `src/offsets.lua` and read it through `O`
(`O.rva.<name>`, `O.<struct>.<field>`) in a module (`local O=...`) or a
runtime (`host.O`). Give it a `from` note, and an anchor where one exists
(`scripts/check_offsets.py --find-anchors`), otherwise `unverified=true`.
Offsets below 0x100 inside a record stay next to the code that reads them.
