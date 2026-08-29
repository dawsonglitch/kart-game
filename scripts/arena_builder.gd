extends Node3D
## Procedurally builds the bumper arena's furniture — everything standing on the
## ground that arena_terrain_builder.gd shaped.
##
## The rink used to be a flat disc with two dozen crates scattered on it, which at
## 225 m of radius mostly read as a very large empty field. It now has places:
##
##   THE BUTTE      a plateau in the middle, too steep to climb except up four
##                  ramp spurs, with a monument and a ring of item boxes on top.
##                  Somewhere worth being, and worth shoving people off.
##   THE BANKING    the ground sweeps up into the boundary wall, so the rim is a
##                  velodrome you carry speed round instead of a thing you scrape.
##   THE CRATER     a bowl carved out of the north-west, with item boxes in it.
##   THE GROVE      a stand of pillars to weave through or lose someone in.
##   THE KICKERS    four ramps shaped into the ground with jump pads on their
##                  crests, for the air the arena never had.
##   BOOST RING     pads set tangentially, so the fast line round the rink is a
##                  real line rather than "anywhere".
##
## Everything is seated and tilted to the finished terrain — arena_terrain_builder
## is a sibling listed before this node in arena.tscn, so its heightmap is already
## stamped by the time _ready() runs here. Nothing needs to assume flat ground.

const ARENA_RADIUS := 225.0

const WALL_SEGMENT_COUNT := 64
const WALL_HEIGHT := 9.0
const WALL_THICKNESS := 1.5
## Straight chords approximating a circle fall a little short of the arc between
## them — segments are sized up so consecutive ones overlap instead of leaving a
## kart-sized gap at the seams.
const WALL_SEGMENT_OVERLAP := 1.15

## Loose crates, kept off the butte (whose sides are a cliff) and off the banking.
const CRATE_COUNT := 16
const CRATE_SIZE := 2.4
const CRATE_MIN_RADIUS := 72.0
const CRATE_MAX_RADIUS := 185.0

## Stacked crates — a pyramid reads as something to smash rather than something
## to steer around, and leaves a satisfying mess of loose boxes when you do.
const CRATE_STACKS := [
	Vector2(112.0, 8.0), Vector2(-24.0, 118.0), Vector2(-104.0, -122.0),
	Vector2(24.0, -116.0), Vector2(178.0, 96.0),
]

## The pillar grove.
const GROVE_CENTER := Vector2(145.0, -55.0)
const GROVE_RADIUS := 40.0
const GROVE_PILLARS := 15
const PILLAR_RADIUS := 2.2
const PILLAR_HEIGHT := 8.0

## Boost pads: a ring set tangentially, plus one part-way up each terrain spur so
## there's a reason to take the ramp at speed.
const BOOST_RING_COUNT := 8
const BOOST_RING_RADIUS := 140.0
const SPUR_BOOST_FRACTION := 0.55 # how far up each spur its pad sits

## Permanent oil slicks, out on the open flat where you'll be carrying speed.
const OIL_SLICKS := [
	{"turns": 0.0833, "radius": 175.0},
	{"turns": 0.5417, "radius": 175.0},
	{"turns": 0.7361, "radius": 175.0},
]

const START_RADIUS := 150.0 # how far from centre each kart spawns, facing the middle

## Item boxes: a scattered ring out on the flat, a crown on top of the butte, and
## a few down in the crater — so every one of the arena's places is worth visiting.
const ITEM_BOX_RING_COUNT := 12
const ITEM_BOX_MIN_RADIUS := 88.0
const ITEM_BOX_MAX_RADIUS := 185.0
const ITEM_BOX_CROWN_COUNT := 4
const ITEM_BOX_CROWN_RADIUS := 19.0
const ITEM_BOX_CRATER_COUNT := 3
const ITEM_BOX_CRATER_RADIUS := 13.0

## The monument on the butte — a landmark visible from anywhere in the rink, and
## something solid to shunt people into up there.
const MONUMENT_HEIGHT := 16.0
const MONUMENT_RADIUS := 2.6

