extends Area3D
## The ROCKET item's projectile. Flies forward from the kart that fired it and
## gently steers toward the nearest kart ahead — gently on purpose: a perfectly
## homing missile is miserable to be on the receiving end of, whereas one that
## can be dodged by swerving stays fun for kids on both ends.
##
## It rides at a fixed height above the ground (sampled by a downward ray) rather
## than following terrain physics, so it tracks over the track's jumps and dips
## without needing its own gravity/suspension model.

@export var speed: float = 34.0
@export var turn_rate: float = 2.0        # radians/sec of homing correction
@export var lifetime: float = 5.0
@export var seek_range: float = 60.0
@export var seek_cone_dot: float = 0.35   # only home onto targets roughly ahead
@export var hover_height: float = 0.9
@export var stun_duration: float = 1.1
@export var knockback_strength: float = 14.0

## Set by the firing kart so its own rocket can't immediately hit it.
var owner_kart: Node3D

@onready var ground_ray: RayCast3D = $GroundRay

var _age: float = 0.0
var _bang_scene: PackedScene = load("res://scenes/bang_effect.tscn")


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	AudioManager.play_at("item_rocket", global_position)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		_explode()
		return

	var target := _find_target()
	if target:
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 0.01:
			var desired := Basis.looking_at(to_target.normalized(), Vector3.UP)
			global_transform.basis = global_transform.basis.slerp(
				desired, clamp(turn_rate * delta, 0.0, 1.0)
			)

	global_position += -global_transform.basis.z * speed * delta
	_follow_ground()


## Keeps the rocket a constant height over whatever is below it. If the ray finds
## nothing (flying out over the edge of a jump), it just holds its current height
## and carries on until lifetime runs out.
func _follow_ground() -> void:
	if ground_ray == null:
		return
	ground_ray.force_raycast_update()
	if ground_ray.is_colliding():
		global_position.y = ground_ray.get_collision_point().y + hover_height


## Nearest kart that's both within range and roughly in front — never the kart
## that fired it.
func _find_target() -> Node3D:
	var forward: Vector3 = -global_transform.basis.z
	var best: Node3D = null
	var best_distance := seek_range
	for kart in get_tree().get_nodes_in_group("karts"):
		if kart == owner_kart or not is_instance_valid(kart):
			continue
		var to_kart: Vector3 = (kart as Node3D).global_position - global_position
		var distance := to_kart.length()
		if distance > best_distance or distance < 0.01:
			continue
		if forward.dot(to_kart / distance) < seek_cone_dot:
			continue
		best = kart
		best_distance = distance
	return best


func _on_body_entered(body: Node3D) -> void:
	if body == owner_kart:
		return
	if body.has_method("apply_stun"):
		var away: Vector3 = -global_transform.basis.z
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		# A shielded target returns false — the shield's own clang already played,
		# and a blocked rocket shouldn't sound like a hit or score like one.
		if body.apply_stun(stun_duration, away * knockback_strength + Vector3.UP * 4.0):
			AudioManager.play_at("item_hit", global_position)
			_credit_hit(body)
	_explode()


## Report the hit as a kart-vs-kart collision so the bumper arena's scoreboard
## counts it — landing a rocket is the one thing in that mode that could shove
## someone clear across the rink and previously score nothing at all.
##
## Emitted on both karts, matching kart_controller.gd's _resolve_kart_collision:
## the arena counter tracks collisions each kart was *involved in*, not hits it
## landed, so a physical bonk already credits both sides. A rocket hit reads the
## same way. Race mode ignores kart_collision entirely, so this is inert there.
func _credit_hit(victim: Node3D) -> void:
	# Only possible to miss if the firing kart was freed mid-flight; the victim
	# still takes the hit either way, it just goes uncredited rather than emitting
	# a signal carrying a dangling reference.
	if not is_instance_valid(owner_kart) or not owner_kart.has_signal("kart_collision"):
		return
	owner_kart.kart_collision.emit(victim)
	if victim.has_signal("kart_collision"):
		victim.kart_collision.emit(owner_kart)


## One shared exit path — spawns the same comic "BANG!" pop a kart-vs-kart crash
## uses, then frees itself. Called for a hit, a wall, and running out of time.
func _explode() -> void:
	if _bang_scene and get_parent():
		var bang := _bang_scene.instantiate()
		get_parent().add_child(bang)
		bang.global_position = global_position + Vector3.UP * 0.4
	queue_free()
