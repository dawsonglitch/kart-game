class_name TrackGround
extends RefCounted
## The racetrack world's height field, in one place.
##
## This used to live entirely inside terrain_builder.gd, which meant it was only
## available *after* the Terrain3D node had built itself — and Terrain3D builds
## after the track (race.tscn orders Track before Terrain so the terrain can read
## the racing line). track_builder.gd therefore had no way to ask how high the
## ground was under a prop, and simply seated its scenery at road height.
##
## Pulling the function out here lets both sides share it: track_builder.gd
## builds one of these from its own layout and uses it to seat trees, barriers,
## grandstands and canyon pylons on the real ground, then hands the same object
## to terrain_builder.gd to stamp into the actual heightmap. One definition, no
## chance of the props and the ground disagreeing.
##
## The shape, in order:
##   1. rolling noise everywhere, plus any standalone mesas/ridges (which only
##      ever raise it),
##   2. the road's own influence — the ground is pulled DOWN to sit clear below
##      every nearby stretch of road, rising to a hillside crest a little further
##      out and fading back to open ground beyond that,
##   3. canyons carved through everything.
## Steps 2 and 3 can only ever lower the result, never raise it, which is what
## guarantees no hill and no mesa can ever poke up through the road.

const NOISE_HEIGHT := 2.0
const NOISE_FREQUENCY := 0.02
const NOISE_SEED := 2024

## Road influence, all measured outward from the *edge* of the road rather than
## its centre — the road's half-width varies along the lap now, so a fixed radius
## from the centreline would sit too close on the wide sweepers and needlessly far
## out on the narrow viaduct.
const NEAR_MARGIN := 3.0    # ground stays clearly below the road out to here
const PEAK_MARGIN := 10.0   # hillside crest sits around here
const HILL_MARGIN := 20.0   # beyond this, open ground; the road has no influence
## How far below the road's own EDGE the ground beside it sits — measured from the
## edge, not the centreline, so a banked corner (whose low edge drops over a metre)
## gets the same shoulder as a flat straight rather than a hole.
##
## Small on purpose, and smaller than the road's apron is deep (RoadRibbon's
## APRON_DROP), which puts the ground part-way UP that ramp rather than at the
## bottom of a step. That is what makes running wide survivable: a CharacterBody3D
## cannot climb a vertical step of any height, so a shoulder even ten centimetres
## below the tarmac would be a one-way trip. See the note on RoadRibbon.APRON_WIDTH
## for the race this was measured in.
##
## It only ever LOWERS the ground, so it does not fill in the valleys the ramps
## and the viaduct fly over — where the natural ground is already further below the
## road, it stays there. What it guarantees is that nothing can rise INTO the road.
const CLEARANCE := 0.6
const HILL_BONUS := 2.5     # how far above local road level a hillside crest rises

## Uniform bucket grid over XZ used to answer "which road stations are near this
## point" without scanning all ~430 of them. The heightmap is ~23k samples and the
## texture pass another ~9k, so the brute-force version was several million
## distance tests per load.
const BUCKET_SIZE := 32.0

var stations := PackedVector3Array()      # road centreline points
var station_half_widths := PackedFloat32Array()
## How far the road's lower edge hangs below its centreline at each station,
## i.e. half-width times the sine of the bank angle.
var station_edge_drops := PackedFloat32Array()
## [center: Vector2, radius, height] — standalone hills, only ever raising ground.
var mesas: Array = []
## [from: Vector2, to: Vector2, radius, floor_y] — carved through everything.
var canyons: Array = []

var _noise := FastNoiseLite.new()
var _buckets: Dictionary = {}
var _max_reach: float = 0.0


static func create(ribbon: RoadRibbon, mesas_in: Array, canyons_in: Array) -> TrackGround:
	var ground := TrackGround.new()
	ground._noise.seed = NOISE_SEED
	ground._noise.frequency = NOISE_FREQUENCY
	ground.mesas = mesas_in
	ground.canyons = canyons_in
	for i in range(ribbon.station_count()):
		ground.stations.append(ribbon.centers[i])
		ground.station_half_widths.append(ribbon.half_widths[i])
		ground.station_edge_drops.append(
			absf(sin(ribbon.banks[i])) * (ribbon.half_widths[i] + RoadRibbon.APRON_WIDTH)
		)
	ground._build_buckets()
	return ground