## Grandstands: a stack of outward-flaring hollow bands (cap_top/cap_bottom off,
## so each is a pure sloped shell, not a solid disk) just past the wall — reads as
## a stylized stadium bowl from inside without needing real seat geometry.
const GRANDSTAND_TIERS := 5
const GRANDSTAND_TIER_RISE := 6.0
const GRANDSTAND_TIER_OUTWARD := 10.0
const GRANDSTAND_GAP := 6.0 # gap between the wall and the first tier's base radius
const GRANDSTAND_RADIAL_SEGMENTS := 96
const STAND_COLORS := [
	Color(0.85, 0.2, 0.2), Color(0.95, 0.95, 0.95), Color(0.2, 0.4, 0.85), Color(0.95, 0.8, 0.15)
]

## Crowd: small colored figures scattered across the grandstand tiers via a
## single MultiMesh, same cheap-at-scale technique the racetrack's scenery uses.
const CROWD_ROWS_PER_TIER := 3
const CROWD_SEATS_PER_ROW := 90
const CROWD_FILL_CHANCE := 0.55
const CROWD_FIGURE_HEIGHT := 1.5
const CROWD_FIGURE_RADIUS := 0.28
const CROWD_COLORS := [
	Color(0.9, 0.2, 0.2), Color(0.2, 0.4, 0.9), Color(0.95, 0.85, 0.2), Color(0.2, 0.75, 0.35),
	Color(0.9, 0.5, 0.15), Color(0.6, 0.25, 0.75), Color(0.95, 0.95, 0.95), Color(0.25, 0.25, 0.3),
]

@export var terrain_path: NodePath = NodePath("../Terrain")
var _terrain: Terrain3D

## Loaded at runtime rather than preload()'d — see the note in track_builder.gd
## about preload() and threaded scene loading.
var _boost_pad_scene: PackedScene
var _jump_pad_scene: PackedScene
var _hazard_oil_scene: PackedScene
var _item_box_scene: PackedScene


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path)
	_boost_pad_scene = load("res://scenes/boost_pad.tscn")
	_jump_pad_scene = load("res://scenes/jump_pad.tscn")
	_hazard_oil_scene = load("res://scenes/hazard_oil.tscn")
	_item_box_scene = load("res://scenes/item_box.tscn")

	_build_wall()
	_build_crates()
	_build_grove()
	_build_launch_pads()
	_build_boost_pads()
	_build_oil_slicks()
	_build_monument()
	_build_item_boxes()
	_build_grandstands()
	_build_crowd()


func _ground_height(x: float, z: float) -> float:
	if _terrain and _terrain.data:
		return _terrain.data.get_height(Vector3(x, 0.0, z))
	return 0.0


func _ground_normal(x: float, z: float) -> Vector3:
	if _terrain and _terrain.data:
		var n: Vector3 = _terrain.data.get_normal(Vector3(x, 0.0, z))
		if n.is_finite() and n.length() > 0.1 and n.y > 0.2:
			return n.normalized()
	return Vector3.UP


## A transform sitting on the ground and lying flat against it, with -Z pointing
## along `facing`. Anything low and wide — pads, slicks, crates — needs this: the
## rink is bumpy and hilly now, and a flat quad placed at ground height on a slope
## has one edge buried and the other in the air.
func _ground_transform(x: float, z: float, facing: Vector3, lift: float = 0.0) -> Transform3D:
	var up := _ground_normal(x, z)
	var forward := facing - up * facing.dot(up)
	if forward.length() < 0.001:
		forward = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	var origin := Vector3(x, _ground_height(x, z) + lift, z)
	return Transform3D(Basis(right, up, -forward), origin)


## Unit vector pointing anticlockwise round the rink at this position — the
## direction you'd be travelling if you were circling it.
static func _tangent_at(x: float, z: float) -> Vector3:
	var radial := Vector3(x, 0.0, z)
	if radial.length() < 0.001:
		return Vector3.FORWARD
	return Vector3.UP.cross(radial.normalized()).normalized()


