extends SceneTree
## Run after an editor import:
## godot --headless --path . --script tests/test_vehicle_selection.gd
## Add -- race or -- arena to check a full mode's player/bot wiring.

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_fails += 1


func _run() -> void:
	var settings = root.get_node("GameSettings")
	var catalog = load("res://scripts/vehicle_catalog.gd")
	var jeep: int = catalog.Kind.CODEX_JEEP
	var classic: int = catalog.Kind.CLASSIC_KART
	var menu_scene = load("res://scenes/main_menu.tscn")
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	_check("both players can choose either car", menu.vehicle1_button.item_count == 2 and menu.vehicle2_button.item_count == 2)
	menu.vehicle1_button.select(menu.vehicle1_button.get_item_index(jeep))
	menu.vehicle2_button.select(menu.vehicle2_button.get_item_index(classic))
	menu._save_settings(2)
	_check("menu saves independent choices", settings.player1_vehicle == jeep and settings.player2_vehicle == classic)
	menu.free()
	menu = menu_scene.instantiate()
	root.add_child(menu)
	_check("returning to menu restores choices", menu.vehicle1_button.get_selected_id() == jeep and menu.vehicle2_button.get_selected_id() == classic)
	menu.free()

	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await _check_mode(args[0], settings, jeep, classic)
	else:
		_check_models(jeep, classic)
	await process_frame
	print("\n%d failure(s)" % _fails)
	quit(1 if _fails else 0)


func _check_models(jeep: int, classic: int) -> void:
	var packed = load("res://scenes/kart.tscn")
	var a = packed.instantiate()
	var b = packed.instantiate()
	a.set_vehicle(jeep) # Also supports configuration before entering the tree.
	root.add_child(a)
	root.add_child(b)
	b.set_vehicle(jeep)
	_check("Jeep loads before and after ready", a._vehicle_model != null and b._vehicle_model != null)
	_check("classic geometry is hidden for Jeep", not a.get_node("Chassis/LowerBody").visible)
	_check("imported paint surface is found", a._vehicle_paint.size() == 1 and b._vehicle_paint.size() == 1)
	a.set_kart_color(Color.RED)
	b.set_kart_color(Color.BLUE)
	if a._vehicle_paint.size() == 1 and b._vehicle_paint.size() == 1:
		_check("two Jeeps have independent paint", a._vehicle_paint[0].albedo_color == Color.RED and b._vehicle_paint[0].albedo_color == Color.BLUE)
	var meshes: Array[Node] = a._vehicle_model.find_children("*", "MeshInstance3D")
	_check("Jeep geometry is consolidated", meshes.size() == 1)
	if meshes.size() == 1:
		var bounds: AABB = meshes[0].get_aabb()
		_check("Jeep fits kart scale and sits on ground", absf(bounds.size.z - 2.5) < 0.01 and absf(bounds.position.y) < 0.01 and bounds.size.x < 1.8)
		_check("all twelve authored materials survive", meshes[0].mesh.get_surface_count() == 12)
		for surface in range(meshes[0].mesh.get_surface_count()):
			var mat = meshes[0].mesh.surface_get_material(surface)
			if mat.resource_name == "codex-lagoon-enamel":
				_check("accent paint is preserved", meshes[0].get_surface_override_material(surface) == null)
	var shape = a.get_node("CollisionShape3D").shape
	a.set_vehicle(classic)
	_check("switching back restores classic visuals", a._vehicle_model == null and a.get_node("Chassis/LowerBody").visible)
	_check("vehicle choice preserves collision and handling", a.get_node("CollisionShape3D").shape == shape and a.max_speed == b.max_speed)
	a.set_vehicle(-42)
	_check("unknown IDs fall back to classic", a.vehicle_id == classic)
	a.free()
	b.free()


func _check_mode(mode: String, settings: Node, jeep: int, classic: int) -> void:
	assert(mode in ["race", "arena"])
	settings.player_count = 2
	settings.bot_count = 1
	settings.player1_vehicle = classic
	settings.player2_vehicle = jeep
	var packed = load("res://scenes/%s.tscn" % mode)
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	_check(mode + " uses P1's classic kart", game.kart1._vehicle_model == null and game.kart1.vehicle_id == classic)
	_check(mode + " uses P2's Jeep", game.kart2._vehicle_model != null and game.kart2.vehicle_id == jeep)
	var bots := 0
	for kart in get_nodes_in_group("karts"):
		if kart.is_ai:
			bots += 1
			_check(mode + " keeps bot's classic kart", kart.vehicle_id == classic)
	_check(mode + " spawns the requested bot", bots == 1)
	game.free()
	await process_frame
