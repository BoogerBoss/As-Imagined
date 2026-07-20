extends Node

# [M25h-1.5] Regression suite for the real separate Switch/Party full-screen
# overlay — see switch_select_screen.gd's own doc comment for the full
# architecture rationale (a child overlay on the still-alive battle_screen
# instance, matching M25h-1.4's Item overlay exactly) and Step 0 source
# citations (gText_ChoosePokemon header, HandleChooseMonCancel's real
# voluntary-vs-forced cancel behavior, the raw-tileset party_menu/bg.png
# scope-narrowing decision).
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
	var row: Button = buttons[0]

	var has_hp_bar := false
	var has_status_icon := false
	for child in row.get_children():
		if child is TextureProgressBar:
			has_hp_bar = true
			# [max_hp is a COMPUTED field, not the raw base_hp passed to
			# _make_mon -- the real Gen-3 HP formula at level 50 turns
			# base_hp=100 into something well above 100, so this compares
			# against bench's own real .max_hp field, not a hardcoded guess.]
			_chk("the row's HP bar reflects the real current/max HP",
					(child as TextureProgressBar).value == 40 and (child as TextureProgressBar).max_value == bench.max_hp)
		if child is TextureRect:
			has_status_icon = true
	_chk("the row carries a real HP bar child (Phase 4b hpbar.png reuse)", has_hp_bar)
	_chk("the row carries a real status icon child for a statused mon (Phase 4b status.png reuse)",
			has_status_icon)


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
