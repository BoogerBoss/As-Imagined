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

# [M27L L4] A SECOND entry point, beside the simulator's rather than instead of
# it — Rob's call, 2026-08-03. This project is two things sharing one binary: a
# battle simulator (which is all `main.tscn` has launched since [M23.0b]) and an
# RPG. Repointing `run/main_scene` at the RPG's title screen would have made
# launching the project mean something different for the simulator half, so the
# two are offered side by side here and `main_scene` is unchanged.
const BATTLE_SCENE := "res://scenes/battle/battle_setup_screen.tscn"
const RPG_SCENE := "res://scenes/overworld/title.tscn"
const OVERWORLD_SCENE := "res://scenes/overworld/overworld.tscn"

@onready var _label: Label = $VBoxContainer/StatusLabel
@onready var _button: Button = $VBoxContainer/PingButton
@onready var _adventure: Button = $VBoxContainer/AdventureButton
@onready var _quick_start: Button = $VBoxContainer/QuickStartButton


func _ready() -> void:
	_button.pressed.connect(_on_button_pressed)
	_adventure.pressed.connect(_on_adventure_pressed)
	_quick_start.pressed.connect(_on_quick_start_pressed)
	_label.text = "As Imagined — entry point OK."
	_button.text = "Start Battle"
	_adventure.text = "Start Adventure"
	_quick_start.text = "Quick Start"


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)


## The RPG. Leads to slot selection rather than straight into the field: which
## playthrough this is has to be answered before the overworld exists, since the
## session it reads is what a slot decides.
func _on_adventure_pressed() -> void:
	get_tree().change_scene_to_file(RPG_SCENE)


## A third way in: a brand new game, straight into the field, with none of
## Oak's intro speech/naming/gender/rival-naming cutscene — Rob's own request,
## for fast iteration when the intro isn't what's being tested. Skips the
## slot-selection screen too, landing on the first slot with nothing in it
## (or slot 0 if all three are full, matching `TitleScreen`'s own clamp-not-
## wrap caution rather than inventing a fourth slot).
##
## Reuses `title.gd`'s own "NEW GAME" sequence exactly (`OverworldSession.reset()`
## then `pending_new_game = true` then a scene change to `overworld.tscn`) —
## the only difference is the new `pending_new_game_skip_intro` flag, which
## `overworld.gd`'s own `_ready()` checks before deciding whether to run
## `run_new_game()` at all. Everything downstream of that (spawning in the
## bedroom, walking to Oak's Lab, picking a starter) is untouched — this
## skips ONLY the talking-heads cutscene, not the game.
##
## `{PLAYER}`/`{RIVAL}` need no special-casing here: `PlayerIdentity.
## display_name()`/`display_rival_name()` already fall back to "LEAF"/"GREEN"
## for exactly this case — a boot that never named anyone — since a debug F6
## boot has always needed the same fallback.
func _on_quick_start_pressed() -> void:
	OverworldSession.reset()
	OverworldSession.active_slot = _first_open_slot()
	OverworldSession.pending_new_game = true
	OverworldSession.pending_new_game_skip_intro = true
	get_tree().change_scene_to_file(OVERWORLD_SCENE)


func _first_open_slot() -> int:
	for i in range(SaveManager.SLOT_COUNT):
		if not SaveManager.has_save(i):
			return i
	return 0
