extends Node

# [M26E4-2] Regression suite for the real Summary/Stats screen skeleton --
# see summary_screen.gd's own doc comment for the full architecture
# rationale and Step 0 source citations (docs/m26_e4_recon.md §1.3/§3).
#
# [M26E4-3] Extended with SKILLS + MOVES(+detail) dynamic-content coverage --
# nature-driven stat coloring, ribbons, ability text, the PP 4-tier ramp,
# move-row content (real move vs. empty-slot placeholder), move
# selection/deselection, the detail panel's power/accuracy sentinel text,
# and page/mon-change clearing the selection. See summary_screen.gd's own
# per-section doc comments for the exact 001_Summary.rb citations these
# assertions are checked against.
#
# [Deliberately NOT tested here] The real on-screen visual result (real
# page-background art, chrome positions, legible text) -- matches every
# prior M25h/M26E3/M26E4 suite's own established precedent of scoping
# automated coverage to pure logic + bare-instance direct calls, leaving the
# real end-to-end proof to this session's own mandatory real screenshot
# pass. EVS/IVS page content and INFO page's own dynamic content (types,
# ability text there, EXP bar) remain E4-4's job, unbuilt here.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_real_pack_assets_exist_with_real_dimensions()
	_test_setup_clamps_start_index_into_range()
	_test_refresh_shows_correct_page_background_and_name()
	_test_refresh_shows_correct_mon_chrome_text()
	_test_refresh_shows_none_when_no_held_item()
	_test_refresh_shows_real_item_name_when_holding_one()
	_test_page_nav_clamps_at_zero()
	_test_page_nav_clamps_at_last_page()
	_test_page_nav_buttons_disabled_at_boundaries()
	_test_mon_cycling_wraps_forward()
	_test_mon_cycling_wraps_backward()
	_test_mon_nav_buttons_disabled_for_single_member_party()
	_test_close_emits_signal_with_current_mon_index()
	_test_escape_closes_and_emits_signal()
	_test_nav_buttons_use_real_font_and_chrome()
	_test_summary_button_now_wired_not_disabled()
	_test_summary_button_opens_overlay_and_hides_submenu()
	_test_opening_summary_twice_is_idempotent()
	_test_closing_summary_reopens_submenu_at_last_viewed_slot()
	_test_escape_while_summary_open_does_not_tear_down_submenu()

	# ── E4-3: SKILLS page ──
	_test_skills_ribbons_always_none()
	_test_info_item_hidden_outside_info_page()
	_test_skills_stat_values_shown()
	_test_skills_raised_stat_colored_red()
	_test_skills_lowered_stat_colored_blue()
	_test_skills_neutral_nature_all_neutral_colored()
	_test_skills_hp_never_colored()
	_test_skills_nodes_hidden_outside_skills_page()

	# ── E4-3: MOVES page ──
	_test_moves_real_move_row_shows_type_name_pp()
	_test_moves_empty_slot_shows_placeholder()
	_test_pp_tier_boundaries()
	_test_moves_row_click_selects_and_shows_detail()
	_test_moves_row_click_again_deselects()
	_test_moves_background_swaps_only_when_selected()
	_test_moves_page_change_resets_selection()
	_test_moves_mon_change_resets_selection()
	_test_moves_nodes_hidden_outside_moves_page()

	# ── E4-3: move detail panel ──
	_test_detail_power_sentinel_status_move()
	_test_detail_power_sentinel_variable_power()
	_test_detail_power_real_value()
	_test_detail_accuracy_sentinel_always_hits()
	_test_detail_accuracy_real_value()
	_test_detail_category_icon_and_description()

	var total := _pass + _fail
	print("summary_screen_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % label)


# ── Fixtures ─────────────────────────────────────────────────────────────

func _make_mon(mon_name: String, dex: int = 1, hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.national_dex_num = dex
	var types: Array[int] = [TypeChart.TYPE_NORMAL]
	sp.types = types
	sp.base_hp = hp
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	var ivs: Array[int] = [0, 0, 0, 0, 0, 0]
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, ivs)


func _make_item(item_name: String) -> ItemData:
	var item := ItemData.new()
	item.item_name = item_name
	return item


# category: 0=Physical, 1=Special, 2=Status (scripts/gen_moves.py's own
# PHYS/SPEC/STAT convention — MoveData has no named constant for this).
func _make_move(move_name: String, type: int = TypeChart.TYPE_NORMAL,
		category: int = 0, power: int = 40, accuracy: int = 100,
		pp: int = 10, description: String = "") -> MoveData:
	var move := MoveData.new()
	move.move_name = move_name
	move.type = type
	move.category = category
	move.power = power
	move.accuracy = accuracy
	move.pp = pp
	move.description = description
	return move


# A mon with a real, specific nature (default Adamant: +Atk -SpAtk) so the
# SKILLS-page raised/lowered coloring tests have something to color.
func _make_mon_with_nature(mon_name: String, dex: int,
		nature: int = BattlePokemon.NATURE_ADAMANT) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.national_dex_num = dex
	var types: Array[int] = [TypeChart.TYPE_NORMAL]
	sp.types = types
	sp.base_hp = 100
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	var ivs: Array[int] = [0, 0, 0, 0, 0, 0]
	return BattlePokemon.from_species(sp, 50, nature, ivs)


func _make_party(members: Array) -> BattleParty:
	var p := BattleParty.new()
	var arr: Array[BattlePokemon] = []
	for m: BattlePokemon in members:
		arr.append(m)
	p.members = arr
	var idx: Array[int] = [0]
	p.active_indices = idx
	return p


func _make_battle_screen_with_font() -> BattleScreenShared:
	var bs := BattleScreenShared.new()
	bs._font_menu = FontFile.new()
	bs._font_menu.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")
	return bs


func _make_overlay(bs: BattleScreenShared, party: BattleParty, start_index: int) -> SummaryScreen:
	var scene: PackedScene = load("res://scenes/battle/summary_screen.tscn")
	var overlay: SummaryScreen = scene.instantiate()
	overlay.setup(bs, party, start_index)
	return overlay


func _is_chrome_stripped(btn: Button) -> bool:
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		if not (btn.get_theme_stylebox(state) is StyleBoxEmpty):
			return false
	return true


# ── Asset integrity ──────────────────────────────────────────────────────

func _test_real_pack_assets_exist_with_real_dimensions() -> void:
	# [M26 Fire-Red art swap, pivot] The raw pokefirered-expansion GBA
	# tile/tilemap/palette decode this test originally checked (a 240x160
	# native-GBA-resolution convention) shipped with a real, confirmed
	# defect -- the whole top-left portrait quadrant rendered as a void,
	# since Fire Red's real BG-tile data genuinely leaves that region
	# blank (the portrait is a separate hardware sprite there, not BG-tile
	# content) and this project's own dark Backdrop node showed through
	# it. Replaced with a flat pull from a ready-composited Essentials
	# plugin pack ("FRLG Summary Screen" v2.0, `assets/FRLG Summary
	# Screen/`) instead -- see `gen_summary_screen_sprites_frlg.py`'s own
	# doc header for the full pivot rationale. That pack's own canvas is
	# 512x384 (2x its native 256x192 Essentials canvas, matching the
	# Emerald UI Pack's own already-established convention for this
	# project, NOT the raw-GBA-hardware 240x160 this test used to check)
	# -- `GbaLayer` stretches whichever texture is assigned to fill its
	# fixed 960x640 box regardless of the source's own native resolution,
	# so this dimension change needed no `.tscn` layout changes.
	var dir := "res://assets/sprites/battle_ui/summary/"
	var page_files := ["summary_frlg_frame_base.png", "summary_frlg_page_skills.png",
			"summary_frlg_page_moves.png", "summary_frlg_page_evs_ivs.png"]
	for f in page_files:
		var tex: Texture2D = load(dir + f)
		_chk("%s exists" % f, tex != null)
		if tex != null:
			_chk("%s is 512x384" % f, tex.get_width() == 512 and tex.get_height() == 384)

	var cursor: Texture2D = load(dir + "summary_frlg_move_selection_cursor_left.png")
	_chk("move_selection_cursor_left exists", cursor != null)
	if cursor != null:
		_chk("move_selection_cursor_left is 64x64",
				cursor.get_width() == 64 and cursor.get_height() == 64)

	var exp_bar: Texture2D = load(dir + "summary_frlg_exp_bar.png")
	_chk("exp_bar exists", exp_bar != null)
	if exp_bar != null:
		_chk("exp_bar is 96x8", exp_bar.get_width() == 96 and exp_bar.get_height() == 8)

	# The 7 old leftover files are confirmed GONE, not just unconsumed --
	# a future re-run of the old (never-existing-here) check would
	# silently pass on stale files if they ever reappeared, so assert
	# their absence explicitly instead.
	var dead_files := ["summary_bg_evs_ivs.png", "summary_bg_info.png",
			"summary_bg_movedetail.png", "summary_bg_moves.png",
			"summary_bg_skills.png", "summary_cursor_move.png",
			"summary_overlay_exp.png"]
	for f in dead_files:
		_chk("%s confirmed deleted (dead Emerald UI Pack leftover)" % f,
				not FileAccess.file_exists(dir + f))


# ── Setup / clamping ─────────────────────────────────────────────────────

func _test_setup_clamps_start_index_into_range() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("Bulbasaur", 1), _make_mon("Charmander", 4)])
	var overlay := _make_overlay(bs, party, 99)
	_chk("out-of-range start_index clamps to last member", overlay._mon_index == 1)
	overlay.queue_free()

	var overlay2 := _make_overlay(bs, party, -5)
	_chk("negative start_index clamps to 0", overlay2._mon_index == 0)
	overlay2.queue_free()


