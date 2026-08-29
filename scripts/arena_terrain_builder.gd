extends Terrain3D
## Procedurally generates the bumper arena's ground. Unlike the racetrack there is
## no curve to follow and no correct direction of travel, so every feature here is
## symmetric — whatever you drive at, you can drive at from any side.
##
## The shape, in the order it is applied:
##   1. rolling bumps everywhere, for feel,
##   2. a banked skirt sweeping up into the boundary wall, so the edge of the rink
##      is a velodrome you can ride round rather than a thing you scrape along,
##   3. THE BUTTE — a flat-topped plateau in the middle whose sides are far too
##      steep to climb, reachable only up four long ramp spurs. It is the one
##      place on the map worth holding, which is what turns an open rink into
##      somewhere with a shape,
##   4. scattered mounds to launch off, and four launch kickers with jump pads on
##      their crests,
##   5. a crater bowl carved back out of all of it.
##
## Same script-generated philosophy as terrain_builder.gd / track_builder.gd.
##
## Builds BEFORE arena_builder.gd's wall/crate/spawn placement — Terrain is listed
## before Rink among World's children in arena.tscn, and Godot fires sibling
## _ready() calls in that order, so arena_builder.gd can safely query this node's
## finished heightmap and seat every prop on the real ground.
##
## VERIFICATION NOTE: same headless-collision caveat as terrain_builder.gd —
## heights/textures are confirmed correct via Terrain3DData.get_height/get_normal
## readback, but Terrain3D's actual runtime collision can't be confirmed without a
## real windowed run. The y < -10 respawn safety net in kart_controller.gd still
## catches a kart that falls through either way.

const ARENA_SIZE := 560.0   # world-space width/height of the generated area (metres)
const SAMPLE_STEP := 2.5
const TEXTURE_PAINT_STEP := 5.0

const BUMP_HEIGHT := 0.7    # amplitude of the base rolling noise, everywhere
const BUMP_FREQUENCY := 0.03

## Kept in step with arena_builder.gd's ARENA_RADIUS — the wall is seated on
## whatever height this file puts under it, so the two have to agree on where the
## rink ends.
const ARENA_RADIUS := 225.0

## The banked skirt: ground climbs from flat to SKIRT_HEIGHT between these radii
## and then stays there, so the wall (and the grandstands past it) sit on a raised
## rim rather than in a ditch.
const SKIRT_INNER_RADIUS := 198.0
const SKIRT_HEIGHT := 10.0

## The butte. MESA_FLAT is the fraction of the radius held at full height; the
## remainder is the wall. It has to be steeper than it looks on paper to actually
## stop anyone: the heightmap is only sampled every SAMPLE_STEP metres, and both
## the render mesh and the collision mesh are built from those samples, so a wall
## thinner than a couple of grid cells gets rounded off into something climbable.
## Measured on the finished terrain, 13 m of rise over 4.5 m reads as ~60 degrees,
## comfortably past kart_controller.gd's 50-degree floor_max_angle.
const MESA_RADIUS := 56.0
const MESA_HEIGHT := 13.0
const MESA_FLAT := 0.92

## Four ramps up onto the butte, on the diagonals so they miss the two default
## spawn points on the +/-X axis. Each runs from SPUR_OUTER_RADIUS at ground level
## in to the edge of the crown at full height — about 14 degrees, gentle enough to
## take at speed.
const SPUR_COUNT := 4
const SPUR_START_TURNS := 0.125 # 45 degrees, i.e. between the axes
const SPUR_OUTER_RADIUS := 92.0
const SPUR_HALF_WIDTH := 12.0
const SPUR_FLAT_FRACTION := 0.6 # inner part of the width held flat, the rest is a shoulder

