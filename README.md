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

- **🛠 Track Designer** — make your own. Start from a template, drag the road
  around, drop trees and jumps and ponds on it, recolour everything, drive it,
  and save it. Saved tracks show up in the **Track** picker on the main menu
  alongside the two built-in courses.

Either mode can be 1 or 2 players, with 0–3 AI bots joining the field.

Each player's **Car** selector offers the original **Classic Kart** and the
Blender-built **Codex Jeep**. Choices carry through races, arena matches, restarts
and returning to the menu. The color swatch changes the Jeep's primary paint;
its teal panels and trim keep their authored colors. Both cars use the same
handling and collision shape, and bots keep the classic kart.

The Jeep is a visual model with static wheels, like the original kart. Its
source/export workflow is in `assets/models/vehicles/README.md`. Selection and
per-player paint have regression checks:

```
godot --headless --path . --script tests/test_vehicle_selection.gd
```

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

Which power-ups each mode can hand out is checked too — a race draws from all
four, the arena only from the weapons and the shield:

```
godot --headless --path . --script tests/test_item_pool.gd
```

## The track designer

`🛠 Designer` on the main menu opens it, on whatever the Track picker has
selected — a saved track to keep working on it, or a built-in course to start
something new of that kind.

You get five starting points: three circuits (**Oval**, **Hill Loop**,
**Twister**) and two rinks (**Open Rink**, **Junkyard**). All five are already
drivable, so a kid who changes nothing still ends up with a working track.

| | |
|---|---|
| **Shape the road** | Drag a red handle. Hold **Shift** while dragging to raise or lower it — that's how you get hills and dips. The **Width** slider widens or pinches the road at that point, and **Add point** puts a new handle further along so you can bend the lap somewhere new. |
| **Build a jump** | **🛫 Make a jump here** on a selected point does the whole thing in one press: it sharpens the road into a lip instead of a smooth curve, drops a landing point in just past it so the road falls away at about twenty-five degrees, and puts a jump pad on the lip. Drag the lip up or down to make it bigger or smaller. A jump needs a reasonably straight stretch; on a corner that's too tight for one the editor says so and puts the road back. |
| **Change your mind** | **↩ Undo** (or Ctrl+Z) takes back the last forty edits — every drag, every colour, every deletion, and a whole jump in one press. Starting a new track, opening another, or going back to the menu all ask before throwing away anything unsaved. |
| **Drop things on it** | Pick something from **Things to add** and click the ground: trees, rocks, crates, jump pads, boost pads, item boxes, oil slicks, bridges and water. Blue handles move them; **Size** and **Turn** adjust the selected one. |
| **Recolour it** | The **Colors** row does the road, the ground, the leaves, the rocks, the water and the sky. |
| **Drive it** | **▶ Test Drive** runs the track you're looking at, unsaved changes and all, and the pause menu comes back to the editor rather than the main menu. |
| **Keep it** | **💾 Save Track** writes it under whatever's in the name box. **📂 Open** lists everything you've saved, to reopen or delete. |
| **Get around** | Drag empty space to spin the view, right-drag to pan, wheel to zoom. The line under the title tells you how long a lap is as you go. |

Saved tracks are JSON files in Godot's per-user data directory
(`user://tracks/`, which is
`~/Library/Application Support/Godot/app_userdata/RacingGameWithKids/tracks` on
this machine) — one file per track, named after the track, safe to copy or back
up.

A player-made course is built by the same code the shipped ones are: the same
`road_ribbon.gd` for the banked, varying-width road, the same `track_ground.gd`
height field under it, the same terrain, pads, boxes, hazards and the crowd
around the start line. What the editor previews is what you drive — the one
exception is the Terrain3D heightmap, which takes seconds to stamp and would
make dragging a handle unusable, so the editor draws its own coarse mesh of the
same height field instead.

One thing the editor watches for and warns about: a corner tighter than the road
is wide can't be built. The road's inner edge laps over the stretch behind it and
that patch comes out wound inside out — invisible, and not solid, so a kart drops
through it. If you draw one, an orange bar says so and tells you how to fix it.

The pieces:

```
track_design.gd          the design itself, as plain data — road nodes, features,
                         colors, the templates, and the JSON it saves as
track_library.gd         user://tracks — save, list, open, delete
track_editor.gd          the editor: the 3D view, the handles, the panel
custom_track_builder.gd  a design -> a race track (road, gates, finish line)
custom_arena_builder.gd  a design -> a bumper rink (floor, wall, spawns)
custom_features.gd       the trees/rocks/jumps/bridges/water, shared by both
custom_terrain_builder.gd  stamps either one's ground into Terrain3D
```

Checked headlessly — the save format, the library, and the worlds both builders
generate:

```
godot --headless --path . --script tests/test_track_design.gd
```

...and the editor's own wiring, driven through its real buttons:

```
godot --headless --path . --script tests/test_track_editor.gd
```

A generated track can also be handed to the AI field, which is the only way to
find out whether a layout is actually drivable rather than merely well formed:

```
godot --headless --path . --script tests/test_track_driving.gd -- twister
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

| | Item | What it does | Arena |
|---|---|---|---|
| 🔥 | Turbo | A big speed burst — stronger and longer than a track boost pad | — |
| 🚀 | Rocket | Fires forward and gently homes in on whoever's ahead; dodgeable | yes |
| 🛢 | Oil Slick | Drops behind you; whoever hits it loses grip. Fades after ~14s | yes |
| 🛡 | Shield | Absorbs the next hit, then pops | yes |

The bumper arena hands out only the weapons and the shield. There's no finish
line to race to, so a turbo there is a wasted pick-up.

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
scenes/      main_menu, race, arena, kart, hud, item_box, rocket, hazards, pads,
             track_editor, and the custom_* variants player-made tracks run in
scripts/     one per scene, plus ai_driver.gd, item_kind.gd, crash_blame.gd,
             and the track/arena builders:
               road_ribbon.gd   the road surface mesh — banking and varying width
               track_ground.gd  the height field the terrain and the props share
               track_props.gd   viaduct, arch gallery, grandstands, barriers,
                                the finish line and the road's material
             the track designer has its own set — see above
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
