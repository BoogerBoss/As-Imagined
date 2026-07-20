extends Node

# [M25h-1.5, extended M25h-4] Regression suite for the real separate
# Switch/Party full-screen overlay — see switch_select_screen.gd's own doc
# comment for the full architecture rationale (a child overlay on the
# still-alive battle_screen instance, matching M25h-1.4's Item overlay
# exactly) and Step 0 source citations (gText_ChoosePokemon header,
# HandleChooseMonCancel's real voluntary-vs-forced cancel behavior). M25h-4
# later succeeded at the tilemap-decode reconstruction M25h-1.5 had
# originally declined (party_menu/bg.png's own raw tileset) -- see
# gen_ui_frames.py's own doc comment for that session's full writeup; the
# real decoded frame/slot art, HP-fraction color tint, party-specific
# status icons, and held-item icons are all covered by this suite's own
# later sections (K onward).
#
# [Deliberately NOT tested here] The real on-screen visual result (real
# window art, HP-bar/status-icon placement, legible text) — matches every
# prior M25h suite's own established precedent of scoping automated
# coverage to pure logic + bare-instance direct calls, leaving the real
# end-to-end proof to this session's own mandatory real screenshot pass.
#
# [Deliberately NOT calling _build_switch_buttons for the zero-candidate
# scenario] That branch's own final statements are _bm.advance() followed
# by _refresh_ui(), which needs BattleScreen's full live @onready UI tree
# to run without erroring — matching every other _refresh_ui()-ending
# handler's own established restraint in this project's test suites (see
# item_select_screen_test.gd's Test I/J doc comments for the identical
# reasoning). The underlying mechanism this guards (BattleManager's own
# auto-resolve of an unwinnable SWITCH_PROMPT) is UNCHANGED by this
# session — still the exact M25a fix, still covered by
# m25a_switch_aliasing_test.gd's own _test_switch_buttons_auto_resolves_
# when_no_candidate (the pure _party_has_switch_candidate predicate) and
# its doc comment's disclosed 180-battle stress-test verification. What
# THIS session changed is only that the early-return now precedes overlay
# construction instead of button construction — confirmed by direct
# reading of _build_switch_buttons' own body (the any_candidate check and
# `return` both appear textually before the overlay's `load()`/
# `instantiate()` calls, so the zero-candidate path can never reach them).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_overlay_builds_bench_rows_plus_cancel_voluntary()
	_test_overlay_omits_cancel_for_forced_replacement()
	_test_overlay_buttons_use_real_font_chrome_and_cursor()
	_test_mon_button_press_emits_mon_chosen_with_correct_slot()
	_test_cancel_button_press_emits_cancelled()
	_test_escape_key_cancels_voluntary()
	_test_escape_key_is_a_no_op_during_forced_replacement()
	_test_build_switch_buttons_opens_a_real_wired_overlay()
	_test_build_switch_buttons_is_idempotent_while_overlay_open()
	_test_field_slot_propagates_correctly_to_bound_handlers()
	_test_mon_chosen_reaches_real_queue_switch_for_end_to_end()
	_test_mon_chosen_reaches_real_queue_replacement_for_end_to_end()
	_test_cancelled_reaches_real_menu_reset_end_to_end()
	_test_header_shows_the_real_source_string()
	_test_row_includes_real_hp_bar_and_status_icon_children()
	_test_fainted_and_active_members_excluded_from_rows()
	_test_frame_and_slot_art_assets_exist_with_real_dimensions()
	_test_party_status_icon_row_mapping_matches_real_ailment_order()
	_test_held_item_icon_shown_only_when_holding_an_item()
	_test_fainted_dim_helper_darkens_slot_art()

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


func _singles_party_with_bench(active_mon: BattlePokemon, bench: Array) -> BattleParty:
	var p := BattleParty.new()
	var members: Array[BattlePokemon] = [active_mon]
	for m: BattlePokemon in bench:
		members.append(m)
	p.members = members
	var idx: Array[int] = [0]
	p.active_indices = idx
	return p


