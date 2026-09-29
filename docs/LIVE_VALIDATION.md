# Live validation and next human check

2026-09-28, installed build 25480438. Memory Explorer 0.1.1 read-only MCP works.
No mod deployment is required for this check. No native call or memory write
has been made. The development addon still has no reroll button or driver.

## Baseline acquired

Two bounded read passes agreed byte-for-byte, including operation and mission
rows, selected planet, screen stack, campaign seed and both cache planet IDs.
Manager pointers and session also agreed at the capture boundaries. This is
stronger than a single pass, but remains separate-frame data, not an atomic
snapshot; an intermediate change followed by a return to the same state cannot
be excluded.

Private research capture outside Git/releases:
`../../dumps/build-25480438/mission-reroller-validation-before.json`.
Earlier exploratory captures are not the current decoder schema; use this file.

Observed planet index268,30 valid operations,72 missions, map screen15,
no highlighted operation at the final baseline. The generated mission records
cross-check parent operation, difficulty, slot ordinal and status. All cache
planet IDs agree and the dirty byte is clear.

The saved mission settings table has title hashes at record+0x340 (record base
game.dll RVA0x3773420, stride896). Those hashes map to the following title hints
in the external extracted English string resource. This is a title-lookup
observation, not proof of current legal-option pools or UI correspondence.

| Difficulty10 operation row | Mission title hints, in native slot order |
| --- | --- |
| 27 | Purge Hatcheries; Retrieve Valuable Data; Search and Destroy |
| 28 | Spread Democracy; Launch ICBM; Eradicate Terminid Swarm |
| 29 | Retrieve Valuable Data; Eradicate Terminid Swarm; Spread Democracy |

## Confirmed UI comparison

The user confirmed the expected difficulty10 combination: Spread Democracy,
Launch ICBM and Eradicate Terminid Swarm. A subsequent two-pass MCP capture
identified highlighted operation row28, operation ID14, difficulty10, with
mission settings IDs85,59,65 in that order. Both read passes agreed and the
session, cached planets and manager pointers remained consistent.

Capture: `../../dumps/build-25480438/mission-reroller-validation-after.json`.
Against the baseline, the campaign seed and **all30 normalized operation
records were identical**, including all72 mission seeds, types and statuses.
Only the hover selection changed. Thus this observed difficulty/hover
transition did not produce a different operation set. Identical data does not
prove that no deterministic regeneration code executed internally.

This validates one three-mission operation's visible titles and selection
identity. It does not yet validate every mission variant, modifiers,
constellations, server acceptance or a callable reroll path.

## Previous user action (completed)

Stay on this planet, change the displayed difficulty to10, and hover the
operation containing Launch ICBM. Check whether its other missions are Spread
Democracy and Eradicate Terminid Swarm. Leave it highlighted and report what
you see. Do not launch a mission or confirm an abandonment; neither is needed.
If difficulty10 is unavailable, report an unlocked difficulty with three-mission
operations so the comparison can use that tier.

## Planet round trip (completed)

The requested action was to back out to the galaxy map, open another available planet, then return to the
original planet at difficulty10. Hover the ICBM operation again if it is still
present, and report when ready. No mission launch or abandonment is needed;
do not confirm either. This normal transition exercises the planet-dependent
generation/cache refresh path identified in the native code. Capture the
returned original planet and compare with the confirmed after-capture.

`scripts/compare_operations.py BEFORE AFTER` validates both captures and
compares campaign seed, generated content and full records separately. It
ignores hover when deciding whether content changed and distinguishes mission
status changes from seed/type changes. It rejects cross-planet comparisons.
These are observations, not proof that a transition is a usable reroll trigger.

The user completed the round trip. Two subsequent read passes agreed, with
planet268 and highlighted row28. Compared with the previous after-capture,
the campaign seed, generated content and all30 operation records remained
identical. Saved as
`../../dumps/build-25480438/mission-reroller-planet-roundtrip.json`. Thus neither
tested menu transition produced a new operation set in this session.

