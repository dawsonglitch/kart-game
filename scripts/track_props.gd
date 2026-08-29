class_name TrackProps
extends RefCounted
## The racetrack's built structures — the things that give each stretch of the lap
## its own look and its own problem to solve. Kept out of track_builder.gd so that
## file stays a readable description of the *layout* (where everything goes)
## rather than a wall of mesh construction.
##
## Every builder here takes the road ribbon and the ground height field, so
## nothing has to guess where the road surface or the terrain is: railings hug the
## banked road edge, pylons reach exactly down to the canyon floor, and the
## grandstands sit on the hillside instead of hovering over it.
##
## Anything a kart can hit is a StaticBody3D with a real collision shape.
## Anything it can't reach (arch tops, crowd, pylons under the bridge, scenery)
## is mesh-only — collision it can never touch is pure cost.

const CROWD_COLORS := [
	Color(0.9, 0.2, 0.2), Color(0.2, 0.4, 0.9), Color(0.95, 0.85, 0.2), Color(0.2, 0.75, 0.35),
	Color(0.9, 0.5, 0.15), Color(0.6, 0.25, 0.75), Color(0.95, 0.95, 0.95), Color(0.25, 0.25, 0.3),
]


# ---------------------------------------------------------------------------
# The viaduct — the narrow span over the canyon.
# ---------------------------------------------------------------------------

## Solid railings both sides, a deck beam under the road, and pylons dropping to
## the canyon floor. The railings are the reason this is fun rather than cruel:
## the drop either side is real and reads as real, but a kid who clips the edge
## bounces off a wall instead of falling twenty metres.
static func build_viaduct(
	parent: Node3D, ribbon: RoadRibbon, ground: TrackGround,
	from_offset: float, to_offset: float
) -> void:
	var root := Node3D.new()
	root.name = "Viaduct"
	parent.add_child(root)

	var span: float = to_offset - from_offset
	var rail_mat := ToonMaterial.create(Color(0.88, 0.88, 0.9))
	var post_mat := ToonMaterial.create(Color(0.55, 0.57, 0.62))
	var deck_mat := ToonMaterial.create(Color(0.62, 0.6, 0.58))

	var rail_step := 4.0
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.3, 0.85, rail_step * 1.08) # overlap so seams don't gap
	var rail_shape := BoxShape3D.new()
	rail_shape.size = rail_mesh.size
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.45, 1.5, 0.45)

	var o := from_offset
	while o < to_offset:
		var frame := ribbon.frame_at(o + rail_step * 0.5)
		var hw := ribbon.half_width_at(o + rail_step * 0.5)
		for side: float in [-1.0, 1.0]:
			var body := StaticBody3D.new()
			body.transform = frame.translated_local(
				Vector3(side * (hw + RoadRibbon.APRON_WIDTH * 0.5), 0.85, 0.0)
			)
			root.add_child(body)
			var mi := MeshInstance3D.new()
			mi.mesh = rail_mesh
			mi.material_override = rail_mat
			body.add_child(mi)
			var cs := CollisionShape3D.new()
			cs.shape = rail_shape
			body.add_child(cs)

			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.material_override = post_mat
			root.add_child(post)
			post.transform = frame.translated_local(
				Vector3(side * (hw + RoadRibbon.APRON_WIDTH * 0.5), 0.3, -rail_step * 0.5)
			)
		o += rail_step

	# Deck: a slab under the road so the span reads as a structure from below and
	# from the approach, rather than a floating ribbon of tarmac.
	var deck_step := 6.0
	o = from_offset
	while o < to_offset:
		var frame := ribbon.frame_at(o + deck_step * 0.5)
		var hw := ribbon.half_width_at(o + deck_step * 0.5)
		var deck := MeshInstance3D.new()
		var deck_mesh := BoxMesh.new()
		deck_mesh.size = Vector3((hw + 1.4) * 2.0, 1.2, deck_step * 1.05)
		deck.mesh = deck_mesh
		deck.material_override = deck_mat
		root.add_child(deck)
		deck.transform = frame.translated_local(Vector3(0.0, -0.9, 0.0))
		o += deck_step

	# Pylons every so often, each reaching the actual canyon floor beneath it.
	var pylon_step: float = span / 5.0
	var pylon_mat := ToonMaterial.create(Color(0.58, 0.56, 0.53))
	o = from_offset + pylon_step * 0.5
	while o < to_offset:
		var frame := ribbon.frame_at(o)
		var floor_y: float = ground.height_at(frame.origin.x, frame.origin.z)
		var height: float = frame.origin.y - 1.4 - floor_y
		if height > 2.0:
			for side: float in [-1.0, 1.0]:
				var leg := MeshInstance3D.new()
				var leg_mesh := BoxMesh.new()
				leg_mesh.size = Vector3(1.8, height, 1.8)
				leg.mesh = leg_mesh
				leg.material_override = pylon_mat
				root.add_child(leg)
				leg.position = Vector3(
					frame.origin.x + frame.basis.x.x * side * 3.0,
					floor_y + height * 0.5,
					frame.origin.z + frame.basis.x.z * side * 3.0
				)
		o += pylon_step


