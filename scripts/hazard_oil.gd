extends Area3D
## Oil slick hazard — temporarily reduces steering traction so the kart slides
## through the turn instead of gripping. Used two ways: placed permanently on the
## track by track_builder.gd, and dropped mid-race by the OIL power-up, which
## sets `lifetime` so the slick fades away instead of littering the track for the
## rest of the race.

@export var traction_amount: float = 0.35
@export var duration: float = 1.2
## Seconds before this slick removes itself. 0 means permanent (track-placed).
@export var lifetime: float = 0.0
## How long the slick spends shrinking away at the end of its life, so it doesn't
## just blink out from under a kart that's about to hit it.
@export var fade_duration: float = 1.5

## The kart that dropped this slick, set by kart_controller.gd's _drop_oil().
## Stays null for the slicks track_builder.gd paints onto the road — those are
## part of the circuit, so spinning off one is nobody's fault but your own.
var owner_kart: Node3D = null

@onready var visual: MeshInstance3D = $Visual

var _age: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if lifetime <= 0.0:
		set_process(false)


func _process(delta: float) -> void:
	_age += delta
	var remaining := lifetime - _age
	if remaining <= 0.0:
		queue_free()
		return
	if remaining < fade_duration and visual:
		var t: float = remaining / fade_duration
		visual.scale = Vector3(t, 1.0, t)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("apply_traction_loss"):
		body.apply_traction_loss(traction_amount, duration)
		AudioManager.play_at("skid", global_position, -8.0)
		# Hitting oil isn't a crash by itself — it's a loss of grip. But whatever
		# the kart slides into while that grip is gone is charged to whoever laid
		# the slick, which is the only way a well-placed oil drop ever scores.
		# The culprit is the kart that dropped this, settled at drop time — whatever
		# is happening to it now, seconds later and elsewhere on the track, has
		# nothing to do with who laid the slick.
		if owner_kart != null and body.has_method("mark_blame"):
			body.mark_blame(owner_kart, duration)
