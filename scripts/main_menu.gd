extends Control
## Title screen: pick a mode (lap race or the open bumper arena), 1 or 2 players,
## name your kart, and choose its color.

@onready var name1_field: LineEdit = $Center/VBox/Row1/Name1Field
@onready var name2_field: LineEdit = $Center/VBox/Row2/Name2Field
@onready var color1_button: ColorPickerButton = $Center/VBox/Row1/ColorButton1
@onready var color2_button: ColorPickerButton = $Center/VBox/Row2/ColorButton2
@onready var race_mode_button: Button = $Center/VBox/ModeRow/RaceModeButton
@onready var arena_mode_button: Button = $Center/VBox/ModeRow/ArenaModeButton
@onready var one_player_button: Button = $Center/VBox/OnePlayerButton
@onready var two_player_button: Button = $Center/VBox/TwoPlayerButton

var _selected_mode: int = GameSettings.GameMode.RACE


func _ready() -> void:
	name1_field.text = GameSettings.player1_name
	name2_field.text = GameSettings.player2_name
	color1_button.color = GameSettings.player1_color
	color2_button.color = GameSettings.player2_color
	# Default to the wheel layout rather than the rectangle — that's the "color wheel" look.
	color1_button.get_picker().picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	color2_button.get_picker().picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	race_mode_button.pressed.connect(func(): _select_mode(GameSettings.GameMode.RACE))
	arena_mode_button.pressed.connect(func(): _select_mode(GameSettings.GameMode.ARENA))
	one_player_button.pressed.connect(func(): _start(1))
	two_player_button.pressed.connect(func(): _start(2))
	_select_mode(GameSettings.GameMode.RACE)
	name1_field.grab_focus()


## Both mode buttons use toggle_mode so exactly one stays visually pressed — click
## either one to select it, rather than needing a separate confirm step.
func _select_mode(mode: int) -> void:
	_selected_mode = mode
	race_mode_button.button_pressed = (mode == GameSettings.GameMode.RACE)
	arena_mode_button.button_pressed = (mode == GameSettings.GameMode.ARENA)


func _start(player_count: int) -> void:
	GameSettings.player1_name = name1_field.text.strip_edges() if name1_field.text.strip_edges() != "" else "Player 1"
	GameSettings.player2_name = name2_field.text.strip_edges() if name2_field.text.strip_edges() != "" else "Player 2"
	GameSettings.player1_color = color1_button.color
	GameSettings.player2_color = color2_button.color
	GameSettings.player_count = player_count
	GameSettings.game_mode = _selected_mode
	GameSettings.next_scene_path = (
		"res://scenes/arena.tscn" if _selected_mode == GameSettings.GameMode.ARENA
		else "res://scenes/race.tscn"
	)
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
