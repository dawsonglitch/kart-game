extends Node3D
## Wires together the shared world, per-player split-screen viewports/cameras, HUDs,
## the AI field, and the race manager. Reads GameSettings.player_count to decide
## 1-player (full screen) vs 2-player (top/bottom split) layout, and
## GameSettings.bot_count for how many AI karts join the grid.

const LANE_OFFSET := 2.2
## Front-to-back spacing between grid rows, in metres along the track, so a field
## of four starts staggered like a real grid rather than four-abreast on a
## two-lane road.
const GRID_ROW_SPACING := 5.0

@onready var race_manager: Node = $RaceManager
@onready var world: Node3D = $World
@onready var track: Node3D = $World/Track
@onready var terrain: Terrain3D = $World/Terrain
@onready var kart1: CharacterBody3D = $World/Kart1
@onready var kart2: CharacterBody3D = $World/Kart2

@onready var viewport_container_1: SubViewportContainer = $UI/ViewportContainer1
@onready var viewport_container_2: SubViewportContainer = $UI/ViewportContainer2
@onready var sub_viewport_1: SubViewport = $UI/ViewportContainer1/SubViewport1
@onready var sub_viewport_2: SubViewport = $UI/ViewportContainer2/SubViewport2
@onready var cam1: Camera3D = $UI/ViewportContainer1/SubViewport1/Cam1
@onready var cam2: Camera3D = $UI/ViewportContainer2/SubViewport2/Cam2
@onready var hud1: Control = $UI/HUD1
@onready var hud2: Control = $UI/HUD2
@onready var pause_menu: Control = $UI/PauseMenu

## Loaded at runtime rather than preload()'d — see the note in track_builder.gd
## about preload() and threaded scene loading.
var _kart_scene: PackedScene


func _ready() -> void:
	var shared_world := world.get_world_3d()
	sub_viewport_1.world_3d = shared_world
	sub_viewport_2.world_3d = shared_world

	var two_player := GameSettings.player_count >= 2

	if two_player:
		_layout_split()
	else:
		kart2.queue_free()
		viewport_container_2.visible = false
		sub_viewport_2.render_target_update_mode = SubViewport.UPDATE_DISABLED
		hud2.visible = false
		viewport_container_1.set_anchors_preset(Control.PRESET_FULL_RECT)
		hud1.set_anchors_preset(Control.PRESET_FULL_RECT)

	# The bots rank by distance along the racing line, so the manager needs the
	# track's path before any kart is registered.
	race_manager.track_path = track.get_racing_path()

	_place_kart(kart1, -LANE_OFFSET, 0)
	kart1.set_display_name(GameSettings.player1_name)
	kart1.set_vehicle(GameSettings.player1_vehicle)
	kart1.set_kart_color(GameSettings.player1_color)
	race_manager.register_kart(kart1)
	cam1.set_target(kart1)
	hud1.setup(kart1, race_manager)
	# Terrain3D's LOD system needs one reference camera; it can't auto-find one since
	# both cameras live inside SubViewports rather than the base window viewport.
	terrain.set_camera(cam1)

	if two_player:
		_place_kart(kart2, LANE_OFFSET, 0)
		kart2.set_display_name(GameSettings.player2_name)
		kart2.set_vehicle(GameSettings.player2_vehicle)
		kart2.set_kart_color(GameSettings.player2_color)
		race_manager.register_kart(kart2)
		cam2.set_target(kart2)
		hud2.setup(kart2, race_manager)

	_spawn_bots(two_player)

	pause_menu.hide()
	pause_menu.restart_requested.connect(_on_restart_requested)
	pause_menu.quit_requested.connect(_on_quit_requested)

	AudioManager.start_ambience()
	race_manager.start_countdown()


