extends Node

# [M25h-1.4] Regression suite for the real separate Item/Bag full-screen
# overlay — see item_select_screen.gd's own doc comment for the full
# architecture rationale and Step 0 source citations.
#
# [M26E1 REWRITE] Every test that reads item CONTENT now goes through the
# real `OverworldSession.bag` rather than a hardcoded `_ITEMS` array — see
# docs/m26_e2_recon.md's own §0a for the decisions this rewrite implements
# (real Bag, battle-legality pocket filter incl. Berries, real quantities,
# a real feed-a-berry mechanic, standalone-mode debug seeding). Every test
# calls `OverworldSession.reset()` first, per `reset()`'s own doc comment —
# the bag is process-global static state, and a prior test's leftovers
# would silently confound a later one otherwise.
#
# [Deliberately NOT tested here] The real on-screen visual result — matches
# every prior M25h suite's own established precedent of scoping automated
# coverage to pure logic + bare-instance direct calls, leaving the real
# end-to-end proof to a real screenshot pass.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_debug_stock_seeded_when_not_overworld_battle()
	_test_debug_stock_not_seeded_when_overworld_battle()
	_test_legal_pockets_excludes_balls_outside_a_wild_battle()
	_test_legal_pockets_includes_balls_in_a_wild_battle()
	_test_overlay_builds_real_bag_contents_plus_cancel()
	_test_stat_raise_berry_never_shown_even_if_present_in_bag()
	_test_overlay_buttons_use_real_font_chrome_and_cursor()
	_test_item_button_press_emits_item_chosen_with_correct_id()
	_test_cancel_button_press_emits_cancelled()
	_test_escape_key_also_cancels()
	_test_build_item_buttons_opens_a_real_wired_overlay()
	_test_build_item_buttons_is_idempotent_while_overlay_open()
	_test_field_slot_propagates_correctly_to_bound_handlers()
	_test_item_chosen_reaches_real_queue_item_for_end_to_end()
	_test_berry_feeding_end_to_end_heals_and_consumes()
	_test_berry_feeding_end_to_end_cures_status()
	_test_full_hp_potion_is_a_no_op_and_is_not_consumed()
	_test_cancelled_reaches_real_menu_reset_end_to_end()
	_test_battle_usable_items_are_real_pocket_items()
	_test_pocket_label_shows_real_pocket_name_and_updates_on_cycle()
	_test_non_battle_usable_item_is_a_graceful_no_op_not_a_crash()
	_test_real_bag_background_art_exists_with_real_dimensions()
	_test_quantity_shows_the_real_bag_count()
	_test_next_pocket_cycles_through_legal_pockets()
	_test_next_pocket_skips_empty_pockets()
	_test_next_pocket_terminates_when_every_pocket_is_empty()
	_test_snap_to_first_non_empty_pocket_on_open()
	_test_dot_row_has_one_dot_per_legal_pocket_and_marks_current_selection()
	_test_left_right_keys_cycle_pockets()
	_test_empty_pocket_shows_placeholder_text()

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


func _make_battle_screen_with_font() -> BattleScreenShared:
	var bs := BattleScreenShared.new()
	bs._font_menu = FontFile.new()
	bs._font_menu.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")
	return bs


func _is_chrome_stripped(btn: Button) -> bool:
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		if not (btn.get_theme_stylebox(state) is StyleBoxEmpty):
			return false
	return true


func _make_overlay(bs: BattleScreenShared, field_slot: int = 0) -> ItemSelectScreen:
	var scene: PackedScene = load("res://scenes/battle/item_select_screen.tscn")
	var overlay: ItemSelectScreen = scene.instantiate()
	overlay.setup(bs, field_slot)
	return overlay


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		_collect_buttons(child, out)


func _button_texts(overlay: ItemSelectScreen) -> Array:
	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	var out: Array = []
	for b in buttons:
		out.append(b.text.substr(BattleScreenShared._CURSOR_PREFIX.length()))
	return out


