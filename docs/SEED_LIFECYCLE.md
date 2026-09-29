# Campaign seed ownership and next validation

2026-09-28, Steam build25480438. Offline saved DLL analysis only; no live
writes, function calls, endpoint requests, or game attachment. All function
addresses below are game.dll RVAs. Raw Ghidra output lives under
`../../tools/ghidra-projects/` and is not a release asset. Decompilation of this
partially analysed binary frequently starts in unwind fragments; recovered
signatures are research evidence, not approved callable interfaces.

## Canonical state versus display snapshot

Let board be `*(game.dll+0x347cee8)`. The canonical campaign operation seed is
`u32(board+0x78e84)`. Refresh `0x12d58e0` copies `0x78ee8` bytes from board to
`board+0x101438`, so the displayed campaign seed is
`u32(board+0x17a2bc)`. Writing only the snapshot would be overwritten at the
next refresh. The active operation is the92-byte record at `board+0x78e88`;
its valid byte is `board+0x78ebc`.

Source: `reroller_layout_consumers.txt`, `0x12d58e0`, first copy; canonical
stores in `reroller_seed_setter.txt`, `0x12d5670` and `0x12b6be0`.

Generator `0x12d5550` uses the snapshot seed plus planet to populate the
operation cache, preserving the valid active operation on its matching
planet. The dirty byte at `board+0xf9a0c` only bypasses the cache check; it
does not independently change the seed. Full refresh sets this byte and
also rebuilds missions using `0x11e5670`. Therefore toggling this byte alone
cannot implement a reroll, and a snapshot-only write is not an ownership
solution. Source: `reroller_layout_consumers.txt`, `0x12d5550/0x12d58e0`;
`reroller_mission_generator.txt`, `0x11e5670`.

Root's read-only observation after the planet roundtrip found canonical and
snapshot seed2201397042 equal, and all30 operations/72 missions unchanged.
The active operation remains present: planet268, difficulty1, operation ID6,
seed4082660196, status count1, first status2. Its presence makes any path that
clears the active record unsuitable for automatic experimentation.

## Native reseed helper found

Function `0x12d5670` has the following recovered behavior:

1. If fourth argument is nonzero, clear all92 active-operation bytes.
2. If second argument is zero, canonical seed is nonzero, and fourth argument
   is zero, return without changing anything.
3. Otherwise advance shared RNG at RVA `0x3483c38` using
   `state=state*0x5851f42d4c957f2d+0x14057b7ef767814f`, modulo2^64, and store
   its upper32 bits as canonical seed.
4. OR dirty flag2 into each owner entry through the same loop as `0x12d57e0`.

Source: `reroller_seed_setter.txt`, `0x12d5670`. The earlier partial entry
`0x12d56b0` in `reroller_seed_owner.txt` must not be treated as a callable
function. Its missing prologue hid the active-operation clearing option.

With second argument nonzero and fourth argument zero, the recovered helper
does preserve the active record. However, saved-image scans found no direct
E8/E9 call or absolute function pointer to `0x12d5670`. Normal caller,
eligibility, owner lifetime, exact ABI, and subsequent refresh timing remain
unverified. This is a promising native implementation detail, not yet a
driver. No helper call or equivalent memory mutation is implemented.

## An ordinary request lifecycle changes the seed

Recovered block `0x12b6be0` polls request ID `0xbca6c557` (ordinary Operation
fetch) via `0x12ccf30`. When the returned status equals3, it unconditionally
advances the shared RNG, writes the canonical seed, invokes owner dirtyflag2,
and advances backend manager state at `+0x702fc` to10. Status2 takes error
handling into state13. The seed-changing block does not clear the active
operation. Exact store is at RVA `0x12b6c49`; call to `0x12d57e0` is at
`0x12b6c4f`.

Sources: `reroller_seed_setter.txt`, `0x12b6be0`;
`reroller_seed_assembly.txt`, section `CODE 12b6c10`;
`reroller_seed_serialization.txt`, `0x12ccf30`. The poll routine returns1
while a request is found by its pending check, otherwise it returns the
request-status map value. Error dispatcher `0x12c38f0` writes status2 in that
map (`reroller_dispatch.txt`). Success dispatcher `0x12c50d0` writes status3
to that same map (`reroller_success_dispatch.txt`, lines212–214), confirming
that status3 denotes success here. The complete state machine and its
startup caller have not been recovered; relaunch behavior remains a testable
inference.

Separately, initialization tail `0x12d0786` sets a zero canonical seed when
backend manager state `+0x702fc` equals14 and marks ownerdirty2. Source:
`reroller_mission_fields.txt`, recovered `0x12d0670` tail.

The string `operationSeed` exists at RVA `0x2260da0`, referenced by instruction
`0x12cb9fd` in an outgoing request serializer (near request ID `0xff195e45`).
This establishes neither a persisted canonical seed nor a seed parser;
the partial decompilation is insufficient to identify the serialized value.
Source: raw RIP-relative reference scan and `reroller_seed_serialization.txt`.
Do not infer seed persistence merely from that string.

## Next human step and prototype boundary

A normal user-driven game relaunch, returning to the same planet and
difficulty, is a meaningful next observation: unlike difficulty/planet
navigation, initial operation fetching and zero-seed initialization contain
actual seed-changing code. This is an inference to test, not a promise that
every relaunch always rerolls. Do not abandon or launch an operation.

After relaunch, reacquire module/board addresses and read both canonical and
snapshot seeds, active operation identity/statuses, and two matching complete
operation/mission snapshots. Compare seeds and generated choices; confirm
the active operation survived independently of other choices changing.

A future preserving reseed prototype needs the ordinary request/refresh
state machine and ownership established, build/byte guards, stable host and
planet context, no pending operation mutation, and proof that dirtyflag2
reaches the normal snapshot refresh. Any private RW mutation must restore
only state still owned by the mod and account for publication/replication;
blindly reverting a published seed could conflict with newer native state.
Those conditions are not satisfied by this research. Keep native writes and
calls disabled. The read-only decoder and filter preview can proceed.
