# Mission Reroller domain

The words this project uses for its own concepts. Game facts are in
`AGENTS.md`; design decisions are in `docs/HISTORY.md`.

- **Reroll**: writing a new campaign seed so that the game regenerates every
  unstarted operation. In a lobby, only the host may reroll.
- **Board**: the operations on the viewed planet's war table, as the game
  holds them in memory.
- **Prediction**: the board that the Lua port of the game's operation
  generator computes for a candidate seed. It is compared with the live board
  before any search.
- **Planet model** (`src/planet_model.lua`, `lib.Planet`): the one way to
  build a planet's prediction. `Planet.bind(read, u, pointer, game, board,
  planet)` decodes that planet through one read function (live, cached or
  frozen) and offers its `inputs()`, `constellation_inputs()`,
  `predictor(definitions)` and `catalogue(snapshot, difficulty, accepts)`;
  the mission and tag inputs share one configuration and effects decoder.
  `Planet.capture(read, u, pointer, game)` compares a snapshot's board with
  its prediction.
- **Filters**: the player's request in the dialog: the missions that are
  required, the world modifiers, and the enemy forces (constellations) to
  accept or exclude.
- **Filter request** (`src/filter_request.lua`): the Filters as the dialog
  holds them, with the open section, mission page and enemy group. It turns
  panel actions into edits, prunes what a new catalogue no longer offers,
  makes the request for the reroll session and builds the panel's model,
  status included. Pure: the dialog runtime reads the game and hands it
  plain tables.
- **Reroll session** (`src/reroll_session.lua`): one run from the player's
  request to its outcome. It is the only writer of the run's **phase**.
  - **Phase**: where the run stands (`waiting_for_stable_inputs`,
    `search_running`, `publication_pending`, ...). The phase names are the
    `M.status` strings that the log prints.
  - **Outcome**: the terminal phase that ends a run (`publication_test_passed`,
    `search_exhausted`, `cancelled`, `session_failed`, ...). Every run ends
    in exactly one.
  - **Checkpoint**: a phase where a run may stop when no later stage can
    start. The run ends there with an outcome and does not hang.
  - **Stages**: the steps a run moves through, always forward:
    1. Capture: read the planet's inputs until they are stable.
    2. Comparison: check the prediction against the live board (identity,
       level, composition).
    3. Search: try seeds until a prediction matches the filters.
    4. Publication: write the matching seed and verify the regenerated
       board.
    5. Selection: open the matching operation.
  - **Run record**: what the session keeps for the current run besides its
    phase: the filters it was started with, the pending start and cancel
    the pipeline takes once each, and the search's report, progress (seeds
    tried) and finished job. A new run begins with an empty record.
- **Host** (`host` in the runtimes): the adapter's services and the build's
  config, as one table:
  - memory reads, the snapshot and the log;
  - the map screen (`host.map`) and, in the builds that publish, the one
    guarded memory write (`host.write`);
  - the reroll session;
  - the native handles, which arrive through `when_initialized`.

  Tests pass a fake host. This is unrelated to a lobby's host player.
- **Runtime**: a `src/*_runtime.lua` file. It runs as
  `function(host, lib, hooks)` and returns its entry points. The assembler
  passes those entry points on as **hooks** to the runtimes created after it.
- **Build config**: the build's mode as data (`read_only`,
  `preview_prediction`, banner, shortcut), set in
  `build_identity_probe.config()`.
