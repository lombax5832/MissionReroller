# Hosting a lobby — v0.20.2

## Status

Validated in game on 2026-09-29 in a lobby of two. The user hosted, searched
and published; the other player reported that their war table showed the
rerolled operation. Whether the operation was then started together, step 5
below, was not reported. Lobbies of three and four, a guest running the mod,
and a player joining during a search have not been exercised. Before this
session every finding of this project was made alone on the ship, and
[NETWORK_RESEED_PATH.md](NETWORK_RESEED_PATH.md) says of its own result that
it must not be generalized to multiplayer; the two-player result is the first
that does.

The docked dialog and its quiet data gaps are those of v0.20.1, which the
user confirmed working in game. See [DOCKED_DIALOG_TEST.md](DOCKED_DIALOG_TEST.md).

## What changed

Until v0.20.1 the mod required exactly one player in the session. With a
second player, reading the planet stopped the whole mod with `STOPPED: …
owner count outside supervised bounds`, and publication demanded `Expected
one source owner`.

v0.20.2 accepts a session of one to four players when the local player is
its host:

- **Host** means: the local player is one of the session's players and the
  board names the local player as its owner.
- **A guest is refused.** The panel opens, offers nothing and reads `ONLY THE
  HOST CAN REROLL OPERATIONS`. The mod keeps running. Publication checks the
  same two conditions again and cannot be reached by a guest.
- **Five or more players, a player listed twice or an empty player** stop the
  mod as before. The game's lobby holds four.
- **The board's player list must have room.** The game adds an entry for
  every player it does not list yet, and the list holds five. The snapshot
  and the publication both count every player, not only the local one.
- **A player joining or leaving changes the search's inputs.** The players
  are part of the fingerprint and of the publication guard, so a search in
  progress stops, and a publication between its check and its write is
  refused with `Owner changed`.
- **Only the dialog build does this.** The earlier builds that share the code
  (live search, seed test, combined, experiment) still require one player.

## What the other players get

The mod writes the campaign seed and marks the players' entries, exactly as
alone. The game then sends the seed to each player with its own
synchronization message. For another player that message leaves the machine;
alone it was a local copy. Their war table therefore shows the rerolled
operations as well. They do not need the mod.

Tell the players of the lobby before testing. This project makes no claim
that the backend accepts the result or that game policy allows it, in a lobby
no more than alone.

## Install

Install `releases/Mission-Reroller-v0.20.2.zip` in place of the previous package,
Purge / Deploy, and restart. If the mod misbehaves in a lobby, reinstall
`Mission-Reroller-v0.20.1.zip`; the two differ only in what is described here.

## Test

Do the steps in order and stop at the first that fails. Send the log with
the report.

1. **Alone first.** Open a planet, press Ctrl+Shift+F8, check one mission and
   search. This must behave as v0.20.1 did. The log line reads `DIALOG_SEARCH
   … players=1`.
2. **Host with one guest, without searching.** Open the planet and the panel.
   It should list missions as usual. If the panel does not open or the log
   shows `STOPPED`, note the text after it and stop here.
3. **Search as host.** Check one mission and search. Expect `DIALOG_SEARCH …
   players=2`, the usual search and publication lines, and
   `PUBLICATION_STATE_VERIFIED`. The matching operation opens.
4. **Ask the guest what their war table shows.** It should show the same
   operations as yours, including the rerolled one. Ask whether anything
   looked wrong on their side: a frozen map, a disconnect, an error.
5. **Start the operation** with the guest and confirm the mission that loads
   is the one that was shown.
6. **A guest with the mod.** If a guest has the mod installed, their panel
   should read `ONLY THE HOST CAN REROLL OPERATIONS` and offer nothing.
7. **A player joins during a search.** Optional. The search should stop
   without publishing.
8. **Three and four players**, if available.

## What the log should show

`MissionRerollerExperiment.log`:

- At start: `Mission filters: Ctrl+Shift+F8; native cursor; docked panel;
  alone or hosting a lobby; …` and `Mission Reroller 0.20.2 docked dialog; …`.
- `DIALOG_SEARCH planet=… region=… difficulty=… players=2`. `players` is new.
- The search and publication lines are unchanged.
- A refused publication reads `PUBLICATION_BLOCKED …` with one of `Not local
  selection owner`, `Source is not local owner`, `Owner queue has no capacity
  for local source` or `Owner changed`.

## Limits

- **What the fields mean in a lobby is inferred.** `session+0x162d8` and
  `+0x162e0` are read as the number and the identities of the players because
  the game's own routine walks them to mark every player. `board+0x1f8078` is
  read as the board's owner because alone it equals the local player. Neither
  was observed in a lobby. If the host's board names someone else, the host
  is refused like a guest and nothing is written.
- **Other checks may stop the mod in a lobby.** The snapshot still requires
  `session+0x167e6`, `root+0x108d`, `root+0x1099` and `root+0x8e8` to be zero
  and the backend to be ready. Their values in a lobby are unknown. A stop
  reads `STOPPED: … session gate set` or `transition gates set`; report it.
- **The send to other players is the game's, and untested.** The mod does
  not send anything itself. Whether a guest's game accepts a seed that the
  host's game did not draw itself, and what it does otherwise, is not known.
- **Undoing a publication** writes the previous seed and marks the players
  again. In a lobby that is a second message to every player.
- **A guest's view is not verified.** The mod verifies the host's regenerated
  board against its prediction. It cannot see a guest's.
- **One seed for the whole campaign**, as before: rerolling changes the
  unstarted operations of every planet, now for every player of the lobby.

## Evidence and changes

Offline only. No game memory was read or written for this change.

- The routine at `0x12d57e0`, whose bytes the mod already verifies before
  every publication, loads the count at `session+0x162d8`, walks the
  identities at `session+0x162e0`, and for each one looks it up among the
  `board+0x1f80d0` entries at `board+0x1f8080`, adding an entry when it is
  missing and setting its flag otherwise. That is the basis for counting
  every player against the five entries.
- `tests/test_lobby_host.lua` drives the packaged `snapshot` and `ownership`
  with synthetic memory: alone; host of two, three and four; host not listed
  first; a full list; guest; a local player outside the session; five
  players; duplicate and empty players; a list without room; and the guard
  and fingerprint changing when a player joins. It runs against the dialog
  build, and against the live search build to confirm that build still
  refuses a lobby.
- `tests/test_prediction_dialog.lua` covers the panel of a guest, which must
  not be treated as a gap in the planet data and must not queue a search.
- Each of twelve deliberately weakened copies of the guards failed these
  tests.
