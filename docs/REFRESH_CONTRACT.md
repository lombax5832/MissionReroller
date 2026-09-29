# Native refresh contract and preserving prototype boundary

2026-09-28, Steam build 25480438. RVAs are relative to game.dll. This is offline saved-image research, using Ghidra with `-readOnly -noanalysis`; no live calls, requests, or writes were made. Raw evidence is under `../../tools/ghidra-projects/` and is excluded from releases.

## Ordinary operation fetch is a startup stage

The complete function containing the former fragment `0x12b6be0` starts at **0x12b6570**. The PE exception entry covering `[0x12b65b2,0x12b705d)` chains to `[0x12b6570,0x12b65b2)`. Decompiling that real entry removes the fragment's unaffiliated-register ambiguity.

It receives the backend manager as its first argument. It saves current state `manager+0x702fc` into previous-state field `+0x70304`, then switches on the current state. In state 9, on first entry only, it constructs the ordinary Operation request inline (request id `0xbca6c557`, method enum 0, owner/context is canonical board `*(game+0x347cee8)`), enqueues it, clears `board+0xc0120` for `0x4310` bytes, and calls `0x12cfe20(board)`. That last function independently enqueues request `0xa531b87b` using that cleared state.

While in state 9, it polls `0x12ccf30(manager,0xbca6c557)`. Status 3 advances the shared RNG, sets canonical seed `board+0x78e84`, marks owner dirty flag 2, and sets manager state 10. Status 2 enters state 13 and records request/error details. Status 1 is pending, determined by `0x12ccf90`; otherwise the status-map value is returned.

State 10 performs another board operation and advances to 11; state 11 waits on another manager. State 12 performs substantial initialization, derives selection from the active operation, can invoke abandonment for an invalid selected planet, refreshes the full snapshot, and enters state 14. Its caller **0x12b5710(manager,dt)** calls this startup state machine only while the manager state is not 14. It also checks `root+0x10b4`, `0x12b70e0`, `manager+0x702f8`, and `manager+1` before proceeding.

Consequences: calling **0x12bf600(manager)** alone while the ship is in ready state 14 will not execute the reseed stage. Resetting startup state to 9 would replay unrelated startup effects; it is not a narrow refresh interface. The ordinary Operation success parser **0x103a500** clears all 92 active-operation bytes before reconstructing an accepted operation from the server response and can collect ids for abandonment. A GET-looking wrapper therefore is not semantically read-only from the client's perspective.

Sources: `reroller_refresh_contract.txt` (0x12b6570, 0x12bf600, 0x12ccf30); `reroller_refresh_followup.txt` (0x12b5710, 0x12cfe20, 0x103a500); `reroller_success_dispatch.txt` request branch 0xbca6c557.

## Preserving helper: exact register contract

Assembly of **0x12d5670** establishes the following Win64 argument registers:

| Register | Meaning established by instructions |
| --- | --- |
| RCX | Board pointer |
| DL | Force a new seed when nonzero |
| R8 | Unused in the helper; overwritten in the tail target |
| R9B | Clear active operation when nonzero |

A candidate FFI declaration is `void (*)(void *, uint8_t, uintptr_t, uint8_t)` with `(board, 1, 0, 0)`. This is an exact register-level candidate, not a supported public game API or a recovered source signature. The routine has no relevant result. It neither accesses a stack argument nor adjusts the caller's stack beyond its tail target's normal preservation of nonvolatile registers.

With those arguments it advances RNG `game+0x3483c38`, updates canonical seed, and tail-jumps to **0x12d57e0(board,2)**. It does not execute the active-operation clearing stores. The tail target marks each owner dirty and resets each affected entry's +8 field to zero. Neither routine checks ship state, host authority, mission progress, backend requests, or owner-array capacity.

Source: `reroller_refresh_assembly.txt`, complete instruction stream from 0x12d5670 through 0x12d58df. This strengthens the former decompiler-only ABI evidence in SEED_LIFECYCLE.md.

## Owner bounds that can be checked without guessing capacity

Source owner IDs are qwords at `session+0x162e0`, count `u32(session+0x162d8)`, with `session=*(game+0x347cef0)`. Destination entries are 16-byte records at `board+0x1f8080`, count `u32(board+0x1f80d0)`: qword owner, dword reset field, dword dirty bits.

The available bytes before the count field fit five entries. Five is a conservative layout-derived maximum, not a recovered symbolic constant. The native function performs unchecked growth for missing owners. A bounded prototype can avoid relying on growth entirely: require both counts in 1..5, unique nonzero IDs, every source ID already present among destination IDs, and readable/writable existing private pages covering the actual RNG, seed, and destination entry writes. Require stable pointers, counts, IDs, and active bytes across preflight reads. Then this call will not enter the append branch under an unchanged game-thread context. Do not treat these IDs as planet indices or assume a single owner ID proves a single human player.

Source: `reroller_refresh_assembly.txt`, 0x12d57e0 and 0x12d59d0 in `reroller_owner_consume.txt`. Despite the output filename, 0x12d59d0 is another dirty setter, not the dirty consumer.

## Concrete guard and publication gaps

