extends Control
## Title screen: pick a mode (lap race or the open bumper arena), which course to
## run — the built-in one or any track saved in the designer — how many bots join
## in, whether power-ups are on, 1 or 2 players, name your kart, and choose its
## color. The Designer button opens track_editor.gd on whatever the picker has
## selected.

@onready var name1_field: LineEdit = $Center/VBox/Row1/Name1Field
@onready var name2_field: LineEdit = $Center/VBox/Row2/Name2Field
@onready var color1_button: ColorPickerButton = $Center/VBox/Row1/ColorButton1
@onready var color2_button: ColorPickerButton = $Center/VBox/Row2/ColorButton2
@onready var race_mode_button: Button = $Center/VBox/ModeRow/RaceModeButton
@onready var arena_mode_button: Button = $Center/VBox/ModeRow/ArenaModeButton
@onready var items_button: Button = $Center/VBox/BotRow/ItemsButton
@onready var timer_button: Button = $Center/VBox/BotRow/TimerButton
@onready var track_option: OptionButton = $Center/VBox/TrackRow/TrackOption
@onready var design_button: Button = $Center/VBox/TrackRow/DesignButton
@onready var one_player_button: Button = $Center/VBox/OnePlayerButton
@onready var two_player_button: Button = $Center/VBox/TwoPlayerButton

var _selected_mode: int = GameSettings.GameMode.RACE
var _selected_bots: int = GameSettings.bot_count

## The 0-3 bot buttons, gathered once so selecting one can un-press the others —
## same one-of-a-set pattern the two mode buttons use.
var _bot_buttons: Array[Button] = []

## Library ids for the entries in the track picker, in the same order. Index 0 is
## always "" — the built-in course for the selected mode — so a fresh install
## with nothing saved still has something to pick.
var _track_ids: Array[String] = []


func _ready() -> void:
	name1_field.text = GameSettings.player1_name
	name2_field.text = GameSettings.player2_name
	color1_button.color = GameSettings.player1_color
	color2_button.color = GameSettings.player2_color
	# Default to the wheel layout rather than the rectangle — that's the "color wheel" look.
	color1_button.get_picker().picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	color2_button.get_picker().picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	track_option.item_selected.connect(_on_track_selected)
	design_button.pressed.connect(_on_design_pressed)
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
	# A saved arena can't be raced on and a saved lap can't be a bumper match, so
	# the picker only ever offers courses that fit the mode you're in.
	_refresh_track_list()
	if not silent:
		AudioManager.play("ui_click", -8.0)


func _select_bots(count: int, silent: bool = false) -> void:
	_selected_bots = count
	for i in range(_bot_buttons.size()):
		_bot_buttons[i].button_pressed = (i == count)
	if not silent:
		AudioManager.play("ui_click", -8.0)


## Rebuilds the picker from the library, keeping the previously chosen track
## selected if it's still there and still matches the mode.
##
## Deliberately does not write back what it ends up selecting: flipping to the
## other mode to look at it and flipping back would otherwise forget which track
## you had picked, because the track isn't in the list while the other mode is
## showing. GameSettings.custom_design_id is only written when you actually
## choose something, or start a session.
func _refresh_track_list() -> void:
	var wanted: String = _selected_track_id()
	if wanted == "":
		wanted = GameSettings.custom_design_id
	track_option.clear()
	_track_ids.clear()

	var built_in := (
		"💥 Bumper Arena (built in)" if _selected_mode == GameSettings.GameMode.ARENA
		else "🏁 Kart Dash Circuit (built in)"
	)
	track_option.add_item(built_in)
	_track_ids.append("")

	for entry in TrackLibrary.list_designs():
		if int(entry["kind"]) != _selected_mode:
			continue
		track_option.add_item("⭐ %s" % String(entry["name"]))
		_track_ids.append(String(entry["id"]))

	var restored: int = _track_ids.find(wanted)
	track_option.select(restored if restored >= 0 else 0)


func _selected_track_id() -> String:
	var index: int = track_option.selected
	return _track_ids[index] if index >= 0 and index < _track_ids.size() else ""


func _on_track_selected(_index: int) -> void:
	GameSettings.custom_design_id = _selected_track_id()
	AudioManager.play("ui_click", -8.0)


## Opens the designer on the track that's currently picked, or on a fresh
## template of the right kind when the built-in course is selected — the built-in
## ones aren't designs and can't be edited, but "I picked Arena and pressed
## Designer" clearly means "make me an arena".
func _on_design_pressed() -> void:
	var id := _selected_track_id()
	GameSettings.editor_design = TrackLibrary.load_design(id) if id != "" else null
	GameSettings.editor_design_id = id if GameSettings.editor_design != null else ""
	if GameSettings.editor_design == null:
		GameSettings.editor_design = TrackDesign.from_template(
			"rink" if _selected_mode == GameSettings.GameMode.ARENA else "oval"
		)
	GameSettings.exit_scene_path = "res://scenes/main_menu.tscn"
	GameSettings.exit_label = "Main Menu"
	AudioManager.play("ui_click", -4.0)
	get_tree().change_scene_to_file("res://scenes/track_editor.tscn")


func _on_items_toggled(enabled: bool) -> void:
	items_button.text = "🎁 Items: On" if enabled else "🎁 Items: Off"


## Arena only: on, the rink runs as a timed match and the most crashes caused
## wins it; off, it never ends and the crash count is just a running tally.
func _on_timer_toggled(enabled: bool) -> void:
	timer_button.text = "⏱ 2 Min Match" if enabled else "⏱ No Time Limit"


func _start(player_count: int) -> void:
	GameSettings.player1_name = name1_field.text.strip_edges() if name1_field.text.strip_edges() != "" else "Player 1"
	GameSettings.player2_name = name2_field.text.strip_edges() if name2_field.text.strip_edges() != "" else "Player 2"
	GameSettings.player1_color = color1_button.color
	GameSettings.player2_color = color2_button.color
	GameSettings.player_count = player_count
	GameSettings.bot_count = _selected_bots
	GameSettings.items_enabled = items_button.button_pressed
	GameSettings.arena_timed = timer_button.button_pressed
	# Leaving a session from here comes back here — the editor is the only thing
	# that redirects it, and it puts this back when you return to the menu.
	GameSettings.exit_scene_path = "res://scenes/main_menu.tscn"
	GameSettings.exit_label = "Main Menu"
	GameSettings.editor_design = null

	var track_id := _selected_track_id()
	GameSettings.custom_design_id = track_id
	var chosen: TrackDesign = TrackLibrary.load_design(track_id) if track_id != "" else null
	if track_id != "" and chosen == null:
		# The file was deleted or corrupted since the list was built. Fall back to
		# the built-in course rather than refusing to start.
		push_warning("Main menu: saved track '%s' couldn't be loaded" % track_id)
		_refresh_track_list()
	# Sets game_mode and next_scene_path together, so a saved arena can't be
	# launched into the race scene or vice versa.
	GameSettings.select_design(chosen, _selected_mode)
	AudioManager.play("ui_click", -4.0)
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
