class_name RoadRibbon
extends RefCounted
## Generates the racetrack's road surface as a real mesh instead of extruding a
## fixed cross-section with CSGPolygon3D, which is what the track used to do.
##
## WHY NOT CSG: the old CSGPolygon3D ran with path_rotation = PATH (1), which
## pins the road's up vector to world +Y — no banking, and a constant width for
## the whole lap. The obvious upgrade, path_rotation = PATH_FOLLOW (2) plus
## Curve3D point tilts, does not work on this track: measured headlessly, the
## curve's rotation-minimising frame already twists up to ~30 degrees around the
## two ramp kinks with *every tilt set to zero*, so the road would corkscrew at
## exactly the two places a kart is airborne. Building the ribbon here means the
## frame is ours: yaw comes from the horizontal tangent (never twists), and bank
## is an explicit, smoothed function of curvature that we can force flat wherever
## we want.
##
## What that buys the map: banked corners, and a width that varies along the lap
## — wide sweepers you can take three-abreast, a pinched chicane, and a genuinely
## narrow viaduct over the canyon.
##
## Everything downstream reads the sampled stations back out of here rather than
## re-deriving them: track_builder.gd seats pads/hazards/props on the *banked*
## surface, and terrain_builder.gd tests its clearance against the real road
## edges instead of assuming a fixed half-width.

## Cross-section: a flat drivable strip with a sloped APRON either side and a
## skirt hanging below the apron's outer edge so nothing sees daylight under the
## road.
##
## The apron replaces the raised kerb the old CSG polygon extruded, and it is not
## cosmetic. A CharacterBody3D cannot climb a vertical step of ANY height —
## move_and_slide has no step-up — so a kerb standing proud of the ground beside
## it makes leaving the road a one-way trip. Measured in an AI race: a bot ran wide
## at the tight forest corner, dropped off the inside edge, and spent the remaining
## two minutes of the session driving up and down beside a road it could not get
## back onto. A ramp has no step, so the same excursion now costs a couple of
## seconds. track_ground.gd deliberately puts the ground part-way UP this ramp for
## the same reason.
const APRON_WIDTH := 1.6
const APRON_DROP := 1.0
const SURFACE_HEIGHT := 0.05
const SKIRT_DEPTH := 1.5

## Metres between sampled stations along the curve. Also the road mesh's
## longitudinal quad size and the resolution of the collision trimesh.
const STATION_SPACING := 2.0

## Bank angle per unit of curvature, in metres: a corner of radius R banks by
## roughly BANK_PER_CURVATURE / R radians. 13.0 puts a 60 m-radius corner at
## ~12 degrees and a lazy 130 m sweeper at ~6.
const BANK_PER_CURVATURE := 13.0
const BANK_MAX := deg_to_rad(12.0)
## Half-length of the stencil used to measure heading change, in stations. Wider
## than one station so a single noisy sample can't spike the bank.
const CURVATURE_STENCIL := 3
## Box-filter passes over the bank/width curves, each ±SMOOTH_RADIUS stations, so
## both ease in and out over tens of metres rather than stepping.
const SMOOTH_PASSES := 4
const SMOOTH_RADIUS := 3

## Texture tiling: one repeat every this many metres along the road. Across the
## road the UV is just the distance along the cross-section, matching the
## fine-grained tiling the CSG version had.
const UV_METRES_PER_TILE := 8.3

# --- Sampled stations, in curve order, closing back on themselves. -----------
var offsets := PackedFloat32Array()
var centers := PackedVector3Array()   # centreline, on the curve itself
var forwards := PackedVector3Array()  # unit, horizontal
var rights := PackedVector3Array()    # unit, banked
var ups := PackedVector3Array()       # unit, banked
var half_widths := PackedFloat32Array()
var banks := PackedFloat32Array()

var mesh: ArrayMesh
var shape: ConcavePolygonShape3D
var length: float = 0.0


## `width_profile` is an Array of [offset_metres, half_width] pairs in increasing
## offset order; half-width is interpolated smoothly between them and wraps around
## the lap. `flat_ranges` is an Array of [from_offset, to_offset] spans forced to
## zero bank — the ramps, where a banked lip would look wrong and land wrong.
static func build(
	curve: Curve3D, width_profile: Array, flat_ranges: Array
) -> RoadRibbon:
	var ribbon := RoadRibbon.new()
	ribbon.length = curve.get_baked_length()
	if ribbon.length <= 0.0:
		return ribbon
	ribbon._sample_stations(curve)
	ribbon._compute_widths(width_profile)
	ribbon._compute_banks(flat_ranges)
	ribbon._build_geometry()
	return ribbon


func station_count() -> int:
	return centers.size()


