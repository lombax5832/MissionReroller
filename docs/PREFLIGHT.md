# In-game callback preflight 0.1.1

Version 0.1.0 loaded in-game and verified the module hashes and helper signature,
then stopped before snapshot completion: `attempt to compare string with number`.
The read wrapper returned both arguments of `assert`, passing its diagnostic
string as the pointer decoder's optional offset. Version 0.1.1 returns exactly
one value from both read and pointer wrappers. The synthetic-memory regression
executes the real update/snapshot path and pointer decoder: it reproduced the
original error and now completes all ten samples. In-game success is pending.

This separate diagnostic performs no native calls and no game-memory writes. It
has no reroll hotkey. The user has authorized the native helper's module-owned RNG
update for the later one-shot test; this package checks prerequisites first.

Import `releases/Mission-Reroller-Preflight-v0.1.1.zip` with Bingus Shared Loader
(internal version 16 or newer). Keep the loader as the winning startup override,
Purge / Deploy, and launch normally. The development core ZIP is not needed.

Alone on your own ship, open the galactic map and select an available planet.
Stay there without selecting a mission for about 15 seconds. Diagnostics run
automatically, once; no key press is needed. Then tell the agent you are ready
so it can read `MissionRerollerPreflight.log` from the loader's Logs folder.

Expected success: `PREFLIGHT_COMPLETE read_only=true native_calls=0` and the
loader entry `mods/ipodalexei/mission_reroller_preflight: loaded`. A
`PREFLIGHT_STOP` line is a failed check; do not keep relaunching to bypass it.

The probe checks both installed module hashes, the full helper/tail-target code
range, target page attributes, bounded owner union, active record and mission
data stability, ten spaced samples, and Lua update thread consistency. It checks
the full eight-byte transition gate at root+0x8e8. It preserves update/shutdown
return values, including trailing nil values, and stops on exceptions.

Thread consistency alone does not prove board ownership. Successful preflight
does not establish native thread safety, backend queue safety, publication, or
host authority. Those remain prerequisites/limits for the subsequent one-shot
implementation. There is no automatic escalation from observation to a call.

Remove this diagnostic after its validation run. Logs contain active-operation
bytes for local comparison; do not include them in releases.
