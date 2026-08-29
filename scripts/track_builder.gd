extends Node3D
## Procedurally builds the racetrack: a road ribbon with built-in curb "guard rails",
## two jumps, boost pads, hazards, checkpoints, a finish line, and woodsy scenery.
## Everything is generated at runtime from the WAYPOINTS list below plus the curve's
## own sampled transforms, so the whole layout — including tweaking it — lives here.

## Roughly twice the length of the original loop, laid out clockwise: a start
## straight, a sweeping east side with a chicane, a big jump down in the south,
## the west side, a second jump climbing back north, and a winding forest chicane
## through the trees back to the finish. Coordinates are the original layout scaled
## 1.4x in X/Z (measured via baked_length in a headless run) to land the lap at
## roughly double the original ~390m loop, landing at ~772m.
const WAYPOINTS: Array[Vector3] = [
	Vector3(0, 0, 119),      # 0 start/finish straight
	Vector3(35, 0, 123),
	Vector3(67, 0, 109),
	Vector3(87, 0, 77),
	Vector3(95, 0, 35),      # east straight
	Vector3(81, 0, 7),       # chicane wiggle in
	Vector3(95, 0, -21),     # chicane wiggle out
	Vector3(84, 0, -56),     # curving toward jump 1
	Vector3(49, 3, -84),     # start climbing
	Vector3(14, 8, -101),    # ramp 1 lip — sharp kink, see SHARP_TANGENT_INDICES
	Vector3(-11, -5, -112),  # steep drop past lip 1
	Vector3(-42, -2, -109),  # descending, opening toward landing
	Vector3(-77, 0, -87),    # landing zone 1
	Vector3(-101, 0, -49),   # sweeping onto the west side
	Vector3(-109, 0, 0),     # west straight
	Vector3(-84, 4, 21),     # start climbing jump 2
	Vector3(-56, 9, 35),     # ramp 2 lip — sharp kink
	Vector3(-40, -4, 55),    # steep drop past lip 2 — keeps roughly the same heading as the
							 # climb (jump 1's successful kink turns ~33°; the west turn back
							 # toward the forest chicane happens gradually at the next point instead)
	Vector3(-95, -1, 81),    # descending toward the forest chicane
	Vector3(-81, 0, 109),    # forest chicane wiggle 1 — dense trees flank this bit
	Vector3(-53, 0, 95),     # forest chicane wiggle 2
	Vector3(-28, 0, 115),    # forest chicane wiggle 3, opening onto the finish straight
]

## Waypoint indices that get a much tighter tangent than the smooth default, so the
## curve keeps a sharp kink there instead of easing through it — purely cosmetic now
## (jump_pad.gd is what actually launches karts), it just keeps each ramp reading as
## a real cliff edge rather than a smoothed-out hill. 9/16 are the ramp lips, 10/17
## are the points right after each.
const SHARP_TANGENT_INDICES := {9: 0.02, 10: 0.05, 16: 0.02, 17: 0.05}
const DEFAULT_TANGENT_SCALE := 0.25

## Offsets (meters along the baked curve from the start line), hand-tuned against the
## per-waypoint offsets measured from WAYPOINTS above. Jump pads sit right on the lips
## (waypoints 9 and 16); a couple of boost pads lead straight into each jump.
const BOOST_PAD_OFFSETS := [50.0, 130.0, 290.0, 460.0, 560.0, 700.0]
const JUMP_PAD_OFFSETS := [340.0, 607.0]
const OIL_HAZARD_OFFSETS := [200.0, 680.0]
const OBSTACLE_OFFSETS := [410.0, 520.0]
const CHECKPOINT_COUNT := 14

## Item boxes come in rows of three across the road, so there's one for each kart
## in a three-wide pack and choosing a lane is a real (if tiny) decision. Offsets
## are spaced roughly every 100-150m and deliberately kept clear of the two jump
## lips (340 / 607) — grabbing a box mid-launch would be luck, not skill.
const ITEM_BOX_OFFSETS := [90.0, 235.0, 385.0, 500.0, 645.0, 745.0]
const ITEM_BOX_LATERAL := [-3.4, 0.0, 3.4]

## Loaded with load() at runtime in _ready(), not preload()'d as top-level consts —
## preload() resolves at script *compile* time, which doesn't play well with
## ResourceLoader.load_threaded_request() (the loading screen loads this whole
## scene tree on a background thread; threaded compilation of a script with eager
## preload()s of five other scenes reliably failed with "Could not preload
## resource", even with use_sub_threads on — load() at runtime sidesteps it).
var _boost_pad_scene: PackedScene
var _jump_pad_scene: PackedScene
var _hazard_oil_scene: PackedScene
var _hazard_obstacle_scene: PackedScene
var _checkpoint_scene: PackedScene
var _item_box_scene: PackedScene

