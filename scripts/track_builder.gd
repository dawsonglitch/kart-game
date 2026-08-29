extends Node3D
## Procedurally builds the racetrack. Everything below describes the *layout* —
## where the road goes, how wide it is, and what sits on it — and hands the actual
## construction off to RoadRibbon (the road surface), TrackProps (the built
## structures) and TrackGround (the height field the terrain and the props share).
##
## The lap is a ~910 m counter-clockwise circuit in three distinct thirds:
##
##   MEADOW   start/finish straight past the grandstands, a fast banked left onto
##            the east straight (painted down the middle: boost lane or item
##            lane), then the chicane.
##   CANYON   the climb to Ramp 1 and the drop off its lip, a stone arch gallery
##            over the landing straight, a second lane split, and then the viaduct
##            — a pinched, railed span over a carved gorge with water at the
##            bottom.
##   FOREST   Down off the viaduct into the trees, round the tightest corner on the
##            lap, then the climb to Ramp 2 — whose lip drops you onto the start
##            straight, in the air, in front of the grandstands.
##
## Two things make the shape readable while driving: the road BANKS into its
## corners (outside edge raised, generated in road_ribbon.gd) and its WIDTH
## changes — 16 m across the start straight, 9.2 m over the viaduct. Both are
## smooth functions of distance round the lap, so editing the layout below can't
## desync them.

const WAYPOINTS: Array[Vector3] = [
	Vector3(0, 0, 124),      # 0  start / finish line
	Vector3(40, 0, 128),     # 1  start straight, grandstands both sides
	Vector3(76, 0, 116),     # 2  Turn 1 entry
	Vector3(100, 0, 88),     # 3  Turn 1 apex — the fastest banked corner on the lap
	Vector3(110, 0, 52),     # 4  Turn 1 exit
	Vector3(112, 0, 14),     # 5  east straight — widest point, painted down the middle
	Vector3(96, 0, -18),     # 6  chicane in
	Vector3(110, 0, -50),    # 7  chicane out
	Vector3(98, 0, -84),     # 8  sweeping into the climb
	Vector3(62, 4, -112),    # 9  climbing
	Vector3(22, 9, -128),    # 10 RAMP 1 lip — sharp kink, see SHARP_TANGENT_INDICES
	Vector3(-10, -4, -138),  # 11 steep drop past the lip
	Vector3(-50, -3, -132),  # 12 landing zone, under the arch gallery
	Vector3(-88, -1, -112),  # 13 south-west sweeper
	Vector3(-118, 2, -80),   # 14 climbing onto the viaduct
	Vector3(-132, 6, -44),   # 15 VIADUCT south end
	Vector3(-134, 8, -4),    # 16 VIADUCT mid-span, highest point over the gorge
	Vector3(-126, 6, 34),    # 17 VIADUCT north end
	Vector3(-116, 0, 68),    # 18 down off the viaduct into the trees
	Vector3(-98, 0, 100),    # 19 forest sweep
	Vector3(-100, 0, 134),   # 20 turning through the trees
	Vector3(-92, 0, 158),    # 21 the tightest corner on the lap
	Vector3(-62, 4, 152),    # 22 climbing east to ramp 2
	Vector3(-40, 9, 140),    # 23 RAMP 2 lip — sharp kink
	Vector3(-18, -2, 130),   # 24 steep drop past the lip, landing on the start
	                         #    straight. It holds the climb's heading almost
	                         #    exactly, which matters more here than anywhere:
	                         #    an earlier layout turned ~100 degrees within 6 m
	                         #    of the landing and the road folded over itself,
	                         #    leaving a hundred square metres of inside-out
	                         #    collision right where karts touch down.
]

## Waypoints that get a much tighter tangent than the smooth default, so the curve
## keeps a sharp kink instead of easing through it. 10 and 23 are the ramp lips
## (which want to read as real cliff edges — jump_pad.gd does the actual
## launching), 11 and 24 the points just past them, and 21 is the forest corner,
## which is meant to be genuinely tight rather than another sweeper.
const SHARP_TANGENT_INDICES := {10: 0.02, 11: 0.05, 21: 0.12, 23: 0.02, 24: 0.05}
const DEFAULT_TANGENT_SCALE := 0.25

