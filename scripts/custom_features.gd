class_name CustomFeatures
extends RefCounted
## Turns a TrackDesign's feature list into actual nodes.
##
## Shared by custom_track_builder.gd and custom_arena_builder.gd, because a tree
## is a tree whether it's beside a lap or beside a rink — the only thing that
## differs is what "the ground" means and whether there's a road to snap pads to.
##
## Nothing here decides *where* a feature goes; that's the player's job in the
## editor. What it does decide is the one thing the player can't see while
## dragging: the height. Every feature is re-seated on the finished height field
## at build time rather than trusting the y it was dropped at, so moving a hill
## under a tree moves the tree with it instead of leaving it hanging.

## Half-width of a bridge deck, and how thick its slab is.
const BRIDGE_HALF_WIDTH := 5.0
const BRIDGE_THICKNESS := 0.6
const BRIDGE_RAIL_HEIGHT := 1.1
## Ramps down off each end. A kart is a CharacterBody3D, which cannot climb a
## vertical step of ANY height — the same fact that governs how close to the road
## TrackGround is allowed to put the shoulder — so a deck slab on its own is a
## bridge you can look at and not drive onto. Each end gets a wedge that runs
## from the deck surface down into the ground.
const BRIDGE_RAMP_SINK := 0.35        # how far the ramp's far edge buries itself
const BRIDGE_RAMP_MIN_RUN := 3.0
const BRIDGE_RAMP_RUN_PER_DROP := 4.0 # 4 m of run per metre of drop, i.e. ~14 degrees

const TREE_TRUNK_HEIGHT := 2.4
const TREE_FOLIAGE_HEIGHT := 3.0

## Water features are carved into the ground as TrackGround canyons. These are
## measured down from the height the player dropped the feature at.
##
## Deliberately shallow, and deliberately wide-walled. The racetrack's gorge gets
## away with sheer walls because its floor is below the y < -10 line that makes
## kart_controller.gd respawn a kart; a pond a child drops in the middle of their
## own track is nowhere near that line, so if its sides were too steep to drive
## back up, falling in would simply end the race with a kart sitting in a hole.
## At these numbers the steepest part of the bank is about 28 degrees even on the
## smallest pool the editor allows — well inside the kart's 50-degree limit — so
## water is something you splash through rather than something that eats you.
const WATER_SURFACE_DROP := 1.0
const WATER_FLOOR_DROP := 3.0
## Fraction of the radius held flat at the bottom; the rest is the bank.
const WATER_FLAT := 0.3


## The canyon entries a design's water features imply, in the shape
## TrackGround.create() and TrackProps.build_water() both expect. Called *before*
## the ground exists (it's an input to it), which is why it reads only the design.
static func water_canyons(design: TrackDesign) -> Array:
	var canyons: Array = []
	for feature in design.features:
		if String(feature["type"]) != "water":
			continue
		var pos: Vector3 = feature["pos"]
		var radius: float = float(feature["size"])
		var here := Vector2(pos.x, pos.z)
		canyons.append({
			# A round pool is a zero-length "canyon" — same carve, both ends at
			# the same point.
			"from": here, "to": here,
			"radius": radius, "flat": WATER_FLAT,
			"floor": pos.y - WATER_FLOOR_DROP,
			"water": pos.y - WATER_SURFACE_DROP,
		})
	return canyons


## Builds every feature except water, whose surface TrackProps.build_water() puts
## in from the same canyon list above.
##
## `ribbon` is the race road, or null in the arena. Pads and item boxes snap onto
## it when it exists so a boost pad dropped near the road ends up flat on the
## tarmac facing the right way, rather than at an angle half off the edge.
## `force_items` overrides the main menu's power-up switch, so the editor always
## shows item boxes it was asked to place — turning items off shouldn't make the
## thing you just dropped disappear while you're still designing with it.
static func build(
	parent: Node3D, design: TrackDesign, ground: TrackGround, ribbon: RoadRibbon,
	force_items: bool = false
) -> void:
	var pad_scenes := {
		"jump": load("res://scenes/jump_pad.tscn"),
		"boost": load("res://scenes/boost_pad.tscn"),
		"box": load("res://scenes/item_box.tscn"),
		"oil": load("res://scenes/hazard_oil.tscn"),
	}
	var foliage_color: Color = design.color_of("foliage")
	var rock_color: Color = design.color_of("rock")

	for feature in design.features:
		var type := String(feature["type"])
		var pos: Vector3 = feature["pos"]
		var size := float(feature["size"])
		var yaw := float(feature["yaw"])
		match type:
			"water":
				continue # the pool is the ground; the surface comes from build_water
			"jump", "boost", "box", "oil":
				# Item boxes obey the main menu's master switch, same as the
				# built-in tracks' — "Items: Off" has to mean off everywhere, not
				# just on the tracks that shipped with the game.
				if type == "box" and not (force_items or GameSettings.items_enabled):
					continue
				var pad: Node3D = (pad_scenes[type] as PackedScene).instantiate()
				parent.add_child(pad)
				pad.global_transform = _road_transform(pos, yaw, ground, ribbon)
				if type != "box":
					# Boxes float above the surface and are always the same size;
					# pads scale. Uniformly — a non-uniform scale on a body with a
					# collision shape is the one Godot warns about.
					pad.scale = Vector3.ONE * size
			"tree":
				_build_tree(parent, _seat(pos, ground), yaw, size, foliage_color)
			"rock":
				_build_rock(parent, _seat(pos, ground), yaw, size, rock_color)
			"crate":
				_build_crate(parent, _seat(pos, ground), yaw, size)
			"bridge":
				_build_bridge(parent, pos, yaw, size, ground, rock_color)