An adjacent native predicate **0x12d5740** requires backend `+0x702f8 !=0`, session `+0x167e6 ==0`, root (`*(game+0x3326340)`) bytes `+0x108d/+0x1099 ==0`, root qword `+0x8e8 ==0`, and snapshot selections `board+0x17a298/+0x17a2a4 >=0`. These are useful read-only diagnostics, but their semantic names and connection to host authority have not been proven. KnowYourConstellation uses three of those bytes as forecast gating, which does not prove host ownership either.

The remaining narrow blockers are:

1. Establish a solo/local-host guard independently of forecast availability. Reading source/destination owner IDs plus the adjacent predicate is a concrete next probe, but interpreting `count==1` as solo would be a guess. A first manually supervised test can additionally require the human to verify they are alone on their own ship; general automatic use still needs native authority detection.
2. Establish safe execution on the same game thread that owns the board and shared RNG. A Lua update wrapper is the intended mechanism, but the guard must not authorize an arbitrary external-thread function invocation. The helper itself supplies no synchronization.
3. Trace the dirty-flag consumer or observe its normal tick reaching snapshot refresh. The helper marks dirty; it does not itself publish to the displayed campaign or rebuild missions. A one-shot test needs an observation window and must stop if canonical/snapshot/cache disagree. Calling full refresh 0x12d58e0 directly would add broad side effects and is not justified merely to force success.
4. Separate active operation preservation from no active mission. The 92-byte record is valid and preserved across the observed relaunch; rejecting all valid active operations would block the user indefinitely. A ship/map-only supervised test can compare the entire record before/after without abandonment. An automatic run still needs a reliable mission/transition guard, and must stop if that record changes naturally.

Any one-shot implementation must hash/signature guard this build, never clear active state, never reset startup state, never enqueue a backend reroll/fetch, and perform at most one helper call followed by read-only validation. A timeout is a stop condition, not authority to keep calling. Do not rewind shared RNG or restore a published seed blindly: other game consumers may have advanced or replicated state.

## Next meaningful human step

The completed relaunch observation is strong evidence that native seed regeneration can change generated choices while preserving an existing active operation. It does not alone prove the helper can be safely called in every session.

No further difficulty/planet/relaunch test addresses the remaining gaps. The next useful human involvement would be **installing and running a bounded, explicitly one-shot in-process diagnostic on a solo ship**, once its thread, page, owner-membership, signature, and snapshot checks exist. Its first mode should collect the guard/owner state without calling the helper. The resulting log makes the exact preconditions reviewable and enables a subsequent single preserving-call test. This research does not supply a callable release or justify enabling the continuous search loop yet.

### Follow-up live preflight supplied by the coordinating agent

The user confirmed they are alone on their own ship. The coordinating agent observed backend state14, backend+0x702f8=1, session+0x167e6=0, root+0x108d/+0x1099/+0x8e8 all zero, source-owner count1, destination-owner count0, pending request count0, map state15, selected planet268, and no highlighted operation.

For precisely source1/destination0 the assembly adds one 16-byte entry at board+0x1f8080 and changes count to1. There is no overlap with the count at+0x1f80d0. A checked union of source/destination IDs of at most5, all actual target pages writable/private, can bound this append operation without requiring preexisting membership. This relaxes the earlier no-growth preference for the supervised case, using the exact observed assembly rather than a guessed allocation.

The RNG target **game+0x3483c38 must also pass the existing-private-RW-page rule**, not just the heap board. A module data address may be MEM_IMAGE instead; if so, the current workspace constraint blocks this helper even though no code bytes are modified. Check with VirtualQuery and do not silently ignore the RNG write. A canonical-only change without snapshot refresh must stop and be reported; it does not authorize direct refresh or a second call. No native calls were made by this research agent.

### Confirmed page constraint and pending human decision

**Decision:** The user approved the narrow native RNG exception on 2026-09-28.
It applies only to the proposed single supervised helper invocation. The first
packaged stage is the read-only callback preflight described in PREFLIGHT.md;
it contains no native invocation and needs an in-game validation run.

Read-only Memory Explorer region queries in session `35980-897404406` confirmed the RNG target is committed PAGE_READWRITE (`protect=4`) **MEM_IMAGE** (`type=0x1000000`). The canonical seed and owner-entry targets are committed PAGE_READWRITE MEM_PRIVATE (`type=0x20000`). The user explicitly confirmed they are alone on their own ship.

The private-page-only workspace rule therefore blocks the proposed native invocation as presently authorized. No helper call or memory write has been performed. The concrete requested exception is limited to allowing the game's own helper at RVA `0x12d5670`, arguments `(board, 1, 0, 0)`, to advance its eight-byte shared RNG at RVA `0x3483c38` during a single supervised in-process test. This does not authorize manual module-data writes, code patches, startup-state resets, backend requests, or repeated calls. The shared RNG advance cannot safely be rolled back.

If that exception is granted, implement the hash/signature-guarded one-shot probe with a read-only preflight before enabling its manual trigger. Validate board/owner write pages and bounds, stable context, active-record preservation, and normal snapshot publication. Stop after one invocation or any failed guard; a timeout must not cause a retry or forced refresh. Thread ownership and publication remain experimental limitations, not established guarantees. No callable probe has yet been packaged.
