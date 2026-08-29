extends CharacterBody3D
## Arcade-style kart controller (not full vehicle physics — forgiving and fun for kids).
## Reads a different input action set depending on player_id: 1 = arrow keys, 2 = WASD.
## Ground handling relies on CharacterBody3D's own floor detection: while grounded it
## hugs slopes, and the instant a ramp's surface drops away underneath, is_on_floor()
## goes false and gravity takes over — that's what gives jumps real hang-time.

signal hit_hazard
## A crash landed on this kart. `by` is whoever is answerable for it — the kart
## that drove into you, the one that fired the rocket, the one whose slick you
## slid off — or null when nobody is (your own bad line into a wall). `cause` is
## a CrashBlame.Cause. arena_manager.gd scores the bumper arena off this signal,
## crediting `by` rather than whoever happened to get hit.
signal crashed(by: Node3D, cause: int)
## Whatever this kart is currently holding changed (picked up, used, or cleared).
## The HUD listens so the item slot always matches reality.
signal item_changed(kind: int)
## Any jolt worth feeling — 0..1 roughly "how hard". camera_rig.gd turns this into
## screen shake for whichever player is watching this kart.
signal impact(strength: float)

@export var player_id: int = 1
@export var kart_color: Color = Color(0.85, 0.15, 0.15)
@export var display_name: String = ""
## When true this kart is driven by ai_driver (see ai_driver.gd) instead of the
## keyboard, and never reads the p%d_* input actions.
@export var is_ai: bool = false

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
## Who caused a kart-vs-kart hit is decided by which kart was closing on the
## contact point faster. Inside this margin (m/s) neither one clearly started it
## — a head-on where both drivers kept their foot in is genuinely both their
## fault — so both sides are credited against each other.
@export var ram_blame_margin: float = 1.5
## How long after being rammed, rocketed, or oiled this kart counts as "not
## really driving". Anything it crashes into during that window is still charged
## to whoever put it there, which is what makes a rocket that punts someone into
## a wall — or into a third kart — score for the kart that fired it.
@export var blame_carry_time: float = 1.5

@export_group("Items")
## What the TURBO power-up gives — noticeably stronger and longer than a track
## boost pad (1.6x for 1.8s), so grabbing an item box feels like a real reward.
@export var turbo_multiplier: float = 2.0
@export var turbo_duration: float = 2.6
## How long a SHIELD lasts if it's never actually hit. It also pops on the first
## impact it absorbs, whichever comes first.
@export var shield_duration: float = 8.0
## Where a dropped OIL slick lands, in metres behind the kart, and how long it
## stays on the track before evaporating.
@export var oil_drop_distance: float = 3.6
@export var oil_lifetime: float = 14.0

@export_group("Engine audio")
## Engine loop pitch ramps across this range from a standstill to top speed.
@export var engine_pitch_idle: float = 0.55
@export var engine_pitch_max: float = 1.7
@export var engine_volume_db: float = -14.0

var speed: float = 0.0
var boost_multiplier: float = 1.0
var boost_timer: float = 0.0
var traction: float = 1.0
var traction_timer: float = 0.0
var stun_timer: float = 0.0

## The power-up in hand, or ItemKind.Kind.NONE. Exactly one at a time — no
## inventory to manage, which is the right amount of decision-making for a kid
## who's also trying to steer.
var held_item: int = ItemKind.Kind.NONE
## While > 0 the next impact is absorbed instead of landing (and pops the shield).
var shield_timer: float = 0.0

## Set by race.gd/arena.gd when this kart is a bot. Anything with a
## get_controls(kart, delta) -> Dictionary method works; see ai_driver.gd.
var ai_driver: Node = null

## Gated false by race_manager during the start countdown so nobody can jump the gun.
var can_drive: bool = true

## While > 0, gravity applies even if a shape is technically still touching the
## ground — set by apply_jump_impulse so a jump pad's launch isn't instantly
## reabsorbed by ordinary floor-snapping on the very next physics step.
var jump_lock_timer: float = 0.0

## While > 0, wall/kart crash detection is skipped so a single hard hit doesn't
## retrigger every physics frame for as long as contact continues.
var crash_cooldown_timer: float = 0.0

## Who is currently answerable for whatever happens to this kart, and for how
## much longer. Set by mark_blame() whenever something outside the driver's
## control acts on it. Already flattened when it's stored — if the kart that
## shoved us was itself someone's victim at the time, the *original* instigator
## goes in here — so reading it never has to walk a chain.
var _blame_source: Node3D = null
var _blame_timer: float = 0.0

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
@onready var boost_flames: GPUParticles3D = $BoostFlames
@onready var shield_bubble: MeshInstance3D = $ShieldBubble

