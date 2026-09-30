# In-mod prediction: first read-only checkpoint

## v0.9.1 automatic backend wait

The v0.9.0 test at baseline seed 114241922 confirmed a planet-100 match after
45 candidates: seed 114241967, row 28, mission types 59 / 81 / 65. The match
remained read-only. Two other planet-100 attempts cancelled with zero completed
candidates because the context guard treated `waiting for pending backend
requests` as a fatal context loss. Planet 268's logged attempt was cancelled by
shortcut/shutdown after 20 candidates; that log does not establish a backend
failure on planet 268. Maximum measured work slices were 78–109 ms.

v0.9.1 treats only the pending-backend reason as transient. The job pauses,
polling at most four times per second, and waits for the queue to remain idle
for 0.5 seconds. It then revalidates the entire immutable read set before
continuing the suspended coroutine. A result completed just before a busy
post-work check is held until this revalidation completes. Changed bytes,
changed board/planet/snapshot, a closed map or other context failures still
reject the job. Waiting does not replace captured inputs or automatically
restart a search against a different campaign state.

Waiting is limited to 60 seconds per continuous pause and 120 seconds total.
Wait time is excluded from the existing 180-second active-search timeout.
The shortcut still cancels, including while waiting. The initial baseline
capture retains its existing bounded wait/retry behavior.

Regression tests reproduce a transient failure with no second keypress and
confirm automatic resume, zero candidate evaluation while busy, held-result
revalidation, stale-result rejection, cancellation and bounded waiting. Package
checks and existing predictor tests pass. The code still only observes the
game's request queue; no network request or seed publication is introduced.

Next human test: replace v0.9.0 with
`releases/Mission-Reroller-Lua-Search-Probe-v0.9.1.zip`, Purge / Deploy, and
restart. On planet 100, press Ctrl+Shift+F9 once and leave the planet selected
until a terminal search log appears (up to five minutes including waits).
Repeat on planet 268. If ordinary backend activity occurs, expect
`LUA_SEARCH_WAIT` followed by `LUA_SEARCH_RESUMED`, without another keypress.
Do not press the shortcut again unless intending to cancel. Report completion;
the map still does not refresh or auto-select in this read-only checkpoint.

## v0.9.0 cooperative search checkpoint

Package: `releases/Mission-Reroller-Lua-Search-Probe-v0.9.0.zip`.
The same shortcut first runs the v0.8 independent baseline checks. Only if the
identity, level and independent composition checks all pass does it start a
read-only search for **Launch ICBM + Geological Survey + Eradicate**, difficulty
**10**. These three families must appear within one operation; other mission
slots remain unrestricted. This diagnostic uses a fixed filter and does not
restore the dialog yet.

The search starts at the current campaign seed plus one (wrapping uint32), with
a 256-candidate limit and a 180-second search timeout. One coroutine owns each
job and yields every 512 reader checkpoints, and between candidates. Cancel
discards the job. Alt-tab does not cancel it. No native generator, refresh,
publication or selection is called by this package.

`frozen_prediction_reads.lua` retains immutable bytes indexed by numeric address
and size, capped at 20,000 entries / 2 MiB. It permits new candidate branches to
extend the read set but never replaces already captured bytes. Before accepting
each candidate, all collected ranges are re-read and compared. Board identity,
planet and the complete snapshot fingerprint are checked before and after every
coroutine resume. Any mismatch stops the job. These checks detect changes; they
do not provide an atomic snapshot across game threads.

`candidate_predictor.lua` caches seed-independent decoded metadata and level
graphs within that frozen context. Their original byte dependencies remain in
the read set. Candidates do not use displayed operation bases or mission seeds;
the canonical active operation remains preserved input. Newly encountered
unsupported or invalid generation stops the search rather than skipping an
unverified prediction. Existing campaign support restrictions still apply.

Validation completed before packaging:

- The actual packaged cached predictor matches 32 saved native-oracle boards,
  including seed 4: 960 operation bases and 2,304 full mission descriptors.
- The packaged cooperative search finds seed 4, row 29, after five candidates
  starting at zero in the saved planet-268 context. A separate native Unicorn
  replay confirms mission types 81 / 59 / 65 and all predicted descriptors.
  That is Survey / ICBM / Eradicate at difficulty 10.
