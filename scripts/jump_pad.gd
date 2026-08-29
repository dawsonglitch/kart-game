extends Area3D
## Launch trigger sitting at a ramp's crest. Gives the kart a real velocity kick
## rather than relying on terrain shape alone — that makes air time reliable and
## easy to tune (just adjust vertical_power) instead of fighting spline geometry.

@export var vertical_power: float = 22.0
@export var forward_boost: float = 4.0
@export var retrigger_cooldown: float = 0.6

var _recently_launched: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("apply_jump_impulse"):
		return
	if _recently_launched.has(body):
		return
	body.apply_jump_impulse(vertical_power, forward_boost)
	_recently_launched[body] = true
	get_tree().create_timer(retrigger_cooldown).timeout.connect(
		func(): _recently_launched.erase(body)
	)