## Scenery scattering — trees/bushes/flowers along both sides of the road, built as
## a handful of MultiMeshInstance3D nodes so a few hundred props cost almost nothing
## to render. Purely decorative, no collision, so exact placement doesn't need to
## dodge track props.
const SCENERY_SAMPLE_INTERVAL := 6.0
const SCENERY_MIN_OFFSET := 11.0
const SCENERY_MAX_OFFSET := 27.0
const SCENERY_KEEP_CHANCE := 0.5
const TREE_TRUNK_HEIGHT := 2.2
const TREE_FOLIAGE_HEIGHT := 2.6
const FLOWER_COLORS := [
	Color(1, 0.45, 0.7), Color(1, 0.85, 0.2), Color(0.7, 0.45, 0.9), Color(1, 1, 1)
]

@onready var path: Path3D = $Path3D

var baked_length: float = 0.0


func _ready() -> void:
	_boost_pad_scene = load("res://scenes/boost_pad.tscn")
	_jump_pad_scene = load("res://scenes/jump_pad.tscn")
	_hazard_oil_scene = load("res://scenes/hazard_oil.tscn")
	_hazard_obstacle_scene = load("res://scenes/hazard_obstacle.tscn")
	_checkpoint_scene = load("res://scenes/checkpoint.tscn")
	_item_box_scene = load("res://scenes/item_box.tscn")
	_build_curve()
	baked_length = path.curve.get_baked_length()
	_place_boost_pads()
	_place_jump_pads()
	_place_hazards()
	_place_checkpoints()
	_place_item_boxes()
	_build_finish_line()
	_place_scenery()


func _build_curve() -> void:
	var curve := Curve3D.new()
	var count := WAYPOINTS.size()
	for i in range(count):
		var prev: Vector3 = WAYPOINTS[(i - 1 + count) % count]
		var point: Vector3 = WAYPOINTS[i]
		var next: Vector3 = WAYPOINTS[(i + 1) % count]
		var tangent_scale: float = SHARP_TANGENT_INDICES.get(i, DEFAULT_TANGENT_SCALE)
		var tangent := (next - prev) * tangent_scale
		curve.add_point(point, -tangent, tangent)
	path.curve = curve


func _transform_at(offset: float) -> Transform3D:
	return path.curve.sample_baked_with_rotation(offset, true, false)


func _place_boost_pads() -> void:
	for offset in BOOST_PAD_OFFSETS:
		var pad := _boost_pad_scene.instantiate()
		add_child(pad)
		pad.global_transform = _transform_at(offset)


func _place_jump_pads() -> void:
	for offset in JUMP_PAD_OFFSETS:
		var pad := _jump_pad_scene.instantiate()
		add_child(pad)
		pad.global_transform = _transform_at(offset)


func _place_hazards() -> void:
	for offset in OIL_HAZARD_OFFSETS:
		var oil := _hazard_oil_scene.instantiate()
		add_child(oil)
		oil.global_transform = _transform_at(offset)
	for offset in OBSTACLE_OFFSETS:
		var obstacle := _hazard_obstacle_scene.instantiate()
		add_child(obstacle)
		obstacle.global_transform = _transform_at(offset)


func _place_checkpoints() -> void:
	var race_manager := get_tree().get_first_node_in_group("race_manager")
	for i in range(CHECKPOINT_COUNT):
		var offset := baked_length * float(i) / float(CHECKPOINT_COUNT)
		var checkpoint := _checkpoint_scene.instantiate()
		add_child(checkpoint)
		checkpoint.global_transform = _transform_at(offset)
		checkpoint.checkpoint_index = i
		checkpoint.is_finish_line = (i == 0)
		if race_manager:
			race_manager.register_checkpoint(checkpoint)


## Rows of item boxes across the road. Skipped entirely when items are turned off
## on the main menu, so that setting genuinely gives back the original game rather
## than leaving inert boxes lying around the track.
func _place_item_boxes() -> void:
	if not GameSettings.items_enabled:
		return
	for offset in ITEM_BOX_OFFSETS:
		var base := _transform_at(offset)
		for lateral in ITEM_BOX_LATERAL:
			var box := _item_box_scene.instantiate()
			add_child(box)
			box.global_transform = base.translated_local(Vector3(lateral, 0.0, 0.0))


## The racing line, handed to race.gd for the bots to follow and to race_manager
## for computing how far around the lap each kart is. Deliberately NOT named
## get_path() — that's a Node method already, and shadowing it would break every
## NodePath lookup against this node.
func get_racing_path() -> Path3D:
	return path


## Used by race_manager to place karts at the start line, side by side.
func get_start_transform(lane_offset: float) -> Transform3D:
	var t := _transform_at(0.0)
	t.origin += t.basis.x * lane_offset
	return t


# ---------------------------------------------------------------------------
# Finish line — a checkered arch over the road plus a checkered ground stripe,
# so it's obvious the moment you cross it, not just a number ticking up in the HUD.
# ---------------------------------------------------------------------------

