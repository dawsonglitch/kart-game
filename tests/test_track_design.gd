extends SceneTree
## Checks the track designer's data layer and the worlds it builds. Run headless:
##
##     godot --headless --path . --script tests/test_track_design.gd
##
## Three things are worth pinning down here, all of them things that break
## quietly rather than loudly:
##
##   - the save format        a design is written to user:// as JSON and read
##                            back later, possibly by a different build. If a
##                            field stops surviving the round trip nothing errors
##                            — the track just comes back subtly different.
##   - the library            saving, listing, overwriting and deleting all key
##                            off filenames derived from the track's name, which
##                            is a string a child typed.
##   - the generated world    a player-made track is built by the same RoadRibbon
##                            and TrackGround the built-in one uses, but from
##                            arbitrary node positions rather than a hand-tuned
##                            layout. A design has to come out as a closed road
##                            with gates on it, features on the road rather than
##                            in a field, and no hill poking up through the
##                            tarmac.
##
## Note the autoloads are fetched off the scene tree rather than named directly:
## a --script SceneTree is compiled before autoloads are registered, so
## `GameSettings` is a compile error in *this* file even though every script it
## loads can use it freely.

var _done := false
var _fails := 0


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	print("\n%s  (%d failures)" % ["FAILED" if _fails > 0 else "ALL PASSED", _fails])
	return true


