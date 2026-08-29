extends Terrain3D
## Procedurally generates the ground: a heightmap that rises into hills near the
## track — higher near the two ramps, since those are the highest points on the
## track curve — and falls away to gentle rolling terrain further out, plus a
## couple of texture-paint slots (grass / dirt-rock) blended by slope and height.
## Everything here is script-generated, same philosophy as track_builder.gd.
##
## Heights/texture-IDs are written one world-position at a time via
## Terrain3DData.set_height/set_control_base_id rather than built as an Image and
## bulk-imported via import_images — verified empirically that a single
## import_images call does not correctly populate multiple regions when its
## footprint straddles a region boundary (the common case here, since the track
## spans both sides of world x=0/z=0), while per-position calls do.
##
## VERIFICATION NOTE: heights, region creation, and control/texture IDs are all
## confirmed correct headlessly (Terrain3DData.get_height/get_normal read back
## exactly what was written). Terrain3D's runtime *collision* could not be
## confirmed headlessly, even after explicitly calling Terrain3DCollision.build()
## and waiting several seconds — bodies fall straight through in every
## collision_mode value tried. This looks like a headless-specific limitation
## (Terrain3D's collision generation likely depends on GPU compute work that
## Godot's null/dummy renderer doesn't execute in --headless mode), not a bug in
## this script, but it genuinely needs checking in a real windowed session —
## don't assume it works. If it doesn't: the existing y < -10 respawn safety net
## in kart_controller.gd still catches a kart that falls through, so this is a
## cosmetic risk (no visible ground under an off-track kart), not a functional one.

const TERRAIN_SIZE := 320.0    # world-space width/height of the generated area (meters)
const SAMPLE_STEP := 2.5       # meters between height samples (== vertex_spacing, see below)
const TEXTURE_PAINT_STEP := 4.0

## The min-across-every-nearby-sample approach in _height_at (below) is safe
## regardless of how generous these are — more reach just means more candidates
## for the minimum, never a weaker guarantee — so these can go back to values that
## actually look like a hillside, unlike the emergency tightened numbers from the
## first attempt at this fix.
const NEAR_ROAD_RADIUS := 10.0     # terrain stays clearly below the road within this distance
const PEAK_RADIUS := 16.0          # hillside crest sits around here
const HILL_RADIUS := 24.0          # beyond this, pure rolling terrain (no track influence)
## Verified via a dense headless sweep (28 lateral samples x every 2m of track
## length, matched against the road's real level, non-twisted extrusion —
## CSGPolygon3D's path_rotation=1 means it does NOT use Curve3D's tilt/twist,
## confirmed against Godot's own docs) that 1.5 already left zero true height
## violations, worst-case ~1.5m of clearance. Bumped to 3.0 anyway: a chase
## camera sitting low behind a kart can make terrain that's only ~1.5m below
## curb height visually read as touching the road at a grazing angle, even
## though it geometrically isn't — this is pure perspective headroom, not a
## bug fix for an actual clipping bug (there wasn't one).
const NEAR_ROAD_CLEARANCE := 3.0   # how far below the road surface terrain sits right next to it
## Texture is forced to dirt out to this distance regardless of slope/height, so
## grass never starts painting immediately at the curb — gives a visible dirt
## shoulder that reads clearly as "not the road" instead of grass appearing to
## hug (and, at a distance/angle, seem to overlap) the road edge. Road curb ends
## at x=6.4 local; this reaches a couple meters past that.
const SHOULDER_RADIUS := 9.0
const HILL_BONUS := 2.5            # how far above local track elevation a hillside crest rises
const NOISE_HEIGHT := 2.0          # amplitude of the base rolling terrain noise

## Curve3D.get_closest_offset() only finds the single nearest point *by arc
## length*, which breaks down anywhere the track curves back near itself in world
## space — chicanes, by definition, do exactly that. Fixed by precomputing this
## many samples across the *entire* curve once and scoring every one of them
## independently in _height_at rather than picking a single "closest" reference.
const CURVE_SAMPLE_COUNT := 900

const SLOPE_ROCK_THRESHOLD := 0.35 # 1 - normal.y beyond this counts as "steep"
const HIGH_ROCK_THRESHOLD := 6.0   # elevation beyond this also counts as rocky hillside

@export var track_path: NodePath = NodePath("../Track")

var _track: Node3D
var _noise := FastNoiseLite.new()


func _ready() -> void:
	_track = get_node_or_null(track_path)
	_noise.seed = 2024
	_noise.frequency = 0.02
	vertex_spacing = SAMPLE_STEP
	# Terrain3D defaults to DYNAMIC_GAME collision: physics collision only gets
	# built in a window around whichever single camera set_camera() was given
	# (race.gd tracks cam1/Kart1). In split-screen the other kart can be well
	# outside that window — e.g. on the opposite side of a long track loop — and
	# would fall straight through open floor with nothing physically wrong with
	# the heightmap itself. FULL_GAME builds real collision for the whole
	# (bounded, finite) terrain once at start instead, which comfortably covers
	# a course this size.
	collision.set_mode(Terrain3DCollision.FULL_GAME)
	_setup_textures()
	_prepare_regions()
	var curve: Curve3D = null
	if _track:
		var path_node = _track.get("path")
		if path_node:
			curve = path_node.curve
	var curve_samples := _build_curve_samples(curve)
	_generate_heightmap(curve_samples)
	data.calc_height_range(true)
	_paint_textures(curve_samples)
	# calc_height_range() only recalculates the terrain's overall height bounds —
	# it does NOT refresh the actual render mesh/texture arrays. Without this
	# call the visual terrain stays flat and untextured no matter what was
	# written above, even though Terrain3DData.get_height/get_normal correctly
	# report the real values (confirmed via headless readback) — the write
	# succeeded, it just never got flushed to what's actually drawn.
	data.update_maps()


