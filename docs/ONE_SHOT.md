# Single native reseed experiment 0.1.1

## Completed live test

On 2026-09-28 the user reported a visible mission refresh. The 0.1.1 log confirms
`PROBE_COMPLETE native_calls=1`: seed 849821765 became 1905939636, 30 operation
records changed, mission bytes changed, and the entire canonical 92-byte active
operation stayed identical. The probe observed forty stable post-call samples.
The loader logged `mods/ipodalexei/mission_reroller_probe: loaded`. This is the
first successful supervised native invocation; no retry or forced refresh was
used. The 30-record metric compares whole display records, not necessarily 30
semantically different operations.

A subsequent read-only capture in session `39440-900549890` confirmed canonical
seed 1905939636 and the same active bytes. Both capture passes agreed, but the
map was no longer the top screen. The strict operation decoder correctly
rejected this capture; it is not a validated matching snapshot. Raw capture:
workspace `dumps/build-25480438/mission-reroller-one-shot-after.json`, excluded
from the repository and packages.

This establishes one successful local generation/publication test in the
supervised solo-ship context. It does not establish server acceptance, repeated
reroll safety, general host detection, complete legal options, modifiers or
constellation matching. The authorized single native experiment is consumed;
disable the probe rather than repeating it. The historical test procedure below
documents that completed experiment, not a request for another invocation.

Version 0.1.0 stopped before any native invocation because a backend request
was pending when the map opened. A subsequent read-only check in session
`24888-900361609` found the queue count at zero. Version 0.1.1 waits for ordinary
pending requests (counts 1..64) instead of permanently stopping. Every busy
sample resets the stability window and disarms the hotkey. Invalid counts still
stop the probe. The queue must be empty at the trigger's final snapshot too.
After an invocation the original 30-second observation deadline remains in
force, including while requests are pending; no retry is added.

The transient-queue regression reproduced the original permanent stop, then
passed with this fix. Persistent queue, successful publication, missing
publication, active-record change, page failures and hotkey checks also pass.
At that revision's packaging time native execution remained untested: neither
preflight nor the 0.1.0 probe called the helper in-game. The later 0.1.1 result
is recorded above.

The user approved the narrow exception for the native helper's module-owned RNG
update. Preflight 0.1.1 subsequently completed ten stable samples in-game on
planet 268, thread 21828, source-owner count 1, destination count 0, union 1.
Both installed module hashes and helper bytes passed. No native calls occurred.

## Human test

1. Disable/remove Mission Reroller Preflight, and import
   `releases/Mission-Reroller-One-Shot-v0.1.1.zip`. Keep Bingus Shared Loader enabled
   and the winning startup override. Purge / Deploy and relaunch normally.
2. Alone on your own ship, open the map, select an available planet, and stay
   there for 15 seconds. Do not start a mission or invite anyone.
3. With the game focused, press and release **Ctrl+F8 once**. The trigger is
   accepted only after stable checks and a released chord have been observed.
4. Stay on that planet for 35 seconds without selecting/launching a mission,
   then tell the agent you are ready. Do not retrigger or relaunch to retry a
   failed test. The agent will inspect `MissionRerollerProbe.log`.

There is no button or continuous reroll loop yet. After the test, disable this
diagnostic. It permits at most one native invocation per game process; relaunch
would reset that limit, so do not use relaunches to repeat this experiment.

## Guard and observation boundaries

The call uses build 25480438 helper RVA 0x12d5670 with arguments `(board,1,0,0)`.
The fourth argument bypasses the active-operation clearing branch. Native code
advances the shared RNG, changes the canonical seed, and marks owners dirty.
No code patches, explicit memory writes, startup resets, backend requests,
forced refreshes, or RNG rollback are implemented.

The probe verifies module hashes, code bytes, map/caches, backend ready state,
zero pending request count, transition gates, owner bounds, writable target
pages, repeated snapshots and update-thread consistency. It rechecks the helper
bytes and snapshot immediately before its single call. It checks the full
active record immediately afterward and on each later update. A 30-second
timeout stops without retry. A passing observation requires a changed seed,
changed operation bytes, and forty stable samples at quarter-second intervals.

These guards do not prove exclusive board-thread ownership or eliminate races.
The native call remains an experimental ABI invocation; Lua `pcall` cannot
guarantee recovery from a native crash. Same-thread sampling is evidence of
consistency, not proof of safe native ownership. The RNG advance is not safely
reversible. Snapshot change alone does not establish backend acceptance or
complete legal-option/constellation coverage.

## Offline validation

`python -B tests/test_probe.py` checks packaging and drives the actual snapshot
and control flow against synthetic process reads, substituting the native call.
Cases cover success, missing publication/timeout, active-record change, pending
requests, invalid pages, held hotkeys and focus changes. Native execution and
game publication are deliberately not claimed as tested by this harness.
