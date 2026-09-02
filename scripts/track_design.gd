class_name TrackDesign
extends RefCounted
## One player-made course, as plain data.
##
## Everything the game generates from a hand-authored layout — track_builder.gd's
## WAYPOINTS, arena_builder.gd's constants — is a *const* in a script, which is
## exactly the thing a player can't edit. This is the same idea moved into a
## value: a list of road nodes (or a rink radius), a list of features dropped on
## it, and a palette. track_editor.gd edits one of these, track_library.gd saves
## it to user://, and custom_track_builder.gd / custom_arena_builder.gd turn one
## back into a world.
##
## It is deliberately *only* data — no nodes, no meshes, nothing that needs a
## scene tree — so the editor can rebuild the preview from it thirty times a
## second and the tests can check a design without opening a window.

enum Kind { RACE, ARENA }

## Bumped if the on-disk shape ever changes incompatibly. from_dict() reads the
## version and refuses anything it doesn't understand rather than half-loading it.
const FORMAT_VERSION := 1

# ---------------------------------------------------------------------------
# The feature library
# ---------------------------------------------------------------------------
## One table, read by both the editor's palette and the builders, so adding a
## feature type is a single edit rather than three that can drift apart.
##
##   label     what the palette button says
##   size      default size, and the range the size slider allows
##   solid     true if it blocks a kart (drives the "will this wreck someone" hint)
##   on_road   true if it is meant to sit ON the road (pads, boxes) rather than
##             beside it — the editor snaps these to the nearest road station and
##             the builder seats them on the road surface instead of the ground
const FEATURES := {
	"tree": {
		"label": "🌲 Tree", "size": 1.2, "min": 0.6, "max": 3.0,
		"solid": false, "on_road": false,
	},
	"rock": {
		"label": "🪨 Rock", "size": 1.6, "min": 0.6, "max": 5.0,
		"solid": true, "on_road": false,
	},
	"crate": {
		"label": "📦 Crate", "size": 1.0, "min": 0.6, "max": 2.5,
		"solid": true, "on_road": false,
	},
	"jump": {
		"label": "🛫 Jump", "size": 1.0, "min": 0.7, "max": 2.0,
		"solid": false, "on_road": true,
	},
	"boost": {
		"label": "💨 Boost", "size": 1.0, "min": 0.7, "max": 2.0,
		"solid": false, "on_road": true,
	},
	"box": {
		"label": "🎁 Item Box", "size": 1.0, "min": 0.7, "max": 1.6,
		"solid": false, "on_road": true,
	},
	"oil": {
		"label": "🛢 Oil Slick", "size": 1.0, "min": 0.7, "max": 2.0,
		"solid": false, "on_road": true,
	},
	"bridge": {
		"label": "🌉 Bridge", "size": 24.0, "min": 10.0, "max": 70.0,
		"solid": false, "on_road": false,
	},
	"water": {
		"label": "💧 Water", "size": 26.0, "min": 12.0, "max": 90.0,
		"solid": false, "on_road": false,
	},
}

## Palette order — FEATURES is a Dictionary and its key order is an
## implementation detail, so the UI reads this instead.
const FEATURE_ORDER := [
	"tree", "rock", "crate", "jump", "boost", "box", "oil", "bridge", "water",
]

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
## Every customisable color, with its default. The editor builds one picker per
## entry from this, so a new color is one line here plus wherever it's applied.
const COLOR_DEFAULTS := {
	"road": Color(0.95, 0.9, 0.82),
	"ground": Color(0.85, 0.95, 0.8),
	"foliage": Color(0.16, 0.5, 0.22),
	"rock": Color(0.52, 0.5, 0.48),
	"water": Color(0.15, 0.45, 0.68),
	"sky": Color(0.3, 0.62, 1.0),
}

# ---------------------------------------------------------------------------
# Limits — the editor clamps to these, and from_dict() re-clamps, so a
# hand-edited save file can't produce a road 400 m wide or a one-node lap.
# ---------------------------------------------------------------------------
## How much of the way to its neighbours each node's tangent reaches — the same
## smoothing the built-in circuit's default uses, so a player-made corner rounds
## off like one of its corners rather than like a different kind of road.
const TANGENT_SCALE := 0.25

const MIN_NODES := 4
const MAX_NODES := 40
const MIN_HALF_WIDTH := 3.5
const MAX_HALF_WIDTH := 14.0
## Road height range. The floor is well clear of the y < -10 line that makes
## kart_controller.gd respawn a kart, so no amount of dragging can build a dip
## that teleports whoever drives into it.
const MIN_HEIGHT := -6.0
const MAX_HEIGHT := 40.0
## How far from the origin anything is allowed to sit. The generated terrain is
## sized from the design's own extent, so this is what stops a stray drag from
## asking for a ten-kilometre heightmap.
const WORLD_LIMIT := 400.0
const MIN_ARENA_RADIUS := 60.0
const MAX_ARENA_RADIUS := 260.0

