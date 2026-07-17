extends Control

# [M23.0b] Minimal entry-point scene — this project's first-ever
# run/main_scene. Deliberately NOT battle-specific: proves the entry point
# launches and that a plain Button's `pressed` signal drives real
# interaction, using only the shared `main_theme.tres` (a single bumped
# default_font_size, nothing more) for readability. The real battle screen
# (move buttons, HP bars, etc.) is M23.1's job, not this session's.

@onready var _label: Label = $VBoxContainer/StatusLabel
@onready var _button: Button = $VBoxContainer/PingButton

var _press_count := 0


func _ready() -> void:
	_button.pressed.connect(_on_button_pressed)
	_label.text = "As Imagined — entry point OK. Click the button."


func _on_button_pressed() -> void:
	_press_count += 1
	_label.text = "Button pressed %d time(s)." % _press_count
