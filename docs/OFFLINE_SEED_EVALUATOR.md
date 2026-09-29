# Offline seed evaluator prototype

This research tool runs the game's generation code in a separate x64 CPU
emulator. It neither attaches to the game nor invokes native code inside it.
Captured pages are supplied through the existing read-only Memory Explorer
addon. All generator writes, including potential cache writes, affect emulator
memory only. No seed publication or game UI integration is implemented here.

## Why separate output buffers were insufficient

The array wrapper at game.dll RVA `0x11e48b0` accepts independent operation
storage, a campaign pointer and a planet. It seeds its local RNG from the
campaign seed plus planet and invokes `0x11e3c10`, `0x11e4060`, `0x11e44d0`.
Mission generator `0x11e5670` accepts independent mission and operation buffers.

However, their shared planet lookup `0x12dbd70` reads the global board. On a
cache miss it copies definitions into board+0x36e230 and following storage,
then invokes `0x11e1e40`. Separate output arguments therefore do not establish
that native calls are side-effect-free. Emulation avoids needing to redirect
that global or allow writes to the live cache.

Replay found a second dependency: `0x11e4b50` constructs an exclusion mask
from the global board's operation array. Passing a separate output array left
that helper reading old operations and produced incorrect candidates. The
corrected replay invokes the board wrapper **0x12d5550** against the emulated
board, with only its emulated cache-dirty flag set. Thus global and argument
references share the same emulated operation array. Missions still use a separate
output buffer. No live board field is written.

## Tools

- `scripts/emulate_seed.py`: replay both generators. Missing pages stop the
  run and identify a read-only capture requirement; missing data is not zero-filled.
- `scripts/validate_seed_replay.py`: compare every byte of valid operation rows
  and populated mission rows with a live reference capture.
- `scripts/search_seeds_offline.py`: enumerate candidate uint32 seeds and require
  all requested mission families within one operation at the requested difficulty.
  It stops on missing inputs, execution errors, attempt limit or time budget.
- `tests/test_emulate_seed.py`: synthetic return, isolation, missing-memory and
  forbidden-system-call checks. These are not live generator validation.

Dependency: Unicorn 2.1.4, installed under workspace `tools/seed-emulator-deps`.
It is not included in any mod ZIP. [Unicorn's API documentation](https://www.unicorn-engine.org/docs/tutorial.html)
describes its separate emulated address space. The tool has no process-memory,
network, or native FFI execution interface. System calls and interrupts stop
execution, as does executing outside the expected game-code address interval.
Each generator invocation has a ten-second/hundred-million-instruction budget.
Scratch-buffer fences and mission-reference bounds are checked.

## First result — 2026-09-28

Read-only MCP session `18648-906202953`, planet 268, campaign seed **569798141**:
all **30 valid operation records (92 bytes each)** and **72 populated mission
records (76 bytes each)** matched the live reference byte-for-byte. There were
zero differing bytes. This is stronger than matching mission names alone.
The first attempt's mismatch was diagnosed and corrected through the global
array alias described above; the comparison was not weakened to ignore it.

An offline difficulty-10 search for ICBM AND Survey then tested 21 candidate
seeds in approximately 5.02 seconds and predicted a match at seed **569798162**:

| Field | Prediction |
|---|---|
| Row / operation ID | 28 / 8 |
| Operation seed | 1055045283 |
| Geological Survey | Type 81, mission seed 475396496 |
| Launch ICBM | Type 59, mission seed 2875651006 |
| Eradicate | Type 65, mission seed 4062341317 |

That candidate has **not** been installed in the game or validated live.
The prototype is an external research evaluator, not yet a script-mod feature.
Four synthetic isolation/failure tests passed after the implementation change.
Per-instruction Python instrumentation initially caused an execution timeout;
using page execution permissions and watching only captured-memory writes made
the bounded replay complete without bypassing a generator instruction.

### Independent seed validation

After the user rerolled twice, the live canonical and snapshot seeds both read
**1799663334**, on the same planet 268 and MCP session. Two successive captures
of the seed, planet, operation buffer and mission buffer were identical, with
the canonical seed checked before and after each capture. These are stability
checks across frames, not an atomic snapshot guarantee.

The evaluator ran with only this new seed overridden in the original frozen
fixture. No captured input pages were added or replaced. All **30 operations**
and **72 missions** again matched byte-for-byte, with zero differences. Evidence
is under ignored `artifacts/seed-emulator/current/seed-1799663334/`; the original
reference capture remains unchanged. This validates a second, independently
generated seed in this context, not every seed, planet or campaign state.

The next implementation step is guarded winning-seed publication, followed by
a supervised in-game comparison of the published result against its prediction.
The current mod still uses its existing native random reseed path.

## Capture format and use

The agent collects missing pages through `hd2_read`, using a fresh session and
module bases. A fixture directory under ignored `artifacts/seed-emulator/` holds:

- `meta.json`: session, game base, board pointer, selected planet.
- `pages/*.json`: address, session and captured page bytes; sessions must agree.
- `expected.json`: reference operation and mission buffers plus observed seed.
- `result.json`, generated binary buffers and `validation.json` for reference replay.
- `seed-<number>/`: candidate outputs; they do not overwrite reference buffers.
- `search-result.json`: match or stop reason, always `published: false`.

Pages are collected across frames, not as an atomic snapshot. Validate context
and actual output equality; do not assume the fixture captures all changing
campaign inputs consistently. Reuse is limited to the captured context and
requires independent live validation on additional seeds. Capture fixtures
contain game-derived code/data and must stay out of Git and releases.

Example after collecting a fixture and validating its current seed:

```powershell
python -B scripts/emulate_seed.py artifacts/seed-emulator/current
python -B scripts/validate_seed_replay.py artifacts/seed-emulator/current
python -B scripts/search_seeds_offline.py artifacts/seed-emulator/current `
  --difficulty 10 --require 0,59,119 --require 22,81,82,129
```

The requirements above mean Launch ICBM AND Geological Survey, allowing any
third mission. They are the existing experimental mission-family IDs, not a
complete legal-option catalogue. This first evaluator does not expose verified
modifier or constellation predictions. Two seeds have matched in one captured
context; other campaign contexts and the proposed winner remain unverified.

## Publication remains separate

The live helper chooses its own seed; it cannot accept the candidate found by
this tool. A separate [one-shot publication test](SEED_PUBLICATION_TEST.md) is now
packaged, awaiting supervised in-game validation. It writes the canonical seed
and invokes the guarded dirty setter. The offline evaluator itself still never
writes to the game, marks a live owner dirty, selects an operation or sends a
backend request.

The first publication attempt exposed a canonical-versus-snapshot input error
in the post-launch refresh tool. After correcting the inputs, the predicted
operation and mission digests both match the live publication log. See the
[publication test findings](SEED_PUBLICATION_TEST.md#publication-observed-predictor-corrected).
The runtime intentionally rolled back the mismatched attempt. The corrected
v0.5.3 publication and visible automatic selection subsequently passed the
supervised check, with both descriptor digests matching.

## Runtime architecture decision

The user chose an all-Lua runtime. The emulator remains an offline development
oracle; a companion process will not be required by the mod. The first partial
Lua port and its next in-game checkpoint are documented in
[Lua prediction test](LUA_PREDICTION_TEST.md). It currently predicts only operation
identities, not full descriptors. Automatic mission-filter searching is pending.
