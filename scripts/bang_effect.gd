extends Node3D
## Comic-book "BANG!" popup for a kart-vs-kart crash — pops in with a quick scale
## punch, holds, fades out along with a burst of sparks, then frees itself.
## Purely cosmetic (spawned by kart_controller.gd's _resolve_kart_collision),
## no gameplay role.

const POP_DURATION := 0.12
const HOLD_DURATION := 0.25
const FADE_DURATION := 0.35
const LIFETIME := POP_DURATION + HOLD_DURATION + FADE_DURATION

@onready var label: Label3D = $Label
@onready var sparks: GPUParticles3D = $Sparks

var _t := 0.0


func _ready() -> void:
	# Random yaw/tilt so repeated bangs don't all look identical.
	rotation.y = randf_range(0.0, TAU)
	rotation.z = randf_range(-0.15, 0.15)
	label.scale = Vector3.ZERO
	sparks.restart()
	sparks.emitting = true


func _process(delta: float) -> void:
	_t += delta
	if _t < POP_DURATION:
		var s: float = ease(_t / POP_DURATION, 0.3) # snappy overshoot-ish pop
		label.scale = Vector3.ONE * s
	elif _t < POP_DURATION + HOLD_DURATION:
		label.scale = Vector3.ONE
	else:
		var fade_t: float = (_t - POP_DURATION - HOLD_DURATION) / FADE_DURATION
		label.modulate.a = 1.0 - clamp(fade_t, 0.0, 1.0)
		label.scale = Vector3.ONE * (1.0 + fade_t * 0.4)
	if _t >= LIFETIME:
		queue_free()
