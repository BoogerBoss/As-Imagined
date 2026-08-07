extends Node

# [M25h-1.5, extended M25h-4, rewritten M26E3-1, extended M26E3-2, rewritten
# M26E3-3] Regression suite for the real separate Switch/Party full-screen
# overlay — see switch_select_screen.gd's own doc comment for the full
# architecture rationale, Step 0 source citations, and the current scope
# (every one of the six slots is now a real, clickable, cursor-selectable
# Button; illegal picks reject with source's own real message; a legal pick
# opens a real Shift/Summary/Cancel — or Send Out/Summary/Cancel — action
# submenu before `mon_chosen` fires).
#
# [Deliberately NOT tested here] The real on-screen visual result (real
# window art, panel positions, legible text, the submenu's own real
# on-screen placement) — matches every prior M25h/M26E3 suite's own
# established precedent of scoping automated coverage to pure logic +
# bare-instance direct calls, leaving the real end-to-end proof to this
# session's own mandatory real screenshot pass.
#
# [Deliberately NOT calling _build_switch_buttons for the zero-candidate
# scenario] Unchanged from the prior session's own established restraint —
# see m25a_switch_aliasing_test.gd for that mechanism's own coverage.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_every_slot_is_a_real_button_singles()
	_test_every_slot_is_a_real_button_doubles()
	_test_forced_replacement_still_omits_cancel()
	_test_default_cursor_is_the_active_panel()
	_test_buttons_use_real_font_and_chrome()
	_test_reject_fainted_slot_shows_message_no_submenu()
	_test_reject_active_slot_shows_message()
	_test_reject_already_selected_doubles_sibling()
	_test_reject_ability_trap_names_holder_and_ability()
	_test_reject_move_trap_generic_message()
	_test_legal_pick_opens_action_submenu_voluntary()
	_test_legal_pick_opens_action_submenu_forced()
	_test_submenu_primary_press_emits_mon_chosen_and_closes()
	_test_submenu_cancel_press_closes_and_reenables_list()
	_test_summary_button_now_opens_a_real_summary_screen()
	_test_escape_closes_submenu_first_when_open()
	_test_escape_after_submenu_closed_still_cancels_voluntary()
	_test_escape_is_a_no_op_during_forced_replacement()
	_test_message_reverts_after_display_duration()
	_test_build_switch_buttons_opens_a_real_wired_overlay()
	_test_build_switch_buttons_hides_the_stale_status_label()
	_test_build_switch_buttons_is_idempotent_while_overlay_open()
	_test_field_slot_propagates_correctly_to_bound_handlers()
	_test_mon_chosen_reaches_real_queue_switch_for_end_to_end()
	_test_mon_chosen_reaches_real_queue_replacement_for_end_to_end()
	_test_cancelled_reaches_real_menu_reset_end_to_end()
	_test_header_shows_the_real_source_string()
	_test_row_includes_real_hp_text_and_status_icon_children()
	_test_all_six_slots_shown_and_all_are_real_buttons()
	_test_real_pack_assets_exist_with_real_dimensions()
	_test_party_status_icon_row_mapping_matches_real_ailment_order()
	_test_held_item_icon_shown_only_when_holding_an_item()
	_test_fainted_dim_helper_darkens_slot_art()
	_test_singles_layout_shape()
	_test_doubles_layout_shape()
	_test_mon_icon_present_on_every_slot()
	_test_ball_icon_defaults_sel_on_active_panel_and_desel_elsewhere()
	_test_hovering_a_bench_row_swaps_ball_and_panel_sel_state()
	_test_cancel_hover_clears_mon_visual_selection()
	_test_hp_bar_trough_and_fill_present_with_correct_zone()
	_test_fainted_row_has_trough_but_no_fill()
	_test_icon_animation_advances_frame_over_real_time()
	_test_selected_icon_bounces_unselected_icon_holds_fixed_shift()

	var total := _pass + _fail
	print("switch_select_screen_test: %d/%d passed" % [_pass, total])
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

func _make_mon(mon_name: String, hp: int = 100, atk: int = 80, def_stat: int = 80,
		spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	var types: Array[int] = [TypeChart.TYPE_NORMAL]
	sp.types = types
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = atk
	sp.base_sp_defense = def_stat
	sp.base_speed = spd
	var ivs: Array[int] = [0, 0, 0, 0, 0, 0]
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, ivs)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


# [M26E3-2] A real dex-bearing variant of _make_mon -- the plain _make_mon
# above leaves national_dex_num at its own PokemonSpecies default (0), which
# has no real icon file on disk, so every icon-specific test below needs a
# REAL dex to get a non-null texture to actually check.
func _make_mon_dex(mon_name: String, dex: int, hp: int = 100) -> BattlePokemon:
	var mon := _make_mon(mon_name, hp)
	mon.species.national_dex_num = dex
	return mon


func _collect_texture_rects(node: Node, out: Array[TextureRect]) -> void:
	if node is TextureRect:
		out.append(node)
	for child in node.get_children():
		_collect_texture_rects(child, out)


func _singles_party_with_bench(active_mon: BattlePokemon, bench: Array) -> BattleParty:
	var p := BattleParty.new()
	var members: Array[BattlePokemon] = [active_mon]
	for m: BattlePokemon in bench:
		members.append(m)
	p.members = members
	var idx: Array[int] = [0]
	p.active_indices = idx
	return p


# [M26E3-3] A real doubles party (2 active + N bench), used by several new
# tests below (the doubles-sibling-already-selected rejection, doubles
# layout shape).
func _doubles_party(active0: BattlePokemon, active1: BattlePokemon, bench: Array) -> BattleParty:
	var p := BattleParty.new()
	var members: Array[BattlePokemon] = [active0, active1]
	for m: BattlePokemon in bench:
		members.append(m)
	p.members = members
	var idx: Array[int] = [0, 1]
	p.active_indices = idx
	return p


func _make_battle_screen_with_font() -> BattleScreenShared:
	var bs := BattleScreenShared.new()
	bs._font_menu = FontFile.new()
	bs._font_menu.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")
	return bs


# [M26E3-3] A bare, never-started BattleManager -- safe to call
# _get_live_opponents()/_is_neutralizing_gas_active() on (both degrade to
# empty/false against an empty _combatants array, confirmed via direct
# source read before relying on it here) without needing a real running
# battle. Used for the trapping-rejection tests, which need SOME real `_bm`
# for `_rejection_message`'s own trapped-check branch to reach real
# AbilityManager logic, but not a fully wired turn loop.
func _make_bare_bm() -> BattleManager:
	return BattleManager.new()


func _is_chrome_stripped(btn: Button) -> bool:
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		if not (btn.get_theme_stylebox(state) is StyleBoxEmpty):
			return false
	return true