## How bumpy a player-made arena floor is. Flatter than the racetrack's rolling
## country (TrackGround.NOISE_HEIGHT) because every square metre of a rink gets
## driven on. Lives here rather than in the builder so the editor's preview and
## the real thing read the same number.
const ARENA_GROUND_NOISE := 0.7

var kind: int = Kind.RACE
var design_name: String = "My Track"

## RACE only — the lap, in order, as [{"pos": Vector3, "half_width": float}, ...].
## The loop closes back to node 0 automatically; there is no repeated end node.
## `pos.y` is the road's height, which is what makes hills and dips.
var nodes: Array = []

## ARENA only — how big the rink is, wall to wall.
var arena_radius: float = 150.0

## Both kinds — [{"type": String, "pos": Vector3, "yaw": float, "size": float}, ...].
## `pos.y` is only meaningful for the ones that carry their own height (water's
## surface); everything else is re-seated on the finished ground at build time,
## so a feature can't end up floating when a hill moves under it.
var features: Array = []

var colors: Dictionary = COLOR_DEFAULTS.duplicate()


# ---------------------------------------------------------------------------
# Templates — "start your own track from a template"
# ---------------------------------------------------------------------------
## Listed in the order the editor offers them. Each is a starting point that is
## already drivable, so a kid who changes nothing still gets a working track.
const TEMPLATES := [
	{"id": "oval", "kind": Kind.RACE, "label": "🏁 Oval", "hint": "A simple flat circuit"},
	{"id": "hills", "kind": Kind.RACE, "label": "⛰ Hill Loop", "hint": "Climbs, drops and a lake"},
	{"id": "twister", "kind": Kind.RACE, "label": "🌀 Twister", "hint": "Tight, wiggly and narrow"},
	{"id": "rink", "kind": Kind.ARENA, "label": "💥 Open Rink", "hint": "An empty bumper arena"},
	{"id": "junkyard", "kind": Kind.ARENA, "label": "🚧 Junkyard", "hint": "A rink full of stuff"},
]


static func from_template(template_id: String) -> TrackDesign:
	var design := TrackDesign.new()
	match template_id:
		"oval":
			design.design_name = "My Oval"
			design._ring(8, 120.0, 88.0, 7.0)
		"hills":
			design.design_name = "My Hills"
			design._ring(10, 140.0, 110.0, 6.5)
			# Two climbs and two drops around the lap, so the elevation reads as
			# hills rather than one tilted plane. Centred above zero rather than
			# on it: the lap's low point stays clear of MIN_HEIGHT, so the shape
			# survives the clamp below unchanged.
			for i in range(design.nodes.size()):
				var wave: float = sin(TAU * float(i) / float(design.nodes.size()) * 2.0)
				design.nodes[i]["pos"].y = 5.0 + wave * 5.0
			design.features.append(design._feature("water", Vector3(0, 0.0, 0), 0.0, 60.0))
			# A quarter and three quarters of the way round. Pads snap to the
			# nearest point of road, and the ring's first node is the start/finish
			# line — putting one on the +X axis would drop a jump pad under the
			# grid, launching the whole field the instant the lights go out.
			design.features.append(design._feature("jump", Vector3(0, 0, 110.0), 0.0, 1.0))
			design.features.append(design._feature("boost", Vector3(0, 0, -110.0), 0.0, 1.0))
		"twister":
			design.design_name = "My Twister"
			design._ring(16, 110.0, 110.0, 5.0)
			# Push alternate nodes in and out of the ring to make a wiggle.
			for i in range(design.nodes.size()):
				var pull: float = 0.72 if i % 2 == 0 else 1.18
				var p: Vector3 = design.nodes[i]["pos"]
				design.nodes[i]["pos"] = Vector3(p.x * pull, p.y, p.z * pull)
			for i in range(6):
				var angle: float = TAU * float(i) / 6.0
				design.features.append(design._feature(
					"tree", Vector3(cos(angle) * 40.0, 0.0, sin(angle) * 40.0), 0.0, 1.6
				))
		"rink":
			design.kind = Kind.ARENA
			design.design_name = "My Rink"
			design.arena_radius = 140.0
		"junkyard":
			design.kind = Kind.ARENA
			design.design_name = "My Junkyard"
			design.arena_radius = 160.0
			# Two rings of junk. The outer one deliberately clears the ring the
			# karts spawn on (custom_arena_builder.gd's START_RADIUS_FRACTION of
			# the rink) — at 100 m a crate landed five metres in front of one of
			# the starting positions on any even-numbered field.
			for i in range(10):
				var angle: float = TAU * float(i) / 10.0
				var radius: float = 55.0 if i % 2 == 0 else 128.0
				var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
				var kinds := ["crate", "rock", "jump", "boost", "box"]
				design.features.append(design._feature(kinds[i % kinds.size()], pos, angle, 1.4))
		_:
			design.design_name = "My Oval"
			design._ring(8, 120.0, 88.0, 7.0)
	# Templates are written by hand up there and everything else in this class
	# clamps on the way in, so they get the same treatment on the way out — a
	# template that sat outside the limits would come back from its first save
	# reshaped, which is a confusing thing for a starting point to do.
	for node in design.nodes:
		node["pos"] = clamp_position(node["pos"])
		node["half_width"] = clampf(float(node["half_width"]), MIN_HALF_WIDTH, MAX_HALF_WIDTH)
	for feature in design.features:
		feature["pos"] = clamp_position(feature["pos"])
	return design