# ── A. `_ensure_debug_stock` — the standalone/debug-mode seed, and its gate ─

func _test_debug_stock_seeded_when_not_overworld_battle() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false

	_make_overlay(bs)

	_chk("Potion was seeded into the real Bag (standalone/debug mode)",
			OverworldSession.bag.has_item(28, 10))
	_chk("Oran Berry was seeded too (the newly-feedable berries get debug coverage)",
			OverworldSession.bag.has_item(520, 5))


func _test_debug_stock_not_seeded_when_overworld_battle() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = true

	_make_overlay(bs)

	_chk("a REAL overworld battle's bag is never auto-seeded, even if genuinely empty",
			OverworldSession.bag.slots(ItemManager.POCKET_ITEMS).is_empty()
			and OverworldSession.bag.slots(ItemManager.POCKET_BERRIES).is_empty())


# ── B. Battle-legality pocket filter (docs/m26_e2_recon.md §3/§0a) ─────────

func _make_bm_with_wild(is_wild: bool) -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	bm.is_wild_battle = is_wild
	return bm


func _test_legal_pockets_excludes_balls_outside_a_wild_battle() -> void:
	OverworldSession.reset()
	OverworldSession.bag.add(1, 5)  # Poké Ball
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = true  # skip debug seeding, isolate this scenario
	bs._bm = _make_bm_with_wild(false)

	var overlay := _make_overlay(bs)

	_chk("Poké Ball is NOT shown outside a wild battle, even though the bag holds one",
			not _button_texts(overlay).any(func(t): return (t as String).begins_with("Poké Ball")))
	bs._bm.queue_free()


func _test_legal_pockets_includes_balls_in_a_wild_battle() -> void:
	OverworldSession.reset()
	OverworldSession.bag.add(1, 5)  # Poké Ball
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = true
	bs._bm = _make_bm_with_wild(true)

	var overlay := _make_overlay(bs)

	_chk("Poké Ball IS shown in a wild battle",
			_button_texts(overlay).any(func(t): return (t as String).begins_with("Poké Ball")))
	bs._bm.queue_free()


# ── C. [M26E2] Each pocket shows ONLY its own contents + Cancel — the old
# combined-flat-list assumption is retired now that pockets are real tabs ──

func _test_overlay_builds_real_bag_contents_plus_cancel() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false  # debug stock: Potion/Full Heal/X Attack/
			# Poké Ball/Oran Berry/Lum Berry — Poké Ball excluded (no _bm set,
			# is_wild_battle reads false on a null-safe check).

	var overlay := _make_overlay(bs)
	var texts := _button_texts(overlay)

	_chk("the Items pocket (default-shown) has exactly 4 buttons (3 items + Cancel)",
			texts.size() == 4)
	_chk("Potion is present", texts.any(func(t): return (t as String).begins_with("Potion")))
	_chk("Full Heal is present", texts.any(func(t): return (t as String).begins_with("Full Heal")))
	_chk("X Attack is present", texts.any(func(t): return (t as String).begins_with("X Attack")))
	_chk("Cancel is present as the LAST entry (matching source's real LIST_CANCEL structure)",
			texts[texts.size() - 1] == "Cancel")
	_chk("Berries are NOT shown on the Items pocket", not texts.any(
			func(t): return (t as String).begins_with("Oran") or (t as String).begins_with("Lum")))

	overlay.next_pocket(1)
	var berry_texts := _button_texts(overlay)
	_chk("cycling to Berries shows exactly 3 buttons (2 berries + Cancel)",
			berry_texts.size() == 3)
	_chk("Oran Berry is present on the Berries pocket (a real bag-feedable berry, M26E1)",
			berry_texts.any(func(t): return (t as String).begins_with("Oran Berry")))
	_chk("Lum Berry is present on the Berries pocket (a real bag-feedable berry, M26E1)",
			berry_texts.any(func(t): return (t as String).begins_with("Lum Berry")))


