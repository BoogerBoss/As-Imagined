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
	_test_switch_buttons_no_longer_use_old_button_area()
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
	return t.substr(BattleScreenShared._CURSOR_PREFIX.length())


func _is_chrome_stripped(btn: Button) -> bool:
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		if not (btn.get_theme_stylebox(state) is StyleBoxEmpty):
			return false
	return true


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


# [Doubles-split roadmap, step 8] _new_button_grid now permanently holds 8
# children (TOP's 4 + FIGHT's 4-slot move pool) -- only the VISIBLE subset
# is "in" the menu currently being shown, the rest are hidden, not absent.
func _visible_buttons(container: Container) -> Array:
	return container.get_children().filter(func(c): return c is Button and c.visible)


# ── A. The cursor glyph itself ─────────────────────────────────────────────

func _test_cursor_glyph_present_in_menu_font() -> void:
	var font := FontFile.new()
	font.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")
	_chk("the real ▶ cursor glyph is present in the menu-context font",
			font.has_char(BattleScreenShared._CURSOR_GLYPH.unicode_at(0)))
	_chk("BattleScreenShared._CURSOR_PREFIX and _CURSOR_BLANK are the same length (consistent row alignment)",
			BattleScreenShared._CURSOR_PREFIX.length() == BattleScreenShared._CURSOR_BLANK.length())


# ── B. _strip_button_chrome applies a real no-op stylebox to every state ──

func _test_strip_button_chrome_applies_empty_styleboxes() -> void:
	var bs := BattleScreenShared.new()
	var btn := Button.new()

	bs._strip_button_chrome(btn)

	_chk("chrome-stripped button has an empty stylebox for every interaction state",
			_is_chrome_stripped(btn))


# ── C. _wire_cursor_group defaults selection to the first button ──────────

func _test_wire_cursor_group_defaults_to_first_option() -> void:
	var bs := BattleScreenShared.new()
	var a := Button.new()
	a.text = "Alpha"
	var b := Button.new()
	b.text = "Beta"
	var buttons: Array[Button] = [a, b]

	bs._wire_cursor_group(buttons)

	_chk("the first button is prefixed with the real cursor glyph",
			a.text == BattleScreenShared._CURSOR_PREFIX + "Alpha")
	_chk("the second button is prefixed with the blank (same-width) slot instead",
			b.text == BattleScreenShared._CURSOR_BLANK + "Beta")


# ── D. _set_cursor_selected moves the marker to a different index ─────────

func _test_set_cursor_selected_moves_the_marker() -> void:
	var bs := BattleScreenShared.new()
	var a := Button.new()
	a.text = "Alpha"
	var b := Button.new()
	b.text = "Beta"
	var buttons: Array[Button] = [a, b]
	bs._wire_cursor_group(buttons)

	bs._set_cursor_selected(buttons, 1)

	_chk("moving selection to index 1 blanks the first button",
			a.text == BattleScreenShared._CURSOR_BLANK + "Alpha")
	_chk("moving selection to index 1 marks the second button",
			b.text == BattleScreenShared._CURSOR_PREFIX + "Beta")


# ── E. Each button in a wired group has a real mouse_entered connection ───

func _test_cursor_group_wires_a_real_mouse_entered_connection() -> void:
	var bs := BattleScreenShared.new()
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
	var bs := BattleScreenShared.new()
	bs._player_party = _singles_party(mon)
	bs._new_button_grid = GridContainer.new()
	_wire_menu_buttons(bs)

	bs._build_top_menu(0)

	# [M26c-3] TOP now builds into the real 2x2 grid (_new_button_grid),
	# not _new_button_area -- see battle_screen.gd's own _new_button_grid
	# onready doc comment.
	var buttons: Array = _visible_buttons(bs._new_button_grid)
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
			buttons[0].text == BattleScreenShared._CURSOR_PREFIX + "Fight")
	_chk("the real option text survives underneath the cursor prefix",
			texts.has("Fight") and texts.has("Switch") and texts.has("Item") and texts.has("Run"))