# ── Refresh / chrome text ────────────────────────────────────────────────

func _test_refresh_shows_correct_page_background_and_name() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("Bulbasaur", 1)])
	var overlay := _make_overlay(bs, party, 0)

	# [M26E4 rework] The portrait/frame BASE layer is real, always-on, and
	# never swapped (see gen_summary_screen_sprites.py's own doc comment) --
	# only the page-specific OVERLAY on top of it changes per page.
	_chk("portrait base is the real, always-on frame",
			(overlay._portrait_base.texture as Texture2D).resource_path.ends_with("summary_frlg_frame_base.png"))

	_chk("page 0 shows INFO", overlay._page_name_label.text == "INFO")
	_chk("page 0 (INFO) has no overlay yet -- the base layer alone is correct",
			overlay._page_overlay.texture == null)

	overlay._on_next_page_pressed()
	_chk("page 1 shows SKILLS", overlay._page_name_label.text == "SKILLS")
	_chk("page 1 overlay is the real summary_frlg_page_skills.png",
			(overlay._page_overlay.texture as Texture2D).resource_path.ends_with("summary_frlg_page_skills.png"))
	_chk("portrait base is unchanged by the page swap",
			(overlay._portrait_base.texture as Texture2D).resource_path.ends_with("summary_frlg_frame_base.png"))

	overlay._on_next_page_pressed()
	_chk("page 2 shows MOVES", overlay._page_name_label.text == "MOVES")
	_chk("page 2 overlay is the real summary_frlg_page_moves.png",
			(overlay._page_overlay.texture as Texture2D).resource_path.ends_with("summary_frlg_page_moves.png"))

	overlay._on_next_page_pressed()
	_chk("page 3 shows EVS/IVS", overlay._page_name_label.text == "EVS/IVS")
	# [M26 Fire-Red art swap] Was "no overlay yet -- E4-4's own future job";
	# this session pulled the real Fire-Red EVS/IVS page BACKGROUND as
	# bonus scope (see gen_summary_screen_sprites_frlg.py's own doc
	# comment) -- the DYNAMIC content (real EV/IV values) is still E4-4's
	# own future job, unbuilt here, but the background is no longer null.
	_chk("page 3 (EVS-IVS) overlay is the real summary_frlg_page_evs_ivs.png",
			(overlay._page_overlay.texture as Texture2D).resource_path.ends_with("summary_frlg_page_evs_ivs.png"))

	overlay.queue_free()


