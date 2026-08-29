# kart-game

A little kart driving game I made for my kids. Godot 4.7, split-screen, keyboard only.

## Modes

- **🏁 Race** — 3 laps around a procedurally built track with jumps, boost pads, oil
  slicks, and swinging log obstacles. Live position readout in the corner.
- **💥 Bumper Arena** — no laps: an open rink with a crowd and scattered crates,
  played as a **two-minute match**. Whoever *caused* the most crashes when the
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

## Layout

```
autoload/    GameSettings (cross-scene state), AudioManager (SFX/ambience)
scenes/      main_menu, race, arena, kart, hud, item_box, rocket, hazards, pads
scripts/     one per scene, plus ai_driver.gd, item_kind.gd, crash_blame.gd,
             and the track/arena builders
tests/       headless GDScript checks for the crash-attribution rules
shaders/     toon.gdshader — the cel-shaded look everything shares
```

Tracks, terrain, scenery, the arena rink, and the grandstand crowd are all
generated in code at runtime rather than hand-placed — see `track_builder.gd` and
`arena_builder.gd`.

Sound effects come from the bundled *Sound FX Starter Pack Vol. 1*;
`autoload/audio_manager.gd` maps short gameplay names onto the clip paths.
