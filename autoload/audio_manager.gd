extends Node
## Autoload sound system. Everything plays through plain (non-positional)
## AudioStreamPlayers with a manually computed distance falloff instead of
## AudioStreamPlayer3D — split-screen means two cameras sharing one World3D, and
## Godot's 3D audio picks a single listener per viewport, so a positional sound
## would be attenuated for whichever viewport happened to own the listener rather
## than "however close the nearest player is." play_at() below does that falloff
## itself against the nearest player kart, which is the behavior we actually want
## on a shared screen.
##
## Clips come straight out of the "Sound FX Starter Pack Vol. 1" folder that was
## already sitting unused in the project (already imported, so no new .import
## files needed) — SOUNDS maps a short gameplay name onto each path so call sites
## say AudioManager.play("boost") rather than repeating a long file path.

## Bus names created at startup, so the master volume and the per-category
## volumes in GameSettings can be adjusted independently.
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"

const SOUNDS := {
	# Driving
	"engine": "res://Sound FX Starter Pack Vol. 1/Steampunk/Engine Loop.wav",
	"boost": "res://Sound FX Starter Pack Vol. 1/Retro/Power Up.wav",
	"jump": "res://Sound FX Starter Pack Vol. 1/Retro/Jump.wav",
	"skid": "res://Sound FX Starter Pack Vol. 1/Retro/Slide.wav",
	# Impacts
	"crash_kart": "res://Sound FX Starter Pack Vol. 1/Motions and Impacts/Impact Metal Hatch.wav",
	"crash_wall": "res://Sound FX Starter Pack Vol. 1/Motions and Impacts/Impact Redwood.wav",
	"crash_obstacle": "res://Sound FX Starter Pack Vol. 1/Hollywood/Wooden Crate Destruction.wav",
	# Items
	"item_pickup": "res://Sound FX Starter Pack Vol. 1/UI & Menus/Equip.wav",
	"item_rocket": "res://Sound FX Starter Pack Vol. 1/Hollywood/Mini Rocket Shot.wav",
	"item_hit": "res://Sound FX Starter Pack Vol. 1/Retro/Damage.wav",
	"item_oil": "res://Sound FX Starter Pack Vol. 1/Medieval/Weapon Whoosh.wav",
	"shield_up": "res://Sound FX Starter Pack Vol. 1/Sci-Fi/Force Armor.wav",
	"shield_block": "res://Sound FX Starter Pack Vol. 1/Medieval/Shield Block.wav",
	# Race flow
	"countdown": "res://Sound FX Starter Pack Vol. 1/UI & Menus/Select.wav",
	"go": "res://Sound FX Starter Pack Vol. 1/Retro/Start.wav",
	"lap": "res://Sound FX Starter Pack Vol. 1/Retro/Combo.wav",
	"finish": "res://Sound FX Starter Pack Vol. 1/Jingles & Stingers/Success.wav",
	"win": "res://Sound FX Starter Pack Vol. 1/Jingles & Stingers/Level Up.wav",
	# UI
	"ui_click": "res://Sound FX Starter Pack Vol. 1/UI & Menus/Select.wav",
	# Ambience (looped)
	"ambience": "res://Sound FX Starter Pack Vol. 1/Environment/Grassy Field Loop.wav",
}

## One-shot players are pooled — a burst of crashes shouldn't allocate nodes
## mid-race, and a hard cap keeps a pile-up from turning into a wall of noise.
const POOL_SIZE := 16

## play_at() falloff: full volume within FALLOFF_NEAR metres of a player, silent
## past FALLOFF_FAR, smoothly ramped between. Tuned against the race track's
## scale (a ~772m lap), where an AI kart two corners back should be inaudible.
const FALLOFF_NEAR := 12.0
const FALLOFF_FAR := 90.0

var _streams: Dictionary = {}   # name -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _ambience_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # menu clicks still work while paused
	_setup_buses()
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_pool.append(player)


## SFX and Music are created in code rather than shipped as a bus layout resource
## — two buses with no effects on them is not worth a binary file to maintain, and
## this keeps the volume wiring visible next to the code that uses it.
func _setup_buses() -> void:
	for bus_name in [SFX_BUS, MUSIC_BUS]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