func _test_refresh_shows_correct_mon_chrome_text() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon("Charizard", 6)
	mon.level = 36
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)

	_chk("nickname shows species name", overlay._nickname_label.text == "Charizard")
	_chk("species label shows species name", overlay._species_label.text == "Charizard")
	_chk("level label shows real Lv text", overlay._level_label.text == "Lv36")
	# [INFO page real content, Fire-Red-source correction] "No." is now a
	# separate real label pill (DexNumberPillLabel), not baked into this
	# value's own text -- see _refresh()'s own doc comment.
	_chk("dex label shows zero-padded dex number", overlay._dex_label.text == "006")
	_chk("mon sprite texture loaded", overlay._mon_sprite.texture != null)
	overlay.queue_free()


func _test_refresh_shows_none_when_no_held_item() -> void:
	# [M26E4 rework] Held item is real SKILLS-page content in source
	# (PSS_DATA_WINDOW_SKILLS_HELD_ITEM lives in sPageSkillsTemplate, not
	# anywhere on INFO) -- ItemLabel's own text is only ever set while
	# _refresh_skills_page() is actually showing, so this must navigate
	# there first, matching _test_skills_ribbons_always_none's own
	# established pattern for the same reason.
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon("Squirtle", 7)
	mon.held_item = null
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()  # INFO -> SKILLS
	_chk("no held item shows 'None'", overlay._item_label.text == "None")
	overlay.queue_free()


func _test_refresh_shows_real_item_name_when_holding_one() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon("Squirtle", 7)
	mon.held_item = _make_item("Leftovers")
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()  # INFO -> SKILLS
	_chk("held item shows its real name", overlay._item_label.text == "Leftovers")
	overlay.queue_free()


# ── Page navigation -- clamps, does NOT wrap ─────────────────────────────

func _test_page_nav_clamps_at_zero() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("Bulbasaur", 1)])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_prev_page_pressed()
	_chk("page stays at 0, does not go negative", overlay._page == 0)
	overlay.queue_free()


func _test_page_nav_clamps_at_last_page() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("Bulbasaur", 1)])
	var overlay := _make_overlay(bs, party, 0)
	for i in range(10):
		overlay._on_next_page_pressed()
	_chk("page clamps at NUM_PAGES-1, does not wrap", overlay._page == SummaryScreen.NUM_PAGES - 1)
	overlay.queue_free()


