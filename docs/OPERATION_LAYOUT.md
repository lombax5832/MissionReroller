# Complete operation rows and regeneration research

2026-09-28, saved Steam build 25480438. All static addresses below are game.dll
RVAs; board is the pointer at RVA `0x347cee8`. This investigation used offline
Ghidra `-readOnly -noanalysis`. It neither invoked native functions nor changed
the running game. Separate read-only observations supplied by the live research
agent are explicitly identified below.

## Operation to mission mapping

The board contains **110 operation rows**, at `board+0xf7280`, stride `0x5c`
(92), followed by cached planet index at `+0xf9a08` and dirty byte `+0xf9a0c`.
The mission rows are at **`board+0xf9a10`, stride `0x4c` (76)**. Their count is
`u32(board+0xffc08)` and cached planet is `u32(board+0xffc0c)`. Allocation bound
is 330 rows. Ordinary current rows observed live use indices below 72.

Source: `../../tools/ghidra-projects/reroller_mission_generator.txt`, function
RVA `0x11e5670`; `reroller_layout_consumers.txt`, `0x12d2140`, `0x12d5550`.

| Operation row offset | Read interpretation |
| --- | --- |
| +0 | Operation row index, used when adding mission references |
| +12 | Generation seed used as mission generator RNG starting state |
| +16 | Planet index (u16) |
| +24 | Operation ID byte in the existing KYC reader; distinct from array index |
| +28 | Category, used for category settings lookup |
| +32 | Difficulty (low byte consumed by mission generator) |
| +36 | Faction enum, consumed by special mission selection |
| +52 | Valid flag byte |
| +56 | Operation template/settings index, used with global stride0x490 |
| +72,+76,+80 | Up to three mission status values |
| +84 | Mission **status** count byte |
| +85,+86,+87 | Mission row indices (bytes) |
| +88 | Generated mission-index count; native accesses the low byte |

**Do not substitute +84 for +88.** They happen to agree in the observed rows,
but generation resets and fills +88 separately, then initializes status rows
only when +84 is zero. A consistent snapshot should validate both counts,
cross-check operation/mission identity, and reject disagreement until its
meaning is known. The index bytes impose a narrower index range than the
mission array allocation; do not infer that all 330 rows are addressable from
an operation's three byte fields.

| Mission row offset | Read interpretation |
| --- | --- |
| +40 | Parent operation row index |
| +44 | Generated level/position selection index; exact semantic name unconfirmed |
| +48 | Mission settings index into RVA `0x3773420`, stride896 |
| +52 | Mission seed |
| +56 | Status copied from operation +72+4*slot |
| +60 | Difficulty |
| +64 | Mission kind: normal path uses category setting/default1; extra mission path uses2 |
| +68 | Ordinal within operation's generated mission references |
| +72 | `0xffffffff` for ordinary missions; special insertion path writes special slot |

Source: `reroller_mission_fields.txt`, RVA `0x11e6340`, writes all these fields
except ordinal; `reroller_mission_generator.txt`, RVA `0x11e5670`, writes the
ordinal, special slot, references and statuses. Mission setting selection
compares the settings record's first hash against weighted allowed hashes.
The generated mission ID is the **settings array index**, not that hash.

The live reader observed 30 valid operations for planet268 (three per each
difficulty1–10) and72 missions: one mission per difficulty1–2 operation, two
per difficulty3–4, and three per difficulty5–10. Mission0 settings index58
and seed1409118643 matched the loaded preview descriptor. These are one
session's observations, not universal mission-count rules or legal pools.

## Normal generation is deterministic

RVA `0x12d5550` takes board, campaign snapshot and planet. Unless the requested
planet differs from cached planet or the dirty byte is set, it skips work.
Otherwise it clears the operation array, initializes an RNG with
`u32(campaign+0x78e84)+planet`, preserves a valid in-progress operation from
`campaign+0x78e88` when its planet matches, and calls operation generators
`0x11e3c10`, `0x11e4060`, `0x11e44d0`.

The equivalent array-based wrapper is `0x11e48b0`. Mission generator
`0x11e5670` then uses each operation's +12 seed, current planet data, difficulty
settings and mission weights to populate the entire mission list. It walks
all110 operation slots, so a displayed difficulty change is not itself proof
of new random generation. Rebuilding with unchanged seed and campaign inputs
should reproduce choices (inference from deterministic inputs).

Source: `reroller_layout_consumers.txt`, RVAs `0x12d5550`, `0x11e48b0`;
`reroller_mission_generator.txt`, `0x11e5670`.

RVA `0x12d58e0` refreshes the campaign snapshot at `board+0x101438`, sets the
operation dirty byte when a planet is selected, invokes `0x12d5550`, then
`0x11e5670(board+0xf9a10, campaign, board+0xf7280, selected_planet)`.
The global campaign seed and selected planet must therefore be read from the
same snapshot/context as operation data. `board+0x17a298` is selected planet.

## Seed-changing paths and limitations

RVA `0x12d53b0` constructs request ID `0x54069357`, method enum3, route
`%s/Operation` (string RVA `0x22c1388`), then clears the active-operation
record, changes the campaign seed using the shared RNG, and calls
`0x12d57e0(...,2)`. This is **not** the separately discovered
`%s/Operation/Reroll` wrapper. A raw direct-call scan found no E8/E9 call to
`0x12d53b0`; its normal user trigger is still unestablished.

RVA `0x12d57e0` marks per-owner dirty flags. It walks manager
`*(game+0x347cef0)+0x162e0`, count at +0x162d8, and ORs flags into board owner
entries at +0x1f8080, stride16, count+0x1f80d0. These appear to be replicated
owner identifiers, **not planet indices**; the semantic owner type is not yet
proven. Flagging alone does not change the RNG seed.

RVA `0x12d2260` is an abandon path: if active-operation valid byte
`campaign+0x78ebc` is clear, it returns. Otherwise, if an active mission status
is3 or4, it advances the campaign seed; it enqueues Operation/Abandon for the
active operation ID, clears the active record, and marks dirty flag2. Thus
abandonment is not a harmless reroll mechanism, and this research does not
authorize calling it automatically.

Source: `reroller_layout_initial.txt`, `0x12d53b0`, `0x12d57e0`;
`reroller_layout_consumers.txt`, `0x12d2260`. The saved binary string confirms
`%s/Operation`; the HTTP verb represented by enum3 was not independently
identified. No guessed calling convention should be taken from these
decompilations: several functions are partially recovered/unwind fragments,
and Ghidra reports missing parameters or unaffiliated registers.

## Next human observation

The complete read-only snapshot can now be compared against the visible
operation's mission titles, then captured before/after a normal difficulty or
planet selection change. Compare campaign seed, cached planet, row seeds,
mission settings IDs and mission seeds. This establishes whether the normal
UI transition actually regenerates choices. Until a legitimate seed-changing
player transition and its ownership are verified, a native reroll driver
remains blocked. This does not block operation-wide filter previews.