func _test_fight_menu_buttons_have_chrome_stripped_and_cursor_wired() -> void:
	var mon := _make_mon("CursorFight")
	mon.add_move(_load_move(33))
	mon.add_move(_load_move(52))
	var bs := BattleScreenShared.new()
	bs._player_party = _singles_party(mon)
	bs._new_button_grid = GridContainer.new()
	bs._new_button_area = VBoxContainer.new()
	_wire_menu_buttons(bs)
	# [M26c-3 real-proportion fix] _build_fight_menu now also calls
	# _on_fight_move_hovered() for the default-selected move, which writes
	# into the real MoveInfoPanel fields -- manually wire stand-ins the same
	# way _font_menu is manually wired for the SWITCH test below, since
	# these are real @onready fields that never resolve on a bare instance.
	bs._move_info_type_label = Label.new()
	bs._move_info_pp_label = Label.new()

	bs._build_fight_menu(0)

	# [M26c-3] The 2 moves now live in the real 2x2 grid; Back is a
	# separate row in _new_button_area below it -- see
	# _build_fight_menu's own doc comment.
	var move_buttons: Array = _visible_buttons(bs._new_button_grid)
	var back_buttons: Array = bs._new_button_area.get_children()
	_chk("Fight menu has exactly 2 moves in the grid", move_buttons.size() == 2)
	_chk("Fight menu has exactly 1 Back button below the grid", back_buttons.size() == 1)
	var all_stripped := true
	for c in move_buttons + back_buttons:
		if not _is_chrome_stripped(c):
			all_stripped = false
	_chk("every Fight menu button has its chrome stripped", all_stripped)
	_chk("the first move is the default-selected option",
			(move_buttons[0].text as String).begins_with(BattleScreenShared._CURSOR_PREFIX))
	_chk("Back is NOT selected by default (only one cursor position at a time)",
			_base_text(back_buttons[0].text) == "Back" and (back_buttons[0].text as String).begins_with(BattleScreenShared._CURSOR_BLANK))


func _test_target_select_buttons_have_chrome_stripped_and_cursor_wired() -> void:
	var attacker := _make_mon("CursorAttacker")
	var earthquake := _load_move(89)
	attacker.add_move(earthquake)
	var opp0 := _make_mon("CursorOpp0")
	var opp1 := _make_mon("CursorOpp1")

	var bs := BattleScreenShared.new()
	bs._player_party = _singles_party(attacker)
	bs._new_button_area = VBoxContainer.new()
	bs._menu = BattleScreenShared.Menu.TARGET_SELECT
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

	# [Doubles-split roadmap, step 6] _health_group_for()/_sprite_node_for()
	# now read the generic _opp_panels/_ply_panels/_opp_sprites/_ply_sprites
	# arrays (sized 1 or 2, no more separate "_d"-suffixed doubles-only
	# arrays or an _is_doubles_mode flag) -- these @onready-equivalent
	# fields never get assigned on a bare BattleScreenShared.new() instance,
	# so they must be wired manually here, mirroring m26c1_databox_test.gd's
	# established manual-onready-wiring convention. Plain Control stubs
	# (not real HealthGroupPanel scenes) are enough since this test only
	# checks wiring/identity, never calls refresh() on them.
	# _opp_party/_player_party (used by _field_slot_for to resolve which
	# doubles slot a candidate occupies) also need to be the SAME real party
	# objects start_battle_doubles built, not left null — a null _opp_party
	# would crash _field_slot_for's own party.num_active() call outright
	# (see m25c_message_log_test.gd's own real bug write-up for this exact
	# failure mode) rather than silently defaulting, now that every lookup
	# unconditionally goes through _field_slot_for regardless of format.
	# [Real bug found while re-verifying this suite] _panel_for() does
	# `panels[slot] as HealthGroupPanel` — a plain Control stand-in fails
	# that runtime cast and silently resolves to null (the sprite lookup's
	# own `as Control` cast doesn't have this problem, which is why only
	# the health-group half of each zone pair went missing). Real
	# HealthGroupPanel instances are needed here, matching
	# phase4d_doubles_visual_test.gd's own established precedent — plain
	# Control stubs are still fine for the sprite arrays below.
	bs._opp_party = p2
	bs._player_party = p1
	bs._opp_panels = [HealthGroupPanel.new(), HealthGroupPanel.new()]
	bs._ply_panels = [HealthGroupPanel.new(), HealthGroupPanel.new()]
	bs._opp_sprites = [Control.new(), Control.new()]
	bs._ply_sprites = [Control.new(), Control.new()]

	bs._build_target_select_buttons(0, 0)

	# [Phase B] Each of the 2 live opponents now wires TWO zones (health
	# group + sprite), so the real total is 4, not 2.
	_chk("TARGET_SELECT wires 4 zones (2 opponents x health-group + sprite)",
			bs._target_select_wired.size() == 4)
	var wired_controls: Array = []
	for entry: Dictionary in bs._target_select_wired:
		wired_controls.append(entry.get("group"))
	var unique_controls := {}
	for c in wired_controls:
		unique_controls[c] = true
	_chk("all 4 wired zones are distinct Controls (no duplicate/aliased slot)",
			unique_controls.size() == 4)
	_chk("both opponents' own health group AND sprite are present among the wired zones",
			wired_controls.has(bs._opp_panels[0]) and wired_controls.has(bs._opp_panels[1])
			and wired_controls.has(bs._opp_sprites[0]) and wired_controls.has(bs._opp_sprites[1]))
	var all_hoverable := true
	var all_click_wired := true
	for entry: Dictionary in bs._target_select_wired:
		var group: Control = entry.get("group")
		if group == null or group.mouse_filter != Control.MOUSE_FILTER_STOP:
			all_hoverable = false
		if not entry.get("enter_cb").is_valid() or not entry.get("exit_cb").is_valid() \
				or not entry.get("click_cb").is_valid():
			all_click_wired = false
	_chk("every wired zone is mouse_filter STOP (hoverable)",
			all_hoverable)
	_chk("every wired zone has real bound enter/exit/click callables",
			all_click_wired)

	var back_buttons: Array = bs._new_button_area.get_children()
	_chk("TARGET_SELECT still builds exactly one Back button", back_buttons.size() == 1)
	_chk("Back button has its chrome stripped", _is_chrome_stripped(back_buttons[0]))
	_chk("Back button is the default-selected cursor option",
			(back_buttons[0].text as String).begins_with(BattleScreenShared._CURSOR_PREFIX))

	bs._clear_target_select_hover_wiring()
	bm.queue_free()


