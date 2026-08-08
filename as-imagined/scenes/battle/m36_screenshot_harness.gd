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
var _frames_between := 4
# Counterfactual switch: nulls the dispatcher so every move takes the legacy
# hit-effect path. Lets the same harness prove whether a symptom is caused by
# the animation engine or exists without it.
var _disable_anim := false

# Trigger state -- see _run()'s own comment on why a fixed gap did not work.
const _TRIGGER_TIMEOUT := 3000
var _anim_started := false
## ⚠️ [2026-08-07] Move ids whose animation started that were NOT the forced
## one. Reported on a timeout so a silent capture-of-the-wrong-move becomes a
## named failure -- see `_run()`'s trigger block.
var _foreign_anims: Array[int] = []
var _anim_frames := 0
var _move_landed := false

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

	# [screenshot pass, 2026-07-30] FORCE THE PLAYER'S SIDE VISIBLE.
	#
	# `_ready()` clears both sides' sprites and relies on each side's own
	# send-out to reveal them (M26B3-5). The opponent's completes here; the
	# PLAYER's does not -- its trainer is still mid-sequence in every frame,
	# so the attacker sprite stays hidden for the whole capture.
	#
	# That made every attacker-side behavior unverifiable by screenshot --
	# Defense Curl's squash, Rollout's wind-up, Flail's decay, the whole
	# mon-deform family -- which is most of what batches 8-13 built. It also
	# explains batch 7's note that "the harness has never shown the player's
	# Pokemon".
	#
	# Forced here rather than fixed in the battle screen, because this is an
	# instrument fault to work around, not a licence to change production
	# behaviour from a harness. The underlying send-out stall is REAL and is
	# flagged separately -- real play reveals the mon correctly per M26B3-5's
	# own verification, so it is harness-specific, not a shipped bug.
	if _screen.has_method("_set_player_mon_sprites_visible"):
		_screen.call("_set_player_mon_sprites_visible", true)
	if _screen.has_method("_set_health_panels_visible"):
		_screen.call("_set_health_panels_visible", true)
	var stage_node := _screen.get_node_or_null("BattleStage")
	if stage_node != null:
		var t := stage_node.get_node_or_null("PlayerTrainerSprite")
		if t != null:
			(t as Control).visible = false

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

	# THE TRIGGER. Previously this captured at a fixed gap starting the moment
	# the move was queued, which routinely missed the animation completely:
	# the battle intro (trainer sprites, party summary, both send-outs, two
	# messages) drains through _pending_beats for ~830 frames before a move's
	# animation begins, so a 26x26 window landed on the intro and a shorter
	# one never reached the move at all. Three separate verification attempts
	# were lost to this before it was fixed.
	#
	# Now the harness waits for the battle screen to say the animation has
	# actually started, and only then begins shooting.
	# ⚠️ **MATCHES THE MOVE ID, AND THE FIRST VERSION DID NOT — IT CAPTURED THE
	# WRONG MOVE'S ANIMATION AND SAID NOTHING.**
	#
	# `anim_script_started(move_id)` has always carried the id; the old lambda
	# discarded it and set the flag for ANY animation. Both battlers act every
	# turn here (`queue_move(1, 0)` is the opponent's Tackle), so whenever the
	# forced move failed to animate, the harness serenely shot the OPPONENT'S
	# move instead and labelled the PNGs with the forced move's id.
	#
	# Found by reviewing the output rather than the code: a Thunder run
	# (`--move=87`) produced six frames captioned "Foe Blastoise used Tackle".
	# Thunder is 70% accuracy, it missed, no animation started for it, and the
	# opponent's Tackle tripped the trigger. Every low-accuracy move in the
	# roster had that exposure, and a reviewer signing off from these PNGs would
	# have been looking at the wrong animation entirely.
	if _screen.has_signal("anim_script_started"):
		_screen.connect("anim_script_started", func(id: int):
			if id == _move_id:
				_anim_started = true
			elif not _foreign_anims.has(id):
				_foreign_anims.append(id))
		_screen.connect("anim_script_finished",
				func(_id: int, f: int): _anim_frames = f)
	# A move the engine DECLINES falls through to the legacy hit effect and
	# never emits anim_script_started, so move_executed is the fallback --
	# but ONLY then. move_executed fires during the battle's synchronous
	# resolution inside advance(), long before the queued animation beat
	# actually runs, so using it for a playable move triggers at frame 0 and
	# captures the intro all over again. That mistake is what the first cut
	# of this fix made.
	var engine_will_play: bool = disp != null and disp.can_play_move(_move_id) \
			and not _disable_anim
	if not engine_will_play:
		_bm.move_executed.connect(func(_a, _b, _m, _d): _move_landed = true)

	# ⚠️ **FORCE THE HIT.** Without it an accuracy roll decides whether this run
	# captures anything, so a 70%-accuracy move silently fails ~30% of the time
	# -- and, before the id check above, silently captured the OPPONENT'S move
	# instead. `_force_hit` is BattleManager's own existing test seam
	# (`battle_manager.gd:599`), not a harness invention. The animation is what
	# is under review; whether the move would have connected is not.
	_bm._force_hit = true

	_bm.set_human_controlled(0, false)
	_bm.set_human_controlled(1, false)
	_bm.queue_move(0, 0)
	_bm.queue_move(1, 0)
	_bm.advance()

	var waited := 0
	while not _anim_started and not _move_landed and waited < _TRIGGER_TIMEOUT:
		await get_tree().process_frame
		waited += 1
	if not _anim_started and not _move_landed:
		print("HARNESS: TRIGGER NEVER FIRED after %d frames -- the move never "
				% waited + "executed. Nothing captured.")
		# ⚠️ Names what DID animate. Before the id check this was the silent
		# case that produced mislabelled PNGs; now it is a loud one that says
		# exactly which move ran instead.
		if not _foreign_anims.is_empty():
			print("HARNESS: but move(s) %s DID animate -- the forced move %d "
					% [str(_foreign_anims), _move_id]
					+ "did not. Nothing was captured rather than capturing "
					+ "the wrong move.")
		get_tree().quit(1)
		return
	print("HARNESS: triggered after %d frames (%s)" % [waited,
			"anim_script_started" if _anim_started
			else "move_executed fallback"])
	# Not a failure -- the opponent animating too is normal -- but worth saying,
	# because it is the condition under which the old bug produced wrong shots.
	if not _foreign_anims.is_empty():
		print("HARNESS: (other move(s) %s also animated this turn; shots are "
				% str(_foreign_anims) + "gated on move %d)" % _move_id)

	# Capture across the animation window from the moment it began.
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

	# [bg probe] Report the anim background layer's real geometry vs the
	# viewport, so "the background does not fill the screen" becomes a
	# measurement rather than an impression.
	var eff = _screen.get("_effect_layer")
	var stage_root: Control = eff.get_parent() as Control if eff != null else null
	if stage_root != null:
		var bg := stage_root.get_node_or_null("AnimBackgroundLayer") as TextureRect
		print("BGPROBE: stage_root=%s rect=%s" % [stage_root.name,
				str(stage_root.get_global_rect())])
		if bg != null:
			print("BGPROBE: visible=%s rect=%s tex=%s stretch=%d viewport=%s"
					% [str(bg.visible), str(bg.get_global_rect()),
						str(bg.texture.get_size()) if bg.texture != null else "<none>",
						bg.stretch_mode, str(get_viewport().get_visible_rect().size)])
		else:
			print("BGPROBE: no AnimBackgroundLayer child")
			for c in stage_root.get_children():
				if c is Control:
					var r: Rect2 = (c as Control).get_global_rect()
					print("   child: %-22s idx=%d y=%.0f..%.0f (%.0f%%..%.0f%%)"
							% [c.name, c.get_index(), r.position.y, r.end.y,
								100.0 * r.position.y / 768.0, 100.0 * r.end.y / 768.0])
	else:
		print("BGPROBE: no effect layer / stage root")
	_report_opponent_side("AFTER move")
	if _anim_frames > 0:
		print("HARNESS: animation ran %d GBA frames; captured %d shots every "
				% [_anim_frames, _saved]
				+ "%d process frames" % _frames_between)
	print("HARNESS: saved %d/%d shots to %s"
			% [_saved, _shot_count, ProjectSettings.globalize_path(SHOT_DIR)])
	get_tree().quit(0 if _saved > 0 else 1)