func _build_wall() -> void:
	var mat_a := ToonMaterial.create(Color(0.9, 0.15, 0.15))
	var mat_b := ToonMaterial.create(Color(0.95, 0.95, 0.95))

	var wall := Node3D.new()
	wall.name = "Wall"
	add_child(wall)

	var slice_angle := TAU / float(WALL_SEGMENT_COUNT)
	var chord_len := 2.0 * ARENA_RADIUS * sin(slice_angle * 0.5) * WALL_SEGMENT_OVERLAP

	var seg_mesh := BoxMesh.new()
	seg_mesh.size = Vector3(chord_len, WALL_HEIGHT, WALL_THICKNESS)
	var seg_shape := BoxShape3D.new()
	seg_shape.size = seg_mesh.size

	for i in range(WALL_SEGMENT_COUNT):
		var angle := slice_angle * i
		var x := cos(angle) * ARENA_RADIUS
		var z := sin(angle) * ARENA_RADIUS
		# The banking lifts the ground under the wall, so each segment is seated
		# on its own local height and sunk a little to close the gap the slope
		# would otherwise leave under its uphill corner.
		var ground := _ground_height(x, z)
		var pos := Vector3(x, ground + WALL_HEIGHT * 0.5 - 1.0, z)

		var body := StaticBody3D.new()
		body.name = "WallSegment%d" % i
		body.transform = Transform3D(Basis(Vector3.UP, angle + PI * 0.5), pos)
		wall.add_child(body)

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = seg_mesh
		mesh_inst.material_override = mat_a if i % 2 == 0 else mat_b
		body.add_child(mesh_inst)

		var shape := CollisionShape3D.new()
		shape.shape = seg_shape
		body.add_child(shape)


func _build_crates() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 # fixed seed — stable layout across runs, not reshuffled every load

	var crates := Node3D.new()
	crates.name = "Crates"
	add_child(crates)

	for i in range(CRATE_COUNT):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(CRATE_MIN_RADIUS, CRATE_MAX_RADIUS)
		_add_crate(crates, cos(angle) * radius, sin(angle) * radius, rng.randf_range(0.0, TAU))

	# Three-two-one pyramids. Stacked by hand rather than dropped as physics
	# bodies: these are scenery you smash into, and a tower that has already
	# collapsed before the countdown finishes is no fun at all.
	for k in range(CRATE_STACKS.size()):
		var base: Vector2 = CRATE_STACKS[k]
		var yaw: float = TAU * float(k) / float(CRATE_STACKS.size())
		var spacing := CRATE_SIZE * 1.02
		for row in range(3):
			var count := 3 - row
			for c in range(count):
				var across: float = (float(c) - float(count - 1) * 0.5) * spacing
				var offset := Vector2(cos(yaw), sin(yaw)) * across
				_add_crate(
					crates, base.x + offset.x, base.y + offset.y, yaw,
					CRATE_SIZE * (0.5 + float(row))
				)


func _add_crate(parent: Node3D, x: float, z: float, yaw: float, lift: float = CRATE_SIZE * 0.5) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CRATE_SIZE, CRATE_SIZE, CRATE_SIZE)
	var shape := BoxShape3D.new()
	shape.size = mesh.size

	var body := StaticBody3D.new()
	body.transform = Transform3D(
		Basis(Vector3.UP, yaw), Vector3(x, _ground_height(x, z) + lift, z)
	)
	parent.add_child(body)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.material_override = ToonMaterial.create(Color(0.75, 0.5, 0.22), 0.1)
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


func _build_grove() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 313

	var grove := Node3D.new()
	grove.name = "Grove"
	add_child(grove)

	var mesh := CylinderMesh.new()
	mesh.top_radius = PILLAR_RADIUS * 0.8
	mesh.bottom_radius = PILLAR_RADIUS
	mesh.height = PILLAR_HEIGHT
	mesh.radial_segments = 10
	var mat := ToonMaterial.create(Color(0.72, 0.7, 0.66))

	for i in range(GROVE_PILLARS):
		# Evenly spaced angles with jitter, so the stand has gaps to thread rather
		# than clumps and voids.
		var angle: float = TAU * (float(i) + rng.randf_range(-0.35, 0.35)) / float(GROVE_PILLARS)
		var radius: float = GROVE_RADIUS * sqrt(rng.randf_range(0.08, 1.0))
		var x: float = GROVE_CENTER.x + cos(angle) * radius
		var z: float = GROVE_CENTER.y + sin(angle) * radius

		var body := StaticBody3D.new()
		body.position = Vector3(x, _ground_height(x, z) + PILLAR_HEIGHT * 0.5, z)
		grove.add_child(body)

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = mesh
		mesh_inst.material_override = mat
		body.add_child(mesh_inst)

		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = PILLAR_RADIUS
		shape.height = PILLAR_HEIGHT
		col.shape = shape
		body.add_child(col)


