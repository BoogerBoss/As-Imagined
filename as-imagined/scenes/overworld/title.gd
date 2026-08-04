extends Node

## [M27L L4] The RPG's boot scene: host the title screen, drive it, and route
## into the overworld.
##
## ⚠️ **THIS IS A SECOND ENTRY POINT, NOT A REPLACEMENT ONE — Rob's call,
## 2026-08-03.** `project.godot`'s `main_scene` stays `scenes/main.tscn`, which is
## the battle SIMULATOR's entry ("Start Battle"); that screen now offers a second
## button into this one. Pointing the project at a title screen instead would
## have changed what launching the project MEANS for the simulator half, which
## has been the only thing `main.tscn` did since `[M23.0b]`.
##
## Thin on purpose: `TitleScreen` owns the list and the cards, `SaveManager` owns
## the payload, and this only connects the two to a scene change.

const OVERWORLD_SCENE := "res://scenes/overworld/overworld.tscn"

var _screen: TitleScreen = null


func _ready() -> void:
	_screen = TitleScreen.new()
	add_child(_screen)
	_screen.slot_chosen.connect(_on_slot_chosen)
	# Deferred so the screen's own `_ready` has built its nodes first — `open()`
	# refreshes labels that do not exist until then.
	_screen.open.call_deferred()


func _process(_delta: float) -> void:
	if _screen == null or not _screen.is_open:
		return
	if Input.is_action_just_pressed("ui_up"):
		_screen.move(-1)
	elif Input.is_action_just_pressed("ui_down"):
		_screen.move(1)
	elif Input.is_action_just_pressed("ui_accept"):
		_screen.confirm()


## ⚠️ **EVERYTHING IS WRITTEN TO `OverworldSession` BEFORE THE SCENE CHANGES**,
## because `change_scene_to_file` frees this node — anything held here would be
## gone before the overworld could read it. Same constraint that made the whole
## session class static in `[M27D D5]`.
func _on_slot_chosen(slot: int, is_new: bool) -> void:
	if is_new:
		# ⚠️ RESET FIRST. Starting a new game over a slot the player had already
		# loaded this session would otherwise inherit its party and flags.
		OverworldSession.reset()
		OverworldSession.active_slot = slot
		OverworldSession.pending_new_game = true
	else:
		var resume := TitleScreen.begin_continue(slot)
		if resume.is_empty():
			# The slot vanished or failed to parse between the listing and the
			# press. Re-open rather than loading an empty playthrough.
			_screen.open()
			return
		OverworldSession.active_slot = slot
		OverworldSession.pending_return = resume
	get_tree().change_scene_to_file(OVERWORLD_SCENE)
