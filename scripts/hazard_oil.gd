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
