extends Control
## Per-player HUD. Race mode: lap counter, race timer, rough speed readout, and a
## big center message for the start countdown / finish time. Arena (bumper) mode
## reuses the same scene via setup_arena() instead — the "lap" label repurposed to
## show a running crash count, and the timer shows elapsed session time instead of
## a per-lap race clock.

var kart: Node3D
var race_manager: Node
var arena_manager: Node

@onready var lap_label: Label = $Margin/VBox/LapLabel
@onready var time_label: Label = $Margin/VBox/TimeLabel
@onready var speed_label: Label = $Margin/VBox/SpeedLabel
@onready var message_label: Label = $CenterMessage


func setup(p_kart: Node3D, p_race_manager: Node) -> void:
	kart = p_kart
	race_manager = p_race_manager
	race_manager.countdown_tick.connect(_on_countdown_tick)
	race_manager.lap_completed.connect(_on_lap_completed)
	race_manager.race_finished.connect(_on_race_finished)
	_update_lap_label()


func setup_arena(p_kart: Node3D, p_arena_manager: Node) -> void:
	kart = p_kart
	arena_manager = p_arena_manager
	arena_manager.countdown_tick.connect(_on_countdown_tick)
	arena_manager.crash_count_changed.connect(_on_crash_count_changed)
	lap_label.text = "Crashes: 0"


func _process(_delta: float) -> void:
	if not kart:
		return
	if race_manager:
		time_label.text = "Time: %s" % _format_time(race_manager.get_race_time(kart))
	elif arena_manager:
		time_label.text = "Time: %s" % _format_time(arena_manager.elapsed_time)
	speed_label.text = "%d" % int(abs(kart.speed) * 6.0) # rough arcade speed readout


func _on_countdown_tick(seconds_left: int) -> void:
	message_label.visible = true
	message_label.text = str(seconds_left) if seconds_left > 0 else "GO!"
	if seconds_left == 0:
		get_tree().create_timer(0.6).timeout.connect(func(): message_label.visible = false)


func _on_lap_completed(player_id: int, lap: int, _lap_time: float) -> void:
	if not (kart and "player_id" in kart and kart.player_id == player_id):
		return
	_update_lap_label()
	# The finish message from _on_race_finished covers the final lap, so only flash
	# here for laps that aren't the last one.
	var total: int = race_manager.TOTAL_LAPS if race_manager else lap
	if lap < total:
		message_label.visible = true
		message_label.text = "Lap %d!" % (lap + 1)
		get_tree().create_timer(1.0).timeout.connect(func(): message_label.visible = false)


func _on_race_finished(results: Array) -> void:
	for r in results:
		if kart and "player_id" in kart and r.player_id == kart.player_id:
			message_label.visible = true
			message_label.text = "Finished!\n%s" % _format_time(r.total_time)


func _on_crash_count_changed(player_id: int, count: int) -> void:
	if not (kart and "player_id" in kart and kart.player_id == player_id):
		return
	lap_label.text = "Crashes: %d" % count


func _update_lap_label() -> void:
	var lap: int = race_manager.get_lap(kart) if race_manager else 0
	var total: int = race_manager.TOTAL_LAPS
	lap_label.text = "Lap %d/%d" % [min(lap + 1, total), total]


func _format_time(t: float) -> String:
	@warning_ignore("integer_division") # intentional — minutes as a whole number
	var minutes := int(t) / 60
	var seconds := int(t) % 60
	var ms := int((t - int(t)) * 100)
	return "%d:%02d.%02d" % [minutes, seconds, ms]
