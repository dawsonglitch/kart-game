extends Area3D
## Oil slick hazard — temporarily reduces steering traction so the kart slides
## through the turn instead of gripping.

@export var traction_amount: float = 0.35
@export var duration: float = 1.2


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("apply_traction_loss"):
		body.apply_traction_loss(traction_amount, duration)
