extends Node
## Tracks checkpoints, laps, race timing, and the live running order for every
## kart in the field — players and bots alike. Lives inside race.tscn as a plain
## child node (found by checkpoint.gd / track_builder.gd via the "race_manager"
## group, so nothing needs a hard NodePath to it).

signal countdown_tick(seconds_left: int)
signal race_started
signal lap_completed(player_id: int, lap: int, lap_time: float)
## Fires once every *human* player has crossed the line — bots still on track
## keep driving, but nobody's waiting on them to see the results.
signal race_finished(results: Array)

const TOTAL_LAPS := 3
const COUNTDOWN_SECONDS := 3

var checkpoints: Array = []
var karts: Array = []

var race_active: bool = false

## The track's Path3D, set by race.gd. Positions are ranked by real distance
## travelled along this curve rather than by checkpoint index alone, so two karts
## between the same pair of gates still order correctly.
var track_path: Path3D

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
		AudioManager.play("countdown", -4.0, 0.9)
		await get_tree().create_timer(1.0).timeout
	countdown_tick.emit(0)
	AudioManager.play("go", -3.0)
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
	_results.append({
		"player_id": _get_player_id(kart),
		"display_name": _get_display_name(kart),
		"total_time": _race_time[kart],
		"is_ai": _is_ai(kart),
		"place": _results.size() + 1,
	})
	# Emitting once the last *human* finishes, not the last kart overall: a slow
	# bot three corners back shouldn't hold up the results screen. Bots that
	# haven't finished simply don't appear in the standings.
	if _all_players_finished():
		GameSettings.last_results = _results
		race_finished.emit(_results)


func _all_players_finished() -> bool:
	for kart in karts:
		if _is_ai(kart):
			continue
		if not _finished.get(kart, false):
			return false
	return true


func _get_player_id(kart: Node3D) -> int:
	return kart.player_id if "player_id" in kart else 0


func _get_display_name(kart: Node3D) -> String:
	return kart.display_name if "display_name" in kart else ""


func _is_ai(kart: Node3D) -> bool:
	return kart.is_ai if "is_ai" in kart else false


func get_lap(kart: Node3D) -> int:
	return _lap.get(kart, 0)


func get_race_time(kart: Node3D) -> float:
	return _race_time.get(kart, 0.0)


func has_finished(kart: Node3D) -> bool:
	return _finished.get(kart, false)


func get_final_place(kart: Node3D) -> int:
	for result in _results:
		if result["player_id"] == _get_player_id(kart):
			return result["place"]
	return 0


# ---------------------------------------------------------------------------
# Running order. Progress is (laps completed x lap length) + distance along the
# curve, which gives a single monotonically increasing number per kart that can
# be compared directly — no special-casing needed for karts on different laps.
# ---------------------------------------------------------------------------

func get_progress(kart: Node3D) -> float:
	var laps: float = float(_lap.get(kart, 0))
	if track_path == null or track_path.curve == null:
		return laps
	var length: float = track_path.curve.get_baked_length()
	var along: float = track_path.curve.get_closest_offset(
		track_path.to_local(kart.global_position)
	)
	return laps * length + along


## 1-based race position (1 = leading). A kart that already finished keeps the
## place it finished in rather than drifting as others catch up.
func get_position(kart: Node3D) -> int:
	if _finished.get(kart, false):
		var final_place := get_final_place(kart)
		if final_place > 0:
			return final_place
	var progress := get_progress(kart)
	var place := 1
	for other in karts:
		if other == kart or not is_instance_valid(other):
			continue
		if _finished.get(other, false) or get_progress(other) > progress:
			place += 1
	return place


## 0.0 for the leader, 1.0 for last — item_kind.roll() uses this to hand better
## items to whoever's behind.
func get_rank_fraction(kart: Node3D) -> float:
	if karts.size() <= 1:
		return 0.5
	return float(get_position(kart) - 1) / float(karts.size() - 1)