## Ground height under a point, with the point's own x/z kept.
static func _seat(pos: Vector3, ground: TrackGround) -> Vector3:
	return Vector3(pos.x, ground.height_at(pos.x, pos.z), pos.z)


## Where a pad or box actually ends up. On a race track the nearest point of road
## wins — flat on the surface, aligned with the direction of travel, and clamped
## inside the kerbs — because a pad you can't drive over is just scenery. Off the
## road (or in the arena, which has none) it lies flat on the ground at the yaw
## the player set.
static func _road_transform(
	pos: Vector3, yaw: float, ground: TrackGround, ribbon: RoadRibbon
) -> Transform3D:
	if ribbon != null:
		var offset := _closest_offset(ribbon, pos)
		var frame := ribbon.frame_at(offset)
		# How far off the centreline the player dropped it, kept but pulled
		# inside the road edge.
		var to_point: Vector3 = pos - frame.origin
		var lateral: float = to_point.dot(frame.basis.x)
		var limit: float = maxf(ribbon.half_width_at(offset) - 1.6, 0.0)
		return frame.translated_local(Vector3(clampf(lateral, -limit, limit), 0.0, 0.0))
	# No road: lie flat against the ground, which is bumpy enough that a pad
	# placed level would have one edge buried and the other in the air.
	var up := _ground_normal(pos, ground)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	forward = (forward - up * forward.dot(up)).normalized()
	var right := forward.cross(up).normalized()
	return Transform3D(Basis(right, up, -forward), _seat(pos, ground) + up * 0.05)


## The height field has no normals of its own, so difference it. One metre is
## wide enough not to pick up the noise's own texture and narrow enough to
## follow a real slope.
static func _ground_normal(pos: Vector3, ground: TrackGround) -> Vector3:
	const STEP := 1.0
	var dx: float = ground.height_at(pos.x + STEP, pos.z) - ground.height_at(pos.x - STEP, pos.z)
	var dz: float = ground.height_at(pos.x, pos.z + STEP) - ground.height_at(pos.x, pos.z - STEP)
	return Vector3(-dx, 2.0 * STEP, -dz).normalized()


## RoadRibbon has no "closest offset" of its own — its stations are a flat list —
## so this walks them. Called a handful of times per build, not per frame.
static func _closest_offset(ribbon: RoadRibbon, pos: Vector3) -> float:
	var best_offset := 0.0
	var best_distance := INF
	for i in range(ribbon.station_count()):
		var center: Vector3 = ribbon.centers[i]
		var d: float = Vector2(pos.x - center.x, pos.z - center.z).length_squared()
		if d < best_distance:
			best_distance = d
			best_offset = ribbon.offsets[i]
	return best_offset


static func _build_tree(
	parent: Node3D, base: Vector3, yaw: float, size: float, foliage_color: Color
) -> void:
	var tree := Node3D.new()
	tree.name = "Tree"
	parent.add_child(tree)
	tree.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), base)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = TREE_TRUNK_HEIGHT
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.material_override = ToonMaterial.create(Color(0.42, 0.28, 0.16))
	trunk.position = Vector3(0, TREE_TRUNK_HEIGHT * 0.5, 0)
	tree.add_child(trunk)

	var foliage_mesh := CylinderMesh.new()
	foliage_mesh.top_radius = 0.0
	foliage_mesh.bottom_radius = 1.9
	foliage_mesh.height = TREE_FOLIAGE_HEIGHT
	var foliage := MeshInstance3D.new()
	foliage.mesh = foliage_mesh
	foliage.material_override = ToonMaterial.create(foliage_color)
	foliage.position = Vector3(0, TREE_TRUNK_HEIGHT + TREE_FOLIAGE_HEIGHT * 0.5 - 0.3, 0)
	tree.add_child(foliage)


## Solid, unlike the racetrack's scattered scenery boulders — a rock you place
## deliberately is meant to be in the way.
static func _build_rock(
	parent: Node3D, base: Vector3, yaw: float, size: float, rock_color: Color
) -> void:
	var body := StaticBody3D.new()
	body.name = "Rock"
	parent.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, size * 0.45, 0))

	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 1.6
	mesh.radial_segments = 7 # faceted, so it reads as rock rather than fruit
	mesh.rings = 3
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = ToonMaterial.create(rock_color)
	body.add_child(visual)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = size * 0.9
	shape.shape = sphere
	body.add_child(shape)