var _bang_scene: PackedScene = load("res://scenes/bang_effect.tscn")
var _rocket_scene: PackedScene = load("res://scenes/rocket.tscn")
var _oil_scene: PackedScene = load("res://scenes/hazard_oil.tscn")

## Per-kart looping engine sound, built in code rather than in kart.tscn because
## the stream has to be a looping *duplicate* (see AudioManager.get_looping_stream)
## — that can't be expressed in the scene file against the shared imported clip.
var _engine_player: AudioStreamPlayer


func _ready() -> void:
	respawn_position = global_position
	respawn_rotation = rotation
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.25
	add_to_group("karts")
	# AudioManager's distance falloff measures against human-driven karts only, so
	# bots must stay out of this group or they'd act as listeners themselves.
	if not is_ai:
		add_to_group("player_karts")
	_apply_color()
	_setup_name_tag()
	_setup_engine_audio()
	if shield_bubble:
		shield_bubble.visible = false


func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	var steer_input := 0.0
	var throttle := false
	var braking := false

	if stun_timer <= 0.0 and can_drive:
		var controls := _gather_controls(delta)
		steer_input = controls["steer"]
		throttle = controls["throttle"]
		braking = controls["brake"]
		if controls["use_item"]:
			use_item()

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
	_update_engine_audio()

	if global_position.y < -10.0:
		respawn()


## Either the keyboard (human) or the attached bot brain (AI), in the one shape
## _physics_process cares about. Keeping both behind this call is what lets a bot
## kart run the exact same driving model as a player rather than a parallel one.
func _gather_controls(delta: float) -> Dictionary:
	if is_ai:
		if ai_driver and ai_driver.has_method("get_controls"):
			return ai_driver.get_controls(self, delta)
		return {"steer": 0.0, "throttle": false, "brake": false, "use_item": false}
	return {
		"steer": Input.get_axis("p%d_left" % player_id, "p%d_right" % player_id),
		"throttle": Input.is_action_pressed("p%d_accel" % player_id),
		"brake": Input.is_action_pressed("p%d_brake" % player_id),
		"use_item": Input.is_action_just_pressed("p%d_item" % player_id),
	}


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
	if _blame_timer > 0.0:
		_blame_timer -= delta
		if _blame_timer <= 0.0:
			_blame_source = null
	if shield_timer > 0.0:
		shield_timer -= delta
		if shield_timer <= 0.0:
			_set_shield_visible(false)
	crash_velocity = crash_velocity.move_toward(Vector3.ZERO, crash_velocity_decay * delta)
	if boost_flames:
		boost_flames.emitting = boost_timer > 0.0


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
		AudioManager.play_at("crash_wall", global_position, -4.0)
		apply_stun(
			crash_stun_duration,
			normal * impact_speed * crash_bounce_factor,
			CrashBlame.Cause.WALL,
		)
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
	AudioManager.play_at("crash_kart", global_position, -2.0)
	var landed_here := apply_crash_impulse(impulse)
	var landed_there: bool = other.apply_crash_impulse(-impulse)

	# The normal points out of `other`'s surface toward us, so this kart closes on
	# the contact by moving *against* it and `other` closes by moving along it.
	# Whichever is closing faster is the one that drove into the other.
	var closing_here := -v1n
	var closing_there := v2n

	# Both culprits are resolved before either hit is recorded. Recording one
	# marks blame on the kart that took it, so looking the second one up
	# afterwards would read blame this very collision just wrote and drop the
	# reciprocal credit — a head-on would score for one driver instead of two.
	var culprit_here: Node3D = get_blame_source(self)
	var culprit_there: Node3D = other.get_blame_source(other)

	if absf(closing_here - closing_there) < ram_blame_margin:
		# Neither one clearly started it — a head-on where both drivers kept their
		# foot in is genuinely both their doing, so it scores for both.
		_charge_ram(culprit_here, other, landed_there)
		_charge_ram(culprit_there, self, landed_here)
	elif closing_here > closing_there:
		_charge_ram(culprit_here, other, landed_there)
	else:
		_charge_ram(culprit_there, self, landed_here)

	_spawn_bang_effect(other)


