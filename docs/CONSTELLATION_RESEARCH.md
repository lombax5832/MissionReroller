# Constellation and operation-preview source research

Investigated 2026-09-28 against the imported first-party
[KnowYourConstellation source](https://github.com/CowboyBingus/KnowYourConstellation)
at commit `46cb418efe913f472509d0382535407242af2e39` (v3.16.1).
No game-memory reads, writes, native calls, or Ghidra analysis were performed
for this note. The coordinating agent reports that the installed EXE and DLL
hashes match this revision's Steam build **25480438** pins. That observation
supersedes the workspace's older 25327279 default for this investigation.

## Build boundary

The current source targets 25480438: EXE SHA-256
`F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06`,
game.dll SHA-256
`2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E`.
The reader hashes the installed module files before using offsets.
[archive.py](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/scripts/archive.py#L10),
[install.lua](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/install.lua#L26).

Historical commit `b1efaf020a12457f8738156f030f98777e61e1e9` supports 25327279.
The subsequent native-reader change moved the enemy-tag hash table from RVA
`0x21e18e0` to `0x21e1920`; it did not change the other mission-reader or
presentation offsets. The 896-byte mission records and inserted native tag 1
already existed at the 25327279 revision, despite HEAD comments naming the
newer build. Do not combine a historical hash pin with the current hash-table
RVA. [Build migration diff](https://github.com/CowboyBingus/KnowYourConstellation/compare/b1efaf020a12457f8738156f030f98777e61e1e9...1e261628eeb2905a13778e02ceb62846fff95b6e).

## Mission and operation layout facts

All RVAs below are relative to `game.dll`; all structure offsets are bytes,
zero-based. These are facts encoded by the reference reader, not independent
validation of the game's current runtime state.

| Object | Layout used by the source |
| --- | --- |
| Screen state | Pointer at RVA `0x347ce28`; stack at owner `+0x429c`, count at stack `+20`, max 5; top 15 is map, 14 briefing. |
| Board | Pointer at RVA `0x347cee8`. |
| Preview descriptor | Board `+0x4168d0`, exactly 200 bytes. |
| Descriptor identity | `u32 +0` seed, `u32 +4` secondary, `u8 +8` faction (2-4), `u8 +9` difficulty (1-10), `u32 +12` planet hash, `u16 +26` mission type (<256). |
| Loaded controller | Root pointer at RVA `0x3326340`; controller pointer at root `+0xae288`; loaded descriptor at controller `+8`. |
| Highlighted local selection | Index at board `+1548960`; `0xffffffff` denotes no local selection. Rows at board `+1012352 +92*index`; index <110; `u8 +52` must be nonzero; planet index `u16 +16`; operation id `u8 +24`; category `u32 +28`. |
| Campaign data | Board `+1053752`; planet count board `+1197132` <=512; static planet rows stride 280, planet hash row `+24`; dynamic rows start campaign `+286752`, stride 304. |
| Campaign operation records | Campaign `+143384`, stride 24; count campaign `+155672` <=512. Planet index `u32 +0`, operation id `u32 +4`, template id `u32 +8`. |
| Operation templates | Header board `+0x1f8908`: values pointer +0, key pointer +8, count +16 <=4096. Template values are pointers. Modifier hash array pointer template +88, count +96 <=256. |
| Modifier definitions | Pointer RVA `0x347cd98`; 52-byte rows, count owner +53248 <=1024. Reader recognizes enemy-tag records when row +4 ==40 and +24 ==13; +0 id, +8 modifier hash, +28 enemy-tag hash. |

Sources: [mission descriptor and selection](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/mission.lua#L41),
[campaign and template reader](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/mission.lua#L168).

The rows described above are enough to identify a highlighted operation and
read its modifier hashes. They do **not** establish how to generate a new
operation, enumerate every mission inside an arbitrary operation, or populate
its loaded preview controller without selecting it. The reader resolves only
the highlighted/selected mission. Its numeric mission id is not an exhaustive
mission-name catalogue. These remain separate research requirements.
[descriptor()](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/mission.lua#L107).

## What a complete constellation filter requires

The output is a **set of mission tags**, not a single operation-wide enemy
constellation. The source combines the following inputs, in this order:

1. Campaign inputs: selected planet dynamic/static modifiers, environmental
   modifiers, applicable events, selected operation-template modifiers, and
   global modifiers with planet/region/faction scope. Some campaign paths are
   gated by session/root state.
2. Loaded-controller level inputs: explicit tags and selected level/stamp tag.
   The loaded descriptor must match the selected descriptor identity.
3. Seeded weighted base selection from difficulty settings, respecting
   `only_when_empty` and fallback-blocker tags. Difficulty rows start at RVA
   `0x328d2a0`, stride 816. Draw count +272; faction candidate tables at
   +276/+372/+468, eight 12-byte entries each. Candidate id +0, weight +4,
   only-when-empty +8. Blocker/fallback sections start +564/+600/+636.
4. Conditional mission tag: mission records at RVA `0x3773420`, stride 896;
   if byte +0x34 ==2 and the 8-byte resource at +0x360 matches the source's
   constant, add authored tag 31 (Horde Forces).
5. Mission exclusions: eight native ids from record +0x14. Configuration
   exclusions: manager RVA `0x347cdf8`, maps +73848 and +49232, key derived
   from the native tag hash. Native tag hashes are at RVA `0x21e1920` (32).

Sources: [campaign](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/mission.lua#L168),
[stamp and exclusions](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/mission.lua#L291),
[sample pipeline](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/mission.lua#L338).

Weighted draws use a 64-bit LCG with multiplier `0x5851F42D4C957F2D`,
increment `0x14057B7EF767814F`, initial state equal to the 32-bit mission seed,
upper 32-bit output, and explicit float32 rounding of sums/target. Candidates
are not removed after selection; output tags are deduplicated. Naive Lua
double arithmetic can disagree. Native id 1 maps to authored id 31, native
ids >1 map to native-1, and native 0 remains 0.
[resolve.lua](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/resolve.lua#L1).

The reader marks a snapshot incomplete on missing campaign inputs, stale
controller, failed stamp reads, or failed config-exclusion reads. It rereads
the descriptor and selection afterward to reject races. The installer only
publishes a forecast after complete identity checks before and after sampling.
A reroller should apply this same acceptance condition: unknown must never
count as a filter match. It cannot accept an arbitrary seed from the base RNG
alone as proof of the final constellation.
[sample](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/mission.lua#L338),
[installer publication gate](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/install.lua#L120).

Recommended operation-filter semantics (design inference): explicitly choose
whether selected constellation tags must occur in any mission or every mission
of an operation, and allow tags to be required/excluded rather than treating
them as a mutually exclusive list. Accept the operation only once all relevant
mission snapshots are complete. Planet/campaign-forced tags may be impossible
to change by rerolling, so the option list should distinguish those from
random base candidates after their current applicability is validated.

The old composition reference was extracted for build 24826606 and describes
30 non-none tags; current code adds Horde Forces. It should not be used as a
current exhaustive legality catalogue. The heavy forecast is Terminid-only,
describes static eligibility and replacements, and cannot promise actual
encounters. SEAF Support is friendly, not an enemy constellation.
[composition reference](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/docs/CONSTELLATIONS.md),
[catalogue](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/catalogue.lua),
[heavy forecast](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/heavy.lua).

## UI facts and missing input path

The mod creates its own native screen GUI in an existing non-main world with
`stingray.World.create_screen_gui(world, 'scale', 1, 1)`, using retained
`Gui.rect/text/update_rect/update_text` primitives. `Gui.text_extents` provides
font metrics. On shutdown/world changes it destroys its own GUI. It does not
modify native widgets. This proves an independently drawn reroll button and
filter box can use a native-looking rendering path; it does not prove they
can receive clicks or capture input.
[panel.lua](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/panel.lua#L30).

Presentation resolves a native owner from manager RVA `0x3326e68`, map event
registry +25224 kind 226, briefing +25272 kind 229. Map frame is owner +349072
with fallback planet frame +280528; briefing frame +31232. Widget inherited
opacity +84, dimensions +36/+40, scales +100/+140, positions +148/+156.
Font RVA `0x3772268`, material hash at pointer(RVA `0x37c5478`)+24, atlas RVA
`0x3772ee8`. These can inform placement after build validation, but the mod's
fallback is still designed around a visible preview frame and does not prove
placement works before any mission is highlighted.
[presentation.lua](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/src/presentation.lua#L35).

No mouse, keyboard, click handler, modal focus, input consumption, native
reroll action, generation call, or network mutation implementation was found
in this repository's runtime source. The UI interaction and native generation
route must be established elsewhere before claiming a usable reroller.
[runtime source tree](https://github.com/CowboyBingus/KnowYourConstellation/tree/46cb418efe913f472509d0382535407242af2e39/src).

## Source reuse and release boundaries

The repository explicitly states that no repository-wide license has been
selected. Its mention of LuaJIT's MIT license covers the compiler, not this
mod's Lua source. Importing the repository for investigation does not by
itself establish permission to redistribute copied runtime source. Keep source
research citations and independently authored implementation separate unless
the author supplies an applicable reuse grant. No legal determination is made
here. [THIRD_PARTY.md](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/THIRD_PARTY.md).

The reference package deliberately excludes extracted game fonts, executable
images and raw memory captures. Its public fixtures use synthetic addresses
and packets. Follow the same boundary in any research-addon release.
[THIRD_PARTY.md](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/THIRD_PARTY.md),
[TECHNICAL.md](https://github.com/CowboyBingus/KnowYourConstellation/blob/46cb418efe913f472509d0382535407242af2e39/docs/TECHNICAL.md).

## Native resolver analysis, 2026-09-29

Offline Ghidra analysis of the saved build 25480438 image, `-readOnly
-noanalysis`. Raw output is in `../../tools/ghidra-projects/reroller_constellation_*.txt`.
The project holds few stored references, so call sites and constants were
located by scanning the image and resolving function starts through `.pdata`.

| RVA | Role |
| --- | --- |
| `0x177dd80` | Resolver: clear list, `0x11deda0`, `0x177deb0`, then configuration exclusions with key `{0xe165f457, 0xec4e3719, hash}` |
| `0x11deda0` | Campaign effects of class 0x28 and kind 13, then 32 global entries of 0x164 bytes |
| `0x12e1210` | Global entry applicability: scope byte +0x54, value +0x58, faction filter +0x5c |
| `0x177deb0` | Level explicit tags, first stamp tag, `0x1758000`, `HordeOnly`, mission exclusions |
| `0x1758000` | Difficulty clamp, candidate filter, seeded draws, fallback and blockers |
| `0x11ebb40` | Difficulty cap from configuration key `{0xaf218cac, 0xfaabbea9}` |
| `0xf70f20` | Copies descriptor arrays into the level: mission type +0x8bc570, explicit tags +0x8bc654, count +0x8bc660 |
| `0x12d27b0` | Builds a local mission descriptor from its 76-byte mission row |
| `0xfc2ea0` | Packs descriptor fields; explicit tags at descriptor +0xaa, count +0xa9 |

The tag table at `0x21e1920` has 32 tags followed by the `Count` and
`MAX_ENEMY_TAGS_PER_MISSION` entries. Names come from the pointer table at
`0x21ded50`: index 1 is `HordeOnly`, 2 `BugAcid`, and so on to 31 `GM_SEAF`.

Findings that differ from, or add to, the reference reader:

- The native code reads the level through controller `+0x2c8`. The reference
  reader uses `+0x288` (648). The offsets inside the level agree. Which slot
  holds the previewed level is decided by the in-game observer.
- The stamp count is read at level `+0x11a715c`; the reference reader tests
  `+0x11a712c`.
- A stamp record with tag 0 still adds the `none` entry to the native list.
  It occupies a slot and counts for only-when-empty candidates.
- Mission exclusions stop at the first empty slot.
- `0x12d27b0` leaves the explicit-tag pointer and count zero. Operation
  modifiers travel in a different descriptor array (+0xae) and are not enemy
  tags in this resolver.
- In the saved tables every difficulty draws once, no candidate is
  only-when-empty, difficulty 1 has no candidates, and the Illuminate have
  only the `GM_IlluminateInvasion` fallback. A stamp tag therefore cannot
  change a Terminid or Automaton base draw.

Still unknown: which stamp a mission places first, and whether any stamp
carries a base constellation. The generator that fills the stamp list was not
ported. [The v0.15.0 test](CONSTELLATION_FILTER_TEST.md) measures it instead.

## What this establishes, and what it does not

Established by reference source: a build-locked read-only selected-mission
constellation predictor, operation-template modifier lookup, selected-operation
planet identity, and native overlay rendering.

Still unknown: a supported reroll trigger, local versus authoritative ownership
of generation results, candidate-operation enumeration, full legal mission and
modifier pools under current planet/difficulty/campaign rules, complete
constellation resolution for unselected candidates, and safe clickable modal
input handling. Repeatedly generating candidates and filtering them does not
by itself establish legality: the generation path and acceptance/commit path
must be shown to preserve the game's constraints. This is a design inference,
not an assertion that the requested feature is impossible.
