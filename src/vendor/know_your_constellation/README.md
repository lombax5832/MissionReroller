# Know Your Constellation roster

`roster.lua` and `roster_data.lua` are copied byte for byte from
[CowboyBingus/KnowYourConstellation](https://github.com/CowboyBingus/KnowYourConstellation)
at commit `662609f` (release v4.0, data from Steam build 25480438). They are
included with CowboyBingus's permission, as the fallback roster for the
enemy-force tooltips when Know Your Constellation is not loaded or exports
no roster. They remain CowboyBingus's work.

Do not edit them. `src/bundled_roster.lua` adapts them to the roster api 1
that `src/unit_forecast.lua` reads, and `tests/test_bundled_roster.py`
checks both files against their upstream git blob IDs.

To take a newer upstream roster, for example after a game update: copy both
files from the new Know Your Constellation commit, update the commit here and
the blob IDs in `tests/test_bundled_roster.py`
(`git ls-tree <commit> src/roster.lua src/roster_data.lua` in that repo),
and check that `src/bundled_roster.lua`'s `from_native` still matches that
commit's `resolve.from_native` and `revision` its `REVISION`. The bundled roster
switches itself off when its data's `build` is not `src/offsets.lua`'s
`build`.
