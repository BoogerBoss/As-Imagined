extends Node

# [M25h-1] Regression suite for the shared bottom-region paging system —
# TOP/FIGHT/TARGET_SELECT relocated into a new real-proportion region
# (ActionRegion, anchor_top=0.75/anchor_bottom=0.95, matching source's own
# B_WIN_MSG tilemapTop=15/height=4 tiles = y=120-152px of a 160px screen),
# plus the Side0Label/Side1Label deletion. SWITCH/ITEM originally stayed in
# the old inline `_button_area` at this sub-phase's own time of writing —
# both have since been rebuilt as real separate full-screen overlays
# (M25h-1.4 for Item, M25h-1.5 for Switch), so `_button_area` itself is now
# dead weight neither of them writes into anymore (see Test 7/8 below, both
# rewritten from this suite's own original "still builds into old area"
# assumption to confirm the real current behavior instead).
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
	_test_switch_opens_a_real_overlay_not_the_old_button_areas()
	_test_item_opens_a_real_overlay_not_the_old_button_areas()
	_test_player_health_group_d1_clears_action_region()
	_test_action_panel_exists_as_panel_container()
	_test_action_panel_has_real_window_art_stylebox()
	_test_action_panel_key_color_is_distinct_from_message_box_key_color()
	_test_color_keyed_texture_generalizes_to_a_custom_key_color()
	_test_status_label_has_real_message_color_override()

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


func _button_texts(container: Container) -> Array:
	# [Doubles-split roadmap, step 8] Filters to VISIBLE buttons only --
	# _new_button_grid now permanently holds 8 children (TOP's 4 + FIGHT's
	# 4-slot move pool), only 4 of which are ever meant to be "in" the menu
	# currently being shown; the rest are hidden, not absent. Harmless for
	# _button_area/_new_button_area, whose children are still fully cleared
	# and rebuilt each call (never hold a hidden child to begin with).
	var texts: Array = []
	for child in container.get_children():
		if child is Button and (child as Button).visible:
			texts.append((child as Button).text)
	return texts


# [Doubles-split roadmap, step 8] _build_top_menu()/_build_fight_menu() now
# reuse 9 permanent Button nodes authored directly in shared_battle_chrome
# .tscn (_top_fight_btn/_top_item_btn/_top_switch_btn/_top_run_btn/
# _move_buttons) instead of creating fresh ones -- real @onready-equivalent
# fields that never resolve on a bare instance, so every test calling either
# builder needs stand-ins wired manually first, matching this file's own
# established convention for every other @onready field.
func _wire_menu_buttons(bs: BattleScreenShared) -> void:
	bs._top_fight_btn = Button.new()
	bs._top_item_btn = Button.new()
	bs._top_switch_btn = Button.new()
	bs._top_run_btn = Button.new()
	var move_buttons: Array[Button] = [Button.new(), Button.new(), Button.new(), Button.new()]
	bs._move_buttons = move_buttons


# ── 1-3. Real .tscn structure — instantiated but never added to the tree,
# matching m25b_menu_test.gd's own `OpponentAnimTimer.one_shot` precedent
# for checking real node properties without needing a live scene. ────────

func _test_action_region_anchored_to_real_proportion() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var instance: Node = scene.instantiate()
	var region: Control = instance.get_node("SharedChrome/ActionRegion")
	_chk("ActionRegion's top anchor matches source's own B_WIN_MSG proportion (tilemapTop=15/160=0.75)",
			is_equal_approx(region.anchor_top, 0.75))
	_chk("ActionRegion's bottom anchor matches source's own B_WIN_MSG proportion ((15+4)/20=0.95)",
			is_equal_approx(region.anchor_bottom, 0.95))
	instance.queue_free()


func _test_new_button_area_is_distinct_node_from_old() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var instance: Node = scene.instantiate()
	var new_area: Node = instance.get_node("SharedChrome/ActionRegion/ActionPanel/ActionVBox/NewButtonArea")
	var old_area: Node = instance.get_node("SharedChrome/VBox/ButtonArea")
	_chk("the new region's own button area exists", new_area != null)
	_chk("the old VBox's own button area still exists (SWITCH/ITEM's own home)", old_area != null)
	_chk("they are genuinely two distinct nodes, not aliases of the same one",
			new_area != old_area)
	instance.queue_free()


func _test_side_labels_deleted() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var instance: Node = scene.instantiate()
	var vbox: Node = instance.get_node("SharedChrome/VBox")
	_chk("Side0Label is gone (confirmed redundant M23.2-era scaffolding + real doubles bug)",
			not vbox.has_node("Side0Label"))
	_chk("Side1Label is gone", not vbox.has_node("Side1Label"))
	_chk("StatusLabel is also gone from VBox specifically (relocated into ActionRegion, not deleted)",
			not vbox.has_node("StatusLabel"))
	instance.queue_free()