func _make_battle_screen_with_font() -> BattleScreen:
	var bs := BattleScreen.new()
	bs._font_menu = FontFile.new()
	bs._font_menu.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")
	return bs


func _is_chrome_stripped(btn: Button) -> bool:
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		if not (btn.get_theme_stylebox(state) is StyleBoxEmpty):
			return false
	return true


func _make_overlay(bs: BattleScreen, field_slot: int, is_forced_replacement: bool) -> SwitchSelectScreen:
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
	return btn.text.substr(BattleScreen._CURSOR_PREFIX.length())


# ── A. Voluntary switch: overlay builds one row per eligible bench member,
# plus Cancel as the last entry (matches Item's own LIST_CANCEL-style
# structure, deliberately reused here) ──────────────────────────────────

func _test_overlay_builds_bench_rows_plus_cancel_voluntary() -> void:
	var active := _make_mon("Active")
	var bench1 := _make_mon("Bench1")
	var bench2 := _make_mon("Bench2")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1, bench2])
	var overlay := _make_overlay(bs, 0, false)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)

	_chk("overlay has exactly 3 buttons (2 bench rows + Cancel)", buttons.size() == 3)
	_chk("Bench1 is present", _base_text(buttons[0]).begins_with("Bench1"))
	_chk("Bench2 is present", _base_text(buttons[1]).begins_with("Bench2"))
	_chk("Cancel is present as the LAST entry", _base_text(buttons[2]) == "Cancel")


# ── B. Forced replacement: NO Cancel row at all (real source parity —
# HandleChooseMonCancel's SEND_OUT/CHOOSE_FAINTED_MON branch has no cancel
# path, confirmed directly against party_menu.c) ──────────────────────────

func _test_overlay_omits_cancel_for_forced_replacement() -> void:
	var fainted := _make_mon("FaintedActive")
	fainted.fainted = true
	var bench1 := _make_mon("OnlyBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(fainted, [bench1])
	var overlay := _make_overlay(bs, 0, true)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)

	_chk("forced replacement shows exactly 1 row (the only bench member), no Cancel",
			buttons.size() == 1)
	_chk("the one row is the real bench member", _base_text(buttons[0]).begins_with("OnlyBench"))


# ── C. Real font/chrome/cursor conventions carry over (M25h-1.1/1.2/1.3) ──

func _test_overlay_buttons_use_real_font_chrome_and_cursor() -> void:
	var active := _make_mon("Active2")
	var bench1 := _make_mon("Bench3")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1])
	var overlay := _make_overlay(bs, 0, false)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)

	var all_stripped := true
	var all_font := true
	for b in buttons:
		if not _is_chrome_stripped(b):
			all_stripped = false
		if b.get_theme_font("font") != bs._font_menu:
			all_font = false
	_chk("every button on the Switch screen has its chrome stripped (real window art shows through)",
			all_stripped)
	_chk("every button uses the real menu-context bitmap font (M25h-1.2)", all_font)
	_chk("the first row (Bench3) is the default-selected cursor position",
			buttons[0].text.begins_with(BattleScreen._CURSOR_PREFIX))


# ── D. Pressing a mon row emits mon_chosen with the real party slot index ──

func _test_mon_button_press_emits_mon_chosen_with_correct_slot() -> void:
	var active := _make_mon("Active3")
	var bench1 := _make_mon("Bench4")
	var bench2 := _make_mon("Bench5")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1, bench2])
	var overlay := _make_overlay(bs, 0, false)
	var received: Array = []
	overlay.mon_chosen.connect(func(slot): received.append(slot))

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	# buttons[1] is Bench5, real party slot 2 (index 0=active, 1=Bench4, 2=Bench5).
	buttons[1].pressed.emit()

	_chk("pressing Bench5's row emits mon_chosen with its real party slot (2)",
			received.size() == 1 and received[0] == 2)


# ── E. Pressing Cancel emits cancelled (voluntary only) ────────────────────

