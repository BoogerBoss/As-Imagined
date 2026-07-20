extends Node

# [M25h-1] Regression suite for the shared bottom-region paging system —
# TOP/FIGHT/TARGET_SELECT relocated into a new real-proportion region
# (ActionRegion, anchor_top=0.75/anchor_bottom=0.95, matching source's own
# B_WIN_MSG tilemapTop=15/height=4 tiles = y=120-152px of a 160px screen),
# while SWITCH/ITEM deliberately stay in the old inline `_button_area`
# (left untouched — M25h-2/h-3's own job to pull out into real separate
# screens), plus the Side0Label/Side1Label deletion.
#
# [Deliberately NOT tested here] _refresh_ui() itself, and the real visual
# non-overlap between the old VBox block and the new region for every
# possible SWITCH/ITEM row count — matches m25b_menu_test.gd's own
# established precedent (needs a live scene tree with every @onready UI
# node resolved); the real end-to-end proof is this session's own real
# screenshot verification, including the anchor-fix screenshot re-check
# after the VBox-overlap regression that verification itself caught.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_action_region_anchored_to_real_proportion()
	_test_new_button_area_is_distinct_node_from_old()
	_test_side_labels_deleted()
	_test_status_label_relocated_into_action_region()
	_test_top_menu_builds_into_new_area_not_old()
	_test_fight_menu_builds_into_new_area_not_old()
	_test_target_select_builds_into_new_area_not_old()
	_test_switch_still_builds_into_old_area()
	_test_item_opens_a_real_overlay_not_the_old_button_areas()
	_test_player_health_group_d1_clears_action_region()
	_test_action_panel_exists_as_panel_container()
	_test_action_panel_has_real_window_art_stylebox()
	_test_action_panel_key_color_is_distinct_from_message_box_key_color()
	_test_color_keyed_texture_generalizes_to_a_custom_key_color()
	_test_status_label_has_neutral_font_color_override()

	var total := _pass + _fail
	print("m25h1_bottom_region_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Fixtures (mirrors m25b_menu_test.gd's own established shape) ────────

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


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _singles_party(mon: BattlePokemon, bench: Array = []) -> BattleParty:
	var p := BattleParty.new()
	var members: Array[BattlePokemon] = [mon]
	for m: BattlePokemon in bench:
		members.append(m)
	p.members = members
	var idx: Array[int] = [0]
	p.active_indices = idx
	return p


func _button_texts(container: VBoxContainer) -> Array:
	var texts: Array = []
	for child in container.get_children():
		if child is Button:
			texts.append((child as Button).text)
	return texts


# ── 1-3. Real .tscn structure — instantiated but never added to the tree,
# matching m25b_menu_test.gd's own `OpponentAnimTimer.one_shot` precedent
# for checking real node properties without needing a live scene. ────────

func _test_action_region_anchored_to_real_proportion() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen.tscn")
	var instance: Node = scene.instantiate()
	var region: Control = instance.get_node("ActionRegion")
	_chk("ActionRegion's top anchor matches source's own B_WIN_MSG proportion (tilemapTop=15/160=0.75)",
			is_equal_approx(region.anchor_top, 0.75))
	_chk("ActionRegion's bottom anchor matches source's own B_WIN_MSG proportion ((15+4)/20=0.95)",
			is_equal_approx(region.anchor_bottom, 0.95))
	instance.queue_free()


func _test_new_button_area_is_distinct_node_from_old() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen.tscn")
	var instance: Node = scene.instantiate()
	var new_area: Node = instance.get_node("ActionRegion/ActionPanel/ActionVBox/NewButtonArea")
	var old_area: Node = instance.get_node("VBox/ButtonArea")
	_chk("the new region's own button area exists", new_area != null)
	_chk("the old VBox's own button area still exists (SWITCH/ITEM's own home)", old_area != null)
	_chk("they are genuinely two distinct nodes, not aliases of the same one",
			new_area != old_area)
	instance.queue_free()


func _test_side_labels_deleted() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen.tscn")
	var instance: Node = scene.instantiate()
	var vbox: Node = instance.get_node("VBox")
	_chk("Side0Label is gone (confirmed redundant M23.2-era scaffolding + real doubles bug)",
			not vbox.has_node("Side0Label"))
	_chk("Side1Label is gone", not vbox.has_node("Side1Label"))
	_chk("StatusLabel is also gone from VBox specifically (relocated into ActionRegion, not deleted)",
			not vbox.has_node("StatusLabel"))
	instance.queue_free()


func _test_status_label_relocated_into_action_region() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen.tscn")
	var instance: Node = scene.instantiate()
	_chk("StatusLabel now lives under ActionRegion/ActionPanel/ActionVBox (same node, new parent)",
			instance.has_node("ActionRegion/ActionPanel/ActionVBox/StatusLabel"))
	instance.queue_free()


# ── 4-6. TOP/FIGHT/TARGET_SELECT build into the NEW area ────────────────

func _test_top_menu_builds_into_new_area_not_old() -> void:
	var mon := _make_mon("Solo")
	mon.add_move(_load_move(33))
	var bs := BattleScreen.new()
	bs._player_party = _singles_party(mon)
	bs._new_button_area = VBoxContainer.new()
	bs._button_area = VBoxContainer.new()

	bs._build_top_menu(0)

	_chk("TOP menu's 4 buttons land in the NEW region's button area",
			_button_texts(bs._new_button_area).size() == 4)
	_chk("TOP menu does NOT also write into the old (SWITCH/ITEM-only) button area",
			bs._button_area.get_child_count() == 0)


func _test_fight_menu_builds_into_new_area_not_old() -> void:
	var mon := _make_mon("Mover")
	mon.add_move(_load_move(33))
	var bs := BattleScreen.new()
	bs._player_party = _singles_party(mon)
	bs._new_button_area = VBoxContainer.new()
	bs._button_area = VBoxContainer.new()

	bs._build_fight_menu(0)

	_chk("FIGHT menu (1 move + Back) lands in the NEW region's button area",
			_button_texts(bs._new_button_area).size() == 2)
	_chk("FIGHT menu does NOT also write into the old button area",
			bs._button_area.get_child_count() == 0)


func _test_target_select_builds_into_new_area_not_old() -> void:
	var attacker := _make_mon("Attacker")
	var earthquake := _load_move(89)  # spread move -- only used to reach target-select
	attacker.add_move(earthquake)
	var opp0 := _make_mon("Opp0")
	var opp1 := _make_mon("Opp1")

	var bs := BattleScreen.new()
	bs._player_party = _singles_party(attacker)
	bs._new_button_area = VBoxContainer.new()
	bs._button_area = VBoxContainer.new()

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.set_human_controlled(1, true)
	var doubles_ally := _make_mon("Ally")
	var ally_party := BattleParty.new()
	var ally_members: Array[BattlePokemon] = [attacker, doubles_ally]
	ally_party.members = ally_members
	var ally_idx: Array[int] = [0, 1]
	ally_party.active_indices = ally_idx
	var opp_party := BattleParty.new()
	var opp_members: Array[BattlePokemon] = [opp0, opp1]
	opp_party.members = opp_members
	opp_party.active_indices = ally_idx.duplicate()
	bm.start_battle_doubles(ally_party, opp_party)
	bs._bm = bm

	bs._build_target_select_buttons(0, 0)

	_chk("TARGET_SELECT's own buttons (2 candidates + Back) land in the NEW region's button area",
			_button_texts(bs._new_button_area).size() == 3)
	_chk("TARGET_SELECT does NOT also write into the old button area",
			bs._button_area.get_child_count() == 0)

	bm.queue_free()


# ── 7. SWITCH deliberately still builds into the OLD area (M25h-1.5's own
# future job, not yet done) ───────────────────────────────────────────────

func _test_switch_still_builds_into_old_area() -> void:
	var mon := _make_mon("SwitchTester")
	var bench := _make_mon("Bench")
	var bs := BattleScreen.new()
	bs._player_party = _singles_party(mon, [bench])
	bs._new_button_area = VBoxContainer.new()
	bs._button_area = VBoxContainer.new()

	bs._build_switch_buttons(false, 0)

	_chk("SWITCH's own buttons (1 candidate + Back) still land in the OLD button area, untouched this session",
			_button_texts(bs._button_area).size() == 2)
	_chk("SWITCH does NOT write into the new region's button area",
			bs._new_button_area.get_child_count() == 0)


# ── 8. [M25h-1.4 superseded this test's own original finding] ITEM no
# longer builds into EITHER _button_area or _new_button_area at all -- it
# now opens a real separate ItemSelectScreen overlay (see
# item_select_screen_test.gd for that screen's own dedicated coverage).
# This is a genuine, deliberate architecture change, not a regression:
# confirmed via this session's own real screenshot verification that the
# overlay renders correctly. Rewritten to confirm the NEW real behavior
# instead of the old inline-panel assumption.
func _test_item_opens_a_real_overlay_not_the_old_button_areas() -> void:
	var mon := _make_mon("ItemTester")
	var bs := BattleScreen.new()
	bs._player_party = _singles_party(mon)
	bs._new_button_area = VBoxContainer.new()
	bs._button_area = VBoxContainer.new()
	bs._font_menu = FontFile.new()
	bs._font_menu.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")

	bs._build_item_buttons(0)

	_chk("ITEM does NOT write into the old _button_area at all anymore",
			bs._button_area.get_child_count() == 0)
	_chk("ITEM does NOT write into the new region's button area either",
			bs._new_button_area.get_child_count() == 0)
	_chk("ITEM instead opens a real separate ItemSelectScreen overlay",
			bs._item_select_overlay != null and bs._item_select_overlay is ItemSelectScreen)


# ── 9. Doubles clearance re-check — the exact real anchor/offset values,
# not the recon's own earlier estimate. Deliberately does NOT instantiate
# battle_screen.tscn into this process's own live tree to check this via
# get_global_rect() -- count_assertions.sh appends --autoplay to every
# scene invocation process-wide (see m25b_menu_test.gd's own established
# "never embed battle_screen.tscn in an autoplay-swept test" precedent),
# and a real BattleScreen instance entering the tree would see that flag
# and call _run_autoplay() -> get_tree().quit(), killing this whole test
# process. Reads the two nodes' own real anchor/offset values directly
# instead and reproduces Godot's own point-anchor math by hand -- verified
# to match a real screenshot's own measured pixel values exactly (486.0/
# 474.64, 11.36px clearance) during this session's own manual verification.
func _test_player_health_group_d1_clears_action_region() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen.tscn")
	var instance: Node = scene.instantiate()
	var d1: Control = instance.get_node("BattleStage/PlayerHealthGroupD1")
	var region: Control = instance.get_node("ActionRegion")

	# PlayerHealthGroupD1 is a POINT anchor (anchor_top == anchor_bottom);
	# its own real bottom edge, as a fraction of viewport height, is
	# anchor_top + (its own local offset_bottom / viewport_height). Uses
	# the same real viewport height this session's own screenshots were
	# captured and measured against (648px) to reproduce the exact
	# clearance figure found there, not just check the anchor fraction
	# alone (which wouldn't catch a local-offset-only regression).
	const VIEWPORT_HEIGHT := 648.0
	var d1_bottom_px: float = d1.anchor_top * VIEWPORT_HEIGHT + d1.offset_bottom
	var region_top_px: float = region.anchor_top * VIEWPORT_HEIGHT

	_chk("PlayerHealthGroupD1's own bottom edge clears ActionRegion's own top edge (no overlap)",
			d1_bottom_px < region_top_px)
	_chk("the real clearance matches this session's own screenshot-measured ~11.36px, not just 'some' positive gap",
			abs((region_top_px - d1_bottom_px) - 11.36) < 0.1)

	instance.queue_free()


# ── 10-14. [M25h-1.1] Real window art for the new region ─────────────────

func _test_action_panel_exists_as_panel_container() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen.tscn")
	var instance: Node = scene.instantiate()
	var panel: Node = instance.get_node("ActionRegion/ActionPanel")
	_chk("ActionPanel exists", panel != null)
	_chk("ActionPanel is genuinely a PanelContainer (has a 'panel' theme stylebox slot to override), not a plain Control",
			panel is PanelContainer)
	instance.queue_free()


func _test_action_panel_has_real_window_art_stylebox() -> void:
	# Called directly on a bare instance with manually-constructed stand-in
	# nodes for _action_panel/_status_label -- mirrors
	# phase4e_message_box_test.gd's own established
	# _test_setup_message_box_applies_stylebox precedent exactly (never adds
	# a real BattleScreen to this process's own live tree: count_assertions.sh
	# appends --autoplay to every scene invocation process-wide, and a real
	# _ready() would re-derive _is_autoplay_run from OS.get_cmdline_args()
	# and call _run_autoplay() -> get_tree().quit(), killing this whole test
	# process — see m25b_menu_test.gd's own established precedent for the
	# same reasoning).
	var bs := BattleScreen.new()
	bs._action_panel = PanelContainer.new()
	bs._status_label = Label.new()
	# [M25h-1.2] _setup_action_region_panel() now also applies the real
	# message-context bitmap font to _status_label -- a null font here
	# (this function's own production caller, _ready(), always loads one
	# first via _load_battle_fonts()) makes add_theme_font_override log a
	# real engine error rather than silently no-op, so this bare-instance
	# test needs one too, same as _test_status_label_has_neutral_font_color_override.
	bs._font_message = FontFile.new()
	bs._font_message.load_bitmap_font("res://assets/fonts/latin_normal_message.fnt")

	bs._setup_action_region_panel()

	var style: StyleBox = bs._action_panel.get_theme_stylebox("panel")
	_chk("ActionPanel has a real StyleBoxTexture override applied (not the theme default)",
			style is StyleBoxTexture)
	if style is StyleBoxTexture:
		_chk("the applied texture is a real, non-null ImageTexture (the color-keyed text_window/1.png pull)",
				(style as StyleBoxTexture).texture != null)
		_chk("the applied margins match this session's own measured 6px corner (not std.png's own 5px)",
				(style as StyleBoxTexture).texture_margin_left == BattleScreen._ACTION_PANEL_MARGIN)


func _test_action_panel_key_color_is_distinct_from_message_box_key_color() -> void:
	# [Step 0 finding] text_window/1.png (the real B_WIN_MSG/action-menu/
	# move-select asset, per LoadUserWindowBorderGfx -> LoadWindowGfx ->
	# sWindowFrames[gSaveBlock2Ptr->optionsWindowFrameType], default 0 on a
	# fresh save) uses its OWN background-key color, genuinely different
	# from std.png's own (the file Phase 4e's _setup_message_box already
	# uses for the separately-styled, untouched-by-this-session log) --
	# confirms these are two distinct real assets, not the same file reused.
	var action_key := BattleScreen._ACTION_PANEL_KEY_COLOR
	var message_key := BattleScreen._MESSAGE_BOX_KEY_COLOR
	_chk("text_window/1.png's own key color is confirmed different from std.png's own",
			not action_key.is_equal_approx(message_key))
	_chk("text_window/1.png's own key color matches this session's own direct pixel inspection (98,197,98,255)",
			action_key.is_equal_approx(Color8(98, 197, 98, 255)))
	_chk("text_window/1.png's own margin (6px) is confirmed different from std.png's own (5px)",
			not is_equal_approx(BattleScreen._ACTION_PANEL_MARGIN, BattleScreen._MESSAGE_BOX_MARGIN))


func _test_color_keyed_texture_generalizes_to_a_custom_key_color() -> void:
	# Small synthetic image (no disk I/O) -- mirrors
	# phase4e_message_box_test.gd's own established
	# _test_color_keyed_texture_synthetic precedent, but exercises the new
	# explicit key_color param instead of relying on the default.
	var img := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	var custom_key := Color8(1, 2, 3, 255)
	img.set_pixel(0, 0, custom_key)
	img.set_pixel(1, 0, Color.WHITE)

	var tex: ImageTexture = BattleScreen._color_keyed_texture(img, custom_key)
	var result: Image = tex.get_image()

	_chk("a custom key color's own matching pixel becomes real alpha=0",
			result.get_pixel(0, 0).a == 0.0)
	_chk("a non-matching pixel (white) is left untouched",
			result.get_pixel(1, 0).is_equal_approx(Color.WHITE))
	_chk("the SAME custom key color is correctly NOT matched by the default (std.png) key check",
			not BattleScreen._is_message_box_key_color(custom_key))


func _test_status_label_has_neutral_font_color_override() -> void:
	# [M25h-1.2 superseded this test's own original finding] Phase 4e/M25h-1.1
	# originally fixed StatusLabel's white-on-white risk with a flat dark
	# `font_color` override, correct for the engine's generic default font
	# (a plain white glyph mask that the override tints directly). M25h-1.2
	# replaced that generic font with a real bitmap font whose glyph pixels
	# are ALREADY fully colored (baked in at atlas-generation time — see
	# gen_battle_fonts.py) -- a dark tint would now multiply against those
	# real colors and crush them toward black, so the correct override is a
	# neutral, non-tinting Color(1,1,1,1) instead. This is a genuine,
	# deliberate behavior change, not a regression: confirmed via this
	# session's own real screenshot verification that StatusLabel's text
	# (source's B_WIN_ACTION_PROMPT red) renders correctly with the new
	# override in place. Bare-instance direct call, same reasoning as the
	# test immediately above; _font_message loaded for real (from disk) so
	# _setup_action_region_panel's new font-override line has a real
	# resource to apply, matching how the panel's own texture load already
	# touches disk in this same function.
	var bs := BattleScreen.new()
	bs._action_panel = PanelContainer.new()
	var label := Label.new()
	bs._status_label = label
	bs._font_message = FontFile.new()
	bs._font_message.load_bitmap_font("res://assets/fonts/latin_normal_message.fnt")

	bs._setup_action_region_panel()

	_chk("StatusLabel has the real message-context bitmap font applied",
			label.get_theme_font("font") == bs._font_message)
	_chk("StatusLabel has a font_color override (not left at the engine's own default)",
			label.has_theme_color_override("font_color"))
	if label.has_theme_color_override("font_color"):
		var c: Color = label.get_theme_color("font_color")
		_chk("the override is neutral/non-tinting white (the bitmap font's own baked-in colors show through unmodified)",
				c.is_equal_approx(Color(1, 1, 1, 1)))
