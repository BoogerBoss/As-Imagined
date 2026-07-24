extends Node

# [M26c-1] Regression suite for the HP/name/level "databox" swap to the
# Emerald UI Pack's own real art (Graphics/UI/Battle/databox_*.png),
# superseding Phase 4b's raw-pokeemerald-decode health-box art, plus the
# new real EXP bar this session adds (singles player only, matching the
# pack's own real scope — see gen_databox_sprites.py's own doc comment).
#
# [Deliberately NOT tested here] Pixel-perfect internal layout (HP-bar/
# name/EXP-tab offsets within each box) — those were measured directly via
# PIL pixel inspection during this session's own Step 0 and are verified
# visually via the mandated real screenshot pass instead, matching this
# project's own established "measure roughly, verify visually, adjust only
# if proven necessary" convention (see e.g. M25h-1's own D1-clearance
# precedent).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_databox_asset_dimensions()
	_test_hp_bar_color_real_sourced_values()
	_test_exp_bar_color_real_sourced_value()
	_test_exp_bar_fraction_unknown_species_returns_zero()
	_test_exp_bar_fraction_level_100_returns_zero()
	_test_exp_bar_fraction_real_species_midpoint()
	_test_exp_bar_fraction_real_species_at_threshold()
	_test_exp_bar_fraction_clamped_non_negative()
	_test_real_scene_structure()
	_test_status_icon_default_preview_texture()
	_test_split_name_level_labels_exist()

	var total := _pass + _fail
	print("m26c1_databox_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── 1. Real pack asset dimensions ────────────────────────────────────────

func _test_databox_asset_dimensions() -> void:
	var player: Texture2D = load("res://assets/sprites/battle_ui/interface/databox_player.png")
	var opponent: Texture2D = load("res://assets/sprites/battle_ui/interface/databox_opponent.png")
	var d_player: Texture2D = load("res://assets/sprites/battle_ui/interface/databox_doubles_player.png")
	var d_opponent: Texture2D = load("res://assets/sprites/battle_ui/interface/databox_doubles_opponent.png")
	_chk("databox_player.png loads", player != null)
	_chk("databox_opponent.png loads", opponent != null)
	_chk("databox_doubles_player.png loads", d_player != null)
	_chk("databox_doubles_opponent.png loads", d_opponent != null)
	if player != null:
		_chk("player box is 260x84 (the taller box, with the EXP ledge)",
				player.get_width() == 260 and player.get_height() == 84)
	if opponent != null:
		_chk("opponent box is 260x62 (no EXP ledge)",
				opponent.get_width() == 260 and opponent.get_height() == 62)
	if d_player != null:
		_chk("doubles player box is 260x62", d_player.get_width() == 260 and d_player.get_height() == 62)
	if d_opponent != null:
		_chk("doubles opponent box is 260x62", d_opponent.get_width() == 260 and d_opponent.get_height() == 62)


# ── 2. HP bar color thresholds — real sourced values, not invented ──────

func _test_hp_bar_color_real_sourced_values() -> void:
	var bs := BattleScreen.new()
	_chk(">50% HP uses the pack's real green highlight (115,255,173)",
			bs._hp_bar_color(51, 100) == Color8(115, 255, 173))
	_chk(">20% (and <=50%) HP uses the pack's real yellow highlight (255,231,57)",
			bs._hp_bar_color(21, 100) == Color8(255, 231, 57))
	_chk("<=20% HP uses the pack's real red highlight (255,90,57)",
			bs._hp_bar_color(20, 100) == Color8(255, 90, 57))
	_chk("max_hp<=0 degrades safely to plain white, not a crash",
			bs._hp_bar_color(0, 0) == Color(1, 1, 1))


# ── 3. EXP bar color — real sourced value ────────────────────────────────

func _test_exp_bar_color_real_sourced_value() -> void:
	_chk("EXP bar tint matches the pack's own real overlay_exp.png color",
			BattleScreen._EXP_BAR_COLOR == Color8(66, 206, 255))


# ── 4-8. _exp_bar_fraction ────────────────────────────────────────────────

func _test_exp_bar_fraction_unknown_species_returns_zero() -> void:
	var bs := BattleScreen.new()
	var sp := PokemonSpecies.new()
	sp.species_name = "Fixture"
	sp.types.append(TypeChart.TYPE_NORMAL)
	sp.base_hp = 100
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	# national_dex_num defaults to 0 -- no real PokemonRegistry entry exists,
	# matching this screen's own hand-built fixture teams exactly.
	_chk("a hand-built fixture mon (dex 0, no real growth-rate data) degrades to an empty bar, not a crash",
			bs._exp_bar_fraction(mon) == 0.0)


func _test_exp_bar_fraction_level_100_returns_zero() -> void:
	var bs := BattleScreen.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 100)  # Bulbasaur
	_chk("a level-100 mon (nothing left to progress toward) returns an empty bar",
			bs._exp_bar_fraction(mon) == 0.0)