func _test_page_nav_buttons_disabled_at_boundaries() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("Bulbasaur", 1)])
	var overlay := _make_overlay(bs, party, 0)
	_chk("prev-page disabled on first page", overlay._prev_page_btn.disabled)
	_chk("next-page enabled on first page", not overlay._next_page_btn.disabled)
	for i in range(SummaryScreen.NUM_PAGES - 1):
		overlay._on_next_page_pressed()
	_chk("next-page disabled on last page", overlay._next_page_btn.disabled)
	_chk("prev-page enabled on last page", not overlay._prev_page_btn.disabled)
	overlay.queue_free()


# ── Mon cycling -- wraps, unlike page nav ────────────────────────────────

func _test_mon_cycling_wraps_forward() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("A", 1), _make_mon("B", 2), _make_mon("C", 3)])
	var overlay := _make_overlay(bs, party, 2)
	overlay._on_next_mon_pressed()
	_chk("cycling forward past the last member wraps to 0", overlay._mon_index == 0)
	overlay.queue_free()


func _test_mon_cycling_wraps_backward() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("A", 1), _make_mon("B", 2), _make_mon("C", 3)])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_prev_mon_pressed()
	_chk("cycling backward past the first member wraps to the last", overlay._mon_index == 2)
	overlay.queue_free()


func _test_mon_nav_buttons_disabled_for_single_member_party() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("A", 1)])
	var overlay := _make_overlay(bs, party, 0)
	_chk("prev-mon disabled for a 1-member party", overlay._prev_mon_btn.disabled)
	_chk("next-mon disabled for a 1-member party", overlay._next_mon_btn.disabled)
	overlay._on_next_mon_pressed()
	_chk("cycling is a no-op for a 1-member party", overlay._mon_index == 0)
	overlay.queue_free()


# ── Close / ESC ───────────────────────────────────────────────────────────

func _test_close_emits_signal_with_current_mon_index() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("A", 1), _make_mon("B", 2)])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_mon_pressed()
	var last_seen := [-1]
	overlay.closed.connect(func(idx): last_seen[0] = idx)
	overlay._on_close_pressed()
	_chk("closed signal reports the currently-viewed mon index", last_seen[0] == 1)
	overlay.queue_free()


func _test_escape_closes_and_emits_signal() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("A", 1)])
	var overlay := _make_overlay(bs, party, 0)
	add_child(overlay)
	var closed_fired := [false]
	overlay.closed.connect(func(idx): closed_fired[0] = true)
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	overlay._unhandled_input(event)
	_chk("ESC fires the closed signal", closed_fired[0])
	overlay.queue_free()


func _test_nav_buttons_use_real_font_and_chrome() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon("A", 1)])
	var overlay := _make_overlay(bs, party, 0)
	for btn in [overlay._prev_page_btn, overlay._next_page_btn, overlay._prev_mon_btn,
			overlay._next_mon_btn, overlay._close_btn]:
		_chk("nav button chrome-stripped", _is_chrome_stripped(btn))
		_chk("nav button uses real menu font", btn.get_theme_font("font") == bs._font_menu)
	overlay.queue_free()


# ── SwitchSelectScreen wiring (E4-2's own return-path contract) ──────────

func _make_switch_screen_party() -> BattleParty:
	return _make_party([_make_mon("Active", 1), _make_mon("Bench1", 2), _make_mon("Bench2", 3)])


func _make_switch_screen(bs: BattleScreenShared) -> SwitchSelectScreen:
	var scene: PackedScene = load("res://scenes/battle/switch_select_screen.tscn")
	var overlay: SwitchSelectScreen = scene.instantiate()
	overlay.setup(bs, 0, false)
	return overlay


func _test_summary_button_now_wired_not_disabled() -> void:
	var bs := _make_battle_screen_with_font()
	bs._player_party = _make_switch_screen_party()
	var overlay := _make_switch_screen(bs)
	overlay._show_action_submenu(1)
	var summary_btn: Button = null
	for child in overlay._action_submenu.get_children():
		if child is Button and (child as Button).text.contains("Summary"):
			summary_btn = child
	_chk("Summary button exists", summary_btn != null)
	_chk("Summary button is no longer a disabled stub", summary_btn != null and not summary_btn.disabled)
	overlay.queue_free()


func _test_summary_button_opens_overlay_and_hides_submenu() -> void:
	var bs := _make_battle_screen_with_font()
	bs._player_party = _make_switch_screen_party()
	var overlay := _make_switch_screen(bs)
	overlay._show_action_submenu(1)
	overlay._on_submenu_summary_pressed(1)
	_chk("Summary overlay is created", overlay._summary_screen != null and is_instance_valid(overlay._summary_screen))
	_chk("action submenu is hidden, not destroyed", overlay._action_submenu != null and not overlay._action_submenu.visible)
	_chk("Summary overlay starts on the picked slot", overlay._summary_screen._mon_index == 1)
	overlay.queue_free()


