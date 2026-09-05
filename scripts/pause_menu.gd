extends Control
## Simple pause overlay: Resume / Restart / Main Menu. Its own process_mode is set to
## ALWAYS in the scene so the buttons keep working while the SceneTree is paused.

signal restart_requested
signal quit_requested

@onready var resume_button: Button = $Panel/VBox/ResumeButton
@onready var restart_button: Button = $Panel/VBox/RestartButton
@onready var quit_button: Button = $Panel/VBox/QuitButton


func _ready() -> void:
	# "Main Menu" normally, "Back to Editor" during a track designer test drive —
	# see GameSettings.exit_label.
	quit_button.text = GameSettings.exit_label
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(func(): restart_requested.emit())
	quit_button.pressed.connect(func(): quit_requested.emit())


func _on_resume_pressed() -> void:
	get_tree().paused = false
	hide()