## Half-width of the drivable road at each listed waypoint, in metres;
## road_ribbon.gd interpolates and smooths between them, so only the waypoints
## where the width actually changes need an entry.
const ROAD_HALF_WIDTHS := {
	0: 7.5,   # start/finish — room for a four-kart grid
	1: 7.5,
	2: 7.0,   # Turn 1, fast and wide
	4: 7.0,
	5: 8.0,   # east straight, widest on the lap — wide enough for the island
	6: 5.4,   # chicane, pinched
	7: 5.4,
	8: 6.4,
	10: 6.4,  # ramps stay a normal width; the drop is the difficulty
	12: 7.2,  # landing zone, deliberately generous
	13: 7.2,
	14: 6.0,
	15: 4.6,  # VIADUCT — the narrowest road on the lap
	17: 4.6,
	18: 6.0,
	19: 5.6,  # into the forest, tightening
	21: 5.4,  # the forest corner
	22: 6.4,  # opening out onto the climb to ramp 2
	24: 7.0,  # landing, wide, running onto the start straight
}

## Waypoint spans held at zero bank. Both ramps: a banked lip throws a kart
## sideways in mid-air, and a banked landing is a nasty surprise on touchdown.
const FLAT_BANK_SPANS := [[9.0, 11.5], [22.0, 24.5]]

## Placements are fractional waypoint indices — 4.5 is halfway (by arc length)
## between waypoints 4 and 5 — rather than raw distances round the lap. The old
## version used hand-measured metre offsets, which quietly desynced from the
## track the moment a waypoint moved.
const BOOST_PAD_PLACEMENTS := [1.25, 4.55, 8.6, 16.0, 22.4, 24.5]
const JUMP_PAD_PLACEMENTS := [10.0, 23.0]
const OIL_HAZARD_PLACEMENTS := [4.3, 6.6, 19.5]
const OBSTACLE_PLACEMENTS := [3.5, 7.45, 20.2]
const CHECKPOINT_COUNT := 14

## Rows of item boxes across the road, one per kart in a three-wide pack, so
## picking a lane is a real (if tiny) decision. Kept clear of the ramp lips —
## grabbing a box mid-launch would be luck, not skill — and of the split islands,
## which hand out their own.
const ITEM_BOX_PLACEMENTS := [1.7, 8.3, 15.0, 18.4, 21.7]
## As a fraction of the local half-width, so a row stays proportioned to the road
## whether it's on the wide east straight or the narrow viaduct.
const ITEM_BOX_LANES := [-0.55, 0.0, 0.55]

## Wide stretches painted down the middle: one lane gets a boost pad, the other a
## pair of item boxes.
const LANE_SPLITS := [
	{"at": 5.05, "boost_side": 1.0},
	{"at": 13.6, "boost_side": -1.0},
]

## Structures, as [from, to] fractional waypoint spans.
const VIADUCT_SPAN := [14.55, 17.45]
const ARCH_GALLERY_SPAN := [12.25, 13.0]
## Straddles the finish line, and starts at the ramp 2 landing — the crowd lines
## the run-out, so you come down out of the air in front of them.
const GRANDSTAND_SPAN := [24.1, 1.35]
## Striped boards framing the outside of the two corners quick enough to run wide
## at. Decoration, not walls — see TrackProps.build_barrier. `side` 0 lets it pick
## the outside from the road's own camber.
const BARRIER_SPANS := [
	{"from": 2.4, "to": 3.8, "side": 0.0},
	{"from": 20.4, "to": 21.7, "side": 0.0},
]