func _test_exp_bar_fraction_real_species_midpoint() -> void:
	var bs := BattleScreen.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 10)  # Bulbasaur, real growth-rate data
	var species_data: Dictionary = PokemonRegistry.get_species(1)
	var growth_rate: String = species_data.get("growth_rate", "")
	var exp_this: int = PokemonRegistry.get_exp_for_level(growth_rate, 10)
	var exp_next: int = PokemonRegistry.get_exp_for_level(growth_rate, 11)
	mon.current_exp = exp_this + (exp_next - exp_this) / 2
	var frac := bs._exp_bar_fraction(mon)
	_chk("a real registry-backed mon exactly halfway to its next level reports ~0.5",
			is_equal_approx(frac, 0.5) or absf(frac - 0.5) < 0.05)


func _test_exp_bar_fraction_real_species_at_threshold() -> void:
	var bs := BattleScreen.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 10)
	var species_data: Dictionary = PokemonRegistry.get_species(1)
	var growth_rate: String = species_data.get("growth_rate", "")
	mon.current_exp = PokemonRegistry.get_exp_for_level(growth_rate, 10)
	_chk("a mon sitting exactly at its own current level's threshold reports an empty bar",
			bs._exp_bar_fraction(mon) == 0.0)


func _test_exp_bar_fraction_clamped_non_negative() -> void:
	var bs := BattleScreen.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 10)
	# A deliberately-out-of-normal-range value (current_exp below this
	# level's own threshold) -- shouldn't happen in real gameplay, but the
	# function must degrade safely (clamp to 0.0), not return a negative
	# fraction that would visually invert the bar.
	mon.current_exp = 0
	var frac := bs._exp_bar_fraction(mon)
	_chk("an out-of-range current_exp clamps to a non-negative fraction", frac >= 0.0)


# ── 9. Real scene structure — the EXP bar exists ONLY on the singles
# player group, matching the real games' own scope exactly (confirmed via
# gen_databox_sprites.py's own Step 0: no EXP-ledge variant exists for
# either the opponent box or either doubles box). The old HpLabel overlay
# node is gone everywhere, not just unused. ──────────────────────────────