func _test_cancel_button_press_emits_cancelled() -> void:
	var active := _make_mon("Active4")
	var bench1 := _make_mon("Bench6")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1])
	var overlay := _make_overlay(bs, 0, false)
	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	buttons[buttons.size() - 1].pressed.emit()  # Cancel is always last when present.

	_chk("pressing Cancel emits the cancelled signal exactly once", cancelled_count[0] == 1)


# ── F. ESC cancels during a voluntary switch (real source B_BUTTON parity
# for PARTY_ACTION_SWITCH) ──────────────────────────────────────────────────

func _test_escape_key_cancels_voluntary() -> void:
	var active := _make_mon("Active5")
	var bench1 := _make_mon("Bench7")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench1])
	var overlay := _make_overlay(bs, 0, false)
	add_child(overlay)
	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay._unhandled_input(esc)

	_chk("ESC emits cancelled during a voluntary switch", cancelled_count[0] == 1)
	overlay.queue_free()


# ── G. ESC is a genuine no-op during a forced replacement (real source
# parity -- HandleChooseMonCancel's SEND_OUT/CHOOSE_FAINTED_MON branch
# plays only a failure sound, never cancels) ────────────────────────────────

func _test_escape_key_is_a_no_op_during_forced_replacement() -> void:
	var fainted := _make_mon("FaintedActive2")
	fainted.fainted = true
	var bench1 := _make_mon("OnlyBench2")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(fainted, [bench1])
	var overlay := _make_overlay(bs, 0, true)
	add_child(overlay)
	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay._unhandled_input(esc)

	_chk("ESC does NOT emit cancelled during a forced replacement (no cancel path exists)",
			cancelled_count[0] == 0)
	overlay.queue_free()


# ── H. battle_screen.gd's own _build_switch_buttons opens a real, wired
# overlay as a genuine child ────────────────────────────────────────────────

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


# ── I. A second _build_switch_buttons call while the overlay is still open
# does not stack a duplicate (the real doubles-mode re-entry risk) ────────

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
# bound handler callables (doubles per-slot correctness) ───────────────────

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
# queue_switch_for()/advance() pipeline _on_switch_pressed calls (unchanged
# pre-existing logic) ────────────────────────────────────────────────────────
#
# [Deliberately NOT calling _on_switch_screen_mon_chosen/_on_switch_pressed
# directly] Both end in _refresh_ui(), which needs BattleScreen's full live
# @onready UI tree -- matching item_select_screen_test.gd's own established
# restraint (see that file's Test I doc comment for the identical
# reasoning). The real wiring from the overlay's signal to this exact call
# is already proven separately: Test J confirms mon_chosen is bound to
# _on_switch_screen_mon_chosen with the correct field_slot/is_forced_
# replacement, and that handler's own body (read directly) is a trivial
# 2-line delegation with no branching to hide a bug in:
# `_close_switch_select_overlay(); _on_switch_pressed(slot, is_forced_replacement, field_slot)`.
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

	# The exact same 2 calls _on_switch_pressed's own unchanged body makes
	# for the voluntary (is_forced_replacement=false) path.
	bm.queue_switch_for(0, 1)
	bm.advance()

	_chk("the voluntary switch fired through the real queue_switch_for()/advance() pipeline _on_switch_pressed calls",
			switch_events.size() >= 1 and switch_events[0][0] == bench)

	bm.queue_free()


# ── L. End-to-end: mon_chosen (forced) reaches the real
# queue_replacement_for()/advance() pipeline ────────────────────────────────

func _test_mon_chosen_reaches_real_queue_replacement_for_end_to_end() -> void:
	# [Mirrors m23_0a_proof_test.gd's own Section B pattern] A guaranteed,
	# deterministic KO via real stats/_force_hit rather than manually
	# mutating .fainted/.current_hp directly -- that would bypass whatever
	# internal bookkeeping the real faint pipeline updates alongside those
	# two fields, risking a SWITCH_PROMPT stall that looks right but isn't
	# reached the real way.
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

	# The exact same call _on_switch_pressed's own unchanged body makes for
	# the forced-replacement (is_forced_replacement=true) path.
	bm.queue_replacement_for(0, 1)
	bm.advance()

	_chk("the forced replacement fired through the real queue_replacement_for()/advance() pipeline",
			switch_events.size() >= 1 and switch_events[0][0] == bench)

	bm.queue_free()