## Standalone hills, independent of the road. The big one at the origin is the
## infield butte every corner is framed against; the rest are the skyline.
## `flat` is the fraction of the radius that stays at full height (a mesa crown).
const MESAS := [
	{"pos": Vector2(0, 0), "radius": 58.0, "height": 17.0, "flat": 0.45},
	{"pos": Vector2(44, 62), "radius": 30.0, "height": 9.0, "flat": 0.2},
	{"pos": Vector2(-44, -46), "radius": 34.0, "height": 11.0, "flat": 0.25},
	{"pos": Vector2(0, 214), "radius": 66.0, "height": 27.0, "flat": 0.3},
	{"pos": Vector2(186, -66), "radius": 62.0, "height": 25.0, "flat": 0.3},
	{"pos": Vector2(-206, 66), "radius": 58.0, "height": 23.0, "flat": 0.3},
	{"pos": Vector2(46, -214), "radius": 64.0, "height": 26.0, "flat": 0.3},
	{"pos": Vector2(-160, 186), "radius": 50.0, "height": 20.0, "flat": 0.3},
]

## Carved through everything else. The first is the gorge the viaduct spans — its
## floor is below the y < -10 respawn line in kart_controller.gd, so a kart that
## somehow gets past the railings is put back on the road rather than falling
## forever. The second is an infield lake, pure scenery.
## `flat` is the fraction of the radius held at floor level before the wall
## starts climbing back out.
const CANYONS := [
	{
		"from": Vector2(-134, -46), "to": Vector2(-130, 34),
		"radius": 30.0, "flat": 0.45, "floor": -22.0, "water": -15.0,
	},
	{
		"from": Vector2(34, 34), "to": Vector2(70, 20),
		"radius": 38.0, "flat": 0.55, "floor": -5.0, "water": -2.2,
	},
]

## Scenery character per waypoint, which is most of what makes the three thirds of
## the lap feel like different places.
enum Biome { MEADOW, ROCKY, FOREST }
const WAYPOINT_BIOMES := [
	Biome.MEADOW, Biome.MEADOW, Biome.MEADOW, Biome.MEADOW, Biome.MEADOW, Biome.MEADOW,
	Biome.MEADOW, Biome.MEADOW,
	Biome.ROCKY, Biome.ROCKY, Biome.ROCKY, Biome.ROCKY, Biome.ROCKY, Biome.ROCKY,
	Biome.ROCKY, Biome.ROCKY, Biome.ROCKY, Biome.ROCKY,
	Biome.FOREST, Biome.FOREST, Biome.FOREST, Biome.FOREST, Biome.FOREST, Biome.FOREST,
	Biome.FOREST,
]

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

## Scenery scattering along both shoulders, built as a handful of
## MultiMeshInstance3D nodes so a few thousand props cost almost nothing to draw.
## Purely decorative, no collision.
const SCENERY_SAMPLE_INTERVAL := 6.0
const SCENERY_MIN_GAP := 5.0     # beyond the road edge, so nothing crowds the kerb
const SCENERY_MAX_GAP := 24.0
const TREE_TRUNK_HEIGHT := 2.2
const TREE_FOLIAGE_HEIGHT := 2.6
const FLOWER_COLORS := [
	Color(1, 0.45, 0.7), Color(1, 0.85, 0.2), Color(0.7, 0.45, 0.9), Color(1, 1, 1)
]

@onready var path: Path3D = $Path3D
@onready var road_mesh: MeshInstance3D = $RoadMesh
@onready var road_body: StaticBody3D = $RoadBody
@onready var road_shape: CollisionShape3D = $RoadBody/RoadShape

var baked_length: float = 0.0

var _ribbon: RoadRibbon
var _ground: TrackGround
## Arc-length offset of each waypoint, used to turn the fractional placements
## above into real distances round the lap.
var _wp_offsets: PackedFloat32Array


func _ready() -> void:
	_boost_pad_scene = load("res://scenes/boost_pad.tscn")
	_jump_pad_scene = load("res://scenes/jump_pad.tscn")
	_hazard_oil_scene = load("res://scenes/hazard_oil.tscn")
	_hazard_obstacle_scene = load("res://scenes/hazard_obstacle.tscn")
	_checkpoint_scene = load("res://scenes/checkpoint.tscn")
	_item_box_scene = load("res://scenes/item_box.tscn")

	_build_curve()
	baked_length = path.curve.get_baked_length()
	_measure_waypoints()
	_build_road()
	_ground = TrackGround.create(_ribbon, MESAS, CANYONS)

	_place_boost_pads()
	_place_jump_pads()
	_place_hazards()
	_place_checkpoints()
	_place_item_boxes()
	_build_finish_line()
	_build_structures()
	_place_scenery()


