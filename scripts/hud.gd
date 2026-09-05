extends Control
## Per-player HUD. Race mode: position in the field, lap counter, race timer, a
## rough speed readout, and a big center message for the start countdown / lap
## flashes / finish. Arena (bumper) mode reuses the same scene via setup_arena()
## instead — the "lap" label repurposed to show how many crashes this player has
## *caused*, the timer counting the match clock down instead of a lap time up,
## the standing showing who is winning the crash contest, and a short feed line
## naming whoever was just bopped (or whoever just bopped you).
##
## The item slot in the corner mirrors whatever power-up this player is holding;
## it's driven by the kart's item_changed signal rather than polled, and hides
## itself entirely when items are turned off.

var kart: Node3D
var race_manager: Node
var arena_manager: Node

@onready var position_label: Label = $Margin/VBox/PositionLabel
@onready var lap_label: Label = $Margin/VBox/LapLabel
@onready var crash_feed: Label = $Margin/VBox/CrashFeed
@onready var time_label: Label = $Margin/VBox/TimeLabel
@onready var speed_label: Label = $Margin/VBox/SpeedLabel
@onready var message_label: Label = $CenterMessage
@onready var item_panel: Panel = $ItemSlot
@onready var item_icon: Label = $ItemSlot/ItemIcon
@onready var item_hint: Label = $ItemSlot/ItemHint

## Ordinal suffixes for the position readout — "1st" reads better to a kid than
## "P1" or a bare number, and there are never more than four karts.
const PLACE_NAMES := ["", "1st", "2nd", "3rd", "4th", "5th", "6th"]

## How long a hit-feed line stays up. Long enough to read mid-drive, short enough
## that back-to-back bumps don't queue up behind each other.
const FEED_SECONDS := 1.6

## Bumps the counter on every feed line so an older line's hide timer can tell it
## has been superseded and leave the newer message alone.
var _feed_token: int = 0


func setup(p_kart: Node3D, p_race_manager: Node) -> void:
	kart = p_kart
	race_manager = p_race_manager
	race_manager.countdown_tick.connect(_on_countdown_tick)
	race_manager.lap_completed.connect(_on_lap_completed)
	race_manager.race_finished.connect(_on_race_finished)
	_connect_item_slot()
	_update_lap_label()


func setup_arena(p_kart: Node3D, p_arena_manager: Node) -> void:
	kart = p_kart
	arena_manager = p_arena_manager
	arena_manager.countdown_tick.connect(_on_countdown_tick)
	arena_manager.crash_count_changed.connect(_on_crash_count_changed)
	arena_manager.crash_scored.connect(_on_crash_scored)
	arena_manager.match_finished.connect(_on_match_finished)
	lap_label.text = "Crashes: 0"
	crash_feed.visible = false
	_connect_item_slot()


func _connect_item_slot() -> void:
	if not GameSettings.items_enabled:
		item_panel.visible = false
		return
	item_hint.text = "Shift" # both players' item key; see project.godot's p%d_item
	if kart and kart.has_signal("item_changed"):
		kart.item_changed.connect(_on_item_changed)
	_on_item_changed(kart.held_item if kart else ItemKind.Kind.NONE)


func _process(_delta: float) -> void:
	if not kart:
		return
	if race_manager:
		time_label.text = "Time: %s" % RaceTime.stamp(race_manager.get_race_time(kart))
		_update_position_label(race_manager)
	elif arena_manager:
		_update_arena_clock()
		_update_position_label(arena_manager)
	speed_label.text = "%d" % int(abs(kart.speed) * 6.0) # rough arcade speed readout


## Works off either manager — race_manager ranks by distance round the track,
## arena_manager by crashes caused. Both answer get_position()/karts.
func _update_position_label(manager: Node) -> void:
	if not manager.has_method("get_position"):
		return
	var place: int = manager.get_position(kart)
	var total: int = manager.karts.size()
	position_label.text = "%s / %d" % [_place_name(place), total]


## A timed arena match counts *down* — and goes red over the last few seconds, so
## a kid with their eyes on the karts still notices the clock running out. With
## the time limit switched off it just shows elapsed session time, as before.
func _update_arena_clock() -> void:
	if not arena_manager.timed:
		time_label.text = "Time: %s" % RaceTime.stamp(arena_manager.elapsed_time)
		return
	var left: float = arena_manager.time_left
	time_label.text = "⏱ %s" % RaceTime.clock(left)
	var urgent: bool = left <= float(arena_manager.FINAL_BEEP_SECONDS)
	time_label.modulate = Color(1, 0.4, 0.35) if urgent else Color(1, 1, 1)


