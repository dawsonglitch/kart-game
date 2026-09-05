extends Control
## Title screen: pick a mode (lap race or the open bumper arena), how many bots
## join in, whether power-ups are on, 1 or 2 players, name your kart, and choose
## its color and car.

@onready var name1_field: LineEdit = $Center/VBox/Row1/Name1Field
@onready var name2_field: LineEdit = $Center/VBox/Row2/Name2Field
@onready var color1_button: ColorPickerButton = $Center/VBox/Row1/ColorButton1
@onready var color2_button: ColorPickerButton = $Center/VBox/Row2/ColorButton2
@onready var vehicle1_button: OptionButton = $Center/VBox/Row1/Vehicle1Button
@onready var vehicle2_button: OptionButton = $Center/VBox/Row2/Vehicle2Button
@onready var race_mode_button: Button = $Center/VBox/ModeRow/RaceModeButton
@onready var arena_mode_button: Button = $Center/VBox/ModeRow/ArenaModeButton
@onready var items_button: Button = $Center/VBox/BotRow/ItemsButton
@onready var timer_button: Button = $Center/VBox/BotRow/TimerButton
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
	_setup_vehicle_picker(vehicle1_button, GameSettings.player1_vehicle)
	_setup_vehicle_picker(vehicle2_button, GameSettings.player2_vehicle)
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

	timer_button.button_pressed = GameSettings.arena_timed
	timer_button.toggled.connect(_on_timer_toggled)
	_on_timer_toggled(timer_button.button_pressed)

	_select_mode(GameSettings.GameMode.RACE, true)
	_select_bots(_selected_bots, true)
	name1_field.grab_focus()


func _setup_vehicle_picker(button: OptionButton, selected_id: int) -> void:
	button.clear()
	for option in VehicleCatalog.OPTIONS:
		button.add_item(option["name"], option["id"])
	button.select(button.get_item_index(VehicleCatalog.valid_id(selected_id)))
	button.item_selected.connect(func(_index: int): AudioManager.play("ui_click", -8.0))


## Both mode buttons use toggle_mode so exactly one stays visually pressed — click
## either one to select it, rather than needing a separate confirm step.
## `silent` is set for the initial setup in _ready(), so opening the menu doesn't
## fire off a couple of click sounds nobody clicked.
func _select_mode(mode: int, silent: bool = false) -> void:
	_selected_mode = mode
	race_mode_button.button_pressed = (mode == GameSettings.GameMode.RACE)
	arena_mode_button.button_pressed = (mode == GameSettings.GameMode.ARENA)
	# The match clock only means anything in the arena — a race ends on laps —
	# so the button greys out rather than sitting there implying otherwise.
	timer_button.disabled = (mode != GameSettings.GameMode.ARENA)
	timer_button.modulate = Color(1, 1, 1, 1.0 if not timer_button.disabled else 0.45)
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


## Arena only: on, the rink runs as a timed match and the most crashes caused
## wins it; off, it never ends and the crash count is just a running tally.
func _on_timer_toggled(enabled: bool) -> void:
	timer_button.text = "⏱ 2 Min Match" if enabled else "⏱ No Time Limit"


func _start(player_count: int) -> void:
	_save_settings(player_count)
	AudioManager.play("ui_click", -4.0)
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")


func _save_settings(player_count: int) -> void:
	GameSettings.player1_name = name1_field.text.strip_edges() if name1_field.text.strip_edges() != "" else "Player 1"
	GameSettings.player2_name = name2_field.text.strip_edges() if name2_field.text.strip_edges() != "" else "Player 2"
	GameSettings.player1_color = color1_button.color
	GameSettings.player2_color = color2_button.color
	GameSettings.player1_vehicle = vehicle1_button.get_selected_id()
	GameSettings.player2_vehicle = vehicle2_button.get_selected_id()
	GameSettings.player_count = player_count
	GameSettings.game_mode = _selected_mode
	GameSettings.bot_count = _selected_bots
	GameSettings.items_enabled = items_button.button_pressed
	GameSettings.arena_timed = timer_button.button_pressed
	GameSettings.next_scene_path = (
		"res://scenes/arena.tscn" if _selected_mode == GameSettings.GameMode.ARENA
		else "res://scenes/race.tscn"
	)
