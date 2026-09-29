# Mission Reroller — development only

**Next in-game test: [v0.19.0 constellation exclusion](docs/CONSTELLATION_FILTER_TEST.md)
and [all mission types and cities](docs/CITY_SCOPE_TEST.md).**
Each constellation cycles ANY, ACCEPT, EXCLUDE per checked mission, or for the
whole operation when no mission is checked; any number can be excluded.
The dialog lists every mission type that has a title, 126 types in 74
families, instead of twelve families. Opening it with the cursor on a city's
operation marker, or with that operation selected, limits the options and
the search to that city. v0.18.0 published and selected a city operation in
game three times. An operation in progress is reported as not rerollable.
Constellation exclusion is not yet validated in game.

**Working in game: [v0.16.0 fast seed search](docs/FAST_SEARCH_TEST.md).**
The search validates its inputs once a second and before a match instead of
after every seed, and predicts only the map difficulty until a seed matches.
The first logged search covered 2,731 seeds at 1,214 per second, against
about 11 per second before; the saved campaign replays at about 14,000 per
second of pure work offline. The budget is 262,144 seeds and an unchanged
request continues where the last search stopped. v0.16.1 adds timing and
stamp diagnostics only. Continuation after an exhausted search has not been
exercised in game.

**Working in game: [v0.15.0 constellations per mission](docs/CONSTELLATION_FILTER_TEST.md).**
A third dialog tab accepts base enemy constellations for each checked mission
separately, or for any one mission when none is checked. Each list shows only
what that mission can draw. Tags are predicted for every candidate mission
from its seed; hovering missions afterwards logs what the loaded preview
added. Two per-mission searches were published and eight hovered missions
agreed with the prediction inputs. The constellation the game then uses has
not been confirmed independently.

**Validated by log: [v0.13.0 viewed-planet rerolling](docs/VIEWED_PLANET_TEST.md).**
Two remote publications were verified with the ship elsewhere. The dialog
retains its contents through temporary data waits, disabling actions until
fresh data returns; that visual fix still awaits the user's confirmation.

**Validated preview: [v0.12.2 viewed-planet filters](docs/FACTION_FILTER_TEST.md).**
Filters populate for the planet being viewed even when the ship is elsewhere.
Remote previews explicitly disable rerolling until the ship arrives.
Incompatible mission choices are dimmed and disabled as you select filters;
hover for a reason. Checked missions remain removable. The check includes
eligible templates, category limits, slots and selected modifier rules.
Mission and modifier choices come from eligible templates on the selected
planet at the map difficulty. Modifiers cycle Any / Require / Exclude and
combine with mission requirements. Invalid selections are cleared when the
planet or difficulty changes. The v0.11.0 dialog was confirmed working in game.

**Validated in-game: [v0.11.0 mission filter dialog](docs/DIALOG_SEARCH_TEST.md).**
Ctrl+Shift+F8 opens the restored mouse dialog with the native cursor and HUD
input blocking. Checked mission families feed the Lua seed search; existing
matches are selected without a refresh. Uses map difficulty and allows repeated
searches without restarting. Search throughput is unchanged. Modifier and
constellation filters remain future work.

**Validated in-game: [v0.10.x live Lua search](docs/LIVE_SEARCH_TEST.md).**
The all-Lua search now publishes one matching seed, verifies the regenerated
board, and opens the matched operation using the tested native/UI selection
path. Start alone on your ship, viewing the planet it orbits at difficulty 10.
This checkpoint uses the fixed ICBM + Survey + Eradicate filter and permits one
publication per game session. The user confirmed success from both planet
overview and an already-selected operation.