func _test_status_label_relocated_into_action_region() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var instance: Node = scene.instantiate()
	_chk("StatusLabel now lives under ActionRegion/ActionPanel/ActionVBox (same node, new parent)",
			instance.has_node("SharedChrome/ActionRegion/ActionPanel/ActionVBox/StatusLabel"))
	instance.queue_free()


# ── 4-6. TOP/FIGHT/TARGET_SELECT build into the NEW area ────────────────

func _test_top_menu_builds_into_new_area_not_old() -> void:
	var mon := _make_mon("Solo")
	mon.add_move(_load_move(33))
	var bs := BattleScreenShared.new()
	bs._player_party = _singles_party(mon)
	bs._new_button_grid = GridContainer.new()
	bs._button_area = VBoxContainer.new()
	_wire_menu_buttons(bs)

	bs._build_top_menu(0)

	# [M26c-3] TOP now builds into the real 2x2 grid (_new_button_grid),
	# not the old plain _new_button_area VBox -- see battle_screen.gd's
	# own _new_button_grid onready doc comment.
	_chk("TOP menu's 4 buttons land in the NEW region's grid",
			_button_texts(bs._new_button_grid).size() == 4)
	_chk("TOP menu does NOT also write into the old (SWITCH/ITEM-only) button area",
			bs._button_area.get_child_count() == 0)


func _test_fight_menu_builds_into_new_area_not_old() -> void:
	var mon := _make_mon("Mover")
	mon.add_move(_load_move(33))
	var bs := BattleScreenShared.new()
	bs._player_party = _singles_party(mon)
	bs._new_button_grid = GridContainer.new()
	bs._new_button_area = VBoxContainer.new()
	bs._button_area = VBoxContainer.new()
	_wire_menu_buttons(bs)
	# [M26c-3 real-proportion fix] _build_fight_menu() also calls
	# _on_fight_move_hovered() for the default-selected move -- see
	# m25h1_3_cursor_test.gd's own identical fix for this same gap.
	bs._move_info_type_label = Label.new()
	bs._move_info_pp_label = Label.new()

	bs._build_fight_menu(0)

	# [M26c-3] The 1 move lands in the real grid; Back is a separate row
	# in _new_button_area below it -- see _build_fight_menu's own doc
	# comment for why Back isn't a 5th grid cell.
	_chk("FIGHT menu's 1 move lands in the NEW region's grid",
			_button_texts(bs._new_button_grid).size() == 1)
	_chk("FIGHT menu's Back button lands in the NEW region's (non-grid) button area",
			_button_texts(bs._new_button_area).size() == 1)
	_chk("FIGHT menu does NOT also write into the old button area",
			bs._button_area.get_child_count() == 0)


func _test_target_select_builds_into_new_area_not_old() -> void:
	# [M26c-4 superseded this test's own original finding] TARGET_SELECT no
	# longer builds any candidate buttons at all -- candidates are wired as
	# hoverable/clickable health-group Controls via _target_select_wired
	# (see m25h1_3_cursor_test.gd's own dedicated coverage for the real
	# chrome/cursor/wiring assertions). Only the single "Back" button still
	# lands in the new region's button area; this test now confirms that
	# narrower, still-true claim instead of the old candidates-as-buttons
	# shape.
	var attacker := _make_mon("Attacker")
	var earthquake := _load_move(89)  # spread move -- only used to reach target-select
	attacker.add_move(earthquake)
	var opp0 := _make_mon("Opp0")
	var opp1 := _make_mon("Opp1")

	var bs := BattleScreenShared.new()
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

	# _health_group_for()/_field_slot_for() need real party objects (not the
	# null defaults a bare BattleScreenShared.new() carries) -- see
	# m25h1_3_cursor_test.gd's own fix for the duplicate-group bug this
	# omission caused there. [Doubles-split roadmap, step 6] The old
	# doubles-only _opp_groups_d/_ply_groups_d/_opp_sprites_d/_ply_sprites_d
	# arrays are gone -- BattleScreenShared reads the same generic
	# _opp_panels/_ply_panels/_opp_sprites/_ply_sprites arrays regardless of
	# format, sized 2 here for doubles. _panel_for() does `panels[slot] as
	# HealthGroupPanel` -- a plain Control stand-in fails that runtime cast
	# and silently resolves to null (the exact bug m25h1_3_cursor_test.gd's
	# own target-select test hit and fixed), so real HealthGroupPanel
	# instances are needed for the panel arrays; plain Control stubs are
	# still fine for the sprite arrays.
	bs._player_party = ally_party
	bs._opp_party = opp_party
	bs._opp_panels = [HealthGroupPanel.new(), HealthGroupPanel.new()]
	bs._ply_panels = [HealthGroupPanel.new(), HealthGroupPanel.new()]
	bs._opp_sprites = [Control.new(), Control.new()]
	bs._ply_sprites = [Control.new(), Control.new()]

	bs._build_target_select_buttons(0, 0)

	# [Phase B] Each of the 2 live opponents now wires TWO zones (health
	# group + sprite), so the real total is 4, not 2.
	_chk("TARGET_SELECT wires the 2 live opponents as hoverable health groups AND sprites, not buttons",
			bs._target_select_wired.size() == 4)
	_chk("TARGET_SELECT's own Back button lands in the NEW region's button area",
			_button_texts(bs._new_button_area).size() == 1)
	_chk("TARGET_SELECT does NOT also write into the old button area",
			bs._button_area.get_child_count() == 0)

	bs._clear_target_select_hover_wiring()
	bm.queue_free()


