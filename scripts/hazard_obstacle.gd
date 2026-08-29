extends Area3D
## A log obstacle that rolls back and forth, sweeping across the road — kids learn
## to time their pass through the gap. On contact it knocks the kart back and
## stuns it briefly.

@export var sweep_amplitude_degrees: float = 55.0
@export var sweep_speed: float = 1.1
@export var roll_speed: float = 4.0
@export var stun_duration: float = 0.9
@export var knockback_base: float = 4.0     # minimum knock even at a near-standstill
@export var knockback_speed_factor: float = 0.5 # extra knock per m/s of kart speed at impact

@onready var visual: Node3D = $Visual
@onready var log_mesh: Node3D = $Visual/BarrierMesh

var _time: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_time = randf() * TAU # desync multiple obstacles so they don't all swing in lockstep


func _process(delta: float) -> void:
	_time += delta
	# Sweep the whole log left-right across the road...
	visual.rotation.y = sin(_time * sweep_speed) * deg_to_rad(sweep_amplitude_degrees)
	# ...while it keeps rolling about its own long axis the whole time.
	log_mesh.rotate_y(roll_speed * delta)


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("apply_stun"):
		return
	var away: Vector3 = body.global_position - global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	# Faster hits get knocked back harder — a slow bump barely nudges you.
	var impact_speed: float = absf(body.speed) if "speed" in body else 0.0
	var strength: float = knockback_base + impact_speed * knockback_speed_factor
	AudioManager.play_at("crash_obstacle", global_position, -4.0)
	# No source kart: a log is part of the course. Passing none lets apply_stun
	# fall back to whoever shoved this kart into it, if anyone did.
	body.apply_stun(
		stun_duration,
		away * strength + Vector3.UP * 3.0,
		CrashBlame.Cause.HAZARD,
	)
