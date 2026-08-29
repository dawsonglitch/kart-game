extends Camera3D
## Third-person chase camera. This node must live inside its own SubViewport (that's
## what makes it "the" camera for that half of the split screen) while the kart it
## follows lives in the shared world outside any viewport — so instead of parenting
## under the kart, it smoothly chases the kart's position/orientation each frame.
##
## It also carries the two bits of "game feel" that belong to the view rather than
## to the kart: a FOV that widens with speed (so a boost reads as speed even when
## the number on the HUD is the only thing that changed) and a decaying shake it
## applies on impacts, driven by the kart's own `impact` signal.

@export var target_path: NodePath
@export var follow_height: float = 3.4
@export var follow_distance: float = 7.0
@export var look_ahead: float = 2.5
@export var position_lerp: float = 6.0
@export var rotation_lerp: float = 5.0

@export_group("Feel")
## FOV at a standstill, and the extra degrees added at (boosted) top speed. The
## widening is what sells a turbo — the kart's actual speed change is only 2x.
@export var base_fov: float = 75.0
@export var fov_speed_gain: float = 22.0
@export var fov_lerp: float = 4.0
## Peak positional jitter, in metres, for a full-strength (1.0) impact.
@export var shake_strength: float = 0.55
## Shake amplitude decays by this fraction per second — ~0.15s to fade out.
@export var shake_decay: float = 6.0

var target: Node3D

var _shake: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	current = true
	_rng.randomize()
	fov = base_fov
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
		if target.has_signal("impact"):
			target.impact.connect(add_shake)


## Called from the followed kart's `impact` signal (and safe to call directly).
## Takes the strongest pending shake rather than summing, so a multi-car pile-up
## rattles hard once instead of launching the camera into orbit.
func add_shake(strength: float) -> void:
	_shake = max(_shake, clamp(strength, 0.0, 1.0) * shake_strength)


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
	_apply_shake(delta)
	_apply_speed_fov(delta)


## Shake is added as a positional offset *after* the smooth follow has been
## applied, so it never feeds back into the chase target — the camera rattles
## around where it should be and settles right back.
func _apply_shake(delta: float) -> void:
	if _shake <= 0.001:
		_shake = 0.0
		return
	global_position += Vector3(
		_rng.randf_range(-_shake, _shake),
		_rng.randf_range(-_shake, _shake) * 0.6,
		_rng.randf_range(-_shake, _shake)
	)
	_shake = move_toward(_shake, 0.0, shake_decay * shake_strength * delta)


func _apply_speed_fov(delta: float) -> void:
	if not ("speed" in target and "max_speed" in target):
		return
	# Deliberately measured against unboosted max_speed, so a boost pushes the
	# ratio past 1.0 and the FOV opens up further than plain flat-out driving.
	var ratio: float = clamp(absf(target.speed) / max(target.max_speed, 0.01), 0.0, 2.0)
	var desired_fov: float = base_fov + fov_speed_gain * ratio * 0.5
	fov = lerp(fov, desired_fov, clamp(fov_lerp * delta, 0.0, 1.0))


func _desired_transform() -> Transform3D:
	var back: Vector3 = target.global_transform.basis.z.normalized()
	var desired_pos: Vector3 = (
		target.global_position + back * follow_distance + Vector3.UP * follow_height
	)
	var look_target: Vector3 = target.global_position + Vector3.UP * 1.0 - back * look_ahead
	var t := Transform3D()
	t.origin = desired_pos
	return t.looking_at(look_target, Vector3.UP)