## The kickers themselves are shaped into the terrain (see
## arena_terrain_builder.gd's KICKERS, and the note there about why they are not
## slabs); all that is needed here is a jump pad lying on each crest.
func _build_launch_pads() -> void:
	var shape := _terrain_script()
	if shape == null:
		return
	for index in range(shape.KICKERS.size()):
		var crest: Dictionary = _terrain.kicker_crest(index)
		var at: Vector2 = crest["crest"]
		var direction: Vector2 = crest["direction"]
		var pad: Node3D = _jump_pad_scene.instantiate()
		add_child(pad)
		pad.global_transform = _ground_transform(
			at.x, at.y, Vector3(direction.x, 0.0, direction.y), 0.02
		)


func _build_boost_pads() -> void:
	var terrain_script := _terrain_script()
	for i in range(BOOST_RING_COUNT):
		var theta: float = TAU * float(i) / float(BOOST_RING_COUNT)
		var x: float = cos(theta) * BOOST_RING_RADIUS
		var z: float = sin(theta) * BOOST_RING_RADIUS
		var pad: Node3D = _boost_pad_scene.instantiate()
		add_child(pad)
		pad.global_transform = _ground_transform(x, z, _tangent_at(x, z), 0.02)

	if terrain_script == null:
		return
	# One on each ramp up the butte, pointing up the slope.
	var spur_count: int = terrain_script.SPUR_COUNT
	var inner: float = terrain_script.MESA_RADIUS * terrain_script.MESA_FLAT
	for k in range(spur_count):
		var theta: float = TAU * (terrain_script.SPUR_START_TURNS + float(k) / float(spur_count))
		var dir := Vector2(cos(theta), sin(theta))
		var radius: float = lerp(float(terrain_script.SPUR_OUTER_RADIUS), inner, SPUR_BOOST_FRACTION)
		var x: float = dir.x * radius
		var z: float = dir.y * radius
		var pad: Node3D = _boost_pad_scene.instantiate()
		add_child(pad)
		pad.global_transform = _ground_transform(x, z, Vector3(-dir.x, 0.0, -dir.y), 0.02)


## The terrain sibling's script, for the numbers that describe the butte and its
## ramps. Read from the live node rather than duplicated here, so moving a spur
## moves the boost pad on it too.
func _terrain_script() -> GDScript:
	if _terrain == null:
		return null
	return _terrain.get_script() as GDScript


func _build_oil_slicks() -> void:
	for slick in OIL_SLICKS:
		var theta: float = float(slick["turns"]) * TAU
		var x: float = cos(theta) * float(slick["radius"])
		var z: float = sin(theta) * float(slick["radius"])
		var oil: Node3D = _hazard_oil_scene.instantiate()
		add_child(oil)
		oil.global_transform = _ground_transform(x, z, _tangent_at(x, z), 0.02)


func _build_monument() -> void:
	var height := MONUMENT_HEIGHT
	var body := StaticBody3D.new()
	body.name = "Monument"
	body.position = Vector3(0.0, _ground_height(0.0, 0.0) + height * 0.5, 0.0)
	add_child(body)

	var mesh := CylinderMesh.new()
	mesh.top_radius = MONUMENT_RADIUS * 0.25
	mesh.bottom_radius = MONUMENT_RADIUS
	mesh.height = height
	mesh.radial_segments = 6
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.material_override = ToonMaterial.create(Color(0.95, 0.82, 0.25), 0.25)
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = MONUMENT_RADIUS
	shape.height = height
	col.shape = shape
	body.add_child(col)


