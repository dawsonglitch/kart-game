extends Node
## Tracks each player's crash count in the open bumper arena — no laps, no
## checkpoints, just an open space to drive around and crash into each other, the
## scattered crates, or the boundary wall. Only counts actual kart-vs-kart hits
## (kart_controller.gd's kart_collision signal) — bonking a wall or crate doesn't
## add to the scoreboard, just a kart-on-kart hit does. Lives inside arena.tscn as
## a plain child node, mirroring race_manager.gd's role in race.tscn.

signal countdown_tick(seconds_left: int)
signal crash_count_changed(player_id: int, count: int)

const COUNTDOWN_SECONDS := 3

var karts: Array = []
var arena_active: bool = false
var elapsed_time: float = 0.0

var _crash_counts: Dictionary = {} # kart -> int


func _ready() -> void:
	add_to_group("arena_manager")


func register_kart(kart: Node3D) -> void:
	karts.append(kart)
	_crash_counts[kart] = 0
	kart.can_drive = false
	kart.kart_collision.connect(_on_kart_crashed.bind(kart))


func _process(delta: float) -> void:
	if arena_active:
		elapsed_time += delta


func start_countdown() -> void:
	for i in range(COUNTDOWN_SECONDS, 0, -1):
		countdown_tick.emit(i)
		AudioManager.play("countdown", -4.0, 0.9)
		await get_tree().create_timer(1.0).timeout
	countdown_tick.emit(0)
	AudioManager.play("go", -3.0)
	arena_active = true
	for kart in karts:
		kart.can_drive = true


## kart_collision(other_kart) is emitted per-kart, so this arrives as
## (other_kart, kart) — other_kart is the emitted arg, kart is the one bound at
## register_kart() time identifying which kart's own counter to bump.
func _on_kart_crashed(_other_kart: Node3D, kart: Node3D) -> void:
	_crash_counts[kart] = _crash_counts.get(kart, 0) + 1
	var player_id: int = kart.player_id if "player_id" in kart else 0
	crash_count_changed.emit(player_id, _crash_counts[kart])


func get_crash_count(kart: Node3D) -> int:
	return _crash_counts.get(kart, 0)