## Record one kart-vs-kart hit: `culprit` is whoever is answerable for the kart
## that drove in, `victim` is the one that got driven into. `landed` is false
## when a shield ate the hit, and a blocked hit scores nothing at all.
func _charge_ram(culprit: Node3D, victim: CharacterBody3D, landed: bool) -> void:
	# culprit == victim is a kart being shoved into the very kart that shoved it:
	# the shover's own doing, not a second hit for them to bank.
	if not landed or culprit == null or culprit == victim:
		return
	victim.mark_blame(culprit, crash_stun_duration)
	victim.crashed.emit(culprit, CrashBlame.Cause.RAM)


## Whoever is currently on the hook for what this kart does or suffers: the live
## blame source if something recently took control away from the driver,
## otherwise `fallback`.
func get_blame_source(fallback: Node3D = null) -> Node3D:
	if _blame_timer > 0.0 and is_instance_valid(_blame_source):
		return _blame_source
	return fallback


## Charge `source` for whatever befalls this kart over the next `effect_duration`
## + blame_carry_time seconds. Called by anything that takes the wheel away from
## the driver — a ram, a rocket, an oil slick. The most recent cause wins: a
## fresh hit explains the next crash better than a stale one does.
##
## `source` is stored exactly as given, so callers must hand over the kart that
## is genuinely answerable rather than the one physically involved. Every caller
## already does: a ram resolves its culprit through get_blame_source() first, and
## a rocket or an oil slick names the kart that chose to fire or drop it, which
## is its own act no matter what is happening to that kart at the time. Chains
## still work, because each link stores an already-resolved culprit — resolving
## a second time here would instead redirect a rocket to whoever had just rammed
## the kart that fired it.
func mark_blame(source: Node3D, effect_duration: float = 0.0) -> void:
	if source == null or source == self or not is_instance_valid(source):
		return
	_blame_source = source
	_blame_timer = effect_duration + blame_carry_time


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
	AudioManager.play_at("jump", global_position, -3.0)


## Called by boost_pad.gd on overlap, and by the TURBO item.
func apply_boost(multiplier: float, duration: float) -> void:
	boost_multiplier = max(boost_multiplier, multiplier)
	boost_timer = max(boost_timer, duration)
	AudioManager.play_at("boost", global_position, -5.0)
	impact.emit(0.35) # a punch of shake so speed *feels* like speed


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
##
## `cause` says what did it (a CrashBlame.Cause) and `source` names the kart
## behind it where there is one — a rocket knows who fired it, a wall doesn't.
##
## Returns whether the hit actually landed — false means a shield ate it. Most
## callers ignore that, but rocket.gd needs it: a blocked rocket shouldn't score
## on the arena's crash counter or play the "got hit" sound over the shield clang.
func apply_stun(
	duration: float,
	knockback: Vector3,
	cause: int = CrashBlame.Cause.HAZARD,
	source: Node3D = null,
) -> bool:
	if _absorb_with_shield():
		return false
	stun_timer = max(stun_timer, duration)
	crash_cooldown_timer = crash_cooldown
	speed = -absf(speed) * crash_bounce_factor
	crash_velocity += knockback
	_play_crash_smoke()
	impact.emit(clamp(knockback.length() / 16.0, 0.25, 1.0))
	hit_hazard.emit()
	# A wall or a swinging log is nobody's doing on its own, so those fall back to
	# whoever put this kart into it — if anyone did — and otherwise go uncredited.
	# A named source outranks that: a rocket landing right now explains this crash
	# better than a bump from a second ago does.
	var culprit: Node3D = source if source != null else get_blame_source()
	mark_blame(culprit, duration)
	crashed.emit(culprit, cause)
	return true


## Called by _resolve_kart_collision — a proper momentum-exchange impulse from
## hitting another (moving) kart, as opposed to apply_stun's simpler "bounce back
## along your own facing," which only makes sense against something immovable.
##
## Physics only: it deliberately does not report a crash, because at the point it
## runs nobody has worked out yet which of the two karts caused the thing. The
## resolver decides that and calls _blame_ram. Returns false if a shield ate it.
func apply_crash_impulse(impulse: Vector3) -> bool:
	if _absorb_with_shield():
		return false
	crash_velocity += impulse
	stun_timer = max(stun_timer, crash_stun_duration)
	crash_cooldown_timer = crash_cooldown
	_play_crash_smoke()
	impact.emit(clamp(impulse.length() / 16.0, 0.3, 1.0))
	hit_hazard.emit()
	return true


func _play_crash_smoke() -> void:
	if crash_smoke:
		crash_smoke.restart()
		crash_smoke.emitting = true


