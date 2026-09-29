# Faction-aware mission and operation modifier filters — v0.12.0

## v0.12.2 viewed-planet preview

The dialog no longer rejects a valid viewed-planet snapshot when the ship is
elsewhere. Mission, modifier, faction and compatibility choices populate from
the viewed planet's operation data. Reroll publication still requires the ship
planet; a remote preview shows "Preview: travel to this planet to reroll
operations" and disables Start. Arrival enables Start on the next snapshot.
An inconsistent map UI/cache planet still hides choices until they agree.

Regression coverage exercises the real context function with different ship
and viewed planets, confirms the remote faction list appears, blocks remote
Start clicks, enables it on arrival, and rejects mismatched UI planet data.
Human check: install v0.12.2, restart, inspect a different-faction planet without
traveling, and confirm its filters populate. Then travel and confirm Start enables.

## v0.12.1 mission compatibility

Install `releases/Mission-Reroller-v0.12.1.zip` for compatibility-aware choices.
After checking a mission, incompatible unchecked rows turn gray and ignore
clicks. Hover a disabled row for a reason. Checked missions always remain
removable; unchecking them re-enables alternatives. Modifier rules participate
in the same check. If modifier changes make the current filter impossible,
Start is disabled and explains the conflict; change a rule or uncheck a mission.

The check enumerates structural possibilities separately for every eligible
template: mission-category minima, maxima, order and native wildcard/fallback
behavior across available slots; terminal modifier draws under the budget and
two-modifier cap; and faction-specific modifier-added missions. Options from
different templates cannot be combined into one imaginary operation. Existing
operations are additional concrete witnesses. The search-start validator repeats
the compatibility check, independently of mouse input.

This is deliberately conservative about random weights, seed correlations,
mission repetition weighting, and level graph outcomes. A selectable combination
is structurally plausible, not guaranteed to occur in the 256-seed search.
No option is disabled merely because a bounded seed search failed to find it.

Regression tests cover category conflicts, separate templates, modifier budget
combinations, disabling/ignoring clicks/re-enabling rows, and 2,560 outcomes of
the ported generator choosers. Saved native fixtures across 32 boards retain
all observed difficulty-10 mission/modifier combinations. Next human check:
choose a conflicting mission pair, verify the second is gray, remove the first,
and verify the second becomes clickable. Then search a compatible combination.

Install `releases/Mission-Reroller-v0.12.0.zip` in place of the previous
Mission Reroller package, Purge / Deploy, and restart with the shared loader.
Open your ship planet at the desired map difficulty and press Ctrl+Shift+F8.

## Test in game

1. Check the Missions tab on a Terminid planet. Faction-ineligible families,
   such as Destroy Command Bunkers, should not be listed. Options are also
   filtered by the current difficulty, planet environments and enable rules.
2. On Modifiers, click a row to cycle ANY -> REQUIRE -> EXCLUDE -> ANY.
   Choose a mission plus a required or excluded modifier and start searching.
   Verify both against the operation opened after the search.
3. Clear Selection clears rules in both tabs. A modifier-only search is valid.
   An already-matching operation is selected without changing the seed.
4. On an Automaton or Illuminate planet, reopen the dialog. Mission and
   modifier lists should change; previously chosen unavailable filters are
   removed. Check that Atmospheric Spores is absent where the game's eligible
   templates do not permit it. Filters valid on both planets remain selected.
5. Check close/reopen, cancel, and a second search without restarting.

The catalogue is a union across eligible operation templates. Individually legal
options can still form an impossible combination; a bounded search then reports
no match and does not publish. A search retains the 256-candidate limit and
the v0.11.0 throughput. Enemy constellation filtering remains future work.

## Eligibility and matching

`filter_catalogue.lua` consumes the same `composition_inputs.lua` methods used
by the predictor. From each distinct operation category/effect/explicit-template
context at the displayed difficulty it resolves eligible templates, mission
candidates, modifier budgets, and faction-specific extra missions. Templates
are not limited to the currently rolled template. Normal template selection
checks faction, difficulty, environment tags and enable overrides; mission
candidates further check faction, difficulty, enable state and biome restrictions.
An explicit template follows the generator's explicit-template path. Modifiers
come from those templates' pools and must fit the current modifier budget.

The visible lists are cached for a stable snapshot and recomputed when it changes
or the dialog reopens. Selections are pruned against that catalogue. Start checks
eligibility again, and the captured search baseline validates it again before
matching existing operations or searching new seeds. Search rules are copied
and combined for the same operation. Require demands presence; Exclude demands
absence. Unknown modifier data cannot satisfy an exclusion. The live snapshot
decoder now exposes both modifier IDs for existing-operation matching.

## Research evidence

Read-only Memory Explorer session `15364-969310140`, supported build 25480438,
confirmed 13 modifier records at game.dll+0x32e94d0, stride 0x50. Each record's
+0x00 contains its identifier, +0x04 its cost, and +0x38 its localization key.
All 13 names were resolved through the existing English extracted string files;
the capture is ignored at artifacts/modifier-live-15364.json. Only the small
identifier/display-name mapping is included in the mod; no dumps or extracted
resources are packaged. New unrecognized IDs fail the catalogue closed.

## Validation

- `tests/test_dialog.py`: all three faction catalogue cases, unavailable mission
  and modifier rejection, cost budgets, modifier-only requests, require/exclude
  matching, copied rules, mouse cycling, faction-change pruning, tab rendering,
  pagination layout, input ownership, focus loss, cancel and reopen.
- `tests/test_live_search.py`: publication rechecks modifier rules, including
  rejecting an absent required modifier and accepting its exclusion.
- `tests/test_search_probe.py` and `tests/test_package.py`: cooperative search
  and existing core/package checks.
- `tests/check_composition_capture.lua` with the saved native oracle: real
  Terminid catalogue gives nine mission families and four modifiers; all
  predicted difficulty-10 modifiers belong to its legal pools. All 32 boards
  and 2,304 mission descriptors still match.

Visual validation of v0.12.0 and cross-faction live testing are pending.