## Note the extra point at the end, repeating waypoint 0 with the same tangents.
## Without it Curve3D is an OPEN curve running from waypoint 0 to waypoint 23 and
## simply stopping — the 24 m closing segment back across the finish line is not
## part of the baked curve at all, and get_baked_length() does not count it. The
## old road hid that because CSGPolygon3D has a `path_joined` flag that welds its
## last section to its first, but everything measured *against* the curve was
## quietly working with an incomplete lap: a 24 m stretch of road with no
## checkpoint or scenery on it, and karts sitting on it reporting a race position
## from the wrong end of the lap. Repeating the point closes it for real.
func _build_curve() -> void:
	var curve := Curve3D.new()
	var count := WAYPOINTS.size()
	for i in range(count + 1):
		var index: int = i % count
		var prev: Vector3 = WAYPOINTS[(index - 1 + count) % count]
		var point: Vector3 = WAYPOINTS[index]
		var next: Vector3 = WAYPOINTS[(index + 1) % count]
		var tangent_scale: float = SHARP_TANGENT_INDICES.get(index, DEFAULT_TANGENT_SCALE)
		var tangent := (next - prev) * tangent_scale
		curve.add_point(point, -tangent, tangent)
	path.curve = curve


func _measure_waypoints() -> void:
	_wp_offsets = PackedFloat32Array()
	for point in WAYPOINTS:
		_wp_offsets.append(path.curve.get_closest_offset(point))
	# Waypoint 0 sits at both ends of the closed curve, and get_closest_offset is
	# free to report either; the whole placement scheme assumes the lap starts at
	# zero.
	_wp_offsets[0] = 0.0


## Fractional waypoint index -> distance round the lap in metres.
func _offset(index: float) -> float:
	var count := WAYPOINTS.size()
	var i: int = int(floor(index)) % count
	var frac: float = index - floor(index)
	var from: float = _wp_offsets[i]
	var to: float = _wp_offsets[(i + 1) % count]
	if to <= from:
		to += baked_length # the span that wraps past the finish line
	return fposmod(from + (to - from) * frac, baked_length)


func _build_road() -> void:
	var widths: Array = []
	var indices: Array = ROAD_HALF_WIDTHS.keys()
	indices.sort()
	for i in indices:
		widths.append([_wp_offsets[i], ROAD_HALF_WIDTHS[i]])
	var flats: Array = []
	for span in FLAT_BANK_SPANS:
		flats.append([_offset(span[0]), _offset(span[1])])

	_ribbon = RoadRibbon.build(path.curve, widths, flats)
	road_mesh.mesh = _ribbon.mesh
	road_shape.shape = _ribbon.shape


func _transform_at(offset: float) -> Transform3D:
	return _ribbon.frame_at(offset)


# ---------------------------------------------------------------------------
# Track furniture
# ---------------------------------------------------------------------------

func _place_boost_pads() -> void:
	for placement in BOOST_PAD_PLACEMENTS:
		_add_pad(_boost_pad_scene, _offset(placement), 0.0)


func _place_jump_pads() -> void:
	for placement in JUMP_PAD_PLACEMENTS:
		_add_pad(_jump_pad_scene, _offset(placement), 0.0)


func _add_pad(scene: PackedScene, offset: float, lateral: float) -> Node3D:
	var pad: Node3D = scene.instantiate()
	add_child(pad)
	pad.global_transform = _transform_at(offset).translated_local(Vector3(lateral, 0.0, 0.0))
	return pad