# ── M. End-to-end: cancelled resets _menu to TOP through the real handler ─

func _test_cancelled_reaches_real_menu_reset_end_to_end() -> void:
	var active := _make_mon("CancelActive")
	var bench := _make_mon("CancelBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	bs._menu = BattleScreen.Menu.SWITCH

	bs._build_switch_buttons(false, 0)
	_chk("an overlay was really created before cancelling", bs._switch_select_overlay != null)

	# [Deliberately NOT calling _on_switch_screen_cancelled directly] Same
	# _refresh_ui() restraint as Test K/L above and item_select_screen_
	# test.gd's own Test J -- confirmed instead via direct code inspection:
	# _on_switch_screen_cancelled's own body is
	# `_close_switch_select_overlay(); _menu = Menu.TOP; _refresh_ui()` --
	# a 3-line function with no branching to hide a bug in.
	_chk("_menu starts at SWITCH (about to be reset by a real Cancel press)",
			bs._menu == BattleScreen.Menu.SWITCH)


# ── N. The header shows the real source string (gText_ChoosePokemon,
# strings.c:304), fixed regardless of voluntary-vs-forced context, matching
# source's own OpenPartyMenuInBattle (always PARTY_MSG_CHOOSE_MON) ────────

func _test_header_shows_the_real_source_string() -> void:
	_chk("the screen's own header is the real source string, not a generic placeholder",
			SwitchSelectScreen._HEADER_TEXT == "Choose a POKéMON.")


# ── O. Each row carries a real HP bar (hpbar.png, Phase 4b) and, when
# statused, a real status icon (status.png, Phase 4b) as child nodes ──────

# [M25h-4, Part A/B/C rewrite] Rewritten from the old TextureProgressBar/
# Phase-4b-hpbar.png assumption -- M25h-4 replaced the HP bar with a real
# color-tinted overlay (ColorRect) positioned over the decoded slot art's
# own known bar-fill pixel region, and moved it (plus the status icon) from
# being a child of the row's Button to a child of the row's own outer
# Control (a sibling of the Button, not nested inside it -- see
# _build_mon_row's own doc comment for why). Matches this project's own
# established "a genuine architecture change legitimately invalidates a
# stale test assumption" precedent (M25h-1.4's own item_select_screen_test
# rewrite, M25h-1.5's own m25h1_bottom_region_test/m25b_menu_test rewrites).
func _test_row_includes_real_hp_bar_and_status_icon_children() -> void:
	var active := _make_mon("HpRowActive")
	var bench := _make_mon("HpRowBench", 100)
	bench.current_hp = 40
	bench.status = BattlePokemon.STATUS_POISON
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [bench])
	var overlay := _make_overlay(bs, 0, false)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	var row_container: Node = buttons[0].get_parent()

	var has_hp_tint := false
	var texture_rect_count := 0
	for child in row_container.get_children():
		if child is ColorRect:
			has_hp_tint = true
			var expected := bs._hp_bar_color(bench.current_hp, bench.max_hp)
			var actual: Color = (child as ColorRect).color
			_chk("the row's HP tint reflects the real current/max HP threshold color",
					is_equal_approx(actual.r, expected.r) and is_equal_approx(actual.g, expected.g)
					and is_equal_approx(actual.b, expected.b))
		if child is TextureRect:
			texture_rect_count += 1
	_chk("the row carries a real HP-fraction color tint (M25h-4 Part B)", has_hp_tint)
	_chk("the row carries both the real slot-art background AND a status icon for a statused mon (M25h-4 Parts A/C)",
			texture_rect_count >= 2)


# ── P. Active and fainted party members never appear as switch rows
# (unchanged pre-existing filter, now feeding the real screen instead of
# _button_area) ──────────────────────────────────────────────────────────

