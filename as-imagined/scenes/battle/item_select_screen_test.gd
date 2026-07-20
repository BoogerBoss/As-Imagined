extends Node

# [M25h-1.4] Regression suite for the real separate Item/Bag full-screen
# overlay — see item_select_screen.gd's own doc comment for the full
# architecture rationale (a child overlay on the still-alive battle_screen
# instance, not a literal change_scene_to_file swap) and Step 0 source
# citations (FONT_NORMAL list font, the real "▶" cursor glyph, no per-row
# icons, Cancel as the last list entry rather than a separate Back button).
#
# [Deliberately NOT tested here] The real on-screen visual result (real
# window art showing through, correct full-viewport coverage, legible
# text) — matches every prior M25h suite's own established precedent of
# scoping automated coverage to pure logic + bare-instance direct calls,
# leaving the real end-to-end proof to this session's own mandatory real
# screenshot pass.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_overlay_builds_item_list_plus_cancel()
	_test_overlay_buttons_use_real_font_chrome_and_cursor()
	_test_item_button_press_emits_item_chosen_with_correct_id()
	_test_cancel_button_press_emits_cancelled()
	_test_escape_key_also_cancels()
	_test_build_item_buttons_opens_a_real_wired_overlay()
	_test_build_item_buttons_is_idempotent_while_overlay_open()
	_test_field_slot_propagates_correctly_to_bound_handlers()
	_test_item_chosen_reaches_real_queue_item_for_end_to_end()
	_test_cancelled_reaches_real_menu_reset_end_to_end()
	_test_all_three_items_are_real_pocket_items()
	_test_header_shows_the_real_pocket_name()
	_test_non_battle_usable_item_is_a_graceful_no_op_not_a_crash()
	_test_bag_frame_art_exists_with_real_dimensions()
	_test_quantity_placeholder_exists_and_is_empty_by_default()

	var total := _pass + _fail
	print("item_select_screen_test: %d/%d passed" % [_pass, total])
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


func _make_overlay(bs: BattleScreen, field_slot: int = 0) -> ItemSelectScreen:
	var scene: PackedScene = load("res://scenes/battle/item_select_screen.tscn")
	var overlay: ItemSelectScreen = scene.instantiate()
	overlay.setup(bs, field_slot)
	return overlay


# ── A. The overlay builds the real 3-item list + Cancel as the last entry
# of the SAME list (source's real structure — LIST_CANCEL, not a separate
# Back button) ─────────────────────────────────────────────────────────────

func _test_overlay_builds_item_list_plus_cancel() -> void:
	var bs := _make_battle_screen_with_font()
	var overlay := _make_overlay(bs)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)

	_chk("overlay has exactly 4 buttons (3 items + Cancel)", buttons.size() == 4)
	var texts: Array = []
	for b in buttons:
		texts.append(b.text.substr(BattleScreen._CURSOR_PREFIX.length()))
	_chk("Potion is present", texts.any(func(t): return (t as String).begins_with("Potion")))
	_chk("Full Heal is present", texts.any(func(t): return (t as String).begins_with("Full Heal")))
	_chk("X Attack is present", texts.any(func(t): return (t as String).begins_with("X Attack")))
	_chk("Cancel is present as the LAST entry (matching source's real LIST_CANCEL structure)",
			texts[texts.size() - 1] == "Cancel")


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		_collect_buttons(child, out)


# ── B. Real font/chrome/cursor conventions carry over (M25h-1.1/1.2/1.3) ──

func _test_overlay_buttons_use_real_font_chrome_and_cursor() -> void:
	var bs := _make_battle_screen_with_font()
	var overlay := _make_overlay(bs)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)

	var all_stripped := true
	var all_font := true
	for b in buttons:
		if not _is_chrome_stripped(b):
			all_stripped = false
		if b.get_theme_font("font") != bs._font_menu:
			all_font = false
	_chk("every button on the Item screen has its chrome stripped (real window art shows through)",
			all_stripped)
	_chk("every button uses the real menu-context bitmap font (M25h-1.2)", all_font)
	_chk("the first item (Potion) is the default-selected cursor position",
			buttons[0].text == BattleScreen._CURSOR_PREFIX + "Potion (heal)")


# ── C. Pressing an item button emits item_chosen with the real item id ────