func get_stream(sound_name: String) -> AudioStream:
	if _streams.has(sound_name):
		return _streams[sound_name]
	if not SOUNDS.has(sound_name):
		push_warning("AudioManager: unknown sound '%s'" % sound_name)
		return null
	var stream: AudioStream = load(SOUNDS[sound_name])
	_streams[sound_name] = stream
	return stream


## A looping copy of a clip. The pack's .import settings all have looping off, and
## flipping it on the shared cached resource would silently make every one-shot
## use of that same clip loop too — so each caller gets its own duplicate.
func get_looping_stream(sound_name: String) -> AudioStream:
	var stream: AudioStream = get_stream(sound_name)
	if stream == null:
		return null
	var copy: AudioStream = stream.duplicate()
	if copy is AudioStreamWAV:
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copy.loop_begin = 0
		copy.loop_end = int(copy.get_length() * copy.mix_rate)
	return copy


## Non-positional one-shot at a fixed volume — UI clicks, countdown beeps, and
## anything the local player should always hear at full strength.
func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = get_stream(sound_name)
	if stream == null:
		return
	var player := _next_free_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## World-space one-shot, attenuated by how close the nearest *player* kart is —
## see the header for why this isn't an AudioStreamPlayer3D. Sounds beyond
## FALLOFF_FAR are dropped entirely rather than played at silence, which keeps a
## field of AI karts from burning the whole pool on inaudible bonks.
func play_at(sound_name: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var distance := _distance_to_nearest_listener(position)
	if distance > FALLOFF_FAR:
		return
	play(sound_name, volume_db + falloff_db(distance), pitch)


## Linear-in-dB ramp rather than true inverse-square: the exact curve matters far
## less here than "near = loud, far = gone", and this one is easy to tune. Public
## because kart_controller.gd applies the same curve to its own continuous engine
## loop rather than routing it through the one-shot pool.
func falloff_db(distance: float) -> float:
	if distance <= FALLOFF_NEAR:
		return 0.0
	var t: float = clamp(
		(distance - FALLOFF_NEAR) / (FALLOFF_FAR - FALLOFF_NEAR), 0.0, 1.0
	)
	return lerp(0.0, -32.0, t)


## Distance to whichever human-driven kart is closest. Player karts add
## themselves to the "player_karts" group in kart_controller.gd; with none in the
## tree (e.g. a menu) everything is treated as on top of the listener.
func distance_to_nearest_listener(position: Vector3) -> float:
	return _distance_to_nearest_listener(position)


func _distance_to_nearest_listener(position: Vector3) -> float:
	var karts := get_tree().get_nodes_in_group("player_karts")
	if karts.is_empty():
		return 0.0
	var nearest := INF
	for kart in karts:
		if not is_instance_valid(kart):
			continue
		var d: float = (kart as Node3D).global_position.distance_to(position)
		nearest = min(nearest, d)
	return nearest if nearest < INF else 0.0


## Round-robin rather than "find one that isn't playing" — with a pool this size
## the oldest player is reliably the best one to steal, and it can't fail to
## return something when every player happens to be busy.
func _next_free_player() -> AudioStreamPlayer:
	for i in range(_pool.size()):
		var index := (_next_player + i) % _pool.size()
		if not _pool[index].playing:
			_next_player = (index + 1) % _pool.size()
			return _pool[index]
	var stolen := _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()
	return stolen


## Quiet background loop for the race/arena scenes. Safe to call repeatedly with
## the same name — it won't restart a loop that's already running.
func start_ambience(sound_name: String = "ambience", volume_db: float = -22.0) -> void:
	if _ambience_player and _ambience_player.playing:
		return
	var stream: AudioStream = get_looping_stream(sound_name)
	if stream == null:
		return
	if _ambience_player == null:
		_ambience_player = AudioStreamPlayer.new()
		_ambience_player.bus = MUSIC_BUS
		add_child(_ambience_player)
	_ambience_player.stream = stream
	_ambience_player.volume_db = volume_db
	_ambience_player.play()


func stop_ambience() -> void:
	if _ambience_player:
		_ambience_player.stop()


func set_sfx_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index(SFX_BUS), linear_to_db(clamp(linear, 0.0, 1.0))
	)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(SFX_BUS), linear <= 0.001)


func set_music_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index(MUSIC_BUS), linear_to_db(clamp(linear, 0.0, 1.0))
	)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(MUSIC_BUS), linear <= 0.001)
