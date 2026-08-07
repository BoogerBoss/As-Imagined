extends Node

# [M26C8] Regression suite for keyboard menu navigation -- the real [input]
# section added to project.godot (ui_up/down/left/right/accept/cancel,
# reusing the SAME action names the overworld already dispatches on) plus
# the keyboard-driven cursor state added to battle_screen_shared.gd's
# existing "▶" cursor mechanism (_wire_cursor_group/_set_cursor_selected,
# M25h-1.3 -- previously mouse-hover-only).
#
# [Deliberately NOT tested here, matching m25b_menu_test.gd's own
# established precedent] The real button-press -> _refresh_ui() ->
# re-render loop for TOP/FIGHT/TARGET_SELECT's own real handlers (Fight/
# Item/Switch/Run, move dispatch, target confirm) -- those need a live
# scene tree with every @onready UI node resolved (message box, action
# panel, health groups), which a bare BattleScreenShared.new() doesn't
# have. This suite exercises the keyboard MECHANISM itself (grid/list
# math, the phase gate, real signal firing) directly, using dummy buttons
# or the one real screen whose own handlers are plain signal emissions
# with no UI dependency (ItemSelectScreen) -- the real end-to-end proof
# for TOP/FIGHT/TARGET_SELECT is a real non-headless playthrough.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_grid_right_left_up_down()
	_test_grid_clamps_at_edges()
	_test_grid_clamps_on_short_trailing_row()
	_test_list_up_down_clamped()
	_test_list_left_right_are_no_ops()
	_test_wire_cursor_group_defaults_to_index_zero()
	_test_mouse_hover_and_keyboard_cursor_stay_in_sync()

	_test_confirm_does_nothing_with_no_battle_manager()
	_test_confirm_does_nothing_outside_move_selection_or_switch_prompt()
	_test_confirm_fires_pressed_during_move_selection()
	_test_confirm_does_not_fire_disabled_button()
	_test_confirm_does_not_fire_invisible_button()

	_test_item_screen_keyboard_down_then_accept_picks_second_row()
	_test_item_screen_keyboard_reaches_cancel_and_confirms()
	_test_item_screen_left_right_still_owned_by_pocket_cycling()

	_test_target_select_defaults_to_first_candidate()
	_test_target_select_keyboard_cycles_and_wraps()
	_test_target_select_confirm_is_a_no_op_with_no_candidates()

	_test_inputmap_has_real_ui_actions()
	_test_physical_keycode_event_matches_ui_action()

	var total := _pass + _fail
	print("m26c8_input_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Fixtures ─────────────────────────────────────────────────────────────

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
	p.active_indices = [0]
	return p


func _doubles_party(mons: Array) -> BattleParty:
	var p := BattleParty.new()
	var typed: Array[BattlePokemon] = []
	for m: BattlePokemon in mons:
		typed.append(m)
	p.members = typed
	p.active_indices = [0, 1]
	return p


# Matches the exact physical-keycode-only shape project.godot's own [input]
# section declares (keycode left at 0), so a synthetic event here matches
# the InputMap the same way a real keyboard event would -- InputEventKey's
# own action-matching compares whichever of keycode/physical_keycode is
# actually set.
func _key_event(physical_keycode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = physical_keycode
	e.pressed = true
	return e


func _make_battle_manager_paused_singles(player_mon: BattlePokemon, opp_mon: BattlePokemon) -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(_singles_party(player_mon), _singles_party(opp_mon))
	return bm


func _make_battle_manager_paused_doubles(p1: Array, p2: Array) -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.set_human_controlled(1, true)
	bm.start_battle_doubles(_doubles_party(p1), _doubles_party(p2))
	return bm


func _make_item_overlay(bs: BattleScreenShared) -> ItemSelectScreen:
	var scene: PackedScene = load("res://scenes/battle/item_select_screen.tscn")
	var overlay: ItemSelectScreen = scene.instantiate()
	overlay.setup(bs, 0)
	return overlay


# ── A. _move_cursor -- 2x2 grid math (TOP/FIGHT's own shape) ─────────────

func _make_4_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for i in range(4):
		var b := Button.new()
		b.text = "b%d" % i
		out.append(b)
	return out


func _test_grid_right_left_up_down() -> void:
	var bs := BattleScreenShared.new()
	var buttons := _make_4_buttons()
	bs._wire_cursor_group(buttons, 2)

	bs._move_cursor(0, 1)
	_chk("right from top-left(0) selects top-right(1)", bs._cursor_index == 1)

	bs._move_cursor(1, 0)
	_chk("down from top-right(1) selects bottom-right(3)", bs._cursor_index == 3)

	bs._move_cursor(0, -1)
	_chk("left from bottom-right(3) selects bottom-left(2)", bs._cursor_index == 2)

	bs._move_cursor(-1, 0)
	_chk("up from bottom-left(2) selects top-left(0)", bs._cursor_index == 0)
	bs.free()


func _test_grid_clamps_at_edges() -> void:
	var bs := BattleScreenShared.new()
	bs._wire_cursor_group(_make_4_buttons(), 2)

	bs._move_cursor(-1, 0)
	_chk("up from top-left(0) stays at 0 -- no wrap", bs._cursor_index == 0)
	bs._move_cursor(0, -1)
	_chk("left from top-left(0) stays at 0 -- no wrap", bs._cursor_index == 0)

	bs._move_cursor(1, 1)  # -> bottom-right(3)
	bs._move_cursor(1, 0)
	_chk("down from bottom-right(3) stays at 3 -- no wrap", bs._cursor_index == 3)
	bs._move_cursor(0, 1)
	_chk("right from bottom-right(3) stays at 3 -- no wrap", bs._cursor_index == 3)
	bs.free()


func _test_grid_clamps_on_short_trailing_row() -> void:
	# A 3-move Pokémon's own FIGHT grid: bottom row has only ONE real cell
	# (index 2), matching source's own gNumberOfMovesToChoose clamp.
	var bs := BattleScreenShared.new()
	var buttons: Array[Button] = []
	for i in range(3):
		var b := Button.new()
		buttons.append(b)
	bs._wire_cursor_group(buttons, 2)

	bs._move_cursor(1, 0)  # down -> bottom-left(2), the only real cell in row 1
	_chk("down from top-left(0) reaches the short row's own cell (2)", bs._cursor_index == 2)
	bs._move_cursor(0, 1)  # right -- would be index 3, which doesn't exist
	_chk("right from the short row's cell clamps back to itself (2), not off the array",
			bs._cursor_index == 2)
	bs.free()


# ── A2. _move_cursor -- plain vertical lists (Item/Switch/Summary's shape) ─

func _make_n_buttons(n: int) -> Array[Button]:
	var out: Array[Button] = []
	for i in range(n):
		out.append(Button.new())
	return out


func _test_list_up_down_clamped() -> void:
	var bs := BattleScreenShared.new()
	bs._wire_cursor_group(_make_n_buttons(3), 1)  # default columns=1

	bs._move_cursor(1, 0)
	_chk("down from 0 selects 1 in a plain vertical list", bs._cursor_index == 1)
	bs._move_cursor(1, 0)
	_chk("down from 1 selects 2", bs._cursor_index == 2)
	bs._move_cursor(1, 0)
	_chk("down from the last entry (2) stays at 2 -- no wrap", bs._cursor_index == 2)

	bs._move_cursor(-1, 0)
	bs._move_cursor(-1, 0)
	_chk("two ups from 2 lands back at 0", bs._cursor_index == 0)
	bs._move_cursor(-1, 0)
	_chk("up from 0 stays at 0 -- no wrap", bs._cursor_index == 0)
	bs.free()


func _test_list_left_right_are_no_ops() -> void:
	var bs := BattleScreenShared.new()
	bs._wire_cursor_group(_make_n_buttons(3), 1)
	bs._move_cursor(1, 0)  # -> index 1
	bs._move_cursor(0, 1)  # right -- should do nothing in a single-column list
	_chk("right is a no-op in a single-column list (stays at 1)", bs._cursor_index == 1)
	bs._move_cursor(0, -1)
	_chk("left is a no-op too (stays at 1)", bs._cursor_index == 1)
	bs.free()


# ── B. _wire_cursor_group defaults + mouse-hover/keyboard sync ───────────

func _test_wire_cursor_group_defaults_to_index_zero() -> void:
	var bs := BattleScreenShared.new()
	var buttons := _make_4_buttons()
	bs._wire_cursor_group(buttons, 2)
	_chk("a freshly-wired group defaults its cursor to index 0",
			bs._cursor_index == 0 and bs._cursor_buttons == buttons)
	bs.free()


func _test_mouse_hover_and_keyboard_cursor_stay_in_sync() -> void:
	# _set_cursor_selected is the SAME function a real mouse_entered listener
	# calls -- simulating a hover here proves the keyboard cursor picks up
	# from wherever the mouse last left it, not a stale value.
	var bs := BattleScreenShared.new()
	var buttons := _make_4_buttons()
	bs._wire_cursor_group(buttons, 2)
	bs._set_cursor_selected(buttons, 3)  # simulated mouse hover on index 3
	bs._move_cursor(0, -1)  # keyboard left, from wherever the mouse left it
	_chk("keyboard movement continues from the mouse's own last selection",
			bs._cursor_index == 2)
	bs.free()


# ── C. _confirm_cursor_selection -- the MOVE_SELECTION/SWITCH_PROMPT gate ─

func _test_confirm_does_nothing_with_no_battle_manager() -> void:
	var bs := BattleScreenShared.new()
	var buttons := _make_4_buttons()
	bs._wire_cursor_group(buttons, 2)
	var fired := [false]
	buttons[0].pressed.connect(func(): fired[0] = true)
	bs._confirm_cursor_selection()
	_chk("Confirm with no _bm at all is a safe no-op", not fired[0])
	bs.free()


func _test_confirm_does_nothing_outside_move_selection_or_switch_prompt() -> void:
	var bs := BattleScreenShared.new()
	bs._bm = BattleManager.new()
	add_child(bs._bm)
	# A freshly-constructed BattleManager starts at BATTLE_START, never
	# having been advanced into MOVE_SELECTION.
	_chk("fixture sanity: fresh BattleManager isn't in MOVE_SELECTION/SWITCH_PROMPT",
			bs._bm.get_phase() != BattleManager.BattlePhase.MOVE_SELECTION
			and bs._bm.get_phase() != BattleManager.BattlePhase.SWITCH_PROMPT)
	var buttons := _make_4_buttons()
	bs._wire_cursor_group(buttons, 2)
	var fired := [false]
	buttons[0].pressed.connect(func(): fired[0] = true)
	bs._confirm_cursor_selection()
	_chk("Confirm outside MOVE_SELECTION/SWITCH_PROMPT is a safe no-op", not fired[0])
	bs._bm.queue_free()
	bs.free()


func _test_confirm_fires_pressed_during_move_selection() -> void:
	var mon := _make_mon("Confirmer")
	mon.add_move(_load_move(33))
	var opp := _make_mon("Opp")
	opp.add_move(_load_move(33))
	var bm := _make_battle_manager_paused_singles(mon, opp)
	_chk("fixture sanity: paused at MOVE_SELECTION",
			bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION)

	var bs := BattleScreenShared.new()
	bs._bm = bm
	var buttons := _make_4_buttons()
	bs._wire_cursor_group(buttons, 2)
	bs._move_cursor(0, 1)  # -> index 1
	var fired := [-1]
	buttons[0].pressed.connect(func(): fired[0] = 0)
	buttons[1].pressed.connect(func(): fired[0] = 1)
	bs._confirm_cursor_selection()
	_chk("Confirm fires the currently-selected button's real pressed signal",
			fired[0] == 1)
	bm.queue_free()
	bs.free()


func _test_confirm_does_not_fire_disabled_button() -> void:
	var mon := _make_mon("ConfirmerB")
	mon.add_move(_load_move(33))
	var opp := _make_mon("OppB")
	opp.add_move(_load_move(33))
	var bm := _make_battle_manager_paused_singles(mon, opp)

	var bs := BattleScreenShared.new()
	bs._bm = bm
	var buttons := _make_4_buttons()
	buttons[0].disabled = true
	bs._wire_cursor_group(buttons, 2)
	var fired := [false]
	buttons[0].pressed.connect(func(): fired[0] = true)
	bs._confirm_cursor_selection()
	_chk("Confirm refuses a disabled selected button, matching a real click's own refusal",
			not fired[0])
	bm.queue_free()
	bs.free()


func _test_confirm_does_not_fire_invisible_button() -> void:
	var mon := _make_mon("ConfirmerC")
	mon.add_move(_load_move(33))
	var opp := _make_mon("OppC")
	opp.add_move(_load_move(33))
	var bm := _make_battle_manager_paused_singles(mon, opp)

	var bs := BattleScreenShared.new()
	bs._bm = bm
	var buttons := _make_4_buttons()
	buttons[0].visible = false
	bs._wire_cursor_group(buttons, 2)
	var fired := [false]
	buttons[0].pressed.connect(func(): fired[0] = true)
	bs._confirm_cursor_selection()
	# [Regression guard] Without a stale menu's own hidden buttons being
	# refused here, mashing Confirm during the paced replay after a turn's
	# already been submitted (see _confirm_cursor_selection's own doc
	# comment) could re-fire whatever was selected before submission.
	_chk("Confirm refuses an invisible (stale-menu) selected button",
			not fired[0])
	bm.queue_free()
	bs.free()


# ── D. Real end-to-end keyboard nav+confirm -- ItemSelectScreen ──────────
# [Why this screen specifically] Its own row/Cancel handlers are plain
# signal emissions (item_chosen/cancelled) with no _refresh_ui()/message-box
# dependency -- see this file's own class-level doc comment for why TOP/
# FIGHT/TARGET_SELECT's real handlers can't be driven this way headlessly.

func _test_item_screen_keyboard_down_then_accept_picks_second_row() -> void:
	OverworldSession.reset()
	OverworldSession.bag.add(28, 5)   # Potion
	OverworldSession.bag.add(48, 5)   # Full Heal

	var mon := _make_mon("ItemNav")
	mon.add_move(_load_move(33))
	var opp := _make_mon("OppItem")
	opp.add_move(_load_move(33))
	var bm := _make_battle_manager_paused_singles(mon, opp)

	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs.is_overworld_battle = true  # skip the debug-stock seed, use only what's added above
	var overlay := _make_item_overlay(bs)
	add_child(overlay)

	var chosen: Array = []
	overlay.item_chosen.connect(func(id): chosen.append(id))

	_chk("overlay's own row buttons are the shared cursor group",
			bs._cursor_buttons.size() >= 2 and bs._cursor_index == 0)

	bs._unhandled_input(_key_event(KEY_DOWN))
	_chk("ui_down moved the cursor off the first row", bs._cursor_index == 1)

	bs._unhandled_input(_key_event(KEY_ENTER))
	_chk("ui_accept chose the SECOND row's real item, not the first",
			chosen.size() == 1 and chosen[0] == 48)

	bm.queue_free()
	overlay.queue_free()
	bs.free()


func _test_item_screen_keyboard_reaches_cancel_and_confirms() -> void:
	OverworldSession.reset()
	OverworldSession.bag.add(28, 5)  # Potion -- exactly one row + Cancel

	var mon := _make_mon("ItemNav2")
	mon.add_move(_load_move(33))
	var opp := _make_mon("OppItem2")
	opp.add_move(_load_move(33))
	var bm := _make_battle_manager_paused_singles(mon, opp)

	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs.is_overworld_battle = true
	var overlay := _make_item_overlay(bs)
	add_child(overlay)

	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	bs._unhandled_input(_key_event(KEY_DOWN))  # row -> Cancel (last entry)
	bs._unhandled_input(_key_event(KEY_ENTER))
	_chk("keyboard-navigating down to Cancel and confirming emits cancelled",
			cancelled_count[0] == 1)

	bm.queue_free()
	overlay.queue_free()
	bs.free()


func _test_item_screen_left_right_still_owned_by_pocket_cycling() -> void:
	# [Regression guard] ItemSelectScreen's own raw-keycode Left/Right
	# (pocket cycling) must stay the sole owner of those keys -- the shared
	# cursor group here is columns=1, so _move_cursor's own left/right is a
	# no-op and can never fight it for the same physical key.
	OverworldSession.reset()
	OverworldSession.bag.add(28, 5)
	OverworldSession.bag.add(1, 5)  # Poké Ball -- a second, distinct pocket

	var mon := _make_mon("ItemNav3")
	mon.add_move(_load_move(33))
	var opp := _make_mon("OppItem3")
	opp.add_move(_load_move(33))
	var bm := _make_battle_manager_paused_singles(mon, opp)

	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs.is_overworld_battle = true
	var overlay := _make_item_overlay(bs)
	add_child(overlay)

	var start_index: int = bs._cursor_index
	bs._unhandled_input(_key_event(KEY_RIGHT))
	_chk("the shared cursor's own index is untouched by Right (columns=1 no-op)",
			bs._cursor_index == start_index)

	bm.queue_free()
	overlay.queue_free()
	bs.free()


# ── E. TARGET_SELECT -- keyboard cycling among health-box candidates ─────

func _test_target_select_defaults_to_first_candidate() -> void:
	var attacker := _make_mon("Attacker")
	attacker.add_move(_load_move(33))  # Tackle -- ordinary foe-targeting
	var ally := _make_mon("Ally")
	ally.add_move(_load_move(33))
	var opp0 := _make_mon("Opp0")
	var opp1 := _make_mon("Opp1")
	var bm := _make_battle_manager_paused_doubles([attacker, ally], [opp0, opp1])

	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _doubles_party([attacker, ally])
	bs._opp_party = _doubles_party([opp0, opp1])
	bs._new_button_area = VBoxContainer.new()
	bs._opp_panels = [HealthGroupPanel.new(), HealthGroupPanel.new()]
	bs._ply_panels = [HealthGroupPanel.new(), HealthGroupPanel.new()]
	bs._opp_sprites = [TextureRect.new(), TextureRect.new()]
	bs._ply_sprites = [TextureRect.new(), TextureRect.new()]
	# [_start_target_focus's own opponent-side idle-bob branch needs these]
	bs._opp_sprite_base_top = [0.0, 0.0]
	bs._opp_sprite_base_bottom = [0.0, 0.0]

	bs._build_target_select_buttons(0, 0)

	_chk("TARGET_SELECT defaults its keyboard cursor to the first candidate",
			bs._target_select_cursor == 0 and bs._target_select_candidates.size() == 2)
	_chk("...and that candidate is genuinely focused, matching every other menu's "
			+ "own default-selection-on-open convention",
			bs._target_focus_mon == bs._target_select_candidates[0])
	bm.queue_free()
	bs.free()


func _test_target_select_keyboard_cycles_and_wraps() -> void:
	var attacker := _make_mon("Attacker2")
	attacker.add_move(_load_move(33))
	var ally := _make_mon("Ally2")
	ally.add_move(_load_move(33))
	var opp0 := _make_mon("Opp0b")
	var opp1 := _make_mon("Opp1b")
	var bm := _make_battle_manager_paused_doubles([attacker, ally], [opp0, opp1])

	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _doubles_party([attacker, ally])
	bs._opp_party = _doubles_party([opp0, opp1])
	bs._menu = BattleScreenShared.Menu.TARGET_SELECT
	bs._new_button_area = VBoxContainer.new()
	bs._opp_panels = [HealthGroupPanel.new(), HealthGroupPanel.new()]
	bs._ply_panels = [HealthGroupPanel.new(), HealthGroupPanel.new()]
	bs._opp_sprites = [TextureRect.new(), TextureRect.new()]
	bs._ply_sprites = [TextureRect.new(), TextureRect.new()]
	# [_start_target_focus's own opponent-side idle-bob branch needs these]
	bs._opp_sprite_base_top = [0.0, 0.0]
	bs._opp_sprite_base_bottom = [0.0, 0.0]
	bs._build_target_select_buttons(0, 0)

	bs._unhandled_input(_key_event(KEY_DOWN))
	_chk("ui_down cycles TARGET_SELECT to the second candidate",
			bs._target_select_cursor == 1
			and bs._target_focus_mon == bs._target_select_candidates[1])

	bs._unhandled_input(_key_event(KEY_DOWN))
	_chk("cycling past the last candidate WRAPS back to the first "
			+ "(a small cyclic set, not a fixed-shape grid to clamp against)",
			bs._target_select_cursor == 0
			and bs._target_focus_mon == bs._target_select_candidates[0])
	bm.queue_free()
	bs.free()


func _test_target_select_confirm_is_a_no_op_with_no_candidates() -> void:
	var bs := BattleScreenShared.new()
	# Deliberately empty -- e.g. a stale/never-built state.
	bs._target_select_candidates = []
	bs._target_select_field_slot = -1
	# Would crash on a real index into an empty array if the guard were
	# missing; reaching the assertion below at all is the proof.
	bs._confirm_target_select_cursor()
	_chk("confirming TARGET_SELECT with no candidates is a safe no-op", true)
	bs.free()


# ── F. project.godot's own [input] section is real and effective ─────────

func _test_inputmap_has_real_ui_actions() -> void:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"]:
		_chk("InputMap declares a real '%s' action" % action, InputMap.has_action(action))


func _test_physical_keycode_event_matches_ui_action() -> void:
	_chk("a physical Up-arrow key event matches ui_up",
			_key_event(KEY_UP).is_action_pressed("ui_up"))
	_chk("a physical Down-arrow key event matches ui_down",
			_key_event(KEY_DOWN).is_action_pressed("ui_down"))
	_chk("a physical Enter key event matches ui_accept",
			_key_event(KEY_ENTER).is_action_pressed("ui_accept"))
	_chk("a physical Escape key event matches ui_cancel",
			_key_event(KEY_ESCAPE).is_action_pressed("ui_cancel"))
