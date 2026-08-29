extends Terrain3D
## Procedurally generates the bumper arena's ground: gentle rolling bumps
## everywhere for texture and feel, a handful of large fixed mounds scattered
## through the middle distance to drive up and launch off of, and a dirt "apron"
## ring near the boundary wall for texture variety. No track curve to follow here
## (unlike terrain_builder.gd) — hills are simple symmetric mounds rather than
## one-way ramps, since there's no fixed direction of travel in a free-roam arena.
## Same script-generated philosophy as terrain_builder.gd/track_builder.gd.
##
## Builds BEFORE arena_builder.gd's wall/crate/spawn placement — Terrain is listed
## before Rink among World's children in arena.tscn, and Godot fires sibling
## _ready() calls in that order, so arena_builder.gd can safely query this node's
## finished heightmap. Same dependency pattern race.tscn relies on between Track
## and Terrain, just with the roles reversed (there, terrain reads the track's
## curve; here, the rink reads the terrain's heights).
##
## VERIFICATION NOTE: same headless-collision caveat as terrain_builder.gd —
## heights/textures are confirmed correct via Terrain3DData.get_height/get_normal
## readback, but Terrain3D's actual runtime collision can't be confirmed without a
## real windowed run. The y < -10 respawn safety net in kart_controller.gd still
## catches a kart that falls through either way.

const ARENA_SIZE := 480.0   # world-space width/height of the generated area (meters)
const SAMPLE_STEP := 3.0
const TEXTURE_PAINT_STEP := 5.0

const BUMP_HEIGHT := 0.7    # amplitude of the base rolling noise, everywhere
const BUMP_FREQUENCY := 0.03

## Fixed mound centers — symmetric hills (drive up and launch off any side, no
## "correct" direction like a track ramp) scattered through the middle of the
## rink, well clear of the wall (arena_builder.gd's ARENA_RADIUS = 225) and of
## the two spawn points on the +/-X axis.
const HILLS := [
	{"pos": Vector2(70, 90), "radius": 38.0, "height": 9.0},
	{"pos": Vector2(-90, -60), "radius": 42.0, "height": 10.0},
	{"pos": Vector2(60, -100), "radius": 34.0, "height": 8.0},
	{"pos": Vector2(-60, 110), "radius": 30.0, "height": 7.0},
]

## Beyond this distance from center, terrain paints as dirt instead of the usual
## grass/rock rule — reads as a stadium apron ringing the wall.
const APRON_INNER_RADIUS := 190.0

const SLOPE_ROCK_THRESHOLD := 0.4
const HIGH_ROCK_THRESHOLD := 5.0

var _noise := FastNoiseLite.new()


func _ready() -> void:
	_noise.seed = 4141
	_noise.frequency = BUMP_FREQUENCY
	vertex_spacing = SAMPLE_STEP
	# Terrain3D defaults to DYNAMIC_GAME collision: physics collision only gets
	# built in a window around whichever single camera set_camera() was given
	# (arena.gd tracks cam1/Kart1). At this arena's size the other kart can spawn
	# ~300m away — well outside that window — and falls straight through open
	# floor with nothing actually wrong with the heightmap. FULL_GAME builds
	# real collision for the whole (bounded, finite) arena once at start
	# instead, which comfortably covers a space this size.
	collision.set_mode(Terrain3DCollision.FULL_GAME)
	_setup_textures()
	_prepare_regions()
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
	grass.albedo_color = Color(0.85, 0.95, 0.8)
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
	dirt.albedo_color = Color(0.88, 0.8, 0.65)
	dirt.albedo_texture = load("res://assets/textures/road_albedo.jpg")
	dirt.uv_scale = 25.0

	var terrain_assets := Terrain3DAssets.new()
	terrain_assets.set_texture_list([grass, rock, dirt])
	assets = terrain_assets


## See terrain_builder.gd's identical function for why regions are pre-created
## explicitly rather than relying on import/write calls to create them on demand.
func _prepare_regions() -> void:
	var half := ARENA_SIZE * 0.5
	var world_size: float = float(region_size) * vertex_spacing
	var min_idx := int(floor(-half / world_size))
	var max_idx := int(floor(half / world_size))
	for rx in range(min_idx, max_idx + 1):
		for rz in range(min_idx, max_idx + 1):
			data.add_region_blank(Vector2i(rx, rz), false)


func _generate_heightmap() -> void:
	var half := ARENA_SIZE * 0.5
	var wz := -half
	while wz < half:
		var wx := -half
		while wx < half:
			data.set_height(Vector3(wx, 0.0, wz), _height_at(wx, wz))
			wx += SAMPLE_STEP
		wz += SAMPLE_STEP


## Base rolling noise everywhere, with each hill's mound taking over (never
## reducing height, only ever raising it) within its own radius — hills can't
## dip the surrounding ground, so overlapping mounds always combine cleanly.
func _height_at(wx: float, wz: float) -> float:
	var h: float = _noise.get_noise_2d(wx, wz) * BUMP_HEIGHT
	for hill in HILLS:
		var center: Vector2 = hill["pos"]
		var d := Vector2(wx, wz).distance_to(center)
		if d >= hill["radius"]:
			continue
		var t: float = 1.0 - (d / hill["radius"])
		var mound: float = hill["height"] * smoothstep(0.0, 1.0, t)
		h = max(h, mound)
	return h


func _paint_textures() -> void:
	var half := ARENA_SIZE * 0.5
	var wz := -half
	while wz < half:
		var wx := -half
		while wx < half:
			var pos := Vector3(wx, 0.0, wz)
			var id: int
			if Vector2(wx, wz).length() > APRON_INNER_RADIUS:
				id = 2 # dirt apron near the wall
			else:
				var normal: Vector3 = data.get_normal(pos)
				var slope := 1.0 - normal.y
				var h := data.get_height(pos)
				id = 1 if (slope > SLOPE_ROCK_THRESHOLD or h > HIGH_ROCK_THRESHOLD) else 0
			data.set_control_base_id(pos, id)
			wx += TEXTURE_PAINT_STEP
		wz += TEXTURE_PAINT_STEP