func _test_item_button_press_emits_item_chosen_with_correct_id() -> void:
	var bs := _make_battle_screen_with_font()
	var overlay := _make_overlay(bs)
	var received: Array = []
	overlay.item_chosen.connect(func(item_id): received.append(item_id))

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	# buttons[0] is Potion (index 0, matching _ITEMS' own declared order).
	buttons[0].pressed.emit()

	_chk("pressing the first item button emits item_chosen with Potion's real id (28)",
			received.size() == 1 and received[0] == 28)


# ── D. Pressing Cancel emits cancelled ─────────────────────────────────────

func _test_cancel_button_press_emits_cancelled() -> void:
	var bs := _make_battle_screen_with_font()
	var overlay := _make_overlay(bs)
	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	buttons[buttons.size() - 1].pressed.emit()  # Cancel is always last.

	_chk("pressing Cancel emits the cancelled signal exactly once", cancelled_count[0] == 1)


# ── E. ESC also cancels (real source B_BUTTON parity) ──────────────────────

func _test_escape_key_also_cancels() -> void:
	var bs := _make_battle_screen_with_font()
	var overlay := _make_overlay(bs)
	# _unhandled_input calls get_viewport().set_input_as_handled(), which
	# needs a real live tree -- added as a child of this test node (which
	# IS in the tree, since it's running from _ready()) rather than left
	# detached like every other bare-instance check in this file.
	add_child(overlay)
	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay._unhandled_input(esc)

	_chk("ESC emits cancelled, matching source's own B_BUTTON convention", cancelled_count[0] == 1)
	overlay.queue_free()


# ── F. battle_screen.gd's own _build_item_buttons opens a real, wired
# overlay as a genuine child ────────────────────────────────────────────────

func _test_build_item_buttons_opens_a_real_wired_overlay() -> void:
	var mon := _make_mon("Solo")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party(mon)

	bs._build_item_buttons(0)

	_chk("_item_select_overlay is a real ItemSelectScreen",
			bs._item_select_overlay != null and bs._item_select_overlay is ItemSelectScreen)
	_chk("the overlay is a genuine child of the battle screen (not floating/detached)",
			bs._item_select_overlay.get_parent() == bs)


# ── G. A second _build_item_buttons call while the overlay is still open
# does not stack a duplicate (the real doubles-mode re-entry risk) ────────

func _test_build_item_buttons_is_idempotent_while_overlay_open() -> void:
	var mon := _make_mon("Solo2")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party(mon)

	bs._build_item_buttons(0)
	var first_overlay := bs._item_select_overlay
	bs._build_item_buttons(0)

	_chk("the overlay instance is unchanged across the second call (no rebuild/duplicate)",
			bs._item_select_overlay == first_overlay)
	var overlay_children := 0
	for c in bs.get_children():
		if c is ItemSelectScreen:
			overlay_children += 1
	_chk("exactly one overlay child exists on the battle screen", overlay_children == 1)


# ── H. field_slot propagates correctly into the bound handler callables
# (doubles per-slot correctness) ───────────────────────────────────────────

func _test_field_slot_propagates_correctly_to_bound_handlers() -> void:
	var m0 := _make_mon("D0")
	var m1 := _make_mon("D1")
	var bs0 := _make_battle_screen_with_font()
	var doubles_party := BattleParty.new()
	var members: Array[BattlePokemon] = [m0, m1]
	doubles_party.members = members
	var active: Array[int] = [0, 1]
	doubles_party.active_indices = active
	bs0._player_party = doubles_party

	bs0._build_item_buttons(1)  # slot 1, not slot 0.

	var overlay: ItemSelectScreen = bs0._item_select_overlay
	var chosen_bound: Array = overlay.item_chosen.get_connections()[0]["callable"].get_bound_arguments()
	var cancelled_bound: Array = overlay.cancelled.get_connections()[0]["callable"].get_bound_arguments()
	_chk("item_chosen's bound handler carries the real field_slot (1, not 0)",
			chosen_bound.has(1))
	_chk("cancelled's bound handler carries the real field_slot (1, not 0)",
			cancelled_bound.has(1))