- The saved planet-100 context also produces a matching candidate (seed 0,
  row 29). That new-seed result has no separate native replay; the captured
  baseline continues to match all 40 bases and 96 mission descriptors.
- Decoded-rule caching reduced the ordinary-context run from 4,319 cooperative
  slices to 154; the special-context run took 262 slices. Measured largest
  offline slices varied up to 45 ms, so this is a work budget, not a guaranteed
  frame-time bound. In-game duration and responsiveness remain to be measured.
- Tests cover same-operation matching, immutable filter options, seed wrap,
  memory bounds, changed input rejection, context loss before/after work,
  baseline rejection, candidate exhaustion, cancellation, timeout, background
  progress and shutdown. Existing identity and package checks pass. The ZIP
  excludes captured data, emulator dependencies and publication APIs.

### Next human test

1. Replace v0.8.0 with the v0.9.0 search probe, Purge / Deploy with the loader
   winning startup, and restart the game.
2. Alone on your ship, open planet 100 and press **Ctrl+Shift+F9** once. Leave
   that planet selected for up to **three minutes**. Alt-tab is supported.
3. Repeat on planet 268 after the first search completes. Pressing the shortcut
   during an active search cancels it. Report completion and any noticeable
   stuttering. No mission refresh or automatic selection should occur.

The log should show the baseline PASS records, `LUA_SEARCH_STARTED`, progress
every five seconds while running, then `LUA_SEARCH_MATCH`, `LUA_SEARCH_EXHAUSTED`,
`LUA_SEARCH_CANCELLED` or `LUA_SEARCH_FAILED`. Matches include candidate seed,
row, mission descriptors, attempts, read-set size and maximum slice duration,
with `published=false selected=false`. This checkpoint tests the in-game search
and input lifecycle before reconnecting publication and automatic selection.

## v0.8.0 independent seed prediction

`operation_base_inputs.lua` supplies IDs/seeds/difficulty through the existing
identity generator and derives faction, category and explicit-template inputs
from campaign records. It resolves the supported special category from its
bound definition, including category 14's normal non-invasion fallback. It
preserves the canonical active operation, including its original explicit hash,
template and modifiers. Displayed operation rows are comparison outputs only.

Support is deliberately bounded: one enabled normal campaign event, no defense
event or planet invasion, a nonzero difficulty cap, supported special faction
resolution, and no unresolved conditional or operation-suppressing world
modifier sources. These unsupported cases reject capture; this is not a general
generator for every campaign state. The old seed-assisted level diagnostic is
still logged separately; the independent composition pass does not use observed
mission seeds or operation bases to predict its result.

Validation:

- The actual packaged predictor matches 31 saved ordinary-planet boards:
  930 operation bases and 2,232 full mission descriptors, templates and modifiers.
- A fresh guarded MCP capture on planet 100 in session `20320-961053437`, seed
  373592754, matches all 40 operation bases and 96 mission descriptors, including
  special rows 50–59 with category 9. Re-reading all 2,500 consumed input ranges
  found no changes; the guards are consistency checks, not an atomic snapshot.
- Three additional native helper signatures are pinned from the live module.
- Altering observed operation or mission seeds changes only the comparison;
  captured prediction inputs remain unchanged. Disabled planets, absent normal
  events, defense events and invasions reject the real input decoder in tests.
- Full special-event records contained changing progress counters at offsets
  12 and 28. Capture now reads only planet, eligibility, ID and faction fields;
  a regression verifies that unrelated progress does not change the fingerprint.
- `seed_search.lua` implements bounded sequential candidates, uint32 wrap,
  cancellation and error termination. It uses the existing operation-wide mission
  matcher. Tests cover split-operation rejection, budgets and cancellation, and
  Survey + ICBM + Eradicate decisions match all 31 saved boards plus the live
  capture. This search controller is not yet included in the deployed probe.

### In-game result

The v0.8.0 loader, build hashes and function signatures passed. At campaign seed
1764573301, the log records three complete successful checks in order: planet
100, planet 268, planet 268. Planet 100 matched all 40 operation bases, templates
and modifier sets plus 96 mission descriptors. Both planet-268 checks matched
all 30 bases, templates and modifier sets plus 72 mission descriptors. Each run
reports identity, level, composition and `LUA_SEED_PREDICTION_PASS`, with
`observed_operation_bases=false`, `preserved_active=true` and `read_only=true`.
No retry, timeout, mismatch or stop occurred. This checkpoint is complete for
these planets and campaign inputs; unrestricted campaign support is not implied.

