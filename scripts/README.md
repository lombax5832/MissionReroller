# Scripts

## Release

| Script | Output |
| --- | --- |
| `build.py` | `releases/Mission-Reroller-v<version>.zip`, the package published on Nexus Mods and GitHub. `NAME`, `DEFAULT_VERSION` and the manifest's description live here; the version is the `RELEASE_TAG` environment variable (`v1.2.3`) when set, which the release workflow sets from the tag; `MODULE` and `GUID` come from `build_core.RELEASE_MODULE` / `RELEASE_GUID`. |
| `build_identity_probe.py` | `source()` assembles the single plaintext entry from `src/`; `build.py` calls it with `search`, `publish` and `dialog` enabled. Its own `main` is the read-only research probe below. |
| `release_notes.py` | `python -B scripts/release_notes.py v<version>` prints that version's `CHANGELOG.md` section, the player-facing notes, and fails when there is none; `--plain` gives one line of plain text per change for Nexus Mods, which renders no Markdown. The release workflow uses it for the GitHub release and the Nexus Mods changelog. |
| `build_core.py` | The inert development core (`Mission-Reroller-Development-v0.2.0.zip`): the pure filter and search controller with no memory access. `build_identity_probe.source()` embeds it. |

`python -B scripts/build.py` builds the release; `python -B tests/test_package.py`
checks it and runs the dialog tests.

## Research builds

These package other configurations of the release source and are not meant
for players. The older checkpoint builds (keyboard experiment, combined
dialog, seed test, one-shot probe, preflight, input inventory, mouse probe)
were removed; the repository history keeps them.

| Script | Package | Documented in |
| --- | --- | --- |
| `build_identity_probe.py` | Read-only Lua composition validation | `docs/LUA_PREDICTION_TEST.md` |
| `build_search_probe.py` | Read-only cooperative Lua seed search | `docs/LUA_PREDICTION_TEST.md` |
| `build_live_search.py` | Fixed-filter search, publication and selection | `docs/LIVE_SEARCH_TEST.md` |

## Offsets

| Script | Purpose |
| --- | --- |
| `check_offsets.py` | Checks `src/offsets.lua` against a game dump. With `--reference <old dump>` it carries the table to a new build: moved code, globals and fields get `FIX` lines (`--write` applies them), changed code lists the struct displacements that changed and the Lua lines using them. `--find-anchors` suggests anchors for unverified entries. Compares the hashes with the installed game. Runbook: `docs/UPDATING.md`; rehearsal test: `tests/test_check_offsets.py`. |
| `code_match.py` | Capstone decoding of the dumps for `check_offsets.py`: code equal up to call targets and RIP displacements, function bounds from `.pdata`, RIP and value users, register origins. Needs the workspace `tools/seed-emulator-deps` and numpy. |
| `offsets.py` | Reads `src/offsets.lua` for the Python tools (`O.rva`, `O.field`, `O.research`) through `offsets_json.lua` and `HD2_LUAJIT`. |

## Analysis tools

The remaining scripts read saved captures under the ignored `artifacts/`
folder or, for `check_live_*.py`, live game memory through the Memory
Explorer addon. They are development tools and package nothing. Each one's
docstring says what it needs.