# ---------------------------------------------------------------------------
# The arch gallery — a run of stone ribs straddling the road.
# ---------------------------------------------------------------------------

## Deliberately open ribs rather than a closed tube: it gives the flicker of
## driving through a covered section without putting the players in the dark, and
## it costs one MultiMesh. Springs from outside the curb, so nothing on the road
## can touch it and it needs no collision.
static func build_arch_gallery(
	parent: Node3D, ribbon: RoadRibbon,
	from_offset: float, to_offset: float, rib_spacing: float = 4.0
) -> void:
	var blocks_per_rib := 11
	var transforms: Array[Transform3D] = []
	var o := from_offset
	while o <= to_offset:
		var frame := ribbon.frame_at(o)
		var radius: float = ribbon.half_width_at(o) + 1.7
		for k in range(blocks_per_rib):
			# Half circle from one springing point over to the other.
			var angle: float = PI * float(k) / float(blocks_per_rib - 1)
			var lateral: float = cos(angle) * radius
			var height: float = sin(angle) * radius
			# Each block is rotated to lie along the arch, so the ring reads as
			# voussoirs rather than a scatter of loose bricks.
			var basis := frame.basis.rotated(frame.basis.z, angle - PI * 0.5)
			transforms.append(Transform3D(basis, frame.origin + frame.basis.x * lateral + frame.basis.y * height))
		o += rib_spacing

	var block := BoxMesh.new()
	block.size = Vector3(1.15, 1.0, 1.5)
	_multimesh(parent, "ArchGallery", transforms, block, Color(0.6, 0.58, 0.55))


# ---------------------------------------------------------------------------
# Grandstands along the start/finish straight.
# ---------------------------------------------------------------------------

static func build_grandstands(
	parent: Node3D, ribbon: RoadRibbon, ground: TrackGround,
	from_offset: float, to_offset: float
) -> void:
	var root := Node3D.new()
	root.name = "Grandstands"
	parent.add_child(root)

	var tiers := 4
	var tier_depth := 3.2
	var tier_rise := 2.1
	var gap := 11.0
	var colors := [Color(0.86, 0.22, 0.22), Color(0.95, 0.95, 0.95), Color(0.22, 0.42, 0.86), Color(0.95, 0.8, 0.18)]

	var seats: Array[Transform3D] = []
	var seat_colors: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150

	var step := 6.0
	var o := from_offset
	while o < to_offset:
		var frame := ribbon.frame_at(o + step * 0.5)
		var hw := ribbon.half_width_at(o + step * 0.5)
		for side: float in [-1.0, 1.0]:
			for tier in range(tiers):
				var lateral: float = side * (hw + gap + tier * tier_depth)
				var pos := Vector3(
					frame.origin.x + frame.basis.x.x * lateral,
					0.0,
					frame.origin.z + frame.basis.x.z * lateral
				)
				var base_y: float = ground.height_at(pos.x, pos.z)
				var height: float = tier_rise * float(tier + 1)
				var box := MeshInstance3D.new()
				var box_mesh := BoxMesh.new()
				box_mesh.size = Vector3(tier_depth, height, step * 1.02)
				box.mesh = box_mesh
				box.material_override = ToonMaterial.create(colors[tier % colors.size()])
				root.add_child(box)
				# Yaw only — a stand leaning with the road's camber looks broken.
				# The box is `tier_depth` across its local X and `step` along its
				# local Z, and this yaw puts local Z along the road, so the tiers
				# step outwards across it and consecutive boxes butt up end to end.
				var forward: Vector3 = -frame.basis.z
				var yaw: float = atan2(-forward.x, -forward.z)
				box.transform = Transform3D(
					Basis(Vector3.UP, yaw), Vector3(pos.x, base_y + height * 0.5, pos.z)
				)
				for _seat in range(3):
					if rng.randf() > 0.6:
						continue
					var jitter: float = rng.randf_range(-step * 0.4, step * 0.4)
					var seat_pos := Vector3(
						pos.x - frame.basis.z.x * jitter,
						base_y + height + 0.75,
						pos.z - frame.basis.z.z * jitter
					)
					seats.append(Transform3D(Basis(Vector3.UP, yaw), seat_pos))
					seat_colors.append(CROWD_COLORS[rng.randi_range(0, CROWD_COLORS.size() - 1)])
		o += step

	var figure := CapsuleMesh.new()
	figure.radius = 0.28
	figure.height = 1.5
	_multimesh(parent, "Crowd", seats, figure, Color.WHITE, seat_colors)