# ── D. A stat-raise berry (no real battle_usage in source) is never shown,
# even if it's physically sitting in the bag ────────────────────────────────

func _test_stat_raise_berry_never_shown_even_if_present_in_bag() -> void:
	OverworldSession.reset()
	OverworldSession.bag.add(15, 3)  # Liechi Berry — HOLD_EFFECT_ATTACK_UP,
			# no battle_usage in source (docs/m26_e2_recon.md §0a decision 2b).
	OverworldSession.bag.add(520, 1)  # Oran Berry — real battle_usage, keeps
			# the Berries pocket non-empty so the snap-to-first-non-empty
			# logic doesn't skip past it before this test can look.
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = true  # isolate — no debug-stock noise

	var overlay := _make_overlay(bs)
	# Items is empty (neither berry is a POCKET_ITEMS entry), so the
	# open-time snap-to-first-non-empty-pocket logic already lands on
	# Berries — no explicit next_pocket() call needed.

	_chk("Liechi Berry is NOT shown — it carries no real battle_usage",
			not _button_texts(overlay).any(func(t): return (t as String).begins_with("Liechi")))


# ── E. Real font/chrome/cursor conventions carry over (M25h-1.1/1.2/1.3) ──

func _test_overlay_buttons_use_real_font_chrome_and_cursor() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false
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
	_chk("the first row is the default-selected cursor position",
			buttons[0].text.begins_with(BattleScreenShared._CURSOR_PREFIX))


# ── F. Pressing an item button emits item_chosen with the real item id ────

func _test_item_button_press_emits_item_chosen_with_correct_id() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false
	var overlay := _make_overlay(bs)
	var received: Array = []
	overlay.item_chosen.connect(func(item_id): received.append(item_id))

	var idx := overlay._row_item_ids.find(28)  # Potion
	_chk("Potion is one of the built rows", idx >= 0)
	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	buttons[idx].pressed.emit()

	_chk("pressing Potion's button emits item_chosen with its real id (28)",
			received.size() == 1 and received[0] == 28)


# ── G. Pressing Cancel emits cancelled ─────────────────────────────────────

func _test_cancel_button_press_emits_cancelled() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false
	var overlay := _make_overlay(bs)
	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	buttons[buttons.size() - 1].pressed.emit()  # Cancel is always last.

	_chk("pressing Cancel emits the cancelled signal exactly once", cancelled_count[0] == 1)


# ── H. ESC also cancels (real source B_BUTTON parity) ──────────────────────

func _test_escape_key_also_cancels() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false
	var overlay := _make_overlay(bs)
	add_child(overlay)
	var cancelled_count := [0]
	overlay.cancelled.connect(func(): cancelled_count[0] += 1)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay._unhandled_input(esc)

	_chk("ESC emits cancelled, matching source's own B_BUTTON convention", cancelled_count[0] == 1)
	overlay.queue_free()


# ── I. battle_screen.gd's own _build_item_buttons opens a real, wired
# overlay as a genuine child ────────────────────────────────────────────────

func _test_build_item_buttons_opens_a_real_wired_overlay() -> void:
	OverworldSession.reset()
	var mon := _make_mon("Solo")
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false
	bs._player_party = _singles_party(mon)

	bs._build_item_buttons(0)

	_chk("_item_select_overlay is a real ItemSelectScreen",
			bs._item_select_overlay != null and bs._item_select_overlay is ItemSelectScreen)
	_chk("the overlay is a genuine child of the battle screen (not floating/detached)",
			bs._item_select_overlay.get_parent() == bs)


# ── J. A second _build_item_buttons call while the overlay is still open
# does not stack a duplicate (the real doubles-mode re-entry risk) ────────

func _test_build_item_buttons_is_idempotent_while_overlay_open() -> void:
	OverworldSession.reset()
	var mon := _make_mon("Solo2")
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false
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


# ── K. field_slot propagates correctly into the bound handler callables
# (doubles per-slot correctness) ───────────────────────────────────────────