func _test_real_scene_structure() -> void:
	# [Established precedent — see m25b_menu_test.gd/phase4d_doubles_visual_
	# test.gd/phase4e_message_box_test.gd's own doc comments] Deliberately
	# NOT add_child()-ing the instantiated scene: count_assertions.sh
	# appends --autoplay process-wide, and battle_screen.gd's own _ready()
	# ends by calling _run_autoplay() -> get_tree().quit() once a real
	# BattleManager child actually starts advancing — entering the live
	# tree here would race and kill this whole test process. instantiate()
	# DOES fully build the real node subtree (every child node genuinely
	# exists), it just never fires NOTIFICATION_READY (so @onready vars are
	# NOT yet populated on `instance` itself) — worked around by calling
	# _setup_health_ui() directly with its own required @onready fields
	# assigned by hand first, the same "manually wire the one function
	# under test" pattern phase4e_message_box_test.gd's own
	# _test_setup_message_box_applies_stylebox established, just reading
	# the REAL child nodes via get_node() rather than fake stand-ins, since
	# the whole real subtree already genuinely exists.
	var scene: PackedScene = load("res://scenes/battle/battle_screen.tscn")
	var instance: BattleScreen = scene.instantiate()

	_chk("PlayerHealthGroup has a real ExpFill node",
			instance.has_node("BattleStage/PlayerHealthGroup/ExpFill"))
	_chk("OpponentHealthGroup has NO ExpFill node (opponent mons never show an EXP bar)",
			not instance.has_node("BattleStage/OpponentHealthGroup/ExpFill"))
	_chk("doubles player group has NO ExpFill node (no EXP bar in doubles at all)",
			not instance.has_node("BattleStage/PlayerHealthGroupD0/ExpFill"))
	_chk("doubles opponent group has NO ExpFill node",
			not instance.has_node("BattleStage/OpponentHealthGroupD0/ExpFill"))

	for path in ["BattleStage/OpponentHealthGroup/HpLabel", "BattleStage/PlayerHealthGroup/HpLabel",
			"BattleStage/OpponentHealthGroupD0/HpLabel", "BattleStage/OpponentHealthGroupD1/HpLabel",
			"BattleStage/PlayerHealthGroupD0/HpLabel", "BattleStage/PlayerHealthGroupD1/HpLabel"]:
		_chk("%s no longer exists (HP text is baked into the new box art)" % path,
				not instance.has_node(path))

	# Manually assign every @onready field _setup_health_ui() itself reads
	# directly (not via $-paths) from the REAL nodes already present in this
	# instantiated (but not tree-entered) subtree, then call it directly --
	# proves the real function actually wires the new art/colors correctly.
	instance._font_healthbox = FontFile.new()
	instance._font_healthbox.load_bitmap_font("res://assets/fonts/latin_small_healthbox.fnt")
	# [M26c-1 follow-up] NameLevelLabel split into NameLabel + LevelLabel.
	instance._opponent_name_label = instance.get_node("BattleStage/OpponentHealthGroup/NameLabel")
	instance._opponent_level_label = instance.get_node("BattleStage/OpponentHealthGroup/LevelLabel")
	instance._player_name_label = instance.get_node("BattleStage/PlayerHealthGroup/NameLabel")
	instance._player_level_label = instance.get_node("BattleStage/PlayerHealthGroup/LevelLabel")
	# [M26c battle-UI polish] The new separate GenderLabel nodes -- also
	# manually wired here since _setup_health_ui() now iterates over them
	# too (font/color override loop), matching every other label above.
	instance._opponent_gender_label = instance.get_node("BattleStage/OpponentHealthGroup/GenderLabel")
	instance._player_gender_label = instance.get_node("BattleStage/PlayerHealthGroup/GenderLabel")
	instance._opponent_health_bg = instance.get_node("BattleStage/OpponentHealthGroup/Background")
	instance._player_health_bg = instance.get_node("BattleStage/PlayerHealthGroup/Background")
	instance._opponent_hp_fill = instance.get_node("BattleStage/OpponentHealthGroup/HpFill")
	instance._player_hp_fill = instance.get_node("BattleStage/PlayerHealthGroup/HpFill")
	instance._player_exp_fill = instance.get_node("BattleStage/PlayerHealthGroup/ExpFill")
	# [M26c-3] Numeric HP readout -- also manually wired here since
	# _setup_health_ui() now iterates over it too (font/color override loop).
	instance._player_hp_number_label = instance.get_node("BattleStage/PlayerHealthGroup/HpNumberLabel")
	instance._opponent_status_icon = instance.get_node("BattleStage/OpponentHealthGroup/StatusIcon")
	instance._player_status_icon = instance.get_node("BattleStage/PlayerHealthGroup/StatusIcon")

	instance._setup_health_ui()

	var player_bg: TextureRect = instance._player_health_bg
	var opp_bg: TextureRect = instance._opponent_health_bg
	_chk("PlayerHealthGroup's real Background texture is the new databox_player.png",
			player_bg.texture != null and "databox_player" in player_bg.texture.resource_path)
	_chk("OpponentHealthGroup's real Background texture is the new databox_opponent.png",
			opp_bg.texture != null and "databox_opponent" in opp_bg.texture.resource_path)

	_chk("the real ExpFill node is tinted with the pack's own real EXP color",
			instance._player_exp_fill.tint_progress == BattleScreen._EXP_BAR_COLOR)
	_chk("the real ExpFill node's range is 0.0-1.0 (a fraction, not an HP-style raw value)",
			instance._player_exp_fill.min_value == 0.0 and instance._player_exp_fill.max_value == 1.0)

	instance.queue_free()