## Skipped entirely when items are turned off on the main menu (same rule
## track_builder.gd follows).
func _build_item_boxes() -> void:
	if not GameSettings.items_enabled:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091 # fixed, so the boxes are in the same spots every session

	for i in range(ITEM_BOX_RING_COUNT):
		# Evenly spaced angles with a little jitter, rather than fully random
		# placement, so no arc of the rink ends up with no boxes at all.
		var angle: float = TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(ITEM_BOX_RING_COUNT)
		var radius: float = rng.randf_range(ITEM_BOX_MIN_RADIUS, ITEM_BOX_MAX_RADIUS)
		_add_item_box(cos(angle) * radius, sin(angle) * radius)

	for i in range(ITEM_BOX_CROWN_COUNT):
		var angle: float = TAU * float(i) / float(ITEM_BOX_CROWN_COUNT) + PI * 0.25
		_add_item_box(cos(angle) * ITEM_BOX_CROWN_RADIUS, sin(angle) * ITEM_BOX_CROWN_RADIUS)

	var crater: Dictionary = _first_crater()
	if not crater.is_empty():
		var center: Vector2 = crater["pos"]
		for i in range(ITEM_BOX_CRATER_COUNT):
			var angle: float = TAU * float(i) / float(ITEM_BOX_CRATER_COUNT)
			_add_item_box(
				center.x + cos(angle) * ITEM_BOX_CRATER_RADIUS,
				center.y + sin(angle) * ITEM_BOX_CRATER_RADIUS
			)


func _first_crater() -> Dictionary:
	var script := _terrain_script()
	if script == null:
		return {}
	var craters: Array = script.CRATERS
	return craters[0] if not craters.is_empty() else {}


func _add_item_box(x: float, z: float) -> void:
	var box: Node3D = _item_box_scene.instantiate()
	add_child(box)
	box.global_position = Vector3(x, _ground_height(x, z), z)


## Purely visual (MeshInstance3D only, no collision) — well outside the wall and
## unreachable, so there's no reason to pay for collision shapes on it.
func _build_grandstands() -> void:
	var stands := Node3D.new()
	stands.name = "Grandstands"
	add_child(stands)

	var base_radius := ARENA_RADIUS + GRANDSTAND_GAP
	var ground := _ground_height(base_radius, 0.0) # the banking is level all the way round
	for i in range(GRANDSTAND_TIERS):
		var bottom_r := base_radius + i * GRANDSTAND_TIER_OUTWARD
		var top_r := bottom_r + GRANDSTAND_TIER_OUTWARD

		var mesh := CylinderMesh.new()
		mesh.bottom_radius = bottom_r
		mesh.top_radius = top_r
		mesh.height = GRANDSTAND_TIER_RISE
		mesh.radial_segments = GRANDSTAND_RADIAL_SEGMENTS
		# Caps off — a cap fills the ENTIRE cross-section from the central axis
		# (r=0) out to that end's radius, not just an annular ring at the rim,
		# so leaving them on would cover the whole arena floor with a giant
		# solid disk at each tier's base/top. Hollow shell so it reads as an
		# open bowl instead — but that means
		# players standing INSIDE the bowl are looking at what CylinderMesh
		# considers the *inner*, backward-facing side. toon.gdshader hard-codes
		# `cull_back` (correct for every other prop here, which is always
		# viewed from outside), so on a shell like this it silently culled the
		# only side anyone would ever actually see, making the whole
		# grandstand invisible even though the geometry was otherwise correct.
		mesh.cap_top = false
		mesh.cap_bottom = false

		var mat := StandardMaterial3D.new()
		mat.albedo_color = STAND_COLORS[i % STAND_COLORS.size()]
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED

		var body := MeshInstance3D.new()
		body.name = "Tier%d" % i
		body.mesh = mesh
		body.material_override = mat
		body.position.y = ground + i * GRANDSTAND_TIER_RISE + GRANDSTAND_TIER_RISE * 0.5
		stands.add_child(body)