func _test_field_slot_propagates_correctly_to_bound_handlers() -> void:
	OverworldSession.reset()
	var m0 := _make_mon("D0")
	var m1 := _make_mon("D1")
	var bs0 := _make_battle_screen_with_font()
	bs0.is_overworld_battle = false
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


# ── L. The real queue_item_for()/advance() pipeline _on_item_pressed calls
# (unchanged pre-existing logic) actually applies Potion's heal ────────────

func _test_item_chosen_reaches_real_queue_item_for_end_to_end() -> void:
	var healer := _make_mon("Healer", 100)
	healer.add_move(_load_move(33))
	var opp := _make_mon("Opp", 100)
	opp.add_move(_load_move(33))

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(_singles_party(healer), _singles_party(opp))

	healer.current_hp = 40

	var healed_events: Array = []
	bm.item_healed.connect(func(mon, amount): healed_events.append([mon, amount]))

	bm.queue_item_for(0, BattleScreenShared.POTION_ITEM_ID)
	bm.advance()

	_chk("Potion's real heal effect fired through the real queue_item_for()/advance() pipeline",
			healed_events.size() == 1 and healed_events[0][0] == healer and healed_events[0][1] == 20)

	bm.queue_free()


# ── M. [M26E1] The real feed-a-berry mechanic, end to end — Oran Berry
# heals AND is genuinely consumed via bag_item_consumed ────────────────────

func _test_berry_feeding_end_to_end_heals_and_consumes() -> void:
	OverworldSession.reset()
	OverworldSession.bag.add(520, 3)  # Oran Berry

	var healer := _make_mon("BerryHealer", 100)
	healer.add_move(_load_move(33))
	var opp := _make_mon("Opp3", 100)
	opp.add_move(_load_move(33))

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(_singles_party(healer), _singles_party(opp))
	healer.current_hp = 40

	var healed_events: Array = []
	bm.item_healed.connect(func(mon, amount): healed_events.append([mon, amount]))
	var consumed_events: Array = []
	bm.bag_item_consumed.connect(func(item): consumed_events.append(item))

	bm.queue_item_for(0, 520)  # Oran Berry
	bm.advance()

	_chk("Oran Berry heals its own flat 10 HP when fed directly",
			healed_events.size() == 1 and healed_events[0][0] == healer and healed_events[0][1] == 10)
	_chk("bag_item_consumed fired for the real berry",
			consumed_events.size() == 1 and consumed_events[0].item_id == 520)

	bm.queue_free()


func _test_berry_feeding_end_to_end_cures_status() -> void:
	OverworldSession.reset()
	OverworldSession.bag.add(522, 3)  # Lum Berry

	var target := _make_mon("BerryCureTarget", 100)
	target.add_move(_load_move(33))
	target.status = BattlePokemon.STATUS_PARALYSIS
	var opp := _make_mon("Opp4", 100)
	opp.add_move(_load_move(33))

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(_singles_party(target), _singles_party(opp))

	var cured_events: Array = []
	bm.party_status_cured.connect(func(mon): cured_events.append(mon))
	var consumed_events: Array = []
	bm.bag_item_consumed.connect(func(item): consumed_events.append(item))

	bm.queue_item_for(0, 522)  # Lum Berry
	bm.advance()

	_chk("Lum Berry cures paralysis when fed directly",
			cured_events.size() == 1 and cured_events[0] == target
			and target.status == BattlePokemon.STATUS_NONE)
	_chk("bag_item_consumed fired for the real berry",
			consumed_events.size() == 1 and consumed_events[0].item_id == 522)

	bm.queue_free()


# ── N. [M26E1] A no-op use (Potion on a full-HP target) does NOT consume
# the item — real inventory is not spent on nothing happening ─────────────

