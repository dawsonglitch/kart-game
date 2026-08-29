# kart-game

A little kart driving game I made for my kids. Godot 4.7, split-screen, keyboard only.

## Modes

- **🏁 Race** — 3 laps around a procedurally built circuit with banked corners, a
  road that widens and pinches, two big jumps, a viaduct over a gorge, boost pads,
  oil slicks, and swinging log obstacles. Live position readout in the corner.
- **💥 Bumper Arena** — no laps: an open rink built around a plateau you can only
  reach up four ramps, with a banked rim, a crater, jump kickers and a pillar
  grove, played as a **two-minute match**. Whoever *caused* the most crashes when the
  clock runs out wins. Turn the timer off on the main menu for the old
  open-ended rink that never ends.

Either mode can be 1 or 2 players, with 0–3 AI bots joining the field.

## Who caused that crash?

The arena scores crashes you *made happen*, not crashes you were in — otherwise
the kid getting bullied round the rink would be winning. So every crash in the
game names a culprit, or nobody:

| What happened | Who gets the point |
|---|---|
| One kart drives into another | Whoever was closing on the contact faster |
| A genuine head-on, both flat out | Both of them |
| A rocket connects | Whoever fired it |
| You spin off someone's dropped oil into something | Whoever dropped it |
| You get punted into a wall, a log, or a third kart | Whoever punted you |
| You bin it into a wall all by yourself | Nobody |
| A shield eats the hit | Nobody — it never landed |

Blame carries for a beat or two after you're hit, which is what makes chain
reactions work: rocket someone into a third kart and *both* crashes are yours.
Ties at full time go to whoever was crashed into least.

The rules live in `kart_controller.gd` (the `crashed` signal and the
`mark_blame` / `get_blame_source` pair around it), with the tally in
`arena_manager.gd`. They're fiddly enough to be worth pinning down:

```
godot --headless --path . --script tests/test_crash_blame.gd
```

The generated maps have their own checks — structure and placement, plus a slower
one that puts the AI field on the track and watches it drive:

```
godot --headless --path . --script tests/test_track_map.gd
```

```
godot --headless --path . --script tests/test_arena_map.gd
```

```
godot --headless --path . --script tests/test_track_driving.gd
```

## Controls

| | Steer | Go | Brake / reverse | Use item |
|---|---|---|---|---|
| Player 1 | Arrow keys | ↑ | ↓ | Right Shift |
| Player 2 | A / D | W | S | Left Shift |

`Esc` pauses.

## Power-ups

Drive through a floating `?` box to pick one up (one at a time). Whoever's further
back gets better odds on the aggressive items, so a kid who's behind can still
catch up. Items can be switched off entirely on the main menu.

| | Item | What it does |
|---|---|---|
| 🔥 | Turbo | A big speed burst — stronger and longer than a track boost pad |
| 🚀 | Rocket | Fires forward and gently homes in on whoever's ahead; dodgeable |
| 🛢 | Oil Slick | Drops behind you; whoever hits it loses grip. Fades after ~14s |
| 🛡 | Shield | Absorbs the next hit, then pops |

## Bots

Bots run the *same* driving model players do — same physics, same items, same
crashes, no cheating. In a race they follow the track spline, brake for corners,
and unstick themselves if they get wedged; in the arena they hunt whoever's
closest and detour for item boxes. Each has a fixed name, color, and skill level
(see `BOT_PROFILES` in `autoload/game_settings.gd`).

## The circuit

About 890 m a lap, in three parts that look and drive differently:

| | |
|---|---|
| **Meadow** | The start/finish straight past the grandstands — 16 m wide, room for the whole grid. A fast banked left onto the east straight, which is painted down the middle: pick the boost-pad lane or the item-box lane. Then a pinched chicane. |
| **Canyon** | The climb to Ramp 1 and the drop off its lip, a stone arch gallery over the landing straight, a second lane split, and then the viaduct — the narrowest road on the lap, railed both sides, spanning a gorge with water 30 m below. |
| **Forest** | Ramp 2 climbing back north, a tight banked corner through the trees, and the run down to the line. |

Corners bank into themselves and the road width changes as you go round, both
generated from the layout rather than authored — see `road_ribbon.gd`. Editing
`WAYPOINTS` in `track_builder.gd` moves everything else with it: the pads,
hazards, checkpoints, structures, terrain and scenery are all placed relative to
the waypoints, not at fixed distances.

## The arena

225 m of open rink, with somewhere to go:

- **The butte** — a plateau in the middle with sides too steep to climb, reachable
  only up four long ramps. There's a monument and a ring of item boxes on top, and
  a long way down if someone shunts you off.
- **The banking** — the ground sweeps up into the boundary wall, so the rim is a
  velodrome rather than something you scrape along.
- **The crater**, a bowl in the north-west with item boxes at the bottom; **the
  grove**, a stand of pillars to lose someone in; four **kickers** shaped into the
  ground with jump pads on their crests; a **boost ring** set tangentially; crate
  pyramids and oil slicks.

## Layout

```
autoload/    GameSettings (cross-scene state), AudioManager (SFX/ambience)
scenes/      main_menu, race, arena, kart, hud, item_box, rocket, hazards, pads
scripts/     one per scene, plus ai_driver.gd, item_kind.gd, crash_blame.gd,
             and the track/arena builders:
               road_ribbon.gd   the road surface mesh — banking and varying width
               track_ground.gd  the height field the terrain and the props share
               track_props.gd   viaduct, arch gallery, grandstands, barriers
tests/       headless GDScript checks for the crash-attribution rules
shaders/     toon.gdshader — the cel-shaded look everything shares
```

Tracks, terrain, scenery, the arena rink, and the grandstand crowd are all
generated in code at runtime rather than hand-placed — see `track_builder.gd` and
`arena_builder.gd`. The racetrack's ground is defined once in `track_ground.gd`
and used by both the props (so a tree stands on the ground) and the Terrain3D
heightmap (so the ground is where the tree thinks it is).

Sound effects come from the bundled *Sound FX Starter Pack Vol. 1*;
`autoload/audio_manager.gd` maps short gameplay names onto the clip paths.