func _make_overlay(bs: BattleScreenShared, field_slot: int, is_forced_replacement: bool) -> SwitchSelectScreen:
	var scene: PackedScene = load("res://scenes/battle/switch_select_screen.tscn")
	var overlay: SwitchSelectScreen = scene.instantiate()
	overlay.setup(bs, field_slot, is_forced_replacement)
	return overlay


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		_collect_buttons(child, out)


func _base_text(btn: Button) -> String:
	return btn.text.substr(BattleScreenShared._CURSOR_PREFIX.length())


# Recursively searches every Label/Button in the tree for a substring --
# used to confirm a slot is genuinely RENDERED somewhere.
func _tree_contains_text(node: Node, needle: String) -> bool:
	if node is Label and (node as Label).text.contains(needle):
		return true
	if node is Button and (node as Button).text.contains(needle):
		return true
	for child in node.get_children():
		if _tree_contains_text(child, needle):
			return true
	return false


func _all_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_all_nodes(child))
	return out


func _find_zone_fill(container: Node) -> TextureRect:
	var rects: Array[TextureRect] = []
	_collect_texture_rects(container, rects)
	for r in rects:
		if r.texture is AtlasTexture and (r.texture as AtlasTexture).atlas != null \
				and (r.texture as AtlasTexture).atlas.resource_path.ends_with("party_hp_zones.png"):
			return r
	return null


# Finds the real slot Button carrying `party_slot` in its own meta, matching
# switch_select_screen.gd's own `_build_slot`-assigned "party_slot" tag —
# the reliable way to locate a specific slot regardless of on-screen order.
func _find_slot_button(overlay: SwitchSelectScreen, party_slot: int) -> Button:
	for btn in overlay._slot_buttons:
		if int(btn.get_meta("party_slot")) == party_slot:
			return btn
	return null


# ── A. [M26E3-3] Every slot -- active AND every bench row, fainted
# included -- is now a real Button, not just legal bench candidates ───────

func _test_every_slot_is_a_real_button_singles() -> void:
	var active := _make_mon("SlotActive")
	var live_bench := _make_mon("SlotLiveBench")
	var fainted_bench := _make_mon("SlotFaintedBench")
	fainted_bench.fainted = true
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [live_bench, fainted_bench])
	var overlay := _make_overlay(bs, 0, false)

	_chk("3 real slot buttons exist (1 active + 2 bench, fainted included)",
			overlay._slot_buttons.size() == 3)
	_chk("Cancel is a separate button, not counted among the slot buttons",
			overlay._cancel_btn != null and not overlay._slot_buttons.has(overlay._cancel_btn))
	_chk("the active mon's own slot is a real Button now (party_slot 0)",
			_find_slot_button(overlay, 0) != null)
	_chk("the fainted bench mon's own slot is a real Button too (party_slot 2)",
			_find_slot_button(overlay, 2) != null)


func _test_every_slot_is_a_real_button_doubles() -> void:
	var a0 := _make_mon("DSlotActive0")
	var a1 := _make_mon("DSlotActive1")
	var b0 := _make_mon("DSlotBench0")
	var b1 := _make_mon("DSlotBench1")
	var b2 := _make_mon("DSlotBench2")
	var b3 := _make_mon("DSlotBench3")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _doubles_party(a0, a1, [b0, b1, b2, b3])
	bs._opp_panels = [Control.new(), Control.new()]
	var overlay := _make_overlay(bs, 0, false)

	_chk("6 real slot buttons exist (2 active + 4 bench)", overlay._slot_buttons.size() == 6)


