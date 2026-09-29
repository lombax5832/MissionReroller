# Reseed synchronization versus backend requests

Investigated 2026-09-28 against the saved build 25480438 images and read-only
Memory Explorer session `18648-906202953`. No game memory writes, native calls,
debugger attachment, new rerolls, or network interception were performed in
this investigation. The earlier packet capture contained 59 user-driven reseeds.

## Finding

The recovered seed synchronization path uses the session participant transport,
not the backend HTTP request queue. In the currently inspected solo session,
the participant and transport destination both resolve to the local player.
The final send routine handles that destination by copying bytes to an in-memory
receive queue, bypassing the external-send branch.

This is strong static-plus-live-state evidence for local loopback of this
specific path. It is not a dynamic trace of every instruction during a reroll,
nor proof that all downstream listeners, periodic work, or later mission
selection/activation are free of server effects. It must not be generalized to
multiplayer: different recipients reach the external-send branch.

## Recovered chain

RVAs refer to game.dll unless labeled executable.

1. The mod invokes `0x12d5670(board,1,0,0)`. It advances the local RNG, writes
   canonical seed `board+0x78e84`, and marks owner entries dirty via `0x12d57e0`.
2. Board tick `0x12cf280` and the related `0x12cff90` process owner entries via
   `0x12d5ac0`. The first synchronization message (`0x8532b643`) contains the
   campaign seed as one of seven serialized fields. Recipient is the owner ID
   in the entry, not a backend URL. Other messages can accompany this sync.
3. Sender `0xbde430` dispatches through the live session transport interface.
   Its single-recipient slot resolves to executable `0x3502c0`, which calls
   executable `0x34ff40` to serialize an RPC and submit it to the active transport.
4. The live active transport resolves to executable `0x293f50`. Depending on
   message flags, it queues or immediately dispatches through `0x28d390` to
   executable `0x2aa350`, which queues connection data.
5. Connection creation (`exe 0x2a4cb0`) sets `connection+0x187dc` when source and
   destination identity fields at +8 and +16 are equal. Live reads found both
   equal and that flag set. Sender `exe 0x2a9850` uses the local transport identity
   at connection+0x18 for this branch when the alternate transport is present.
6. The selected transport method resolves to executable **`0x76f630`**. If the
   destination equals `transport+0x590`, it appends a record to the array at
   `transport+0x6f0` (count +0x6e8, stride 0x4b8), copies the bytes, and records
   their length at record+0x4b4. The unequal-destination branch invokes the
   external interface at transport+0x538 instead.
7. Live reads confirmed the connection destination used by that branch equals
   `transport+0x590`. The first 32 bytes of the live `exe+0x76f630` routine exactly
   matched the saved image used for decompilation. This is a narrow entry-byte
   cross-check, not a new full-module hash validation.

Additional live observations: board owner and session local owner matched; the
participant transport table and lower connection table each contained one entry;
the entry matched the local owner. Backend state was 14 (ready), and pending
HTTP count was zero at two sampled instants. Those instantaneous queue reads do
not establish that no requests occurred between reads.

## Independent HTTP work

The same normal board tick contains separate timer/state-driven HTTP builders:

| Builder RVA | Request ID | Route format |
|---|---|---|
| 0x12ba390 | 0xb31ac0d3 | `%s/WarSeason/%d/Status` |
| 0x12ba440 | 0x776c9501 | `%s/WarSeason/%d/warinfo` |
| 0x12ba4e0 | 0xd3565bab | `%s/WarSeason/%d/timeSinceStart` |

These call HTTP queue routine `0x12ccd20`, unlike the participant RPC path.
Their gates include timestamps, update flags, and campaign state, rather than
an unconditional request for every dirty-owner iteration. This demonstrates a
source of ordinary HTTP traffic in the relevant update loop. It does not identify
which encrypted packet exchange corresponds to which route, or exhaust all HTTP
call sites. The separate `/Operation/Reroll` wrapper remains unused by the mod.

## Relation to the capture

The capture's recurring 30-/60-second payload patterns are consistent with
background work. Continuous reseeding did not show one API exchange per call.
The local transport branch gives a concrete explanation for why publishing a
new seed need not create an external packet in this solo setup. Request contents
and any deferred effects remain unproven; neither packet timing nor this branch
alone establishes an absolute absence of official-server impact.

## Saved evidence

Raw decompilations remain outside the mod/release in ignored workspace research:

- `tools/ghidra-projects/reroller_layout_consumers.txt`
- `tools/ghidra-projects/reroller_network_transport.txt`
- `tools/ghidra-projects/reroller_dirty_tick.txt`
- `tools/ghidra-projects/reroller_rpc_transport.txt`
- `tools/ghidra-projects/reroller_rpc_send.txt`
- `tools/ghidra-projects/reroller_peer_send.txt`
- `tools/ghidra-projects/reroller_peer_local_dispatch.txt`
- `tools/ghidra-projects/reroller_platform_send.txt`
- `tools/ghidra-projects/reroller_peer_queue.txt`
- `tools/ghidra-projects/reroller_loopback_branch.txt`
- `tools/ghidra-projects/reroller_final_local_send.txt`
- `tools/ghidra-projects/reroller_local_publication.txt`

Capture-specific findings are in
`artifacts/network/20260928-044442/FINDINGS.md`. Actual player identifiers and
live pointers are intentionally omitted here; they are session-specific and
unnecessary for reproducing the offset-based investigation.
