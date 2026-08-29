extends Control
## Threaded scene load with a visible progress bar — the terrain/texture setup in
## race.tscn takes a few seconds now, long enough that a blank screen would look
## like a freeze. ResourceLoader.load_threaded_* loads in the background while this
## screen polls and displays real progress, then swaps in the finished scene. This
## is the standard, documented Godot pattern for a loading screen.
##
## VERIFICATION NOTE: headless testing (no real rendering device) consistently
## fails to thread-load the shader-based materials used throughout race.tscn —
## the same category of headless-only limitation found with Terrain3D's collision
## earlier ("No rendering device on load" shows up repeatedly in headless runs
## throughout this project). I tried pre-warming the shader cache, with and
## without use_sub_threads, and every ResourceLoader cache mode including
## CACHE_MODE_REPLACE_DEEP for the fallback below — none of it changed the
## outcome, which points at rendering-server-level state rather than anything
## fixable from a resource-caching angle. A completely fresh process's first
## load() of the same scene works fine, confirming this isn't a problem with
## race.tscn itself. This needs a real windowed run to confirm the progress bar
## behaves — don't assume it's fine just because the code looks right.
##
## _on_load_failed() below falls back to a normal blocking load if the threaded
## path ever fails for real, so the player isn't stranded either way.

@onready var progress_bar: ProgressBar = $Center/VBox/ProgressBar
@onready var percent_label: Label = $Center/VBox/PercentLabel

var _fallback_used := false
## Read once at startup — GameSettings.next_scene_path is set by main_menu.gd (or
## by race.gd/arena.gd on restart) right before this scene loads, same pattern as
## player_count/colors below it.
var _scene_path: String = GameSettings.next_scene_path


func _ready() -> void:
	ResourceLoader.load_threaded_request(_scene_path)


func _process(_delta: float) -> void:
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_scene_path, progress)
	var fraction: float = progress[0] if progress.size() > 0 else 0.0

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_update_display(fraction)
		ResourceLoader.THREAD_LOAD_LOADED:
			_update_display(1.0)
			var packed: PackedScene = ResourceLoader.load_threaded_get(_scene_path)
			set_process(false)
			get_tree().change_scene_to_packed(packed)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_on_load_failed()


func _update_display(fraction: float) -> void:
	var percent := int(round(fraction * 100.0))
	progress_bar.value = percent
	percent_label.text = "%d%%" % percent


## Threaded load didn't work out — rather than leave the player stuck, do a normal
## blocking load instead. Briefly freezes (same as having no loading screen at
## all), but still gets them into the race. CACHE_MODE_REPLACE_DEEP re-loads the
## whole dependency tree rather than trusting whatever the failed attempt cached.
func _on_load_failed() -> void:
	if _fallback_used:
		percent_label.text = "Couldn't load — please restart the game."
		set_process(false)
		return
	_fallback_used = true
	percent_label.text = "Loading..."
	var packed: PackedScene = ResourceLoader.load(
		_scene_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP
	)
	set_process(false)
	if packed:
		get_tree().change_scene_to_packed(packed)
	else:
		percent_label.text = "Couldn't load — please restart the game."