func _test_forced_replacement_still_omits_cancel() -> void:
	var fainted := _make_mon("ForcedNoCancelActive")
	fainted.fainted = true
	var bench := _make_mon("ForcedNoCancelBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(fainted, [bench])
	var overlay := _make_overlay(bs, 0, true)

	_chk("a forced replacement still has NO Cancel button at all (real source parity, unchanged)",
			overlay._cancel_btn == null)


# ── B. [M26E3-3] Default cursor position is the ACTIVE panel (index 0),
# matching `004_Party.rb`'s own `pbStartScene` default -- a deliberate
# change from the pre-E3-3 "first legal bench mon" default ─────────────────

func _test_default_cursor_is_the_active_panel() -> void:
	var active := _make_mon("DefaultCursorActive")
	var bench := _make_mon("DefaultCursorBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	var overlay := _make_overlay(bs, 0, false)

	var active_btn := _find_slot_button(overlay, 0)
	_chk("the active panel's own button carries the default cursor prefix",
			active_btn.text.begins_with(BattleScreenShared._CURSOR_PREFIX))
	var bench_btn := _find_slot_button(overlay, 1)
	_chk("the bench row does NOT carry the cursor by default",
			not bench_btn.text.begins_with(BattleScreenShared._CURSOR_PREFIX))


# ── C. Real font/chrome conventions carry over to every slot (M25h-1.1/
# 1.2/1.3), now including the active panel's own button ────────────────────

func _test_buttons_use_real_font_and_chrome() -> void:
	var active := _make_mon("FontActive")
	var bench := _make_mon("FontBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	var overlay := _make_overlay(bs, 0, false)

	var all_buttons: Array[Button] = overlay._slot_buttons.duplicate()
	all_buttons.append(overlay._cancel_btn)
	var all_stripped := true
	var all_font := true
	for b in all_buttons:
		if not _is_chrome_stripped(b):
			all_stripped = false
		if b.get_theme_font("font") != bs._font_menu:
			all_font = false
	_chk("every button (every slot + Cancel) has its chrome stripped",
			all_stripped)
	_chk("every button uses the real menu-context bitmap font",
			all_font)


# ── D. [M26E3-3] Real legality gauntlet -- rejection cases ─────────────────
# (party_menu.c:7526-7593 TrySwitchInPokemon, in its own real order; see
# switch_select_screen.gd's own _rejection_message doc comment for the full
# citation)

func _test_reject_fainted_slot_shows_message_no_submenu() -> void:
	var active := _make_mon("RejFaintActive")
	var fainted := _make_mon("RejFaintBench")
	fainted.fainted = true
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [fainted])
	var overlay := _make_overlay(bs, 0, false)
	var chosen: Array = []
	overlay.mon_chosen.connect(func(slot): chosen.append(slot))

	_find_slot_button(overlay, 1).pressed.emit()

	_chk("a fainted slot shows the real 'has no energy left to battle!' message",
			overlay._header.text == "RejFaintBench has no energy left to battle!")
	_chk("no action submenu opens for an illegal pick", overlay._action_submenu == null)
	_chk("mon_chosen never fires for a rejected pick", chosen.is_empty())


func _test_reject_active_slot_shows_message() -> void:
	var active := _make_mon("RejActiveActive")
	var bench := _make_mon("RejActiveBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	var overlay := _make_overlay(bs, 0, false)

	_find_slot_button(overlay, 0).pressed.emit()

	_chk("picking the currently-active mon's own slot shows 'is already in battle!'",
			overlay._header.text == "RejActiveActive is already in battle!")
	_chk("no action submenu opens", overlay._action_submenu == null)


func _test_reject_already_selected_doubles_sibling() -> void:
	var a0 := _make_mon("SibActive0")
	var a1 := _make_mon("SibActive1")
	var bench := _make_mon("SibBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _doubles_party(a0, a1, [bench])
	bs._opp_panels = [Control.new(), Control.new()]
	bs._bm = _make_bare_bm()
	# [M22 Phase 1 shape] field slot 0 already chose bench (party slot 2)
	# this same choosing round -- the real doubles-sibling scenario.
	bs._bm._chosen_switch_slots = [2, -1]
	var overlay := _make_overlay(bs, 1, false)  # building field slot 1's screen

	_find_slot_button(overlay, 2).pressed.emit()

	_chk("picking a bench mon the SIBLING slot already chose shows 'has already been selected.'",
			overlay._header.text == "SibBench has already been selected.")
	_chk("no action submenu opens", overlay._action_submenu == null)


func _test_reject_ability_trap_names_holder_and_ability() -> void:
	# Real end-to-end: a genuine Shadow Tag opponent traps the active mon,
	# so picking ANY legal bench mon is rejected -- matching source's own
	# pre-set gPartyMenu.action, independent of which slot was picked.
	var active := _make_mon("TrapActive")
	var bench := _make_mon("TrapBench")
	var trapper := _make_mon("Wobbuffet")
	trapper.ability = _load_ability(AbilityManager.ABILITY_SHADOW_TAG)

	var bm := BattleManager.new()
	add_child(bm)
	active.add_move(_load_move(33))
	trapper.add_move(_load_move(33))
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(_singles_party_with_bench(active, [bench]),
			_singles_party_with_bench(trapper, []))

	var bs := _make_battle_screen_with_font()
	bs._player_party = bm._parties[0]
	bs._bm = bm
	var overlay := _make_overlay(bs, 0, false)

	_find_slot_button(overlay, 1).pressed.emit()

	_chk("a Shadow-Tag-trapped active mon rejects ANY pick, naming the real trapper + ability",
			overlay._header.text == "Wobbuffet is preventing switching out with its Shadow Tag Ability!")
	_chk("no action submenu opens", overlay._action_submenu == null)
	bm.queue_free()


func _test_reject_move_trap_generic_message() -> void:
	var active := _make_mon("RootedActive")
	active.ingrain_active = true
	var bench := _make_mon("RootedBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	bs._bm = _make_bare_bm()
	var overlay := _make_overlay(bs, 0, false)

	_find_slot_button(overlay, 1).pressed.emit()

	_chk("a move/self-trapped (Ingrain) active mon rejects with the generic 'can't be switched out!', naming the ACTIVE mon",
			overlay._header.text == "RootedActive can't be switched out!")
	_chk("no action submenu opens", overlay._action_submenu == null)


# ── E. [M26E3-3, §0a decision 3] A legal pick opens the real action
# submenu instead of immediately emitting mon_chosen ───────────────────────

func _test_legal_pick_opens_action_submenu_voluntary() -> void:
	var active := _make_mon("SubmenuActive")
	var bench := _make_mon("SubmenuBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	bs._bm = _make_bare_bm()
	var overlay := _make_overlay(bs, 0, false)
	var chosen: Array = []
	overlay.mon_chosen.connect(func(slot): chosen.append(slot))

	_find_slot_button(overlay, 1).pressed.emit()

	_chk("a legal pick opens a real action submenu", overlay._action_submenu != null)
	_chk("mon_chosen does NOT fire yet -- only after the submenu's own primary button",
			chosen.is_empty())
	var submenu_buttons: Array[Button] = []
	_collect_buttons(overlay._action_submenu, submenu_buttons)
	_chk("the submenu has exactly 3 real buttons", submenu_buttons.size() == 3)
	_chk("the primary button reads 'Shift' for a voluntary switch",
			_base_text(submenu_buttons[0]) == "Shift")
	_chk("the list's own slot buttons are disabled while the submenu is open",
			_find_slot_button(overlay, 1).disabled)


func _test_legal_pick_opens_action_submenu_forced() -> void:
	var fainted := _make_mon("SubmenuForcedActive")
	fainted.fainted = true
	var bench := _make_mon("SubmenuForcedBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(fainted, [bench])
	bs._bm = _make_bare_bm()
	var overlay := _make_overlay(bs, 0, true)

	_find_slot_button(overlay, 1).pressed.emit()

	var submenu_buttons: Array[Button] = []
	_collect_buttons(overlay._action_submenu, submenu_buttons)
	_chk("the primary button reads 'Send Out' for a forced replacement",
			_base_text(submenu_buttons[0]) == "Send Out")


func _test_submenu_primary_press_emits_mon_chosen_and_closes() -> void:
	var active := _make_mon("SubmenuPrimaryActive")
	var bench := _make_mon("SubmenuPrimaryBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	bs._bm = _make_bare_bm()
	var overlay := _make_overlay(bs, 0, false)
	var chosen: Array = []
	overlay.mon_chosen.connect(func(slot): chosen.append(slot))

	_find_slot_button(overlay, 1).pressed.emit()
	var submenu_buttons: Array[Button] = []
	_collect_buttons(overlay._action_submenu, submenu_buttons)
	submenu_buttons[0].pressed.emit()  # Shift/Send Out is always index 0.

	_chk("pressing Shift/Send Out emits mon_chosen with the real party slot",
			chosen.size() == 1 and chosen[0] == 1)
	_chk("the submenu closes afterward", overlay._action_submenu == null)


func _test_submenu_cancel_press_closes_and_reenables_list() -> void:
	var active := _make_mon("SubmenuCancelActive")
	var bench := _make_mon("SubmenuCancelBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	bs._bm = _make_bare_bm()
	var overlay := _make_overlay(bs, 0, false)
	var chosen: Array = []
	var cancelled_count := [0]
	overlay.mon_chosen.connect(func(slot): chosen.append(slot))
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	_find_slot_button(overlay, 1).pressed.emit()
	var submenu_buttons: Array[Button] = []
	_collect_buttons(overlay._action_submenu, submenu_buttons)
	submenu_buttons[2].pressed.emit()  # Cancel is always index 2.

	_chk("the submenu's own Cancel closes it without picking anything",
			overlay._action_submenu == null and chosen.is_empty())
	_chk("the submenu's own Cancel does NOT emit the top-level cancelled signal",
			cancelled_count[0] == 0)
	_chk("the list's slot buttons are re-enabled after the submenu closes",
			not _find_slot_button(overlay, 1).disabled)


# [M26E4-2, was _test_summary_button_is_a_disabled_stub] E3-3 shipped
# Summary as a real but disabled stub, explicitly flagged as "M26E4's own
# future hook" -- that hook is now real. This test's own name and assertion
# are updated in place (not left contradicting the shipped behavior) to
# match: Summary is enabled and pressing it opens a real SummaryScreen
# overlay, per switch_select_screen.gd's own new `_on_submenu_summary_
# pressed` -- full coverage of the overlay's own contract (idempotency, the
# real return-path-reopens-at-last-viewed-slot behavior, ESC precedence)
# lives in summary_screen_test.gd, not duplicated here.
func _test_summary_button_now_opens_a_real_summary_screen() -> void:
	var active := _make_mon("SummaryRealActive")
	var bench := _make_mon("SummaryRealBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	bs._bm = _make_bare_bm()
	var overlay := _make_overlay(bs, 0, false)

	_find_slot_button(overlay, 1).pressed.emit()
	var submenu_buttons: Array[Button] = []
	_collect_buttons(overlay._action_submenu, submenu_buttons)

	_chk("Summary is a real, present button",
			_base_text(submenu_buttons[1]) == "Summary")
	_chk("Summary is no longer a disabled stub -- M26E4-2 wired it", not submenu_buttons[1].disabled)

	submenu_buttons[1].pressed.emit()
	_chk("pressing Summary opens a real overlay",
			overlay._summary_screen != null and is_instance_valid(overlay._summary_screen))
	_chk("the submenu is hidden (not destroyed) while Summary is open",
			overlay._action_submenu != null and not overlay._action_submenu.visible)


# ── F. ESC handling: closes the submenu first if one is open, matching the
# submenu's own Cancel; otherwise falls through to the existing top-level
# voluntary-cancel/forced-no-op behavior ───────────────────────────────────

func _test_escape_closes_submenu_first_when_open() -> void:
	var active := _make_mon("EscSubmenuActive")
	var bench := _make_mon("EscSubmenuBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	bs._bm = _make_bare_bm()
	var overlay := _make_overlay(bs, 0, false)
	add_child(overlay)
	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	_find_slot_button(overlay, 1).pressed.emit()
	_chk("the submenu is open before pressing ESC", overlay._action_submenu != null)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay._unhandled_input(esc)

	_chk("ESC closes the submenu (back to the list), not the whole screen",
			overlay._action_submenu == null)
	_chk("ESC-closing the submenu does NOT emit the top-level cancelled signal",
			cancelled_count[0] == 0)
	overlay.queue_free()


func _test_escape_after_submenu_closed_still_cancels_voluntary() -> void:
	var active := _make_mon("EscVoluntaryActive")
	var bench := _make_mon("EscVoluntaryBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	var overlay := _make_overlay(bs, 0, false)
	add_child(overlay)
	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay._unhandled_input(esc)

	_chk("with no submenu open, ESC still cancels the whole voluntary switch (unchanged real source parity)",
			cancelled_count[0] == 1)
	overlay.queue_free()


func _test_escape_is_a_no_op_during_forced_replacement() -> void:
	var fainted := _make_mon("EscForcedActive")
	fainted.fainted = true
	var bench := _make_mon("EscForcedBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(fainted, [bench])
	var overlay := _make_overlay(bs, 0, true)
	add_child(overlay)
	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay._unhandled_input(esc)

	_chk("ESC does NOT emit cancelled during a forced replacement (no cancel path exists, unchanged)",
			cancelled_count[0] == 0)
	overlay.queue_free()


# ── G. [M26E3-3] The rejection message auto-reverts to the real prompt
# after its own display duration -- tested via direct timer manipulation,
# not a real wait, matching this project's own established convention for
# timer-driven UI behavior ─────────────────────────────────────────────────

func _test_message_reverts_after_display_duration() -> void:
	var active := _make_mon("RevertActive")
	var bench := _make_mon("RevertBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	var overlay := _make_overlay(bs, 0, false)

	overlay._show_rejection_message("A test rejection message.")
	_chk("the header shows the rejection message immediately", overlay._header.text == "A test rejection message.")

	overlay._process(SwitchSelectScreen._MESSAGE_DISPLAY_SECONDS + 0.01)
	_chk("after the real display duration elapses, the header reverts to the real prompt",
			overlay._header.text == SwitchSelectScreen._HEADER_TEXT)


# ── H. battle_screen_shared.gd's own _build_switch_buttons opens a real,
# wired overlay as a genuine child (unchanged by E3-3) ─────────────────────

func _test_build_switch_buttons_opens_a_real_wired_overlay() -> void:
	var active := _make_mon("Active6")
	var bench1 := _make_mon("Bench8")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1])

	bs._build_switch_buttons(false, 0)

	_chk("_switch_select_overlay is a real SwitchSelectScreen",
			bs._switch_select_overlay != null and bs._switch_select_overlay is SwitchSelectScreen)
	_chk("the overlay is a genuine child of the battle screen (not floating/detached)",
			bs._switch_select_overlay.get_parent() == bs)


# ── H2. [Bugfix] The stale "Choose a Pokémon to switch in." status prompt
# no longer bleeds through on top of this full-screen overlay ──────────────
# SharedChrome's own root node carries z_index=5 (see battle_screen_shared
# .gd's _effect_layer doc comment), which sorts globally ahead of tree
# order -- so _status_label, left visible by _refresh_ui()'s own default
# layout, was drawing OVER this overlay despite being added earlier in the
# tree. Reported directly by Rob: "the 'what should pokemon do' text box
# shows on the pokemon switch screen."

func _test_build_switch_buttons_hides_the_stale_status_label() -> void:
	var active := _make_mon("Active6b")
	var bench1 := _make_mon("Bench8b")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1])
	bs._status_label = Label.new()
	bs._status_label.visible = true
	bs._status_label.text = "Choose a Pokémon to switch in."

	bs._build_switch_buttons(false, 0)

	_chk("the underlying status prompt is hidden once the overlay is open",
			not bs._status_label.visible)


# ── I. A second _build_switch_buttons call while the overlay is still open
# does not stack a duplicate (unchanged by E3-3) ───────────────────────────

func _test_build_switch_buttons_is_idempotent_while_overlay_open() -> void:
	var active := _make_mon("Active7")
	var bench1 := _make_mon("Bench9")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1])

	bs._build_switch_buttons(false, 0)
	var first_overlay := bs._switch_select_overlay
	bs._build_switch_buttons(false, 0)

	_chk("the overlay instance is unchanged across the second call (no rebuild/duplicate)",
			bs._switch_select_overlay == first_overlay)
	var overlay_children := 0
	for c in bs.get_children():
		if c is SwitchSelectScreen:
			overlay_children += 1
	_chk("exactly one overlay child exists on the battle screen", overlay_children == 1)


# ── J. field_slot AND is_forced_replacement propagate correctly into the
# bound handler callables (doubles per-slot correctness, unchanged by E3-3
# -- this test is about the EXTERNAL connection battle_screen_shared.gd
# makes to overlay.mon_chosen, not about how/when the overlay itself fires
# it) ────────────────────────────────────────────────────────────────────

func _test_field_slot_propagates_correctly_to_bound_handlers() -> void:
	var m0 := _make_mon("D0")
	var m1 := _make_mon("D1fainted")
	m1.fainted = true
	var bench := _make_mon("D1Bench")
	var bs0 := _make_battle_screen_with_font()
	var doubles_party := BattleParty.new()
	var members: Array[BattlePokemon] = [m0, m1, bench]
	doubles_party.members = members
	var active: Array[int] = [0, 1]
	doubles_party.active_indices = active
	bs0._player_party = doubles_party

	bs0._build_switch_buttons(true, 1)  # forced replacement, slot 1, not slot 0.

	var overlay: SwitchSelectScreen = bs0._switch_select_overlay
	var chosen_bound: Array = overlay.mon_chosen.get_connections()[0]["callable"].get_bound_arguments()
	_chk("mon_chosen's bound handler carries is_forced_replacement=true",
			chosen_bound.has(true))
	_chk("mon_chosen's bound handler carries the real field_slot (1, not 0)",
			chosen_bound.has(1))


# ── K. End-to-end: mon_chosen (voluntary) reaches the real
# queue_switch_for()/advance() pipeline -- unchanged by E3-3, since this
# tests _on_switch_pressed's own body directly, not how the overlay itself
# decides to fire mon_chosen ────────────────────────────────────────────────

func _test_mon_chosen_reaches_real_queue_switch_for_end_to_end() -> void:
	var active := _make_mon("VolActive", 100)
	active.add_move(_load_move(33))
	var bench := _make_mon("VolBench", 100)
	var opp := _make_mon("VolOpp", 100)
	opp.add_move(_load_move(33))

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(_singles_party_with_bench(active, [bench]), _singles_party_with_bench(opp, []))

	var switch_events: Array = []
	bm.pokemon_switched_in.connect(func(mon, side, slot): switch_events.append([mon, side, slot]))

	bm.queue_switch_for(0, 1)
	bm.advance()

	_chk("the voluntary switch fired through the real queue_switch_for()/advance() pipeline",
			switch_events.size() >= 1 and switch_events[0][0] == bench)

	bm.queue_free()


# ── L. End-to-end: mon_chosen (forced) reaches the real
# queue_replacement_for()/advance() pipeline (unchanged by E3-3) ──────────

func _test_mon_chosen_reaches_real_queue_replacement_for_end_to_end() -> void:
	var will_faint := _make_mon("ForcedActive", 10, 30, 30, 50)
	will_faint.add_move(_load_move(33))
	var bench := _make_mon("ForcedBench", 100)
	var opp := _make_mon("ForcedOpp", 200, 200, 30, 200)
	opp.add_move(_load_move(33))

	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(_singles_party_with_bench(will_faint, [bench]), _singles_party_with_bench(opp, []))

	bm.queue_move(0, 0)
	bm.advance()
	_chk("the frail active fainted and the battle genuinely stalled at SWITCH_PROMPT",
			will_faint.fainted and bm.get_phase() == BattleManager.BattlePhase.SWITCH_PROMPT)

	var switch_events: Array = []
	bm.pokemon_switched_in.connect(func(mon, side, slot): switch_events.append([mon, side, slot]))

	bm.queue_replacement_for(0, 1)
	bm.advance()

	_chk("the forced replacement fired through the real queue_replacement_for()/advance() pipeline",
			switch_events.size() >= 1 and switch_events[0][0] == bench)

	bm.queue_free()


# ── M. End-to-end: cancelled resets _menu to TOP through the real handler
# (unchanged by E3-3) ────────────────────────────────────────────────────

func _test_cancelled_reaches_real_menu_reset_end_to_end() -> void:
	var active := _make_mon("CancelActive")
	var bench := _make_mon("CancelBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	bs._menu = BattleScreenShared.Menu.SWITCH

	bs._build_switch_buttons(false, 0)
	_chk("an overlay was really created before cancelling", bs._switch_select_overlay != null)
	_chk("_menu starts at SWITCH (about to be reset by a real Cancel press)",
			bs._menu == BattleScreenShared.Menu.SWITCH)


# ── N. The header shows the real source string ─────────────────────────

func _test_header_shows_the_real_source_string() -> void:
	_chk("the screen's own header is the real source string, not a generic placeholder",
			SwitchSelectScreen._HEADER_TEXT == "Choose a POKéMON.")


# ── O. Each row's own button text carries the real current/max HP fraction,
# and a real panel-art background + status icon are still real child
# TextureRects ──────────────────────────────────────────────────────────

func _test_row_includes_real_hp_text_and_status_icon_children() -> void:
	var active := _make_mon("HpRowActive")
	var bench := _make_mon("HpRowBench", 100)
	bench.current_hp = 40
	bench.status = BattlePokemon.STATUS_POISON
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	var overlay := _make_overlay(bs, 0, false)

	var row_btn := _find_slot_button(overlay, 1)
	_chk("the row's own button text carries the real current/max HP fraction",
			row_btn.text.contains("HP %d/%d" % [bench.current_hp, bench.max_hp]))

	var row_container: Node = row_btn.get_parent()
	var texture_rect_count := 0
	for child in row_container.get_children():
		if child is TextureRect:
			texture_rect_count += 1
	_chk("the row carries both the real panel-art background AND a status icon for a statused mon",
			texture_rect_count >= 2)


# ── P. [M26E3-3] ALL SIX SLOTS are shown, and now EVERY ONE of them is a
# real clickable Button (superseding E3-1's "only a live bench mon is
# clickable" restriction, resolving legality via real rejection messages
# instead of by omitting the Button entirely) ──────────────────────────────

func _test_all_six_slots_shown_and_all_are_real_buttons() -> void:
	var active := _make_mon("ActiveShown")
	var fainted_bench := _make_mon("FaintedBenchShown")
	fainted_bench.fainted = true
	var live_bench := _make_mon("LiveBenchShown")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [fainted_bench, live_bench])
	var overlay := _make_overlay(bs, 0, false)

	_chk("the active member IS now a clickable Button (rejected on click, not omitted)",
			_find_slot_button(overlay, 0) != null)
	_chk("the fainted bench member IS now a clickable Button too",
			_find_slot_button(overlay, 1) != null)
	_chk("a live bench member is a clickable Button",
			_find_slot_button(overlay, 2) != null)
	_chk("all three are genuinely rendered with their own real name",
			_tree_contains_text(overlay, "ActiveShown")
			and _tree_contains_text(overlay, "FaintedBenchShown")
			and _tree_contains_text(overlay, "LiveBenchShown"))


# ── Q. The real Emerald UI Pack assets this screen actually consumes exist
# at their real pack dimensions -- extended to the faint_sel variants E3-3
# newly consumes (a fainted slot can now carry the cursor too) ────────────

func _test_real_pack_assets_exist_with_real_dimensions() -> void:
	var bg_singles: Texture2D = load("res://assets/sprites/battle_ui/party/party_bg_singles.png")
	var bg_doubles: Texture2D = load("res://assets/sprites/battle_ui/party/party_bg_doubles.png")
	var round_base: Texture2D = load("res://assets/sprites/battle_ui/party/panel_round_base.png")
	var round_faint: Texture2D = load("res://assets/sprites/battle_ui/party/panel_round_faint.png")
	var round_faint_sel: Texture2D = load("res://assets/sprites/battle_ui/party/panel_round_faint_sel.png")
	var rect_base: Texture2D = load("res://assets/sprites/battle_ui/party/panel_rect_base.png")
	var rect_faint: Texture2D = load("res://assets/sprites/battle_ui/party/panel_rect_faint.png")
	var rect_faint_sel: Texture2D = load("res://assets/sprites/battle_ui/party/panel_rect_faint_sel.png")
	_chk("party_bg_singles.png loads at its real pack dimensions (512x384)",
			bg_singles != null and bg_singles.get_width() == 512 and bg_singles.get_height() == 384)
	_chk("party_bg_doubles.png loads at its real pack dimensions (512x384)",
			bg_doubles != null and bg_doubles.get_width() == 512 and bg_doubles.get_height() == 384)
	_chk("panel_round_base.png loads at its real pack dimensions (156x98)",
			round_base != null and round_base.get_width() == 156 and round_base.get_height() == 98)
	_chk("panel_round_faint.png loads at its real pack dimensions (156x98)",
			round_faint != null and round_faint.get_width() == 156 and round_faint.get_height() == 98)
	_chk("panel_round_faint_sel.png (E3-3's new cursor-on-fainted-active case) loads at its real pack dimensions (156x98)",
			round_faint_sel != null and round_faint_sel.get_width() == 156 and round_faint_sel.get_height() == 98)
	_chk("panel_rect_base.png loads at its real pack dimensions (288x48)",
			rect_base != null and rect_base.get_width() == 288 and rect_base.get_height() == 48)
	_chk("panel_rect_faint.png loads at its real pack dimensions (288x48)",
			rect_faint != null and rect_faint.get_width() == 288 and rect_faint.get_height() == 48)
	_chk("panel_rect_faint_sel.png (E3-3's new cursor-on-fainted-bench case) loads at its real pack dimensions (288x48)",
			rect_faint_sel != null and rect_faint_sel.get_width() == 288 and rect_faint_sel.get_height() == 48)


# ── R. _party_status_icon_row's own real AILMENT-order mapping (unchanged
# by E3-3 -- a pure static function) ───────────────────────────────────────

func _test_party_status_icon_row_mapping_matches_real_ailment_order() -> void:
	var mon := _make_mon("AilmentTester")
	mon.status = BattlePokemon.STATUS_POISON
	_chk("poison maps to row 0 (AILMENT_PSN=1, anim index 0)",
			SwitchSelectScreen._party_status_icon_row(mon) == 0)
	mon.status = BattlePokemon.STATUS_PARALYSIS
	_chk("paralysis maps to row 1 (AILMENT_PRZ=2, anim index 1)",
			SwitchSelectScreen._party_status_icon_row(mon) == 1)
	mon.status = BattlePokemon.STATUS_SLEEP
	_chk("sleep maps to row 2 (AILMENT_SLP=3, anim index 2)",
			SwitchSelectScreen._party_status_icon_row(mon) == 2)
	mon.status = BattlePokemon.STATUS_FREEZE
	_chk("freeze maps to row 3 (AILMENT_FRZ=4, anim index 3)",
			SwitchSelectScreen._party_status_icon_row(mon) == 3)
	mon.status = BattlePokemon.STATUS_BURN
	_chk("burn maps to row 4 (AILMENT_BRN=5, anim index 4)",
			SwitchSelectScreen._party_status_icon_row(mon) == 4)
	mon.status = BattlePokemon.STATUS_NONE
	_chk("no status maps to -1 (no icon)",
			SwitchSelectScreen._party_status_icon_row(mon) == -1)

	var fainted_with_status := _make_mon("FaintedWithStatusTester")
	fainted_with_status.status = BattlePokemon.STATUS_POISON
	fainted_with_status.fainted = true
	_chk("a fainted mon shows FNT (row 6) even if it also carries a real status, matching GetMonAilment's own real priority order",
			SwitchSelectScreen._party_status_icon_row(fainted_with_status) == SwitchSelectScreen._PARTY_STATUS_ROW_FNT)


# ── S. Held-item icon shown only for a mon actually holding an item --
# re-indexed for E3-3 (the active mon is now slot_buttons[0], so the
# holder/non-holder bench mons are party_slot 1/2) ─────────────────────────

func _test_held_item_icon_shown_only_when_holding_an_item() -> void:
	var active := _make_mon("HoldActive")
	var holder := _make_mon("HoldBenchHolder")
	holder.held_item = ItemRegistry.get_item(28)  # Potion -- any real item.
	var non_holder := _make_mon("HoldBenchNonHolder")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [holder, non_holder])
	var overlay := _make_overlay(bs, 0, false)

	var holder_row: Node = _find_slot_button(overlay, 1).get_parent()
	var non_holder_row: Node = _find_slot_button(overlay, 2).get_parent()
	var holder_texture_rects := 0
	for c in holder_row.get_children():
		if c is TextureRect:
			holder_texture_rects += 1
	var non_holder_texture_rects := 0
	for c in non_holder_row.get_children():
		if c is TextureRect:
			non_holder_texture_rects += 1

	_chk("a held-item-carrying mon's row has one more TextureRect than a non-carrying mon's row (the held-item icon)",
			holder_texture_rects == non_holder_texture_rects + 1)


# ── T. The fainted-slot dim helper itself still works correctly
# (superseded -- unchanged by E3-3) ─────────────────────────────────────

func _test_fainted_dim_helper_darkens_slot_art() -> void:
	var slot_art := TextureRect.new()
	slot_art.modulate = Color(1, 1, 1, 1)
	SwitchSelectScreen._apply_fainted_dim(slot_art)
	_chk("the fainted-dim helper still darkens the slot art's own modulate (a superseded fallback, not the active mechanism)",
			slot_art.modulate.r < 1.0 and slot_art.modulate.a == 1.0)


# ── U. [M26E3-1, re-verified for E3-3] Singles shape: 1 round active panel
# + 5 rect bench rows -- now ALL 6 are real slot buttons, plus Cancel ─────

func _test_singles_layout_shape() -> void:
	var active := _make_mon("SinglesActive")
	var bench_members: Array = []
	for i in range(5):
		bench_members.append(_make_mon("SinglesBench%d" % i))
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, bench_members)
	var overlay := _make_overlay(bs, 0, false)

	_chk("singles shows 6 real slot buttons (1 active + 5 bench) plus Cancel",
			overlay._slot_buttons.size() == 6 and overlay._cancel_btn != null)

	var bg: TextureRect = overlay.get_child(0)
	_chk("the background used is the real singles mockup",
			bg.texture != null and bg.texture.resource_path.ends_with("party_bg_singles.png"))


# ── V. Doubles shape: 2 round active panels + 4 rect bench rows ──────────

func _test_doubles_layout_shape() -> void:
	var m0 := _make_mon("DoublesActive0")
	var m1 := _make_mon("DoublesActive1")
	var bs := _make_battle_screen_with_font()
	var doubles_party := BattleParty.new()
	var members: Array[BattlePokemon] = [m0, m1]
	for i in range(4):
		members.append(_make_mon("DoublesBench%d" % i))
	doubles_party.members = members
	var active_idx: Array[int] = [0, 1]
	doubles_party.active_indices = active_idx
	bs._player_party = doubles_party
	bs._opp_panels = [Control.new(), Control.new()]
	var overlay := _make_overlay(bs, 0, false)

	_chk("doubles shows 6 real slot buttons (2 active + 4 bench) plus Cancel",
			overlay._slot_buttons.size() == 6 and overlay._cancel_btn != null)

	var bg: TextureRect = overlay.get_child(0)
	_chk("the background used is the real doubles mockup",
			bg.texture != null and bg.texture.resource_path.ends_with("party_bg_doubles.png"))


# ── W. Every slot (active AND every bench row, legal or not) gets a real
# per-species mon icon (unchanged by E3-3) ─────────────────────────────────

func _test_mon_icon_present_on_every_slot() -> void:
	var active := _make_mon_dex("IconActive", 1)
	var live_bench := _make_mon_dex("IconLiveBench", 4)
	var fainted_bench := _make_mon_dex("IconFaintedBench", 7)
	fainted_bench.fainted = true
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [live_bench, fainted_bench])
	var overlay := _make_overlay(bs, 0, false)

	_chk("one icon entry is tracked per slot shown (active + 2 bench = 3)",
			overlay._icon_entries.size() == 3)
	for entry in overlay._icon_entries:
		var rect: TextureRect = entry["rect"]
		_chk("each tracked icon's TextureRect carries a real, non-null texture",
				rect.texture != null)


# ── X. [M26E3-3] Ball icon cursor marker now defaults to sel on the ACTIVE
# panel (matching the new default-cursor-position finding), desel
# everywhere else ──────────────────────────────────────────────────────────

func _test_ball_icon_defaults_sel_on_active_panel_and_desel_elsewhere() -> void:
	var active := _make_mon_dex("BallActive", 1)
	var bench1 := _make_mon_dex("BallBench1", 4)
	var bench2 := _make_mon_dex("BallBench2", 7)
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1, bench2])
	var overlay := _make_overlay(bs, 0, false)

	_chk("3 mon slots (1 active + 2 bench) are tracked for cursor-driven visual selection",
			overlay._mon_visual_entries.size() == 3)
	var ball_active: TextureRect = overlay._mon_visual_entries[0]["ball"]
	var ball_bench1: TextureRect = overlay._mon_visual_entries[1]["ball"]
	var ball_bench2: TextureRect = overlay._mon_visual_entries[2]["ball"]
	_chk("the active panel (default-selected) shows the real SEL ball icon",
			ball_active.texture.resource_path.ends_with("party_ball_icon_sel.png"))
	_chk("bench slot 1 (not selected) shows the real DESEL ball icon",
			ball_bench1.texture.resource_path.ends_with("party_ball_icon.png"))
	_chk("bench slot 2 (not selected) shows the real DESEL ball icon",
			ball_bench2.texture.resource_path.ends_with("party_ball_icon.png"))

	var all_rects: Array[TextureRect] = []
	_collect_texture_rects(overlay, all_rects)
	var sel_count := 0
	for r in all_rects:
		if r.texture == null:
			continue
		var path: String = (r.texture as Texture2D).resource_path
		if path.contains("party_ball_icon") and path.ends_with("_sel.png"):
			sel_count += 1
	_chk("exactly one ball icon on the whole screen shows SEL (the default active-panel selection)",
			sel_count == 1)


# ── Y. Hovering a different bench row swaps both the ball icon AND the
# panel's own real `_sel` art state (unchanged mechanism, re-indexed now
# that the active panel occupies _mon_visual_entries[0]) ───────────────────

func _test_hovering_a_bench_row_swaps_ball_and_panel_sel_state() -> void:
	var active := _make_mon_dex("HoverActive", 1)
	var bench1 := _make_mon_dex("HoverBench1", 4)
	var bench2 := _make_mon_dex("HoverBench2", 7)
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1, bench2])
	var overlay := _make_overlay(bs, 0, false)

	overlay._set_mon_visual_selected(2)  # bench2, party_slot 2.

	var entry_active: Dictionary = overlay._mon_visual_entries[0]
	var entry_bench2: Dictionary = overlay._mon_visual_entries[2]
	_chk("after hovering bench2, the active panel's ball reverts to DESEL",
			(entry_active["ball"] as TextureRect).texture.resource_path.ends_with("party_ball_icon.png"))
	_chk("after hovering bench2, its own ball becomes SEL",
			(entry_bench2["ball"] as TextureRect).texture.resource_path.ends_with("party_ball_icon_sel.png"))
	_chk("the active panel's own panel art reverts to its real BASE state",
			(entry_active["panel_art"] as TextureRect).texture.resource_path.ends_with("panel_round_base.png"))
	_chk("bench2's panel art swaps to the real _sel state (panel_rect_sel.png)",
			(entry_bench2["panel_art"] as TextureRect).texture.resource_path.ends_with("panel_rect_sel.png"))


# ── Z. Hovering Cancel clears every mon's own visual selection (unchanged
# mechanism) ─────────────────────────────────────────────────────────────

func _test_cancel_hover_clears_mon_visual_selection() -> void:
	var active := _make_mon_dex("ClearActive", 1)
	var bench1 := _make_mon_dex("ClearBench1", 4)
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1])
	var overlay := _make_overlay(bs, 0, false)

	overlay._clear_mon_visual_selection()

	var entry_active: Dictionary = overlay._mon_visual_entries[0]
	_chk("clearing selection reverts the active panel's ball to DESEL",
			(entry_active["ball"] as TextureRect).texture.resource_path.ends_with("party_ball_icon.png"))
	_chk("clearing selection reverts its panel art to the real BASE state",
			(entry_active["panel_art"] as TextureRect).texture.resource_path.ends_with("panel_round_base.png"))
	_chk("clearing selection marks the icon entry as not selected (rests, doesn't bounce)",
			(entry_active["icon"] as Dictionary)["selected"] == false)