## Launch kickers: a gentle ramp up to a crest and a shorter, steeper drop off the
## back, sculpted into the ground rather than built as a slab. They started life
## as tilted boxes and a bot spent half a test match jammed against the side of
## one — a 16 m slab standing 4.5 m proud is a wall from three of its four sides,
## and the AI's reverse-and-turn recovery just drove it back in again. Terrain has
## no walls: every approach is a slope you either climb or slide off.
## `turns` and `radius` place the CREST; the run-up trails back along the tangent
## (the way you'd be going if you were circling the rink) and the drop continues
## past it.
const KICKERS := [
	{"turns": 0.0625, "radius": 105.0},
	{"turns": 0.3125, "radius": 105.0},
	{"turns": 0.5625, "radius": 105.0},
	{"turns": 0.8125, "radius": 105.0},
]
const KICKER_RUN_UP := 24.0     # 5 m of rise over this is about 12 degrees
const KICKER_DROP := 11.0       # and about 24 degrees off the back
const KICKER_HEIGHT := 5.0
## Wide, and mostly shoulder. The flat middle is 5.8 m either side of the axis and
## the shoulder takes another 8.7 m to reach ground level — 5 m of drop over 8.7 m
## is about 30 degrees, which is a slope you slide off. Anything narrower turns the
## sides back into the walls this shape exists to avoid; note the steepest line on
## the whole shape is the diagonal across the back corner, where the drop and the
## shoulder combine, so both have to stay well inside kart_controller.gd's
## 50-degree floor_max_angle on their own.
const KICKER_HALF_WIDTH := 14.5
const KICKER_FLAT_FRACTION := 0.4

## Symmetric mounds — drive up and launch off any side. Kept clear of the butte,
## its ramps, the kickers, the crater and the wall: everything here combines with
## max(), so a mound overlapping a kicker doesn't break anything, it just swallows
## it — one of these sat on a kicker's run-up and left its crest four metres BELOW
## where the approach started.
const MOUNDS := [
	{"pos": Vector2(95, 105), "radius": 38.0, "height": 9.0},
	{"pos": Vector2(-128, -88), "radius": 42.0, "height": 10.0},
	{"pos": Vector2(78, -140), "radius": 34.0, "height": 8.0},
	{"pos": Vector2(-40, 152), "radius": 30.0, "height": 7.0},
]

## Carved back out afterwards. `flat` is the fraction of the radius held at floor
## level before the wall climbs back out — a bowl you can drop into and ride
## around rather than a pothole.
const CRATERS := [
	{"pos": Vector2(-124, 82), "radius": 42.0, "flat": 0.5, "depth": -8.0},
]

const SLOPE_ROCK_THRESHOLD := 0.4
const HIGH_ROCK_THRESHOLD := 6.0

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
			data.set_height(Vector3(wx, 0.0, wz), height_at(wx, wz))
			wx += SAMPLE_STEP
		wz += SAMPLE_STEP


## Public so arena_builder.gd can ask about ground it hasn't stamped yet if it
## ever needs to; ordinarily it reads the finished heightmap instead.
func height_at(wx: float, wz: float) -> float:
	var radius: float = Vector2(wx, wz).length()
	var h: float = _noise.get_noise_2d(wx, wz) * BUMP_HEIGHT

	# The banked rim, added to the base so the bumps ride up it too.
	if radius > SKIRT_INNER_RADIUS:
		var t: float = clamp((radius - SKIRT_INNER_RADIUS) / (ARENA_RADIUS - SKIRT_INNER_RADIUS), 0.0, 1.0)
		h += SKIRT_HEIGHT * smoothstep(0.0, 1.0, t)

	# The butte: flat crown, then a wall too steep to climb.
	if radius < MESA_RADIUS:
		var t := 1.0
		if radius > MESA_RADIUS * MESA_FLAT:
			t = smoothstep(
				0.0, 1.0,
				1.0 - (radius - MESA_RADIUS * MESA_FLAT) / (MESA_RADIUS * (1.0 - MESA_FLAT))
			)
		h = max(h, MESA_HEIGHT * t)

	h = max(h, _spur_height(wx, wz))
	h = max(h, _kicker_height(wx, wz))

	for mound in MOUNDS:
		var center: Vector2 = mound["pos"]
		var d: float = Vector2(wx, wz).distance_to(center)
		if d >= mound["radius"]:
			continue
		var t: float = 1.0 - (d / float(mound["radius"]))
		h = max(h, float(mound["height"]) * smoothstep(0.0, 1.0, t))

	for crater in CRATERS:
		var center: Vector2 = crater["pos"]
		var d: float = Vector2(wx, wz).distance_to(center)
		var crater_radius: float = crater["radius"]
		if d >= crater_radius:
			continue
		var flat: float = crater["flat"]
		var t := 0.0
		if d > crater_radius * flat:
			t = smoothstep(0.0, 1.0, (d - crater_radius * flat) / (crater_radius * (1.0 - flat)))
		h = min(h, lerp(float(crater["depth"]), h, t))

	return h