# ── 7. [M25h-1.5 superseded this test's own original finding] SWITCH no
# longer builds into EITHER _button_area or _new_button_area at all -- it
# now opens a real separate SwitchSelectScreen overlay, matching M25h-1.4's
# own Item precedent exactly (see switch_select_screen_test.gd for that
# screen's own dedicated coverage). This is a genuine, deliberate
# architecture change, not a regression: confirmed via this session's own
# real screenshot verification that the overlay renders correctly.
# Rewritten to confirm the NEW real behavior instead of the old
# inline-panel assumption.
func _test_switch_opens_a_real_overlay_not_the_old_button_areas() -> void:
	var mon := _make_mon("SwitchTester")
	var bench := _make_mon("Bench")
	var bs := BattleScreenShared.new()
	bs._player_party = _singles_party(mon, [bench])
	bs._new_button_area = VBoxContainer.new()
	bs._button_area = VBoxContainer.new()
	bs._font_menu = FontFile.new()
	bs._font_menu.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")

	bs._build_switch_buttons(false, 0)

	_chk("SWITCH does NOT write into the old _button_area at all anymore",
			bs._button_area.get_child_count() == 0)
	_chk("SWITCH does NOT write into the new region's button area either",
			bs._new_button_area.get_child_count() == 0)
	_chk("SWITCH instead opens a real separate SwitchSelectScreen overlay",
			bs._switch_select_overlay != null and bs._switch_select_overlay is SwitchSelectScreen)


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
	var bs := BattleScreenShared.new()
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
# re-measured directly against the current .tscn rather than trusted from
# an old screenshot. Deliberately does NOT instantiate battle_screen_doubles
# .tscn into this process's own live tree to check this via
# get_global_rect() -- count_assertions.sh appends --autoplay to every
# scene invocation process-wide (see m25b_menu_test.gd's own established
# "never embed a real battle screen in an autoplay-swept test" precedent),
# and a real BattleScreenShared instance entering the tree would see that
# flag and call _run_autoplay() -> get_tree().quit(), killing this whole
# test process. Reads the two nodes' own real anchor/offset values directly
# instead and reproduces Godot's own point-anchor math by hand.
# [Doubles-split roadmap, step 7] Retargeted from the old monolithic
# battle_screen.tscn (which combined singles/doubles health groups behind
# an _is_doubles_mode flag) to battle_screen_doubles.tscn specifically --
# the OLD `PlayerHealthGroupD1` raw health-group node no longer exists at
# all; step 5's panel-extraction refactor replaced it with `PlayerPanel1`,
# a real HealthGroupPanel instance at a new anchor/offset (this file's own
# node-not-found crash on the stale path is exactly what caught this).
# Every other test in this file reads SharedChrome/ActionRegion instead
# (present, identical, on both split scenes) and is retargeted to
# battle_screen_singles.tscn.
# [Value re-measured, not carried forward] The OLD 11.36px figure was
# screenshot-measured against the pre-split battle_screen.tscn's own
# PlayerHealthGroupD1 node, whose own anchor/offset values had ALSO already
# drifted independently (see CLAUDE.md's own M26c-1 entry: an external
# Godot-editor GUI edit changed that node's offset_bottom sometime before
# this session, landing its own real clearance around ~40px instead) --
# neither the node identity nor its old measured value can be trusted to
# still apply here. Recomputed directly from PlayerPanel1/ActionRegion's own
# CURRENT anchor_top/offset values in battle_screen_doubles.tscn instead:
# (0.68*768 + 5.3599854) vs (0.75*768) = 527.5999854 vs 576.0, a genuine
# ~48.4px clearance -- ample room, no overlap.
func _test_player_health_group_d1_clears_action_region() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen_doubles.tscn")
	var instance: Node = scene.instantiate()
	var d1: Control = instance.get_node("BattleStage/PlayerPanel1")
	var region: Control = instance.get_node("SharedChrome/ActionRegion")

	# PlayerPanel1 is a POINT anchor (anchor_top == anchor_bottom); its own
	# real bottom edge, as a fraction of viewport height, is anchor_top +
	# (its own local offset_bottom / viewport_height). VIEWPORT_HEIGHT
	# matches the real base resolution set explicitly in project.godot
	# (1024x768, since M26a).
	const VIEWPORT_HEIGHT := 768.0
	var d1_bottom_px: float = d1.anchor_top * VIEWPORT_HEIGHT + d1.offset_bottom
	var region_top_px: float = region.anchor_top * VIEWPORT_HEIGHT

	_chk("PlayerPanel1's own bottom edge clears ActionRegion's own top edge (no overlap)",
			d1_bottom_px < region_top_px)
	_chk("the real clearance matches this session's own re-measured ~48.4px, not just 'some' positive gap",
			abs((region_top_px - d1_bottom_px) - 48.4000146) < 0.1)

	instance.queue_free()


