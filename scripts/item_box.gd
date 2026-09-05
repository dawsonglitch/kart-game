extends Area3D
## A floating, spinning "?" box. Drive through it to get a random power-up (see
## item_kind.gd). Which power-ups are on the table depends on the mode: a race
## can hand out anything, the bumper arena only the attack weapons and the
## shield. Only karts with an empty hand pick it up — a kart already holding
## something drives straight through, so a box is never wasted.
##
## Picked-up boxes hide and respawn on a timer instead of being freed, so a lap
## later the same box is back where the kids expect it. Placement is done by
## track_builder.gd / arena_builder.gd.

@export var respawn_delay: float = 5.0
@export var spin_speed: float = 1.6
@export var bob_height: float = 0.25
@export var bob_speed: float = 2.0

@onready var visual: Node3D = $Visual
@onready var collision: CollisionShape3D = $CollisionShape3D

var _time: float = 0.0
var _base_y: float = 0.0
var _available: bool = true
var _rng := RandomNumberGenerator.new()
## The items this box can give out, fixed for the session — the mode can't change
## without a scene reload, so there's no reason to look it up per pickup.
var _pool: Array = ItemKind.RACE_POOL


func _ready() -> void:
	_rng.randomize()
	_pool = ItemKind.pool_for_mode(GameSettings.game_mode)
	_base_y = visual.position.y
	# Desync the bob/spin of neighboring boxes so a row of them doesn't pulse in
	# lockstep (same trick hazard_obstacle.gd uses for its sweeping logs).
	_time = randf() * TAU
	# Arena bots hunt for boxes by group rather than by scanning the scene tree
	# every frame (see ai_driver.gd's CHASE mode).
	add_to_group("item_boxes")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	if not _available:
		return
	visual.rotation.y += spin_speed * delta
	visual.position.y = _base_y + sin(_time * bob_speed) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if not _available or not body.has_method("grant_item"):
		return
	if body.held_item != ItemKind.Kind.NONE:
		return # already holding something — leave the box for someone else
	body.grant_item(ItemKind.roll(_rng, _rank_fraction_of(body), _pool))
	_consume()


## 0.0 if this kart is leading, 1.0 if it's last — feeds item_kind.roll()'s
## catch-up weighting. Falls back to the middle when there's no race manager
## (arena mode has no running order at all).
func _rank_fraction_of(kart: Node3D) -> float:
	var manager := get_tree().get_first_node_in_group("race_manager")
	if manager == null or not manager.has_method("get_rank_fraction"):
		return 0.5
	return manager.get_rank_fraction(kart)


func _consume() -> void:
	_available = false
	visual.visible = false
	# Deferred: body_entered fires mid-physics-step, and flipping a collision
	# shape off while the physics server is still resolving that same step is
	# exactly what set_deferred exists for.
	collision.set_deferred("disabled", true)
	AudioManager.play_at("item_pickup", global_position)
	get_tree().create_timer(respawn_delay).timeout.connect(_respawn)


## Whether this box currently has something to give — a consumed box is still in
## the tree (waiting out its respawn timer), so bots have to ask before driving
## to one.
func is_available() -> bool:
	return _available


func _respawn() -> void:
	if not is_inside_tree():
		return
	_available = true
	visual.visible = true
	collision.set_deferred("disabled", false)