# ── G. The old inline _button_area (no real window art) is deliberately
# left untouched -- a real, disclosed scope boundary, not an oversight.
# [M25h-1.4/M25h-1.5 note] Neither Item NOR Switch is in this "deliberately
# unaffected" category anymore -- both now have their own real overlay
# screens (see item_select_screen_test.gd/switch_select_screen_test.gd).
# Only battle-end remains here. Switch's own real chrome/cursor coverage
# now lives entirely in switch_select_screen_test.gd's own Test C
# (_test_overlay_buttons_use_real_font_chrome_and_cursor) -- this test is
# narrowed to a regression guard confirming _button_area stays genuinely
# untouched (empty) when Switch opens its real overlay instead, rather than
# re-asserting Switch's old "no chrome" premise, which is no longer true.
func _test_switch_buttons_no_longer_use_old_button_area() -> void:
	var mon := _make_mon("CursorSwitchTester")
	var bench := _make_mon("CursorBench")
	var bs := BattleScreenShared.new()
	bs._player_party = _singles_party(mon, [bench])
	bs._button_area = VBoxContainer.new()
	bs._menu = BattleScreenShared.Menu.SWITCH
	bs._font_menu = FontFile.new()
	bs._font_menu.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")

	bs._build_switch_buttons(false, 0)

	_chk("Switch no longer writes into the old _button_area at all (real overlay instead)",
			bs._button_area.get_child_count() == 0)
	_chk("Switch opens a real SwitchSelectScreen overlay",
			bs._switch_select_overlay != null and bs._switch_select_overlay is SwitchSelectScreen)


func _test_battle_end_button_deliberately_unaffected() -> void:
	var bs := BattleScreenShared.new()
	bs._button_area = VBoxContainer.new()

	bs._build_battle_end_buttons()

	var btn: Button = bs._button_area.get_children()[0]
	_chk("Play Again keeps Godot's own default chrome", not _is_chrome_stripped(btn))
	_chk("Play Again's text has no cursor prefix", btn.text == "Play Again")