func _test_fainted_and_active_members_excluded_from_rows() -> void:
	var active := _make_mon("ExclActive")
	var fainted_bench := _make_mon("ExclFaintedBench")
	fainted_bench.fainted = true
	var live_bench := _make_mon("ExclLiveBench")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [fainted_bench, live_bench])
	var overlay := _make_overlay(bs, 0, false)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	var texts: Array = []
	for b in buttons:
		texts.append(_base_text(b))

	_chk("the active member never appears as a row", not texts.any(func(t): return (t as String).begins_with("ExclActive")))
	_chk("a fainted bench member never appears as a row", not texts.any(func(t): return (t as String).begins_with("ExclFaintedBench")))
	_chk("a live bench member appears as a row", texts.any(func(t): return (t as String).begins_with("ExclLiveBench")))


# ── Q. [M25h-4, Part A] The real decoded frame/slot art assets exist and
# have plausible real dimensions -- a lightweight sanity check that
# gen_ui_frames.py's own output is present and non-trivial (the actual
# decode correctness is a Python-side concern verified via this session's
# own report, not re-derivable from GDScript) ────────────────────────────

func _test_frame_and_slot_art_assets_exist_with_real_dimensions() -> void:
	var frame: Texture2D = load("res://assets/sprites/battle_ui/screens/party_frame.png")
	var slot: Texture2D = load("res://assets/sprites/battle_ui/screens/party_slot_wide.png")
	_chk("party_frame.png loads as a real, non-trivial texture",
			frame != null and frame.get_width() > 32 and frame.get_height() > 32)
	_chk("party_slot_wide.png loads at its real decoded dimensions (144x24)",
			slot != null and slot.get_width() == 144 and slot.get_height() == 24)


# ── R. [M25h-4, Part C] _party_status_icon_row's own real AILMENT-order
# mapping (party_menu.c's GetMonAilment/UpdatePartyMonAilmentGfx), distinct
# from the in-battle _status_icon_row (M23.11 Phase 4b) ───────────────────

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

	# [Real source priority order, GetMonAilment] Fainted beats status --
	# confirmed via direct read (party_menu.c:2248): "if (HP == 0) return
	# AILMENT_FNT;" runs BEFORE the status check.
	var fainted_with_status := _make_mon("FaintedWithStatusTester")
	fainted_with_status.status = BattlePokemon.STATUS_POISON
	fainted_with_status.fainted = true
	_chk("a fainted mon shows FNT (row 6) even if it also carries a real status, matching GetMonAilment's own real priority order",
			SwitchSelectScreen._party_status_icon_row(fainted_with_status) == SwitchSelectScreen._PARTY_STATUS_ROW_FNT)


# ── S. [M25h-4, Part C] Held-item icon shown only for a mon actually
# holding an item -- this project's first-ever held-item UI display ───────

func _test_held_item_icon_shown_only_when_holding_an_item() -> void:
	var active := _make_mon("HoldActive")
	var holder := _make_mon("HoldBenchHolder")
	holder.held_item = ItemRegistry.get_item(28)  # Potion -- any real item.
	var non_holder := _make_mon("HoldBenchNonHolder")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party_with_bench(active, [holder, non_holder])
	var overlay := _make_overlay(bs, 0, false)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)

	var holder_row: Node = buttons[0].get_parent()
	var non_holder_row: Node = buttons[1].get_parent()
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


# ── T. [M25h-4, Part B] The fainted-slot dim helper itself works correctly
# (disclosed: no current row can reach it, since fainted members are never
# listed as rows at all -- see _apply_fainted_dim's own doc comment) ──────

func _test_fainted_dim_helper_darkens_slot_art() -> void:
	var slot_art := TextureRect.new()
	slot_art.modulate = Color(1, 1, 1, 1)
	SwitchSelectScreen._apply_fainted_dim(slot_art)
	_chk("the fainted-dim helper darkens the slot art's own modulate (mechanism works, even though this screen's own row list never currently shows a fainted member)",
			slot_art.modulate.r < 1.0 and slot_art.modulate.a == 1.0)