# ---------------------------------------------------------------------------
# Barriers — striped boards framing the outside of the quickest corners.
# ---------------------------------------------------------------------------

## MESH ONLY, no collision, and that is the whole design. A solid wall running
## parallel to the road is a trap for anything that ends up on the wrong side of
## it: a bot (or a kid) out on the shoulder steers back towards the racing line,
## hits the wall, reverses, and drives into it again. The road already keeps you
## honest by being banked and by having a shoulder that costs you time, so these
## are here to make the corner readable, not to catch anyone. The one place solid
## railings ARE right is the viaduct, where the alternative is a twenty-metre
## drop and there is nothing on the far side to get stuck against.
##
## `side` is which edge to line: -1 left, +1 right, or 0 to pick the outside of
## the corner automatically from the road's own camber (the raised edge of a
## banked corner is by definition its outside).
static func build_barrier(
	parent: Node3D, ribbon: RoadRibbon,
	from_offset: float, to_offset: float, side: float = 0.0, lateral_gap: float = 2.2
) -> void:
	var root := Node3D.new()
	root.name = "Barrier"
	parent.add_child(root)

	var step := 3.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.25, 1.0, step * 1.1)
	var mats := [ToonMaterial.create(Color(0.9, 0.2, 0.2)), ToonMaterial.create(Color(0.96, 0.96, 0.96))]

	var index := 0
	var o := from_offset
	while o < to_offset:
		var mid: float = o + step * 0.5
		var frame := ribbon.frame_at(mid)
		var pick: float = side
		if pick == 0.0:
			var bank: float = asin(clamp(frame.basis.x.y, -1.0, 1.0))
			# basis.x.y > 0 means the right edge is the raised, outside one.
			pick = 1.0 if bank > 0.0 else -1.0
		var lateral: float = pick * (ribbon.half_width_at(mid) + RoadRibbon.APRON_WIDTH + lateral_gap)
		var board := MeshInstance3D.new()
		board.mesh = mesh
		board.material_override = mats[index % 2]
		root.add_child(board)
		board.transform = frame.translated_local(Vector3(lateral, 0.5, 0.0))
		index += 1
		o += step


# ---------------------------------------------------------------------------
# Lane splits — a painted divider down the middle of a wide stretch.
# ---------------------------------------------------------------------------

