extends Node

# [M25h-1.3] Regression suite for removing Godot's default Button chrome
# (so the real text_window/1.png art from M25h-1.1 shows through cleanly)
# and the real "▶" selection cursor that replaces it as the sole selection
# indicator — see gen_battle_fonts.py's own doc comment for the Step 0
# source citation on the cursor glyph itself (both of source's own cursor
# mechanisms draw this same right-pointing-triangle marker).
#
# [Deliberately NOT tested here] The real on-screen visual result (chrome
# genuinely invisible, real window art showing through, cursor genuinely
# legible next to the right option) — matches every prior M25h/Phase-4x
# suite's own established precedent of scoping automated coverage to pure
# logic + bare-instance direct calls, leaving the real end-to-end proof to
# this session's own mandatory real screenshot pass.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_cursor_glyph_present_in_menu_font()
	_test_strip_button_chrome_applies_empty_styleboxes()
	_test_wire_cursor_group_defaults_to_first_option()
	_test_set_cursor_selected_moves_the_marker()
	_test_cursor_group_wires_a_real_mouse_entered_connection()
	_test_top_menu_buttons_have_chrome_stripped_and_cursor_wired()
	_test_fight_menu_buttons_have_chrome_stripped_and_cursor_wired()
	_test_target_select_buttons_have_chrome_stripped_and_cursor_wired()
	_test_switch_and_item_buttons_deliberately_unaffected()
	_test_battle_end_button_deliberately_unaffected()

	var total := _pass + _fail
	print("m25h1_3_cursor_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % label)


# ── Fixtures (mirrors m25b_menu_test.gd's own established shape) ──────────

func _make_mon(mon_name: String, hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
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


func _base_text(t: String) -> String:
	return t.substr(BattleScreen._CURSOR_PREFIX.length())


func _is_chrome_stripped(btn: Button) -> bool:
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		if not (btn.get_theme_stylebox(state) is StyleBoxEmpty):
			return false
	return true


# ── A. The cursor glyph itself ─────────────────────────────────────────────

func _test_cursor_glyph_present_in_menu_font() -> void:
	var font := FontFile.new()
	font.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")
	_chk("the real ▶ cursor glyph is present in the menu-context font",
			font.has_char(BattleScreen._CURSOR_GLYPH.unicode_at(0)))
	_chk("BattleScreen._CURSOR_PREFIX and _CURSOR_BLANK are the same length (consistent row alignment)",
			BattleScreen._CURSOR_PREFIX.length() == BattleScreen._CURSOR_BLANK.length())


# ── B. _strip_button_chrome applies a real no-op stylebox to every state ──

func _test_strip_button_chrome_applies_empty_styleboxes() -> void:
	var bs := BattleScreen.new()
	var btn := Button.new()

	bs._strip_button_chrome(btn)

	_chk("chrome-stripped button has an empty stylebox for every interaction state",
			_is_chrome_stripped(btn))


# ── C. _wire_cursor_group defaults selection to the first button ──────────

func _test_wire_cursor_group_defaults_to_first_option() -> void:
	var bs := BattleScreen.new()
	var a := Button.new()
	a.text = "Alpha"
	var b := Button.new()
	b.text = "Beta"
	var buttons: Array[Button] = [a, b]

	bs._wire_cursor_group(buttons)

	_chk("the first button is prefixed with the real cursor glyph",
			a.text == BattleScreen._CURSOR_PREFIX + "Alpha")
	_chk("the second button is prefixed with the blank (same-width) slot instead",
			b.text == BattleScreen._CURSOR_BLANK + "Beta")


# ── D. _set_cursor_selected moves the marker to a different index ─────────

func _test_set_cursor_selected_moves_the_marker() -> void:
	var bs := BattleScreen.new()
	var a := Button.new()
	a.text = "Alpha"
	var b := Button.new()
	b.text = "Beta"
	var buttons: Array[Button] = [a, b]
	bs._wire_cursor_group(buttons)

	bs._set_cursor_selected(buttons, 1)

	_chk("moving selection to index 1 blanks the first button",
			a.text == BattleScreen._CURSOR_BLANK + "Alpha")
	_chk("moving selection to index 1 marks the second button",
			b.text == BattleScreen._CURSOR_PREFIX + "Beta")


# ── E. Each button in a wired group has a real mouse_entered connection ───

func _test_cursor_group_wires_a_real_mouse_entered_connection() -> void:
	var bs := BattleScreen.new()
	var a := Button.new()
	a.text = "Alpha"
	var buttons: Array[Button] = [a]

	bs._wire_cursor_group(buttons)

	_chk("the button gained a real mouse_entered connection (hover tracking, this project's one real menu input method)",
			a.mouse_entered.get_connections().size() > 0)


# ── F. The 3 real in-scope builders (ActionPanel's own real window art)
# both strip chrome AND wire the cursor, end to end ────────────────────────

func _test_top_menu_buttons_have_chrome_stripped_and_cursor_wired() -> void:
	var mon := _make_mon("CursorTop")
	mon.add_move(_load_move(33))
	var bs := BattleScreen.new()
	bs._player_party = _singles_party(mon)
	bs._new_button_area = VBoxContainer.new()

	bs._build_top_menu(0)

	var buttons: Array = bs._new_button_area.get_children()
	_chk("TOP menu has exactly 4 buttons", buttons.size() == 4)
	var all_stripped := true
	var all_wired := true
	var texts: Array = []
	for c in buttons:
		if not _is_chrome_stripped(c):
			all_stripped = false
		if c.mouse_entered.get_connections().size() == 0:
			all_wired = false
		texts.append(_base_text(c.text))
	_chk("every TOP menu button has its chrome stripped", all_stripped)
	_chk("every TOP menu button has a real mouse_entered cursor connection", all_wired)
	_chk("Fight is the default-selected (first) option",
			buttons[0].text == BattleScreen._CURSOR_PREFIX + "Fight")
	_chk("the real option text survives underneath the cursor prefix",
			texts.has("Fight") and texts.has("Switch") and texts.has("Item") and texts.has("Run"))


func _test_fight_menu_buttons_have_chrome_stripped_and_cursor_wired() -> void:
	var mon := _make_mon("CursorFight")
	mon.add_move(_load_move(33))
	mon.add_move(_load_move(52))
	var bs := BattleScreen.new()
	bs._player_party = _singles_party(mon)
	bs._new_button_area = VBoxContainer.new()

	bs._build_fight_menu(0)

	var buttons: Array = bs._new_button_area.get_children()
	_chk("Fight menu has exactly 2 moves + Back", buttons.size() == 3)
	var all_stripped := true
	for c in buttons:
		if not _is_chrome_stripped(c):
			all_stripped = false
	_chk("every Fight menu button has its chrome stripped", all_stripped)
	_chk("the first move is the default-selected option",
			(buttons[0].text as String).begins_with(BattleScreen._CURSOR_PREFIX))
	_chk("Back is NOT selected by default (only one cursor position at a time)",
			_base_text(buttons[2].text) == "Back" and (buttons[2].text as String).begins_with(BattleScreen._CURSOR_BLANK))


func _test_target_select_buttons_have_chrome_stripped_and_cursor_wired() -> void:
	var attacker := _make_mon("CursorAttacker")
	var earthquake := _load_move(89)
	attacker.add_move(earthquake)
	var opp0 := _make_mon("CursorOpp0")
	var opp1 := _make_mon("CursorOpp1")

	var bs := BattleScreen.new()
	bs._player_party = _singles_party(attacker)
	bs._new_button_area = VBoxContainer.new()
	bs._menu = BattleScreen.Menu.TARGET_SELECT
	bs._pending_move_index = 0

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.set_human_controlled(1, true)
	var ally := _make_mon("CursorAlly")
	var p1 := BattleParty.new()
	var p1_members: Array[BattlePokemon] = [attacker, ally]
	p1.members = p1_members
	var p1_active: Array[int] = [0, 1]
	p1.active_indices = p1_active
	var p2 := BattleParty.new()
	var p2_members: Array[BattlePokemon] = [opp0, opp1]
	p2.members = p2_members
	var p2_active: Array[int] = [0, 1]
	p2.active_indices = p2_active
	bm.start_battle_doubles(p1, p2)
	bs._bm = bm

	bs._build_target_select_buttons(0, 0)

	var buttons: Array = bs._new_button_area.get_children()
	_chk("TARGET_SELECT has at least one candidate + Back", buttons.size() >= 2)
	var all_stripped := true
	var all_wired := true
	for c in buttons:
		if not _is_chrome_stripped(c):
			all_stripped = false
		if c.mouse_entered.get_connections().size() == 0:
			all_wired = false
	_chk("every TARGET_SELECT button has its chrome stripped", all_stripped)
	_chk("every TARGET_SELECT button has a real mouse_entered cursor connection", all_wired)
	_chk("the first candidate is the default-selected option",
			(buttons[0].text as String).begins_with(BattleScreen._CURSOR_PREFIX))

	bm.queue_free()


# ── G. The old inline _button_area (no real window art) is deliberately
# left untouched -- a real, disclosed scope boundary, not an oversight ────

func _test_switch_and_item_buttons_deliberately_unaffected() -> void:
	var mon := _make_mon("CursorSwitchTester")
	var bench := _make_mon("CursorBench")
	var bs := BattleScreen.new()
	bs._player_party = _singles_party(mon, [bench])
	bs._button_area = VBoxContainer.new()
	bs._menu = BattleScreen.Menu.SWITCH

	bs._build_switch_buttons(false, 0)

	var buttons: Array = bs._button_area.get_children()
	var any_stripped := false
	var any_wired := false
	var any_prefixed := false
	for c in buttons:
		if _is_chrome_stripped(c):
			any_stripped = true
		if c.mouse_entered.get_connections().size() > 0:
			any_wired = true
		if (c.text as String).begins_with(BattleScreen._CURSOR_PREFIX) or (c.text as String).begins_with(BattleScreen._CURSOR_BLANK):
			any_prefixed = true
	_chk("Switch buttons keep Godot's own default chrome (no real window art behind them yet)",
			not any_stripped)
	_chk("Switch buttons have no cursor wiring", not any_wired)
	_chk("Switch buttons' text has no cursor prefix at all", not any_prefixed)


func _test_battle_end_button_deliberately_unaffected() -> void:
	var bs := BattleScreen.new()
	bs._button_area = VBoxContainer.new()

	bs._build_battle_end_buttons()

	var btn: Button = bs._button_area.get_children()[0]
	_chk("Play Again keeps Godot's own default chrome", not _is_chrome_stripped(btn))
	_chk("Play Again's text has no cursor prefix", btn.text == "Play Again")
