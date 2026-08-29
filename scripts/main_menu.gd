extends Control
## Title screen: pick a mode (lap race or the open bumper arena), how many bots
## join in, whether power-ups are on, 1 or 2 players, name your kart, and choose
## its color.

@onready var name1_field: LineEdit = $Center/VBox/Row1/Name1Field
@onready var name2_field: LineEdit = $Center/VBox/Row2/Name2Field
@onready var color1_button: ColorPickerButton = $Center/VBox/Row1/ColorButton1
@onready var color2_button: ColorPickerButton = $Center/VBox/Row2/ColorButton2
@onready var race_mode_button: Button = $Center/VBox/ModeRow/RaceModeButton
@onready var arena_mode_button: Button = $Center/VBox/ModeRow/ArenaModeButton
@onready var items_button: Button = $Center/VBox/BotRow/ItemsButton
@onready var one_player_button: Button = $Center/VBox/OnePlayerButton
@onready var two_player_button: Button = $Center/VBox/TwoPlayerButton

var _selected_mode: int = GameSettings.GameMode.RACE
var _selected_bots: int = GameSettings.bot_count

## The 0-3 bot buttons, gathered once so selecting one can un-press the others —
## same one-of-a-set pattern the two mode buttons use.
var _bot_buttons: Array[Button] = []


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

	for count in range(4):
		var button: Button = $Center/VBox/BotRow.get_node("Bots%dButton" % count)
		_bot_buttons.append(button)
		button.pressed.connect(_select_bots.bind(count))

	items_button.button_pressed = GameSettings.items_enabled
	items_button.toggled.connect(_on_items_toggled)
	_on_items_toggled(items_button.button_pressed)

	_select_mode(GameSettings.GameMode.RACE, true)
	_select_bots(_selected_bots, true)
	name1_field.grab_focus()


## Both mode buttons use toggle_mode so exactly one stays visually pressed — click
## either one to select it, rather than needing a separate confirm step.
## `silent` is set for the initial setup in _ready(), so opening the menu doesn't
## fire off a couple of click sounds nobody clicked.
func _select_mode(mode: int, silent: bool = false) -> void:
	_selected_mode = mode
	race_mode_button.button_pressed = (mode == GameSettings.GameMode.RACE)
	arena_mode_button.button_pressed = (mode == GameSettings.GameMode.ARENA)
	if not silent:
		AudioManager.play("ui_click", -8.0)


func _select_bots(count: int, silent: bool = false) -> void:
	_selected_bots = count
	for i in range(_bot_buttons.size()):
		_bot_buttons[i].button_pressed = (i == count)
	if not silent:
		AudioManager.play("ui_click", -8.0)


func _on_items_toggled(enabled: bool) -> void:
	items_button.text = "🎁 Items: On" if enabled else "🎁 Items: Off"


func _start(player_count: int) -> void:
	GameSettings.player1_name = name1_field.text.strip_edges() if name1_field.text.strip_edges() != "" else "Player 1"
	GameSettings.player2_name = name2_field.text.strip_edges() if name2_field.text.strip_edges() != "" else "Player 2"
	GameSettings.player1_color = color1_button.color
	GameSettings.player2_color = color2_button.color
	GameSettings.player_count = player_count
	GameSettings.game_mode = _selected_mode
	GameSettings.bot_count = _selected_bots
	GameSettings.items_enabled = items_button.button_pressed
	GameSettings.next_scene_path = (
		"res://scenes/arena.tscn" if _selected_mode == GameSettings.GameMode.ARENA
		else "res://scenes/race.tscn"
	)
	AudioManager.play("ui_click", -4.0)
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
