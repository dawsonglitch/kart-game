extends SceneTree
## Structural checks on the generated bumper arena. Run headless:
##
##     godot --headless --path . --script tests/test_arena_map.gd
##
## The rink's shape does real work now — the butte in the middle is only
## interesting if its sides genuinely can't be driven up and its four ramps
## genuinely can, and both of those are properties of a heightmap sampled on a
## grid rather than of the numbers written in the script. Everything standing on
## that ground has to be seated on it, too.

var _done := false
var _fails := 0


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail != "" else ""))


func _run() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)

	var terrain := Terrain3D.new()
	terrain.name = "Terrain"
	terrain.set_script(load("res://scripts/arena_terrain_builder.gd"))
	world.add_child(terrain)

	var rink := Node3D.new()
	rink.name = "Rink"
	rink.set_script(load("res://scripts/arena_builder.gd"))
	world.add_child(rink)

	var shape: GDScript = load("res://scripts/arena_terrain_builder.gd")

	_check_butte(terrain, shape)
	_check_ground_features(terrain, shape)
	_check_props(terrain, rink, shape)
	_check_kickers(terrain, rink, shape)
	_check_spawns(terrain, rink)

	print("\n%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


## The whole point of the butte is that you have to take a ramp. Measured against
## the finished heightmap, not the formula: the grid rounds a thin wall off into
## something climbable, so the wall has to be steep enough to survive sampling.
func _check_butte(terrain: Terrain3D, shape: GDScript) -> void:
	var crown: float = terrain.data.get_height(Vector3.ZERO)
	_check("the butte's crown is at full height", absf(crown - shape.MESA_HEIGHT) < 0.8,
		"y = %.2f" % crown)

	var wall_slope := 0.0
	var mid_wall: float = shape.MESA_RADIUS * (shape.MESA_FLAT + (1.0 - shape.MESA_FLAT) * 0.5)
	for i in range(720):
		var angle: float = TAU * float(i) / 720.0
		var near_ramp := false
		for k in range(shape.SPUR_COUNT):
			var spur: float = TAU * (shape.SPUR_START_TURNS + float(k) / float(shape.SPUR_COUNT))
			if absf(angle_difference(angle, spur)) < deg_to_rad(22.0):
				near_ramp = true
		if near_ramp:
			continue
		var normal: Vector3 = terrain.data.get_normal(
			Vector3(cos(angle) * mid_wall, 0.0, sin(angle) * mid_wall)
		)
		wall_slope = max(wall_slope, rad_to_deg(acos(clamp(normal.y, -1.0, 1.0))))
	# kart_controller.gd sets floor_max_angle to 50 degrees.
	_check("the butte's sides are too steep to climb", wall_slope > 55.0,
		"steepest %.0f deg" % wall_slope)

	var ramp_slope := 0.0
	for k in range(shape.SPUR_COUNT):
		var angle: float = TAU * (shape.SPUR_START_TURNS + float(k) / float(shape.SPUR_COUNT))
		var radius: float = shape.SPUR_OUTER_RADIUS
		while radius > shape.MESA_RADIUS * shape.MESA_FLAT:
			var normal: Vector3 = terrain.data.get_normal(
				Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			)
			ramp_slope = max(ramp_slope, rad_to_deg(acos(clamp(normal.y, -1.0, 1.0))))
			radius -= 1.0
	_check("...but its four ramps are comfortably drivable", ramp_slope < 35.0,
		"steepest %.0f deg" % ramp_slope)


func _check_ground_features(terrain: Terrain3D, shape: GDScript) -> void:
	var rim: float = terrain.data.get_height(Vector3(shape.ARENA_RADIUS - 2.0, 0.0, 0.0))
	var flat: float = terrain.data.get_height(Vector3(shape.SKIRT_INNER_RADIUS - 20.0, 0.0, 0.0))
	_check("the rim banks up into the wall", rim - flat > 7.0, "%.1f m of rise" % (rim - flat))

	var crater: Dictionary = shape.CRATERS[0]
	var center: Vector2 = crater["pos"]
	var floor_y: float = terrain.data.get_height(Vector3(center.x, 0.0, center.y))
	_check("the crater is a real bowl", floor_y < -6.0, "floor y = %.1f" % floor_y)
	# Below -10 and kart_controller.gd respawns anyone who drops in.
	_check("the crater floor stays above the respawn line", floor_y > -10.0,
		"floor y = %.1f" % floor_y)


func _check_props(terrain: Terrain3D, rink: Node3D, shape: GDScript) -> void:
	var counts := {}
	var floating := 0
	var worst := 0.0
	for child in rink.get_children():
		var script: Script = child.get_script()
		if script == null:
			continue
		var kind := String(script.resource_path).get_file().get_basename()
		counts[kind] = counts.get(kind, 0) + 1
		if kind == "jump_pad":
			continue # legitimately sits on top of a ramp, well clear of the ground
		var pos: Vector3 = (child as Node3D).global_position
		var gap: float = absf(pos.y - terrain.data.get_height(Vector3(pos.x, 0.0, pos.z)))
		if gap > 1.2:
			floating += 1
			worst = max(worst, gap)
	print("props: " + str(counts))
	_check("every prop is seated on the ground", floating == 0,
		"%d floating, worst %.2f m" % [floating, worst])
	_check("the whole layout got placed",
		counts.get("boost_pad", 0) == rink.BOOST_RING_COUNT + 4
		and counts.get("jump_pad", 0) == shape.KICKERS.size()
		and counts.get("hazard_oil", 0) == rink.OIL_SLICKS.size()
		and counts.get("item_box", 0) == rink.ITEM_BOX_RING_COUNT
			+ rink.ITEM_BOX_CROWN_COUNT + rink.ITEM_BOX_CRATER_COUNT,
		str(counts))

	var names := []
	for child in rink.get_children():
		names.append(String(child.name))
	for wanted in ["Wall", "Crates", "Grove", "Monument", "Grandstands", "Crowd"]:
		_check("built " + wanted, names.has(wanted))


## Each kicker has to actually stand proud of the ground it sits on, climb at
## something a kart can take, and have its jump pad on the crest. It also has to
## have no walls: these were tilted slabs first, and a bot spent half a test match
## jammed against the flat side of one.
func _check_kickers(terrain: Terrain3D, rink: Node3D, shape: GDScript) -> void:
	var lowest_crest := INF
	var steepest := 0.0
	for index in range(shape.KICKERS.size()):
		var kicker: Dictionary = terrain.kicker_crest(index)
		var crest: Vector2 = kicker["crest"]
		var direction: Vector2 = kicker["direction"]
		var foot: Vector2 = crest - direction * shape.KICKER_RUN_UP
		var crest_y: float = terrain.data.get_height(Vector3(crest.x, 0.0, crest.y))
		var foot_y: float = terrain.data.get_height(Vector3(foot.x, 0.0, foot.y))
		lowest_crest = min(lowest_crest, crest_y - foot_y)
		# Walk the run-up and the drop, and the sides, looking for anything a kart
		# would hit rather than ride.
		var side := Vector2(-direction.y, direction.x)
		var along := 0.0
		while along <= shape.KICKER_RUN_UP + shape.KICKER_DROP:
			var across: float = -shape.KICKER_HALF_WIDTH
			while across <= shape.KICKER_HALF_WIDTH:
				var at: Vector2 = foot + direction * along + side * across
				var normal: Vector3 = terrain.data.get_normal(Vector3(at.x, 0.0, at.y))
				steepest = max(steepest, rad_to_deg(acos(clamp(normal.y, -1.0, 1.0))))
				across += 1.0
			along += 1.0
	_check("kickers stand proud of the ground",
		lowest_crest > shape.KICKER_HEIGHT * 0.7, "lowest is %.1f m" % lowest_crest)
	# kart_controller.gd sets floor_max_angle to 50 degrees. Nothing on or beside a
	# kicker may exceed that, or it is a wall again.
	_check("nothing on a kicker is a wall", steepest < 45.0, "steepest %.0f deg" % steepest)

	var pads := 0
	for child in rink.get_children():
		var script: Script = child.get_script()
		if script == null or not String(script.resource_path).ends_with("jump_pad.gd"):
			continue
		pads += 1
		var pos: Vector3 = (child as Node3D).global_position
		var ground: float = terrain.data.get_height(Vector3(pos.x, 0.0, pos.z))
		if absf(pos.y - ground) > 0.5:
			_fails += 1
			print("     a jump pad is %.2f m off the ground" % absf(pos.y - ground))
	_check("one jump pad per kicker", pads == shape.KICKERS.size(), "%d pads" % pads)


## Karts spawn evenly round a ring, so the spacing changes with the size of the
## field — a spawn that is clear for two players can be inside a crate stack for
## five.
func _check_spawns(terrain: Terrain3D, rink: Node3D) -> void:
	var solids: Array = []
	_collect_solids(rink, solids)
	var worst := INF
	var worst_desc := ""
	var off_ground := 0
	for field in range(1, 6):
		for i in range(field):
			var start: Transform3D = rink.get_start_transform(float(i) / float(field))
			for solid in solids:
				var d: float = Vector2(start.origin.x - solid.x, start.origin.z - solid.z).length()
				if d < worst:
					worst = d
					worst_desc = "field of %d, kart %d" % [field, i]
			var ground: float = terrain.data.get_height(
				Vector3(start.origin.x, 0.0, start.origin.z)
			)
			if absf(start.origin.y - 0.6 - ground) > 0.1:
				off_ground += 1
	_check("every spawn is on the ground", off_ground == 0)
	_check("no spawn sits on an obstacle", worst > 6.0,
		"closest %.1f m, %s" % [worst, worst_desc])


func _collect_solids(node: Node, into: Array) -> void:
	for child in node.get_children():
		if child is StaticBody3D:
			into.append((child as Node3D).global_position)
		_collect_solids(child, into)
