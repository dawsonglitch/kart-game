extends Node3D
## Wires together the shared world, per-player split-screen viewports/cameras, HUDs,
## and the race manager. Reads GameSettings.player_count to decide 1-player (full
## screen) vs 2-player (top/bottom split) layout.

const LANE_OFFSET := 2.2

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

	_place_kart(kart1, -LANE_OFFSET)
	kart1.set_display_name(GameSettings.player1_name)
	kart1.set_kart_color(GameSettings.player1_color)
	race_manager.register_kart(kart1)
	cam1.set_target(kart1)
	hud1.setup(kart1, race_manager)
	# Terrain3D's LOD system needs one reference camera; it can't auto-find one since
	# both cameras live inside SubViewports rather than the base window viewport.
	terrain.set_camera(cam1)

	if two_player:
		_place_kart(kart2, LANE_OFFSET)
		kart2.set_display_name(GameSettings.player2_name)
		kart2.set_kart_color(GameSettings.player2_color)
		race_manager.register_kart(kart2)
		cam2.set_target(kart2)
		hud2.setup(kart2, race_manager)

	pause_menu.hide()
	pause_menu.restart_requested.connect(_on_restart_requested)
	pause_menu.quit_requested.connect(_on_quit_requested)

	race_manager.start_countdown()


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


func _place_kart(kart: CharacterBody3D, lane_offset: float) -> void:
	kart.global_transform = track.get_start_transform(lane_offset)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()


func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_menu.visible = get_tree().paused


func _on_restart_requested() -> void:
	get_tree().paused = false
	# Route through the loading screen rather than reload_current_scene() — restart
	# re-runs the same terrain/texture setup in _ready(), which is exactly the load
	# the loading screen exists to cover, not just the initial menu->race transition.
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")


func _on_quit_requested() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