# ── AA. Real overlay_hp_back/overlay_hp compositing: a trough background is
# always present, and a live-cropped zone-color fill sits at the correct
# zone -- re-indexed for E3-3's own new party_slot layout (active is now
# party_slot 0, bench mons shift up by one) ────────────────────────────────

func _test_hp_bar_trough_and_fill_present_with_correct_zone() -> void:
	# [Same pitfall this file's own earlier session already hit once]
	# BattlePokemon's real HP formula does NOT make max_hp equal the
	# base_hp parameter -- fractions are computed from each mon's own REAL
	# post-construction max_hp, never a hardcoded current_hp literal.
	var active := _make_mon_dex("HpZoneActive", 1)
	var green_mon := _make_mon_dex("HpZoneGreen", 4)
	# green_mon.current_hp already equals its own real max_hp (full HP, zone 0).
	var yellow_mon := _make_mon_dex("HpZoneYellow", 7)
	yellow_mon.current_hp = int(yellow_mon.max_hp * 0.3)  # frac 0.3 -> zone 1 (yellow, <=0.5)
	var red_mon := _make_mon_dex("HpZoneRed", 25)
	red_mon.current_hp = int(red_mon.max_hp * 0.1)  # frac 0.1 -> zone 2 (red, <=0.2)
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [green_mon, yellow_mon, red_mon])
	var overlay := _make_overlay(bs, 0, false)

	var green_row: Node = _find_slot_button(overlay, 1).get_parent()
	var yellow_row: Node = _find_slot_button(overlay, 2).get_parent()
	var red_row: Node = _find_slot_button(overlay, 3).get_parent()

	var green_fill := _find_zone_fill(green_row)
	var yellow_fill := _find_zone_fill(yellow_row)
	var red_fill := _find_zone_fill(red_row)
	_chk("a full-HP mon's fill crops the GREEN band (zone 0)",
			green_fill != null and (green_fill.texture as AtlasTexture).region.position.y == 0)
	_chk("a 30%-HP mon's fill crops the YELLOW band (zone 1)",
			yellow_fill != null and (yellow_fill.texture as AtlasTexture).region.position.y == 8)
	_chk("a 10%-HP mon's fill crops the RED band (zone 2)",
			red_fill != null and (red_fill.texture as AtlasTexture).region.position.y == 16)

	var trough_count := 0
	var rects: Array[TextureRect] = []
	_collect_texture_rects(overlay, rects)
	for r in rects:
		if r.texture != null and (r.texture as Texture2D).resource_path.contains("party_hp_trough"):
			trough_count += 1
	_chk("every one of the 4 slots (1 active + 3 bench) has its own real trough background",
			trough_count == 4)