## The four access ramps, as raised causeways running in to the edge of the
## crown. Held flat across the middle of their width with a shoulder either side,
## so they read as ramps rather than as ridges.
func _spur_height(wx: float, wz: float) -> float:
	var inner_radius: float = MESA_RADIUS * MESA_FLAT
	var best := 0.0
	var point := Vector2(wx, wz)
	for k in range(SPUR_COUNT):
		var angle: float = TAU * (SPUR_START_TURNS + float(k) / float(SPUR_COUNT))
		var dir := Vector2(cos(angle), sin(angle))
		var outer: Vector2 = dir * SPUR_OUTER_RADIUS
		var inner: Vector2 = dir * inner_radius
		var axis: Vector2 = inner - outer
		var t: float = clamp((point - outer).dot(axis) / axis.length_squared(), 0.0, 1.0)
		var d: float = point.distance_to(outer + axis * t)
		if d >= SPUR_HALF_WIDTH:
			continue
		var across := 1.0
		if d > SPUR_HALF_WIDTH * SPUR_FLAT_FRACTION:
			across = smoothstep(
				0.0, 1.0,
				1.0 - (d - SPUR_HALF_WIDTH * SPUR_FLAT_FRACTION)
					/ (SPUR_HALF_WIDTH * (1.0 - SPUR_FLAT_FRACTION))
			)
		best = max(best, MESA_HEIGHT * t * across)
	return best


## Where the crest of kicker `index` is, and which way it points — arena_builder.gd
## puts a jump pad on it, and needs both.
func kicker_crest(index: int) -> Dictionary:
	var kicker: Dictionary = KICKERS[index]
	var angle: float = float(kicker["turns"]) * TAU
	var radius: float = kicker["radius"]
	var crest := Vector2(cos(angle) * radius, sin(angle) * radius)
	# Tangential: the direction you travel going round the rink.
	var direction := Vector2(sin(angle), -cos(angle))
	return {"crest": crest, "direction": direction}


## Same plateau-and-shoulder lateral profile as the butte's ramps, with a long
## climb to the crest and a short drop off the back.
func _kicker_height(wx: float, wz: float) -> float:
	var point := Vector2(wx, wz)
	var best := 0.0
	for index in range(KICKERS.size()):
		var shape: Dictionary = kicker_crest(index)
		var crest: Vector2 = shape["crest"]
		var direction: Vector2 = shape["direction"]
		var foot: Vector2 = crest - direction * KICKER_RUN_UP
		var along: float = (point - foot).dot(direction)
		if along < 0.0 or along > KICKER_RUN_UP + KICKER_DROP:
			continue
		var across: float = absf((point - foot).cross(direction))
		if across >= KICKER_HALF_WIDTH:
			continue
		var profile: float
		if along <= KICKER_RUN_UP:
			profile = along / KICKER_RUN_UP
		else:
			profile = 1.0 - (along - KICKER_RUN_UP) / KICKER_DROP
		var shoulder := 1.0
		if across > KICKER_HALF_WIDTH * KICKER_FLAT_FRACTION:
			shoulder = smoothstep(
				0.0, 1.0,
				1.0 - (across - KICKER_HALF_WIDTH * KICKER_FLAT_FRACTION)
					/ (KICKER_HALF_WIDTH * (1.0 - KICKER_FLAT_FRACTION))
			)
		best = max(best, KICKER_HEIGHT * profile * shoulder)
	return best


func _paint_textures() -> void:
	var half := ARENA_SIZE * 0.5
	var wz := -half
	while wz < half:
		var wx := -half
		while wx < half:
			var pos := Vector3(wx, 0.0, wz)
			var id: int
			if Vector2(wx, wz).length() > SKIRT_INNER_RADIUS:
				id = 2 # dirt banking sweeping up to the wall
			else:
				var normal: Vector3 = data.get_normal(pos)
				var slope := 1.0 - normal.y
				var h := data.get_height(pos)
				id = 1 if (slope > SLOPE_ROCK_THRESHOLD or h > HIGH_ROCK_THRESHOLD) else 0
			data.set_control_base_id(pos, id)
			wx += TEXTURE_PAINT_STEP
		wz += TEXTURE_PAINT_STEP
