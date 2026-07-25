extends Node

# [Doubles-split roadmap, step 1] Verifies HealthGroupPanel in isolation --
# nothing in production references this component yet (see this file's own
# doc comment on health_group_panel.gd for the full roadmap context). Real
# PackedScene.instantiate() + add_child() (not the bare-off-tree-instance
# convention used elsewhere in this project for pure-script classes) so
# _ready()'s own font/atlas/solid-fill-bar wiring genuinely runs, matching
# how a real future consumer will use this scene.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_node_structure()
	_test_ready_wires_font()
	_test_ready_wires_default_databox_and_status()
	_test_ready_configures_solid_fill_bar()
	_test_status_icon_row_mapping()
	_test_refresh_sets_name_and_level()
	_test_refresh_gender_glyph_positions_after_name()
	_test_refresh_no_gender_glyph_positions_level_after_name_alone()
	_test_refresh_status_icon_visibility()
	_test_refresh_hp_fill_values()
	_test_opponent_variant_has_no_exp_nodes()
	_test_player_variant_has_exp_nodes()
	_test_player_variant_default_databox_and_status()
	_test_player_variant_ready_configures_exp_fill()
	_test_player_variant_refresh_sets_hp_number_and_exp()
	_test_player_variant_refresh_without_exp_fraction_leaves_exp_value_untouched()
	_test_opponent_variant_refresh_tolerates_missing_exp_fraction_arg()
	_test_doubles_variants_node_structure_and_no_exp_nodes()
	_test_doubles_variants_default_databox_and_status()
	_test_doubles_variants_use_the_smaller_font_size()
	_test_doubles_opponent_refresh()
	_test_doubles_player_refresh()

	var total := _pass + _fail
	print("health_group_panel_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_panel() -> HealthGroupPanel:
	var scene: PackedScene = load("res://scenes/battle/health_group_panel.tscn")
	var panel: HealthGroupPanel = scene.instantiate()
	add_child(panel)
	return panel


func _make_player_panel() -> HealthGroupPanel:
	var scene: PackedScene = load("res://scenes/battle/health_group_panel_player.tscn")
	var panel: HealthGroupPanel = scene.instantiate()
	add_child(panel)
	return panel


func _make_doubles_opponent_panel() -> HealthGroupPanel:
	var scene: PackedScene = load("res://scenes/battle/health_group_panel_doubles_opponent.tscn")
	var panel: HealthGroupPanel = scene.instantiate()
	add_child(panel)
	return panel


func _make_doubles_player_panel() -> HealthGroupPanel:
	var scene: PackedScene = load("res://scenes/battle/health_group_panel_doubles_player.tscn")
	var panel: HealthGroupPanel = scene.instantiate()
	add_child(panel)
	return panel


# ── Node structure ──────────────────────────────────────────────────────

func _test_node_structure() -> void:
	var panel := _make_panel()
	for name in ["Background", "StatusIcon", "HpFill", "NameLabel", "GenderLabel", "LevelLabel"]:
		_chk("panel has a real %s child" % name, panel.has_node(name))
	panel.queue_free()


# ── _ready() wiring ─────────────────────────────────────────────────────

func _test_ready_wires_font() -> void:
	var panel := _make_panel()
	var name_label: Label = panel.get_node("NameLabel")
	var level_label: Label = panel.get_node("LevelLabel")
	var gender_label: Label = panel.get_node("GenderLabel")
	for label in [name_label, level_label, gender_label]:
		var font: Font = label.get_theme_font("font")
		_chk("label has a real font override", font != null)
		_chk("label font is the real health-box bitmap font",
				font is FontFile and (font as FontFile).fixed_size_scale_mode == 2)
	panel.queue_free()


func _test_ready_wires_default_databox_and_status() -> void:
	var panel := _make_panel()
	var background: TextureRect = panel.get_node("Background")
	_chk("Background texture matches the default databox_texture export",
			background.texture == panel.databox_texture)
	_chk("default databox_texture is the opponent databox pull",
			"databox_opponent" in panel.databox_texture.resource_path)
	var status_icon: TextureRect = panel.get_node("StatusIcon")
	_chk("StatusIcon texture is a real AtlasTexture", status_icon.texture is AtlasTexture)
	_chk("StatusIcon atlas is the default status_sheet export",
			(status_icon.texture as AtlasTexture).atlas == panel.status_sheet)
	panel.queue_free()


func _test_ready_configures_solid_fill_bar() -> void:
	var panel := _make_panel()
	var hp_fill: TextureProgressBar = panel.get_node("HpFill")
	_chk("HpFill has a real fill texture", hp_fill.texture_progress != null)
	_chk("HpFill uses nine-patch stretch (the bugfix this project's own history documents)",
			hp_fill.nine_patch_stretch)
	_chk("HpFill step is 0 (no value rounding)", hp_fill.step == 0.0)
	panel.queue_free()


# ── status_icon_row (static mapping, matches battle_screen.gd's own) ────

func _test_status_icon_row_mapping() -> void:
	_chk("poison -> row 0", HealthGroupPanel.status_icon_row(BattlePokemon.STATUS_POISON) == 0)
	_chk("toxic -> row 0", HealthGroupPanel.status_icon_row(BattlePokemon.STATUS_TOXIC) == 0)
	_chk("paralysis -> row 1", HealthGroupPanel.status_icon_row(BattlePokemon.STATUS_PARALYSIS) == 1)
	_chk("sleep -> row 2", HealthGroupPanel.status_icon_row(BattlePokemon.STATUS_SLEEP) == 2)
	_chk("freeze -> row 3", HealthGroupPanel.status_icon_row(BattlePokemon.STATUS_FREEZE) == 3)
	_chk("burn -> row 4", HealthGroupPanel.status_icon_row(BattlePokemon.STATUS_BURN) == 4)
	_chk("no status -> -1 (hidden)", HealthGroupPanel.status_icon_row(BattlePokemon.STATUS_NONE) == -1)


# ── refresh() ────────────────────────────────────────────────────────────

func _test_refresh_sets_name_and_level() -> void:
	var panel := _make_panel()
	panel.refresh("Charizard", "", "Lv50", BattlePokemon.STATUS_NONE, 100, 150, Color.WHITE)
	var name_label: Label = panel.get_node("NameLabel")
	var level_label: Label = panel.get_node("LevelLabel")
	_chk("name label text set", name_label.text == "Charizard")
	_chk("level label text set", level_label.text == "Lv50")
	panel.queue_free()


func _test_refresh_gender_glyph_positions_after_name() -> void:
	var panel := _make_panel()
	panel.refresh("Bulbasaur", "♂", "Lv100", BattlePokemon.STATUS_NONE, 1, 1, Color.WHITE)
	var name_label: Label = panel.get_node("NameLabel")
	var gender_label: Label = panel.get_node("GenderLabel")
	var level_label: Label = panel.get_node("LevelLabel")
	_chk("gender glyph text set", gender_label.text == "♂")
	_chk("gender label starts at/after the name's own right edge",
			gender_label.offset_left >= name_label.offset_left)
	_chk("level label starts at/after the gender label's own right edge",
			level_label.offset_left >= gender_label.offset_right)
	panel.queue_free()


func _test_refresh_no_gender_glyph_positions_level_after_name_alone() -> void:
	var panel := _make_panel()
	panel.refresh("Ditto", "", "Lv5", BattlePokemon.STATUS_NONE, 1, 1, Color.WHITE)
	var gender_label: Label = panel.get_node("GenderLabel")
	var level_label: Label = panel.get_node("LevelLabel")
	_chk("empty glyph leaves the gender label's own text empty", gender_label.text == "")
	_chk("level label still gets a real position with no gender glyph present",
			level_label.offset_right > level_label.offset_left)
	panel.queue_free()


func _test_refresh_status_icon_visibility() -> void:
	var panel := _make_panel()
	var status_icon: TextureRect = panel.get_node("StatusIcon")

	panel.refresh("Machop", "", "Lv30", BattlePokemon.STATUS_NONE, 50, 50, Color.WHITE)
	_chk("no status -> icon hidden", not status_icon.visible)

	panel.refresh("Machop", "", "Lv30", BattlePokemon.STATUS_PARALYSIS, 50, 50, Color.WHITE)
	_chk("paralysis -> icon shown", status_icon.visible)
	var atlas := status_icon.texture as AtlasTexture
	_chk("paralysis -> region row 1", atlas.region.position.y == 8.0)

	panel.refresh("Machop", "", "Lv30", BattlePokemon.STATUS_BURN, 50, 50, Color.WHITE)
	_chk("burn -> region row 4", atlas.region.position.y == 32.0)
	panel.queue_free()


func _test_refresh_hp_fill_values() -> void:
	var panel := _make_panel()
	var hp_fill: TextureProgressBar = panel.get_node("HpFill")
	panel.refresh("Snorlax", "", "Lv40", BattlePokemon.STATUS_NONE, 75, 200, Color8(255, 90, 57))
	_chk("hp fill max_value set", hp_fill.max_value == 200)
	_chk("hp fill value set", hp_fill.value == 75)
	_chk("hp fill tint_progress set to the passed-in color", hp_fill.tint_progress == Color8(255, 90, 57))
	panel.queue_free()


# ── Step 2: player variant (HpNumberLabel/ExpFill) ───────────────────────

func _test_opponent_variant_has_no_exp_nodes() -> void:
	var panel := _make_panel()
	_chk("opponent-shaped panel has no HpNumberLabel node", not panel.has_node("HpNumberLabel"))
	_chk("opponent-shaped panel has no ExpFill node", not panel.has_node("ExpFill"))
	panel.queue_free()


func _test_player_variant_has_exp_nodes() -> void:
	var panel := _make_player_panel()
	_chk("player-shaped panel has a real HpNumberLabel node", panel.has_node("HpNumberLabel"))
	_chk("player-shaped panel has a real ExpFill node", panel.has_node("ExpFill"))
	panel.queue_free()


func _test_player_variant_default_databox_and_status() -> void:
	var panel := _make_player_panel()
	var background: TextureRect = panel.get_node("Background")
	_chk("player variant's default databox_texture is the player databox pull",
			"databox_player" in panel.databox_texture.resource_path)
	_chk("Background texture matches it", background.texture == panel.databox_texture)
	var status_icon: TextureRect = panel.get_node("StatusIcon")
	_chk("player variant's default status_sheet is the player status pull (status.png, not status2.png)",
			(status_icon.texture as AtlasTexture).atlas == panel.status_sheet
			and "battle_ui/interface/status.png" in panel.status_sheet.resource_path)
	panel.queue_free()


func _test_player_variant_ready_configures_exp_fill() -> void:
	var panel := _make_player_panel()
	var exp_fill: TextureProgressBar = panel.get_node("ExpFill")
	_chk("ExpFill has a real fill texture", exp_fill.texture_progress != null)
	_chk("ExpFill uses nine-patch stretch", exp_fill.nine_patch_stretch)
	_chk("ExpFill tint_progress is the real Emerald UI Pack EXP-bar color",
			exp_fill.tint_progress == Color8(66, 206, 255))
	_chk("ExpFill range is normalized [0,1]", exp_fill.min_value == 0.0 and exp_fill.max_value == 1.0)
	var hp_number_label: Label = panel.get_node("HpNumberLabel")
	_chk("HpNumberLabel got the real font override too",
			hp_number_label.get_theme_font("font") != null)
	panel.queue_free()


func _test_player_variant_refresh_sets_hp_number_and_exp() -> void:
	var panel := _make_player_panel()
	panel.refresh("Blastoise", "", "Lv55", BattlePokemon.STATUS_NONE, 90, 120, Color.WHITE, 0.35)
	var hp_number_label: Label = panel.get_node("HpNumberLabel")
	var exp_fill: TextureProgressBar = panel.get_node("ExpFill")
	_chk("hp number label shows current/max", hp_number_label.text == "90/120")
	_chk("exp fill value set from the passed exp_fraction", exp_fill.value == 0.35)
	panel.queue_free()


func _test_player_variant_refresh_without_exp_fraction_leaves_exp_value_untouched() -> void:
	var panel := _make_player_panel()
	var exp_fill: TextureProgressBar = panel.get_node("ExpFill")
	exp_fill.value = 0.7
	# Default exp_fraction (-1.0) means "no real EXP data available" (matches
	# _exp_bar_fraction's own disclosed 0.0-for-unresolvable-species fallback
	# in battle_screen.gd) -- refresh() must not stomp a value the caller
	# never supplied.
	panel.refresh("Wartortle", "", "Lv36", BattlePokemon.STATUS_NONE, 60, 90, Color.WHITE)
	_chk("hp number label still updates independent of exp_fraction",
			(panel.get_node("HpNumberLabel") as Label).text == "60/90")
	_chk("exp fill value left untouched when exp_fraction is omitted", exp_fill.value == 0.7)
	panel.queue_free()


func _test_opponent_variant_refresh_tolerates_missing_exp_fraction_arg() -> void:
	var panel := _make_panel()
	# No HpNumberLabel/ExpFill exist on this variant at all -- refresh() must
	# not crash reaching for either.
	panel.refresh("Pidgey", "", "Lv10", BattlePokemon.STATUS_NONE, 20, 20, Color.WHITE, 0.5)
	_chk("opponent variant refresh completes without error", true)
	panel.queue_free()


# ── Step 3: doubles-scale variants ───────────────────────────────────────

func _test_doubles_variants_node_structure_and_no_exp_nodes() -> void:
	for panel in [_make_doubles_opponent_panel(), _make_doubles_player_panel()]:
		for name in ["Background", "StatusIcon", "HpFill", "NameLabel", "GenderLabel", "LevelLabel"]:
			_chk("doubles panel has a real %s child" % name, panel.has_node(name))
		_chk("doubles panel has no HpNumberLabel (no EXP bar in doubles at all)",
				not panel.has_node("HpNumberLabel"))
		_chk("doubles panel has no ExpFill (no EXP bar in doubles at all)",
				not panel.has_node("ExpFill"))
		panel.queue_free()


func _test_doubles_variants_default_databox_and_status() -> void:
	var opp := _make_doubles_opponent_panel()
	_chk("doubles-opponent default databox is the doubles-opponent pull",
			"databox_doubles_opponent" in opp.databox_texture.resource_path)
	_chk("doubles-opponent default status sheet is the opponent status pull (status2.png)",
			"battle_ui/interface/status2.png" in opp.status_sheet.resource_path)
	opp.queue_free()

	var ply := _make_doubles_player_panel()
	_chk("doubles-player default databox is the doubles-player pull",
			"databox_doubles_player" in ply.databox_texture.resource_path)
	_chk("doubles-player default status sheet is the player status pull (status.png)",
			"battle_ui/interface/status.png" in ply.status_sheet.resource_path)
	ply.queue_free()


func _test_doubles_variants_use_the_smaller_font_size() -> void:
	# Real-estate constraint carried over from the pre-split .tscn: doubles
	# boxes use font_size=14, singles boxes use font_size=64 -- confirming
	# the doubles scenes' own authored .tscn values, since the script's
	# _ready() only overrides which FONT is used, never font_size.
	for panel in [_make_doubles_opponent_panel(), _make_doubles_player_panel()]:
		var name_label: Label = panel.get_node("NameLabel")
		_chk("doubles NameLabel keeps its own smaller authored font_size",
				name_label.get_theme_font_size("font_size") == 14)
		panel.queue_free()
	var singles := _make_panel()
	var singles_name_label: Label = singles.get_node("NameLabel")
	_chk("singles NameLabel's own authored font_size is the larger 64, for contrast",
			singles_name_label.get_theme_font_size("font_size") == 64)
	singles.queue_free()


func _test_doubles_opponent_refresh() -> void:
	var panel := _make_doubles_opponent_panel()
	var status_icon: TextureRect = panel.get_node("StatusIcon")
	var hp_fill: TextureProgressBar = panel.get_node("HpFill")
	panel.refresh("Zubat", "", "Lv22", BattlePokemon.STATUS_SLEEP, 12, 40, Color8(255, 231, 57))
	_chk("doubles-opponent name set", (panel.get_node("NameLabel") as Label).text == "Zubat")
	_chk("doubles-opponent status icon shown for sleep", status_icon.visible)
	_chk("doubles-opponent status region is row 2 (sleep)",
			(status_icon.texture as AtlasTexture).region.position.y == 16.0)
	_chk("doubles-opponent hp fill values set", hp_fill.value == 12 and hp_fill.max_value == 40)
	panel.queue_free()


func _test_doubles_player_refresh() -> void:
	var panel := _make_doubles_player_panel()
	panel.refresh("Golbat", "♀", "Lv24", BattlePokemon.STATUS_NONE, 55, 55, Color.WHITE)
	_chk("doubles-player name set", (panel.get_node("NameLabel") as Label).text == "Golbat")
	_chk("doubles-player gender glyph set", (panel.get_node("GenderLabel") as Label).text == "♀")
	_chk("doubles-player status icon hidden (no status)",
			not (panel.get_node("StatusIcon") as TextureRect).visible)
	panel.queue_free()
