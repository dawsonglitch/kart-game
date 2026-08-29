extends Node
## Scores the open bumper arena. The winner is whoever *caused* the most crashes
## before the two-minute clock runs out — not whoever was involved in the most,
## which used to reward getting rammed just as much as ramming.
##
## Every crash in the game arrives here already carrying its culprit: see the
## `crashed` signal in kart_controller.gd and the blame rules around it (who was
## closing faster on a bump, who fired the rocket, who dropped the slick, and who
## shoved a kart into the wall it hit). This node only tallies. A crash with a
## culprit scores for the culprit; a crash nobody caused — your own line into the
## boundary — scores for nobody.
##
## Lives inside arena.tscn as a plain child node, mirroring race_manager.gd's
## role in race.tscn.

signal countdown_tick(seconds_left: int)
## `count` is crashes this player *caused* — the number on the scoreboard.
signal crash_count_changed(player_id: int, count: int)
## One scored hit, for the HUD's little "you bopped Zippy" flash. `cause` is a
## CrashBlame.Cause.
signal crash_scored(culprit_id: int, victim_id: int, cause: int)
## Fires when the clock runs out, with the final standings ordered best first.
signal match_finished(results: Array)

const COUNTDOWN_SECONDS := 3
## The last few seconds of the match beep once each, so time running out doesn't
## just arrive out of nowhere.
const FINAL_BEEP_SECONDS := 5

var karts: Array = []
var arena_active: bool = false
var elapsed_time: float = 0.0

## Whether this session runs on a clock at all — GameSettings.arena_timed, read
## once at _ready(). Off gives the original open-ended rink: crashes are still
## attributed and counted, nothing ever ends it.
var timed: bool = false
## Seconds left in a timed match. Meaningless while `timed` is false.
var time_left: float = 0.0
var match_over: bool = false

var _crashes_caused: Dictionary = {} # kart -> int
var _crashes_taken: Dictionary = {}  # kart -> int
var _results: Array = []
## Whole second the last end-of-match beep played on, so each of the final ticks
## beeps once rather than every frame.
var _last_beep: int = -1


func _ready() -> void:
	add_to_group("arena_manager")
	timed = GameSettings.arena_timed
	time_left = GameSettings.ARENA_MATCH_SECONDS


func register_kart(kart: Node3D) -> void:
	karts.append(kart)
	_crashes_caused[kart] = 0
	_crashes_taken[kart] = 0
	kart.can_drive = false
	kart.crashed.connect(_on_kart_crashed.bind(kart))


func _process(delta: float) -> void:
	if not arena_active:
		return
	elapsed_time += delta
	if not timed:
		return
	time_left = max(time_left - delta, 0.0)
	_beep_final_seconds()
	if time_left <= 0.0:
		_finish_match()


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


## crashed(by, cause) is emitted per-kart, so this arrives as (by, cause, victim)
## — `by` and `cause` are the emitted args, and `victim` is the kart bound at
## register_kart() time, i.e. the one that took the hit.
func _on_kart_crashed(by: Node3D, cause: int, victim: Node3D) -> void:
	if not arena_active:
		return # countdown or post-match; a bump then is worth nothing
	# Nobody on the hook — a solo bounce off the boundary wall — so it scores for
	# nobody and counts against nobody. Deliberately not tallied as a crash taken
	# either: that column is only read as a tie-break for "who got picked on
	# least", and a kid who spends the match ricocheting off the wall shouldn't
	# lose a tie over their own driving.
	if by == null or by == victim or not is_instance_valid(by):
		return
	if not _crashes_caused.has(by):
		return # a kart that isn't in this match (shouldn't happen; cheap to be sure)
	_crashes_taken[victim] = _crashes_taken.get(victim, 0) + 1
	_crashes_caused[by] += 1
	crash_count_changed.emit(_player_id(by), _crashes_caused[by])
	crash_scored.emit(_player_id(by), _player_id(victim), cause)


func _beep_final_seconds() -> void:
	var whole := int(ceil(time_left))
	if whole > FINAL_BEEP_SECONDS or whole == _last_beep:
		return
	_last_beep = whole
	if whole > 0:
		AudioManager.play("countdown", -6.0, 1.15)


func _finish_match() -> void:
	if match_over:
		return
	match_over = true
	arena_active = false
	for kart in karts:
		if is_instance_valid(kart):
			kart.can_drive = false
	_results = get_standings()
	GameSettings.last_results = _results
	match_finished.emit(_results)


# ---------------------------------------------------------------------------
# Scoreboard
# ---------------------------------------------------------------------------

## Standings, best first. Most crashes caused wins; ties break on whoever was
## crashed into least, so the kid who dished it out without taking it back
## finishes ahead of the one who traded hit for hit.
func get_standings() -> Array:
	var rows: Array = []
	for kart in karts:
		if not is_instance_valid(kart):
			continue
		rows.append({
			"player_id": _player_id(kart),
			"display_name": _display_name(kart),
			"crashes_caused": _crashes_caused.get(kart, 0),
			"crashes_taken": _crashes_taken.get(kart, 0),
			"is_ai": kart.is_ai if "is_ai" in kart else false,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["crashes_caused"] != b["crashes_caused"]:
			return a["crashes_caused"] > b["crashes_caused"]
		return a["crashes_taken"] < b["crashes_taken"]
	)
	for i in range(rows.size()):
		rows[i]["place"] = i + 1
	return rows


## Crashes this kart caused — the scoreboard number.
func get_crash_count(kart: Node3D) -> int:
	return _crashes_caused.get(kart, 0)


## Crashes another kart put this one into. Solo wall bonks aren't in here — see
## _on_kart_crashed.
func get_crashes_taken(kart: Node3D) -> int:
	return _crashes_taken.get(kart, 0)


## 1-based live standing (1 = leading), so the HUD can show a running order the
## same way it does in a race. Named to match race_manager.get_position().
func get_position(kart: Node3D) -> int:
	var standings := get_standings()
	var id := _player_id(kart)
	for row in standings:
		if row["player_id"] == id:
			return row["place"]
	return standings.size() + 1


## Display name for a player id, for the HUD's hit feed — which only has the
## ids the crash_scored signal carries.
func name_for(player_id: int) -> String:
	for kart in karts:
		if is_instance_valid(kart) and _player_id(kart) == player_id:
			return _display_name(kart)
	return "Player %d" % player_id


func _player_id(kart: Node3D) -> int:
	return kart.player_id if "player_id" in kart else 0


func _display_name(kart: Node3D) -> String:
	if "display_name" in kart and kart.display_name != "":
		return kart.display_name
	return "Player %d" % _player_id(kart)