### Test procedure (completed)

Install `releases/Mission-Reroller-Lua-Probe-v0.8.0.zip`, replacing v0.7.1.
Purge / Deploy with the loader winning startup, then restart the game. Alone on
your ship, select planet 100 and press Ctrl+Shift+F9 once. Leave it selected for
30 seconds. Repeat on planet 268, then report completion.

No refresh or selection is expected. The new checkpoint is
`LUA_SEED_PREDICTION_PASS ... observed_operation_bases=false`, alongside the
existing comparison logs. The next integration is a frozen-input, bounded
candidate search followed by the
existing publication/selection flow. Input freezing and context revalidation
across a multi-frame search still need integration before any seed is published.

## v0.7.1 live failure diagnostic

The v0.7.0 game run passed module loading, build hashes and function signatures.
For seed 3648242517, capture failed on planet 100 and subsequently planet 268
at bundled line 1161: `attempt to compare number with nil`. Sixty rejected
captures exhausted the timeout. The logs show one arming event, so the planet
changed during that attempt; both planets encountered the same error.

The exact packaged composition factory still matches the saved 31-board oracle
and the previous live planet-100 capture, including when module addresses are
FFI pointers. This has not reproduced the live failure. No root cause or fix is
claimed. The earlier tests mocked runtime capture, so they did not establish
that every in-game integration path worked.

v0.7.1 adds a decoded-operation difficulty guard and a `[COMPOSITION_INPUT]`
diagnostic containing planet, operation row, template, mission and both bounds
when a difficulty operand is missing. Capture errors include a stack trace if
the game's debug library permits it. The read-only behavior, retries, stable
capture requirement and timeout remain unchanged. Tests cover diagnostic
rejection of a missing decoded difficulty and the real packaged factory.

The first v0.7.1 in-game test passed on planet 100 at seed 373592754. The loader
reported the module loaded, and build hashes and function signatures verified.
The log contained one arming event followed by:

```text
LUA_IDENTITY_PASS planet=100 seed=373592754 pool=35 special_events=1 matched=40 live=40 predicted=40
LUA_LEVEL_PASS checked=96 category_draws=56 observed_seed_assisted=true
LUA_COMPOSITION_PASS planet=100 operations=40 templates=40 modifiers=40 missions=96 observed_mission_seeds=false scope=operation-base-inputs
```

No capture retry, timeout, mismatch or stop appeared in this run. This validates
the combined Lua stages for these inputs; it does not identify the earlier
failure's cause or prove a fix.

The follow-up log confirms four successful runs in order: planet 100, planet
268, planet 268, planet 100, all at seed 373592754. Both planet-268 checks match
30 operation identities, 30 templates, 30 modifier sets and 72 mission
descriptors; both planet-100 checks match 40/40/40 and 96 respectively. Every
run reports identity, level and composition PASS, with no retry, timeout,
mismatch or stop. The requested combined eligibility/category/finalization
checkpoint is complete for these two planets and this campaign state.

Next development milestone: independently generate the remaining operation
base fields for candidate campaign seeds, then connect composition prediction
to a bounded in-Lua filter search. Validate that path read-only before
reconnecting the existing seed publication and automatic-selection flow.
Constellations and unsupported conditional generation branches remain separate
unfinished work; this checkpoint does not establish general seed-search support.

## v0.7.0 combined composition checkpoint

Package: `releases/Mission-Reroller-Lua-Probe-v0.7.0.zip`.
This combines mission eligibility, category selection and operation finalization
with the existing RNG, level selection and weighted mission picker. It predicts
template index, operation modifiers, mission count, mission type, mission seed
and level index for every populated operation in the viewed planet's cache.

The composition pass takes operation IDs, seeds, difficulties, categories,
factions and explicit template hashes as base inputs. The identity pass still
checks IDs/seeds/difficulties separately. Observed mission seeds are comparison
outputs only in the new pass; the older seed-assisted level diagnostic is retained
as a separate cross-check. A canonical in-progress operation's template and
modifiers remain preserved inputs. This is not yet an independent generator of
every operation base field from an arbitrary campaign seed.

