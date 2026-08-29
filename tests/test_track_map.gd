extends SceneTree
## Structural checks on the generated racetrack. Run headless:
##
##     godot --headless --path . --script tests/test_track_map.gd
##
## The point of these is that the track is *generated*, so a one-line change to
## WAYPOINTS or ROAD_HALF_WIDTHS in track_builder.gd silently moves everything
## else — pads, gates, terrain, structures. Each check below exists because
## something here actually broke while the map was being built:
##
##   - road mesh/collision      the ribbon was wound the wrong way round, which
##                              made the road invisible AND non-solid (Godot winds
##                              triangles clockwise; Jolt back-face culls a
##                              one-sided trimesh).
##   - checkpoint gate width    the road is wider than the gate scene now, and a
##                              kart slipping past the edge of a gate has its lap
##                              silently refused by race_manager.
##   - ground clearance         the terrain is built from the road's own shape; a
##                              bug in its spatial index left the road with no
##                              influence at all and hills poking through it.
##   - props on the road        placements are fractional waypoint indices, so an
##                              off-by-one puts a boost pad in a field.

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
	var track: Node3D = load("res://scenes/track.tscn").instantiate()
	root.add_child(track)
	var ribbon: RoadRibbon = track.get_ribbon()
	var ground: TrackGround = track.get_ground()
	print("lap %.1f m over %d stations" % [ribbon.length, ribbon.station_count()])

	_check("road mesh built", ribbon.mesh != null and ribbon.mesh.get_surface_count() == 1)
	_check("road mesh is on the node", track.get_node("RoadMesh").mesh == ribbon.mesh)
	_check("road collider is on the node", track.get_node("RoadBody/RoadShape").shape != null)

	# Winding: Godot's front face is the one (c - a) x (b - a) points out of. Get
	# this backwards and the road is inside out — invisible, and solid only from
	# below.
	var arrays: Array = ribbon.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var inside_out := 0
	for f in range(verts.size() / 3):
		var a: Vector3 = verts[f * 3]
		var b: Vector3 = verts[f * 3 + 1]
		var c: Vector3 = verts[f * 3 + 2]
		var geometric: Vector3 = (c - a).cross(b - a)
		if geometric.length() > 0.0001 and geometric.normalized().dot(normals[f * 3]) < -0.2:
			inside_out += 1
	_check("road triangles face outwards", inside_out == 0, "%d inside out" % inside_out)

	# ...and prove it by actually firing rays at the thing.
	_check_collision(track, ribbon)

	# Banking and width have to genuinely vary — they are the two things that make
	# the circuit read as more than a flat ribbon.
	var min_bank := INF
	var max_bank := -INF
	var min_width := INF
	var max_width := -INF
	for i in range(ribbon.station_count()):
		min_bank = min(min_bank, ribbon.banks[i])
		max_bank = max(max_bank, ribbon.banks[i])
		min_width = min(min_width, ribbon.half_widths[i])
		max_width = max(max_width, ribbon.half_widths[i])
	print("bank %.1f to %.1f deg, half-width %.1f to %.1f m"
		% [rad_to_deg(min_bank), rad_to_deg(max_bank), min_width, max_width])
	_check("corners bank both ways", min_bank < deg_to_rad(-6.0) and max_bank > deg_to_rad(6.0))
	_check("road width varies along the lap", max_width - min_width > 2.5)

	# Ramps must stay flat: a banked lip throws a kart sideways in mid-air.
	var ramp_bank := 0.0
	for placement in track.JUMP_PAD_PLACEMENTS:
		var frame: Transform3D = ribbon.frame_at(track._offset(placement))
		ramp_bank = max(ramp_bank, absf(asin(clamp(frame.basis.x.y, -1.0, 1.0))))
	_check("jump ramps are level", ramp_bank < deg_to_rad(1.5), "%.1f deg" % rad_to_deg(ramp_bank))

	_check_shape(ribbon)
	_check_props(track, ribbon)
	_check_gates(track, ribbon)
	_check_ground(track, ribbon, ground)
	_check_structures(track)
	_check_stands(track, ribbon)

	print("\n%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _check_collision(track: Node3D, ribbon: RoadRibbon) -> void:
	var space := root.world_3d.direct_space_state
	var hits := 0
	var tried := 0
	var offset := 0.0
	while offset < ribbon.length:
		var frame := ribbon.frame_at(offset)
		var query := PhysicsRayQueryParameters3D.create(
			frame.origin + Vector3.UP * 4.0, frame.origin - Vector3.UP * 2.0
		)
		query.collision_mask = 1
		tried += 1
		if space.intersect_ray(query).get("collider") == track.get_node("RoadBody"):
			hits += 1
		offset += 10.0
	_check("the road is solid all the way round", hits == tried, "%d of %d" % [hits, tried])


## Two things a layout edit can break that nothing else notices: two stretches of
## road ending up on top of each other in world space (the curve is free to loop
## back near itself), and a climb or drop steeper than a kart can actually take.
func _check_shape(ribbon: RoadRibbon) -> void:
	var count := ribbon.station_count()
	var worst := INF
	var worst_desc := ""
	for i in range(count):
		for j in range(i + 1, count):
			var arc: float = ribbon.offsets[j] - ribbon.offsets[i]
			arc = min(arc, ribbon.length - arc)
			if arc < 45.0:
				continue # neighbours along the road, not a separate stretch
			var a: Vector3 = ribbon.centers[i]
			var b: Vector3 = ribbon.centers[j]
			if absf(a.y - b.y) > 6.0:
				continue # one is well above the other, e.g. a ramp over its landing
			var gap: float = (
				Vector2(a.x - b.x, a.z - b.z).length()
				- ribbon.half_widths[i] - ribbon.half_widths[j]
			)
			if gap < worst:
				worst = gap
				worst_desc = "lap offsets %.0f and %.0f" % [ribbon.offsets[i], ribbon.offsets[j]]
	_check("separate stretches of road do not overlap", worst > 6.0,
		"closest edges %.1f m apart, %s" % [worst, worst_desc])

	var steepest := 0.0
	var steepest_at := 0.0
	for i in range(count):
		var a: Vector3 = ribbon.centers[i]
		var b: Vector3 = ribbon.centers[(i + 1) % count]
		var flat: float = Vector2(b.x - a.x, b.z - a.z).length()
		if flat < 0.01:
			continue
		var grade: float = rad_to_deg(atan(absf(b.y - a.y) / flat))
		if grade > steepest:
			steepest = grade
			steepest_at = ribbon.offsets[i]
	# kart_controller.gd sets floor_max_angle to 50 degrees.
	_check("no part of the road is too steep to drive", steepest < 45.0,
		"steepest %.0f deg at lap offset %.0f" % [steepest, steepest_at])


## Godot renames duplicate instanced scenes to "@Area3D@N", so props are
## identified by the script they carry rather than by node name.
func _check_props(track: Node3D, ribbon: RoadRibbon) -> void:
	var counts := {}
	var off_road := 0
	var floating := 0
	for child in track.get_children():
		var script: Script = child.get_script()
		if script == null:
			continue
		var kind := String(script.resource_path).get_file().get_basename()
		if kind == "track_builder":
			continue
		counts[kind] = counts.get(kind, 0) + 1
		var pos: Vector3 = (child as Node3D).global_position
		var offset: float = track.path.curve.get_closest_offset(pos)
		var frame: Transform3D = ribbon.frame_at(offset)
		if absf((pos - frame.origin).dot(frame.basis.x)) > ribbon.half_width_at(offset):
			off_road += 1
			print("     %s at lap offset %.0f is off the tarmac" % [kind, offset])
		if absf(pos.y - frame.origin.y) > 1.2:
			floating += 1
			print("     %s at lap offset %.0f is off the road surface" % [kind, offset])
	print("props: " + str(counts))
	_check("every prop is on the road", off_road == 0)
	_check("every prop is on the road surface", floating == 0)
	_check("the whole layout got placed",
		counts.get("boost_pad", 0) == track.BOOST_PAD_PLACEMENTS.size() + track.LANE_SPLITS.size()
		and counts.get("jump_pad", 0) == track.JUMP_PAD_PLACEMENTS.size()
		and counts.get("hazard_oil", 0) == track.OIL_HAZARD_PLACEMENTS.size()
		and counts.get("hazard_obstacle", 0) == track.OBSTACLE_PLACEMENTS.size()
		and counts.get("checkpoint", 0) == track.CHECKPOINT_COUNT
		and counts.get("item_box", 0) > 0,
		str(counts))


## A gate narrower than the road it stands on means a kart can drive through the
## gap beside it, miss the checkpoint, and have its lap refused with no feedback.
func _check_gates(track: Node3D, ribbon: RoadRibbon) -> void:
	var narrow := 0
	for child in track.get_children():
		var script: Script = child.get_script()
		if script == null or not String(script.resource_path).ends_with("checkpoint.gd"):
			continue
		var offset: float = track.path.curve.get_closest_offset((child as Node3D).global_position)
		var gate_half: float = 13.0 * 0.5 * (child as Node3D).scale.x
		var road_half: float = ribbon.half_width_at(offset) + RoadRibbon.APRON_WIDTH
		if gate_half < road_half + 2.0:
			narrow += 1
			print("     gate at %.0f spans %.1f m, road is %.1f m" % [offset, gate_half, road_half])
		# ...and not SO wide that it reaches a different stretch of road, which
		# would let a kart trip a gate it is nowhere near.
		var gate_pos: Vector3 = (child as Node3D).global_position
		for i in range(ribbon.station_count()):
			var arc: float = absf(ribbon.offsets[i] - offset)
			arc = min(arc, ribbon.length - arc)
			if arc < 60.0:
				continue
			var centre: Vector3 = ribbon.centers[i]
			if absf(gate_pos.y - centre.y) > 6.0:
				continue
			var reach: float = (
				Vector2(gate_pos.x - centre.x, gate_pos.z - centre.z).length()
				- ribbon.half_widths[i]
			)
			if reach < gate_half + 3.0:
				narrow += 1
				print("     gate at %.0f reaches within %.1f m of the road at %.0f"
					% [offset, reach, ribbon.offsets[i]])
				break
	_check("checkpoint gates span their road and nothing else", narrow == 0)


func _check_ground(track: Node3D, ribbon: RoadRibbon, ground: TrackGround) -> void:
	# Sample right across the road, kerb to kerb, at every metre of the lap.
	var worst := INF
	var worst_at := 0.0
	var offset := 0.0
	while offset < ribbon.length:
		var frame := ribbon.frame_at(offset)
		var half: float = ribbon.half_width_at(offset) + RoadRibbon.APRON_WIDTH
		var lateral := -half
		while lateral <= half + 0.001:
			var point: Vector3 = frame.origin + frame.basis.x * lateral
			var clearance: float = point.y - ground.height_at(point.x, point.z)
			if clearance < worst:
				worst = clearance
				worst_at = offset
			lateral += half / 6.0
		offset += 1.0
	# The ground sits deliberately close under the road now — part-way up the
	# apron, so a kart can drive back on — so this only asks that it never actually
	# reaches the tarmac.
	_check("ground never reaches the road", worst > 0.2,
		"worst %.2f m at lap offset %.0f" % [worst, worst_at])

	# And the same thing again against the heightmap that actually gets stamped,
	# which is a different code path (Terrain3D's own sampling grid).
	var terrain := Terrain3D.new()
	terrain.set_script(load("res://scripts/terrain_builder.gd"))
	terrain.track_path = track.get_path()
	root.add_child(terrain)
	var too_high := 0
	offset = 0.0
	while offset < ribbon.length:
		var frame := ribbon.frame_at(offset)
		var height: float = terrain.data.get_height(Vector3(frame.origin.x, 0.0, frame.origin.z))
		if not is_nan(height) and height > frame.origin.y - 0.5:
			too_high += 1
		offset += 4.0
	_check("the stamped heightmap keeps clear of the road too", too_high == 0)

	# The viaduct only works if there is really a gorge under it, and the gorge
	# floor has to be past kart_controller.gd's y < -10 respawn line so a kart
	# that gets down there is put back on the road.
	var deck: Transform3D = ribbon.frame_at(track._offset(16.0))
	var beside: float = ground.height_at(
		deck.origin.x + deck.basis.x.x * 9.0, deck.origin.z + deck.basis.x.z * 9.0
	)
	_check("the viaduct spans a real drop", deck.origin.y - beside > 15.0,
		"%.1f m" % (deck.origin.y - beside))
	_check("the gorge floor is below the respawn line", beside < -10.0, "y = %.1f" % beside)


## Each grandstand box is `tier_depth` across its local X and `step` along its
## local Z, so its long axis has to end up running ALONG the road. A yaw that is
## 90 degrees out still produces a plausible-looking row of boxes — they just bury
## each other across the road and leave gaps down it — so this compares each box's
## own axis against the road's heading rather than eyeballing the result.
func _check_stands(track: Node3D, ribbon: RoadRibbon) -> void:
	var crooked := 0
	var count := 0
	for child in track.get_node("Grandstands").get_children():
		count += 1
		var pos: Vector3 = (child as Node3D).global_position
		var axis: Vector3 = -(child as Node3D).global_transform.basis.z
		var flat_axis := Vector2(axis.x, axis.z).normalized()
		# Compared against every nearby station rather than one "closest offset":
		# a stand sits ~25 m off the road, and where the road bends the nearest
		# point by arc length can belong to a different stretch entirely.
		var best := 0.0
		for i in range(ribbon.station_count()):
			var centre: Vector3 = ribbon.centers[i]
			if Vector2(pos.x - centre.x, pos.z - centre.z).length() > 36.0:
				continue
			var along: Vector3 = ribbon.forwards[i]
			# Either way round is fine — a box is symmetric end to end.
			best = max(best, absf(flat_axis.dot(Vector2(along.x, along.z).normalized())))
		if best < 0.9:
			crooked += 1
	_check("grandstand boxes lie along the road", crooked == 0,
		"%d of %d crooked" % [crooked, count])


func _check_structures(track: Node3D) -> void:
	var names := []
	for child in track.get_children():
		names.append(String(child.name))
	for wanted in [
		"Viaduct", "ArchGallery", "Grandstands", "Crowd", "LaneSplit", "MarkerPosts",
		"Barrier", "Water0", "TreeTrunks", "Boulders", "RockSpires", "Flowers",
	]:
		_check("built " + wanted, names.has(wanted))