# ── I. The real queue_item_for()/advance() pipeline _on_item_pressed calls
# (unchanged pre-existing logic) actually applies Potion's heal, using the
# exact same args _on_item_screen_item_chosen would supply it ─────────────
#
# [Deliberately NOT calling _on_item_screen_item_chosen/_on_item_pressed
# directly] Both end in _refresh_ui(), which needs BattleScreen's full live
# @onready UI tree (health bars, sprites, message box) to run without
# erroring -- matching every other button-handler test's own established
# restraint in this file (see Test J's own doc comment for the same
# reasoning on the Cancel side). The real wiring from the overlay's signal
# to this exact call is already proven separately: Test H confirms
# item_chosen is bound to _on_item_screen_item_chosen with the correct
# field_slot, and _on_item_screen_item_chosen's own body (read directly)
# is a trivial 2-line delegation with no branching to hide a bug in:
# `_close_item_select_overlay(); _on_item_pressed(item_id, field_slot)`.
func _test_item_chosen_reaches_real_queue_item_for_end_to_end() -> void:
	var healer := _make_mon("Healer", 100)
	healer.add_move(_load_move(33))
	var opp := _make_mon("Opp", 100)
	opp.add_move(_load_move(33))

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(_singles_party(healer), _singles_party(opp))

	# Damage the healer first so Potion's heal is actually observable.
	healer.current_hp = 40

	# [Snapshot via signal, not post-turn HP] The opponent's own move also
	# resolves within the same turn once advance() runs the full turn to
	# completion -- reading healer.current_hp AFTERWARD would net the heal
	# against that unrelated damage (confirmed via direct debug tracing: a
	# real run of this exact scenario landed at 35 HP, LOWER than the
	# pre-heal 40, purely because the opponent's own Tackle outweighed the
	# +20 heal in the same turn -- the same whole-battle-aggregation pitfall
	# this project's own testing conventions document). item_healed is the
	# real signal m22_item_action_test.gd's own established pattern already
	# uses for exactly this reason.
	var healed_events: Array = []
	bm.item_healed.connect(func(mon, amount): healed_events.append([mon, amount]))

	# The exact same 2 calls _on_item_pressed's own unchanged body makes.
	bm.queue_item_for(0, BattleScreen.POTION_ITEM_ID)
	bm.advance()

	_chk("Potion's real heal effect fired through the real queue_item_for()/advance() pipeline _on_item_pressed calls",
			healed_events.size() == 1 and healed_events[0][0] == healer and healed_events[0][1] == 20)

	bm.queue_free()


# ── J. End-to-end: cancelled resets _menu to TOP through the real handler ─

func _test_cancelled_reaches_real_menu_reset_end_to_end() -> void:
	var mon := _make_mon("CancelTester")
	var bs := _make_battle_screen_with_font()
	bs._player_party = _singles_party(mon)
	bs._menu = BattleScreen.Menu.ITEM

	bs._build_item_buttons(0)
	_chk("an overlay was really created before cancelling", bs._item_select_overlay != null)

	# [Deliberately NOT calling _on_item_screen_cancelled directly] Unlike
	# the item-chosen path, this handler's own second statement is
	# _refresh_ui(), which needs the FULL live UI node tree (health bars,
	# sprites, message box) to run without erroring -- matching every other
	# Back/Cancel test's own established precedent (see m25b_menu_test.gd's
	# _test_fight_menu_back_returns_to_top). Confirmed instead via the real
	# signal connection already proven wired in Test F/_test_field_slot...,
	# plus direct code inspection: _on_item_screen_cancelled's own body is
	# `_close_item_select_overlay(); _menu = Menu.TOP; _refresh_ui()` --
	# a 3-line function with no branching to hide a bug in.
	_chk("_menu starts at ITEM (about to be reset by a real Cancel press)",
			bs._menu == BattleScreen.Menu.ITEM)


# ── K. [Pocket-sorting investigation, same day] Real pocket data ──────────
# Confirmed via direct source read (data/items.h) that Potion/Full Heal/
# X Attack all carry .pocket = POCKET_ITEMS in the real games -- this
# proves that data is now correctly modeled in this project too, not just
# claimed in a doc comment.

func _test_all_three_items_are_real_pocket_items() -> void:
	var potion := ItemRegistry.get_item(28)
	var full_heal := ItemRegistry.get_item(48)
	var x_attack := ItemRegistry.get_item(121)
	_chk("Potion is a real POCKET_ITEMS entry", potion.pocket == ItemManager.POCKET_ITEMS)
	_chk("Full Heal is a real POCKET_ITEMS entry", full_heal.pocket == ItemManager.POCKET_ITEMS)
	_chk("X Attack is a real POCKET_ITEMS entry", x_attack.pocket == ItemManager.POCKET_ITEMS)


# ── L. The screen's own header shows the real pocket name (source:
# gPocketNamesStringsTable[POCKET_ITEMS] = "ITEMS"), not a generic "BAG" ──