Validation before deployment:

- 256 native eligibility cases, 256 category cases and 256 finalizer cases pass.
  These isolate dependencies; the captured-board tests below exercise integration.
- Native traces match 2,082 configuration lookups, 1,089 effect collections,
  971 enable checks, 72 category choices with decoded pools, and 29 template lists.
  Requested effect collections in the ordinary fixture are empty, so these counts
  do not establish coverage of every nonempty campaign-effect branch.
- 31 saved boards match 2,232 full mission descriptors, templates and modifiers.
- Fresh MCP capture on planet 100, session `20784-956209796`, matches 96 full
  mission descriptors. All 2,403 consumed input ranges were re-read unchanged
  under selection/cache guards; this is consistency evidence, not an atomic capture.
- All eight newly pinned function signatures match the live game.
- The actual composition capture wrapper passes both datasets. Changing an
  observed mission seed produces a mismatch without changing prediction inputs.
- Runtime tests exercise composition success/failure, retain separate level
  failures, retries, timeout, background progress and update/shutdown returns.
  Package checks pass and exclude captures, emulator dependencies and write APIs.

The decoder checks objective scope before reading progress, so unrelated changing
progress cannot prevent a stable capture. Weighted mission usage resets per
operation, as confirmed by the native trace. The category-6 defense template
gate deliberately remains unsupported and produces diagnostics. (Conditional
world modifiers with environment tags were also refused until v0.22.1, which
ports the world-modifier collector; see [HISTORY](HISTORY.md).) Constellation prediction and general
new-seed search/publication are not enabled.

### Next human test

1. Replace the previous Mission Reroller probe with v0.7.0, keep Bingus Shared
   Loader as the winning startup override, Purge / Deploy, and restart the game.
2. Alone on your ship, open planet 100 in the galactic map and press
   **Ctrl+Shift+F9** once. Leave that planet selected for up to 30 seconds.
3. Select planet 268 and repeat, then repeat once on each planet if available.
   Alt-tabbing after arming the check is supported.
4. Report completion. No visual refresh is expected. Inspect the loader log for
   successful module loading and `MissionRerollerExperiment.log` for
   `LUA_IDENTITY_PASS`, `LUA_LEVEL_PASS` and `LUA_COMPOSITION_PASS` for each run.
   The composition record includes templates, modifiers and mission counts and
   `observed_mission_seeds=false`. Preserve retries/mismatches/STOPPED diagnostics.

This version is not yet validated in-game. Passing the new checkpoint supports
the tested planets and current campaign inputs, not every generation branch.

The runtime architecture is entirely inside the Lua addon, as requested. The
offline Unicorn emulator remains a development oracle; it is not shipped or
called by this addon. No companion, candidate manifest, captured binary, or
Python installation is needed to run this test.

## Original v0.6.0 scope

`generation_rng.lua` reproduces the generator's 64-bit multiply/add and high-word
output using LuaJIT uint64 values. The campaign seed plus planet wraps at 32 bits
before being widened. Converting the entire state to a Lua number would lose
precision. The captured double scaling constant is exactly 1 / 2^32.

`operation_identity.lua` ports the shared operation-ID and seed selection loop
in generator functions 0x11e3c10 and 0x11e4060. It preserves the snapshot's active
operation, consumes RNG draws in the observed order, scans cyclically for an
unused ID, and falls back to per-difficulty exclusion when the global pool is
exhausted. The exclusion helper includes four rows, including the following
difficulty's first row. Input tables are not mutated.

This is a partial port: it does not evaluate generation-branch eligibility,
operation-finalizer validity, mission composition, modifiers, or constellations.
It models ten difficulties and compares every populated row with the live board.
Special operations, a reduced difficulty cap, or rejected definitions can produce
a diagnostic mismatch. A PASS verifies the compared IDs/seeds/difficulties in
that context; it does not establish complete descriptor prediction or support
for every planet. This build cannot search for a mission filter or publish seeds.