# ── AB. A fainted row shows the real faint trough but NO zone fill ────────

func _test_fainted_row_has_trough_but_no_fill() -> void:
	var active := _make_mon_dex("FaintTroughActive", 1)
	var fainted := _make_mon_dex("FaintTroughBench", 4)
	fainted.fainted = true
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [fainted])
	var overlay := _make_overlay(bs, 0, false)

	var fainted_row: Node = _find_slot_button(overlay, 1).get_parent()

	var row_rects: Array[TextureRect] = []
	_collect_texture_rects(fainted_row, row_rects)
	var has_faint_trough := false
	for r in row_rects:
		if r.texture != null and (r.texture as Texture2D).resource_path.ends_with("party_hp_trough_faint.png"):
			has_faint_trough = true
	_chk("the fainted row shows the real FAINT trough variant", has_faint_trough)
	_chk("the fainted row has NO zone-color fill (nothing to show)", _find_zone_fill(fainted_row) == null)


# ── AC. The real, confirmed tier-0 icon animation cadence advances a live
# icon's own frame over real elapsed time (unchanged by E3-3) ──────────────

func _test_icon_animation_advances_frame_over_real_time() -> void:
	var active := _make_mon_dex("AnimActive", 1)
	var bench := _make_mon_dex("AnimBench", 4)
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	var overlay := _make_overlay(bs, 0, false)

	_chk("animation starts at frame 0", overlay._icon_frame == 0)
	overlay._process(SwitchSelectScreen._ICON_FRAME_SECONDS + 0.001)
	_chk("after one real frame-interval elapses, the shared frame index flips to 1",
			overlay._icon_frame == 1)
	for entry in overlay._icon_entries:
		var rect: TextureRect = entry["rect"]
		_chk("every tracked icon's texture matches its own frame-1 texture after the flip",
				rect.texture == (entry["frames"] as Array)[1])
	overlay._process(SwitchSelectScreen._ICON_FRAME_SECONDS + 0.001)
	_chk("a second real frame-interval flips it back to frame 0", overlay._icon_frame == 0)