func _test_opening_summary_twice_is_idempotent() -> void:
	var bs := _make_battle_screen_with_font()
	bs._player_party = _make_switch_screen_party()
	var overlay := _make_switch_screen(bs)
	overlay._show_action_submenu(1)
	overlay._on_submenu_summary_pressed(1)
	var first := overlay._summary_screen
	overlay._on_submenu_summary_pressed(1)
	_chk("a second Summary press does not stack a duplicate overlay",
			overlay._summary_screen == first)
	overlay.queue_free()


func _test_closing_summary_reopens_submenu_at_last_viewed_slot() -> void:
	var bs := _make_battle_screen_with_font()
	bs._player_party = _make_switch_screen_party()
	var overlay := _make_switch_screen(bs)
	overlay._show_action_submenu(1)
	overlay._on_submenu_summary_pressed(1)
	overlay._summary_screen._on_next_mon_pressed()
	# Summary was opened for slot 1 but the player cycled forward to slot 2
	# before closing -- the real return-path contract (docs/m26_e4_recon.md
	# §1.3) hands back gLastViewedMonIndex, NOT the originally-picked slot.
	overlay._on_summary_screen_closed(2)
	_chk("Summary overlay is torn down", overlay._summary_screen == null)
	_chk("a fresh action submenu reopened", overlay._action_submenu != null and overlay._action_submenu.visible)
	var primary_found := false
	for child in overlay._action_submenu.get_children():
		if child is Button and (child as Button).pressed.get_connections().size() > 0:
			for c in (child as Button).pressed.get_connections():
				if (c["callable"] as Callable).get_bound_arguments() == [2]:
					primary_found = true
	_chk("the reopened submenu targets the last-viewed slot (2), not the original pick (1)",
			primary_found)
	overlay.queue_free()


func _test_escape_while_summary_open_does_not_tear_down_submenu() -> void:
	var bs := _make_battle_screen_with_font()
	bs._player_party = _make_switch_screen_party()
	var overlay := _make_switch_screen(bs)
	add_child(overlay)
	overlay._show_action_submenu(1)
	overlay._on_submenu_summary_pressed(1)
	var submenu_before := overlay._action_submenu
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	overlay._unhandled_input(event)
	_chk("switch_select_screen's own ESC handling is a no-op while Summary is open",
			overlay._action_submenu == submenu_before)
	overlay.queue_free()


# ── E4-3: SKILLS page ────────────────────────────────────────────────────

# [M26E4 rework] Nature-name and Ability tests removed here -- both were
# built against the earlier Emerald-UI-Pack-based E4-3 pass, which showed
# them as their own SKILLS-page text boxes. Direct source verification
# (pokemon_summary_screen.c's own sSummaryTemplate/sPageSkillsTemplate)
# found neither is real SKILLS-page content: Nature's own NAME appears
# only in INFO's Trainer Memo sentence, still deferred (needs Met Level/
# Met Location, tracked nowhere in this project). [Fire-Red-source
# correction] Ability was described here as real INFO-page content via
# Emerald's own `PSS_DATA_WINDOW_INFO_ABILITY` -- true for Emerald, but
# this screen's art is Fire-Red-sourced, and Fire Red's own
# `pokemon_summary_screen.c` has no Ability display anywhere on the
# screen at all. Nature's own EFFECT (stat coloring) is still fully
# covered below.

func _test_skills_ribbons_always_none() -> void:
	var bs := _make_battle_screen_with_font()
	var party := _make_party([_make_mon_with_nature("Machop", 66)])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	_chk("ribbons always show 'None' (no ribbon system exists)", overlay._ribbons_label.text == "None")
	overlay.queue_free()


func _test_info_item_hidden_outside_info_page() -> void:
	# [Fire-Red-source correction, supersedes this test's own earlier
	# Emerald-sourced assumption] Held item is real INFO-page content in
	# Fire Red's own source (PrintInfoPage's itemNameStrBuf print), not
	# SKILLS -- Emerald's PSS_DATA_WINDOW_SKILLS_HELD_ITEM/
	# sPageSkillsTemplate citation this test used to carry is real, but
	# for the wrong engine; this screen's art is Fire-Red-sourced.
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Squirtle", 7)
	mon.held_item = _make_item("Leftovers")
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)  # starts on INFO
	_chk("item label visible on INFO", overlay._item_label.visible)
	_chk("item label shows the real held item on INFO", overlay._item_label.text == "Leftovers")

	overlay._on_next_page_pressed()  # -> SKILLS
	_chk("item label hidden on SKILLS", not overlay._item_label.visible)
	overlay.queue_free()


func _test_skills_stat_values_shown() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Machop", 66, BattlePokemon.NATURE_HARDY)
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	var labels := overlay._stat_value_labels
	_chk("HP shows current/max", labels[BattlePokemon.STAT_HP].text
			== "%d/%d" % [mon.current_hp, mon.max_hp])
	_chk("Atk shows the plain stat number", labels[BattlePokemon.STAT_ATK].text == str(mon.attack))
	_chk("Def shows the plain stat number", labels[BattlePokemon.STAT_DEF].text == str(mon.defense))
	_chk("SpAtk shows the plain stat number", labels[BattlePokemon.STAT_SPATK].text == str(mon.sp_attack))
	_chk("SpDef shows the plain stat number", labels[BattlePokemon.STAT_SPDEF].text == str(mon.sp_defense))
	_chk("Speed shows the plain stat number", labels[BattlePokemon.STAT_SPEED].text == str(mon.speed))
	overlay.queue_free()


