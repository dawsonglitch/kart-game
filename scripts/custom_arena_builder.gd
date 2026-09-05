class_name CustomArenaBuilder
extends Node3D
## Builds a player-made *bumper arena* from a TrackDesign, the way
## arena_builder.gd builds the built-in rink from its own constants.
##
## Much less happens here than in arena_builder.gd, and that's the point: the
## built-in rink's butte, spurs, crater, grove and kickers are a designed map,
## while this one is whatever the player put in it. What it guarantees is the
## part a player can't draw — a floor that's flat enough to drive on, a wall all
## the way round so nobody drives off the edge of the world, and spawn points
## spread evenly round the rim so the field doesn't start on top of itself.
##
## Public API matches arena_builder.gd's, so arena.gd and the AI drivers can't
## tell which rink they were handed.

const WALL_SEGMENT_COUNT := 64
const WALL_HEIGHT := 9.0
const WALL_THICKNESS := 1.5
## Segments are chords of a circle, so consecutive ones only touch at their
## corners; overlapping them slightly closes the gaps a kart could otherwise
## clip through.
const WALL_SEGMENT_OVERLAP := 1.15
## Sunk into the ground by this much, so the uphill corner of a segment on a
## slope doesn't leave a gap under it.
const WALL_SINK := 1.0

## How far out from the middle each kart spawns, as a fraction of the radius.
const START_RADIUS_FRACTION := 0.66

var design: TrackDesign

var _ground: TrackGround


func _ready() -> void:
	design = _resolve_design()
	var canyons: Array = CustomFeatures.water_canyons(design)
	_ground = TrackGround.create(
		null_ribbon(), [], canyons, TrackDesign.ARENA_GROUND_NOISE
	)

	_build_wall()
	TrackProps.build_water(self, canyons)
	CustomFeatures.build(self, design, _ground, null)


## An arena has no road, and TrackGround wants a ribbon to read stations off.
## An empty one is the honest answer: no stations means the road contributes
## nothing to the height field, which is exactly right here.
func null_ribbon() -> RoadRibbon:
	return RoadRibbon.new()


func _resolve_design() -> TrackDesign:
	var chosen: TrackDesign = GameSettings.custom_design
	if chosen != null and chosen.kind == TrackDesign.Kind.ARENA:
		return chosen
	push_warning("Custom arena: no usable arena design selected; falling back to the rink template")
	return TrackDesign.from_template("rink")


## Same red-and-white ring the built-in rink has, seated on this design's own
## ground rather than a fixed height.
func _build_wall() -> void:
	var mat_a := ToonMaterial.create(Color(0.9, 0.15, 0.15))
	var mat_b := ToonMaterial.create(Color(0.95, 0.95, 0.95))

	var wall := Node3D.new()
	wall.name = "Wall"
	add_child(wall)

	var radius: float = design.arena_radius
	var slice_angle := TAU / float(WALL_SEGMENT_COUNT)
	var chord_len := 2.0 * radius * sin(slice_angle * 0.5) * WALL_SEGMENT_OVERLAP

	var seg_mesh := BoxMesh.new()
	seg_mesh.size = Vector3(chord_len, WALL_HEIGHT, WALL_THICKNESS)
	var seg_shape := BoxShape3D.new()
	seg_shape.size = seg_mesh.size

	for i in range(WALL_SEGMENT_COUNT):
		var angle := slice_angle * i
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		var pos := Vector3(x, _ground.height_at(x, z) + WALL_HEIGHT * 0.5 - WALL_SINK, z)

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


# ---------------------------------------------------------------------------
# Public API — matches arena_builder.gd
# ---------------------------------------------------------------------------

func get_ground() -> TrackGround:
	return _ground


## `turns` is a fraction of a full circle round the rim: kart k of a field of N
## spawns at k/N, so everyone is evenly spread and nobody lands on anybody.
## Karts face the middle, which is where the game is.
func get_start_transform(turns: float) -> Transform3D:
	var angle: float = TAU * turns
	var radius: float = design.arena_radius * START_RADIUS_FRACTION
	var x := cos(angle) * radius
	var z := sin(angle) * radius
	var origin := Vector3(x, _ground.height_at(x, z) + 1.0, z)
	# A kart's own forward is -Z, so looking at the centre means -Z pointing
	# inward, i.e. +Z pointing out along the radius.
	var out := Vector3(x, 0.0, z).normalized()
	if out.length() < 0.5:
		out = Vector3.BACK
	var right := Vector3.UP.cross(out).normalized()
	return Transform3D(Basis(right, Vector3.UP, out), origin)


func get_arena_center() -> Vector3:
	return Vector3.ZERO


func get_arena_radius() -> float:
	return design.arena_radius


## The built-in rink's butte has ramps the AI needs to know about. A custom arena
## has no butte, so there is nothing to climb — ai_driver.gd treats an empty list
## as "just drive on the flat".
func get_climb_points() -> PackedVector3Array:
	return PackedVector3Array()


## Likewise: no central obstacle to steer around. ai_driver.gd skips its
## avoidance entirely on a zero radius.
func get_plateau() -> Dictionary:
	return {"center": Vector3.ZERO, "radius": 0.0}
