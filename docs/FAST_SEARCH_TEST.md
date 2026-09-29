# Fast seed search — v0.16.0

## Result, 2026-09-29 session (v0.16.0)

Both logged searches matched, published and verified
(`descriptors_match=true`, `PUBLICATION_STATE_VERIFIED`):

| Planet | Request | Seeds | Rate | Longest slice |
| --- | --- | --- | --- | --- |
| 253, ship there | two missions, two required modifiers, one constellation each | 2,731 | 1,214 /s | 53 ms |
| 268, ship at 253 | two missions, one excluded modifier, one constellation each | 309 | 341 /s | 29 ms |

The first search needed more than ten times the old 256-seed budget and
took about 2.2 s; at the old rate it would have taken about four minutes.
Fractional slice times show that the high-resolution clock is in use.

The rates are well below the offline figure. Both searches were short, so
the start-up capture weighs heavily in them, and the log did not yet say how
a slice divides between search work and the context check, or whether the
game compiles the Lua code. v0.16.1 adds `elapsed_s`, `slices`, `work_ms`,
`context_ms` and `jit` to the search lines for that purpose. It changes no
behaviour.

Not exercised in that session: an exhausted search and its continuation,
alt-tab during a search, and a search long enough for a progress line.

## Timing, 2026-09-29 session (v0.18.0)

Three short city searches reported the new timing fields:

| Seeds | Elapsed | Slices | Search work | Context checks | JIT |
| --- | --- | --- | --- | --- | --- |
| 6 | 1.73 s | 61 | 389 ms | 48 ms | on |
| 25 | 1.72 s | 55 | 396 ms | 43 ms | on |
| 284 | 1.81 s | 56 | 430 ms | 42 ms | on |

Every search takes about 1.7 s and 55 frames before its first seed, to
capture and validate its inputs. That start-up explains the low rates of
short searches; 278 further seeds cost 0.08 s. The context check is cheap at
under a millisecond per frame, and the game compiles the Lua code. The rate
of the search itself still needs one search of ten seconds or more.

## Install

Install `releases/Mission-Reroller-v0.19.0.zip` in place of the previous package,
Purge / Deploy, and restart. Remain alone on your ship for this supervised test.
This build contains the per-mission constellations of v0.15.0; their test is in
[CONSTELLATION_FILTER_TEST.md](CONSTELLATION_FILTER_TEST.md) and can be run with
this package. Filters, publication, verification and selection are unchanged.

## What changed

| | v0.15.0 | v0.16.0 |
| --- | --- | --- |
| Seeds per second, from your v0.13.0 log and the offline replay | about 11 | about 14,000 of pure work offline; expect several thousand in game |
| Seed budget per search | 256 | 262,144, within the unchanged 180 s limit |
| Search again with the same filters | repeats the same seeds | continues after the last seed searched |

Two changes produce the speed:

1. **Inputs are validated when it matters.** Every candidate is predicted from
   frozen copies of the campaign data, so a rejected candidate needs no memory
   reads. The frozen copies are compared with the game once a second, after a
   backend wait, and always before a match is accepted. Before, all of them
   were re-read after every candidate, which took four to five frames.
2. **Only the map difficulty is predicted while searching.** Operations are
   generated independently from their own seeds, so the three operations at
   the requested difficulty are enough to reject a seed. A matching seed is
   then predicted completely, the match is confirmed on that board, and the
   complete board is what publication verifies, exactly as before.

The search now works for 16 ms in each frame instead of yielding after every
seed. Expect roughly half the usual frame rate while it runs.

## Test

1. Repeat a search that used to take several seconds, for example three
   missions on one planet. It should finish almost at once.
2. Try a request that was out of reach: two missions with one constellation
   each, or three missions with a modifier rule.
3. If a search ends with `No match in … seeds; search again to continue`,
   start it again unchanged. The log should show `resumed=true` and a
   `first_seed` that follows the previous `next_seed`.
4. Alt-tab during a long search and return. The search should have continued.
5. Note how the game feels while searching. If the frame rate drop is too
   much or you would trade more of it for speed, say so; it is one number.

## What the log should show

- `LUA_SEARCH_STARTED … first_seed=… resumed=false … limit=262144`.
- `LUA_SEARCH_PROGRESS attempts=… seeds_per_second=…` every five seconds.
- `LUA_SEARCH_MATCH seed=… attempts=… seeds_per_second=…`, then the usual
  `PUBLISH_BEGIN`, `PREDICTION_CHECK descriptors_match=true` and
  `PUBLICATION_STATE_VERIFIED`.
- `LUA_SEARCH_EXHAUSTED attempts=262144 … next_seed=…` when nothing matched.

`seeds_per_second` and `max_slice_ms` are the numbers to report. A
`LUA_SEARCH_FAILED … Prediction inputs changed; restart search` means the
campaign data changed during the search; nothing was published. A
`Search and complete predictions differ` failure would mean the two
predictions disagree; nothing is published in that case either.

## Evidence

- `tests/check_fast_prediction.lua` replays the saved planet 268 campaign
  memory. The search prediction equals the complete prediction for every
  difficulty on 1,537 seeds (46,110 operations), including the 32 seeds whose
  boards were captured from the game. The packaged job then scans 65,536 seeds
  in 4.65 s of work with a longest slice of 17 ms.
- `tests/check_composition_capture.lua` still matches all 32 captured boards
  and 2,304 mission descriptors.
- `tests/test_prediction_search_job.lua` covers the slice length, the cap on
  seeds per slice if the clock stalls, no reads for rejected seeds, validation
  once a second and before a match, a change of inputs shortly before a match,
  and disagreement between the two predictions.
- `tests/test_search_probe_runtime.lua` covers the budget and resumed ranges:
  the same request continues, while another filter, another campaign seed or
  a failed search starts again.

The offline rate is pure Lua work on this machine. In game the rate also
depends on the frame rate and on the context check made before every slice.
That check reads the operation board once per frame instead of twice.
In-game validation is the next step.