func _build_curve_samples(curve: Curve3D) -> PackedVector3Array:
	var samples := PackedVector3Array()
	if curve == null:
		return samples
	var length := curve.get_baked_length()
	for i in range(CURVE_SAMPLE_COUNT):
		samples.append(curve.sample_baked(length * float(i) / float(CURVE_SAMPLE_COUNT)))
	return samples


func _setup_textures() -> void:
	var grass := Terrain3DTextureAsset.new()
	grass.id = 0
	grass.name = "Grass"
	grass.albedo_color = Color(0.85, 0.95, 0.8) # slight tint, texture carries most of the color
	grass.albedo_texture = load("res://assets/textures/grass_albedo.jpg")
	grass.uv_scale = 40.0

	var dirt := Terrain3DTextureAsset.new()
	dirt.id = 1
	dirt.name = "Dirt"
	dirt.albedo_color = Color(0.9, 0.85, 0.75)
	dirt.albedo_texture = load("res://assets/textures/rock_albedo.jpg")
	dirt.uv_scale = 30.0

	var terrain_assets := Terrain3DAssets.new()
	terrain_assets.set_texture_list([grass, dirt])
	assets = terrain_assets


## add_region_blank only creates the ONE region containing a given position; a
## terrain that straddles region boundaries (ours does — track spans both sides of
## x=0/z=0) needs every touched region created up front before any height/texture
## data is written.
func _prepare_regions() -> void:
	var half := TERRAIN_SIZE * 0.5
	var world_size: float = float(region_size) * vertex_spacing
	var min_idx := int(floor(-half / world_size))
	var max_idx := int(floor(half / world_size))
	for rx in range(min_idx, max_idx + 1):
		for rz in range(min_idx, max_idx + 1):
			data.add_region_blank(Vector2i(rx, rz), false)


func _generate_heightmap(curve_samples: PackedVector3Array) -> void:
	var half := TERRAIN_SIZE * 0.5
	var wz := -half
	while wz < half:
		var wx := -half
		while wx < half:
			data.set_height(Vector3(wx, 0.0, wz), _height_at(wx, wz, curve_samples))
			wx += SAMPLE_STEP
		wz += SAMPLE_STEP


## The ground literally follows the track's shape: every curve sample within reach
## independently proposes a height (low right beside its own road elevation, rising
## to a small hillside crest, fading to open noise further out), and the terrain
## takes the SAFEST (lowest) of every proposal, not just whichever sample happens
## to be nearest.
##
## This replaces an earlier version that picked one "closest" sample and used it
## for both the falloff distance AND the elevation reference — those two things
## went out of sync anywhere the track curves back near itself (the forest chicane
## especially), letting terrain rise above a *different* nearby stretch of road
## than the one that was actually closest. Scoring every sample independently and
## keeping the minimum can't have that failure mode: for a point actually on the
## road, the correct local sample is also the closest one and dominates the
## minimum, and no other, more distant sample can ever push the result *up* — only
## down, which is always safe.
func _height_at(wx: float, wz: float, curve_samples: PackedVector3Array) -> float:
	var base: float = _noise.get_noise_2d(wx, wz) * NOISE_HEIGHT
	if curve_samples.is_empty():
		return base

	var result := base
	for p in curve_samples:
		var d := Vector2(wx - p.x, wz - p.z).length()
		if d >= HILL_RADIUS:
			continue

		var near_height := p.y - NEAR_ROAD_CLEARANCE
		var peak_height := p.y + HILL_BONUS
		var contribution: float
		if d < NEAR_ROAD_RADIUS:
			contribution = near_height
		elif d < PEAK_RADIUS:
			var t := (d - NEAR_ROAD_RADIUS) / (PEAK_RADIUS - NEAR_ROAD_RADIUS)
			contribution = lerp(near_height, peak_height, smoothstep(0.0, 1.0, t))
		else:
			var t := (d - PEAK_RADIUS) / (HILL_RADIUS - PEAK_RADIUS)
			contribution = lerp(peak_height, base, smoothstep(0.0, 1.0, t))

		result = min(result, contribution)

	return result


func _within_shoulder(wx: float, wz: float, curve_samples: PackedVector3Array) -> bool:
	for p in curve_samples:
		if Vector2(wx - p.x, wz - p.z).length() < SHOULDER_RADIUS:
			return true
	return false


func _paint_textures(curve_samples: PackedVector3Array) -> void:
	var half := TERRAIN_SIZE * 0.5
	var wz := -half
	while wz < half:
		var wx := -half
		while wx < half:
			var pos := Vector3(wx, 0.0, wz)
			var rocky: bool
			if _within_shoulder(wx, wz, curve_samples):
				rocky = true
			else:
				var normal: Vector3 = data.get_normal(pos)
				var slope := 1.0 - normal.y
				var h := data.get_height(pos)
				rocky = slope > SLOPE_ROCK_THRESHOLD or h > HIGH_ROCK_THRESHOLD
			data.set_control_base_id(pos, 1 if rocky else 0)
			wx += TEXTURE_PAINT_STEP
		wz += TEXTURE_PAINT_STEP