The probe reads cached planet definitions and the display snapshot in process
through the existing ReadProcessMemory adapter. It takes two equal captures and
requires four stable polls, with a 30-second timeout. It checks the pinned module
hashes, generator code digests, and RNG constant. It continues an armed check
while the user is alt-tabbed. There are no writes to game memory, native generator
calls, selection calls, or requests introduced by this test.

## Validation completed before packaging

- 1,800 outputs checked against exact Python integer RNG calculations, covering
  zero, signed boundaries, uint32 maximum, and seed-plus-planet overflow.
- 31 saved/emulated seed cases matched all 930 operation identities, including
  seed 0, 1, 2147483647, 2147483648, and 4294967295.
- A fresh pair of matching MCP captures in session `24072-913054796` matched all
  30 current operation identities for planet 268, seed 569798162. This ran LuaJIT
  outside the game against captured data; execution inside the game is pending.
- Generator code digests were also compared with the current live code.
- Stubbed runtime/package tests cover changed code signatures, cache capture,
  missing/extra/mismatched rows, stable-input gating, timeout/retry, repeated
  shortcuts, background progress, duplicate initialization, and callback returns.

The test cases and live captures remain under ignored `artifacts/`. They are not
in the package. The release uses the same module and GUID as the publication
test, so it replaces that test rather than running beside it.

## Completed 0.6.0 human test procedure

1. Replace the previous Mission Reroller test with
   `releases/Mission-Reroller-Lua-Probe-v0.6.0.zip`. Keep Bingus Shared Loader as
   the winning startup override. Purge / Deploy and restart the game.
2. Alone on your ship, open the map and select the current test planet. Press
   **Ctrl+Shift+F9**, release it, and wait about three seconds. The board should
   stay unchanged; there is no visible diagnostic dialog in this build.
3. Select another available planet, preferably of the same faction, and repeat
   the shortcut. Report when both checks are complete so the logs can be read.

Expected log in `MissionRerollerExperiment.log`:

```text
LUA_IDENTITY_READY signatures=verified read_only=true
LUA_IDENTITY_PASS planet=... seed=... pool=... matched=30 live=30 predicted=30 ...
```

`LUA_IDENTITY_MISMATCH` includes the differing rows for further porting work.
`LUA_IDENTITY_BLOCKED` is a stable-capture timeout and allows another shortcut.
`STOPPED` is a guard/read error; preserve that log before restarting. The loader
log must also show `mods/ipodalexei/mission_reroller_experiment: loaded` before
this checkpoint is considered validated inside the game.

After this checkpoint, port the operation finalizer and mission selector, compare
their full descriptors against the oracle, and only then connect the evaluator
to the filter dialog and the already-verified publication/selection transaction.

## Observed results and 0.6.1 correction

The loader confirmed the module loaded. On 2026-09-28 the in-game log recorded:

```text
LUA_IDENTITY_PASS planet=268 seed=1754223445 pool=35 matched=30 live=30 predicted=30 elapsed_ms=0.000 read_only=true scope=IDs/seeds/difficulty
LUA_IDENTITY_BLOCKED stable map inputs unavailable; press shortcut to retry
```

The first result validates the partial predictor inside the game's Lua VM on a
new seed. The zero elapsed value is timer resolution, not a precise benchmark.
The second attempt did not reach prediction comparison.

Read-only MCP inspection in session `3212-914399953` showed selection word 0
still held ship planet 268 while word 1 and both operation/mission caches held
viewed planet 100. The inherited publication adapter compared against word 0 and
therefore waited indefinitely for matching caches. A regression against the real
adapter reproduced that timeout. Version 0.6.1 allows explicit read-only preview
snapshots using word 1, normalizes only the local decoder input, and preserves
the raw selection in the stability fingerprint. Writing adapters cannot opt in;
their original behavior is unchanged. The regression covers the full decoder,
dirty/wrong-planet cache rejection, and rejection of preview mode for writers.

Planet 100 also contains special operation rows 50–59. Its ordinary rows 0–29
all matched the Lua algorithm when checked against the captured bytes outside
the game. The special ten rows are not implemented, so a full-board comparison
on that planet should still report a mismatch. Do not suppress these rows or
claim full coverage. The fixed diagnostic is packaged locally, but another
restart solely to confirm this known limitation is unnecessary. Next development
work is the special-operation path and full descriptor evaluation. Keep the
working 0.6.0 session available for read-only research in the meantime.