func _build_buckets() -> void:
	for i in range(stations.size()):
		var reach: float = station_half_widths[i] + HILL_MARGIN
		_max_reach = max(_max_reach, reach)
		var p: Vector3 = stations[i]
		# Register each station in every bucket its influence can touch, so a
		# lookup only ever has to read the one bucket the query point falls in.
		var min_x := int(floor((p.x - reach) / BUCKET_SIZE))
		var max_x := int(floor((p.x + reach) / BUCKET_SIZE))
		var min_z := int(floor((p.z - reach) / BUCKET_SIZE))
		var max_z := int(floor((p.z + reach) / BUCKET_SIZE))
		for bx in range(min_x, max_x + 1):
			for bz in range(min_z, max_z + 1):
				var key := Vector2i(bx, bz)
				# Plain Array here, not PackedInt32Array: packed arrays are VALUE
				# types, so `_buckets[key].append(i)` would append to a throwaway
				# copy and leave every bucket empty — which silently removes the
				# road's influence from the ground entirely.
				if not _buckets.has(key):
					_buckets[key] = []
				(_buckets[key] as Array).append(i)
	# Pack them once they're final; lookups happen tens of thousands of times.
	for key in _buckets:
		_buckets[key] = PackedInt32Array(_buckets[key])


func _nearby(x: float, z: float) -> PackedInt32Array:
	return _buckets.get(
		Vector2i(int(floor(x / BUCKET_SIZE)), int(floor(z / BUCKET_SIZE))),
		PackedInt32Array()
	)


func height_at(x: float, z: float) -> float:
	var result: float = _noise.get_noise_2d(x, z) * NOISE_HEIGHT
	for mesa in mesas:
		var center: Vector2 = mesa["pos"]
		var d: float = Vector2(x, z).distance_to(center)
		var radius: float = mesa["radius"]
		if d >= radius:
			continue
		# Flat top out to `flat` of the radius, then a smooth skirt down to zero,
		# so these read as mesas with a driveable crown rather than sharp cones.
		var flat: float = mesa.get("flat", 0.0)
		var t: float = 1.0
		if d > radius * flat:
			t = smoothstep(0.0, 1.0, 1.0 - (d - radius * flat) / (radius * (1.0 - flat)))
		result = max(result, mesa["height"] * t)

	var base := result
	for i in _nearby(x, z):
		var p: Vector3 = stations[i]
		var d: float = Vector2(x - p.x, z - p.z).length()
		var hw: float = station_half_widths[i]
		var hill_r: float = hw + HILL_MARGIN
		if d >= hill_r:
			continue
		var near_r: float = hw + NEAR_MARGIN
		var peak_r: float = hw + PEAK_MARGIN
		var near_h: float = p.y - station_edge_drops[i] - CLEARANCE
		var peak_h: float = p.y + HILL_BONUS
		var contribution: float
		if d < near_r:
			contribution = near_h
		elif d < peak_r:
			contribution = lerp(near_h, peak_h, smoothstep(0.0, 1.0, (d - near_r) / (peak_r - near_r)))
		else:
			contribution = lerp(peak_h, base, smoothstep(0.0, 1.0, (d - peak_r) / (hill_r - peak_r)))
		result = min(result, contribution)

	for canyon in canyons:
		var d: float = _distance_to_segment(Vector2(x, z), canyon["from"], canyon["to"])
		var radius: float = canyon["radius"]
		if d >= radius:
			continue
		# Flat floor out to `flat` of the radius and a steep wall beyond it,
		# rather than one smooth bowl from rim to axis. A bowl of this depth
		# reads as a valley; a gorge needs walls, and the viaduct needs a real
		# floor under it to plant its pylons on.
		var flat: float = canyon.get("flat", 0.5)
		var t: float = 0.0
		if d > radius * flat:
			t = smoothstep(0.0, 1.0, (d - radius * flat) / (radius * (1.0 - flat)))
		result = min(result, lerp(float(canyon["floor"]), result, t))

	return result


## Distance from the nearest road *edge* — negative-ish values aren't produced,
## it clamps at zero on the road itself. Used for painting the dirt shoulder and
## for keeping scenery off the tarmac.
func distance_to_road_edge(x: float, z: float) -> float:
	var best := INF
	for i in _nearby(x, z):
		var p: Vector3 = stations[i]
		var d: float = Vector2(x - p.x, z - p.z).length() - station_half_widths[i]
		best = min(best, d)
	if best == INF:
		# Outside every bucket means further than HILL_MARGIN from any road.
		return _max_reach
	return max(best, 0.0)


func in_canyon(x: float, z: float) -> bool:
	for canyon in canyons:
		if _distance_to_segment(Vector2(x, z), canyon["from"], canyon["to"]) < canyon["radius"]:
			return true
	return false


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clamp((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
