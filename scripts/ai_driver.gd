class_name AIDriver
extends Node
## Bot brain. Produces the same {steer, throttle, brake, use_item} dictionary a
## human's keyboard produces, which kart_controller.gd feeds into the identical
## driving model — so a bot is subject to exactly the same physics, boosts,
## hazards, and crashes a player is. No cheating, no separate movement path.
##
## Two modes, because the two game modes want completely different behavior:
##   TRACK — follow the racetrack spline (race.tscn). Aims at a point ahead on
##           the curve, brakes for corners, and recovers if it gets stuck.
##   CHASE — hunt the nearest other kart inside the bumper arena (arena.tscn),
##           steering off the boundary wall when it gets close to it.

enum Mode { TRACK, CHASE }

## Full-lock steering is reached when the target sits this many radians off the
## nose. Anything wider just pins the stick — a bot shouldn't feather the wheel
## when it's pointed completely the wrong way.
const STEER_FULL_LOCK := 0.6

## Considered stuck after this long below STUCK_SPEED while trying to drive.
const STUCK_SPEED := 1.5
const STUCK_TIME := 1.2
## How long the reverse-and-turn recovery runs before trying forward again.
const UNSTICK_TIME := 0.9

## TRACK: how far ahead on the curve to aim, in metres, at a standstill and per
## m/s of current speed. Looking further ahead at speed is what stops a bot from
## sawing at the wheel down a straight.
const LOOKAHEAD_BASE := 9.0
const LOOKAHEAD_PER_SPEED := 0.75

## CHASE: start steering away from the wall once past this fraction of the rink
## radius.
const WALL_AVOID_FRACTION := 0.82
## CHASE: how far an empty-handed bot will detour to grab an item box. Race-mode
## bots need no equivalent — the boxes sit on the racing line they already follow.
const BOX_SEEK_RANGE := 70.0

## Longest a bot will sit on an item waiting for its ideal moment. Without this a
## bot can hold one indefinitely: an arena bot orbiting a target is never "going
## straight", so the TURBO condition would never come true and it would keep the
## item (and stay ineligible for another box) for the whole session.
const MAX_ITEM_HOLD := 6.0

@export var mode: int = Mode.TRACK
## 0..1 — scales top speed, corner discipline, and item reaction time together,
## so one number covers "how good is this bot". race.gd spreads bots across a
## range rather than fielding identical clones.
@export var skill: float = 0.75

## TRACK mode: the racing line to follow. Set by race.gd from the track's Path3D
## (kept as the node, not the raw Curve3D, so curve-space points can be converted
## to world space correctly no matter where the path sits).
var path: Path3D

## CHASE mode: the rink's centre and radius, used for wall avoidance.
var arena_center: Vector3 = Vector3.ZERO
var arena_radius: float = 0.0

## Per-bot lateral offset from the exact centre line, so a field of bots fans out
## across the road instead of driving nose-to-tail in one groove.
var lane_offset: float = 0.0

var _rng := RandomNumberGenerator.new()
var _stuck_timer: float = 0.0
var _unstick_timer: float = 0.0
var _unstick_steer: float = 1.0
## Counts down after picking up an item — bots don't fire the instant they grab
## something, which would be both inhuman and unfair.
var _item_delay: float = 0.0
## How long the current item has been held, against MAX_ITEM_HOLD.
var _item_held_time: float = 0.0
var _last_seen_item: int = ItemKind.Kind.NONE
## Remembered from the last steering decision purely so the TURBO check can ask
## "are we going straight right now?" without recomputing the racing line.
var _last_steer: float = 0.0


func _ready() -> void:
	_rng.randomize()


## The one entry point kart_controller.gd calls each physics step.
func get_controls(kart: Node3D, delta: float) -> Dictionary:
	var controls := {"steer": 0.0, "throttle": false, "brake": false, "use_item": false}
	_update_stuck_state(kart, delta)

	if _unstick_timer > 0.0:
		_unstick_timer -= delta
		# Reverse away from whatever we're wedged against, wheels turned, so the
		# next forward attempt starts pointing somewhere new.
		controls["steer"] = _unstick_steer
		controls["brake"] = true
		return controls

	match mode:
		Mode.TRACK:
			_drive_track(kart, controls)
		Mode.CHASE:
			_drive_chase(kart, controls)

	_last_steer = controls["steer"]
	controls["use_item"] = _decide_item(kart, delta)
	return controls


