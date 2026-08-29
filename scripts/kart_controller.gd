extends CharacterBody3D
## Arcade-style kart controller (not full vehicle physics — forgiving and fun for kids).
## Reads a different input action set depending on player_id: 1 = arrow keys, 2 = WASD.
## Ground handling relies on CharacterBody3D's own floor detection: while grounded it
## hugs slopes, and the instant a ramp's surface drops away underneath, is_on_floor()
## goes false and gravity takes over — that's what gives jumps real hang-time.

signal hit_hazard
## Fired only for an actual kart-vs-kart hit (not walls/crates/hazards) — this is
## what arena_manager.gd counts as a "crash" for the bumper arena's scoreboard.
signal kart_collision(other_kart: Node3D)

@export var player_id: int = 1
@export var kart_color: Color = Color(0.85, 0.15, 0.15)
@export var display_name: String = ""

## Body parts (children of Chassis) that get tinted kart_color at runtime.
const PAINTED_PARTS := ["LowerBody", "Cabin", "Hood"]
## Underglow strips — same kart_color, but glowing (emission_boost), on their own
## material instance since they need different shader settings than the body panels.
const GLOW_PARTS := ["Underglow_L", "Underglow_R"]

## Name-tag render layers start at this 1-based layer number; player_id is added on
## top (P1 -> layer 10, P2 -> layer 11), so each kart's tag lives on its own layer and
## camera_rig.gd can exclude a kart's own camera from seeing its own tag.
const NAME_TAG_LAYER_BASE := 9

@export_group("Handling")
@export var max_speed: float = 16.0
@export var reverse_speed: float = 7.0
@export var acceleration: float = 12.0
@export var brake_power: float = 22.0
@export var coast_friction: float = 8.0
@export var steer_rate: float = 2.6 # radians/sec at full steer, full speed
@export var gravity: float = 32.0
@export var air_control: float = 0.2 # fraction of ground steering allowed mid-air

@export_group("Crashes")
## Any hard hit — a wall/curb, the other kart, or a hazard — triggers a bounce-back
## and a puff of smoke. Only wall/kart hits need a speed threshold; hazards always
## trigger (they call apply_stun directly). Below this speed a graze is ignored.
@export var crash_speed_threshold: float = 4.0
@export var crash_bounce_factor: float = 0.55 # bounce-back speed as a fraction of impact speed
@export var crash_stun_duration: float = 0.25
@export var crash_cooldown: float = 0.5
## How fast crash_velocity (see below) bleeds off — the shove fades out over
## roughly a second rather than persisting or cutting off instantly.
@export var crash_velocity_decay: float = 8.0
## 1.0 = textbook equal-mass elastic collision (velocity along the contact normal
## fully swaps). Tested higher first for a punchier arcade "bonk" — at top speed
## (16) that launched a stationary kart ~27m, way past fun into absurd, so this
## stays at a plain 1:1 exchange; a full-speed hit already moves the hit kart at
## roughly the hitter's own top speed, which reads as a solid, satisfying shove.
@export var crash_restitution: float = 1.0

var speed: float = 0.0
var boost_multiplier: float = 1.0
var boost_timer: float = 0.0
var traction: float = 1.0
var traction_timer: float = 0.0
var stun_timer: float = 0.0

## Gated false by race_manager during the start countdown so nobody can jump the gun.
var can_drive: bool = true

## While > 0, gravity applies even if a shape is technically still touching the
## ground — set by apply_jump_impulse so a jump pad's launch isn't instantly
## reabsorbed by ordinary floor-snapping on the very next physics step.
var jump_lock_timer: float = 0.0

## While > 0, wall/kart crash detection is skipped so a single hard hit doesn't
## retrigger every physics frame for as long as contact continues.
var crash_cooldown_timer: float = 0.0

## World-space horizontal "shove" velocity from a crash, layered on top of the
## normal forward/back driving model and decaying back to zero over time — this
## is the actual channel that lets a hit push a kart sideways in a way that
## lasts more than one frame (speed alone only ever points along the kart's own
## forward axis, so it can't represent a sideways shove at all).
var crash_velocity: Vector3 = Vector3.ZERO

var respawn_position: Vector3
var respawn_rotation: Vector3

@onready var chassis: Node3D = $Chassis
@onready var slope_ray: RayCast3D = $SlopeRay
@onready var name_tag: Label3D = $NameTag
@onready var crash_smoke: GPUParticles3D = $CrashSmoke

var _bang_scene: PackedScene = load("res://scenes/bang_effect.tscn")


func _ready() -> void:
	respawn_position = global_position
	respawn_rotation = rotation
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.25
	add_to_group("karts")
	_apply_color()
	_setup_name_tag()