# ── 10-14. [M25h-1.1] Real window art for the new region ─────────────────

func _test_action_panel_exists_as_panel_container() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var instance: Node = scene.instantiate()
	var panel: Node = instance.get_node("SharedChrome/ActionRegion/ActionPanel")
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
	var bs := BattleScreenShared.new()
	bs._action_panel = PanelContainer.new()
	bs._status_label = Label.new()
	# [M25h-1.2, font itself since migrated] _setup_action_region_panel()
	# now also applies the real message-context font to _status_label -- a
	# null font here (this function's own production caller, _ready(),
	# always loads one first via _load_battle_fonts()) makes
	# add_theme_font_override log a real engine error rather than silently
	# no-op, so this bare-instance test needs one too, same as
	# _test_status_label_has_real_message_color_override. A plain hand-
	# constructed bitmap FontFile still works fine here -- this test only
	# cares that _setup_action_region_panel() applies WHATEVER _font_message
	# currently holds, not what type it is (that's the OTHER test's job).
	bs._font_message = FontFile.new()
	bs._font_message.load_bitmap_font("res://assets/fonts/latin_normal_message.fnt")
	# [M26c-3 real-proportion fix] _setup_action_region_panel() now also
	# styles MoveInfoType/MoveInfoPP with the real "menu" font -- real
	# @onready fields that never resolve on a bare instance (see
	# m25h1_3_cursor_test.gd's own identical fix for _build_fight_menu's own
	# MoveInfoPanel wiring gap). add_theme_font_override logs a real engine
	# error on a null font, same as _status_label's own font above.
	bs._font_menu = FontFile.new()
	bs._font_menu.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")
	bs._move_info_type_label = Label.new()
	bs._move_info_pp_label = Label.new()

	bs._setup_action_region_panel()

	var style: StyleBox = bs._action_panel.get_theme_stylebox("panel")
	_chk("ActionPanel has a real StyleBoxTexture override applied (not the theme default)",
			style is StyleBoxTexture)
	if style is StyleBoxTexture:
		_chk("the applied texture is a real, non-null ImageTexture (the color-keyed text_window/1.png pull)",
				(style as StyleBoxTexture).texture != null)
		_chk("the applied margins match this session's own measured 6px corner (not std.png's own 5px)",
				(style as StyleBoxTexture).texture_margin_left == BattleScreenShared._ACTION_PANEL_MARGIN)


func _test_action_panel_key_color_is_distinct_from_message_box_key_color() -> void:
	# [Step 0 finding] text_window/1.png (the real B_WIN_MSG/action-menu/
	# move-select asset, per LoadUserWindowBorderGfx -> LoadWindowGfx ->
	# sWindowFrames[gSaveBlock2Ptr->optionsWindowFrameType], default 0 on a
	# fresh save) uses its OWN background-key color, genuinely different
	# from std.png's own (the file Phase 4e's _setup_message_box already
	# uses for the separately-styled, untouched-by-this-session log) --
	# confirms these are two distinct real assets, not the same file reused.
	var action_key := BattleScreenShared._ACTION_PANEL_KEY_COLOR
	var message_key := BattleScreenShared._MESSAGE_BOX_KEY_COLOR
	_chk("text_window/1.png's own key color is confirmed different from std.png's own",
			not action_key.is_equal_approx(message_key))
	_chk("text_window/1.png's own key color matches this session's own direct pixel inspection (98,197,98,255)",
			action_key.is_equal_approx(Color8(98, 197, 98, 255)))
	_chk("text_window/1.png's own margin (6px) is confirmed different from std.png's own (5px)",
			not is_equal_approx(BattleScreenShared._ACTION_PANEL_MARGIN, BattleScreenShared._MESSAGE_BOX_MARGIN))