The canonical seed at board+0x78e84 also matched the copied campaign seed.
The canonical active-operation record was valid, on this planet at difficulty1,
with one mission status2. This record must be preserved; a reset that clears
the active operation cannot serve as an automatic reroll implementation.
Raw read remains outside Git in `mission-reroller-canonical-seed.json`.

Development v0.2.0 now includes the equivalent bounded decoder in Lua as
`MissionReroller.inspect_snapshot`. Replay against all three captures agrees
with Python on all90 operations' mission IDs and seeds. It accepts supplied
bytes only and does not read game memory or enable a reroll. Its results remain
marked `matching_ready=false` because legal catalogues and full constellation
and modifier evaluation are not yet available.

## Normal relaunch (completed)

The native ordinary operation-fetch completion path contains a canonical seed
advance and marks the board owner state dirty. This is distinct from the
standalone reset path that clears active operation state. See
[seed lifecycle](SEED_LIFECYCLE.md) for the static evidence and limitations.

Quit to desktop and relaunch normally with the existing Memory Explorer addon.
Return to the same planet at difficulty10. Do not start or abandon an operation;
leave the planet open, hovering the ICBM operation if it remains available.
No development-mod installation is needed. Tell the agent when ready.

After relaunch, refresh MCP status/modules and acquire new pointer values; never
reuse this session's addresses. Capture two agreeing passes and the canonical
seed plus92-byte active record at board+0x78e84. Compare against the round-trip
capture and canonical baseline. Specifically distinguish newly generated
unstarted operations from the preserved difficulty1 active operation, ID6,
seed4082660196 on planet268 (one mission, status2). A seed advance on normal
load was supported by static code; the following captures now confirm this
particular relaunch outcome.

The fresh Memory Explorer session returned a new board allocation. Both read
passes agreed. The canonical and snapshot seed changed from 2201397042 to
2929768776. Of 30 operation rows, 29 changed and only row 0 remained identical.
The complete 92-byte active-operation record was byte-for-byte identical to the
pre-relaunch record; its generated mission type 58, seed 1409118643, level index 20,
status 2 and difficulty 1 were also unchanged. Thus the normal relaunch regenerated
unstarted choices while preserving this active operation in the observed case.

Captures outside Git/releases:
`../../dumps/build-25480438/mission-reroller-relaunch.json` and
`../../dumps/build-25480438/mission-reroller-canonical-relaunch.json`.
The Lua decoder agrees with Python on all 30 post-relaunch operations, bringing
the replay total to 120 operation records across four captures.

This verifies a normal-game outcome, not a callable in-session refresh contract.
The specific state-machine route taken during launch was not instrumented, and
no mod-triggered refresh, backend request, native call or write has been tested.
The next development task is the operation-fetch state-machine contract; no
additional menu trial is justified merely by these successful observations.

## Reproduce offline interpretation

From the workspace root (substitute the available Python executable):

```powershell
python -B MissionReroller/scripts/inspect_operations.py `
  dumps/build-25480438/mission-reroller-validation-before.json `
  --dump dumps/build-25480438/game.dll.unpacked.bin `
  --strings extracted/strings/0xd29d9f674db28566.strings.json `
  --difficulty 10
```

The dump SHA-256 is checked before resolving title hashes. No extracted strings
or game binary is included in the repository/package. The command does not
access the running game. The decoded fingerprint identifies the capture only;
it is not a native generation token or a server operation identifier.

## Validation completed

The capture decoder's synthetic tests cover full-operation decoding, changed
read passes, session changes, stale/dirty caches, invalid mission references,
duplicate references, owner/difficulty/slot/status mismatches, invalid screen,
invalid selection and byte-count parsing independent of padding. The existing
Lua filter/search and package tests also pass. One on-screen comparison is
confirmed; the native reroll driver, legal-option catalogue, complete
constellation/modifier evaluation and clickable UI remain unfinished.