# ---------------------------------------------------------------------------
# TRACK mode — follow the racing line.
# ---------------------------------------------------------------------------

func _drive_track(kart: Node3D, controls: Dictionary) -> void:
	if path == null or path.curve == null:
		controls["throttle"] = true
		return
	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	if length <= 0.0:
		controls["throttle"] = true
		return

	# get_closest_offset works in the curve's own space, so the kart's position
	# has to be taken into that space first (and sampled points brought back).
	var here: float = curve.get_closest_offset(path.to_local(kart.global_position))
	var speed: float = absf(kart.speed)
	var lookahead: float = LOOKAHEAD_BASE + speed * LOOKAHEAD_PER_SPEED
	var target: Vector3 = _point_on_curve(curve, length, here + lookahead, lane_offset)

	controls["steer"] = _steer_toward(kart, target)

	# Corner speed: compare the track's heading one lookahead out against two, and
	# back off for the difference. A straight leaves the bot flat out; a hairpin
	# pulls the target speed well down so it arrives at a speed it can hold.
	var dir_near: Vector3 = _curve_heading(curve, length, here + lookahead)
	var dir_far: Vector3 = _curve_heading(curve, length, here + lookahead * 2.0)
	var straightness: float = clamp(dir_near.dot(dir_far), 0.0, 1.0)
	var corner_factor: float = lerp(0.45, 1.0, straightness)
	# Low-skill bots also just drive slower overall, which is most of what makes
	# an easy bot easy without making it behave erratically.
	var target_speed: float = kart.max_speed * lerp(0.62, 1.0, clamp(skill, 0.0, 1.0)) * corner_factor

	controls["throttle"] = speed < target_speed
	controls["brake"] = speed > target_speed * 1.3


## A point on the curve at `offset` (wrapped — the track is a loop), pushed
## sideways by `lateral` along the curve's own right vector, in world space.
func _point_on_curve(curve: Curve3D, length: float, offset: float, lateral: float) -> Vector3:
	var wrapped: float = fposmod(offset, length)
	var t: Transform3D = curve.sample_baked_with_rotation(wrapped, true, false)
	return path.to_global(t.origin + t.basis.x * lateral)


func _curve_heading(curve: Curve3D, length: float, offset: float) -> Vector3:
	var a: Vector3 = _point_on_curve(curve, length, offset, 0.0)
	var b: Vector3 = _point_on_curve(curve, length, offset + 6.0, 0.0)
	var dir: Vector3 = b - a
	dir.y = 0.0
	return dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD


# ---------------------------------------------------------------------------
# CHASE mode — bumper arena.
# ---------------------------------------------------------------------------

func _drive_chase(kart: Node3D, controls: Dictionary) -> void:
	# Empty-handed, with a box in reach? Go shopping first — otherwise the arena's
	# power-ups would only ever be picked up by accident on the way to a ram.
	var aim: Vector3 = arena_center
	var box := _nearest_available_box(kart) if kart.held_item == ItemKind.Kind.NONE else null
	if box:
		aim = box.global_position
	else:
		var target_kart := _nearest_other_kart(kart)
		if target_kart:
			aim = target_kart.global_position

	# Wall avoidance wins over the chase: near the boundary, blend the aim point
	# back toward the middle so the bot peels off instead of grinding the wall.
	if arena_radius > 0.0:
		var from_center: Vector3 = kart.global_position - arena_center
		from_center.y = 0.0
		var edge_ratio: float = from_center.length() / arena_radius
		if edge_ratio > WALL_AVOID_FRACTION:
			var pull: float = clamp((edge_ratio - WALL_AVOID_FRACTION) / (1.0 - WALL_AVOID_FRACTION), 0.0, 1.0)
			aim = aim.lerp(arena_center, pull)

	controls["steer"] = _steer_toward(kart, aim)
	# Flat out unless it's badly mis-aimed — a bot spinning in place at full
	# throttle looks broken, whereas easing off lets it point itself first.
	var speed: float = absf(kart.speed)
	var target_speed: float = kart.max_speed * lerp(0.6, 1.0, clamp(skill, 0.0, 1.0))
	controls["throttle"] = absf(controls["steer"]) < 0.9 or speed < target_speed * 0.4
	controls["brake"] = false