func _place_hazards() -> void:
	for placement in OIL_HAZARD_PLACEMENTS:
		var oil := _hazard_oil_scene.instantiate()
		add_child(oil)
		oil.global_transform = _transform_at(_offset(placement))
	for placement in OBSTACLE_PLACEMENTS:
		var obstacle := _hazard_obstacle_scene.instantiate()
		add_child(obstacle)
		obstacle.global_transform = _transform_at(_offset(placement))


## How far past the kerb each checkpoint gate reaches. race_manager requires every
## gate in order before a lap counts and says nothing when one is missed, so a kart
## that runs wide and drives round the end of a gate simply never scores the lap —
## measured in an AI race, the slowest bot ran wide at the forest corner and
## finished a hundred and fifty seconds with no laps to show for it while the other
## two banked two each. The margin is generous for that reason; the road never
## passes within 23 m of another stretch of itself (tests/test_track_map.gd checks
## this), so a gate this wide still cannot be tripped from the wrong piece of road.
const CHECKPOINT_MARGIN := 10.0


## Gates are also scaled to the road: the checkpoint scene's shape is 13 m across,
## which no longer spans the road everywhere now that the width varies (the start
## straight is 16 m of tarmac plus kerbs).
func _place_checkpoints() -> void:
	var race_manager := get_tree().get_first_node_in_group("race_manager")
	for i in range(CHECKPOINT_COUNT):
		var offset := baked_length * float(i) / float(CHECKPOINT_COUNT)
		var checkpoint := _checkpoint_scene.instantiate()
		add_child(checkpoint)
		checkpoint.global_transform = _transform_at(offset)
		var wanted: float = (_ribbon.half_width_at(offset) + CHECKPOINT_MARGIN) * 2.0
		checkpoint.scale = Vector3(wanted / 13.0, 1.0, 1.0)
		checkpoint.checkpoint_index = i
		checkpoint.is_finish_line = (i == 0)
		if race_manager:
			race_manager.register_checkpoint(checkpoint)


## Skipped entirely when items are turned off on the main menu, so that setting
## genuinely gives back the original game rather than leaving inert boxes lying
## around the track.
func _place_item_boxes() -> void:
	if not GameSettings.items_enabled:
		return
	for placement in ITEM_BOX_PLACEMENTS:
		var offset := _offset(placement)
		var half_width := _ribbon.half_width_at(offset)
		for lane in ITEM_BOX_LANES:
			_add_item_box(offset, lane * half_width)


func _add_item_box(offset: float, lateral: float) -> void:
	var box := _item_box_scene.instantiate()
	add_child(box)
	box.global_transform = _transform_at(offset).translated_local(Vector3(lateral, 0.0, 0.0))


# ---------------------------------------------------------------------------
# Structures
# ---------------------------------------------------------------------------

func _build_structures() -> void:
	TrackProps.build_viaduct(
		self, _ribbon, _ground, _offset(VIADUCT_SPAN[0]), _offset(VIADUCT_SPAN[1])
	)
	TrackProps.build_water(self, CANYONS)
	TrackProps.build_arch_gallery(
		self, _ribbon, _offset(ARCH_GALLERY_SPAN[0]), _offset(ARCH_GALLERY_SPAN[1])
	)
	# The grandstand run straddles the finish line, so its start offset is past
	# its end offset; unwrapping it keeps the loop that walks it going forwards.
	var stand_from := _offset(GRANDSTAND_SPAN[0])
	var stand_to := _offset(GRANDSTAND_SPAN[1])
	if stand_to < stand_from:
		stand_to += baked_length
	TrackProps.build_grandstands(self, _ribbon, _ground, stand_from, stand_to)

	for span in BARRIER_SPANS:
		TrackProps.build_barrier(
			self, _ribbon, _offset(span["from"]), _offset(span["to"]), span["side"]
		)

	for split in LANE_SPLITS:
		var offset := _offset(split["at"])
		var half_width := _ribbon.half_width_at(offset)
		var lane: float = half_width * 0.55
		TrackProps.build_lane_split(self, _ribbon, offset)
		var boost_side: float = split["boost_side"]
		_add_pad(_boost_pad_scene, offset, boost_side * lane)
		if GameSettings.items_enabled:
			_add_item_box(offset - 3.0, -boost_side * lane)
			_add_item_box(offset + 3.0, -boost_side * lane)

	TrackProps.build_markers(self, _ribbon, _ground)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## The racing line, handed to race.gd for the bots to follow and to race_manager