func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	var steer_input := 0.0
	var throttle := false
	var braking := false

	if stun_timer <= 0.0 and can_drive:
		var accel_action := "p%d_accel" % player_id
		var brake_action := "p%d_brake" % player_id
		var left_action := "p%d_left" % player_id
		var right_action := "p%d_right" % player_id
		steer_input = Input.get_axis(left_action, right_action)
		throttle = Input.is_action_pressed(accel_action)
		braking = Input.is_action_pressed(brake_action)

	var current_max_speed := max_speed * boost_multiplier

	if throttle:
		speed = move_toward(speed, current_max_speed, acceleration * delta)
	elif braking:
		speed = move_toward(speed, -reverse_speed, brake_power * delta)
	else:
		speed = move_toward(speed, 0.0, coast_friction * delta)

	var ground_ratio := 1.0 if is_on_floor() else air_control
	var speed_ratio: float = clamp(abs(speed) / max_speed, 0.15, 1.0)
	var turn_dir := 1.0 if speed >= 0.0 else -1.0
	rotate_y(-steer_input * steer_rate * speed_ratio * ground_ratio * traction * turn_dir * delta)

	var forward: Vector3 = -global_transform.basis.z
	var horizontal := forward * speed + crash_velocity
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if jump_lock_timer > 0.0:
		jump_lock_timer -= delta
		velocity.y -= gravity * delta
	elif is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta

	move_and_slide()
	_check_wall_collisions()
	_update_visual_lean(steer_input, delta)

	if global_position.y < -10.0:
		respawn()


func _tick_timers(delta: float) -> void:
	if boost_timer > 0.0:
		boost_timer -= delta
		if boost_timer <= 0.0:
			boost_multiplier = 1.0
	if traction_timer > 0.0:
		traction_timer -= delta
		if traction_timer <= 0.0:
			traction = 1.0
	if stun_timer > 0.0:
		stun_timer -= delta
	if crash_cooldown_timer > 0.0:
		crash_cooldown_timer -= delta
	crash_velocity = crash_velocity.move_toward(Vector3.ZERO, crash_velocity_decay * delta)


## Wall/curb/other-kart impacts aren't scripted triggers like hazards — they're
## just whatever move_and_slide() bumped into this frame. A collision normal close
## to straight up is the ground (or a slope we're meant to be driving on), so only
## a mostly-horizontal normal counts as a real "hit something" crash. Kart-vs-kart
## hits get real momentum physics (see _resolve_kart_collision); anything else
## (wall/curb/crate) gets the simpler bounce-back-along-your-own-facing response,
## which is the right behavior for hitting something that can't move.
func _check_wall_collisions() -> void:
	if crash_cooldown_timer > 0.0:
		return
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var normal: Vector3 = collision.get_normal()
		if absf(normal.y) > 0.5:
			continue # ground/slope contact, not a wall or another kart

		var collider := collision.get_collider()
		if collider is CharacterBody3D and collider.is_in_group("karts"):
			# Relative speed, not just our own — a stationary kart getting
			# rear-ended still needs to register the hit even though its own
			# `speed` is ~0. Uses each kart's *intended* horizontal velocity,
			# not the raw `velocity` property — on a square, dead-on hit,
			# move_and_slide() has already zeroed the blocked component of
			# `velocity` by the time this runs this same frame, which would
			# make a full-speed head-on collision look like ~0 relative speed
			# and silently fail to register at all.
			var rel: Vector3 = _intended_velocity() - collider._intended_velocity()
			if rel.length() < crash_speed_threshold:
				continue
			# Whichever kart's own move_and_slide() actually reports this contact
			# resolves it (and drives both sides of the outcome) — NOT always
			# both: a near-stationary kart being rammed has nothing of its own to
			# "slide" into, so move_and_slide() gives it no collision to detect
			# at all here, only the moving kart sees one. Resolving immediately
			# sets crash_cooldown_timer on both sides (see apply_crash_impulse),
			# so even when both karts *do* detect the same contact in one frame,
			# whichever processes first (fixed by scene tree order) wins and the
			# other's cooldown is already set by the time its own check runs.
			_resolve_kart_collision(collider, normal)
			return

		var impact_speed := absf(speed)
		if impact_speed < crash_speed_threshold:
			continue
		apply_stun(crash_stun_duration, normal * impact_speed * crash_bounce_factor)
		return


## The horizontal velocity this kart is actually trying to move at this frame —
## same formula _physics_process feeds into move_and_slide(), computed fresh so
## it's available even after move_and_slide() has already partly zeroed the real
## `velocity` property in response to this exact collision (see the dead-on-hit
## note in _check_wall_collisions).
func _intended_velocity() -> Vector3:
	return (-global_transform.basis.z) * speed + crash_velocity


## Real crash physics between two karts: an equal-mass elastic-collision impulse
## along the contact normal (each kart's velocity component along that normal
## gets exchanged), so a fast kart T-boning a slow/stopped one visibly shoves it
## sideways in the direction it was traveling, rather than a generic bounce.
func _resolve_kart_collision(other: CharacterBody3D, normal: Vector3) -> void:
	var v1n: float = _intended_velocity().dot(normal)
	var v2n: float = other._intended_velocity().dot(normal)
	var impulse: Vector3 = normal * ((v2n - v1n) * crash_restitution)
	apply_crash_impulse(impulse)
	other.apply_crash_impulse(-impulse)
	kart_collision.emit(other)
	other.kart_collision.emit(self)
	_spawn_bang_effect(other)


