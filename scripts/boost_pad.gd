extends Area3D
## Speed boost trigger. Drop these on straights or right before jumps for extra air.

@export var boost_multiplier: float = 1.6
@export var boost_duration: float = 1.8
@export var retrigger_cooldown: float = 0.4

var _recently_boosted: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("apply_boost"):
		return
	if _recently_boosted.has(body):
		return
	body.apply_boost(boost_multiplier, boost_duration)
	_recently_boosted[body] = true
	get_tree().create_timer(retrigger_cooldown).timeout.connect(
		func(): _recently_boosted.erase(body)
	)
