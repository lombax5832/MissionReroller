# In-game test: operations edited by Refresh Operations

Checks that a reroll works after Refresh Operations' F6 has edited
operations, and answers the open question in
[EXTERNAL_EDITS.md](EXTERNAL_EDITS.md): does a reroll replace the edited
row? Alone on the ship, hosting.

## Setup

1. Build from the branch (`python -B scripts/build.py`) and import the ZIP,
   Refresh Operations + Missions and the loader into Arsenal. Purge, Deploy,
   launch.
2. `BingusSharedLoader.log` shows
   `mods/ipodalexei/mission_reroller_experiment: loaded` and
   `mods/ryanb/refresh_operations: loaded`.

## 1. F6 on one operation, then a reroll

1. Open a planet and wait two seconds. The log shows
   `BASELINE_RECORDED planet=<P> seed=<S>`.
2. Select an operation and press F6 to refresh its missions.
3. Press F7 and choose filters the board does not already satisfy, so a
   search and a reroll run. Start.

Passes when the log shows, in order:

```
LUA_IDENTITY_EDITED planet=<P> seed=<S> ... matched=29 live=30 ...
LUA_IDENTITY_EXTERNAL_EDIT row=<R> observed=... predicted=... evidence=baseline
LUA_COMPOSITION_PASS ... edited_rows=1
PUBLISH_BEGIN ...
PREDICTION_CHECK descriptors_match=true ...
PUBLICATION_STATE_VERIFIED ...
```

and the panel closes on the matching operation. `descriptors_match=true`
answers the open question: the reroll replaced the edited row.

If instead the log shows `PREDICTION_CHECK descriptors_match=false` and
`PUBLICATION_RESTORED`, the edited row survived the reroll. Nothing is lost
(the old seed is back), but send the log: the edit then has to be refused
before the search.

## 2. F6 on several operations

Repeat 1 with F6 on two or three operations (select each, press F6), then
F7. Passes with one `LUA_IDENTITY_EXTERNAL_EDIT` line per refreshed
operation, `edited_rows=<n>`, and the same publication lines.

## 3. The edited operation already matches

Press F6 on an operation until its missions satisfy a filter, then F7 with
that filter. Passes when the log has no `EXISTING_MATCH row=<R>` for the
edited row: the mod searches instead and rerolls.

## 4. The order from the report: F7, F6, F7

F7 (any result), F6 on the selected operation, F7 again. Passes with
`LUA_IDENTITY_EDITED` and the search; the earlier failure was
`LUA_IDENTITY_MISMATCH` and the caption `IDENTITY_TEST_MISMATCH`.

## Failure lines

- `LUA_IDENTITY_NOT_EXTERNAL <reason>`: the difference was not accepted as an
  edit. Send the line with the `LUA_IDENTITY_DETAIL` lines before it.
- `STOPPED: <reason>`: send the whole log.

## Also note

Press Refresh Operations' plain F6 (not on a selected operation) once and
send the lines that follow. A `BASELINE_RECORDED` with a new seed means it
rerolls the campaign seed, as Mission Reroller does.