func _place_name(place: int) -> String:
	return PLACE_NAMES[place] if place > 0 and place < PLACE_NAMES.size() else "%dth" % place


func _on_item_changed(kind: int) -> void:
	var has_item: bool = kind != ItemKind.Kind.NONE
	item_icon.text = ItemKind.icon(kind)
	item_hint.visible = has_item
	# The empty slot stays on screen (dimmed) rather than disappearing, so the
	# corner doesn't visibly jump every time an item is used.
	item_panel.modulate = Color(1, 1, 1, 1.0 if has_item else 0.45)


func _on_countdown_tick(seconds_left: int) -> void:
	message_label.visible = true
	message_label.text = str(seconds_left) if seconds_left > 0 else "GO!"
	if seconds_left == 0:
		get_tree().create_timer(0.6).timeout.connect(func(): message_label.visible = false)


func _on_lap_completed(player_id: int, lap: int, _lap_time: float) -> void:
	if not _is_mine(player_id):
		return
	_update_lap_label()
	# The finish message from _on_race_finished covers the final lap, so only flash
	# here for laps that aren't the last one.
	var total: int = race_manager.TOTAL_LAPS if race_manager else lap
	if lap < total:
		AudioManager.play("lap", -6.0)
		message_label.visible = true
		message_label.text = "Lap %d!" % (lap + 1)
		get_tree().create_timer(1.0).timeout.connect(func(): message_label.visible = false)


func _on_race_finished(results: Array) -> void:
	for r in results:
		if _is_mine(r.player_id):
			# A win gets the bigger fanfare; anything else gets the finish chime.
			AudioManager.play("win" if r.place == 1 else "finish", -4.0)
			message_label.visible = true
			message_label.text = "%s!\n%s" % [_place_name(r.place), RaceTime.stamp(r.total_time)]


func _on_crash_count_changed(player_id: int, count: int) -> void:
	if not _is_mine(player_id):
		return
	lap_label.text = "Crashes: %d" % count


## A hit landed somewhere in the rink. Only the ones this player is actually part
## of are worth a line — either they scored it, or they wore it. Anything between
## two bots stays off their HUD.
func _on_crash_scored(culprit_id: int, victim_id: int, cause: int) -> void:
	var who_hit: String = arena_manager.name_for(culprit_id)
	var who_took: String = arena_manager.name_for(victim_id)
	if _is_mine(culprit_id):
		_flash_feed(
			"%s %s %s!" % [CrashBlame.icon(cause), CrashBlame.verb(cause), who_took],
			Color(0.5, 1, 0.55),
		)
	elif _is_mine(victim_id):
		_flash_feed(
			"%s %s %s you!" % [CrashBlame.icon(cause), who_hit, CrashBlame.verb(cause)],
			Color(1, 0.55, 0.5),
		)


func _flash_feed(text: String, color: Color) -> void:
	crash_feed.text = text
	crash_feed.modulate = color
	crash_feed.visible = true
	_feed_token += 1
	var token := _feed_token
	get_tree().create_timer(FEED_SECONDS).timeout.connect(func() -> void:
		# Only hide if no newer line has come in behind this one.
		if token == _feed_token:
			crash_feed.visible = false
	)


## The match clock ran out. Everyone sees the same board rather than only their
## own line, so a kid can tell at a glance that they came second by one.
func _on_match_finished(results: Array) -> void:
	crash_feed.visible = false
	var won: bool = results.size() > 0 and _is_mine(results[0]["player_id"])
	AudioManager.play("win" if won else "finish", -4.0)
	var lines: PackedStringArray = ["TIME!"]
	for row in results:
		lines.append("%s  %s — %d" % [
			_place_name(row["place"]),
			row["display_name"],
			row["crashes_caused"],
		])
	lines.append("Esc to restart")
	# The countdown-sized 64px font fits one word, not a five-line scoreboard, and
	# the default 300px-wide box would clip the longest names.
	message_label.add_theme_font_size_override("font_size", 28)
	message_label.offset_left = -260.0
	message_label.offset_right = 260.0
	message_label.text = "\n".join(lines)
	message_label.visible = true


## Called by race.gd when the shared standings board comes up: the per-player
## finish flash has had its moment, and leaving it behind the dimmed overlay just
## makes the board harder to read.
func clear_message() -> void:
	message_label.visible = false


func _is_mine(player_id: int) -> bool:
	return kart != null and "player_id" in kart and kart.player_id == player_id


func _update_lap_label() -> void:
	var lap: int = race_manager.get_lap(kart) if race_manager else 0
	var total: int = race_manager.TOTAL_LAPS
	lap_label.text = "Lap %d/%d" % [min(lap + 1, total), total]