## The road's frame at an arbitrary offset: origin on the *driving surface* at the
## centreline, basis.x pointing right along the banked camber, basis.y the banked
## up, basis.z pointing backwards (Godot's -Z-is-forward convention), so this can
## be assigned straight to a prop's global_transform.
func frame_at(offset: float) -> Transform3D:
	var count := station_count()
	if count == 0:
		return Transform3D()
	var pos: float = fposmod(offset, length) / STATION_SPACING
	var i: int = int(floor(pos)) % count
	var j: int = (i + 1) % count
	var t: float = pos - floor(pos)

	var forward: Vector3 = forwards[i].lerp(forwards[j], t).normalized()
	var up: Vector3 = ups[i].lerp(ups[j], t).normalized()
	# Godot's basis is right-handed with x cross y = z (= backwards), so the right
	# vector is forward cross up, not up cross forward. Getting this backwards
	# mirrors every lateral offset and inverts the camber.
	var right: Vector3 = forward.cross(up).normalized()
	# Re-orthogonalise: lerping two unit frames leaves them very slightly skewed.
	up = right.cross(forward).normalized()
	var origin: Vector3 = centers[i].lerp(centers[j], t) + up * SURFACE_HEIGHT
	return Transform3D(Basis(right, up, -forward), origin)


## A point on the driving surface, `lateral` metres right of the centreline —
## follows the camber, so a prop at the edge of a banked corner sits on the road
## rather than hovering over it or sinking into it.
func surface_point(offset: float, lateral: float) -> Vector3:
	var t := frame_at(offset)
	return t.origin + t.basis.x * lateral


func half_width_at(offset: float) -> float:
	var count := half_widths.size()
	if count == 0:
		return 0.0
	var pos: float = fposmod(offset, length) / STATION_SPACING
	var i: int = int(floor(pos)) % count
	var j: int = (i + 1) % count
	return lerp(half_widths[i], half_widths[j], pos - floor(pos))


# ---------------------------------------------------------------------------
# Sampling and profiles
# ---------------------------------------------------------------------------

func _sample_stations(curve: Curve3D) -> void:
	# One station every STATION_SPACING, with the spacing stretched slightly so a
	# whole number of them closes the loop exactly — otherwise the last quad
	# straddles a seam of a different length than every other one.
	var count := int(round(length / STATION_SPACING))
	var spacing := length / float(count)
	for i in range(count):
		var offset := spacing * float(i)
		offsets.append(offset)
		centers.append(curve.sample_baked(offset))
	for i in range(count):
		var ahead: Vector3 = centers[(i + 1) % count]
		var behind: Vector3 = centers[(i - 1 + count) % count]
		var forward := ahead - behind
		# Yaw only. Keeping the road's forward horizontal is what stops the frame
		# from rolling through the ramps (see the class comment); the mesh still
		# climbs, because consecutive station *origins* carry the elevation.
		forward.y = 0.0
		if forward.length() < 0.001:
			forward = Vector3.FORWARD
		forwards.append(forward.normalized())


func _compute_widths(width_profile: Array) -> void:
	var count := station_count()
	var raw := PackedFloat32Array()
	raw.resize(count)
	for i in range(count):
		raw[i] = _profile_lookup(width_profile, offsets[i])
	half_widths = _smooth(raw)


## Smoothstep interpolation between the nearest profile entries either side of
## `offset`, wrapping around the lap so the finish straight and the start
## straight agree on a width.
func _profile_lookup(profile: Array, offset: float) -> float:
	if profile.is_empty():
		return 6.0
	if profile.size() == 1:
		return profile[0][1]
	var last := profile.size() - 1
	for k in range(profile.size()):
		var a: Array = profile[k]
		var b: Array = profile[(k + 1) % profile.size()]
		var from: float = a[0]
		var to: float = b[0]
		var span: float = to - from
		if k == last:
			span = length - from + b[0] # the wrap-around segment
		if span <= 0.0:
			continue
		var d: float = fposmod(offset - from, length)
		if d <= span:
			return lerp(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, d / span))
	return float(profile[0][1])


func _compute_banks(flat_ranges: Array) -> void:
	var count := station_count()
	var raw := PackedFloat32Array()
	raw.resize(count)
	for i in range(count):
		# Signed heading change measured across a stencil wider than one station,
		# divided by the arc length it spans — i.e. curvature in radians/metre.
		var a: Vector3 = forwards[(i - CURVATURE_STENCIL + count) % count]
		var b: Vector3 = forwards[(i + CURVATURE_STENCIL) % count]
		var turn: float = Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))
		var arc: float = 2.0 * CURVATURE_STENCIL * STATION_SPACING
		# Positive `turn` in the (x, z) plane is a right-hander, and a right-hander
		# wants its right-hand edge dropped — which is what a positive bank angle
		# does once it is applied as a rotation about the forward axis below.
		raw[i] = clamp(turn / arc * BANK_PER_CURVATURE, -BANK_MAX, BANK_MAX)

	for span in flat_ranges:
		for i in range(count):
			if _offset_in_span(offsets[i], span[0], span[1]):
				raw[i] = 0.0

	banks = _smooth(raw)
	for i in range(count):
		# Roll the flat frame about its own forward axis. Godot's right-hand rule
		# about `forward` tips the right-hand side down for a positive angle,
		# which is the outside-up camber a right-hander wants.
		var up: Vector3 = Vector3.UP.rotated(forwards[i], banks[i])
		ups.append(up)
		rights.append(forwards[i].cross(up).normalized())