## A closed elliptical loop of `count` evenly spaced nodes. Every race template
## starts from one of these and then bends it.
func _ring(count: int, radius_x: float, radius_z: float, half_width: float) -> void:
	nodes.clear()
	for i in range(count):
		var angle: float = TAU * float(i) / float(count)
		nodes.append({
			"pos": Vector3(cos(angle) * radius_x, 0.0, sin(angle) * radius_z),
			"half_width": half_width,
		})


func _feature(type: String, pos: Vector3, yaw: float, size: float) -> Dictionary:
	return {"type": type, "pos": pos, "yaw": yaw, "size": size}


# ---------------------------------------------------------------------------
# Editing
# ---------------------------------------------------------------------------

func add_feature(type: String, pos: Vector3, yaw: float = 0.0, size: float = -1.0) -> Dictionary:
	var spec: Dictionary = FEATURES.get(type, {})
	var feature := _feature(
		type, clamp_position(pos), yaw, size if size > 0.0 else float(spec.get("size", 1.0))
	)
	features.append(feature)
	return feature


## Inserts a road node midway between `index` and the one after it, which is how
## the editor lengthens a lap: you get a new handle exactly where the road
## already runs, and dragging it is what changes the shape.
func split_node(index: int) -> int:
	if kind != Kind.RACE or nodes.size() >= MAX_NODES or nodes.is_empty():
		return -1
	var a: Dictionary = nodes[index % nodes.size()]
	var b: Dictionary = nodes[(index + 1) % nodes.size()]
	nodes.insert((index % nodes.size()) + 1, {
		"pos": (a["pos"] as Vector3 + b["pos"] as Vector3) * 0.5,
		"half_width": (float(a["half_width"]) + float(b["half_width"])) * 0.5,
	})
	return (index % nodes.size()) + 1


func remove_node(index: int) -> bool:
	if kind != Kind.RACE or nodes.size() <= MIN_NODES:
		return false
	nodes.remove_at(index % nodes.size())
	return true


func set_node_position(index: int, pos: Vector3) -> void:
	nodes[index]["pos"] = clamp_position(pos)


func set_node_half_width(index: int, half_width: float) -> void:
	nodes[index]["half_width"] = clampf(half_width, MIN_HALF_WIDTH, MAX_HALF_WIDTH)


static func clamp_position(pos: Vector3) -> Vector3:
	return Vector3(
		clampf(pos.x, -WORLD_LIMIT, WORLD_LIMIT),
		clampf(pos.y, MIN_HEIGHT, MAX_HEIGHT),
		clampf(pos.z, -WORLD_LIMIT, WORLD_LIMIT)
	)


## How far out anything in this design reaches, used to size the generated
## terrain — a small track shouldn't pay for a 620 m heightmap.
func extent() -> float:
	var reach := 40.0
	if kind == Kind.ARENA:
		reach = max(reach, arena_radius + 40.0)
	for node in nodes:
		var p: Vector3 = node["pos"]
		reach = max(reach, maxf(absf(p.x), absf(p.z)) + float(node["half_width"]) + 30.0)
	for feature in features:
		var p: Vector3 = feature["pos"]
		reach = max(reach, maxf(absf(p.x), absf(p.z)) + float(feature["size"]) + 15.0)
	return min(reach, WORLD_LIMIT + 60.0)