# ── 10. StatusIcon default preview texture — a real AtlasTexture sub-
# resource assigned directly in the .tscn (region 0 = the Poison row) so
# every StatusIcon node renders real pack-sourced pixel content in the
# Godot editor viewport with no need to run the scene. _setup_health_ui()
# still overwrites each node's .texture with its own freshly-created
# AtlasTexture at runtime (unchanged — the region is genuinely dynamic,
# mutated per-refresh by _update_status_icon) -- this test checks the
# state BEFORE that ever runs, i.e. what the editor itself would show.
# ──────────────────────────────────────────────────────────────────────

func _test_status_icon_default_preview_texture() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen.tscn")
	var instance: BattleScreen = scene.instantiate()

	var opponent_paths := [
		"BattleStage/OpponentHealthGroup/StatusIcon",
		"BattleStage/OpponentHealthGroupD0/StatusIcon",
		"BattleStage/OpponentHealthGroupD1/StatusIcon",
	]
	var player_paths := [
		"BattleStage/PlayerHealthGroup/StatusIcon",
		"BattleStage/PlayerHealthGroupD0/StatusIcon",
		"BattleStage/PlayerHealthGroupD1/StatusIcon",
	]

	for path in opponent_paths:
		var icon: TextureRect = instance.get_node(path)
		var atlas := icon.texture as AtlasTexture
		_chk("%s has a real AtlasTexture assigned pre-runtime (editor-previewable)" % path,
				atlas != null)
		if atlas != null:
			_chk("%s's preview atlas sources status2.png (opponent sheet)" % path,
					atlas.atlas != null and "status2" in atlas.atlas.resource_path)

	for path in player_paths:
		var icon: TextureRect = instance.get_node(path)
		var atlas := icon.texture as AtlasTexture
		_chk("%s has a real AtlasTexture assigned pre-runtime (editor-previewable)" % path,
				atlas != null)
		if atlas != null:
			_chk("%s's preview atlas sources status.png (player sheet)" % path,
					atlas.atlas != null and "status.png" in atlas.atlas.resource_path)

	instance.queue_free()


# ── 11. Split NameLabel/LevelLabel — real, separately-existing nodes for
# all 6 health groups (singles opponent/player + 4 doubles slots), with the
# old combined NameLevelLabel node gone everywhere. ──────────────────────

func _test_split_name_level_labels_exist() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen.tscn")
	var instance: BattleScreen = scene.instantiate()

	var groups := [
		"BattleStage/OpponentHealthGroup", "BattleStage/PlayerHealthGroup",
		"BattleStage/OpponentHealthGroupD0", "BattleStage/OpponentHealthGroupD1",
		"BattleStage/PlayerHealthGroupD0", "BattleStage/PlayerHealthGroupD1",
	]
	for group_path in groups:
		_chk("%s/NameLabel exists" % group_path,
				instance.has_node(group_path + "/NameLabel"))
		_chk("%s/LevelLabel exists" % group_path,
				instance.has_node(group_path + "/LevelLabel"))
		_chk("%s/NameLevelLabel (the old combined node) no longer exists" % group_path,
				not instance.has_node(group_path + "/NameLevelLabel"))

	instance.queue_free()