func _offset_in_span(offset: float, from: float, to: float) -> bool:
	return fposmod(offset - from, length) <= fposmod(to - from, length)


## Circular box filter, repeated. Used on both the bank and the width curves so
## neither steps abruptly at a control point.
func _smooth(values: PackedFloat32Array) -> PackedFloat32Array:
	var count := values.size()
	if count == 0:
		return values
	var current := values
	for _pass in range(SMOOTH_PASSES):
		var next := PackedFloat32Array()
		next.resize(count)
		for i in range(count):
			var sum := 0.0
			for k in range(-SMOOTH_RADIUS, SMOOTH_RADIUS + 1):
				sum += current[(i + k + count * 2) % count]
			next[i] = sum / float(SMOOTH_RADIUS * 2 + 1)
		current = next
	return current


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

## The cross-section at one station, as (lateral, vertical) pairs in the station's
## own banked frame. Vertical is measured from the centreline point on the curve.
func _profile(i: int) -> Array:
	var w: float = half_widths[i]
	var o: float = w + APRON_WIDTH
	return [
		Vector2(-o, -SKIRT_DEPTH),
		Vector2(-o, -APRON_DROP),
		Vector2(-w, SURFACE_HEIGHT),
		Vector2(w, SURFACE_HEIGHT),
		Vector2(o, -APRON_DROP),
		Vector2(o, -SKIRT_DEPTH),
	]


## Points in the cross-section, and which of its edges is the drivable surface
## (profile point 2 to point 3). That one strip gets smoothed normals so a banked
## corner reads as a curve; every other edge is an apron, a skirt or the underside
## and stays flat-shaded, which keeps the road's edge a crisp line under the cel
## shader.
const PROFILE_POINTS := 6
const SURFACE_EDGE := 2


func _build_geometry() -> void:
	var count := station_count()
	if count < 3:
		return

	var world := []   # per station: Array[Vector3], one per profile point
	var u_coords := []  # per station: Array[float], distance along the cross-section
	for i in range(count):
		var profile := _profile(i)
		var pts: Array[Vector3] = []
		var us: Array[float] = []
		var run := 0.0
		for k in range(profile.size()):
			var p: Vector2 = profile[k]
			pts.append(centers[i] + rights[i] * p.x + ups[i] * p.y)
			if k > 0:
				run += (profile[k] - profile[k - 1]).length()
			us.append(run)
		# Repeat the first point at the end so the loop below can close the
		# cross-section with an underside, making the ribbon a solid rather than
		# an open shell.
		pts.append(pts[0])
		us.append(run + (profile[0] - profile[profile.size() - 1]).length())
		world.append(pts)
		u_coords.append(us)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(count):
		var j := (i + 1) % count
		var v0: float = offsets[i] / UV_METRES_PER_TILE
		# The closing quad wraps past the end of the lap; using offsets[0] there
		# would run the texture backwards over the finish line.
		var v1: float = (length if j == 0 else offsets[j]) / UV_METRES_PER_TILE
		for edge in range(PROFILE_POINTS):
			var a: Vector3 = world[i][edge]
			var b: Vector3 = world[i][edge + 1]
			var c: Vector3 = world[j][edge + 1]
			var d: Vector3 = world[j][edge]
			var flat_normal: Vector3 = (b - a).cross(d - a)
			if flat_normal.length() < 0.000001:
				continue
			flat_normal = flat_normal.normalized()
			var na := flat_normal
			var nb := flat_normal
			var nc := flat_normal
			var nd := flat_normal
			if edge == SURFACE_EDGE:
				na = ups[i]
				nb = ups[i]
				nc = ups[j]
				nd = ups[j]
			var ua: float = u_coords[i][edge]
			var ub: float = u_coords[i][edge + 1]
			var uc: float = u_coords[j][edge + 1]
			var ud: float = u_coords[j][edge]
			_quad(st,
				a, b, c, d,
				na, nb, nc, nd,
				Vector2(ua, v0), Vector2(ub, v0), Vector2(uc, v1), Vector2(ud, v1))

	st.generate_tangents()
	mesh = st.commit()
	# Trimesh straight off the finished surface, so the collider is exactly the
	# geometry that was drawn — banking, curbs, varying width and all.
	shape = mesh.create_trimesh_shape()


## Emits a-c-b and a-d-c, NOT a-b-c and a-c-d. Godot winds triangles CLOCKWISE:
## a face's front side is the one from which (c - a) cross (b - a) points at you,
## the opposite of the usual counter-clockwise convention (verified against
## BoxMesh's own arrays). Winding these the intuitive way builds the whole road
## inside out — invisible under the shader's cull_back, and, because Jolt culls
## back faces on a one-sided trimesh too, with collision only from underneath.
func _quad(
	st: SurfaceTool,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
	ta: Vector2, tb: Vector2, tc: Vector2, td: Vector2
) -> void:
	_vertex(st, a, na, ta)
	_vertex(st, c, nc, tc)
	_vertex(st, b, nb, tb)
	_vertex(st, a, na, ta)
	_vertex(st, d, nd, td)
	_vertex(st, c, nc, tc)


func _vertex(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)