## for computing how far around the lap each kart is. Deliberately NOT named
## get_path() — that's a Node method already, and shadowing it would break every
## NodePath lookup against this node.
func get_racing_path() -> Path3D:
	return path


## The generated road. terrain_builder.gd uses it to keep the ground clear of the
## real, variable-width, banked road surface rather than a guessed corridor.
func get_ribbon() -> RoadRibbon:
	return _ribbon


## The height field this track's props are already seated on — terrain_builder.gd
## stamps the same one into the actual heightmap, so the two can't disagree.
func get_ground() -> TrackGround:
	return _ground


## Used by race_manager to place karts at the start line, side by side.
func get_start_transform(lane_offset: float) -> Transform3D:
	return _transform_at(0.0).translated_local(Vector3(lane_offset, 0.0, 0.0))


# ---------------------------------------------------------------------------
# Finish line — a checkered arch over the road plus a checkered ground stripe,
# so it's obvious the moment you cross it, not just a number ticking up in the HUD.
# ---------------------------------------------------------------------------

func _build_finish_line() -> void:
	var t := _transform_at(0.0)
	var half_width := _ribbon.half_width_at(0.0)
	var post_lateral := half_width + 1.2
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
		post.global_transform = t.translated_local(Vector3(side * post_lateral, 2.75, 0))

	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(post_lateral * 2.0 + 0.4, 1.3, 0.2)
	var banner := MeshInstance3D.new()
	banner.mesh = banner_mesh
	banner.material_override = checker_mat
	add_child(banner)
	banner.global_transform = t.translated_local(Vector3(0, 5.2, 0))

	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(half_width * 2.0 + 0.6, 0.08, 2.0)
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
# Scenery — themed by which third of the lap it sits beside.
# ---------------------------------------------------------------------------

