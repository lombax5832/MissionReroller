# Day and night on the war table

Research for the Day / Night filter (planned for v0.27.0). Every RVA refers to
build 25480438. Live readings were made on 2026-09-30 through Memory Explorer
v0.2.1 with the ship over planet 201.

## Decision record

- The filter offers Any / Day / Night, default Any, and is ANDed with the
  mission, modifier and enemy force filters.
- Strict: a mission matches only when it stays on the chosen side, outside a
  fixed twilight band around the terminator, from the seed write until
  2.5 hours later. The band width is a tunable constant, tuned from drops.
- Cities do not move. When only a city can satisfy the filters (city scope,
  or filters only a city mission meets) and no eligible city qualifies, the
  dialog refuses to search and shows a countdown such as `Night here in
  1h 40m`, re-evaluated every frame. Whole-planet searches that may produce
  non-city missions are always allowed, since a reroll moves those pins.
- The buffer is checked against the predicted write time, again just before
  the write (a failed candidate resumes the search), and on the verified
  board.
- No time-left readout or per-mission marker in the result or preview.
- Day lengths differ per planet (15.7 hours on planet 201, about 71 minutes
  on a moon). Where half a day cannot hold 2.5 hours the buffer is capped at
  `min(2.5 h, 0.5 * (half_day - 2 * band))`, and the dialog shows the
  buffer it will use.

## What the game does

- **Clock.** The board holds galactic war time as a double in seconds at
  board+0x1f8058 (copies at +0x46028 and +0x147460). It advances with frame
  time and is re-synced when it drifts more than 300 s (12cf280, 12cf990).
  War time 0 is about Unix 1706040314 (2024-01-23 20:05 UTC).
- **Time of day.** 1017ef0 computes the ship view's time of day in minutes
  (0..1440, 720 noon, 0 midnight) and stores it at ui_root+0x78ae668
  (ui_root is the global at 3326340). GameStart telemetry sends it as
  `time_of_day` (serializer bf6c00, caller 1345000). The shader variables
  `day_night_cycle` (= minutes / 1440) and `night_amount` come from the same
  environment (acc241). Readers treat `night_amount > 0.5` as night.
- **Geometry.** The published environment (ui_root+0x78ad430) holds the sun
  direction at +0x120c in the ship camera's frame. Rotating its negation by
  the inverse of the camera quaternion (ship settings ui_root+0x78abfb8,
  quaternion at +0xc) gives the sun in the planet frame. There the sun lies
  in the equatorial plane (z within 0.0006 of 0) and turns about +Z at a
  constant rate, so the time of day at a point depends only on longitude:

  ```
  tod = (720 + 4 * (node_lon - sun_lon)) mod 1440     -- degrees to minutes
  ```

  On planet 201 every point is lit for exactly half of the day. Moons and
  tilted bodies differ (next section).
- **Mission positions.** A level node of the planet definitions
  (definitions + i*0x88) holds a unit position vector at +0x04..+0x0c, its
  own index at +0x10 and its kind at +0x14. node_lon = atan2(y, x).
- **The ship camera** looks at the cursor's point on the globe, not exactly
  at the selected node, so the live value differs from a node's value by
  the cursor's offset. Planet 201 node 357 with the cursor on it matched to
  0.01 minute; node 127 with the cursor 4.2 degrees east read 16.8 minutes
  later, as the formula predicts for the camera direction.

## Live measurements, planet 201

| War time | Sun longitude (planet frame) |
| --- | --- |
| 84732609.5 | -125.955 |
| 84733261.8 | -130.061 |

The sun's longitude falls by 0.0063646 degrees per war second: a day of
56553 s, 15.71 hours. Night at node 127 read `night_amount` 1.0 at 01:08;
day at node 357 read 0.0 at 14:14.

## The viewed planet

The ship environment stays on the ship's planet. The war-table map UI
(global 3326aa0, `map_ui` in `src/offsets.lua`) runs its own environment
update for the viewed planet (725160 calls 1023d70 at 72a357): seed at
map_ui+0x23b0, settings at +0x24d0 (quaternion +0xc, viewer body +0x2c),
environment at +0x2530. The hover label `SEST %02u:%02u:%02u` (1430450) is
1017ef0 on that environment at the cursor point, times 60.

Bodies are env + b*0x1c0: quaternions at +0x94 and +0xa4, parent byte at
+0x171 (9 none), distance +0x174, orbit period range +0x188/+0x18c, spin
period range +0x190/+0x194, phase range +0x1b4/+0x1b8 (radians), orbit and
spin lerp factors at +0x1c0/+0x1c4. With `u(x) = hi32(x*0x5851f42d4c957f2d
+ 0x14057b7ef767814f) * 2^-32` and `ang(T,P,ph) = fmod(T/(P+0.001)*2pi + ph,
2pi)`:

```
World(L) = Q(L+0x94) * Trans(0, dist, 0) * rotZ(ang(T, orbit, phase(u(seed+L+0x10ec)))) * Q(L+0xa4)
           * World(parent)                                   -- 101c7c0
Ms       = rotZ(ang(T, spin, phase(u(seed+b+0x10e3))))       -- 1022270
sun      = normalize(row3(inverse(World(b)) * inverse(Ms)))  -- star at the origin
```

| Body | Day | Check |
| --- | --- | --- |
| Planet 201 (ship) | 56553 s | model within 0.036 degrees |
| Planet 268, a moon of body 1 | about 4260 s | within 0.012 degrees at T - 6.3 s, 0.51 at T |

On the moon the sun sits 4.8 degrees off the equator and its longitude is
not linear in time, so the port evaluates the chain at each time and uses
1017ef0 itself rather than the longitude shortcut. The 6.3 s lag of the
map's environment is unexplained and small (0.5 degrees).

## Open
- **In-mission lighting.** Whether the level's lighting equals the time of
  day at the mission's node at deployment. The in-game test plan checks it.
- **Twilight band.** Its width in minutes, from a dawn or dusk drop.
