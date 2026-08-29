extends Area3D
## One ordered gate in the lap sequence. race_manager (found via the "race_manager"
## group) validates that a kart passes gates in order before a lap counts, and this
## gate's transform also becomes that kart's respawn point if it falls off nearby.

var checkpoint_index: int = 0
var is_finish_line: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("set_checkpoint"):
		return
	body.set_checkpoint(global_position, rotation)
	var race_manager := get_tree().get_first_node_in_group("race_manager")
	if race_manager:
		race_manager.checkpoint_passed(body, checkpoint_index, is_finish_line)
