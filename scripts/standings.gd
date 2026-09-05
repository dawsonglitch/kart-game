extends Control
## The end-of-race board: one shared list of the whole field, drawn across both
## halves of the split screen rather than each player seeing only their own line
## in their own HUD. race.gd shows it a couple of seconds after race_manager's
## race_finished, so the per-player "1st!" flash lands first.
##
## Bots that were still out on track when the humans finished are listed as DNF
## instead of being left off — knowing you beat Turbo Tina by half a lap is most
## of the point of racing bots. They aren't frozen, either: the board re-reads
## race_manager.get_standings() a couple of times a second, so late bots move up
## out of the DNF block with real times as they cross the line, and stops polling
## once the last one is in.

signal restart_requested
signal quit_requested

## Ordinal names, matching hud.gd's — "3rd" reads better to a kid than "P3".
const PLACE_NAMES := ["", "1st", "2nd", "3rd", "4th", "5th", "6th"]

## How often the board re-reads the running order. Fast enough that a bot
## crossing the line looks immediate, slow enough not to rebuild rows every frame.
const REFRESH_SECONDS := 0.5

@onready var rows: VBoxContainer = $Panel/VBox/Rows
@onready var restart_button: Button = $Panel/VBox/Buttons/RestartButton
@onready var quit_button: Button = $Panel/VBox/Buttons/QuitButton

var _race_manager: Node
var _refresh_accum: float = 0.0
## Cheap fingerprint of what's currently drawn, so an unchanged running order
## doesn't tear down and rebuild every row twice a second.
var _drawn: String = ""


func _ready() -> void:
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	# Matches the pause menu's exit — both mean the same thing, and during a
	# track designer test drive both go back to the editor.
	quit_button.text = GameSettings.exit_label
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	set_process(false)
	hide()


func show_standings(p_race_manager: Node) -> void:
	_race_manager = p_race_manager
	show()
	_refresh()
	# So Enter/Space works without reaching for the mouse mid-couch.
	restart_button.grab_focus()


func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum < REFRESH_SECONDS:
		return
	_refresh_accum = 0.0
	_refresh()


func _refresh() -> void:
	if _race_manager == null:
		return
	var standings: Array = _race_manager.get_standings()

	var still_running := false
	for row in standings:
		if not row["finished"]:
			still_running = true
			break
	# Once the last kart is in, nothing can change again.
	set_process(still_running)

	var signature := _signature_of(standings)
	if signature == _drawn:
		return
	_drawn = signature

	# remove_child before queue_free: a freed child still sits in the container
	# until the end of the frame, which would show the new rows underneath the
	# old ones for one frame.
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for row in standings:
		rows.add_child(_build_row(row))


## Only the things actually drawn: a finished kart's time never changes, and an
## unfinished one shows no time at all, so id/place/finished covers every row.
func _signature_of(standings: Array) -> String:
	var parts: PackedStringArray = []
	for row in standings:
		parts.append("%d/%d/%s" % [row["player_id"], row["place"], row["finished"]])
	return ",".join(parts)


func _build_row(row: Dictionary) -> HBoxContainer:
	# The human rows are what a player scans for, so they sit forward in white at
	# a larger size while the bots' rows hang back.
	var mine: bool = not row["is_ai"]
	var font_size: int = 24 if mine else 19

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.modulate = Color(1, 1, 1) if mine else Color(0.74, 0.76, 0.8)

	var place := _row_label(_place_name(row["place"]), font_size)
	place.custom_minimum_size = Vector2(56, 0)
	line.add_child(place)

	# A swatch of the kart's own paint — faster to match against the kart you were
	# just driving than reading down a column of names.
	var swatch := ColorRect.new()
	swatch.color = row["color"]
	swatch.custom_minimum_size = Vector2(18, 18)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(swatch)

	var who := _row_label(row["display_name"], font_size)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(who)

	var time := _row_label(
		RaceTime.stamp(row["total_time"]) if row["finished"] else "DNF", font_size
	)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time.custom_minimum_size = Vector2(120, 0)
	if not row["finished"]:
		time.modulate = Color(0.85, 0.7, 0.45)
	line.add_child(time)

	return line


## Same outline treatment as the HUD labels, so the board stays readable over
## whatever stretch of track is still moving behind it.
func _row_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	return label


func _place_name(place: int) -> String:
	return PLACE_NAMES[place] if place > 0 and place < PLACE_NAMES.size() else "%dth" % place
