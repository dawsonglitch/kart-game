# kart-game

A little kart driving game I made for my kids. Godot 4.7, split-screen, keyboard only.

## Modes

- **🏁 Race** — 3 laps around a procedurally built track with jumps, boost pads, oil
  slicks, and swinging log obstacles. Live position readout in the corner.
- **💥 Bumper Arena** — no laps, no rules: an open rink with a crowd, scattered
  crates, and a crash counter.

Either mode can be 1 or 2 players, with 0–3 AI bots joining the field.

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
scripts/     one per scene, plus ai_driver.gd, item_kind.gd, track/arena builders
shaders/     toon.gdshader — the cel-shaded look everything shares
```

Tracks, terrain, scenery, the arena rink, and the grandstand crowd are all
generated in code at runtime rather than hand-placed — see `track_builder.gd` and
`arena_builder.gd`.

Sound effects come from the bundled *Sound FX Starter Pack Vol. 1*;
`autoload/audio_manager.gd` maps short gameplay names onto the clip paths.