func _test_skills_raised_stat_colored_red() -> void:
	var bs := _make_battle_screen_with_font()
	# Adamant: +Atk -SpAtk.
	var mon := _make_mon_with_nature("Machop", 66, BattlePokemon.NATURE_ADAMANT)
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	var lbl: Label = overlay._stat_value_labels[BattlePokemon.STAT_ATK]
	_chk("raised stat uses the real raised-fg color",
			lbl.get_theme_color("font_color") == SummaryScreen._COLOR_RAISED_FG)
	_chk("raised stat uses the real raised-shadow color",
			lbl.get_theme_color("font_shadow_color") == SummaryScreen._COLOR_RAISED_SHADOW)
	overlay.queue_free()


func _test_skills_lowered_stat_colored_blue() -> void:
	var bs := _make_battle_screen_with_font()
	# Adamant: +Atk -SpAtk.
	var mon := _make_mon_with_nature("Machop", 66, BattlePokemon.NATURE_ADAMANT)
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	var lbl: Label = overlay._stat_value_labels[BattlePokemon.STAT_SPATK]
	_chk("lowered stat uses the real lowered-fg color",
			lbl.get_theme_color("font_color") == SummaryScreen._COLOR_LOWERED_FG)
	_chk("lowered stat uses the real lowered-shadow color",
			lbl.get_theme_color("font_shadow_color") == SummaryScreen._COLOR_LOWERED_SHADOW)
	overlay.queue_free()


func _test_skills_neutral_nature_all_neutral_colored() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Machop", 66, BattlePokemon.NATURE_HARDY)
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	var all_neutral := true
	for lbl in overlay._stat_value_labels:
		if (lbl as Label).get_theme_color("font_color") != SummaryScreen._COLOR_NEUTRAL_FG:
			all_neutral = false
	_chk("a neutral nature leaves every stat neutral-colored", all_neutral)
	overlay.queue_free()


func _test_skills_hp_never_colored() -> void:
	var bs := _make_battle_screen_with_font()
	# Adamant's own raised/lowered pair never includes STAT_HP by
	# construction (BattlePokemon._nature_stat_pair only ever returns
	# STAT_ATK..STAT_SPEED) -- this confirms HP stays neutral regardless.
	var mon := _make_mon_with_nature("Machop", 66, BattlePokemon.NATURE_ADAMANT)
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	var lbl: Label = overlay._stat_value_labels[BattlePokemon.STAT_HP]
	_chk("HP is never colored raised/lowered, always neutral",
			lbl.get_theme_color("font_color") == SummaryScreen._COLOR_NEUTRAL_FG)
	overlay.queue_free()


func _test_skills_nodes_hidden_outside_skills_page() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Machop", 66)
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)  # starts on INFO
	_chk("ribbons label hidden on INFO", not overlay._ribbons_label.visible)
	var any_stat_visible := false
	for lbl in overlay._stat_value_labels:
		if (lbl as Label).visible:
			any_stat_visible = true
	_chk("stat value labels hidden on INFO", not any_stat_visible)

	overlay._on_next_page_pressed()  # -> SKILLS
	_chk("ribbons label visible on SKILLS", overlay._ribbons_label.visible)
	var all_stat_visible := true
	for lbl in overlay._stat_value_labels:
		if not (lbl as Label).visible:
			all_stat_visible = false
	_chk("stat value labels visible on SKILLS", all_stat_visible)
	overlay.queue_free()


# ── E4-3: MOVES page ─────────────────────────────────────────────────────

func _test_moves_real_move_row_shows_type_name_pp() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Flamethrower", TypeChart.TYPE_FIRE, 1, 90, 100, 15))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()  # -> MOVES

	var row: Dictionary = overlay._move_rows[0]
	_chk("real move row is enabled", not (row["button"] as Button).disabled)
	_chk("real move row shows its type icon", (row["type_icon"] as TextureRect).visible)
	_chk("real move row shows the real move name", (row["name_label"] as Label).text == "Flamethrower")
	_chk("real move row shows real PP at full", (row["pp_label"] as Label).text == "15/15")
	_chk("full PP uses tier-0 color",
			(row["pp_label"] as Label).get_theme_color("font_color") == SummaryScreen._PP_TIER_FG[0])
	overlay.queue_free()


func _test_moves_empty_slot_shows_placeholder() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Flamethrower"))  # only 1 of 4 slots filled
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()

	var row: Dictionary = overlay._move_rows[1]
	_chk("empty move row is disabled", (row["button"] as Button).disabled)
	_chk("empty move row hides its type icon", not (row["type_icon"] as TextureRect).visible)
	_chk("empty move row shows '-' for its name", (row["name_label"] as Label).text == "-")
	_chk("empty move row shows '--' for PP", (row["pp_label"] as Label).text == "--")
	overlay.queue_free()