## v0.6.2: special-operation checkpoint

The supported special-event branch of 0x11e44d0 is now ported. The input collector
reads active campaign-event records, their planet/operation bindings, template
IDs/pointers, planet availability, cached special-pool count, and difficulty
bounds. These are generation inputs; it does not derive eligibility from the
already-generated operation rows. Arrays and pointers are bounded and included
in the two-pass stability fingerprint. Event order matters: special rows consume
the same RNG after ordinary rows, while an occupied active row consumes no draw.
Difficulty ranges are clamped to 1–10, and duplicate events preserve earlier rows.

Two equal guarded live captures on planet 100 were passed through the actual Lua
collector and predictor outside the game. All **40 rows**, including special
rows 50–59, matched for seed 1754223445. The code signature for the special pass
is also checked at initialization. Tests cover eligibility reads, missing
bindings/templates, inactive events, unavailable planets, range clamping,
changed-input fingerprints, excessive counts, event ordering, and active-row
preservation. The earlier viewed-planet correction is included.

This remains partial identity prediction. Faction value 1 requires another
campaign resolver and is explicitly unsupported; finalizer validity and ordinary
branch eligibility are not yet ported. A full-board mismatch remains a failure,
including any extra rows. Do not discard unsupported rows to obtain a PASS.

### Completed human test

Replace the current test with `releases/Mission-Reroller-Lua-Probe-v0.6.2.zip`,
Purge / Deploy, and restart. On the second planet used previously (planet index
100), press **Ctrl+Shift+F9**, release, and wait three seconds. Repeat on the
original planet (index 268). Keep the loader as the winning startup override.
No board changes or dialog are expected; this package is still read-only.

If the campaign context is unchanged, expected results are a 40-row PASS on
planet 100 with `special_events=1`, and a 30-row PASS on planet 268. Changed live
campaign events may alter those counts; inspect the reported inputs before
assuming a regression. Confirm the loader entry and log results before enabling
this collector in the full predictor.

### In-game result: both planets passed

The 2026-09-28 v0.6.2 run confirmed the loader entry loaded, both module hashes
and code signatures matched, and the following comparisons passed inside the
game's Lua VM:

```text
LUA_IDENTITY_PASS planet=100 seed=929426942 pool=35 special_events=1 matched=40 live=40 predicted=40 elapsed_ms=0.000 read_only=true scope=IDs/seeds/difficulty
LUA_IDENTITY_PASS planet=268 seed=929426942 pool=35 special_events=0 matched=30 live=30 predicted=30 elapsed_ms=0.000 read_only=true scope=IDs/seeds/difficulty
```

There were no timeout, mismatch, or STOPPED entries in the test log. This closes
the identity checkpoint for these two contexts, including the viewed-planet
correction and supported special-event path. It does not validate full mission
composition, modifiers, constellations, or every campaign branch. No repeat test
or restart is needed for this checkpoint; next work is the remaining mission
eligibility, operation-finalizer, and level-selection stages described below.

## Mission-composition work started

`mission_weighted_choice.lua` ports the weighted-choice portion of 0x11e6340.
It requires an already-eligible candidate list and weights. It restricts the draw
to least-used types, follows candidate order, explicitly rounds float32
intermediates, and reproduces the singleton path that does not increment usage.
The caller owns the usage table; no game data is written.

An offline differential harness executed the captured native leaf function with
256 synthetic cases, including uint32 seed boundaries, scalar/vector-sized
candidate pools, unequal counts, zero weights, and float rounding edges. Lua
matched the selected type and every changed usage count in all cases. This module
is not wired into the diagnostic release and is not yet a complete mission
predictor. Candidate eligibility (0x11e5100 and 0x11e6800), operation-finalizer
selection, and level selection (0x11e6020) still need porting and validation.
The saved decompilation for those dependencies is
`tools/ghidra-projects/reroller_mission_inputs.txt` outside this repository.

The emulator is used only during development. It is not a runtime companion.
Captured fixtures and generated oracle files remain under ignored `artifacts/`.

## v0.6.3: level-selection checkpoint