func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909 # fixed seed — stable crowd layout across runs

	var mesh := CapsuleMesh.new()
	mesh.radius = CROWD_FIGURE_RADIUS
	mesh.height = CROWD_FIGURE_HEIGHT

	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var base_radius := ARENA_RADIUS + GRANDSTAND_GAP
	# Same ground offset _build_grandstands() applies — keeps the crowd seated
	# on the tiers rather than floating relative to wherever they actually are.
	var ground := _ground_height(base_radius, 0.0)

	for tier in range(GRANDSTAND_TIERS):
		var bottom_r := base_radius + tier * GRANDSTAND_TIER_OUTWARD
		var top_r := bottom_r + GRANDSTAND_TIER_OUTWARD
		var tier_base_y := ground + tier * GRANDSTAND_TIER_RISE
		for row in range(CROWD_ROWS_PER_TIER):
			var row_t := (row + 0.5) / float(CROWD_ROWS_PER_TIER)
			var radius: float = lerp(bottom_r, top_r, row_t)
			var y: float = tier_base_y + row_t * GRANDSTAND_TIER_RISE + CROWD_FIGURE_HEIGHT * 0.5
			for seat in range(CROWD_SEATS_PER_ROW):
				if rng.randf() > CROWD_FILL_CHANCE:
					continue
				var angle: float = TAU * (seat + rng.randf_range(-0.3, 0.3)) / float(CROWD_SEATS_PER_ROW)
				var pos := Vector3(cos(angle) * radius, y, sin(angle) * radius)
				transforms.append(Transform3D(Basis(Vector3.UP, angle + PI), pos))
				colors.append(CROWD_COLORS[rng.randi_range(0, CROWD_COLORS.size() - 1)])

	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# ToonMaterial's shader always factors in per-instance COLOR, so white here
	# just lets each figure's own instance color (set above) show through as-is.
	mmi.material_override = ToonMaterial.create(Color.WHITE)
	mmi.name = "Crowd"
	add_child(mmi)


## Used by arena.gd to place each kart around the edge of the rink, facing the
## middle. `turns` is a position around the rim in full turns: 0.0 and 0.5 are
## the two original opposite spawns, and a field of N karts uses i/N so everyone
## starts evenly spread around the circle rather than stacked up.
func get_start_transform(turns: float) -> Transform3D:
	var angle: float = turns * TAU
	var x := cos(angle) * START_RADIUS
	var z := sin(angle) * START_RADIUS
	var ground := _ground_height(x, z)
	var pos := Vector3(x, ground + 0.6, z)
	var t := Transform3D()
	t.origin = pos
	return t.looking_at(Vector3(0.0, pos.y, 0.0), Vector3.UP)


## The foot of each ramp up the butte, for the arena bots (see ai_driver.gd).
## Without these a bot whose target is up on the plateau just noses into the cliff
## and shuffles along the bottom of it — the one place in the rink where "drive
## towards them" is the wrong answer.
func get_climb_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var shape := _terrain_script()
	if shape == null:
		return points
	for k in range(shape.SPUR_COUNT):
		var angle: float = TAU * (shape.SPUR_START_TURNS + float(k) / float(shape.SPUR_COUNT))
		var x: float = cos(angle) * shape.SPUR_OUTER_RADIUS
		var z: float = sin(angle) * shape.SPUR_OUTER_RADIUS
		points.append(Vector3(x, _ground_height(x, z), z))
	return points


## The plateau, as a no-go circle for the arena bots (see ai_driver.gd) — its
## sides are a cliff, so the straight line between two karts either side of it is
## not a route.
func get_plateau() -> Dictionary:
	var shape := _terrain_script()
	if shape == null:
		return {"center": Vector3.ZERO, "radius": 0.0}
	return {
		"center": Vector3(0.0, _ground_height(0.0, 0.0), 0.0),
		"radius": float(shape.MESA_RADIUS),
	}


## Rink dimensions for the arena bots' wall avoidance (see ai_driver.gd).
func get_arena_radius() -> float:
	return ARENA_RADIUS


func get_arena_center() -> Vector3:
	return Vector3(0.0, _ground_height(0.0, 0.0), 0.0)