func _test_pp_tier_boundaries() -> void:
	_chk("full PP (4/4) is tier 0", SummaryScreen._pp_tier(4, 4) == 0)
	_chk("more than half (3/4) is tier 0", SummaryScreen._pp_tier(3, 4) == 0)
	_chk("exactly half (2/4) is tier 1", SummaryScreen._pp_tier(2, 4) == 1)
	_chk("exactly a quarter (1/4) is tier 2", SummaryScreen._pp_tier(1, 4) == 2)
	_chk("zero PP is tier 3", SummaryScreen._pp_tier(0, 4) == 3)
	_chk("degenerate zero-total PP defaults to tier 0", SummaryScreen._pp_tier(0, 0) == 0)

	# [Fire-Red-source correction] `GetMoveTextColor` (pokemon_summary_
	# screen.c) special-cases maxPP==3 and maxPP==2 rather than falling out
	# of the general proportional formula -- this is the exact pair the
	# general formula alone gets wrong (2/3 real-PP-fraction-wise reads as
	# "more than half", but source says tier 2/"getting low"). Discriminates
	# the fix from the pre-fix formula, which returned 0 for (2,3).
	_chk("maxPP=3, curPP=2 is tier 2 (source's own special case, not the general formula's answer)",
			SummaryScreen._pp_tier(2, 3) == 2)
	_chk("maxPP=3, curPP=1 is tier 1", SummaryScreen._pp_tier(1, 3) == 1)
	_chk("maxPP=3, curPP=3 (full) is tier 0", SummaryScreen._pp_tier(3, 3) == 0)
	_chk("maxPP=2, curPP=1 is tier 1", SummaryScreen._pp_tier(1, 2) == 1)
	_chk("maxPP=2, curPP=2 (full) is tier 0", SummaryScreen._pp_tier(2, 2) == 0)


func _test_moves_row_click_selects_and_shows_detail() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Flamethrower", TypeChart.TYPE_FIRE, 1, 90, 100, 15, "A blast of fire."))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()

	overlay._on_move_row_pressed(0)
	_chk("clicking a row selects it", overlay._selected_move_index == 0)
	_chk("detail power label becomes visible", overlay._move_detail_power_label.visible)
	# [Fire-Red-source correction] Real source's own buffers carry no
	# "Pow "/"Acc " prefix and no "%" sign -- those come from the real
	# POWER/ACCURACY label pills now baked into summary_frlg_page_
	# movedetail.png instead. See summary_screen.gd's own
	# _refresh_move_detail() doc comment for the full citation.
	_chk("detail power shows the real power", overlay._move_detail_power_label.text == "90")
	_chk("detail accuracy shows the real accuracy", overlay._move_detail_accuracy_label.text == "100")
	_chk("detail description shows the real text",
			overlay._move_detail_desc_label.text == "A blast of fire.")
	overlay.queue_free()


func _test_moves_row_click_again_deselects() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Flamethrower"))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()

	overlay._on_move_row_pressed(0)
	overlay._on_move_row_pressed(0)
	_chk("clicking the same row again deselects it", overlay._selected_move_index == -1)
	_chk("detail power label becomes hidden again", not overlay._move_detail_power_label.visible)
	overlay.queue_free()


func _test_moves_background_swaps_only_when_selected() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Flamethrower"))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()
	_chk("MOVES page with nothing selected uses the normal MOVES overlay",
			(overlay._page_overlay.texture as Texture2D).resource_path.ends_with("summary_frlg_page_moves.png"))

	# [Fire-Red-source correction -- supersedes this test's own earlier
	# claim] Direct read of `PokeSum_CopyNewBgTilemapBeforePageFlip`
	# proves the OPPOSITE of what this test used to assert:
	# `PSS_PAGE_MOVES_INFO` really does load a distinct real tilemap
	# (`sBgTilemap_MovesInfoPage`), not the plain list's own
	# `sBgTilemap_MovesPage`. See summary_screen.gd's own _refresh() doc
	# comment for the full citation.
	overlay._on_move_row_pressed(0)
	_chk("selecting a move DOES swap to the real move-detail overlay",
			(overlay._page_overlay.texture as Texture2D).resource_path.ends_with("summary_frlg_page_movedetail.png"))
	_chk("portrait base is unaffected by move selection",
			(overlay._portrait_base.texture as Texture2D).resource_path.ends_with("summary_frlg_frame_base.png"))

	overlay._on_move_row_pressed(0)  # deselect
	_chk("deselecting reverts to the normal MOVES overlay",
			(overlay._page_overlay.texture as Texture2D).resource_path.ends_with("summary_frlg_page_moves.png"))
	overlay.queue_free()