`mission_level_choice.lua` ports the level-choice stage of 0x11e6020. Ordinary
operations use the ordered root/adjacent-level list. Special operations draw
from that list after the first slot and retry levels already used in the
operation. The native retry advances cumulatively by the attempt number;
substituting ordinary linear probing would change results. Empty/exhausted
candidate lists consume no RNG. The RNG module now supports copying/restoring
its own full 64-bit state through eight-byte strings, without touching game RNG.

`level_inputs.lua` reads the cached graph, selects the correct normal/special
root table, and filters adjacent nodes by the native level kind. It checks node,
edge, pool, slot, and candidate-array bounds. The probe caches repeated reads
within each capture and includes graph inputs in the stability fingerprint.
The level function's code digest is checked along with the earlier signatures.

Validation before packaging:

- 320 comparisons against the captured native level function with synthetic
  normal/special graphs, slots, usage lists, and full 64-bit starting states.
  Both selected levels and final RNG states matched, including retries and
  exhausted paths.
- 31 saved board cases: all 2,232 mission levels matched through the actual Lua
  graph decoder and verification stage.
- Two equal, guarded read-only captures in session `40460-915716812`: all 72
  levels on planet 268, seed 929426942, matched outside the game.
- Regression tests exercise graph bounds, normal/special edge filtering,
  changed-input fingerprints, RNG-state round trips, wrong-level detection,
  unsupported RNG traces, and reporting a level failure after an identity pass.

**This is stage verification, not full independent mission prediction.** The
category chooser is still unported. `level_verification.lua` tries its possible
zero/one RNG draw and uses the observed mission seed to identify that trace.
Observed level indices do not influence that decision: the ported level function
must independently produce the observed level. Ambiguous or unsupported traces
fail explicitly. This establishes graph decoding and level-choice behavior,
but does not verify candidate eligibility, mission type, modifiers, constellation,
or the ability to evaluate a new seed's complete descriptors.

### Next human test: v0.6.3

Replace the previous probe with `releases/Mission-Reroller-Lua-Probe-v0.6.3.zip`,
Purge / Deploy, and restart with Bingus Shared Loader still winning startup.
Select each of the same two planets, press **Ctrl+Shift+F9**, release, and wait
three seconds. This remains read-only: no visual refresh, selection, or dialog
is expected.

Each check should produce an identity PASS followed by:

```text
LUA_LEVEL_PASS checked=... category_draws=... observed_seed_assisted=true scope=level-selection
```

The previously observed counts were 72 missions on planet 268 and 96 on planet
100. Campaign changes may affect counts. Any `LUA_LEVEL_MISMATCH` or `STOPPED`
needs investigation. The normal graph and native special-choice logic have
offline coverage; the live special-planet graph is part of this checkpoint.

Next development after this checkpoint: port the eligibility/category stages
(including campaign/config overrides and biome restrictions) so observed mission
seeds are no longer needed, then complete operation finalization before enabling
new-seed mission-filter searches. Supporting decompilation is in
`tools/ghidra-projects/reroller_mission_eligibility.txt`, outside the mod repo.

## Development commands

### v0.6.5: pointer cache key fix

The v0.6.4 game log reported persistent failures on planets 268 and 100 for
seed 2021753643, with `root=35 nodes=35 start=35` and
`definitions=[cdata (deleted)]`. Planet 268 timed out after 60 rejected captures;
neither planet passed. Distinct pointer addresses had identical `tostring`
representations, so the per-capture cache reused the first four-byte value
(the normal pool count, 35) for subsequent four-byte reads.

Reproduced the exact root/start/count error with the real capture cache and a
saved live fixture by making pointer `tostring` return `[cdata (deleted)]`:

```powershell
& $env:HD2_LUAJIT tests/check_level_capture.lua artifacts/level-live-42812-268.lua . opaque-pointers
```

The cache now uses `tonumber(ffi.cast('uintptr_t', address))` and separate size
keys. The supported user-space address range is exactly representable by Lua
numbers. Identity, level, and special-input fingerprints format numeric pointer
values explicitly; level error messages do the same. No bounds were relaxed.

The same regression passes after the fix, as do planet 100's 96 captured levels,
planet 268's 72 levels, and all 31 saved board cases (2,232 levels), with opaque
pointer formatting enabled. A fixture-independent package regression also checks
distinct pointer values, equivalent pointer objects, different read sizes, and
fingerprint formatting. Probe package, retry, wrapper, and signature tests pass.

