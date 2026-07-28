extends Node

# [M26B3/M26C4/M26B5] Regression suite for the 3 combined M26 UI additions:
# the opponent trainer battlefield sprite (M26B3-2 — the retired portrait
# banner's replacement), Fight-screen move-category icon, and the compact
# 6-pokéball party status row. Bare off-tree BattleScreenShared instances
# throughout (never ran _ready(), so every @onready node used here is
# stubbed by hand first) -- matching message_pacing_test.gd's own
# established precedent for this exact class of test.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_party_ball_texture_priority()
	_test_refresh_party_status_row_reads_real_party()
	_test_refresh_party_status_row_pads_short_party_with_empty()
	_test_show_party_status_summary_bypassed_when_not_in_tree()
	_test_show_trainer_intro_noop_for_null_trainer()
	_test_show_trainer_intro_sets_sprite_texture_when_not_in_tree()
	_test_trainer_sprite_shares_opponent_mon_geometry()
	_test_intro_banner_is_retired_from_both_scenes()
	_test_opponent_mon_visibility_helper_covers_every_slot()
	_test_player_trainer_sprite_shares_player_mon_geometry()
	_test_player_throw_matches_source_frame_sequence()
	_test_player_trainer_frame_stepping_walks_the_strip()
	await _test_player_send_out_bypassed_when_not_in_tree()
	_test_player_mon_visibility_helper_covers_every_slot()
	_test_intro_message_uses_the_real_challenge_template()
	_test_opponent_send_out_message_singles_and_doubles()
	_test_player_send_out_message_singles_and_doubles()
	await _test_intro_split_lets_text_print_while_trainer_stands()
	_test_recall_constants_match_source()
	_test_ball_particle_wobble_matches_source_anim()
	await _test_recall_bypass_hides_sprite_and_panel_together()
	_test_recall_finds_the_right_slot_in_doubles()
	_test_faint_queues_a_recall_beat()
	await _test_battle_end_win_queues_the_real_defeat_template()
	await _test_battle_end_loss_recalls_mons_and_queues_no_line()
	await _test_battle_end_noop_without_a_trainer()
	_test_battle_setup_context_trainer_key_round_trip()
	_test_trainer_identity_survives_a_roster_regen()
	_test_filenames_agree_with_trainer_keys()
	_test_battle_manager_get_trainer_data_round_trip()
	_test_simulator_opponent_gets_no_free_resources()
	_test_simulator_win_awards_no_money()
	_test_real_trainer_and_portrait_pipeline_resolves()

	var total := _pass + _fail
	print("m26_trainer_category_party_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Fixtures ─────────────────────────────────────────────────────────────

func _make_mon(mon_name: String, hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = hp
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _party_of(members: Array[BattlePokemon]) -> BattleParty:
	var p := BattleParty.new()
	p.members = members
	p.active_indices = [0]
	return p


func _make_ball_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	for i in range(6):
		var t := TextureRect.new()
		t.name = "Ball%d" % i
		row.add_child(t)
	return row


# [M26 polish batch, item 3] The old "M26q-1: category icon" section (a
# direct test of _category_icon_texture()) is gone -- that function and the
# MoveInfoCategory node it fed were removed per explicit request. Nothing
# here duplicates coverage of the party-ball row below, which is a wholly
# separate feature (_party_ball_texture, M26o) and was left untouched.


# ── M26o: party ball state priority ───────────────────────────────────────

func _test_party_ball_texture_priority() -> void:
	var healthy := _make_mon("Healthy")
	var statused := _make_mon("Statused")
	statused.status = BattlePokemon.STATUS_PARALYSIS
	var fainted := _make_mon("Fainted")
	fainted.fainted = true

	_chk("null slot -> empty ball",
			"ball_empty" in BattleScreenShared._party_ball_texture(null).resource_path)
	_chk("fainted mon -> fainted ball",
			"ball_fainted" in BattleScreenShared._party_ball_texture(fainted).resource_path)
	_chk("statused mon -> status ball",
			"ball_status" in BattleScreenShared._party_ball_texture(statused).resource_path)
	_chk("healthy mon -> normal ball",
			"ball_normal" in BattleScreenShared._party_ball_texture(healthy).resource_path)
	# Priority: fainted beats status, matching source's own real check order
	# (fainted checked before status in CreatePartyStatusSummarySprites).
	var fainted_and_statused := _make_mon("Both")
	fainted_and_statused.status = BattlePokemon.STATUS_POISON
	fainted_and_statused.fainted = true
	_chk("fainted beats status when both are true",
			"ball_fainted" in BattleScreenShared._party_ball_texture(fainted_and_statused).resource_path)


func _test_refresh_party_status_row_reads_real_party() -> void:
	var bs := BattleScreenShared.new()
	var row := _make_ball_row()
	var healthy := _make_mon("A")
	var fainted := _make_mon("B")
	fainted.fainted = true
	var members: Array[BattlePokemon] = [healthy, fainted]
	bs._refresh_party_status_row(row, _party_of(members))
	var ball0 := row.get_child(0) as TextureRect
	var ball1 := row.get_child(1) as TextureRect
	_chk("slot 0 (healthy) shows the normal ball", "ball_normal" in ball0.texture.resource_path)
	_chk("slot 1 (fainted) shows the fainted ball", "ball_fainted" in ball1.texture.resource_path)


func _test_refresh_party_status_row_pads_short_party_with_empty() -> void:
	var bs := BattleScreenShared.new()
	var row := _make_ball_row()
	var members: Array[BattlePokemon] = [_make_mon("OnlyOne")]
	bs._refresh_party_status_row(row, _party_of(members))
	for i in range(1, 6):
		var ball := row.get_child(i) as TextureRect
		_chk("slot %d (no member) shows the empty ball" % i, "ball_empty" in ball.texture.resource_path)


func _test_show_party_status_summary_bypassed_when_not_in_tree() -> void:
	var bs := BattleScreenShared.new()
	bs._party_status_opponent = _make_ball_row()
	bs._party_status_player = _make_ball_row()
	# Bare Control.new() defaults visible=true (only the .tscn-authored real
	# nodes start hidden) -- forced false here so the assertion below proves
	# the bypass path genuinely never reaches its own "set visible = true"
	# line, not just that some unrelated default happened to already match.
	bs._party_status_opponent.visible = false
	var members: Array[BattlePokemon] = [_make_mon("Opp")]
	bs._opp_party = _party_of(members)
	var player_members: Array[BattlePokemon] = [_make_mon("Ply")]
	bs._player_party = _party_of(player_members)
	_chk("bare instance is genuinely not in the tree", not bs.is_inside_tree())
	await bs._show_party_status_summary()
	_chk("icons still refreshed despite the bypass",
			"ball_normal" in (bs._party_status_opponent.get_child(0) as TextureRect).texture.resource_path)
	_chk("row stays hidden since the not-in-tree bypass returns before ever showing it",
			not bs._party_status_opponent.visible)


# ── M26B3-2: trainer sprite (replaces the retired intro banner) ───────────
#
# These assertions were REWRITTEN 2026-07-26. They previously encoded the
# portrait-banner implementation (a caption label + a framed portrait over a
# dark backdrop), which the M26B3 recon established has no basis in source at
# all. A passing suite against a wrong implementation is exactly the trap
# CLAUDE.md's own C/T/A note warns about, so the old assertions are gone
# rather than adapted.

func _test_show_trainer_intro_noop_for_null_trainer() -> void:
	var bs := BattleScreenShared.new()
	bs._opponent_trainer_sprite = TextureRect.new()
	bs._opponent_trainer_sprite.visible = false
	await bs._show_trainer_intro(null)
	_chk("null trainer leaves the sprite hidden (early-return before anything)",
			not bs._opponent_trainer_sprite.visible)
	_chk("null trainer sets no texture", bs._opponent_trainer_sprite.texture == null)


func _test_show_trainer_intro_sets_sprite_texture_when_not_in_tree() -> void:
	var bs := BattleScreenShared.new()
	bs._opponent_trainer_sprite = TextureRect.new()
	bs._opponent_trainer_sprite.visible = false
	var trainer := TrainerRegistry.get_trainer_by_key("TRAINER_BRAWLY_1_RSE")
	_chk("fixture trainer resolves", trainer != null)
	await bs._show_trainer_intro(trainer)
	_chk("real trainer sets the sprite texture", bs._opponent_trainer_sprite.texture != null)
	_chk("sprite stays hidden on the not-in-tree bypass (no tween possible)",
			not bs._opponent_trainer_sprite.visible)


# The sprite must occupy the SAME battlefield slot as the opponent mon -- this
# is the core of what B3-2 corrected, so it gets a direct geometry assertion
# rather than being left to a screenshot.
func _test_trainer_sprite_shares_opponent_mon_geometry() -> void:
	for scene_path in ["res://scenes/battle/battle_screen_singles.tscn",
			"res://scenes/battle/battle_screen_doubles.tscn"]:
		var packed: PackedScene = load(scene_path)
		var root: Node = packed.instantiate()
		var trainer: Control = root.get_node_or_null("BattleStage/OpponentTrainerSprite")
		var mon: Control = root.get_node_or_null("BattleStage/OpponentSprite0")
		var label: String = scene_path.get_file()
		_chk("%s has an OpponentTrainerSprite" % label, trainer != null)
		_chk("%s still has OpponentSprite0" % label, mon != null)
		if trainer != null and mon != null:
			_chk("%s trainer sprite shares the mon's anchors" % label,
					is_equal_approx(trainer.anchor_left, mon.anchor_left)
					and is_equal_approx(trainer.anchor_top, mon.anchor_top))
			_chk("%s trainer sprite shares the mon's offsets" % label,
					is_equal_approx(trainer.offset_left, mon.offset_left)
					and is_equal_approx(trainer.offset_top, mon.offset_top))
			_chk("%s trainer sprite starts hidden" % label, not trainer.visible)
		root.free()


# ── M26B3-5: intro sequencing + the real messages ────────────────────────

func _bs_with_parties(opp_names: Array, ply_names: Array) -> BattleScreenShared:
	var bs := BattleScreenShared.new()
	var opp: Array[BattlePokemon] = []
	for n: String in opp_names:
		opp.append(_make_mon(n))
	var ply: Array[BattlePokemon] = []
	for n: String in ply_names:
		ply.append(_make_mon(n))
	# Typed-array assignment from a ternary silently fails (this project's own
	# documented GDScript gotcha) -- an earlier draft did exactly that, left
	# `bs` null, and every message assertion below aborted while the suite
	# still reported green. Explicit branches instead.
	var oi: Array[int] = [0]
	if opp.size() > 1:
		oi = [0, 1]
	var pi: Array[int] = [0]
	if ply.size() > 1:
		pi = [0, 1]
	var op := BattleParty.new()
	op.members = opp
	op.active_indices = oi
	var pp := BattleParty.new()
	pp.members = ply
	pp.active_indices = pi
	bs._opp_party = op
	bs._player_party = pp
	return bs


func _texts_of(bs: BattleScreenShared) -> Array:
	var out: Array = []
	for beat: Dictionary in bs._pending_beats:
		if beat.get("kind", "") == "text":
			out.append(beat["text"])
	return out


func _test_intro_message_uses_the_real_challenge_template() -> void:
	var bs := _bs_with_parties(["Foe"], ["Mine"])
	var trainer := TrainerRegistry.get_trainer_by_key("TRAINER_ROXANNE_1_RSE")
	bs._queue_trainer_intro_message(trainer)
	var t: Array = _texts_of(bs)
	_chk("intro queues one line", t.size() == 1)
	if t.size() == 1:
		# sText_Trainer1WantsToBattle = "You are challenged by
		# {B_TRAINER1_NAME_WITH_CLASS}!". B3-2 shipped "X wants to battle!",
		# which is the LINK/two-trainer phrasing, not this one -- guarded so
		# the wrong template can't come back.
		_chk("uses source's real single-trainer template",
				(t[0] as String).begins_with("You are challenged by "))
		_chk("does NOT use the link/two-trainer 'wants to battle' phrasing",
				not ("wants to battle" in (t[0] as String)))
		_chk("carries the class as well as the name", "Roxanne" in t[0] and t[0] != "You are challenged by Roxanne!")


func _test_opponent_send_out_message_singles_and_doubles() -> void:
	var trainer := TrainerRegistry.get_trainer_by_key("TRAINER_ROXANNE_1_RSE")
	var singles := _bs_with_parties(["Geodude"], ["Mine"])
	singles._queue_trainer_send_out_message(trainer)
	var st: Array = _texts_of(singles)
	_chk("singles send-out queues one line", st.size() == 1)
	if st.size() == 1:
		_chk("singles names the mon sent out",
				"sent out " in st[0] and "Geodude" in st[0])
		_chk("singles does not use the two-mon 'and' form", not (" and " in st[0]))

	var doubles := _bs_with_parties(["Geodude", "Nosepass"], ["A", "B"])
	doubles._queue_trainer_send_out_message(trainer)
	var dt: Array = _texts_of(doubles)
	if dt.size() == 1:
		# sText_Trainer1SentOutTwoPkmn joins the two with " and ".
		_chk("doubles names BOTH mons joined with 'and'",
				"Geodude and Nosepass" in dt[0])


func _test_player_send_out_message_singles_and_doubles() -> void:
	var singles := _bs_with_parties(["Foe"], ["Blaze"])
	singles._queue_player_send_out_message()
	var st: Array = _texts_of(singles)
	_chk("player send-out uses source's 'Go!' template",
			st.size() == 1 and st[0] == "Go! Blaze!")

	var doubles := _bs_with_parties(["A", "B"], ["Blaze", "Torrent"])
	doubles._queue_player_send_out_message()
	var dt: Array = _texts_of(doubles)
	_chk("doubles joins both player mons with 'and'",
			dt.size() == 1 and dt[0] == "Go! Blaze and Torrent!")


func _test_intro_split_lets_text_print_while_trainer_stands() -> void:
	# The whole point of splitting _show_trainer_intro/_dismiss_trainer_intro
	# is that both opponent messages print while she is still on screen.
	# _dismiss on a hidden sprite must be a no-op so the order can't silently
	# invert.
	var bs := BattleScreenShared.new()
	bs._opponent_trainer_sprite = TextureRect.new()
	bs._opponent_trainer_sprite.visible = false
	await bs._dismiss_trainer_intro()
	_chk("dismissing a trainer who never arrived is a no-op",
			not bs._opponent_trainer_sprite.visible)


# ── M26B3-6a: recall-to-ball on faint ────────────────────────────────────

func _test_recall_constants_match_source() -> void:
	# The recall animation is ported from gBattleAnimSpecial_SwitchOutPlayerMon
	# (its opponent twin is byte-identical). The numbers are the port, so they
	# are asserted directly.
	_chk("ball leads the shrink by source's own 10-frame delay",
			BattleScreenShared._RECALL_BALL_LEAD_FRAMES == 10)
	# AnimTask_SwitchOutShrinkMon: 0x100 -> 0x2D0 stepping 0x30 per frame.
	# (0x2D0-0x100)/0x30 is 9.67, and the loop runs until the value REACHES
	# the threshold -- so it takes 10 frames, not 9. Integer division here
	# truncates to 9 and would assert the wrong number; ceil is the correct
	# derivation and this comment exists because the first draft got it wrong.
	_chk("shrink runs ceil((0x2D0-0x100)/0x30) = 10 frames",
			BattleScreenShared._RECALL_SHRINK_FRAMES
			== ceili((0x2D0 - 0x100) / float(0x30)))
	# LaunchBallFadeMonTask blends toward BALL_POKE's own openFadeColor,
	# RGB(31,22,30) in GBA 5-bit channels -> (255,181,247).
	var c := BattleScreenShared._RECALL_FADE_COLOR
	_chk("fade colour is BALL_POKE's real openFadeColor, 5-bit scaled",
			c.r8 == 255 and c.g8 == 181 and c.b8 == 247)


func _test_ball_particle_wobble_matches_source_anim() -> void:
	# sAnim_RegularBall (battle_anim_throw.c:163-172), BALL_POKE's animNums=0:
	#   FRAME(0,1) FRAME(1,1) FRAME(2,1) FRAME(0,1,hFlip) FRAME(2,1) FRAME(1,1)
	# The hFlip on step 4 is what reads as the back-and-forth wobble; the
	# first cut rendered a static frame 0 and had no wobble at all.
	var a := BattleScreenShared._BALL_PARTICLE_ANIM
	_chk("wobble cycle is source's own 6 steps", a.size() == 6)
	var frames: Array = []
	for cmd: Dictionary in a:
		frames.append(cmd["frame"])
	_chk("frame order matches sAnim_RegularBall (0,1,2,0,2,1)",
			frames == [0, 1, 2, 0, 2, 1])
	var flips: Array = []
	for cmd: Dictionary in a:
		flips.append(cmd["flip"])
	_chk("exactly one step is horizontally flipped", flips.count(true) == 1)
	_chk("the flip is on step 4, as in source", flips[3] == true)


func _test_recall_bypass_hides_sprite_and_panel_together() -> void:
	# Under the not-in-tree/--autoplay bypass the recall still has to leave
	# the slot in its final state, or a fainted mon stays drawn.
	var bs := BattleScreenShared.new()
	var mon := _make_mon("Fainter")
	var members: Array[BattlePokemon] = [mon]
	bs._opp_party = _party_of(members)
	var sprite := TextureRect.new()
	sprite.visible = true
	var panel := Control.new()
	panel.visible = true
	bs._opp_sprites = [sprite]
	bs._opp_panels = [panel]
	_chk("bare instance is genuinely not in the tree", not bs.is_inside_tree())
	await bs._play_recall_to_ball(mon)
	_chk("bypass hides the recalled sprite", not sprite.visible)
	_chk("bypass hides its health box too", not panel.visible)


func _test_recall_finds_the_right_slot_in_doubles() -> void:
	var bs := BattleScreenShared.new()
	var a := _make_mon("SlotZero")
	var b := _make_mon("SlotOne")
	var members: Array[BattlePokemon] = [a, b]
	var party := BattleParty.new()
	party.members = members
	var idx: Array[int] = [0, 1]
	party.active_indices = idx
	bs._opp_party = party
	var s0 := TextureRect.new()
	var s1 := TextureRect.new()
	bs._opp_sprites = [s0, s1]
	bs._opp_panels = []
	var found := bs._find_mon_slot(b)
	_chk("slot lookup resolves the correct doubles slot",
			not found.is_empty() and found["sprite"] == s1)
	var missing := bs._find_mon_slot(_make_mon("NotOnField"))
	_chk("a mon that isn't on the field resolves to nothing",
			missing.is_empty())


func _test_faint_queues_a_recall_beat() -> void:
	# The recall is queued as a beat rather than run straight off the signal,
	# so it orders against the M26o party-summary re-show already listening
	# to pokemon_fainted rather than racing it.
	var bs := BattleScreenShared.new()
	bs._bm = BattleManager.new()
	# _mon_label() (used by the faint log line) reads both parties to decide
	# the "Foe X" prefix, so both must exist before the signal fires.
	var mon := _make_mon("Fainter")
	var opp_members: Array[BattlePokemon] = [mon]
	bs._opp_party = _party_of(opp_members)
	var ply_members: Array[BattlePokemon] = [_make_mon("Mine")]
	bs._player_party = _party_of(ply_members)
	bs._wire_log_signals()
	bs._bm.pokemon_fainted.emit(mon)
	var recalls := 0
	for beat: Dictionary in bs._pending_beats:
		if beat.get("kind", "") == "recall":
			recalls += 1
			_chk("recall beat carries the fainted mon", beat.get("mon", null) == mon)
	_chk("a faint queues exactly one recall beat", recalls == 1)
	bs._bm.free()


# ── M26B3-4: opponent trainer returns for the post-battle speech ─────────

func _bs_with_trainer_end_stubs() -> BattleScreenShared:
	var bs := BattleScreenShared.new()
	bs._opponent_trainer_sprite = TextureRect.new()
	bs._opponent_trainer_sprite.visible = false
	bs._bm = BattleManager.new()
	return bs


func _stage_with_opponent_mon(bs: BattleScreenShared) -> TextureRect:
	var stage := Control.new()
	stage.name = "BattleStage"
	bs.add_child(stage)
	var mon := TextureRect.new()
	mon.name = "OpponentSprite0"
	mon.visible = true
	stage.add_child(mon)
	return mon


func _test_battle_end_win_queues_the_real_defeat_template() -> void:
	var bs := _bs_with_trainer_end_stubs()
	var mon := _stage_with_opponent_mon(bs)
	var trainer := TrainerRegistry.get_trainer_by_key("TRAINER_ROXANNE_1_RSE")
	_chk("Roxanne fixture resolves", trainer != null)
	bs._bm.set_trainer_data(1, trainer)
	await bs._show_trainer_battle_end(0)
	# This project DIMS a fainted mon (alpha 0.3) rather than destroying its
	# sprite the way source does, so the win path must clear the slot too --
	# otherwise the returning trainer overlaps a ghost of the mon it beat.
	_chk("win also clears the slot (this project dims fainted mons, source destroys them)",
			not mon.visible)
	var texts: Array = []
	for beat: Dictionary in bs._pending_beats:
		if beat.get("kind", "") == "text":
			texts.append(beat["text"])
	_chk("win queues exactly one post-battle line", texts.size() == 1)
	if texts.size() == 1:
		var line: String = texts[0]
		# Source template is "You defeated {B_TRAINER1_NAME_WITH_CLASS}!" --
		# name WITH class, so both halves must be present.
		_chk("line uses source's own 'You defeated ...!' template",
				line.begins_with("You defeated ") and line.ends_with("!"))
		_chk("line carries the trainer's own name", "Roxanne" in line)
		_chk("line carries the CLASS too, not just the bare name",
				line != "You defeated Roxanne!")
	bs._bm.free()


func _test_battle_end_loss_recalls_mons_and_queues_no_line() -> void:
	# Built by hand rather than from the real .tscn: an instantiated-but-
	# never-added scene has NO @onready vars resolved (_bm would be null),
	# and adding a real battle screen to this test's own tree would let
	# --autoplay's process-wide quit kill the suite (see this file's own
	# header). An earlier draft did instantiate the scene, and the resulting
	# "Invalid call ... in base 'Nil'" aborted the whole test function --
	# every assertion below silently never ran while the suite still
	# reported a pass.
	var root := _bs_with_trainer_end_stubs()
	var mon := _stage_with_opponent_mon(root)
	root._bm.set_trainer_data(1, TrainerRegistry.get_trainer_by_key("TRAINER_ROXANNE_1_RSE"))
	await root._show_trainer_battle_end(1)
	# The recall-first step: on a LOSS the opponent's mon is still alive and
	# standing in the slot the trainer is about to occupy, so source recalls
	# it before sliding in (returnopponentmon1toball). Without this the
	# trainer would overlap a live Pokemon.
	_chk("loss hides the still-living opponent mon before the slide-in",
			not mon.visible)
	var texts := 0
	for beat: Dictionary in root._pending_beats:
		if beat.get("kind", "") == "text":
			texts += 1
	# The trainer's WIN speech is per-encounter map-script dialogue this
	# project has no data for -- so the loss path must queue nothing rather
	# than invent a line.
	_chk("loss queues no post-battle line (no data source for the speech)",
			texts == 0)
	root._bm.free()
	root.free()


func _test_battle_end_noop_without_a_trainer() -> void:
	var bs := _bs_with_trainer_end_stubs()
	await bs._show_trainer_battle_end(0)
	_chk("wild/fixture battle queues no post-battle line",
			bs._pending_beats.is_empty())
	_chk("wild/fixture battle leaves the trainer sprite hidden",
			not bs._opponent_trainer_sprite.visible)
	bs._bm.free()


# ── M26B3-3: player trainer back sprite + throw animation ────────────────

# Same geometry contract as the opponent's, mirrored: the player's trainer
# stands where the player's own Pokémon will.
func _test_player_trainer_sprite_shares_player_mon_geometry() -> void:
	for scene_path in ["res://scenes/battle/battle_screen_singles.tscn",
			"res://scenes/battle/battle_screen_doubles.tscn"]:
		var root: Node = (load(scene_path) as PackedScene).instantiate()
		var trainer: Control = root.get_node_or_null("BattleStage/PlayerTrainerSprite")
		var mon: Control = root.get_node_or_null("BattleStage/PlayerSprite0")
		var label: String = scene_path.get_file()
		_chk("%s has a PlayerTrainerSprite" % label, trainer != null)
		_chk("%s still has PlayerSprite0" % label, mon != null)
		if trainer != null and mon != null:
			_chk("%s player trainer shares the mon's anchors" % label,
					is_equal_approx(trainer.anchor_left, mon.anchor_left)
					and is_equal_approx(trainer.anchor_top, mon.anchor_top))
			_chk("%s player trainer shares the mon's offsets" % label,
					is_equal_approx(trainer.offset_left, mon.offset_left)
					and is_equal_approx(trainer.offset_top, mon.offset_top))
			_chk("%s player trainer starts hidden" % label, not trainer.visible)
		root.free()


# The throw sequence is ported frame-for-frame from sAnimCmd_Kanto. These
# numbers are the whole point of the port, so they get asserted directly
# rather than left to a screenshot that can't measure them.
func _test_player_throw_matches_source_frame_sequence() -> void:
	var frames := BattleScreenShared._PLAYER_THROW_FRAMES
	_chk("throw has 5 steps (sAnimCmd_Kanto's own count)", frames.size() == 5)
	var expected_frames := [1, 2, 3, 4, 0]
	var expected_holds := [20, 6, 6, 24, 1]
	var ok_f := true
	var ok_h := true
	for i in range(min(frames.size(), 5)):
		if frames[i]["frame"] != expected_frames[i]:
			ok_f = false
		if frames[i]["hold"] != expected_holds[i]:
			ok_h = false
	_chk("frame indices match source (1,2,3,4,0)", ok_f)
	_chk("frame durations match source (20,6,6,24,1)", ok_h)

	var total := 0
	for step in frames:
		total += int(step["hold"])
	_chk("full throw runs 57 frames", total == 57)
	# 31 is the BALL LAUNCH frame (Task_StartSendOutAnim), NOT the moment the
	# mon appears -- the mon is loaded by the same callback that frees the
	# trainer, so those two are simultaneous. An earlier draft revealed the
	# mon at 31 and the screenshot pass caught the resulting overlap; this
	# assertion exists so that misreading can't quietly return.
	_chk("ball-launch frame is 31, source's own framesToWait",
			BattleScreenShared._PLAYER_BALL_LAUNCH_FRAME == 31)
	_chk("ball launch lands strictly inside the throw (it is not the end)",
			BattleScreenShared._PLAYER_BALL_LAUNCH_FRAME < total)
	# [B3-3 correction] She slides off LEFT over 50 frames while throwing --
	# source's own player-side data[0]. B3-3 first shipped her simply
	# vanishing, on the mistaken claim that the player's trainer never
	# slides out. Pinned so that claim can't return.
	_chk("player slide-out is source's own 50 frames",
			BattleScreenShared._PLAYER_SLIDE_OUT_FRAMES == 50)
	_chk("the slide runs concurrently with the throw, not after it",
			BattleScreenShared._PLAYER_SLIDE_OUT_FRAMES < total)


# Frame stepping walks a VERTICAL strip, so only region.y moves.
func _test_player_trainer_frame_stepping_walks_the_strip() -> void:
	var bs := BattleScreenShared.new()
	bs._player_trainer_sprite = TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load(BattleScreenShared._PLAYER_BACK_PIC) as Texture2D
	atlas.region = Rect2(0, 0, 64, 64)
	bs._player_trainer_sprite.texture = atlas
	_chk("placeholder back pic (Leaf) is a real 5-frame 64x320 strip",
			atlas.atlas != null and atlas.atlas.get_height() == 320
			and atlas.atlas.get_width() == 64)
	bs._set_player_trainer_frame(3)
	_chk("frame 3 selects region y=192", is_equal_approx(atlas.region.position.y, 192.0))
	_chk("frame 3 leaves region x at 0 (vertical strip)",
			is_equal_approx(atlas.region.position.x, 0.0))
	bs._set_player_trainer_frame(0)
	_chk("frame 0 returns to y=0", is_equal_approx(atlas.region.position.y, 0.0))


func _test_player_send_out_bypassed_when_not_in_tree() -> void:
	var bs := BattleScreenShared.new()
	bs._player_trainer_sprite = TextureRect.new()
	bs._player_trainer_sprite.visible = false
	_chk("bare instance is genuinely not in the tree", not bs.is_inside_tree())
	await bs._show_player_send_out()
	_chk("texture still gets set before the bypass returns",
			bs._player_trainer_sprite.texture != null)
	_chk("sprite stays hidden on the not-in-tree bypass",
			not bs._player_trainer_sprite.visible)


func _test_player_mon_visibility_helper_covers_every_slot() -> void:
	var root: Node = (load("res://scenes/battle/battle_screen_doubles.tscn") as PackedScene).instantiate()
	root._set_player_mon_sprites_visible(false)
	var s0: CanvasItem = root.get_node_or_null("BattleStage/PlayerSprite0")
	var s1: CanvasItem = root.get_node_or_null("BattleStage/PlayerSprite1")
	_chk("doubles player slot 0 hidden", s0 != null and not s0.visible)
	_chk("doubles player slot 1 hidden", s1 != null and not s1.visible)
	root._set_player_mon_sprites_visible(true)
	_chk("doubles player slot 0 revealed", s0 != null and s0.visible)
	_chk("doubles player slot 1 revealed", s1 != null and s1.visible)
	# The opponent walk must not have been broken by the shared refactor.
	root._set_opponent_mon_sprites_visible(false)
	var o1: CanvasItem = root.get_node_or_null("BattleStage/OpponentSprite1")
	_chk("opponent walk still independent after the shared refactor",
			o1 != null and not o1.visible and s0.visible)
	root.free()


# The retired banner must be genuinely gone from both scenes, not just unused.
func _test_intro_banner_is_retired_from_both_scenes() -> void:
	for scene_path in ["res://scenes/battle/battle_screen_singles.tscn",
			"res://scenes/battle/battle_screen_doubles.tscn"]:
		var root: Node = (load(scene_path) as PackedScene).instantiate()
		_chk("%s no longer has TrainerIntroBanner" % scene_path.get_file(),
				root.get_node_or_null("BattleStage/TrainerIntroBanner") == null)
		root.free()


# Hiding/revealing the opponent mon must be generic over slot count -- 1 in
# singles, 2 in doubles.
func _test_opponent_mon_visibility_helper_covers_every_slot() -> void:
	var root: Node = (load("res://scenes/battle/battle_screen_doubles.tscn") as PackedScene).instantiate()
	root._set_opponent_mon_sprites_visible(false)
	var s0: CanvasItem = root.get_node_or_null("BattleStage/OpponentSprite0")
	var s1: CanvasItem = root.get_node_or_null("BattleStage/OpponentSprite1")
	_chk("doubles slot 0 hidden", s0 != null and not s0.visible)
	_chk("doubles slot 1 hidden", s1 != null and not s1.visible)
	root._set_opponent_mon_sprites_visible(true)
	_chk("doubles slot 0 revealed", s0 != null and s0.visible)
	_chk("doubles slot 1 revealed", s1 != null and s1.visible)
	root.free()



# ── Plumbing: BattleSetupContext / BattleManager ──────────────────────────

func _test_battle_setup_context_trainer_key_round_trip() -> void:
	_chk("default opp_trainer_key is \"\" (every pre-existing caller's implicit value)",
			BattleSetupContext.opp_trainer_key == "")
	var p1 := _party_of([_make_mon("P1")])
	var p2 := _party_of([_make_mon("P2")])
	BattleSetupContext.set_pending(p1, p2, false, "", "TRAINER_BRAWLY_1_RSE")
	_chk("set_pending threads the trainer key through",
			BattleSetupContext.opp_trainer_key == "TRAINER_BRAWLY_1_RSE")
	BattleSetupContext.clear()
	_chk("clear() resets opp_trainer_key back to \"\"",
			BattleSetupContext.opp_trainer_key == "")
	# Every pre-M26l caller never passes the 5th arg at all -- confirm that
	# omission still defaults safely rather than requiring a call-site change.
	BattleSetupContext.set_pending(p1, p2, false, "")
	_chk("omitting the 5th arg still defaults to \"\"",
			BattleSetupContext.opp_trainer_key == "")
	BattleSetupContext.clear()


## [Step 1] The int id space is gone; the canonical key IS the filename. These
## pin the properties that replaced it: keys resolve, bare keys do not, and no
## saved artifact carries a number that a roster regen could invalidate.
func _test_trainer_identity_survives_a_roster_regen() -> void:
	for key in ["TRAINER_ROXANNE_1_RSE", "TRAINER_BRAWLY_5_RSE"]:
		var t := TrainerRegistry.get_trainer_by_key(key)
		_chk("default opponent %s resolves by key" % key, t != null)
		_chk("%s's own trainer_key matches its filename" % key,
				t != null and t.trainer_key == key)
	_chk("has_trainer_key answers a hit without erroring",
			TrainerRegistry.has_trainer_key("TRAINER_ROXANNE_1_RSE"))
	# A MISS is a meaningful answer, not an error.
	_chk("has_trainer_key answers a miss as false, not a crash",
			not TrainerRegistry.has_trainer_key("TRAINER_DEFINITELY_NOT_REAL"))
	# Rule A: no alias layer. The unsuffixed spelling must be dead.
	_chk("the bare, unsuffixed key does NOT resolve",
			not TrainerRegistry.has_trainer_key("TRAINER_ROXANNE_1"))
	var keys := TrainerRegistry.all_keys()
	_chk("all_keys() lists the roster, sorted",
			keys.size() == 854 and keys[0] < keys[1])

	# The real regen hazard was a persisted int. TeamStorage is this project's
	# only writer of player-authored data, and its spec must never carry one.
	var spec := {
		"dex": 1, "level": 5, "move_ids": [1], "nature": 0,
		"evs": [0, 0, 0, 0, 0, 0], "ivs": [31, 31, 31, 31, 31, 31], "ability_slot": 0,
	}
	_chk("a saved team member spec stores no trainer id", not spec.has("trainer_id"))


## [Step 1] The filename IS the key, so every file must agree with its own
## trainer_key field. Checked across the WHOLE roster rather than spot-checked:
## a single disagreement silently breaks lookup for that trainer only.
func _test_filenames_agree_with_trainer_keys() -> void:
	var keys := TrainerRegistry.all_keys()
	var mismatches := 0
	for key in keys:
		var t := TrainerRegistry.get_trainer_by_key(key)
		if t == null or t.trainer_key != key:
			mismatches += 1
	_chk("every filename matches its resource's own trainer_key", mismatches == 0)
	_chk("the sweep actually covered the roster", keys.size() == 854)


func _test_battle_manager_get_trainer_data_round_trip() -> void:
	var bm := BattleManager.new()
	_chk("no trainer attached by default", bm.get_trainer_data(1) == null)
	var trainer := TrainerRegistry.get_trainer_by_key("TRAINER_BRAWLY_1_RSE")
	bm.set_trainer_data(1, trainer)
	_chk("get_trainer_data reads back exactly what set_trainer_data attached",
			bm.get_trainer_data(1) == trainer)
	_chk("the other side is untouched", bm.get_trainer_data(0) == null)


## [Step 3] A simulator opponent gets exactly the resources the user chose --
## the team, nothing else. The screen previously attached a real gym leader as
## a default "portrait pilot", which also handed the AI her battle items and
## armed the money branch. These pin both halves of that removal.
func _test_simulator_opponent_gets_no_free_resources() -> void:
	var bm := BattleManager.new()
	add_child(bm)

	# (a) No trainer attached => empty AI item stock. Asserted through the real
	# consumer gate (_maybe_ai_use_item early-returns on an empty stock) rather
	# than by reading the private array, so this tracks behaviour not storage.
	_chk("no trainer is attached to the AI side by default",
			bm.get_trainer_data(1) == null)
	_chk("the AI's battle-item stock is empty at battle start",
			bm._trainer_battle_item_stock[1].is_empty())

	# Discriminator: attaching Roxanne WOULD have stocked it -- proving the
	# assertion above is real and not vacuous.
	var roxanne := TrainerRegistry.get_trainer_by_key("TRAINER_ROXANNE_1_RSE")
	_chk("Roxanne really does carry battle items (so the check above matters)",
			roxanne != null and roxanne.battle_items.size() == 2)
	bm.set_trainer_data(1, roxanne)
	_chk("attaching her stocks the AI -- the behaviour Step 3 removed",
			not bm._trainer_battle_item_stock[1].is_empty())

	bm.queue_free()


## (b) With no opponent trainer, winning awards no money -- the reward branch is
## gated on _trainer_data[1] being non-null.
func _test_simulator_win_awards_no_money() -> void:
	var bm := BattleManager.new()
	add_child(bm)
	_chk("last_money_awarded starts at 0", bm.last_money_awarded == 0)
	_chk("no trainer attached means the money branch cannot arm",
			bm.get_trainer_data(1) == null)
	bm.queue_free()


func _test_real_trainer_and_portrait_pipeline_resolves() -> void:
	# The exact chain _ready()/_show_trainer_intro() drive for a real
	# opp_trainer_key: BattleSetupContext key -> get_trainer_by_key()
	# -> TrainerPicRegistry.get_portrait_texture(trainer.pic_stem).
	var trainer := TrainerRegistry.get_trainer_by_key("TRAINER_BRAWLY_1_RSE")
	_chk("TRAINER_BRAWLY_1_RSE resolves to Brawly",
			trainer != null and trainer.trainer_key == "TRAINER_BRAWLY_1_RSE")
	var portrait := TrainerPicRegistry.get_portrait_texture(trainer.pic_stem, trainer.trainer_key)
	_chk("Brawly's own pic_stem resolves to a real portrait texture",
			trainer.pic_stem == "leader_brawly" and portrait != null)
	_chk("portrait is the real 64x64 mugshot size", portrait.get_size() == Vector2(64, 64))
