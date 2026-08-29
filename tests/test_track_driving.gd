extends SceneTree
## Puts the AI field on the racetrack and lets it drive. Run headless:
##
##     godot --headless --path . --script tests/test_track_driving.gd
##
## Slower than the structural tests (it simulates a couple of minutes of racing),
## but it is the only check that catches a map that is *shaped* wrong rather than
## built wrong. It has already earned its keep once: a kerbed island down the
## middle of a wide straight looked fine in every structural check, and then a bot
## drove into its nose and stayed there for the rest of the race.

const RACE_SECONDS := 190.0
const MIN_LAPS := 2
const MAX_STALLED_SECONDS := 12

var _scene: Node = null
var _manager: Node
var _bots: Array = []
var _frames := 0
var _last_check := 0.0
var _lowest := {}
var _stalled := {}
var _stall_spots := {}
var _last_progress := {}


func _process(_delta: float) -> bool:
	if _scene == null:
		_start()
		return false

	_frames += 1
	var now: float = _manager.get_race_time(_bots[0])
	for bot in _bots:
		_lowest[bot] = min(_lowest[bot], (bot as Node3D).global_position.y)

	if now - _last_check >= 1.0:
		_last_check = now
		for bot in _bots:
			var progress: float = _manager.get_progress(bot)
			if progress - _last_progress[bot] < 3.0: # under 3 m in a second is wedged
				_stalled[bot] += 1
				(_stall_spots[bot] as Array).append(int(fposmod(progress, _lap_length())))
			_last_progress[bot] = progress

	if now < RACE_SECONDS:
		return false
	_report(now)
	return true


func _start() -> void:
	var settings: Node = root.get_node("/root/GameSettings")
	settings.player_count = 1
	settings.bot_count = 3
	settings.items_enabled = true
	_scene = load("res://scenes/race.tscn").instantiate()
	root.add_child(_scene)
	_manager = get_first_node_in_group("race_manager")
	for kart in get_nodes_in_group("karts"):
		if not kart.is_ai:
			continue
		_bots.append(kart)
		_lowest[kart] = 0.0
		_stalled[kart] = 0
		_stall_spots[kart] = []
		_last_progress[kart] = 0.0


func _lap_length() -> float:
	return _manager.track_path.curve.get_baked_length()


func _report(elapsed: float) -> void:
	print("%.0f seconds of racing over %d frames, lap is %.0f m"
		% [elapsed, _frames, _lap_length()])
	var fails := 0
	for bot in _bots:
		var laps: int = _manager.get_lap(bot)
		var progress: float = _manager.get_progress(bot)
		print("  %-12s laps=%d  %7.1f m at %.1f m/s  lowest y=%6.1f  wedged %d s"
			% [bot.display_name, laps, progress, progress / max(elapsed, 0.001),
			   _lowest[bot], _stalled[bot]])
		if _stalled[bot] > 0:
			# Grouped into 25 m buckets round the lap, so a repeated number points
			# straight at the corner or the prop that is causing it.
			var buckets := {}
			for spot in _stall_spots[bot]:
				var bucket: int = int(spot / 25) * 25
				buckets[bucket] = buckets.get(bucket, 0) + 1
			print("      wedged near lap offsets: " + str(buckets))
		if laps < MIN_LAPS:
			fails += 1
			print("      FAIL  only %d laps — expected at least %d" % [laps, MIN_LAPS])
		# Anything below -12 has fallen off the map; the gorge floor is at -22.
		if _lowest[bot] < -12.0:
			fails += 1
			print("      FAIL  fell off the map (y = %.1f)" % _lowest[bot])
		if _stalled[bot] > MAX_STALLED_SECONDS:
			fails += 1
			print("      FAIL  wedged for %d s — something on the map is trapping bots"
				% _stalled[bot])
	print("\n%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
