extends Node
## Autoload singleton — the only state that needs to survive scene changes.
## Set by main_menu.gd before loading race.tscn/arena.tscn.

enum GameMode { RACE, ARENA }

## Which mode the main menu's Play buttons launch — race.tscn's lap race, or
## arena.tscn's open crash-into-each-other rink.
var game_mode: int = GameMode.RACE

## The scene loading_screen.gd loads next. Set alongside game_mode so restarting
## (from race.gd/arena.gd) and the initial menu->game transition both go through
## the same loading path without loading_screen.gd needing to know about modes.
var next_scene_path: String = "res://scenes/race.tscn"

## 1 = single player (free drive / time trial), 2 = two players split-screen.
var player_count: int = 1

## Set from the name fields on the main menu; shown as each kart's name tag
## (visible only in the *other* player's viewport — see kart_controller.gd).
var player1_name: String = "Player 1"
var player2_name: String = "Player 2"

## Set from the color wheels on the main menu; applied to each kart's paint via
## kart_controller.gd's set_kart_color().
var player1_color: Color = Color(0.85, 0.15, 0.15)
var player2_color: Color = Color(0.15, 0.4, 0.9)

## How many AI-driven karts join the field, 0-3. Set from the main menu; race.gd
## and arena.gd instance that many extra karts and attach an AIDriver to each.
var bot_count: int = 2

## Bumper arena only: run the rink as a timed match. On, the session ends after
## ARENA_MATCH_SECONDS and whoever caused the most crashes takes it; off keeps
## the original open-ended rink that never ends on its own. Crashes are
## attributed and counted either way.
var arena_timed: bool = true

## How long a timed arena match runs. Two minutes is about as long as a round
## holds a kid's attention, and short enough that losing one isn't a big deal.
const ARENA_MATCH_SECONDS := 120.0

## Master switch for the item-box power-ups. Off gives the original pure-driving
## game, which is the better one for a kid still learning to steer.
var items_enabled: bool = true

## Bot identities, indexed in order as bots are added. Names and colors are fixed
## rather than random so the same bot is recognizably "the yellow one" every race;
## skill is spread so the field isn't three clones of the same driver.
const BOT_PROFILES := [
	{"name": "Zippy", "color": Color(0.95, 0.8, 0.15), "skill": 0.72},
	{"name": "Turbo Tina", "color": Color(0.25, 0.8, 0.35), "skill": 0.86},
	{"name": "Rusty", "color": Color(0.85, 0.45, 0.15), "skill": 0.6},
]

## The last finished session's standings, best first. race_manager.gd fills it
## with [{player_id, display_name, total_time, is_ai, place}, ...] in finish
## order; arena_manager.gd fills it with [{player_id, display_name,
## crashes_caused, crashes_taken, is_ai, place}, ...] when the clock runs out.
var last_results: Array = []
