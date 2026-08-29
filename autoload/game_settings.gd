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

## Filled in by race_manager.gd when a race finishes: [{player_id, total_time}, ...]
var last_results: Array = []
