# Operations edited by another mod

Refresh Operations + Missions (`mods/ryanb/refresh_operations`, F6 while
hosting) can rewrite operations on the war table without changing the
campaign seed. Before this change, Mission Reroller's identity check then
failed on the edited rows and the reroll stopped with
`identity_test_mismatch`. `src/external_edits.lua` tells such an edit apart
from a gap in the generator port, and the reroll goes on without the edited
rows. The in-game test is [EXTERNAL_EDITS_TEST.md](EXTERNAL_EDITS_TEST.md).

## What the edit looks like

The user's log of 2026-10-01 (planet 201, campaign seed `1263716310`): F7
passed, F6 refreshed the missions of the selected operation, F7 failed on
that operation alone.

```
LUA_IDENTITY_PASS planet=201 seed=1263716310 pool=31 special_events=0 matched=30 live=30 predicted=30 ...
CONSTELLATION_CHECK planet=201 row=28 type=22 seed=402966911 ...
CONSTELLATION_CHECK planet=201 row=28 type=21 seed=322166244 ...
LUA_IDENTITY_MISMATCH planet=201 seed=1263716310 pool=31 special_events=0 matched=29 live=30 predicted=30 ...
LUA_IDENTITY_DETAIL row=28 observed=23/3061063729/d10 predicted=23/1048270963/d10
```

The campaign seed, the operation type (23) and the difficulty stayed the
same; only row 28's operation seed changed, and its missions with it. Row
29 still matched.

## Why the edited row can be left out

- A reroll regenerates every unstarted operation from the new seed. The
  search predicts the new board from the seed, the planet's pool, its
  events and the operation in progress, never from the displayed rows, so an
  edited row plays no part in it.
- The check after the seed is written (`matches` in
  `src/live_publication_runtime.lua`) compares the whole regenerated board
  with the prediction and restores the old seed if they differ. If the game
  kept an edited row through a reroll, that check would catch it.

## When a difference counts as an edit

`ExternalEdits.classify` takes the structured `differences` of
`probe:compare` (`src/identity_probe.lua`). Every differing row must be an
unstarted operation (not `preserved`), keep its difficulty, and have one of
these proofs:

- **baseline**: the planet was seen under the same campaign seed with this
  row equal to the prediction. The runtime records the first board it sees
  per planet and seed, once a second while the galactic map is open and no
  run is going (`BASELINE_RECORDED planet=… seed=…`), and after each passing
  comparison. A later board under the same seed never replaces it, so an
  edit cannot prove itself. With this proof the operation type may differ
  as well.
- **later_rows**: only the operation seed differs and a row after it
  matches. Every ordinary row draws its seed the same way, and a port error
  in the draws would carry into the rows after it.

A missing or extra row, a changed difficulty, an edited operation in
progress, or a row with neither proof keeps the mismatch
(`LUA_IDENTITY_NOT_EXTERNAL <reason>`). Each row is proven on its own, so
F6 on several operations is handled the same way as on one.

## What changes downstream

The accepted rows travel on the snapshot as `s.external`:

- the level check (`probe:compare_levels`) skips them;
- the composition check passes when only they failed
  (`ExternalEdits.composition_passes`, using `failed_rows` and `general`
  from `src/composition_capture.lua`), in the identity runtime and in the
  search's frozen baseline;
- the existing-match check never offers them: their missions came from the
  other mod, not from a seed.

## In game

A reroll replaces an edited row with the one the new seed gives: on
2026-10-01 the run after F6 on row 28 logged
`PREDICTION_CHECK descriptors_match=true` (see `docs/HISTORY.md`).

## Unknown

- The dialog's catalogue (`src/filter_catalogue.lua`) still counts every
  displayed operation, edited ones included, as proof that its mix of
  missions and modifiers is allowed. If F6 can make a mix no seed gives, a
  search for it runs out of seeds; it never writes anything wrong.
- How Refresh Operations' plain refresh (not the missions of a selected
  operation) changes the board. If it changes the campaign seed, the
  identity check passes as for any reroll.