## Bot karts are instanced rather than sitting in race.tscn, since how many of
## them exist is a menu choice. Each gets an AIDriver child pointed at the track
## path and its own lane offset, so the field spreads across the road instead of
## queueing up in one groove.
func _spawn_bots(two_player: bool) -> void:
	var count: int = clamp(GameSettings.bot_count, 0, GameSettings.BOT_PROFILES.size())
	if count <= 0:
		return
	_kart_scene = load("res://scenes/kart.tscn")
	var track_path: Path3D = track.get_racing_path()
	# Player ids 1 and 2 belong to the humans whether or not player 2 is present,
	# so bots always start at 3 — that keeps each kart's name-tag render layer
	# unique (see kart_controller.gd's NAME_TAG_LAYER_BASE).
	var next_player_id := 3

	for i in range(count):
		var profile: Dictionary = GameSettings.BOT_PROFILES[i]
		var bot: CharacterBody3D = _kart_scene.instantiate()
		bot.is_ai = true
		bot.player_id = next_player_id + i
		world.add_child(bot)
		bot.set_display_name(profile["name"])
		bot.set_kart_color(profile["color"])

		var driver := AIDriver.new()
		driver.mode = AIDriver.Mode.TRACK
		driver.path = track_path
		driver.skill = profile["skill"]
		# Alternate the racing line side by side across the field.
		@warning_ignore("integer_division") # pairs of bots share a lane distance
		var lane_step: int = i / 2
		driver.lane_offset = (-1.0 if i % 2 == 0 else 1.0) * (1.6 + 0.9 * float(lane_step))
		bot.add_child(driver)
		bot.ai_driver = driver

		# Slot bots into grid rows behind the players: with two humans on row 0,
		# bots fill rows 1+ two-abreast; with one human, the first bot shares row 0.
		var slot: int = i + (2 if two_player else 1)
		@warning_ignore("integer_division") # rows are whole numbers by design
		var row: int = slot / 2
		var lane: float = -LANE_OFFSET if slot % 2 == 0 else LANE_OFFSET
		_place_kart(bot, lane, row)
		race_manager.register_kart(bot)


func _layout_split() -> void:
	viewport_container_1.anchor_left = 0.0
	viewport_container_1.anchor_right = 1.0
	viewport_container_1.anchor_top = 0.0
	viewport_container_1.anchor_bottom = 0.5
	viewport_container_1.offset_bottom = -2.0

	viewport_container_2.anchor_left = 0.0
	viewport_container_2.anchor_right = 1.0
	viewport_container_2.anchor_top = 0.5
	viewport_container_2.anchor_bottom = 1.0
	viewport_container_2.offset_top = 2.0

	hud1.anchor_left = 0.0
	hud1.anchor_right = 1.0
	hud1.anchor_top = 0.0
	hud1.anchor_bottom = 0.5

	hud2.anchor_left = 0.0
	hud2.anchor_right = 1.0
	hud2.anchor_top = 0.5
	hud2.anchor_bottom = 1.0


## `row` is how many grid rows back from the start line this kart begins, so a
## field of four doesn't spawn inside each other.
func _place_kart(kart: CharacterBody3D, lane_offset: float, row: int = 0) -> void:
	kart.global_transform = track.get_start_transform(lane_offset)
	# Straight back along the kart's own facing rather than back along the curve:
	# the start/finish area is a straight, so this is both simpler and correct
	# here, and it can't drift off the road the way a negative curve offset
	# (which wraps around to the *end* of the lap) would.
	kart.global_position += kart.global_transform.basis.z * (GRID_ROW_SPACING * row)
	# The respawn point kart_controller.gd captured in its own _ready() predates
	# this placement, so refresh it — otherwise a fall before the first checkpoint
	# would drop the kart back at the scene's origin.
	kart.respawn_position = kart.global_position
	kart.respawn_rotation = kart.rotation


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()


func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_menu.visible = get_tree().paused


func _on_restart_requested() -> void:
	get_tree().paused = false
	AudioManager.stop_ambience()
	# Route through the loading screen rather than reload_current_scene() — restart
	# re-runs the same terrain/texture setup in _ready(), which is exactly the load
	# the loading screen exists to cover, not just the initial menu->race transition.
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")


func _on_quit_requested() -> void:
	get_tree().paused = false
	AudioManager.stop_ambience()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