## Closest item box still holding something, within BOX_SEEK_RANGE.
func _nearest_available_box(kart: Node3D) -> Node3D:
	var best: Node3D = null
	var best_distance := BOX_SEEK_RANGE
	for box in get_tree().get_nodes_in_group("item_boxes"):
		if not is_instance_valid(box) or not box.is_available():
			continue
		var d: float = (box as Node3D).global_position.distance_to(kart.global_position)
		if d < best_distance:
			best_distance = d
			best = box
	return best


func _nearest_other_kart(kart: Node3D) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for other in get_tree().get_nodes_in_group("karts"):
		if other == kart or not is_instance_valid(other):
			continue
		var d: float = (other as Node3D).global_position.distance_to(kart.global_position)
		if d < best_distance:
			best_distance = d
			best = other
	return best


# ---------------------------------------------------------------------------
# Shared helpers.
# ---------------------------------------------------------------------------

## Steering value in the same convention as Input.get_axis(left, right):
## positive turns right. Negated because signed_angle_to about +Y is positive
## counter-clockwise (i.e. to the left).
func _steer_toward(kart: Node3D, target: Vector3) -> float:
	var to_target: Vector3 = target - kart.global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return 0.0
	var forward: Vector3 = -kart.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return 0.0
	var angle: float = forward.normalized().signed_angle_to(to_target.normalized(), Vector3.UP)
	return clamp(-angle / STEER_FULL_LOCK, -1.0, 1.0)


## Wedged against a wall or a crate with the throttle down is the one failure a
## purely reactive steering model can't escape, so it gets an explicit timer:
## crawl for long enough and the bot backs up with the wheel turned.
func _update_stuck_state(kart: Node3D, delta: float) -> void:
	if _unstick_timer > 0.0:
		return
	if not kart.can_drive:
		_stuck_timer = 0.0
		return
	if absf(kart.speed) < STUCK_SPEED:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_TIME:
			_stuck_timer = 0.0
			_unstick_timer = UNSTICK_TIME
			_unstick_steer = 1.0 if _rng.randf() < 0.5 else -1.0
	else:
		_stuck_timer = 0.0


## Whether to press the item button this frame. Each item has a condition worth
## waiting for, plus a reaction delay so bots don't fire on the same frame they
## pick something up.
func _decide_item(kart: Node3D, delta: float) -> bool:
	var item: int = kart.held_item
	if item == ItemKind.Kind.NONE:
		_last_seen_item = ItemKind.Kind.NONE
		_item_held_time = 0.0
		return false
	if item != _last_seen_item:
		_last_seen_item = item
		_item_held_time = 0.0
		# Better bots think faster. 0.35s at top skill, ~1.4s at the bottom.
		_item_delay = lerp(1.4, 0.35, clamp(skill, 0.0, 1.0)) + _rng.randf_range(0.0, 0.4)
	if _item_delay > 0.0:
		_item_delay -= delta
		return false
	_item_held_time += delta
	if _item_held_time >= MAX_ITEM_HOLD:
		return true # waited long enough — take the shot that's available

	match item:
		ItemKind.Kind.SHIELD:
			return true # no reason to hold a shield
		ItemKind.Kind.TURBO:
			# Save it for somewhere it'll actually pay off: pointed straight and
			# not already boosting.
			return kart.boost_timer <= 0.0 and absf(_last_steer) < 0.35
		ItemKind.Kind.ROCKET:
			return _has_kart_within(kart, 55.0, true)
		ItemKind.Kind.OIL:
			return _has_kart_within(kart, 28.0, false)
	return false


## Is there another kart within `range_m`, ahead of us (`ahead` true) or behind?
func _has_kart_within(kart: Node3D, range_m: float, ahead: bool) -> bool:
	var forward: Vector3 = -kart.global_transform.basis.z
	for other in get_tree().get_nodes_in_group("karts"):
		if other == kart or not is_instance_valid(other):
			continue
		var to_other: Vector3 = (other as Node3D).global_position - kart.global_position
		to_other.y = 0.0
		var distance: float = to_other.length()
		if distance > range_m or distance < 0.5:
			continue
		var dot: float = forward.dot(to_other / distance)
		if (ahead and dot > 0.55) or (not ahead and dot < -0.3):
			return true
	return false