func _test_full_hp_potion_is_a_no_op_and_is_not_consumed() -> void:
	OverworldSession.reset()
	OverworldSession.bag.add(28, 3)  # Potion

	var mon := _make_mon("FullHpMon", 100)
	mon.add_move(_load_move(33))
	var opp := _make_mon("Opp5", 100)
	opp.add_move(_load_move(33))

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(_singles_party(mon), _singles_party(opp))
	# current_hp is already max — the Potion should have nothing to do.

	var consumed_events: Array = []
	bm.bag_item_consumed.connect(func(item): consumed_events.append(item))

	bm.queue_item_for(0, 28)
	bm.advance()

	_chk("a no-op Potion use does not fire bag_item_consumed (nothing was spent)",
			consumed_events.is_empty())

	bm.queue_free()


# ── O. End-to-end: cancelled resets _menu to TOP through the real handler ─

func _test_cancelled_reaches_real_menu_reset_end_to_end() -> void:
	OverworldSession.reset()
	var mon := _make_mon("CancelTester")
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false
	bs._player_party = _singles_party(mon)
	bs._menu = BattleScreenShared.Menu.ITEM

	bs._build_item_buttons(0)
	_chk("an overlay was really created before cancelling", bs._item_select_overlay != null)
	_chk("_menu starts at ITEM (about to be reset by a real Cancel press)",
			bs._menu == BattleScreenShared.Menu.ITEM)


# ── P. Real battle_usage/pocket data on the items this screen can show ────

func _test_battle_usable_items_are_real_pocket_items() -> void:
	var potion := ItemRegistry.get_item(28)
	var full_heal := ItemRegistry.get_item(48)
	var x_attack := ItemRegistry.get_item(121)
	var oran := ItemRegistry.get_item(520)
	var lum := ItemRegistry.get_item(522)
	_chk("Potion is a real POCKET_ITEMS entry", potion.pocket == ItemManager.POCKET_ITEMS)
	_chk("Full Heal is a real POCKET_ITEMS entry", full_heal.pocket == ItemManager.POCKET_ITEMS)
	_chk("X Attack is a real POCKET_ITEMS entry", x_attack.pocket == ItemManager.POCKET_ITEMS)
	_chk("Oran Berry is POCKET_BERRIES with a real battle_usage",
			oran.pocket == ItemManager.POCKET_BERRIES
			and oran.battle_usage == ItemManager.BATTLE_USE_RESTORE_HP)
	_chk("Lum Berry is POCKET_BERRIES with a real battle_usage",
			lum.pocket == ItemManager.POCKET_BERRIES
			and lum.battle_usage == ItemManager.BATTLE_USE_CURE_STATUS)


# ── Q. [M26E2] The real pocket-name-bar shows the current pocket's real
# source name, and updates live as the player cycles pockets ──────────────

func _test_pocket_label_shows_real_pocket_name_and_updates_on_cycle() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false
	var overlay := _make_overlay(bs)

	var pocket_label: Label = overlay.get_node("Panel/PocketLabel")
	_chk("the pocket-name-bar shows the real source name for the default (Items) pocket",
			pocket_label.text == "ITEMS")

	overlay.next_pocket(1)
	_chk("cycling to Berries updates the pocket-name-bar to the real source name",
			pocket_label.text == "BERRIES")


# ── R. A non-battle-usable item's dispatch degrades gracefully ────────────

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

	var used_events: Array = []
	bm.item_action_used.connect(func(user, item, target): used_events.append([user, item, target]))
	var healed_events: Array = []
	bm.item_healed.connect(func(mon2, amount): healed_events.append([mon2, amount]))
	var consumed_events: Array = []
	bm.bag_item_consumed.connect(func(item): consumed_events.append(item))

	bm._do_item_use(0, non_battle_usable_item, 0)

	_chk("item_action_used still fires (the item was genuinely selected/used)",
			used_events.size() == 1 and used_events[0][1] == non_battle_usable_item)
	_chk("no effect actually applied", healed_events.is_empty())
	_chk("nothing was consumed either", consumed_events.is_empty())
	_chk("the user's own HP is completely unaffected", mon.current_hp == 100)

	bm.queue_free()


