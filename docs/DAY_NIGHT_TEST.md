# v0.27.0 Day / Night filter: in-game test

v0.27.0 adds a TIME OF DAY section to the panel: Any time, Day or Night.
With Day or Night chosen, a match's missions must stay on that side,
outside a 30-minute twilight band around 06:00 and 18:00, for 2.5 hours
after the seed is written, or for half of a side when the planet's days are
too short for that. How the sun is predicted is in
[DAY_NIGHT_RESEARCH.md](DAY_NIGHT_RESEARCH.md). v0.25.0 (central offsets)
is still unvalidated too; step 1 covers its startup line.

The war table shows the local time under the cursor as `SEST hh:mm:ss`
when you hover a planet's surface. Use it to read a mission's time of day:
hover the mission's marker. 06:00 is dawn, 12:00 noon, 18:00 dusk.

## Result, 2026-09-30

Steps 1 to 3 and 7 passed. Four searches matched with `holds=true`, then
`DAYNIGHT_VERIFIED holds=true` and `PUBLICATION_STATE_VERIFIED`:

| Planet | Side | Day, buffer | Missions (minutes) |
| --- | --- | --- | --- |
| 201 | Night | 56598 s, 9000 s | 61, 87, 73 |
| 201 | Day | 56598 s, 9000 s | 582, 550, 612 |
| 100 | Day | 6606 s, 1514 s | 581, 562, 604 |
| 100 | Night | 6606 s, 1514 s | 1269, 1263, 1291 |

The player confirmed the missions were on the chosen side. Steps 4 to 6
(a city, the countdown, the twilight band) are still to run.

## Setup

Import `releases/Mission-Reroller-v0.27.0.zip` and the loader into Arsenal
or HD2MM, keep the loader as the winning startup override, Purge / Deploy,
launch. Read `BingusSharedLoader.log` and `MissionRerollerExperiment.log`
from `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs`. Stay alone on your
ship.

## Steps

1. Reach the ship and open the galactic map.
   - Pass: `mods/ipodalexei/mission_reroller_experiment: loaded`,
     `Mission Reroller 0.27.0 docked dialog` and
     `build=25480438 hashes=verified signatures=37 anchors=24 verified`.
   - Fail: `STOPPED: … offset signature sky_<name> mismatch` or any other
     `STOPPED:` line.
2. **Day, whole planet.** View a planet with a long day, press F7 and
   click DAY on the TIME OF DAY header (a dropdown before
   docs/TIME_OF_DAY_HEADER_TEST.md). The line under it reads
   `STAYS ON THAT SIDE FOR AT LEAST 2H 30M` and `DAY <length>`. Check nothing else and press REROLL
   OPERATIONS.
   - Pass: `DAYNIGHT_PLANET planet=<n> day_s=… buffer_s=9000 band_min=30`,
     `DAYNIGHT_SEARCH side=day …`, `DAYNIGHT_MATCH side=day … holds=true
     minutes=level<a>@<m>,…` with every minute value between 390 and 900
     (06:30 to 15:00), then `DAYNIGHT_VERIFIED row=<r> holds=true` and
     `PUBLICATION_STATE_VERIFIED`.
   - Hover each mission of the selected operation: SEST reads the same
     times as the `minutes=` values (minutes / 60 = hours), within a few
     minutes. Deploy to one: it is daylight.
   - Fail: a `holds=false` line other than one followed by
     `DAYNIGHT_WINDOW_CLOSED`, SEST outside 06:30–15:00, or a dark
     mission.
3. **Night, whole planet.** As step 2 with NIGHT.
   - Pass: `DAYNIGHT_MATCH side=night … holds=true` with minute values
     from 1110 up or below 180 (18:30 to 03:00); SEST agrees; the mission
     is dark.
4. **A city.** On a planet with a city, point at the city's operation
   before pressing F7 (`THIS CITY ONLY`). Hover the city and read SEST.
   Choose the side it is on now, if it has at least 2.5 hours of that side
   left (Day: SEST before 15:00; Night: after 18:30 or before 03:00).
   - Pass: the panel reads `READY TO SEARCH`; the search matches the city's
     operation with `DAYNIGHT_MATCH … row=<30 or more> … holds=true`.
5. **A city that must wait.** In the same city, choose the other side.
   - Pass: REROLL OPERATIONS stays disabled and the status reads, for
     example, `NIGHT HERE IN 3H 10M`. Write down the countdown and SEST at
     the city. The countdown should reach zero when the city's SEST passes
     18:30 for Night or 06:30 for Day. Reopen the panel later and check
     how far off it was.
   - Fail: the countdown is off by more than a few minutes, or
     `DAYNIGHT_BLOCKED <reason>` appears (send the line).
6. **Twilight band.** Without any time filter, deploy to a mission whose
   SEST is between 17:30 and 18:30, or 05:30 and 06:30, and note SEST and
   whether it looks like day, dusk or night on the ground. This tunes the
   30-minute band (`DayNight.BAND` in `src/day_night.lua`).
7. **Short days.** View a planet or moon whose day is short (a moon's
   operations change side within the hour). Choose Night.
   - Pass: the line reads `STAYS ON THAT SIDE FOR AT LEAST <less than
     2h 30m>` and `SHORT DAYS / DAY <length>`, and a search that matches logs `buffer_s=` with the same
     value.

Send the mod's log after the run, with the SEST readings and what each
mission looked like on the ground.