## The lap as a closed Curve3D. The node list has no repeated end point, so the
## first node is added again at the end with the same tangents — an OPEN curve
## here stops at the last node and simply doesn't include the stretch back across
## the start line, which quietly costs that stretch its checkpoints and reports
## lap positions from the wrong end of the track. track_builder.gd's own
## _build_curve() has the long version.
##
## Lives here, next to the nodes, because both the builder that makes the real
## track and the editor that previews it need exactly this curve — and a preview
## built from a slightly different curve than the game uses is the one bug this
## whole feature can't afford.
func build_curve() -> Curve3D:
	var curve := Curve3D.new()
	var count: int = nodes.size()
	if count == 0:
		return curve
	for i in range(count + 1):
		var index: int = i % count
		var prev: Vector3 = nodes[(index - 1 + count) % count]["pos"]
		var point: Vector3 = nodes[index]["pos"]
		var next: Vector3 = nodes[(index + 1) % count]["pos"]
		var tangent: Vector3 = (next - prev) * TANGENT_SCALE
		curve.add_point(point, -tangent, tangent)
	return curve


## The [[offset, half_width], ...] profile RoadRibbon.build() reads, measured
## along `curve` (which must be the one build_curve() just returned).
func width_profile(curve: Curve3D) -> Array:
	var profile: Array = []
	for i in range(nodes.size()):
		# Node 0 sits at both ends of the closed curve and get_closest_offset is
		# free to report either; the profile is read by distance from zero, so it
		# has to be the near end.
		var offset: float = 0.0 if i == 0 else curve.get_closest_offset(nodes[i]["pos"])
		profile.append([offset, float(nodes[i]["half_width"])])
	profile.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return profile


func color_of(key: String) -> Color:
	return colors.get(key, COLOR_DEFAULTS[key])


# ---------------------------------------------------------------------------
# Serialisation — plain JSON-safe dictionaries, since track_library.gd writes
# these as .json files a curious kid can open and a parent can back up.
# Vector3 and Color have no JSON form, so they go in and out as float arrays.
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var node_list: Array = []
	for node in nodes:
		node_list.append({
			"pos": _v3_to_array(node["pos"]),
			"half_width": float(node["half_width"]),
		})
	var feature_list: Array = []
	for feature in features:
		feature_list.append({
			"type": String(feature["type"]),
			"pos": _v3_to_array(feature["pos"]),
			"yaw": float(feature["yaw"]),
			"size": float(feature["size"]),
		})
	var color_map: Dictionary = {}
	for key in colors:
		var c: Color = colors[key]
		color_map[key] = [c.r, c.g, c.b]
	return {
		"format": FORMAT_VERSION,
		"kind": kind,
		"name": design_name,
		"nodes": node_list,
		"arena_radius": arena_radius,
		"features": feature_list,
		"colors": color_map,
	}


## Returns null for anything that isn't a design this build understands, so a
## corrupt or hand-mangled file is skipped rather than crashing the menu.
static func from_dict(data: Dictionary) -> TrackDesign:
	if int(data.get("format", 0)) != FORMAT_VERSION:
		return null
	var design := TrackDesign.new()
	design.kind = Kind.ARENA if int(data.get("kind", 0)) == Kind.ARENA else Kind.RACE
	design.design_name = String(data.get("name", "Untitled"))
	design.arena_radius = clampf(
		float(data.get("arena_radius", 150.0)), MIN_ARENA_RADIUS, MAX_ARENA_RADIUS
	)

	for entry in data.get("nodes", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		design.nodes.append({
			"pos": clamp_position(_array_to_v3(entry.get("pos", []))),
			"half_width": clampf(
				float(entry.get("half_width", 7.0)), MIN_HALF_WIDTH, MAX_HALF_WIDTH
			),
		})
	if design.kind == Kind.RACE and design.nodes.size() < MIN_NODES:
		return null
	if design.nodes.size() > MAX_NODES:
		design.nodes.resize(MAX_NODES)

	for entry in data.get("features", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var type := String(entry.get("type", ""))
		if not FEATURES.has(type):
			continue # a feature type this build doesn't have; drop it, keep the rest
		var spec: Dictionary = FEATURES[type]
		design.features.append({
			"type": type,
			"pos": clamp_position(_array_to_v3(entry.get("pos", []))),
			"yaw": float(entry.get("yaw", 0.0)),
			"size": clampf(
				float(entry.get("size", spec["size"])), float(spec["min"]), float(spec["max"])
			),
		})

	var color_map: Dictionary = data.get("colors", {})
	for key in COLOR_DEFAULTS:
		var raw = color_map.get(key, null)
		if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 3:
			design.colors[key] = Color(float(raw[0]), float(raw[1]), float(raw[2]))
	return design


func duplicate_design() -> TrackDesign:
	# Round-tripping through the dictionary form is both the deep copy and a
	# standing check that everything an editing session can produce survives a
	# save — if a field ever stops serialising, the editor notices immediately
	# rather than the player discovering it after a reload.
	var copy := TrackDesign.from_dict(to_dict())
	return copy if copy else TrackDesign.new()


static func _v3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _array_to_v3(raw) -> Vector3:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
		return Vector3.ZERO
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
