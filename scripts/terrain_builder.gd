extends Terrain3D
## Stamps the racetrack world's ground into an actual Terrain3D heightmap, and
## paints it with grass / rock / dirt.
##
## The *shape* itself is not decided here any more — it lives in TrackGround
## (scripts/track_ground.gd), which track_builder.gd builds first and seats all
## of its own props on. This script just samples that same height field, so the
## ground the karts drive on and the ground the trees, grandstands, barriers and
## canyon pylons are standing on cannot drift apart. See track_ground.gd for what
## the shape actually is (rolling noise, standalone mesas, the road's own
## hillside cut, and carved canyons).
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

## World-space width/height of the generated area, in metres. Big enough to hold
## the ~280 x 290 m lap plus the ring of skyline hills in TrackGround's mesa list,
## which sit out around 200 m from the origin — without the extra reach they'd be
## sliced off at the world edge and read as cliffs into nothing.
const TERRAIN_SIZE := 620.0
const SAMPLE_STEP := 2.5       # metres between height samples (== vertex_spacing)
const TEXTURE_PAINT_STEP := 5.0

## Texture is forced to dirt within this distance of the road *edge*, so grass
## never starts painting immediately at the kerb — it gives a visible dirt
## shoulder that reads clearly as "not the road" instead of grass appearing to
## hug (and, at a distance and a low angle, seem to overlap) the road edge.
const SHOULDER_WIDTH := 3.5

const SLOPE_ROCK_THRESHOLD := 0.35 # 1 - normal.y beyond this counts as "steep"
const HIGH_ROCK_THRESHOLD := 7.0   # elevation beyond this also counts as rocky hillside

@export var track_path: NodePath = NodePath("../Track")

var _ground: TrackGround


func _ready() -> void:
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

	# race.tscn lists Track before Terrain among World's children and Godot fires
	# sibling _ready() calls in that order, so the track has already built its
	# road and its height field by the time we get here.
	var track := get_node_or_null(track_path)
	if track and track.has_method("get_ground"):
		_ground = track.get_ground()
	if _ground == null:
		# Nothing to follow — leave a flat, empty world rather than crashing.
		data.update_maps()
		return

	_generate_heightmap()
	data.calc_height_range(true)
	_paint_textures()
	# calc_height_range() only recalculates the terrain's overall height bounds —
	# it does NOT refresh the actual render mesh/texture arrays. Without this
	# call the visual terrain stays flat and untextured no matter what was
	# written above, even though Terrain3DData.get_height/get_normal correctly
	# report the real values (confirmed via headless readback) — the write
	# succeeded, it just never got flushed to what's actually drawn.
	data.update_maps()


func _setup_textures() -> void:
	var grass := Terrain3DTextureAsset.new()
	grass.id = 0
	grass.name = "Grass"
	grass.albedo_color = Color(0.85, 0.95, 0.8) # slight tint, texture carries most of the color
	grass.albedo_texture = load("res://assets/textures/grass_albedo.jpg")
	grass.uv_scale = 40.0

	var rock := Terrain3DTextureAsset.new()
	rock.id = 1
	rock.name = "Rock"
	rock.albedo_color = Color(0.9, 0.85, 0.75)
	rock.albedo_texture = load("res://assets/textures/rock_albedo.jpg")
	rock.uv_scale = 30.0

	var dirt := Terrain3DTextureAsset.new()
	dirt.id = 2
	dirt.name = "Dirt"
	dirt.albedo_color = Color(0.88, 0.8, 0.66)
	dirt.albedo_texture = load("res://assets/textures/road_albedo.jpg")
	dirt.uv_scale = 25.0

	var terrain_assets := Terrain3DAssets.new()
	terrain_assets.set_texture_list([grass, rock, dirt])
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


func _generate_heightmap() -> void:
	var half := TERRAIN_SIZE * 0.5
	var wz := -half
	while wz < half:
		var wx := -half
		while wx < half:
			data.set_height(Vector3(wx, 0.0, wz), _ground.height_at(wx, wz))
			wx += SAMPLE_STEP
		wz += SAMPLE_STEP


func _paint_textures() -> void:
	var half := TERRAIN_SIZE * 0.5
	var wz := -half
	while wz < half:
		var wx := -half
		while wx < half:
			var pos := Vector3(wx, 0.0, wz)
			var id: int
			if _ground.distance_to_road_edge(wx, wz) < SHOULDER_WIDTH:
				id = 2 # dirt shoulder hugging the kerb
			else:
				var normal: Vector3 = data.get_normal(pos)
				var slope := 1.0 - normal.y
				var h := data.get_height(pos)
				# Canyon walls and the tops of the skyline hills go to bare rock;
				# everything gentle and low stays grass.
				id = 1 if (slope > SLOPE_ROCK_THRESHOLD or h > HIGH_ROCK_THRESHOLD) else 0
			data.set_control_base_id(pos, id)
			wx += TEXTURE_PAINT_STEP
		wz += TEXTURE_PAINT_STEP
