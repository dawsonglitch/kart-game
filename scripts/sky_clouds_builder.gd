@tool # matches the base class (SunshineCloudsDriver.gd is also @tool) — Godot warns
# on a mismatch otherwise. The actual setup below still only runs at real game
# runtime (see the editor-hint guard in _ready), since our clouds are fully
# procedural and don't need interactive in-editor authoring the way Terrain3D does.
extends SunshineCloudsDriverGD
## Wires up SunshineClouds2 (GDScript variant — this project is a non-.NET Godot
## build, so it must use the addon's SunshineClouds.gd/SunshineCloudsGD path, not
## its parallel C# CompositorEffect, which can't run here at all — see the
## graphics-pass plan for how that was confirmed).
##
## Starts from the addon's own SunshineCloudsGDTestResource.tres (already correctly
## wired to its noise textures and compute shaders — hand-assembling those
## references from scratch risks getting one wrong) and dials the raymarch step
## counts down further, since this renders twice for split-screen — a real
## performance risk that can't be judged headlessly; watch actual frame rate once
## this is visible and lower these further (or disable the node) if it drags.

const CLOUDS_RESOURCE_PATH := "res://addons/SunshineClouds2/SunshineCloudsGDTestResource.tres"

@export var sun_path: NodePath = NodePath("../Sun")
@export var conservative_max_step_count: float = 28.0
@export var conservative_max_lighting_steps: float = 6.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var sun := get_node_or_null(sun_path)
	if sun:
		tracked_directional_lights = [sun]

	var env := _find_world_environment(get_tree().root)
	if env:
		ambience_sample_environment = env.environment
		var clouds: SunshineCloudsGD = load(CLOUDS_RESOURCE_PATH).duplicate()
		clouds.max_step_count = conservative_max_step_count
		clouds.max_lighting_steps = conservative_max_lighting_steps
		if not env.compositor:
			env.compositor = Compositor.new()
		env.compositor.compositor_effects = [clouds]
		clouds_resource = clouds
		update_continuously = true

	super._ready()


func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found := _find_world_environment(child)
		if found:
			return found
	return null