func _build_finish_line() -> void:
	var t := _transform_at(0.0)
	var checker_mat := StandardMaterial3D.new()
	checker_mat.albedo_texture = _build_checker_texture()
	checker_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	checker_mat.uv1_scale = Vector3(5, 2, 1)

	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.18
	post_mesh.bottom_radius = 0.22
	post_mesh.height = 5.5
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.85, 0.15, 0.15)

	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.material_override = post_mat
		add_child(post)
		post.global_transform = t.translated_local(Vector3(side * 6.6, 2.75, 0))

	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(13.6, 1.3, 0.2)
	var banner := MeshInstance3D.new()
	banner.mesh = banner_mesh
	banner.material_override = checker_mat
	add_child(banner)
	banner.global_transform = t.translated_local(Vector3(0, 5.2, 0))

	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(12.2, 0.08, 2.0)
	var stripe := MeshInstance3D.new()
	stripe.mesh = stripe_mesh
	stripe.material_override = checker_mat
	add_child(stripe)
	stripe.global_transform = t.translated_local(Vector3(0, 0.09, 0))


func _build_checker_texture() -> ImageTexture:
	var size := 8
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in range(size):
		for x in range(size):
			var is_white := (x + y) % 2 == 0
			image.set_pixel(x, y, Color.WHITE if is_white else Color.BLACK)
	return ImageTexture.create_from_image(image)


# ---------------------------------------------------------------------------
# Scenery — trees, bushes, and flowers scattered along both shoulders.
# ---------------------------------------------------------------------------

func _place_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 # fixed seed so the layout is stable across runs, not reshuffled every load

	var trunks: Array[Transform3D] = []
	var foliage: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var flowers: Array[Transform3D] = []

	var offset := 0.0
	while offset < baked_length:
		var base := _transform_at(offset)
		for side: float in [-1.0, 1.0]:
			for _slot in range(2):
				if rng.randf() > SCENERY_KEEP_CHANCE:
					continue
				var lateral := side * rng.randf_range(SCENERY_MIN_OFFSET, SCENERY_MAX_OFFSET)
				var forward_jitter := rng.randf_range(-2.5, 2.5)
				var pos: Vector3 = base.origin + base.basis.x * lateral + base.basis.z * forward_jitter
				var yaw := rng.randf_range(0.0, TAU)
				var pick := rng.randf()
				if pick < 0.45:
					var s := rng.randf_range(0.8, 1.3)
					var trunk_t := Transform3D(
						Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(s, s, s)),
						pos + Vector3(0, TREE_TRUNK_HEIGHT * 0.5 * s, 0)
					)
					trunks.append(trunk_t)
					foliage.append(
						trunk_t.translated_local(
							Vector3(0, (TREE_TRUNK_HEIGHT + TREE_FOLIAGE_HEIGHT) * 0.5, 0)
						)
					)
				elif pick < 0.72:
					var s := rng.randf_range(0.7, 1.2)
					bushes.append(
						Transform3D(
							Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(s, s, s)),
							pos + Vector3(0, 0.45 * s, 0)
						)
					)
				else:
					var s := rng.randf_range(0.6, 1.1)
					flowers.append(
						Transform3D(
							Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(s, s, s)),
							pos + Vector3(0, 0.14 * s, 0)
						)
					)
		offset += SCENERY_SAMPLE_INTERVAL

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.24
	trunk_mesh.height = TREE_TRUNK_HEIGHT
	_build_multimesh("TreeTrunks", trunks, trunk_mesh, Color(0.42, 0.28, 0.16))

	var foliage_mesh := CylinderMesh.new()
	foliage_mesh.top_radius = 0.0
	foliage_mesh.bottom_radius = 1.7
	foliage_mesh.height = TREE_FOLIAGE_HEIGHT
	_build_multimesh("TreeFoliage", foliage, foliage_mesh, Color(0.16, 0.5, 0.22))

	var bush_mesh := SphereMesh.new()
	bush_mesh.radius = 0.55
	bush_mesh.height = 0.9
	_build_multimesh("Bushes", bushes, bush_mesh, Color(0.22, 0.55, 0.25))

	var flower_mesh := SphereMesh.new()
	flower_mesh.radius = 0.16
	flower_mesh.height = 0.28
	_build_flower_multimesh(flowers, flower_mesh)


func _build_multimesh(node_name: String, transforms: Array[Transform3D], mesh: Mesh, color: Color) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = ToonMaterial.create(color)
	mmi.name = node_name
	add_child(mmi)


func _build_flower_multimesh(transforms: Array[Transform3D], mesh: Mesh) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, FLOWER_COLORS[rng.randi_range(0, FLOWER_COLORS.size() - 1)])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# ToonMaterial's shader always factors in per-instance COLOR, so white here just
	# lets each flower's own MultiMesh instance color (set above) show through as-is.
	mmi.material_override = ToonMaterial.create(Color.WHITE)
	mmi.name = "Flowers"
	add_child(mmi)