func _check(check_name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print(("PASS  " if ok else "FAIL  ") + check_name + ("   " + detail if detail != "" else ""))


func _run() -> void:
	_test_templates()
	_test_round_trip()
	_test_rejects_junk()
	_test_library()
	_test_editing()
	_test_race_world()
	_test_arena_world()


# ---------------------------------------------------------------------------

func _test_templates() -> void:
	print("\n--- templates ---")
	for template in TrackDesign.TEMPLATES:
		var design := TrackDesign.from_template(String(template["id"]))
		var id := String(template["id"])
		_check("%s builds" % id, design != null)
		_check("%s has the advertised kind" % id, design.kind == int(template["kind"]))
		if design.kind == TrackDesign.Kind.RACE:
			_check(
				"%s has enough road nodes" % id,
				design.nodes.size() >= TrackDesign.MIN_NODES,
				"%d nodes" % design.nodes.size()
			)
			# Every node has to be a real, distinct point: two nodes on top of
			# each other give Curve3D a zero-length segment and the road folds.
			var too_close := 0
			for i in range(design.nodes.size()):
				var a: Vector3 = design.nodes[i]["pos"]
				var b: Vector3 = design.nodes[(i + 1) % design.nodes.size()]["pos"]
				if a.distance_to(b) < 5.0:
					too_close += 1
			_check("%s nodes are spaced apart" % id, too_close == 0, "%d too close" % too_close)
		else:
			_check(
				"%s rink is a sane size" % id,
				design.arena_radius >= TrackDesign.MIN_ARENA_RADIUS
					and design.arena_radius <= TrackDesign.MAX_ARENA_RADIUS
			)
	# The picker in the editor and the one on the menu both index this list.
	var race_templates := 0
	var arena_templates := 0
	for template in TrackDesign.TEMPLATES:
		if int(template["kind"]) == TrackDesign.Kind.ARENA:
			arena_templates += 1
		else:
			race_templates += 1
	_check("there is a template for each mode", race_templates > 0 and arena_templates > 0)
	_check_templates_keep_the_grid_clear()

	# A template that sits outside the design limits comes back reshaped from its
	# first save, which is a baffling thing for a starting point to do.
	for template in TrackDesign.TEMPLATES:
		var id := String(template["id"])
		var design := TrackDesign.from_template(id)
		var reloaded := TrackDesign.from_dict(design.to_dict())
		var drift := 0.0
		if reloaded:
			for i in range(design.nodes.size()):
				drift = maxf(
					drift, (design.nodes[i]["pos"] as Vector3).distance_to(reloaded.nodes[i]["pos"])
				)
		_check("%s is unchanged by a save" % id, reloaded != null and drift < 0.001, "drift %.3f" % drift)


## Nothing a template ships with may sit where the field starts. Both ways of
## getting this wrong have happened: the hill loop put a jump pad on the +X axis,
## which is the ring's first node and therefore the start/finish line, so the
## whole grid launched itself the instant the lights went out; and the junkyard's
## outer ring of crates crossed the circle the arena spawns karts on, leaving one
## of them staring at a crate five metres away on any even-numbered field.
##
## Neither is a crash, which is exactly why they need a check — a starting point
## that starts you in trouble just reads as the editor being broken.
const MIN_SPAWN_CLEARANCE := 12.0

func _check_templates_keep_the_grid_clear() -> void:
	for template in TrackDesign.TEMPLATES:
		var id := String(template["id"])
		var design := TrackDesign.from_template(id)
		var closest := INF
		if design.kind == TrackDesign.Kind.ARENA:
			# Spawns are spread evenly round the rim; the field can be 1 to 4.
			for field_size in range(1, 5):
				for slot in range(field_size):
					var angle: float = TAU * float(slot) / float(field_size)
					var radius: float = (
						design.arena_radius * CustomArenaBuilder.START_RADIUS_FRACTION
					)
					var spawn := Vector2(cos(angle) * radius, sin(angle) * radius)
					for feature in design.features:
						var pos: Vector3 = feature["pos"]
						closest = minf(closest, spawn.distance_to(Vector2(pos.x, pos.z)))
		else:
			# A race grid forms on the start/finish line, which is node 0.
			var start: Vector3 = design.nodes[0]["pos"]
			for feature in design.features:
				# Only the things that end up ON the road can be under a kart;
				# scenery beside it is what scenery is for.
				if not bool(TrackDesign.FEATURES[String(feature["type"])]["on_road"]):
					continue
				var pos: Vector3 = feature["pos"]
				closest = minf(closest, Vector2(start.x, start.z).distance_to(Vector2(pos.x, pos.z)))
		if closest == INF:
			continue # nothing placed that could be in the way
		_check(
			"%s starts the field on clear ground" % id,
			closest >= MIN_SPAWN_CLEARANCE,
			"closest is %.1f m away" % closest
		)


func _test_round_trip() -> void:
	print("\n--- save format ---")
	var original := TrackDesign.from_template("hills")
	original.design_name = "Round Trip"
	original.colors["road"] = Color(0.2, 0.4, 0.6)
	original.add_feature("rock", Vector3(31.0, 4.0, -12.0), 1.25, 2.5)
	original.add_feature("bridge", Vector3(-40.0, 0.0, 8.0), -0.5, 30.0)

	var text := JSON.stringify(original.to_dict())
	var restored := TrackDesign.from_dict(JSON.parse_string(text))
	_check("survives JSON", restored != null)
	if restored == null:
		return
	_check("name kept", restored.design_name == original.design_name)
	_check("kind kept", restored.kind == original.kind)
	_check("node count kept", restored.nodes.size() == original.nodes.size())

	var worst_node := 0.0
	for i in range(original.nodes.size()):
		worst_node = maxf(
			worst_node, (original.nodes[i]["pos"] as Vector3).distance_to(restored.nodes[i]["pos"])
		)
		worst_node = maxf(
			worst_node,
			absf(float(original.nodes[i]["half_width"]) - float(restored.nodes[i]["half_width"]))
		)
	_check("node positions and widths kept", worst_node < 0.001, "worst drift %.4f" % worst_node)

	_check("feature count kept", restored.features.size() == original.features.size())
	var features_match := true
	for i in range(original.features.size()):
		var a: Dictionary = original.features[i]
		var b: Dictionary = restored.features[i]
		if String(a["type"]) != String(b["type"]):
			features_match = false
		if (a["pos"] as Vector3).distance_to(b["pos"]) > 0.001:
			features_match = false
		if absf(float(a["yaw"]) - float(b["yaw"])) > 0.001:
			features_match = false
		if absf(float(a["size"]) - float(b["size"])) > 0.001:
			features_match = false
	_check("features kept exactly", features_match)

	var worst_color := 0.0
	for key in original.colors:
		var a: Color = original.colors[key]
		var b: Color = restored.color_of(key)
		worst_color = maxf(worst_color, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
	_check("colors kept", worst_color < 0.002, "worst drift %.4f" % worst_color)

	# duplicate_design() goes through the same path, so it is a deep copy: editing
	# the copy must not reach back into the original.
	var copy := original.duplicate_design()
	copy.nodes[0]["pos"] = Vector3(999, 0, 999)
	copy.features[0]["size"] = 4.75
	_check(
		"duplicate_design is a deep copy",
		(original.nodes[0]["pos"] as Vector3).x != 999.0
			and float(original.features[0]["size"]) != 4.75
	)


func _test_rejects_junk() -> void:
	print("\n--- bad files ---")
	_check("empty dictionary refused", TrackDesign.from_dict({}) == null)
	_check(
		"wrong format version refused",
		TrackDesign.from_dict({"format": TrackDesign.FORMAT_VERSION + 99}) == null
	)
	_check(
		"a race with no road refused",
		TrackDesign.from_dict({"format": TrackDesign.FORMAT_VERSION, "kind": 0, "nodes": []}) == null
	)

	# A design carrying a feature type this build doesn't know about should load
	# without it rather than not load at all — that's what lets a future version
	# add features without orphaning today's saves.
	var design := TrackDesign.from_template("oval")
	var data := design.to_dict()
	(data["features"] as Array).append(
		{"type": "antigravity_tunnel", "pos": [0, 0, 0], "yaw": 0.0, "size": 1.0}
	)
	var loaded := TrackDesign.from_dict(data)
	_check("unknown feature type skipped, rest kept", loaded != null and loaded.features.is_empty())

	# Values well outside the editor's limits are clamped, not trusted.
	var wild := design.to_dict()
	(wild["nodes"] as Array)[0]["pos"] = [99999.0, 5000.0, -99999.0]
	(wild["nodes"] as Array)[0]["half_width"] = 400.0
	var tamed := TrackDesign.from_dict(wild)
	var tamed_pos: Vector3 = tamed.nodes[0]["pos"]
	_check(
		"out-of-range values clamped",
		absf(tamed_pos.x) <= TrackDesign.WORLD_LIMIT
			and tamed_pos.y <= TrackDesign.MAX_HEIGHT
			and float(tamed.nodes[0]["half_width"]) <= TrackDesign.MAX_HALF_WIDTH
	)


func _test_library() -> void:
	print("\n--- library ---")
	# Start from a clean slate: this runs against the real user:// directory.
	for entry in TrackLibrary.list_designs():
		TrackLibrary.delete_design(String(entry["id"]))

	var design := TrackDesign.from_template("oval")
	design.design_name = "Dad's Big Loop!"
	var id := TrackLibrary.save_design(design)
	_check("saved", id != "", "id '%s'" % id)
	_check("id is a readable slug", id == "dads-big-loop", "got '%s'" % id)
	_check("file exists", TrackLibrary.exists(id))

	var listed := TrackLibrary.list_designs()
	_check("listed once", listed.size() == 1)
	_check("listed under its own name", listed.size() == 1 and String(listed[0]["name"]) == design.design_name)
	_check("listed with its kind", listed.size() == 1 and int(listed[0]["kind"]) == TrackDesign.Kind.RACE)

	var reopened := TrackLibrary.load_design(id)
	_check("reopens", reopened != null and reopened.design_name == design.design_name)

	# Saving a second track with the same name must not overwrite the first.
	var second := TrackDesign.from_template("rink")
	second.design_name = "Dad's Big Loop!"
	var second_id := TrackLibrary.save_design(second)
	_check("same name gets its own file", second_id != id, "'%s' vs '%s'" % [id, second_id])
	_check("both are listed", TrackLibrary.list_designs().size() == 2)

	# ...but saving *over* a known id does overwrite, which is what the editor's
	# Save button does on a track that has been saved once already.
	design.design_name = "Renamed"
	TrackLibrary.save_design(design, id)
	_check("overwrite keeps the same file", TrackLibrary.list_designs().size() == 2)
	_check("overwrite took", TrackLibrary.load_design(id).design_name == "Renamed")

	_check("deleted", TrackLibrary.delete_design(id))
	_check("gone after delete", TrackLibrary.load_design(id) == null)
	_check("deleting twice is not a crash", not TrackLibrary.delete_design(id))
	TrackLibrary.delete_design(second_id)
	_check("library empty again", TrackLibrary.list_designs().is_empty())

	# A file that isn't ours at all is skipped rather than breaking the listing.
	var junk := FileAccess.open("%s/not-a-track.json" % TrackLibrary.DIR, FileAccess.WRITE)
	if junk:
		junk.store_string("this is not JSON {{{")
		junk.close()
		_check("junk file skipped by the listing", TrackLibrary.list_designs().is_empty())
		DirAccess.remove_absolute("%s/not-a-track.json" % TrackLibrary.DIR)


func _test_editing() -> void:
	print("\n--- editing ---")
	var design := TrackDesign.from_template("oval")
	var before := design.nodes.size()
	var inserted := design.split_node(0)
	_check("splitting a segment adds a node", design.nodes.size() == before + 1)
	_check("the new node is where the road already ran", inserted == 1)
	if inserted == 1:
		var a: Vector3 = design.nodes[0]["pos"]
		var b: Vector3 = design.nodes[2]["pos"]
		var mid: Vector3 = design.nodes[1]["pos"]
		_check("new node sits between its neighbours", mid.distance_to((a + b) * 0.5) < 0.001)

	while design.nodes.size() > TrackDesign.MIN_NODES:
		design.remove_node(0)
	_check("cannot delete below the minimum", not design.remove_node(0))
	_check("still has the minimum", design.nodes.size() == TrackDesign.MIN_NODES)

	design.set_node_half_width(0, 999.0)
	_check("width is clamped", float(design.nodes[0]["half_width"]) == TrackDesign.MAX_HALF_WIDTH)
	design.set_node_position(0, Vector3(0.0, 9999.0, 0.0))
	_check("height is clamped", (design.nodes[0]["pos"] as Vector3).y == TrackDesign.MAX_HEIGHT)

	# An arena has no road nodes, so neither editing operation should touch it.
	var arena := TrackDesign.from_template("rink")
	_check("arenas have no road nodes to split", arena.split_node(0) == -1)
	_check("arenas have no road nodes to remove", not arena.remove_node(0))


# ---------------------------------------------------------------------------
# The generated worlds
# ---------------------------------------------------------------------------

func _test_race_world() -> void:
	print("\n--- a player-made race track ---")
	var design := TrackDesign.from_template("hills")
	# One of each kind of thing, placed on purpose rather than by the template,
	# so the checks below are about placement and not about the template.
	design.add_feature("boost", Vector3(140.0, 0.0, 30.0))
	design.add_feature("box", Vector3(-140.0, 0.0, -30.0))
	design.add_feature("tree", Vector3(60.0, 0.0, 60.0))
	design.add_feature("bridge", Vector3(0.0, 0.0, 70.0), 0.0, 30.0)
	root.get_node("/root/GameSettings").select_design(design)

	var track: Node3D = load("res://scenes/custom_track.tscn").instantiate()
	root.add_child(track)
	var ribbon: RoadRibbon = track.get_ribbon()
	var ground: TrackGround = track.get_ground()
	print("lap %.1f m over %d stations" % [ribbon.length, ribbon.station_count()])

	_check("road mesh built", ribbon.mesh != null and ribbon.mesh.get_surface_count() == 1)
	_check("road collider built", track.get_node("RoadBody/RoadShape").shape != null)
	_check("lap is a sensible length", ribbon.length > 200.0, "%.1f m" % ribbon.length)

	# Closed loop: the curve repeats node 0 at the end, so the last station has
	# to come back round to the first. An open curve here is the bug that leaves
	# a stretch of road with no gates on it and karts reporting a lap position
	# from the wrong end.
	var first: Vector3 = ribbon.centers[0]
	var last: Vector3 = ribbon.centers[ribbon.station_count() - 1]
	_check("road closes on itself", first.distance_to(last) < 6.0, "%.2f m gap" % first.distance_to(last))

	var gates: Array = []
	for child in track.get_children():
		if child is Area3D and "checkpoint_index" in child:
			gates.append(child)
	_check("gates placed", gates.size() >= 6, "%d gates" % gates.size())
	var indices: Array = []
	for gate in gates:
		indices.append(gate.checkpoint_index)
	indices.sort()
	var numbered := true
	for i in range(indices.size()):
		if indices[i] != i:
			numbered = false
	_check("gates numbered 0..n with no gaps", numbered)
	var finish_lines := 0
	for gate in gates:
		if gate.is_finish_line:
			finish_lines += 1
	_check("exactly one finish line", finish_lines == 1)

	# Gates have to span the road they sit on, or a kart running wide slips round
	# the end of one and race_manager silently refuses the lap.
	var narrow := 0
	for gate in gates:
		var offset: float = _closest_offset(ribbon, gate.global_position)
		if gate.scale.x * 13.0 < ribbon.half_width_at(offset) * 2.0:
			narrow += 1
	_check("every gate spans its road", narrow == 0, "%d too narrow" % narrow)

	# Nothing may rise into the road: the ground is built from the road's own
	# shape and is supposed to be pulled down clear of it everywhere.
	var pokes_through := 0
	for i in range(ribbon.station_count()):
		var center: Vector3 = ribbon.centers[i]
		if ground.height_at(center.x, center.z) > center.y - 0.05:
			pokes_through += 1
	_check("ground stays below the road", pokes_through == 0, "%d stations" % pokes_through)

	# Pads and boxes snap to the road; scenery does not.
	var on_road := {"BoostPad": false, "ItemBox": false}
	var tree_found := false
	var bridge_found := false
	for child in track.get_children():
		var node_name: String = child.name
		if node_name.begins_with("BoostPad") or node_name.begins_with("ItemBox"):
			var key: String = "BoostPad" if node_name.begins_with("BoostPad") else "ItemBox"
			var offset: float = _closest_offset(ribbon, child.global_position)
			var frame: Transform3D = ribbon.frame_at(offset)
			var lateral: float = absf((child.global_position - frame.origin).dot(frame.basis.x))
			on_road[key] = lateral <= ribbon.half_width_at(offset)
		elif node_name.begins_with("Tree"):
			tree_found = true
		elif node_name.begins_with("Bridge"):
			bridge_found = true
	_check("a boost pad dropped near the road ends up on it", on_road["BoostPad"])
	_check("an item box dropped near the road ends up on it", on_road["ItemBox"])
	_check("a tree is built", tree_found)
	_check("a bridge is built", bridge_found)
	_check_bridge_is_drivable(track, ground)

	# The template's lake is carved into the ground, not painted on top of it...
	var lake_floor: float = ground.height_at(0.0, 0.0)
	_check("water is a dip in the ground", lake_floor < -2.0, "floor at %.1f m" % lake_floor)
	# ...and it is a dip a kart can drive back out of. Nothing respawns a kart out
	# of a pond (that only happens below y = -10, and the editor can't build
	# anything that deep), so a bank steeper than the kart's 50-degree floor limit
	# would mean falling in ends the race sitting in a puddle.
	var steepest := 0.0
	for i in range(0, 80):
		var r: float = float(i)
		var here: float = ground.height_at(r, 0.0)
		var there: float = ground.height_at(r + 1.0, 0.0)
		steepest = maxf(steepest, absf(there - here))
	_check(
		"the pond can be driven out of",
		rad_to_deg(atan(steepest)) < 45.0,
		"steepest bank %.0f degrees" % rad_to_deg(atan(steepest))
	)
	var water_planes := 0
	for child in track.get_children():
		if String(child.name).begins_with("Water"):
			water_planes += 1
	_check("water has a surface", water_planes >= 1)

	track.queue_free()


## A kart is a CharacterBody3D and cannot climb a vertical step of any height, so
## a bridge deck that stands proud of the ground at its ends is scenery, not a
## bridge. Each end gets a ramp; this checks both of them actually reach the
## ground rather than stopping short above it (which is what happens if the ramp
## slab is sized by its horizontal run instead of its own length) or pitching the
## wrong way entirely.
func _check_bridge_is_drivable(track: Node3D, ground: TrackGround) -> void:
	var bridge: StaticBody3D = null
	for child in track.get_children():
		if child is StaticBody3D and String(child.name).begins_with("Bridge"):
			bridge = child
	if bridge == null:
		_check("bridge found to check", false)
		return

	var ramps: Array = []
	var has_deck := false
	for child in bridge.get_children():
		if not (child is CollisionShape3D):
			continue
		if String(child.name).begins_with("RampShape"):
			ramps.append(child)
		elif child.name == "DeckShape":
			has_deck = true
	_check("bridge has a solid deck", has_deck)

	var landings := 0
	var worst := 0.0
	for shape in ramps:
		var box: BoxShape3D = shape.shape
		# The lower of the ramp's two top edges is the end that meets the ground.
		var lowest := INF
		var landing := Vector3.ZERO
		for end: float in [-1.0, 1.0]:
			var corner: Vector3 = shape.global_transform * Vector3(
				0.0, box.size.y * 0.5, end * box.size.z * 0.5
			)
			if corner.y < lowest:
				lowest = corner.y
				landing = corner
		landings += 1
		worst = maxf(worst, landing.y - ground.height_at(landing.x, landing.z))
	_check("both ramps are there", landings == 2)
	_check(
		"the ramps reach the ground",
		landings == 2 and worst <= 0.05,
		"worst end stands %.2f m proud" % worst
	)


func _test_arena_world() -> void:
	print("\n--- a player-made arena ---")
	var design := TrackDesign.from_template("junkyard")
	root.get_node("/root/GameSettings").select_design(design)

	var rink := Node3D.new()
	rink.set_script(load("res://scripts/custom_arena_builder.gd"))
	root.add_child(rink)

	_check("rink reports the design's size", is_equal_approx(rink.get_arena_radius(), design.arena_radius))
	var wall := rink.get_node_or_null("Wall")
	_check("wall built all the way round", wall != null and wall.get_child_count() >= 32)

	# Every wall segment has to be at the rim, or there is a hole to drive out of.
	var misplaced := 0
	if wall:
		for segment in wall.get_children():
			var radial := Vector2(segment.position.x, segment.position.z).length()
			if absf(radial - design.arena_radius) > 1.0:
				misplaced += 1
	_check("wall sits on the rim", misplaced == 0, "%d segments off" % misplaced)

	# Spawns: inside the wall, spread out, and facing the middle.
	var previous := Vector3.ZERO
	var inside := true
	var facing_in := true
	var min_gap := INF
	for i in range(4):
		var t: Transform3D = rink.get_start_transform(float(i) / 4.0)
		if Vector2(t.origin.x, t.origin.z).length() >= design.arena_radius:
			inside = false
		# A kart's forward is -Z; pointing at the centre means -Z aims inward.
		if (t.basis * Vector3.FORWARD).dot(-t.origin.normalized()) < 0.5:
			facing_in = false
		if i > 0:
			min_gap = minf(min_gap, t.origin.distance_to(previous))
		previous = t.origin
	_check("spawns are inside the wall", inside)
	_check("spawns face the middle", facing_in)
	_check("spawns are spread apart", min_gap > 20.0, "closest pair %.1f m" % min_gap)

	# The AI asks for these on every arena; a custom rink has neither, and both
	# have to be the shape ai_driver.gd reads as "nothing here".
	_check("no butte to climb", rink.get_climb_points().is_empty())
	_check("no central obstacle", float(rink.get_plateau()["radius"]) == 0.0)

	var solids := 0
	for child in rink.get_children():
		if child is StaticBody3D:
			solids += 1
	_check("the junkyard's crates and rocks are solid", solids >= 2, "%d bodies" % solids)

	# The rink floor is where karts spawn and drive; it must not be a hillside.
	var ground: TrackGround = rink.get_ground()
	var roughest := 0.0
	for i in range(24):
		var angle: float = TAU * float(i) / 24.0
		var radius: float = design.arena_radius * 0.5
		roughest = maxf(roughest, absf(ground.height_at(cos(angle) * radius, sin(angle) * radius)))
	_check("rink floor is close to flat", roughest < 2.0, "worst %.2f m" % roughest)

	rink.queue_free()


## RoadRibbon has no closest-offset of its own; this mirrors the walk
## custom_features.gd does so the checks measure the same thing the builder did.
func _closest_offset(ribbon: RoadRibbon, pos: Vector3) -> float:
	var best_offset := 0.0
	var best := INF
	for i in range(ribbon.station_count()):
		var center: Vector3 = ribbon.centers[i]
		var d: float = Vector2(pos.x - center.x, pos.z - center.z).length_squared()
		if d < best:
			best = d
			best_offset = ribbon.offsets[i]
	return best_offset
