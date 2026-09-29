# Native reroll investigation

2026-09-28; offline saved build 25480438 DLL only. No live request, memory
write, debugger attachment, or game-file change was performed. Ghidra used
`-readOnly -noanalysis`; raw analysis output remains under `tools/`, outside
the mod/release. Image base in the dump is `0x7fffbe270000`; addresses below
are RVAs.

## Confirmed native request wrapper

Function **`0x12bfe90`** constructs a 0xC60-byte request descriptor:

| Offset | Value |
| --- | --- |
| +0x04 | request identifier `0xf64c89ff` |
| +0x08 | method enum 1 (HTTP verb not independently confirmed here) |
| +0x0C | formatted route `%s/Operation/Reroll`, prefix from manager +0x44 |
| +0xC10 | remains zero; no JSON/body object is constructed |
| +0xC18 | 0x1E, likely timeout/budget; exact semantics unconfirmed |
| +0xC20 | function's second parameter, a context/owner field |

It calls generic enqueue function **`0x12ccd20`**. Crucially, the second
parameter is **not a request payload**: other request builders store JSON at
+0xC10, while completion handlers use +0xC20 as their caller/owner context.
No planet id, difficulty, seed, mission list, modifier list, or operation id is
serialized by this wrapper.

Local evidence: `../../tools/ghidra-projects/reroller_backend.txt`, function
0x12bfe90; `reroller_serialize.txt`, function 0x12ccd20;
`reroller_payload.txt`, function 0x12c2400 (independent request body example);
`reroller_dispatch.txt`, function 0x12c38f0 (context use).

## Generic restrictions observed

The queue routine is not a JSON serializer. It requires manager +0x31C70 to be
nonzero and caps pending requests at **64**, stored at manager +0x448 with
0xC60 stride and count +0x31C48. A fixed request-id allowlist can bypass one
manager flag, but reroll's `0xf64c89ff` is **not** in that allowlist: the reroll
path requires manager byte +3 nonzero. This flag appears to concern backend
session/authentication state, but its exact meaning is not established.

Queue admission can produce status 1 for the flag rejection, status 2 for a
full queue, and an optional status 3 path driven by manager +0x3CDD4 and RNG.
The generic error routine also handles HTTP 401 by clearing manager byte +3.
These are native client admission conditions, not proven reroll-specific
costs, limits, cooldowns, host restrictions, or server authorization rules.

Local evidence: `../../tools/ghidra-projects/reroller_serialize.txt`
(0x12ccd20) and `reroller_dispatch.txt` (0x12c38f0).

## Caller and response tracing results

An offline scan of the saved DLL code range found **no direct E8 call or E9
jump targeting 0x12bfe90**. A full-image scan found no absolute pointer to its
loaded address. Searches for the little-endian request id `0xf64c89ff` found
only the wrapper immediate at **0x12BFECF** and one entry in an enum-like
constant table at **0x21CFAD4**. Searches for the function RVA found only
unwind metadata entries at **0x389413C** and **0x408F548**, not a demonstrated
dispatch table. The exception directory confirms the wrapper's range
`[0x12BFE90, 0x12BFF32)`.

The generic error dispatcher 0x12C38F0 and success dispatcher **0x12C50D0**
were decompiled. Neither recovered dispatcher has a branch naming this
reroll id. In contrast, the ordinary operation-fetch request id `0xBCA6C557`
has an explicit success path that parses returned operations and may invoke
the abandon helper. No reroll-specific response schema or refresh callback
has been established.

Local evidence: `../../tools/ghidra-projects/reroller_dispatch.txt`,
`reroller_success_dispatch.txt`; integer, pointer and rel32 scans of
`../../dumps/build-25480438/game.dll.unpacked.bin`. Negative scan results
cannot exclude indirect/computed calls, other modules, transformed ids, or
code not represented in this saved dump. Do not claim the endpoint is unused
with certainty.

## Avoid a misleading adjacent-string inference

The nearby **`operationIds`** JSON field at 0x22C13F0 belongs to
**`%s/Operation/Abandon`** at 0x22C1400, request id **0x3D5D7633**. That builder
creates an array of integer operation ids. It does **not** establish the
reroll payload. The reroll URL is the separate string at **0x22C13D8**.

Local evidence: `../../tools/ghidra-projects/reroller_payload.txt`, recovered
block beginning 0x12BFBC2. This is a split-function block with unaffiliated
registers in its decompilation; the string references and constructed request
id are direct observations, not a fully recovered callable signature.

## Conclusion for implementation

There is native code capable of enqueuing a request named Operation/Reroll,
but this research does **not** establish a normal player-accessible trigger,
that the server supports it for ordinary players, its consequences, or how
the client accepts resulting operations. No usable reroll driver is justified
by this evidence alone. In particular, do not call the wrapper with a guessed
context pointer or invent a JSON payload.

A safe next step is to identify an existing native event/UI/refresh pathway
and its owner lifetime, or observe an already-authorized normal refresh using
read-only instrumentation. Any implementation still needs bounded request
cadence, cancellation, backend error handling, complete candidate snapshots,
and proof of host/planet/difficulty restrictions. Those are implementation
requirements inferred from the asynchronous native queue, not confirmed
features supplied by this request wrapper.
