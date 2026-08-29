extends Node3D
## Procedurally builds the open "bumper arena" — a big circular rink bounded by a
## tall candy-striped wall, ringed by tiered grandstands packed with a crowd, with
## a scatter of static crates in the middle to dodge and crash into. No track, no
## laps: karts spawn facing each other across the rink and just drive around.
## Everything here is script-generated, same philosophy as
## track_builder.gd/terrain_builder.gd.
##
## Ground itself belongs to arena_terrain_builder.gd (a Terrain3D sibling, built
## first — see that script's header for the ordering note); this script samples
## its finished heights to seat the wall/crates/spawns correctly on the bumpy
## ground rather than assuming a flat y = 0.

const ARENA_RADIUS := 225.0 # 5x the original flat-rink version

const WALL_SEGMENT_COUNT := 64
const WALL_HEIGHT := 9.0
const WALL_THICKNESS := 1.5
## Straight chords approximating a circle fall a little short of the arc between
## them — segments are sized up so consecutive ones overlap instead of leaving a
## kart-sized gap at the seams.
const WALL_SEGMENT_OVERLAP := 1.15

const CRATE_COUNT := 24
const CRATE_SIZE := 2.4
const CRATE_MIN_RADIUS := 40.0   # stay this far from center — keeps an open middle
const CRATE_MAX_RADIUS := 170.0  # and this far from the wall

const START_RADIUS := 150.0 # how far from center each kart spawns, facing the middle

## Item boxes, scattered on two rings so there's always one worth driving toward
## from anywhere in the rink. Kept off the open middle (where the fights happen)
## and well inside the wall.
const ITEM_BOX_COUNT := 14
const ITEM_BOX_MIN_RADIUS := 55.0
const ITEM_BOX_MAX_RADIUS := 165.0

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
## single MultiMesh, same cheap-at-scale technique as track_builder.gd's
## tree/bush/flower scattering.
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


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path)
	_build_wall()
	_build_crates()
	_build_item_boxes()
	_build_grandstands()
	_build_crowd()


func _ground_height(x: float, z: float) -> float:
	if _terrain and _terrain.data:
		return _terrain.data.get_height(Vector3(x, 0.0, z))
	return 0.0


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
		var ground := _ground_height(x, z)
		var pos := Vector3(x, ground + WALL_HEIGHT * 0.5, z)

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

	var mesh := BoxMesh.new()
	mesh.size = Vector3(CRATE_SIZE, CRATE_SIZE, CRATE_SIZE)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	var mat := ToonMaterial.create(Color(0.75, 0.5, 0.22), 0.1)

	var crates := Node3D.new()
	crates.name = "Crates"
	add_child(crates)

	for i in range(CRATE_COUNT):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(CRATE_MIN_RADIUS, CRATE_MAX_RADIUS)
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		var ground := _ground_height(x, z)
		var pos := Vector3(x, ground + CRATE_SIZE * 0.5, z)

		var body := StaticBody3D.new()
		body.name = "Crate%d" % i
		body.transform = Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), pos)
		crates.add_child(body)

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = mesh
		mesh_inst.material_override = mat
		body.add_child(mesh_inst)

		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)


## Purely visual (MeshInstance3D only, no collision) — well outside the wall and
## unreachable, so there's no reason to pay for collision shapes on it.
func _build_grandstands() -> void:
	var stands := Node3D.new()
	stands.name = "Grandstands"
	add_child(stands)

	var base_radius := ARENA_RADIUS + GRANDSTAND_GAP
	var ground := _ground_height(base_radius, 0.0) # flat-ish out here; one sample is enough
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


## Power-up boxes scattered around the rink. Skipped entirely when items are
## turned off on the main menu (same rule track_builder.gd follows).
func _build_item_boxes() -> void:
	if not GameSettings.items_enabled:
		return
	var scene: PackedScene = load("res://scenes/item_box.tscn")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091 # fixed, so the boxes are in the same spots every session
	for i in range(ITEM_BOX_COUNT):
		# Evenly spaced angles with a little jitter, rather than fully random
		# placement, so no arc of the rink ends up with no boxes at all.
		var angle: float = TAU * (i + rng.randf_range(-0.3, 0.3)) / float(ITEM_BOX_COUNT)
		var radius: float = rng.randf_range(ITEM_BOX_MIN_RADIUS, ITEM_BOX_MAX_RADIUS)
		var x: float = cos(angle) * radius
		var z: float = sin(angle) * radius
		var box := scene.instantiate()
		add_child(box)
		box.global_position = Vector3(x, _ground_height(x, z), z)


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


## Rink dimensions for the arena bots' wall avoidance (see ai_driver.gd).
func get_arena_radius() -> float:
	return ARENA_RADIUS


func get_arena_center() -> Vector3:
	return Vector3(0.0, _ground_height(0.0, 0.0), 0.0)