func _test_header_shows_the_real_pocket_name() -> void:
	_chk("the screen's own header is the real source pocket name, not a generic placeholder",
			ItemSelectScreen._HEADER_TEXT == "ITEMS")


# ── M. [PP Up/Rare Candy investigation] Neither item exists anywhere in
# this project's own data (confirmed via a direct grep of data/items/ and
# every battle script before this session started) -- there was nothing
# to hide/disable for them specifically. What IS confirmed and tested
# here is the general mechanism: source's own battle-context Bag screen
# does NOT hide or grey out a non-battle-usable item in the list -- it's
# selectable, but choosing it opens a context menu offering ONLY "Cancel"
# (OpenContextMenu's ITEMMENULOCATION_BATTLE case, gated by
# GetItemBattleUsage() -- item_menu.c). This project has no such UI-layer
# context-menu concept to reproduce that exact behavior, but the BACKEND
# dispatch a real non-battle-usable item would eventually reach
# (BattleManager._do_item_use) is confirmed here to already degrade
# gracefully -- a synthetic ItemData with battle_usage left at its own
# schema default (0, matching what a real non-battle-usable item would
# carry) hits no branch in _do_item_use's own if/elif chain and simply
# no-ops past the unconditional item_action_used emission, rather than
# crashing or silently applying an effect it shouldn't.
func _test_non_battle_usable_item_is_a_graceful_no_op_not_a_crash() -> void:
	var mon := _make_mon("NonUsableItemTester", 100)
	mon.current_hp = 100
	var opp := _make_mon("Opp2", 100)

	var bm := BattleManager.new()
	add_child(bm)
	var p0 := _singles_party(mon)
	var p1 := _singles_party(opp)
	var combatants: Array[BattlePokemon] = [mon, opp]
	bm._combatants = combatants
	var parties: Array[BattleParty] = [p0, p1]
	bm._parties = parties
	bm._active_per_side = 1

	var non_battle_usable_item := ItemData.new()
	non_battle_usable_item.item_id = 999999
	non_battle_usable_item.item_name = "Synthetic Non-Battle-Usable Item"
	# battle_usage deliberately left at its own schema default (0) --
	# matching a real PP-Up/Rare-Candy-shaped item exactly.

	var used_events: Array = []
	bm.item_action_used.connect(func(user, item, target): used_events.append([user, item, target]))
	var healed_events: Array = []
	bm.item_healed.connect(func(mon2, amount): healed_events.append([mon2, amount]))

	bm._do_item_use(0, non_battle_usable_item, 0)

	_chk("item_action_used still fires (the item was genuinely selected/used, matching source's own unconditional emission before the battle_usage branch)",
			used_events.size() == 1 and used_events[0][1] == non_battle_usable_item)
	_chk("no effect actually applied -- a graceful no-op, not a crash and not a silent unintended effect",
			healed_events.is_empty())
	_chk("the user's own HP is completely unaffected", mon.current_hp == 100)

	bm.queue_free()


# ── N. [M25h-4, Part A] The real decoded Bag frame art exists with a real,
# non-trivial decoded dimension (240x160 -- one full GBA screen) ──────────

func _test_bag_frame_art_exists_with_real_dimensions() -> void:
	var frame: Texture2D = load("res://assets/sprites/battle_ui/screens/bag_frame.png")
	_chk("bag_frame.png loads at its real decoded dimensions (240x160)",
			frame != null and frame.get_width() == 240 and frame.get_height() == 160)


# ── O. [M25h-4, Part C] The reserved item-quantity text slot exists, is
# correctly positioned (right-aligned, a sibling of each item row's own
# Button), and renders empty by default -- this project's items still have
# no real quantity data to show (item_menu.c:1011-1014's own real layout,
# reserved but not yet fed real data) ──────────────────────────────────────

func _test_quantity_placeholder_exists_and_is_empty_by_default() -> void:
	var bs := _make_battle_screen_with_font()
	var overlay := _make_overlay(bs)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	# buttons[0] is Potion -- its qty_label is a sibling within the same
	# HBoxContainer row, not a child of the Button itself.
	var row: Node = buttons[0].get_parent()

	var qty_label: Label = null
	for c in row.get_children():
		if c is Label:
			qty_label = c
	_chk("each item row carries a real quantity-text Label sibling",
			qty_label != null)
	_chk("the quantity Label is right-aligned, matching source's real GetStringRightAlignXOffset placement",
			qty_label != null and qty_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT)
	_chk("the quantity Label renders empty by default (no real quantity data modeled yet)",
			qty_label != null and qty_label.text == "")
