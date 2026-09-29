# Native adapter contract (not implemented)

The development Lua core is testable without the game. It does not constitute
a working reroller. `new_search(adapter)` is a dependency seam, not a public
claim that a native API exists. No adapter is installed or loaded at startup.

## Required observations

- `context()` returns a fresh `{key, planet, difficulty, available, host,
  screen, operation_in_progress}`. `screen='planet'` means the planet operation
  selection view, not merely being on the ship. The key must change when the
  campaign, allowed rules, session or relevant operation state changes.
- `catalogue(context)` returns `{context, complete, slots, missions, modifiers,
  constellations}`. Option lists contain canonical string IDs, never guessed
  names. Derive legal options from current planet/faction/difficulty/campaign
  rules. Individually legal options need not form a possible joint combination;
  the UI must distinguish that from a proven impossible combination.
- `snapshot(context)` returns `{generation, context_key, complete, operations}`.
  Generation identifies a native batch, not a mod-invented seed. Each operation
  carries `{planet, difficulty, context_key, native_generated, complete,
  modifiers, modifiers_complete, missions}`. A mission contains `{type,
  constellations, forecast_complete}`. Only attest complete when all native
  records and their context agree; never turn missing data into empty sets.
- `request(context, generation)` rechecks context and generation immediately
  before invoking a verified normal game path. Return a unique string ticket,
  or `nil, reason` on refusal. Never edit seeds, rewards, mission IDs or tables.
  It must be nonblocking and must enforce native readiness and backoff itself.
- `poll(ticket)` returns nil while pending, then `{ticket, batch}` or
  `{ticket, error}`. Complete constellation resolution may take multiple frames;
  return the progressively resolved batch with the same request ticket.

No speculative native addresses should be called to implement this contract.
First establish ABI, ownership, request scope (planet versus all operations),
response handling, progress persistence and backend throttling. Enforce installed
module hashes and independent byte signatures before any native integration.

## Search semantics

All selected mission types must occur within one operation. Extra mission slots
are unrestricted. All selected modifiers must occur; extras are allowed.
Constellation scope `every_mission` requires all selected tags on every mission;
scope `operation` requires their union across that operation. Default is
`every_mission`; the eventual UI must make this explicit.

The initial batch is checked before requesting a reroll. At most one request is
in flight. Complete nonmatching responses allow another request after the delay.
Incomplete or stale responses wait until timeout. Timeout never blindly retries.
Cancellation prevents future requests but cannot undo one already accepted by
the backend. Controllers are single-use. Before creating another, the adapter
must confirm that any previous request has settled; it must enforce one request
in flight across controller instances. A match stops and returns the native operation; it does not select
or start that operation automatically. Attempt exhaustion does not prove that
the requested combination is impossible. Numeric limits are development bounds,
not evidence of an approved backend request rate.

The native UI still needs a button on the selected planet view, legal-option
checklists, start/cancel controls, attempt count and meaningful failure states.
The KnowYourConstellation overlay provides rendering research, not clickable
input or an operation generator.
