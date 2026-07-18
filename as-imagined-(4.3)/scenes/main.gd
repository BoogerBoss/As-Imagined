extends Control

# [M23.0b] Minimal entry-point scene — this project's first-ever
# run/main_scene, using only the shared `main_theme.tres` (a single bumped
# default_font_size, nothing more) for readability.
# [M23.1] The button now leads into the bare-bones battle screen
# (scenes/battle/battle_screen.tscn) rather than just incrementing a
# counter — a minimal but real launch flow, still no persistence/menu
# system beyond this.
# [M23.6] The button now routes to scenes/battle/battle_setup_screen.tscn
# instead of jumping straight into battle_screen.tscn — format/team
# selection is now the normal path in, not a bypassable extra step. No
# second "skip setup" entry point was kept here: nothing in this project's
# actual USE of main.tscn benefits from bypassing setup (a direct launch of
# battle_screen.tscn itself — e.g. the --autoplay sweep test, or running
# that scene directly from the editor — remains fully independent of this
# file and unaffected either way, so there was nothing this bypass would
# have uniquely enabled).

@onready var _label: Label = $VBoxContainer/StatusLabel
@onready var _button: Button = $VBoxContainer/PingButton


func _ready() -> void:
	_button.pressed.connect(_on_button_pressed)
	_label.text = "As Imagined — entry point OK."
	_button.text = "Start Battle"


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/battle_setup_screen.tscn")