# ---------------------------------------------------------------------------
# Power-ups. See item_kind.gd for the catalog and the catch-up weighted roll;
# item_box.gd hands them out; the HUD reads them off the item_changed signal.
# ---------------------------------------------------------------------------

## Called by item_box.gd. Silently ignored if the kart already holds something,
## so a box can't be spent on a full hand.
func grant_item(kind: int) -> void:
	if held_item != ItemKind.Kind.NONE or kind == ItemKind.Kind.NONE:
		return
	held_item = kind
	item_changed.emit(held_item)


func use_item() -> void:
	if held_item == ItemKind.Kind.NONE:
		return
	var kind := held_item
	# Cleared *before* firing so an item that immediately affects this kart (the
	# shield bubble popping on a simultaneous hit, say) can't re-enter here and
	# spend the same item twice.
	held_item = ItemKind.Kind.NONE
	item_changed.emit(held_item)
	match kind:
		ItemKind.Kind.TURBO:
			apply_boost(turbo_multiplier, turbo_duration)
		ItemKind.Kind.ROCKET:
			_fire_rocket()
		ItemKind.Kind.OIL:
			_drop_oil()
		ItemKind.Kind.SHIELD:
			_raise_shield()


func _fire_rocket() -> void:
	if not _rocket_scene or not get_parent():
		return
	var rocket := _rocket_scene.instantiate()
	rocket.owner_kart = self
	get_parent().add_child(rocket)
	# Launched from just ahead of the nose so it can't clip the firing kart's own
	# collision box on the very first physics step.
	var forward: Vector3 = -global_transform.basis.z
	rocket.global_position = global_position + forward * 2.2 + Vector3.UP * 0.8
	rocket.global_transform.basis = Basis.looking_at(forward, Vector3.UP)


func _drop_oil() -> void:
	if not _oil_scene or not get_parent():
		return
	var oil := _oil_scene.instantiate()
	oil.lifetime = oil_lifetime
	# So a kart that slides off this slick into something charges the crash to
	# whoever dropped it rather than to nobody at all (see hazard_oil.gd).
	oil.owner_kart = self
	get_parent().add_child(oil)
	var back: Vector3 = global_transform.basis.z
	oil.global_position = global_position + back * oil_drop_distance
	AudioManager.play_at("item_oil", global_position, -6.0)


func _raise_shield() -> void:
	shield_timer = shield_duration
	_set_shield_visible(true)
	AudioManager.play_at("shield_up", global_position, -6.0)


## Returns true if a live shield ate this hit — the caller then skips the stun
## and knockback entirely. One hit per shield, so it pops on use.
func _absorb_with_shield() -> bool:
	if shield_timer <= 0.0:
		return false
	shield_timer = 0.0
	_set_shield_visible(false)
	AudioManager.play_at("shield_block", global_position, -3.0)
	impact.emit(0.3)
	return true


func is_shielded() -> bool:
	return shield_timer > 0.0


func _set_shield_visible(shown: bool) -> void:
	if shield_bubble:
		shield_bubble.visible = shown


# ---------------------------------------------------------------------------
# Engine audio — one looping clip per kart, pitched by speed. Volume is faded by
# distance for bots so a full field doesn't drown out the player's own engine.
# ---------------------------------------------------------------------------

func _setup_engine_audio() -> void:
	var stream: AudioStream = AudioManager.get_looping_stream("engine")
	if stream == null:
		return
	_engine_player = AudioStreamPlayer.new()
	_engine_player.stream = stream
	_engine_player.bus = AudioManager.SFX_BUS
	_engine_player.volume_db = engine_volume_db
	add_child(_engine_player)
	_engine_player.play()


func _update_engine_audio() -> void:
	if _engine_player == null:
		return
	var speed_ratio: float = clamp(absf(speed) / max_speed, 0.0, 1.6)
	_engine_player.pitch_scale = lerp(engine_pitch_idle, engine_pitch_max, speed_ratio)
	if is_ai:
		var distance := AudioManager.distance_to_nearest_listener(global_position)
		_engine_player.volume_db = engine_volume_db - 6.0 + AudioManager.falloff_db(distance)


## Called by checkpoint.gd as each gate is passed, so a fall respawns here.
func set_checkpoint(pos: Vector3, rot: Vector3) -> void:
	respawn_position = pos
	respawn_rotation = rot


func respawn() -> void:
	# Getting knocked clean off the edge still counts against whoever knocked you.
	crashed.emit(get_blame_source(), CrashBlame.Cause.FALL)
	velocity = Vector3.ZERO
	speed = 0.0
	global_position = respawn_position
	rotation = respawn_rotation
