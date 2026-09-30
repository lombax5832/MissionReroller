# Scripts

## Release

| Script | Output |
| --- | --- |
| `build.py` | `releases/Mission-Reroller-v<version>.zip`, the package published on Nexus Mods and GitHub. `MODULE`, `GUID`, `NAME`, `VERSION` and the summary in the manifest live here. |
| `build_identity_probe.py` | `source()` assembles the single plaintext entry from `src/`; `build.py` calls it with `search`, `publish` and `dialog` enabled. Its own `main` is the read-only research probe below. |
| `release_notes.py` | `python -B scripts/release_notes.py v<version>` prints that version's `docs/HISTORY.md` entries and fails when the tag and `VERSION` disagree. The release workflow uses it for the GitHub release and the Nexus Mods changelog. |
| `build_core.py` | The inert development core (`Mission-Reroller-Development-v0.2.0.zip`): the pure filter and search controller with no memory access. `build_identity_probe.source()` embeds it. |

`python -B scripts/build.py` builds the release; `python -B tests/test_package.py`
checks it and runs the dialog tests.

## Research builds

These package earlier checkpoints of the same code. Each is kept because a
test under `tests/` or a document under `docs/` still refers to it, and
because reinstalling one is the quickest way to bisect an in-game regression.
None of them is meant for players.

| Script | Package | Documented in |
| --- | --- | --- |
| `build_experiment.py` | Keyboard filter dialog with a five-call limit | `docs/FILTER_EXPERIMENT.md` |
| `build_combined.py` | Mouse dialog, bounded native search, operation selection | `docs/COMBINED_TEST.md` |
| `build_seed_test.py` | One-shot publication of a predicted seed | `docs/SEED_PUBLICATION_TEST.md` |
| `build_identity_probe.py` | Read-only Lua composition validation | `docs/LUA_PREDICTION_TEST.md` |
| `build_search_probe.py` | Read-only cooperative Lua seed search | `docs/LUA_PREDICTION_TEST.md` |
| `build_live_search.py` | Fixed-filter search, publication and selection | `docs/LIVE_SEARCH_TEST.md` |
| `build_probe.py` | Single native reseed | `docs/ONE_SHOT.md` |
| `build_preflight.py` | Preflight checks only | `docs/PREFLIGHT.md` |
| `build_input_inventory.py` | Input inventory | `docs/MOUSE_INPUT.md` |
| `build_mouse_probe.py` | Mouse input probe | `docs/MOUSE_INPUT.md` |

## Analysis tools

The remaining scripts read saved captures under the ignored `artifacts/`
folder or, for `check_live_*.py`, live game memory through the Memory
Explorer addon. They are development tools and package nothing. Each one's
docstring says what it needs.