func _place_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 # fixed seed so the layout is stable across runs, not reshuffled every load

	var trunks: Array[Transform3D] = []
	var foliage: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var flowers: Array[Transform3D] = []
	var boulders: Array[Transform3D] = []
	var spires: Array[Transform3D] = []

	var offset := 0.0
	while offset < baked_length:
		var base := _transform_at(offset)
		var biome: int = _biome_at(offset)
		var half_width := _ribbon.half_width_at(offset)
		for side: float in [-1.0, 1.0]:
			for _slot in range(3):
				if rng.randf() > _biome_density(biome):
					continue
				var lateral: float = side * (
					half_width + rng.randf_range(SCENERY_MIN_GAP, SCENERY_MAX_GAP)
				)
				var forward_jitter := rng.randf_range(-2.5, 2.5)
				var pos: Vector3 = (
					base.origin + base.basis.x * lateral + base.basis.z * forward_jitter
				)
				# Nothing sensible to plant on a cliff face or in open water.
				if _ground.in_canyon(pos.x, pos.z):
					continue
				pos.y = _ground.height_at(pos.x, pos.z)
				var yaw := rng.randf_range(0.0, TAU)
				var pick := rng.randf()
				match biome:
					Biome.FOREST:
						if pick < 0.78:
							_add_tree(trunks, foliage, pos, yaw, rng.randf_range(0.9, 1.5))
						elif pick < 0.94:
							_add_scaled(bushes, pos, yaw, rng.randf_range(0.7, 1.2), 0.45)
						else:
							_add_scaled(flowers, pos, yaw, rng.randf_range(0.6, 1.1), 0.14)
					Biome.ROCKY:
						if pick < 0.5:
							_add_scaled(boulders, pos, yaw, rng.randf_range(0.7, 2.1), 0.35)
						elif pick < 0.78:
							_add_scaled(spires, pos, yaw, rng.randf_range(0.8, 2.4), 1.4)
						elif pick < 0.92:
							_add_scaled(bushes, pos, yaw, rng.randf_range(0.5, 0.9), 0.45)
						else:
							_add_tree(trunks, foliage, pos, yaw, rng.randf_range(0.7, 1.0))
					_:
						if pick < 0.22:
							_add_tree(trunks, foliage, pos, yaw, rng.randf_range(0.8, 1.3))
						elif pick < 0.5:
							_add_scaled(bushes, pos, yaw, rng.randf_range(0.7, 1.2), 0.45)
						else:
							_add_scaled(flowers, pos, yaw, rng.randf_range(0.6, 1.1), 0.14)
		offset += SCENERY_SAMPLE_INTERVAL

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.24
	trunk_mesh.height = TREE_TRUNK_HEIGHT
	TrackProps._multimesh(self, "TreeTrunks", trunks, trunk_mesh, Color(0.42, 0.28, 0.16))

	var foliage_mesh := CylinderMesh.new()
	foliage_mesh.top_radius = 0.0
	foliage_mesh.bottom_radius = 1.7
	foliage_mesh.height = TREE_FOLIAGE_HEIGHT
	TrackProps._multimesh(self, "TreeFoliage", foliage, foliage_mesh, Color(0.16, 0.5, 0.22))

	var bush_mesh := SphereMesh.new()
	bush_mesh.radius = 0.55
	bush_mesh.height = 0.9
	TrackProps._multimesh(self, "Bushes", bushes, bush_mesh, Color(0.22, 0.55, 0.25))

	var boulder_mesh := SphereMesh.new()
	boulder_mesh.radius = 0.9
	boulder_mesh.height = 1.2
	boulder_mesh.radial_segments = 7 # low and faceted, so they read as rock, not fruit
	boulder_mesh.rings = 3
	TrackProps._multimesh(self, "Boulders", boulders, boulder_mesh, Color(0.52, 0.5, 0.48))

	var spire_mesh := CylinderMesh.new()
	spire_mesh.top_radius = 0.12
	spire_mesh.bottom_radius = 0.95
	spire_mesh.height = 2.8
	spire_mesh.radial_segments = 6
	TrackProps._multimesh(self, "RockSpires", spires, spire_mesh, Color(0.46, 0.43, 0.42))

	_build_flowers(flowers)


func _biome_at(offset: float) -> int:
	# Whichever waypoint span this offset falls in decides the character here.
	var count := WAYPOINTS.size()
	for i in range(count):
		var from: float = _wp_offsets[i]
		var to: float = _wp_offsets[(i + 1) % count]
		var span: float = fposmod(to - from, baked_length)
		if span > 0.0 and fposmod(offset - from, baked_length) < span:
			return WAYPOINT_BIOMES[i]
	return Biome.MEADOW


func _biome_density(biome: int) -> float:
	match biome:
		Biome.FOREST:
			return 0.72
		Biome.ROCKY:
			return 0.4
		_:
			return 0.34


func _add_tree(
	trunks: Array[Transform3D], foliage: Array[Transform3D], pos: Vector3, yaw: float, scale: float
) -> void:
	var trunk := Transform3D(
		Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(scale, scale, scale)),
		pos + Vector3(0, TREE_TRUNK_HEIGHT * 0.5 * scale, 0)
	)
	trunks.append(trunk)
	foliage.append(
		trunk.translated_local(Vector3(0, (TREE_TRUNK_HEIGHT + TREE_FOLIAGE_HEIGHT) * 0.5, 0))
	)


func _add_scaled(
	into: Array[Transform3D], pos: Vector3, yaw: float, scale: float, half_height: float
) -> void:
	into.append(Transform3D(
		Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(scale, scale, scale)),
		pos + Vector3(0, half_height * scale, 0)
	))


func _build_flowers(transforms: Array[Transform3D]) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.28
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var colors: Array[Color] = []
	for _i in range(transforms.size()):
		colors.append(FLOWER_COLORS[rng.randi_range(0, FLOWER_COLORS.size() - 1)])
	TrackProps._multimesh(self, "Flowers", transforms, mesh, Color.WHITE, colors)