# ── AD. Selection bounce: the currently-selected (now: active panel by
# default) icon's own wrap offsets by the real bounce amount; every
# unselected icon holds its own fixed, non-bouncing offset instead ────────

func _test_selected_icon_bounces_unselected_icon_holds_fixed_shift() -> void:
	var active := _make_mon_dex("BounceActive", 1)
	var bench1 := _make_mon_dex("BounceBench1", 4)
	var bench2 := _make_mon_dex("BounceBench2", 7)
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1, bench2])
	var overlay := _make_overlay(bs, 0, false)

	var selected_entry: Dictionary = overlay._mon_visual_entries[0]["icon"]  # active, default-selected.
	var unselected_entry: Dictionary = overlay._mon_visual_entries[1]["icon"]  # bench1.
	var sel_wrap: Control = selected_entry["wrap"]
	var unsel_wrap: Control = unselected_entry["wrap"]
	var sel_base: Vector2 = selected_entry["base_pos"]
	var unsel_base: Vector2 = unselected_entry["base_pos"]

	_chk("the selected (default: active panel) icon's own wrap sits at base_pos + the real bounce offset (frame 0 -> DOWN)",
			sel_wrap.position == sel_base + Vector2(0, SwitchSelectScreen._ICON_BOUNCE_DOWN))
	_chk("an unselected icon's wrap sits at base_pos + its own fixed unselected shift, not bouncing",
			unsel_wrap.position == unsel_base + Vector2(SwitchSelectScreen._ICON_UNSELECTED_SHIFT, 0))

	overlay._process(SwitchSelectScreen._ICON_FRAME_SECONDS + 0.001)
	_chk("after the frame flips (now frame 1), the selected icon's bounce direction is UP",
			sel_wrap.position == sel_base + Vector2(0, SwitchSelectScreen._ICON_BOUNCE_UP))
	_chk("the unselected icon's own fixed shift is unaffected by the frame flip",
			unsel_wrap.position == unsel_base + Vector2(SwitchSelectScreen._ICON_UNSELECTED_SHIFT, 0))
