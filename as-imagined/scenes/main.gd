extends Control

# [M23.0b] Minimal entry-point scene — this project's first-ever
# run/main_scene, using only the shared `main_theme.tres` (a single bumped
# default_font_size, nothing more) for readability.
# [M23.1] The button now leads into the bare-bones battle screen
# (scenes/battle/battle_screen.tscn) rather than just incrementing a
# counter — a minimal but real launch flow, still no persistence/menu
# system beyond this.

@onready var _label: Label = $VBoxContainer/StatusLabel
@onready var _button: Button = $VBoxContainer/PingButton


func _ready() -> void:
	_button.pressed.connect(_on_button_pressed)
	_label.text = "As Imagined — entry point OK."
	_button.text = "Start Battle"


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/battle_screen.tscn")
