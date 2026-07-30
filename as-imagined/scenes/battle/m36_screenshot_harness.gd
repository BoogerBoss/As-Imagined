extends Node

# [M36] Visual proof-of-concept harness — NOT a test.
#
# Everything M36 ships is verified by headless assertions about maths: frame
# counts, travel direction, restoration. That proves the port is faithful to
# the reference; it does NOT prove a single pixel ever reaches the screen.
# This harness closes that gap by driving the REAL battle screen (not a
# double), forcing a chosen move, and saving PNG frames of the actual
# viewport while its animation plays.
#
# Run:
#   godot --path <project> scenes/battle/m36_screenshot_harness.tscn -- \
#         --move=53 --shots=8
#
# Writes to user://m36_shots/ (printed on exit as a real filesystem path).
# Deliberately windowed rather than headless: --headless has no rendering
# device, so the viewport texture would come back blank and "prove" nothing.

const SHOT_DIR := "user://m36_shots"

# Defaults chosen to be the acceptance set: Pound (the hitsplat archetype),
# Tackle (lunge + hitsplat) and Flamethrower (the 22-flame stream).
var _move_id := 53
var _shot_count := 10
var _frames_between := 6
# Counterfactual switch: nulls the dispatcher so every move takes the legacy
# hit-effect path. Lets the same harness prove whether a symptom is caused by
# the animation engine or exists without it.
var _disable_anim := false

var _screen: Node = null
var _bm = null
var _saved := 0


func _ready() -> void:
	_parse_args()
	DisplayServer.window_set_size(Vector2i(1024, 768))
	if not _build_battle():
		print("HARNESS: could not build a battle")
		get_tree().quit(1)
		return
	_run.call_deferred()


# Reports every node on the opposing side: whether it exists, is visible,
# where it sits, and what its modulate is. This is the diagnostic for the
# reported regression (opponent sprite / trainer / HP bar not appearing).
func _report_opponent_side(when: String) -> void:
	print("--- opponent side %s ---" % when)
	var stage := _screen.get_node_or_null("BattleStage")
	if stage == null:
		print("    BattleStage MISSING")
		return
	for name in ["OpponentSprite0", "OpponentPanel0", "PlayerSprite0",
			"PlayerPanel0", "OpponentTrainerSprite", "PlayerTrainerSprite"]:
		var n := stage.get_node_or_null(name)
		if n == null:
			print("    %-22s (no such node)" % name)
			continue
		var c := n as Control
		var extra := ""
		if c != null:
			extra = " pos=%s size=%s mod=%s" % [str(c.position), str(c.size),
					str(c.modulate)]
		print("    %-22s visible=%s%s" % [name, str(n.visible), extra])
		if c != null and c.has_meta("_anim_mon_base"):
			print("        _anim_mon_base=%s"
					% str(c.get_meta("_anim_mon_base")))


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--move="):
			_move_id = int(arg.split("=")[1])
		elif arg.begins_with("--shots="):
			_shot_count = int(arg.split("=")[1])
		elif arg.begins_with("--gap="):
			_frames_between = int(arg.split("=")[1])
		elif arg == "--noanim":
			_disable_anim = true


# Builds two real parties whose lead knows the move under test, so the
# animation that plays is the one being proven rather than whatever the mon
# happened to have.
func _build_battle() -> bool:
	var move := MoveRegistry.get_move(_move_id)
	if move == null:
		print("HARNESS: move %d does not exist" % _move_id)
		return false

	var attacker := PokemonFactory.create_battle_pokemon(6, 50, [_move_id])
	var defender := PokemonFactory.create_battle_pokemon(9, 50, [33])
	if attacker == null or defender == null:
		print("HARNESS: PokemonFactory could not build the battlers")
		return false

	var player := BattleParty.new()
	player.members = [attacker] as Array[BattlePokemon]
	player.active_indices = [0] as Array[int]
	var opp := BattleParty.new()
	opp.members = [defender] as Array[BattlePokemon]
	opp.active_indices = [0] as Array[int]

	BattleSetupContext.set_pending(player, opp, false, "")
	var scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	_screen = scene.instantiate()
	add_child(_screen)
	return true


func _run() -> void:
	# Let the screen lay out and start its battle.
	for i in range(90):
		await get_tree().process_frame
	_bm = _screen.get("_bm")
	if _bm == null:
		print("HARNESS: battle manager never appeared")
		get_tree().quit(1)
		return

	if _disable_anim:
		_screen.set("_anim_dispatcher", null)
		print("HARNESS: animation engine DISABLED (counterfactual run)")
	var disp = _screen.get("_anim_dispatcher")
	if disp == null:
		print("HARNESS: no anim dispatcher (extracted data missing?)")
	else:
		var verdict: Dictionary = disp.verdict_for_move(_move_id)
		print("HARNESS: move %d -> %s | playable=%s | missing=%s"
				% [_move_id, verdict.get("label", "?"),
					str(disp.can_play_move(_move_id)),
					str(verdict.get("missing", []))])

	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_report_opponent_side("BEFORE move")

	# Force the move rather than clicking through menus: the point is the
	# animation, not the input path.
	_bm.set_human_controlled(0, false)
	_bm.set_human_controlled(1, false)
	_bm.queue_move(0, 0)
	_bm.queue_move(1, 0)
	_bm.advance()

	# Capture across the animation window.
	for shot in range(_shot_count):
		for f in range(_frames_between):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/move_%d_shot_%02d.png" % [SHOT_DIR, _move_id, shot]
		var err := img.save_png(path)
		if err == OK:
			_saved += 1
		else:
			print("HARNESS: failed to save %s (err %d)" % [path, err])

	_report_opponent_side("AFTER move")
	print("HARNESS: saved %d/%d shots to %s"
			% [_saved, _shot_count, ProjectSettings.globalize_path(SHOT_DIR)])
	get_tree().quit(0 if _saved > 0 else 1)
