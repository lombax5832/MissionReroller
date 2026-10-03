# Side objective filter

## Status

**Validated in game on 2026-10-02** from the user's log
(`Mission Reroller 0.31.0 docked dialog`, loader line
`mods/ipodalexei/mission_reroller_experiment: loaded`): eleven
`SIDE_OBJECTIVE_CHECK` lines with `modifiers_agree=true agree=true`, and a
Launch ICBM search requiring Lidar Station and excluding SEAF Artillery that
published seed 787509373 and whose hovered mission agreed with the game.
Not checked: the in-mission map after a drop (step 6).

## What changed

A SIDE OBJECTIVES section sits between ENEMY FORCES and TIME OF DAY. Like
enemy forces it has one button per checked mission, or `ANY MISSION` when
none is checked; each row is a side or tactical objective title and cycles
ANY, REQUIRED, EXCLUDED.

- **Matching.** Per mission, every required row and no excluded one
  (`src/search_session.lua`). With `ANY MISSION`: every required row on some
  mission of the operation, no excluded row on any.
- **Prediction.** `src/side_objective_runtime.lua` gives each predicted
  mission its objectives from `src/side_objective_prediction.lua`, with the
  planet's world modifiers from `src/template_environments.lua`.
- **Options and validation.** `src/filter_catalogue.lua` offers what each
  mission type can draw on the viewed planet at the map difficulty and
  keeps its side and tactical slots. A row that would need more slots than
  any type of the mission has, or that would exclude every row of a role,
  is skipped by a click; a row that can be neither required nor excluded is
  dimmed with the reason.

## In-game test

Difficulty 6 or higher on a Terminid or Automaton planet.

1. **Hover check.** On the war table, hover four or five missions of
   different types, including one Eradicate or Evacuate mission, for about
   a second each. Each logs one `SIDE_OBJECTIVE_CHECK` line.
2. **Panel.** Press F7 and open SIDE OBJECTIVES. With no mission checked the
   tab reads `ANY MISSION` and the line under it `ANY MISSION OF THE
   OPERATION`. Check Launch ICBM: the tab changes to Launch ICBM and the
   line reads `3 SIDE + 1 TACTICAL` (4 at difficulty 8 to 10). The rows
   stand in two labelled blocks, SIDE (Lidar Station, SEAF Artillery, ...)
   and TACTICAL below it (Upload Escape Pod Data, ...).
3. **Require and exclude.** With Launch ICBM checked, click Lidar Station
   once (yellow, REQUIRED) and SEAF Artillery twice (red, EXCLUDED). The
   section header reads `2 RULES`. Press REROLL OPERATIONS.
4. When the operation opens, hover its Launch ICBM mission and read the
   objectives in the mission briefing or the pre-drop map: Lidar Station is
   listed, SEAF Artillery is not.
5. **Slots.** Require side objectives until the mission's side slots are
   full; the next unrequired side row is skipped to EXCLUDED on a click, and
   pointing at it shows `Too many required side objectives...`.
6. **Optional, drop in.** Drop into the matched mission and check the
   in-mission map shows the same side objectives.

## Log lines

Pass:

- `SIDE_OBJECTIVE_CHECK planet=<p> row=<r> type=<t> seed=<s> difficulty=<d>
  modifiers=[...] predicted_modifiers=[...] predicted=[...] live=[...]
  modifiers_agree=true agree=true` for every hovered mission. An Eradicate
  or Evacuate mission lists only its primary and sub-step objectives.
- `LUA_SEARCH_OBJECTIVES Launch ICBM=require Lidar Station exclude SEAF Artillery`
  before `LUA_SEARCH_STARTED`.
- `LUA_SEARCH_MATCH_OBJECTIVES row=<r> missions=<type>:[...]` where the
  Launch ICBM mission's list holds `Lidar Station/3` and no
  `SEAF Artillery/3`, then the usual `LUA_SEARCH_MATCH`,
  `PUBLICATION_STATE_VERIFIED` and selection lines; or `EXISTING_MATCH`.

Fail:

- `agree=false` or `modifiers_agree=false` on any `SIDE_OBJECTIVE_CHECK`
  line (send the line: the first is the draw, the second the world
  modifiers).
- `SIDE_OBJECTIVE_CHECK_BLOCKED`, `SIDE_OBJECTIVE_CATALOGUE_BLOCKED` or
  `FILTER_BLOCKED` with a side-objective reason.
- An opened operation whose briefing contradicts the rules.