**Current test: [v0.9.1 automatic backend waiting](docs/LUA_PREDICTION_TEST.md#v091-automatic-backend-wait).**
The read-only search now pauses for temporary pending backend requests instead
of cancelling. It resumes automatically after a quiet interval and full input
revalidation. Planet 100 already produced an in-game match with v0.9.0 after
45 candidates; planet 268's logged search was cancelled after 20 candidates.

**Next test: [v0.9.0 cooperative Lua seed search](docs/LUA_PREDICTION_TEST.md#v090-cooperative-search-checkpoint).**
After validating the displayed board, the probe searches up to 256 candidate
seeds for ICBM + Geological Survey + Eradicate on difficulty 10. Rule bytes are
cached without replacement and revalidated before accepting each candidate.
Search yields between work batches, supports cancellation and alt-tab, and
stops on context changes. It logs a match without refreshing or selecting it.
The packaged search found seed 4 / row 29 in the saved ordinary-planet context;
the offline native emulator confirmed that result. In-game search testing is pending.

**Validated in-game: [v0.8.0 independent seed prediction](docs/LUA_PREDICTION_TEST.md#v080-independent-seed-prediction).**
Operation bases now come from campaign state and the seed, with the active
operation preserved. The packaged predictor matches 31 saved boards and a fresh
planet-100 capture without using displayed operation bases as inputs. The pure
bounded filter-search controller is implemented and tested offline; it is not
connected to the game UI or publication yet. v0.8.0 remains a read-only probe.
At seed 1764573301, planet 100 passed with 40 operation bases and 96 missions;
planet 268 passed twice with 30 bases and 72 missions. All comparison stages
passed without retries, timeouts or mismatches. Support remains limited to the
tested campaign branches.

**Previous diagnostic: v0.7.1.** The v0.7.0 in-game run loaded and verified its
signatures, but capture failed on both planets with `attempt to compare number
with nil` in the eligibility difficulty check. Saved captures still pass; the
root cause is not established. v0.7.1 adds input diagnostics and a failure stack
trace. It now passes twice on each planet at seed 373592754: planet 100 has
40 identities, templates and modifier sets plus 96 mission descriptors;
planet 268 has 30 identities, templates and modifier sets plus 72 descriptors.
All four runs passed without retries, timeouts or mismatches. This completes
the combined checkpoint for these inputs, but does not establish the earlier
failure's cause or prove it fixed.

[Combined composition scope](docs/LUA_PREDICTION_TEST.md#v070-combined-composition-checkpoint).
Mission eligibility, category selection, and operation finalization now run
together in Lua. The combined predictor matched 2,232 mission descriptors across
31 saved boards and 96 descriptors on a fresh planet-100 capture, including
templates and modifiers. v0.7.1 also passes the planet-100 in-game check above.
It uses operation base fields as inputs, but independently generates mission
seeds, types, and levels. This read-only checkpoint does not enable seed searching.

[Validated in-game: Lua probe v0.6.5](docs/LUA_PREDICTION_TEST.md#v065-pointer-cache-key-fix).
The root failure was reproduced: the game renders pointer values as the same
`[cdata (deleted)]` string, causing different reads to share a cache entry.
Version 0.6.5 keys reads by numeric address and size, and formats fingerprint
addresses numerically. With opaque pointer formatting, all 96 saved live levels
on planet 100, 72 on planet 268, and 2,232 saved oracle levels pass. Strict bounds
and bounded retries remain. In-game checks now pass twice on each planet for
seed 33257715: 30 operation identities and 72 levels on planet 268; 40 identities
and 96 levels on planet 100, including the special operation rows. No retries,
timeouts, mismatches, or stops occurred. This checkpoint is complete.
This verifies level selection using observed mission seeds to resolve the
unported category draw; it is not yet independent full mission prediction.

[Validated in-game: read-only Lua predictor v0.6.2](docs/LUA_PREDICTION_TEST.md#v062-special-operation-checkpoint).
Both planet tests passed for seed 929426942: all 40 operation identities on
planet 100 (including ten special rows), and all 30 on planet 268. The loader,
build hashes, and code signatures passed. This validates the viewed-planet fix
and supported special-event input collection inside the game's Lua VM.
The v0.6.5 checkpoint also verifies the level graph and level selection in-game.

The weighted mission picker also matches 256 offline native-function cases.
The v0.7.0 combined eligibility/finalization checkpoint is ready for testing. Prediction stays
entirely inside Lua. Mission-filter searching and publication are not enabled in
this diagnostic build. The original 30-row identity check already passed in-game.

Previous dialog package: [combined mouse search v0.4.1](docs/COMBINED_TEST.md).
It combines the native-cursor dialog and bounded search, then selects the
matched operation without selecting a mission. In-game checks confirmed an
existing match with zero reseeds and a new match after one reseed. Both preserved
the active operation and released the dialog after selection.

Version 0.4.1 removes the session call cap and lowers the minimum interval to
one second, while waiting for each stable refresh. The three-minute search
timeout and Cancel remain. This faster cadence awaits in-game validation.

For network observation, use the [Windows capture workflow](docs/NETWORK_CAPTURE.md).
It records NIC traffic and sampled socket ownership alongside reroll log events;
it does not attach to the game or require a new addon package.

The [offline seed evaluator](docs/OFFLINE_SEED_EVALUATOR.md) reproduced two
independent live seeds, each with 30 operations and 72 missions byte-for-byte,
using the same frozen inputs. It can search without refreshing the game.
The separate [one-shot publication test v0.5.3](docs/SEED_PUBLICATION_TEST.md)
reads a prediction file refreshed after launch, then publishes one predicted
seed with Ctrl+Shift+F9. The first 0.5.0 attempt correctly blocked stale captured
state before writing; 0.5.1 fixes the need to repackage prediction data and lets
preflight rejection be retried. Version 0.5.2 continues work while alt-tabbed and
handles the empty owner queue with bounded native insertion. It temporarily
replaces the dialog build. Corrected prediction and seed publication have now
matched live; v0.5.3 adds the normal click's local map-selection fields to address
the missing visible operation view. The user confirmed that v0.5.3 visibly
selected the correct operation; logs confirmed both predicted digests, preserved
active-operation bytes and no mission selection. Automatic prediction/filter
integration is still pending; this remains a one-shot research build.

Earlier test: [filtered search experiment 0.3.0](docs/FILTER_EXPERIMENT.md), with an
in-game keyboard filter dialog and a five-call session limit. It supported twelve
common mission families. This is separate from the inert Development ZIP.

Completed in-game milestone: [single native reseed experiment](docs/ONE_SHOT.md).
Probe 0.1.1 made exactly one native call, changed the displayed missions, and
preserved the canonical active operation. Disable the diagnostic after this
test. Repeated searches, general host detection, backend acceptance and complete
filter integration remain unverified.

**Not a finished mod.** The current combined package has passed supervised
mouse-dialog, bounded-search and automatic-selection checks. The complete
legal-option catalogue, modifier/constellation integration and a native
war-table entry button remain unfinished. The Development ZIP is still an
inert core, with no button or rerolls.

## Intended behavior

Select an available planet and difficulty, click **Reroll operations**, and
choose required mission types, operation modifiers and enemy constellations.
The mod should evaluate candidate seeds inside Lua, then publish a verified seed
whose normal game-generated operation matches. Required mission types apply across a single operation:
Launch ICBM + Geological Survey permits any third mission. Extra modifiers or
tags remain unrestricted unless a future explicit exclusion filter is added.

Constellations are sets of tags on individual missions. Each checked mission
has its own rules: it must carry one of the accepted constellations and none
of the excluded ones. Without checked missions, one mission of the operation
must carry an accepted one and no mission an excluded one. Modifier filters
require all selected modifiers. An empty selection imposes no requirement.

Native generation and backend acceptance must be established before calling
results vanilla-valid. That would not establish approval under game policy.
This project presently makes neither claim.

## What works offline

- Canonical-ID filters, validated against a supplied complete option catalogue.
- Full-operation matching, with unknown data distinct from a negative result.
- Initial-batch matching, one in-flight request, paced retry after complete
  results, cancellation, context invalidation, attempt limits and timeouts.
- Bingus Shared Loader plaintext addon packaging with stable GUID.
- Matching Lua and Python decoders for complete operation mission lists, with
  two-pass consistency checks. Both were replayed against four read-only live
  captures (120 operation records) with identical mission types and seeds.
- Optional title hints from external game research files, and a comparison tool
  that distinguishes hover/status changes from operation-content changes.

The packaged entry exposes its development core as `MissionReroller` and logs
`unsupported_native_adapter`. It leaves update/shutdown untouched and performs
no memory access, native calls or network requests. The controller is not
connected to the game loop. A loader `loaded` line confirms discovery only.

## Build and test

Requires the adjacent `BingusSharedLoader` source (or `BINGUS_LOADER_ROOT`) and
LuaJIT (`HD2_LUAJIT` or the workspace tool path).

```powershell
python -B scripts/build.py
python -B tests/test_package.py
```

Output: `releases/Mission-Reroller-Development-v0.2.0.zip`. No game binaries,
extracted resources or research captures enter the package. No live deployment
or user gameplay test has been performed for this addon.

## Research and remaining work

- [Research status](docs/RESEARCH.md)
- [Native adapter requirements](docs/ADAPTER.md)
- [Constellation reference investigation](docs/CONSTELLATION_RESEARCH.md)
- [Constellation filter test](docs/CONSTELLATION_FILTER_TEST.md)
- [Fast seed search test](docs/FAST_SEARCH_TEST.md)
- [City and megafactory test](docs/CITY_SCOPE_TEST.md)
- [Native reroll investigation](docs/NATIVE_REROLL_RESEARCH.md)
- [Complete operation layout](docs/OPERATION_LAYOUT.md)
- [Seed lifecycle](docs/SEED_LIFECYCLE.md)
- [In-game validation](docs/LIVE_VALIDATION.md)

The installed binaries matched build 25480438 during research on 2026-09-28.
The workspace's older 25327279 offsets must not be assumed compatible. The
reference KnowYourConstellation checkout lives beside this repository; none of
its source or artwork is embedded or redistributed here.