In-game confirmation completed on 2026-09-28, build 25480438, seed 33257715.
Build hashes and helper/generator signatures verified. Both checks below passed
twice in the same session:

| Planet | Operation identities | Mission levels | Resolved category draws |
| --- | --- | --- | --- |
| 268 | 30/30 | 72/72 | 42 |
| 100 | 40/40 (one special event) | 96/96 | 56 |

There were no capture retries, timeouts, mismatches, or STOPPED entries. This
closes the pointer-cache fix and level-selection checkpoint in these contexts.
No repeat deployment or shortcut check is required for this checkpoint.

Level verification still uses observed mission seeds. Next development is the
eligibility/category stage (including campaign/config overrides and biome
restrictions), followed by operation finalization, before enabling independent
new-seed searches. Modifiers and constellations remain unverified.

### v0.6.3 live result: root guard failure

The user's two shortcut presses did not complete the checkpoint. The log
verified the build and signatures, armed once, then stopped at
`Invalid level root`. The stopped probe does not process further shortcut
presses. The log did not record which planet or root caused the failure;
do not assume the first capture's planet from the later map state.

In session `42812-917181171`, the map was viewing planet 268. A guarded
read-only MCP capture was saved as ignored
`artifacts/level-live-42812-268.json`. All 72 mission levels pass offline for
seed 1702255401. The replay now also exercises `identity_probe.capture` with
LuaJIT pointer addresses and the actual per-capture read cache; it passes for
this capture, the previous live capture, and all 31 saved board cases.
This does not reproduce or fix the reported root failure.

The follow-up MCP capture confirmed viewed planet 100 while the ship remained
on 268. All 96 mission levels (including special category 9, operation ID 2,
root 435 of 512) pass offline. All 193 captured ranges matched a second guarded
read. Saved as ignored `artifacts/level-live-42812-100.json`. Neither capture
reproduces the original failure. A transition during capture, an intermittent
cache issue, or a different unsupported input remain hypotheses, not findings.

Replay a new capture with:

```powershell
python -B scripts/validate_level_live.py artifacts/level-live-42812-268.json
```

### v0.6.4: capture recovery and diagnostics

The probe now rejects capture exceptions within the existing 30-second window
instead of permanently stopping after a single rejected graph. Every rejection
resets the stability gate; passing still requires two equal captures on each of
four fresh polls. Persistent failures time out without comparing or reporting
success. A later shortcut can retry. Initialization/signature failures and
unexpected errors outside capture still stop the probe.

`LUA_CAPTURE_RETRY` records the first error per attempt. Root failures include
planet, seed, operation row, ID, category, special flag, map start, root index,
node count, and definitions address. Timeout logs include the last error and
failure count; recovery is logged as `LUA_CAPTURE_RECOVERED`. New attempts clear
prior result fields. No graph bound was relaxed and no native writes or calls
were added. This is diagnostic resilience, not a confirmed root-cause fix.

Regression test `python -B tests/test_identity_probe.py` first failed on the old
runtime (`Invalid graph must be retryable`) using the real graph decoder with
root=12 and node count=12. It now covers failure in the second capture, full
stability reset, persistent timeout, exact bound diagnostics, and later retry.
The two fresh live replays and 31 saved cases (2,232 mission levels) still pass.

Next HITL: replace the old probe with
`releases/Mission-Reroller-Lua-Probe-v0.6.4.zip`, Purge / Deploy, and restart.
Open each of planets 100 and 268, press Ctrl+Shift+F9, release, and wait three
seconds (up to 30 seconds if capture needs to retry). Nothing should visibly
change. Report completion so the identity, level, retry, and timeout entries can
be checked. Full independent mission prediction remains unfinished.

```powershell
python -B scripts/validate_lua_identity.py artifacts/seed-emulator/current
python -B tests/test_identity_probe.py
python -B scripts/build_identity_probe.py
python -B scripts/validate_special_capture.py artifacts/special-inputs-live-v3.json
python -B scripts/validate_mission_choice.py artifacts/seed-emulator/current
python -B scripts/validate_level_choice.py artifacts/seed-emulator/current
python -B scripts/validate_level_capture.py artifacts/seed-emulator/current
```
