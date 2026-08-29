extends Node
## Tracks checkpoints, laps, and race timing for both players. Lives inside race.tscn
## as a plain child node (found by checkpoint.gd / track_builder.gd via the
## "race_manager" group, so nothing needs a hard NodePath to it).

signal countdown_tick(seconds_left: int)
signal race_started
signal lap_completed(player_id: int, lap: int, lap_time: float)
signal race_finished(results: Array)

const TOTAL_LAPS := 3
const COUNTDOWN_SECONDS := 3

var checkpoints: Array = []
var karts: Array = []

var race_active: bool = false

var _next_checkpoint: Dictionary = {}   # kart -> expected checkpoint index (1-based)
var _lap: Dictionary = {}               # kart -> laps completed so far
var _race_time: Dictionary = {}         # kart -> elapsed seconds since race start
var _finished: Dictionary = {}          # kart -> bool
var _results: Array = []


func _ready() -> void:
	add_to_group("race_manager")


func register_checkpoint(checkpoint: Area3D) -> void:
	checkpoints.append(checkpoint)


func register_kart(kart: Node3D) -> void:
	karts.append(kart)
	_next_checkpoint[kart] = 1
	_lap[kart] = 0
	_race_time[kart] = 0.0
	_finished[kart] = false
	kart.can_drive = false


func _process(delta: float) -> void:
	if not race_active:
		return
	for kart in karts:
		if not _finished.get(kart, true):
			_race_time[kart] += delta


func start_countdown() -> void:
	for i in range(COUNTDOWN_SECONDS, 0, -1):
		countdown_tick.emit(i)
		await get_tree().create_timer(1.0).timeout
	countdown_tick.emit(0)
	race_active = true
	for kart in karts:
		kart.can_drive = true
	race_started.emit()


func checkpoint_passed(kart: Node3D, index: int, is_finish_line: bool) -> void:
	if not karts.has(kart) or _finished.get(kart, false):
		return
	var expected: int = _next_checkpoint.get(kart, 1)
	if is_finish_line:
		if expected < checkpoints.size():
			return # hasn't cleared every gate this lap yet — ignore early re-crossing
		_lap[kart] = _lap.get(kart, 0) + 1
		_next_checkpoint[kart] = 1
		lap_completed.emit(_get_player_id(kart), _lap[kart], _race_time[kart])
		if _lap[kart] >= TOTAL_LAPS:
			_finish_kart(kart)
	elif index == expected:
		_next_checkpoint[kart] = expected + 1


func _finish_kart(kart: Node3D) -> void:
	_finished[kart] = true
	kart.can_drive = false
	_results.append({"player_id": _get_player_id(kart), "total_time": _race_time[kart]})
	if _results.size() == karts.size():
		GameSettings.last_results = _results
		race_finished.emit(_results)


func _get_player_id(kart: Node3D) -> int:
	return kart.player_id if "player_id" in kart else 0


func get_lap(kart: Node3D) -> int:
	return _lap.get(kart, 0)


func get_race_time(kart: Node3D) -> float:
	return _race_time.get(kart, 0.0)