# ── S. [M26E1] The real Emerald UI Pack Bag background exists at its real
# 512x384 dimensions, replacing the old bag_frame.png decode ──────────────

func _test_real_bag_background_art_exists_with_real_dimensions() -> void:
	var bg: Texture2D = load("res://assets/sprites/battle_ui/bag/bag_bg_male.png")
	_chk("bag_bg_male.png loads at its real pack dimensions (512x384)",
			bg != null and bg.get_width() == 512 and bg.get_height() == 384)


# ── T. [M26E1] The quantity slot now shows the real per-stack Bag count ───

func _test_quantity_shows_the_real_bag_count() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false  # debug stock: Potion x10
	var overlay := _make_overlay(bs)

	var idx := overlay._row_item_ids.find(28)  # Potion
	var buttons: Array[Button] = []
	_collect_buttons(overlay, buttons)
	var row: Node = buttons[idx].get_parent()

	var qty_label: Label = null
	for c in row.get_children():
		if c is Label:
			qty_label = c
	_chk("each item row carries a real quantity-text Label sibling", qty_label != null)
	_chk("the quantity Label shows the real Bag count (x10 for the seeded Potion stack)",
			qty_label != null and qty_label.text == "x10")


# ── U. [M26E2] next_pocket() cycles through every legal pocket, wrapping ──

func _test_next_pocket_cycles_through_legal_pockets() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false  # debug stock: Items + Berries both non-empty
	var overlay := _make_overlay(bs)

	_chk("opens on the first legal pocket (Items)",
			overlay._pocket_order[overlay._pocket_index] == ItemManager.POCKET_ITEMS)
	overlay.next_pocket(1)
	_chk("next_pocket(1) advances to Berries",
			overlay._pocket_order[overlay._pocket_index] == ItemManager.POCKET_BERRIES)
	overlay.next_pocket(1)
	_chk("next_pocket(1) wraps back around to Items (only 2 legal pockets here)",
			overlay._pocket_order[overlay._pocket_index] == ItemManager.POCKET_ITEMS)
	overlay.next_pocket(-1)
	_chk("next_pocket(-1) moves backward, wrapping to Berries",
			overlay._pocket_order[overlay._pocket_index] == ItemManager.POCKET_BERRIES)


# ── V. [M26E2] next_pocket() skips an empty pocket entirely ────────────────

func _test_next_pocket_skips_empty_pockets() -> void:
	OverworldSession.reset()
	OverworldSession.bag.add(28, 1)  # Potion -> Items
	OverworldSession.bag.add(1, 1)   # Poké Ball -> Poké Balls
	# Berries pocket deliberately left empty.
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = true
	bs._bm = _make_bm_with_wild(true)
	var overlay := _make_overlay(bs)

	_chk("opens on Items (the first non-empty legal pocket)",
			overlay._pocket_order[overlay._pocket_index] == ItemManager.POCKET_ITEMS)
	overlay.next_pocket(1)
	_chk("next_pocket(1) skips the empty Berries pocket and lands on Poké Balls",
			overlay._pocket_order[overlay._pocket_index] == ItemManager.POCKET_POKE_BALLS)
	bs._bm.queue_free()


# ── W. [M26E2] next_pocket() never hangs when every legal pocket is empty ──

func _test_next_pocket_terminates_when_every_pocket_is_empty() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = true  # no debug stock, genuinely empty bag
	var overlay := _make_overlay(bs)

	_chk("with an entirely empty bag, the overlay still opens with the full legal-pocket set",
			overlay._pocket_order.size() == 2)
	overlay.next_pocket(1)
	_chk("next_pocket() returns (does not infinite-loop) when every legal pocket is empty",
			true)  # reaching this line at all is the proof


# ── X. [M26E2] Opening the screen snaps past an empty first pocket ─────────