func _test_color_keyed_texture_generalizes_to_a_custom_key_color() -> void:
	# Small synthetic image (no disk I/O) -- mirrors
	# phase4e_message_box_test.gd's own established
	# _test_color_keyed_texture_synthetic precedent, but exercises the new
	# explicit key_color param instead of relying on the default.
	var img := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	var custom_key := Color8(1, 2, 3, 255)
	img.set_pixel(0, 0, custom_key)
	img.set_pixel(1, 0, Color.WHITE)

	var tex: ImageTexture = BattleScreenShared._color_keyed_texture(img, custom_key)
	var result: Image = tex.get_image()

	_chk("a custom key color's own matching pixel becomes real alpha=0",
			result.get_pixel(0, 0).a == 0.0)
	_chk("a non-matching pixel (white) is left untouched",
			result.get_pixel(1, 0).is_equal_approx(Color.WHITE))
	_chk("the SAME custom key color is correctly NOT matched by the default (std.png) key check",
			not BattleScreenShared._is_message_box_key_color(custom_key))


func _test_status_label_has_real_message_color_override() -> void:
	# [M25h-1.2 superseded this test's own original Phase 4e/M25h-1.1
	# finding; superseded AGAIN by the message-box font migration] Phase
	# 4e/M25h-1.1 originally fixed StatusLabel's white-on-white risk with a
	# flat dark `font_color` override, correct for the engine's generic
	# default font. M25h-1.2 replaced that generic font with a real bitmap
	# font whose glyph pixels were already fully colored (baked in at
	# atlas-generation time), making a neutral, non-tinting Color(1,1,1,1)
	# the correct override instead. The message-box font migration (see
	# _font_message's own doc comment) replaced THAT bitmap font with a
	# real TTF for _font_message specifically -- a TTF carries no baked-in
	# color at all, so neutral white would now be genuinely invisible
	# against the message box's own light interior art. The correct
	# override is once again a real, non-neutral color choice — this time
	# _MESSAGE_FONT_COLOR (red, matching source's own B_WIN_ACTION_PROMPT
	# scheme), plus a new real font_shadow_color override this TTF also
	# needs that the bitmap font never did (its shadow was baked into the
	# glyph pixels too). Confirmed via this session's own real screenshot
	# verification. Bare-instance direct call, same reasoning as the test
	# immediately above; _font_message loaded for real (from disk, via the
	# real production _load_battle_fonts() path this time, not a manual
	# bitmap-font stub, since the whole point here is confirming the real
	# TTF's color scheme) so _setup_action_region_panel's font-override
	# lines have a real resource to apply.
	var bs := BattleScreenShared.new()
	bs._action_panel = PanelContainer.new()
	var label := Label.new()
	bs._status_label = label
	bs._load_battle_fonts()
	# [M26c-3 real-proportion fix] Same MoveInfoPanel wiring gap as the test
	# above -- see that test's own comment.
	bs._move_info_type_label = Label.new()
	bs._move_info_pp_label = Label.new()

	bs._setup_action_region_panel()

	_chk("StatusLabel has the real message-context font applied",
			label.get_theme_font("font") == bs._font_message)
	_chk("StatusLabel has a font_color override (not left at the engine's own default)",
			label.has_theme_color_override("font_color"))
	if label.has_theme_color_override("font_color"):
		var c: Color = label.get_theme_color("font_color")
		_chk("the override is the real message color (red), not a neutral pass-through -- this TTF has no baked-in color",
				c.is_equal_approx(BattleScreenShared._MESSAGE_FONT_COLOR))
	_chk("StatusLabel also has a real font_shadow_color override (the TTF has no baked-in shadow either)",
			label.has_theme_color_override("font_shadow_color"))
	if label.has_theme_color_override("font_shadow_color"):
		_chk("the shadow override is the real message shadow color (black)",
				label.get_theme_color("font_shadow_color").is_equal_approx(BattleScreenShared._MESSAGE_FONT_SHADOW_COLOR))