func _spawn_bang_effect(other: Node3D) -> void:
	if not _bang_scene or not get_parent():
		return
	var bang := _bang_scene.instantiate()
	get_parent().add_child(bang)
	bang.global_position = (global_position + other.global_position) * 0.5 + Vector3.UP * 1.2


func _update_visual_lean(steer_input: float, delta: float) -> void:
	if not chassis:
		return
	var target_roll := -steer_input * 0.18
	var target_pitch := 0.0
	if slope_ray and slope_ray.is_colliding():
		var normal: Vector3 = slope_ray.get_collision_normal()
		var local_normal: Vector3 = global_transform.basis.inverse() * normal
		target_pitch = local_normal.z * 0.5
	chassis.rotation.z = lerp_angle(chassis.rotation.z, target_roll, 8.0 * delta)
	chassis.rotation.x = lerp_angle(chassis.rotation.x, target_pitch, 8.0 * delta)


func _apply_color() -> void:
	var mat := ToonMaterial.create(kart_color, 0.6) # 0.6 — glossy car paint, not chrome
	for part_name in PAINTED_PARTS:
		var part := chassis.get_node_or_null(part_name) as MeshInstance3D
		if part:
			part.material_override = mat

	var glow_mat := ToonMaterial.create(kart_color, 0.0, 2.2) # bright underglow, no specular needed
	for part_name in GLOW_PARTS:
		var part := chassis.get_node_or_null(part_name) as MeshInstance3D
		if part:
			part.material_override = glow_mat


## Called by race.gd after instancing, so the color picked on the main menu applies
## (kart_color's exported default only covers the case of testing the scene alone).
func set_kart_color(new_color: Color) -> void:
	kart_color = new_color
	_apply_color()


func _setup_name_tag() -> void:
	if not name_tag:
		return
	# Put the tag on its own exclusive render layer and take it off the default
	# layer, so only a camera that explicitly asks for this layer will draw it.
	name_tag.layers = 1 << (NAME_TAG_LAYER_BASE + player_id - 1)
	set_display_name(display_name)


func set_display_name(new_name: String) -> void:
	display_name = new_name
	if name_tag:
		name_tag.text = new_name if new_name != "" else ("Player %d" % player_id)


## Called by jump_pad.gd on overlap — a real velocity kick, not just terrain shape,
## so air time is consistent and easy to tune regardless of exact ramp geometry.
func apply_jump_impulse(vertical_power: float, forward_boost: float = 0.0) -> void:
	velocity.y = vertical_power
	if forward_boost > 0.0:
		speed = max(speed, forward_boost)
	jump_lock_timer = 0.3


## Called by boost_pad.gd on overlap.
func apply_boost(multiplier: float, duration: float) -> void:
	boost_multiplier = max(boost_multiplier, multiplier)
	boost_timer = max(boost_timer, duration)


## Called by hazard_oil.gd on overlap.
func apply_traction_loss(amount: float, duration: float) -> void:
	traction = min(traction, amount)
	traction_timer = max(traction_timer, duration)


## Called by hazard_obstacle.gd and _check_wall_collisions on any hard impact with
## something that can't itself move (a wall, curb, or crate). Bounces the kart
## backward at a speed proportional to how fast it was going — a graze barely
## nudges you, plowing in at full speed sends you well back — and puffs out a
## brief burst of smoke at the point of impact. knockback goes through
## crash_velocity (see below) rather than a one-off velocity nudge, so a hit that
## lands at an angle actually shoves you sideways for a beat instead of the
## sideways component vanishing the instant the next physics frame recomputes
## velocity from forward*speed alone.
func apply_stun(duration: float, knockback: Vector3) -> void:
	stun_timer = max(stun_timer, duration)
	crash_cooldown_timer = crash_cooldown
	speed = -absf(speed) * crash_bounce_factor
	crash_velocity += knockback
	_play_crash_smoke()
	hit_hazard.emit()


## Called by _resolve_kart_collision — a proper momentum-exchange impulse from
## hitting another (moving) kart, as opposed to apply_stun's simpler "bounce back
## along your own facing," which only makes sense against something immovable.
func apply_crash_impulse(impulse: Vector3) -> void:
	crash_velocity += impulse
	stun_timer = max(stun_timer, crash_stun_duration)
	crash_cooldown_timer = crash_cooldown
	_play_crash_smoke()
	hit_hazard.emit()


func _play_crash_smoke() -> void:
	if crash_smoke:
		crash_smoke.restart()
		crash_smoke.emitting = true


## Called by checkpoint.gd as each gate is passed, so a fall respawns here.
func set_checkpoint(pos: Vector3, rot: Vector3) -> void:
	respawn_position = pos
	respawn_rotation = rot


func respawn() -> void:
	velocity = Vector3.ZERO
	speed = 0.0
	global_position = respawn_position
	rotation = respawn_rotation