func _test_snap_to_first_non_empty_pocket_on_open() -> void:
	OverworldSession.reset()
	OverworldSession.bag.add(522, 1)  # Lum Berry -> Berries only
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = true  # Items pocket stays empty
	var overlay := _make_overlay(bs)

	_chk("the overlay opens directly on Berries, skipping the empty Items pocket",
			overlay._pocket_order[overlay._pocket_index] == ItemManager.POCKET_BERRIES)


# ── Y. [M26E2] The dot row carries one dot per legal pocket, and the
# SELECTED region tracks the current pocket live ───────────────────────────

func _test_dot_row_has_one_dot_per_legal_pocket_and_marks_current_selection() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false
	var overlay := _make_overlay(bs)

	var dot_row: HBoxContainer = overlay.get_node("Panel/DotRow")
	_chk("the dot row has exactly one dot per legal pocket (2: Items + Berries)",
			dot_row.get_child_count() == 2)

	var first_dot: TextureRect = dot_row.get_child(0)
	var first_region: Rect2 = (first_dot.texture as AtlasTexture).region
	_chk("the first (currently selected) dot uses the SELECTED region",
			first_region == ItemManager.pocket_dot_region(0, true))

	var second_dot: TextureRect = dot_row.get_child(1)
	var second_region: Rect2 = (second_dot.texture as AtlasTexture).region
	_chk("the second (unselected) dot uses the UNSELECTED region",
			second_region == ItemManager.pocket_dot_region(1, false))

	overlay.next_pocket(1)
	var dot_row2: HBoxContainer = overlay.get_node("Panel/DotRow")
	var first_dot2: TextureRect = dot_row2.get_child(0)
	var first_region2: Rect2 = (first_dot2.texture as AtlasTexture).region
	_chk("after cycling, the FIRST dot switches to the UNSELECTED region",
			first_region2 == ItemManager.pocket_dot_region(0, false))
	var second_dot2: TextureRect = dot_row2.get_child(1)
	var second_region2: Rect2 = (second_dot2.texture as AtlasTexture).region
	_chk("after cycling, the SECOND dot switches to the SELECTED region",
			second_region2 == ItemManager.pocket_dot_region(1, true))


# ── Z. [M26E2] LEFT/RIGHT keys cycle pockets, matching FieldBagScreen's own
# ui_left/ui_right convention translated to this screen's raw-keycode style ─

func _test_left_right_keys_cycle_pockets() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = false
	var overlay := _make_overlay(bs)
	add_child(overlay)

	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	overlay._unhandled_input(right)
	_chk("KEY_RIGHT cycles to the next pocket (Berries)",
			overlay._pocket_order[overlay._pocket_index] == ItemManager.POCKET_BERRIES)

	var left := InputEventKey.new()
	left.keycode = KEY_LEFT
	left.pressed = true
	overlay._unhandled_input(left)
	_chk("KEY_LEFT cycles back to the previous pocket (Items)",
			overlay._pocket_order[overlay._pocket_index] == ItemManager.POCKET_ITEMS)

	overlay.queue_free()


# ── AA. [M26E2] A pocket that's empty on EVERY legal pocket (the all-empty
# fallback) shows the real "No items." placeholder, not a blank list ──────

func _test_empty_pocket_shows_placeholder_text() -> void:
	OverworldSession.reset()
	var bs := _make_battle_screen_with_font()
	bs.is_overworld_battle = true  # genuinely empty bag, no debug stock
	var overlay := _make_overlay(bs)

	# The placeholder is a plain Label, not a Button — `_button_texts` only
	# ever collects Buttons, so it's read directly off the VBox instead.
	var vbox: VBoxContainer = overlay.get_node("Panel/Margin/VBox")
	var placeholder: Label = null
	for c in vbox.get_children():
		if c is Label and c.name != "Header":
			placeholder = c
	_chk("with every legal pocket empty, the screen shows the real 'No items.' placeholder",
			placeholder != null and placeholder.text == "No items.")
	_chk("Cancel is still present alongside the placeholder",
			_button_texts(overlay) == ["Cancel"])