static func _build_crate(parent: Node3D, base: Vector3, yaw: float, size: float) -> void:
	var side := size * 2.4
	var body := StaticBody3D.new()
	body.name = "Crate"
	parent.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, side * 0.5, 0))

	var mesh := BoxMesh.new()
	mesh.size = Vector3(side, side, side)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = ToonMaterial.create(Color(0.72, 0.5, 0.25))
	body.add_child(visual)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	body.add_child(shape)


## A flat deck of `length` metres running along `yaw`, railed both sides, with a
## ramp down off each end.
##
## The deck's surface sits level with the HIGHER of the two ends' ground, so it
## spans whatever is between them rather than following it. Which is also why the
## ramps are needed: the lower end can be a couple of metres down.
static func _build_bridge(
	parent: Node3D, pos: Vector3, yaw: float, length: float, ground: TrackGround, rail_color: Color
) -> void:
	var forward := Vector3(cos(yaw), 0.0, sin(yaw))
	var end_a: Vector3 = pos - forward * length * 0.5
	var end_b: Vector3 = pos + forward * length * 0.5
	var end_heights := [
		ground.height_at(end_a.x, end_a.z), ground.height_at(end_b.x, end_b.z)
	]
	var deck_top: float = maxf(end_heights[0], end_heights[1])

	var body := StaticBody3D.new()
	body.name = "Bridge"
	parent.add_child(body)
	# Built straight from `forward` rather than as a rotation angle: the deck's
	# own long axis is its local Z, and getting the sign of that conversion wrong
	# lays the bridge across what it was meant to span.
	var basis := Basis(Vector3(forward.z, 0.0, -forward.x), Vector3.UP, forward)
	body.global_transform = Transform3D(
		basis, Vector3(pos.x, deck_top - BRIDGE_THICKNESS * 0.5, pos.z)
	)

	var timber := ToonMaterial.create(Color(0.62, 0.5, 0.38))
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(BRIDGE_HALF_WIDTH * 2.0, BRIDGE_THICKNESS, length)
	var deck := MeshInstance3D.new()
	deck.mesh = deck_mesh
	deck.material_override = timber
	body.add_child(deck)

	var deck_shape := CollisionShape3D.new()
	deck_shape.name = "DeckShape"
	var deck_box := BoxShape3D.new()
	deck_box.size = deck_mesh.size
	deck_shape.shape = deck_box
	body.add_child(deck_shape)

	# One ramp per end, each pitched to land its outer edge just under the ground
	# it meets. Local +Z is along the bridge, so the near end of a ramp sits at
	# the deck's own surface height and the far end swings down from there.
	for side: int in [0, 1]:
		var sign_z: float = -1.0 if side == 0 else 1.0
		var drop: float = deck_top - (float(end_heights[side]) - BRIDGE_RAMP_SINK)
		var run: float = maxf(BRIDGE_RAMP_MIN_RUN, drop * BRIDGE_RAMP_RUN_PER_DROP)
		var pitch: float = atan(drop / run)
		# `run` and `drop` are the horizontal and vertical legs; the slab lies
		# along the hypotenuse. Sizing it by `run` instead would leave its far
		# edge short of the ground by the difference — a small step, which is the
		# one thing a kart cannot drive up.
		var slab: float = sqrt(run * run + drop * drop)
		var ramp_mesh := BoxMesh.new()
		ramp_mesh.size = Vector3(BRIDGE_HALF_WIDTH * 2.0, BRIDGE_THICKNESS, slab)
		var ramp_transform := Transform3D(
			Basis(Vector3.RIGHT, sign_z * pitch),
			Vector3(0.0, -drop * 0.5, sign_z * (length * 0.5 + run * 0.5))
		)

		var ramp := MeshInstance3D.new()
		ramp.mesh = ramp_mesh
		ramp.material_override = timber
		ramp.transform = ramp_transform
		body.add_child(ramp)

		var ramp_shape := CollisionShape3D.new()
		# Named so the checks in tests/test_track_design.gd can tell a ramp from
		# the deck and the railings, all of which are collision shapes on the
		# same body.
		ramp_shape.name = "RampShape%d" % side
		var ramp_box := BoxShape3D.new()
		ramp_box.size = ramp_mesh.size
		ramp_shape.shape = ramp_box
		ramp_shape.transform = ramp_transform
		body.add_child(ramp_shape)

	# Railings, so driving onto a bridge isn't a coin flip. On the deck only —
	# railing the ramps would fence off the way on.
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.35, BRIDGE_RAIL_HEIGHT, length)
	var rail_material := ToonMaterial.create(rail_color)
	for side: float in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		rail.mesh = rail_mesh
		rail.material_override = rail_material
		rail.position = Vector3(
			side * (BRIDGE_HALF_WIDTH - 0.2), (BRIDGE_THICKNESS + BRIDGE_RAIL_HEIGHT) * 0.5, 0.0
		)
		body.add_child(rail)

		var rail_shape := CollisionShape3D.new()
		rail_shape.name = "RailShape%d" % (0 if side < 0.0 else 1)
		var rail_box := BoxShape3D.new()
		rail_box.size = rail_mesh.size
		rail_shape.shape = rail_box
		rail_shape.position = rail.position
		body.add_child(rail_shape)
