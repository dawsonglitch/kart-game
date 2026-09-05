extends Terrain3D
## Stamps a player-made course's ground into a Terrain3D heightmap, for both
## custom races and custom arenas.
##
## terrain_builder.gd and arena_terrain_builder.gd each own the *shape* of their
## own world. This one owns no shape at all — it reads the finished TrackGround
## off whichever builder sits beside it (custom_track_builder.gd or
## custom_arena_builder.gd, both of which expose get_ground()) and samples it.
## That's the same split terrain_builder.gd already uses for the racetrack, and
## it's what stops the ground the karts drive on from drifting apart from the
## ground the trees are standing on.
##
## The one thing it decides for itself is how big to be: a player's oval might be
## 200 m across or 700, and generating a fixed 620 m heightmap for either is
## either wasteful or short. TrackDesign.extent() answers that.
##
## VERIFICATION NOTE: the same headless caveat as terrain_builder.gd applies —
## heights and texture IDs read back correctly in a headless run, but Terrain3D's
## runtime *collision* cannot be confirmed without a real windowed session. The
## y < -10 respawn net in kart_controller.gd catches a kart that falls through
## either way.

const SAMPLE_STEP := 2.5        # metres between height samples (== vertex_spacing)
const TEXTURE_PAINT_STEP := 5.0
## Texture is forced to dirt within this distance of the road edge, giving a
## visible shoulder rather than grass appearing to hug the kerb.
const SHOULDER_WIDTH := 3.5
const SLOPE_ROCK_THRESHOLD := 0.35
const HIGH_ROCK_THRESHOLD := 7.0

## Which sibling to read the ground off. custom_race.tscn points this at Track,
## custom_arena.tscn at Rink.
@export var source_path: NodePath = NodePath("../Track")

var _ground: TrackGround
var _half_size: float = 200.0


func _ready() -> void:
	vertex_spacing = SAMPLE_STEP
	# FULL_GAME rather than the DYNAMIC_GAME default: collision would otherwise
	# only be built around the one camera set_camera() was given, and in
	# split-screen the other kart can be well outside that window. Same reasoning
	# as terrain_builder.gd, which has the longer note.
	collision.set_mode(Terrain3DCollision.FULL_GAME)

	var source := get_node_or_null(source_path)
	if source and source.has_method("get_ground"):
		_ground = source.get_ground()
	var design: TrackDesign = source.design if source and "design" in source else null
	if design:
		_half_size = design.extent()

	_setup_textures(design)
	_prepare_regions()

	if _ground == null:
		# Nothing to follow — a flat empty world beats a crash.
		data.update_maps()
		return

	_generate_heightmap()
	data.calc_height_range(true)
	_paint_textures()
	# calc_height_range() only refreshes the height *bounds*; without
	# update_maps() the drawn terrain stays flat and untextured no matter what
	# was written. See terrain_builder.gd for the full note.
	data.update_maps()


## Same three textures the built-in worlds use, tinted by the design's palette so
## "change the colors of everything" reaches the ground as well as the props.
func _setup_textures(design: TrackDesign) -> void:
	var ground_tint: Color = design.color_of("ground") if design else TrackDesign.COLOR_DEFAULTS["ground"]
	var rock_tint: Color = design.color_of("rock") if design else TrackDesign.COLOR_DEFAULTS["rock"]

	var grass := Terrain3DTextureAsset.new()
	grass.id = 0
	grass.name = "Grass"
	grass.albedo_color = ground_tint
	grass.albedo_texture = load("res://assets/textures/grass_albedo.jpg")
	grass.uv_scale = 40.0

	var rock := Terrain3DTextureAsset.new()
	rock.id = 1
	rock.name = "Rock"
	# Lifted towards white: the tint multiplies the texture, and a rock color
	# picked to look right on a boulder comes out nearly black spread over a
	# cliff face.
	rock.albedo_color = rock_tint.lerp(Color.WHITE, 0.45)
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


## add_region_blank only creates the one region containing a given position, so
## every region the world touches has to be created before anything is written
## into it — a course straddling x=0/z=0 always spans four of them.
func _prepare_regions() -> void:
	var world_size: float = float(region_size) * vertex_spacing
	var min_idx := int(floor(-_half_size / world_size))
	var max_idx := int(floor(_half_size / world_size))
	for rx in range(min_idx, max_idx + 1):
		for rz in range(min_idx, max_idx + 1):
			data.add_region_blank(Vector2i(rx, rz), false)


func _generate_heightmap() -> void:
	var wz := -_half_size
	while wz < _half_size:
		var wx := -_half_size
		while wx < _half_size:
			data.set_height(Vector3(wx, 0.0, wz), _ground.height_at(wx, wz))
			wx += SAMPLE_STEP
		wz += SAMPLE_STEP


func _paint_textures() -> void:
	var wz := -_half_size
	while wz < _half_size:
		var wx := -_half_size
		while wx < _half_size:
			var pos := Vector3(wx, 0.0, wz)
			var id: int
			if _ground.distance_to_road_edge(wx, wz) < SHOULDER_WIDTH:
				id = 2 # dirt shoulder hugging the kerb
			else:
				var normal: Vector3 = data.get_normal(pos)
				var slope := 1.0 - normal.y
				var h := data.get_height(pos)
				id = 1 if (slope > SLOPE_ROCK_THRESHOLD or h > HIGH_ROCK_THRESHOLD) else 0
			data.set_control_base_id(pos, id)
			wx += TEXTURE_PAINT_STEP
		wz += TEXTURE_PAINT_STEP