func _test_moves_page_change_resets_selection() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Flamethrower"))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()
	overlay._on_move_row_pressed(0)
	_chk("selection made before page change", overlay._selected_move_index == 0)

	overlay._on_next_page_pressed()  # -> EVS/IVS
	_chk("leaving MOVES via next-page resets the selection", overlay._selected_move_index == -1)

	overlay._on_prev_page_pressed()  # back to MOVES
	overlay._on_move_row_pressed(0)
	overlay._on_prev_page_pressed()  # -> SKILLS
	_chk("leaving MOVES via prev-page also resets the selection", overlay._selected_move_index == -1)
	overlay.queue_free()


func _test_moves_mon_change_resets_selection() -> void:
	var bs := _make_battle_screen_with_font()
	var mon1 := _make_mon_with_nature("Charizard", 6)
	mon1.add_move(_make_move("Flamethrower"))
	var mon2 := _make_mon_with_nature("Blastoise", 9)
	var party := _make_party([mon1, mon2])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()
	overlay._on_move_row_pressed(0)
	_chk("selection made before mon change", overlay._selected_move_index == 0)

	overlay._on_next_mon_pressed()
	_chk("cycling to a different mon resets the selection", overlay._selected_move_index == -1)
	overlay.queue_free()


func _test_moves_nodes_hidden_outside_moves_page() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Flamethrower"))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()  # -> SKILLS
	var any_row_visible := false
	for row in overlay._move_rows:
		if (row["button"] as Button).visible:
			any_row_visible = true
	_chk("move rows hidden on SKILLS", not any_row_visible)

	overlay._on_next_page_pressed()  # -> MOVES
	var all_row_visible := true
	for row in overlay._move_rows:
		if not (row["button"] as Button).visible:
			all_row_visible = false
	_chk("move rows visible on MOVES", all_row_visible)
	overlay.queue_free()


# ── E4-3: move detail panel ──────────────────────────────────────────────

func _test_detail_power_sentinel_status_move() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Swords Dance", TypeChart.TYPE_NORMAL, 2, 0, 0, 20))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()
	overlay._on_move_row_pressed(0)
	_chk("a status move (power 0) shows the '---' power sentinel",
			overlay._move_detail_power_label.text == "---")
	overlay.queue_free()


func _test_detail_power_sentinel_variable_power() -> void:
	# [Fire-Red-source correction, supersedes this test's own earlier
	# assertion] `BufferMonMoveI` (pokemon_summary_screen.c) treats
	# power<=1 identically -- both get "---", no distinct "???" branch.
	# Grepped Fire Red's own reference tree directly for the
	# "display_damage=="Variable power move"" citation this test used to
	# rely on -- it appears nowhere in it.
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Magnitude", TypeChart.TYPE_GROUND, 0, 1, 100))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()
	overlay._on_move_row_pressed(0)
	_chk("the power=1 variable-power sentinel shows '---', same as power=0",
			overlay._move_detail_power_label.text == "---")
	overlay.queue_free()


func _test_detail_power_real_value() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Flamethrower", TypeChart.TYPE_FIRE, 1, 90, 100))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()
	overlay._on_move_row_pressed(0)
	_chk("a real power value is shown plainly", overlay._move_detail_power_label.text == "90")
	overlay.queue_free()


func _test_detail_accuracy_sentinel_always_hits() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Aerial Ace", TypeChart.TYPE_FLYING, 0, 60, 0))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()
	overlay._on_move_row_pressed(0)
	_chk("accuracy 0 (always hits) shows the '---' sentinel",
			overlay._move_detail_accuracy_label.text == "---")
	overlay.queue_free()


func _test_detail_accuracy_real_value() -> void:
	# [Fire-Red-source correction] Real source's accuracy buffer is a bare
	# number -- no "%" sign appears anywhere in `moveAccuracyStrBufs`.
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Flamethrower", TypeChart.TYPE_FIRE, 1, 90, 85))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()
	overlay._on_move_row_pressed(0)
	_chk("a real accuracy value is shown plainly, no percent sign",
			overlay._move_detail_accuracy_label.text == "85")
	overlay.queue_free()


func _test_detail_category_icon_and_description() -> void:
	var bs := _make_battle_screen_with_font()
	var mon := _make_mon_with_nature("Charizard", 6)
	mon.add_move(_make_move("Flamethrower", TypeChart.TYPE_FIRE, 1, 90, 100, 15, "A blast of fire."))
	var party := _make_party([mon])
	var overlay := _make_overlay(bs, party, 0)
	overlay._on_next_page_pressed()
	overlay._on_next_page_pressed()
	overlay._on_move_row_pressed(0)
	_chk("category icon texture is loaded for a real move",
			overlay._move_detail_category_icon.texture != null)
	_chk("category icon becomes visible when a move is selected",
			overlay._move_detail_category_icon.visible)
	_chk("description shows the real move description",
			overlay._move_detail_desc_label.text == "A blast of fire.")
	overlay.queue_free()
