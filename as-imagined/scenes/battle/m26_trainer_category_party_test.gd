extends Node

# [M26l/M26q-1/M26o] Regression suite for the 3 combined M26 UI additions:
# trainer-intro portrait banner, Fight-screen move-category icon, and the
# compact 6-pokéball party status row. Bare off-tree BattleScreenShared instances
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
	_test_battle_setup_context_trainer_id_round_trip()
	_test_battle_manager_get_trainer_data_round_trip()
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
	bs._trainer_sprite = TextureRect.new()
	bs._trainer_sprite.visible = false
	await bs._show_trainer_intro(null)
	_chk("null trainer leaves the sprite hidden (early-return before anything)",
			not bs._trainer_sprite.visible)
	_chk("null trainer sets no texture", bs._trainer_sprite.texture == null)


func _test_show_trainer_intro_sets_sprite_texture_when_not_in_tree() -> void:
	var bs := BattleScreenShared.new()
	bs._trainer_sprite = TextureRect.new()
	bs._trainer_sprite.visible = false
	var trainer := TrainerRegistry.get_trainer_by_key("TRAINER_BRAWLY_1")
	_chk("fixture trainer resolves", trainer != null)
	await bs._show_trainer_intro(trainer)
	_chk("real trainer sets the sprite texture", bs._trainer_sprite.texture != null)
	_chk("sprite stays hidden on the not-in-tree bypass (no tween possible)",
			not bs._trainer_sprite.visible)


# The sprite must occupy the SAME battlefield slot as the opponent mon -- this
# is the core of what B3-2 corrected, so it gets a direct geometry assertion
# rather than being left to a screenshot.
func _test_trainer_sprite_shares_opponent_mon_geometry() -> void:
	for scene_path in ["res://scenes/battle/battle_screen_singles.tscn",
			"res://scenes/battle/battle_screen_doubles.tscn"]:
		var packed: PackedScene = load(scene_path)
		var root: Node = packed.instantiate()
		var trainer: Control = root.get_node_or_null("BattleStage/TrainerSprite")
		var mon: Control = root.get_node_or_null("BattleStage/OpponentSprite0")
		var label := scene_path.get_file()
		_chk("%s has a TrainerSprite" % label, trainer != null)
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

func _test_battle_setup_context_trainer_id_round_trip() -> void:
	_chk("default opp_trainer_id is -1 (every pre-existing caller's implicit value)",
			BattleSetupContext.opp_trainer_id == -1)
	var p1 := _party_of([_make_mon("P1")])
	var p2 := _party_of([_make_mon("P2")])
	BattleSetupContext.set_pending(p1, p2, false, "", 80)
	_chk("set_pending threads the trainer id through", BattleSetupContext.opp_trainer_id == 80)
	BattleSetupContext.clear()
	_chk("clear() resets opp_trainer_id back to -1", BattleSetupContext.opp_trainer_id == -1)
	# Every pre-M26l caller never passes the 5th arg at all -- confirm that
	# omission still defaults safely rather than requiring a call-site change.
	BattleSetupContext.set_pending(p1, p2, false, "")
	_chk("omitting the 5th arg still defaults to -1", BattleSetupContext.opp_trainer_id == -1)
	BattleSetupContext.clear()


func _test_battle_manager_get_trainer_data_round_trip() -> void:
	var bm := BattleManager.new()
	_chk("no trainer attached by default", bm.get_trainer_data(1) == null)
	var trainer := TrainerRegistry.get_trainer_by_key("TRAINER_BRAWLY_1")
	bm.set_trainer_data(1, trainer)
	_chk("get_trainer_data reads back exactly what set_trainer_data attached",
			bm.get_trainer_data(1) == trainer)
	_chk("the other side is untouched", bm.get_trainer_data(0) == null)


func _test_real_trainer_and_portrait_pipeline_resolves() -> void:
	# The exact chain _ready()/_show_trainer_intro() drive for a real
	# opp_trainer_id: BattleSetupContext id -> TrainerRegistry.get_trainer()
	# -> TrainerPicRegistry.get_portrait_texture(trainer.trainer_pic_id).
	var trainer := TrainerRegistry.get_trainer(80)
	_chk("trainer id 80 resolves to Brawly", trainer != null and trainer.trainer_key == "TRAINER_BRAWLY_1")
	var portrait := TrainerPicRegistry.get_portrait_texture(trainer.trainer_pic_id)
	_chk("Brawly's own trainer_pic_id resolves to a real portrait texture", portrait != null)
	_chk("portrait is the real 64x64 mugshot size", portrait.get_size() == Vector2(64, 64))
