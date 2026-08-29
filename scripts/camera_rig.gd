extends Camera3D
## Third-person chase camera. This node must live inside its own SubViewport (that's
## what makes it "the" camera for that half of the split screen) while the kart it
## follows lives in the shared world outside any viewport — so instead of parenting
## under the kart, it smoothly chases the kart's position/orientation each frame.

@export var target_path: NodePath
@export var follow_height: float = 3.4
@export var follow_distance: float = 7.0
@export var look_ahead: float = 2.5
@export var position_lerp: float = 6.0
@export var rotation_lerp: float = 5.0

var target: Node3D


func _ready() -> void:
	current = true
	if target_path != NodePath():
		target = get_node_or_null(target_path)


func set_target(node: Node3D) -> void:
	target = node
	# Snap immediately so the camera doesn't swoop in from the origin on race start.
	if target:
		_snap_to_target()
		if "player_id" in target:
			# Don't render this kart's own name tag in its own viewport — it only
			# shows up in the *other* player's view. See kart_controller.gd's
			# NAME_TAG_LAYER_BASE for how the layer number is derived.
			var own_tag_layer := 9 + int(target.player_id)
			set_cull_mask_value(own_tag_layer, false)


func _snap_to_target() -> void:
	var desired := _desired_transform()
	global_transform = desired


func _physics_process(delta: float) -> void:
	if not target:
		return
	var desired := _desired_transform()
	global_position = global_position.lerp(desired.origin, clamp(position_lerp * delta, 0.0, 1.0))
	global_transform.basis = global_transform.basis.slerp(
		desired.basis, clamp(rotation_lerp * delta, 0.0, 1.0)
	)


func _desired_transform() -> Transform3D:
	var back: Vector3 = target.global_transform.basis.z.normalized()
	var desired_pos: Vector3 = (
		target.global_position + back * follow_distance + Vector3.UP * follow_height
	)
	var look_target: Vector3 = target.global_position + Vector3.UP * 1.0 - back * look_ahead
	var t := Transform3D()
	t.origin = desired_pos
	return t.looking_at(look_target, Vector3.UP)