## Marks a stretch where the two lanes are worth different things: a boost pad
## one side, item boxes the other. Commit early — you can't see which is which
## until you're most of the way there.
##
## PAINT, NOT A KERB. This was a solid kerbed island to begin with, and in a
## two-minute AI test one bot drove square into its nose and stayed there for the
## rest of the race: bots steer at the racing line plus a small lane offset, and
## the smaller offsets put a kart squarely on top of a centre divider. A kid who
## picks the middle at speed gets the same treatment. The reward asymmetry either
## side is what makes the choice interesting; the divider only ever needed to
## announce it, so it is now flush with the road and nothing can wedge on it.
static func build_lane_split(
	parent: Node3D, ribbon: RoadRibbon, offset: float, split_length: float = 20.0
) -> void:
	var root := Node3D.new()
	root.name = "LaneSplit"
	parent.add_child(root)

	var pale := ToonMaterial.create(Color(0.95, 0.95, 0.92))
	var red := ToonMaterial.create(Color(0.85, 0.2, 0.2))
	var step := 2.0
	var half := split_length * 0.5
	var index := 0
	var o := -half
	while o < half:
		var frame := ribbon.frame_at(offset + o + step * 0.5)
		# Tapered towards both ends, so it reads as an arrowhead pointing the way
		# you are going rather than a rectangle lying in the road.
		var taper: float = 1.0 - pow(absf(o + step * 0.5) / half, 2.0)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(max(2.6 * taper, 0.2), 0.04, step * 1.02)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = pale if index % 2 == 0 else red
		root.add_child(mi)
		mi.transform = frame.translated_local(Vector3(0.0, 0.03, 0.0))
		index += 1
		o += step


# ---------------------------------------------------------------------------
# Roadside marker posts — cheap, and they do most of the work of making a corner
# readable at speed before you can see round it.
# ---------------------------------------------------------------------------

static func build_markers(parent: Node3D, ribbon: RoadRibbon, ground: TrackGround, spacing: float = 14.0) -> void:
	var posts: Array[Transform3D] = []
	var colors: Array[Color] = []
	var o := 0.0
	var index := 0
	while o < ribbon.length:
		var frame := ribbon.frame_at(o)
		for side: float in [-1.0, 1.0]:
			var lateral: float = side * (ribbon.half_width_at(o) + RoadRibbon.APRON_WIDTH + 3.4)
			var pos := Vector3(
				frame.origin.x + frame.basis.x.x * lateral,
				0.0,
				frame.origin.z + frame.basis.x.z * lateral
			)
			# Seat on whichever is higher, the shoulder or the road's own level —
			# a post half-buried in the hillside reads worse than one standing a
			# little proud of it.
			var base_y: float = max(ground.height_at(pos.x, pos.z), frame.origin.y - 2.0)
			posts.append(Transform3D(Basis.IDENTITY, Vector3(pos.x, base_y + 0.55, pos.z)))
			colors.append(Color(0.95, 0.95, 0.95) if index % 3 != 0 else Color(0.9, 0.25, 0.2))
		index += 1
		o += spacing

	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.11
	mesh.bottom_radius = 0.13
	mesh.height = 1.1
	_multimesh(parent, "MarkerPosts", posts, mesh, Color.WHITE, colors)


# ---------------------------------------------------------------------------
# Water — one flat sheet per carved canyon.
# ---------------------------------------------------------------------------

static func build_water(parent: Node3D, canyons: Array) -> void:
	for i in range(canyons.size()):
		var canyon: Dictionary = canyons[i]
		if not canyon.has("water"):
			continue
		var from: Vector2 = canyon["from"]
		var to: Vector2 = canyon["to"]
		var radius: float = canyon["radius"]
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(from.distance_to(to) + radius * 2.0, radius * 2.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.45, 0.68, 0.72)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.1
		mat.metallic = 0.35
		# Two-sided: the surface is visible from the bridge above and, if a kart
		# does end up down there, from underneath as well.
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.name = "Water%d" % i
		mi.mesh = mesh
		mi.material_override = mat
		parent.add_child(mi)
		var mid: Vector2 = (from + to) * 0.5
		var yaw: float = atan2(to.y - from.y, to.x - from.x)
		mi.transform = Transform3D(Basis(Vector3.UP, -yaw), Vector3(mid.x, canyon["water"], mid.y))


# ---------------------------------------------------------------------------

static func _multimesh(
	parent: Node3D, node_name: String, transforms: Array[Transform3D], mesh: Mesh,
	color: Color, per_instance: Array[Color] = []
) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not per_instance.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, per_instance[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# The toon shader always multiplies in per-instance COLOR, so passing white
	# here lets each instance's own tint through unchanged.
	mmi.material_override = ToonMaterial.create(color)
	mmi.name = node_name
	parent.add_child(mmi)
