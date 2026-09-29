# Mission reroller research status

Date: 2026-09-28. This is an unfinished implementation, not a tested game mod.

## Confirmed requirements

The requested entry point is a button after choosing an available planet,
before choosing a mission. Its dialog must offer currently legal missions,
operation modifiers and constellations. It should search normal generated
operations and stop on a match. User clarification: requiring Launch ICBM and
Geological Survey means both inside one operation, with any remaining slot
unrestricted. Matching those types in separate operations is insufficient.

## Primary evidence

The imported first-party reference is
[KnowYourConstellation](https://github.com/CowboyBingus/KnowYourConstellation),
commit `46cb418efe913f472509d0382535407242af2e39`. See the separate
[constellation findings](CONSTELLATION_RESEARCH.md) for exact references.

The installed binaries were hashed directly and match that commit's build
25480438 pins:

- EXE: `F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06`
- game.dll: `2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E`

Offline research uses the saved `../dumps/build-25480438/game.dll.unpacked.bin`
and the `HD2-25480438` Ghidra project. Generated disassembly remains outside this
repository in `../tools/ghidra-projects/reroller_*.txt`. No external process
attachment, live native invocation, endpoint request or game-memory write was
performed.

The binary contains `%s/Operation/Reroll` at RVA `0x22c13d8`. The function at
RVA `0x12bfe90` builds a request with dispatch ID `0xf64c89ff`, kind 1 and value
30, formats that route, stores its second argument in a context field and
passes the request to `0x12ccd20`. The meanings of request fields must be
established from their consumers, not inferred solely from the endpoint name.
This is evidence of a native request path, not a verified user-callable reroll
API. See [native findings](NATIVE_REROLL_RESEARCH.md).

## Live access limitation

Resolved on the subsequent 2026-09-28 retry: native MCP status, module bases,
region queries and bounded reads all succeeded with Memory Explorer 0.1.1 in
read-only mode. The board global at game.dll RVA `0x347cee8` pointed into a
committed private read/write region. Its selection fields read planet index
268 and local selection index 0. The screen manager at RVA `0x347ce28` had
one screen-stack entry, value 15 (the reference reader's map screen). These
are separate-frame observations, not an atomic operation snapshot or proof
that the reroll path is callable. No memory writes or native calls occurred.
Session addresses are intentionally omitted from this repository.

Historical connection failure:

The Memory Explorer tool names appeared during initial tool discovery, then
became unavailable to this chat. A fallback using its existing Python `Bridge`
was refused by the server's exclusive lock: `Another Memory Explorer server
owns this bridge`. That lock was respected. No bridge request was sent and no
live memory facts were claimed from that failed attempt. The game being launched
was not the issue. Do not run two bridge clients or remove the lock.

## Completion gates

Progress on gate 2: the complete operation/mission table mapping is now
established from native field writers and live read-only data. See
[operation layout](OPERATION_LAYOUT.md) and [live validation](LIVE_VALIDATION.md).
The user subsequently confirmed the difficulty10 mission combination, and the
follow-up capture selected the predicted row28. All30 operation records and
their72 mission seeds remained identical across the difficulty/hover change.
The subsequent planet round trip also preserved every operation record. The
equivalent Lua decoder now agrees with Python on all three live captures.
Normal relaunch subsequently changed the campaign seed and 29 of 30 operation
rows while preserving the complete active-operation record and its mission.
The fourth capture also passed the Lua/Python replay. See live validation for
the observation's limits; an in-session native refresh is not implemented.
`scripts/inspect_operations.py` decodes two matching read passes and rejects
changed sessions, stale cache state, malformed counts, mismatched owners,
difficulties, ordinals and statuses. It deliberately emits research-only output,
not a matching-ready native adapter snapshot. Full constellation/modifier
resolution and UI correspondence remain unverified.

1. Find the native user/state transition that regenerates operations. Determine
   whether it affects a selected planet or all operations, what it sends, how
   it receives results, and how it preserves an in-progress operation. Identify
   native eligibility and request throttling; endpoint presence alone is not
   enough.
2. Read all missions in one generated operation with consistent context and
   identity. Resolve their full constellation rules, including level data.
3. Derive legal options and display names from current campaign, faction,
   planet and difficulty rules. Do not promote a historical name list to a
   legal-option catalogue or claim every combination is feasible.
4. Implement an adapter with build hashes, byte signatures, bounded reads,
   verified calling conventions, context rechecks and error handling. Any data
   writes must follow workspace private read/write-page constraints.
5. Implement a clickable native dialog, input capture, cancel and progress
   display; protect existing callbacks and coexist with constellation overlays.
6. Build/test, then user-driven deployment and in-game validation. The user
   launches the game. Verify visible behavior and loader/mod logs, not just
   successful initialization. This gate is not satisfied.

The supervised one-shot probe subsequently passed in-game: one native helper
invocation changed the seed and displayed missions while preserving all 92
canonical active-operation bytes. See ONE_SHOT.md for exact evidence and limits.
This establishes that narrow native integration milestone, not backend
acceptance, repeated search safety, operation legality or filter UI behavior.
