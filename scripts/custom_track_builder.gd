extends Node3D
## Builds a player-made *race* track from a TrackDesign, the way
## track_builder.gd builds the built-in circuit from its own constants.
##
## It reuses the same three pieces the built-in track is made of — RoadRibbon for
## the banked, varying-width road surface, TrackGround for the height field the
## terrain and the props share, and TrackProps for the finish line and the
## distance markers — so a track a kid drew in the editor drives like the one
## that shipped with the game rather than like a different game.
##
## The design comes from GameSettings.custom_design, set by the main menu or by
## the editor's Test Drive button. If there isn't one (or it's an arena by
## mistake), this falls back to the Oval template rather than building nothing:
## an empty world with karts falling through it is a much worse failure than the
## wrong track.
##
## Public API is deliberately identical to track_builder.gd's, because race.gd,
## race_manager.gd and terrain_builder.gd's custom counterpart all talk to
## "the track" through it and neither knows nor cares which one it got.

## Gates roughly this far apart round the lap. race_manager requires every gate
## in order, so too few makes cutting the course easy and too many is just work —
## the built-in circuit's 14 over ~890 m is about one per 64 m.
const CHECKPOINT_SPACING := 64.0
const MIN_CHECKPOINTS := 6
const MAX_CHECKPOINTS := 40
## How far past the kerb each gate reaches, so a kart running wide still trips it
## — see the long note on track_builder.gd's own CHECKPOINT_MARGIN for the race
## that was lost to a gate that didn't.
const CHECKPOINT_MARGIN := 10.0
## The checkpoint scene's own gate is this wide, so scaling to the road is a
## ratio against it.
const CHECKPOINT_SCENE_WIDTH := 13.0

@onready var path: Path3D = $Path3D
@onready var road_mesh: MeshInstance3D = $RoadMesh
@onready var road_body: StaticBody3D = $RoadBody
@onready var road_shape: CollisionShape3D = $RoadBody/RoadShape

var design: TrackDesign
var baked_length: float = 0.0

var _ribbon: RoadRibbon
var _ground: TrackGround


func _ready() -> void:
	design = _resolve_design()

	path.curve = design.build_curve()
	baked_length = path.curve.get_baked_length()
	_build_road()
	var canyons: Array = CustomFeatures.water_canyons(design)
	_ground = TrackGround.create(_ribbon, [], canyons)

	_place_checkpoints()
	TrackProps.build_finish_line(self, _ribbon)
	TrackProps.build_markers(self, _ribbon, _ground)
	TrackProps.build_water(self, canyons)
	CustomFeatures.build(self, design, _ground, _ribbon)


## A race track needs a race design. Anything else — nothing selected, a stale
## arena left in GameSettings — gets the starter oval instead of a crash.
func _resolve_design() -> TrackDesign:
	var chosen: TrackDesign = GameSettings.custom_design
	if chosen != null and chosen.kind == TrackDesign.Kind.RACE and chosen.nodes.size() >= TrackDesign.MIN_NODES:
		return chosen
	push_warning("Custom track: no usable race design selected; falling back to the oval template")
	return TrackDesign.from_template("oval")


func _build_road() -> void:
	_ribbon = RoadRibbon.build(path.curve, design.width_profile(path.curve), [])
	road_mesh.mesh = _ribbon.mesh
	road_mesh.material_override = TrackProps.road_material(design.color_of("road"))
	road_shape.shape = _ribbon.shape


func _place_checkpoints() -> void:
	var count: int = clampi(
		int(round(baked_length / CHECKPOINT_SPACING)), MIN_CHECKPOINTS, MAX_CHECKPOINTS
	)
	var checkpoint_scene: PackedScene = load("res://scenes/checkpoint.tscn")
	var race_manager := get_tree().get_first_node_in_group("race_manager")
	for i in range(count):
		var offset: float = baked_length * float(i) / float(count)
		var checkpoint: Area3D = checkpoint_scene.instantiate()
		add_child(checkpoint)
		checkpoint.global_transform = _ribbon.frame_at(offset)
		var wanted: float = (_ribbon.half_width_at(offset) + CHECKPOINT_MARGIN) * 2.0
		checkpoint.scale = Vector3(wanted / CHECKPOINT_SCENE_WIDTH, 1.0, 1.0)
		checkpoint.checkpoint_index = i
		checkpoint.is_finish_line = (i == 0)
		if race_manager:
			race_manager.register_checkpoint(checkpoint)


# ---------------------------------------------------------------------------
# Public API — the same shape track_builder.gd exposes, so race.gd,
# race_manager.gd and custom_terrain_builder.gd can drive either one.
# ---------------------------------------------------------------------------

func get_racing_path() -> Path3D:
	return path


func get_ribbon() -> RoadRibbon:
	return _ribbon


func get_ground() -> TrackGround:
	return _ground


func get_start_transform(lane_offset: float) -> Transform3D:
	return _ribbon.frame_at(0.0).translated_local(Vector3(lane_offset, 0.0, 0.0))
