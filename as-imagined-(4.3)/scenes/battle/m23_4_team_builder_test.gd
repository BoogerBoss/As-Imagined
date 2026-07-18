extends Node

# [M23.4] Team builder core — automated headless test suite, matching this
# project's own established `[headless-testable subset]` precedent
# (m23_0a_proof_test.gd/battle_screen_autoplay). Covers the data-layer
# legality logic (MoveNameMap, MovepoolResolver) directly, plus a real
# button-press-driven walkthrough of the actual scenes/team_builder/
# team_builder_screen.tscn scene — instantiated for real and driven via
# `.pressed.emit()`/setting real widget values, the same pattern M23.1's own
# manual-verification driver used, not a re-implementation of the screen's
# logic in test code.
#
# Section 3/4's own "does this match" assertion deliberately does NOT
# re-derive the HP/stat formula by hand (already covered by
# m23_3_converter_test.gd's own Section 2 and stat_test.gd) — it instead
# builds the SAME dex/level/nature/ivs/evs/moves/ability directly via
# PokemonFactory.create_battle_pokemon (bypassing the UI) and confirms the
# UI-driven result is field-for-field identical. That's the real risk
# surface this milestone adds on top of an already-tested factory: correct
# UI→factory parameter wiring, not formula correctness.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_move_name_map()
	_test_section_2_movepool_resolver()
	_test_section_3_ui_driven_build_bulbasaur()
	_test_section_4_ui_driven_build_charizard()
	_test_section_5_illegal_state_blocking()

	var total := _pass + _fail
	print("m23_4_team_builder_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


# ── Section 1: MoveNameMap ───────────────────────────────────────────────

func _test_section_1_move_name_map() -> void:
	_chk("S1.01 MOVE_TACKLE resolves to 33", MoveNameMap.id_for_name("MOVE_TACKLE") == 33)
	_chk("S1.02 MOVE_GROWL resolves to 45", MoveNameMap.id_for_name("MOVE_GROWL") == 45)
	_chk("S1.03 MOVE_VINE_WHIP resolves to 22", MoveNameMap.id_for_name("MOVE_VINE_WHIP") == 22)
	_chk("S1.04 alias MOVE_DOUBLESLAP resolves to the same ID as MOVE_DOUBLE_SLAP",
			MoveNameMap.id_for_name("MOVE_DOUBLESLAP") == MoveNameMap.id_for_name("MOVE_DOUBLE_SLAP")
			and MoveNameMap.id_for_name("MOVE_DOUBLE_SLAP") == 3)
	_chk("S1.05 unknown name resolves to -1", MoveNameMap.id_for_name("MOVE_TOTALLY_NOT_REAL") == -1)


# ── Section 2: MovepoolResolver ──────────────────────────────────────────
# Bulbasaur's real level-up learnset (data/learnsets.json): Tackle@1,
# Growl@4, Leech Seed@7, Vine Whip@10, Poison Powder@15, Sleep Powder@15,
# Razor Leaf@20, Sweet Scent@25, Growth@32, Synthesis@39, Solar Beam@46.

func _test_section_2_movepool_resolver() -> void:
	_chk("S2.01 unknown dex returns empty pool", MovepoolResolver.legal_move_ids(99999, 50).is_empty())

	var lvl1 := MovepoolResolver.legal_move_ids(1, 1)
	_chk("S2.02 Bulbasaur at level 1 knows Tackle (33)", 33 in lvl1)
	_chk("S2.03 Bulbasaur at level 1 does NOT yet know Growl (45, learned at 4)", not (45 in lvl1))
	_chk("S2.04 Bulbasaur at level 1 does NOT yet know Solar Beam (76, learned at 46)", not (76 in lvl1))

	var lvl10 := MovepoolResolver.legal_move_ids(1, 10)
	_chk("S2.05 Bulbasaur at level 10 knows Tackle/Growl/Leech Seed/Vine Whip",
			33 in lvl10 and 45 in lvl10 and 73 in lvl10 and 22 in lvl10)
	_chk("S2.06 Bulbasaur at level 10 does NOT yet know Poison Powder (77, learned at 15)",
			not (77 in lvl10))

	var lvl46 := MovepoolResolver.legal_move_ids(1, 46)
	_chk("S2.07 Bulbasaur at level 46 knows Solar Beam (76)", 76 in lvl46)

	# Substitute is a universal (any-species, any-level) move per
	# special_movesets.json's own universalMoves list — legal even for a
	# freshly-level-1 Bulbasaur, confirming the TM/tutor/universal half of
	# the legality policy (not just level-up gating).
	var substitute_id := MoveNameMap.id_for_name("MOVE_SUBSTITUTE")
	_chk("S2.08 Substitute is a real implemented move", ResourceLoader.exists("res://data/moves/move_%04d.tres" % substitute_id))
	_chk("S2.09 Substitute (universal move) is legal for level-1 Bulbasaur", substitute_id in lvl1)

	_chk("S2.10 pool has no duplicate IDs", lvl46.size() == _dedup(lvl46).size())
	var sorted_copy := lvl46.duplicate()
	sorted_copy.sort()
	_chk("S2.11 pool is returned sorted", lvl46 == sorted_copy)

	for move_id in lvl46:
		if not ResourceLoader.exists("res://data/moves/move_%04d.tres" % move_id):
			_chk("S2.12 every returned move ID is a real implemented .tres (move #%d)" % move_id, false)
			return
	_chk("S2.12 every returned move ID is a real implemented .tres", true)


func _dedup(arr: Array) -> Array:
	var seen: Dictionary = {}
	for v in arr:
		seen[v] = true
	return seen.keys()


# ── Section 3/4: full UI-driven builds ───────────────────────────────────

func _instantiate_screen() -> Node:
	var scene: PackedScene = load("res://scenes/team_builder/team_builder_screen.tscn")
	var instance := scene.instantiate()
	add_child(instance)
	return instance


func _test_section_3_ui_driven_build_bulbasaur() -> void:
	var screen := _instantiate_screen()

	var species_edit: LineEdit = screen.get_node("Scroll/VBox/SpeciesRow/SpeciesLineEdit")
	var load_btn: Button = screen.get_node("Scroll/VBox/SpeciesRow/LoadSpeciesButton")
	species_edit.text = "1"
	load_btn.pressed.emit()

	var level_spin: SpinBox = screen.get_node("Scroll/VBox/LevelRow/LevelSpinBox")
	level_spin.value = 20

	var nature_option: OptionButton = screen.get_node("Scroll/VBox/NatureRow/NatureOptionButton")
	nature_option.select(nature_option.get_item_index(BattlePokemon.NATURE_ADAMANT))

	var ability_option: OptionButton = screen.get_node("Scroll/VBox/AbilityRow/AbilityOptionButton")
	_chk("S3.01 Bulbasaur has at least one real ability slot offered", ability_option.item_count > 0)
	var chosen_ability_slot: int = ability_option.get_selected_id()

	# Add two real, legal moves via the actual dropdown + Add button.
	var available_option: OptionButton = screen.get_node("Scroll/VBox/MovesSection/AddMoveRow/AvailableMovesOptionButton")
	var add_move_btn: Button = screen.get_node("Scroll/VBox/MovesSection/AddMoveRow/AddMoveButton")
	var tackle_idx := _find_item_by_id(available_option, 33)
	_chk("S3.02 Tackle is offered in the available-moves dropdown at level 20", tackle_idx >= 0)
	available_option.select(tackle_idx)
	add_move_btn.pressed.emit()

	var growl_idx := _find_item_by_id(available_option, 45)
	_chk("S3.03 Growl is offered after adding Tackle (not yet at the 4-move cap)", growl_idx >= 0)
	available_option.select(growl_idx)
	add_move_btn.pressed.emit()

	_chk("S3.04 Tackle no longer appears in the available dropdown once selected",
			_find_item_by_id(available_option, 33) == -1)

	var ev_boxes := _get_ev_spinboxes(screen)
	ev_boxes[BattlePokemon.STAT_ATK].value = 100
	ev_boxes[BattlePokemon.STAT_SPEED].value = 50

	var iv_boxes := _get_iv_spinboxes(screen)
	iv_boxes[BattlePokemon.STAT_DEF].value = 10

	var build_btn: Button = screen.get_node("Scroll/VBox/BuildButton")
	build_btn.pressed.emit()

	var built: BattlePokemon = screen._built_pokemon
	_chk("S3.05 a BattlePokemon was actually produced", built != null)
	if built == null:
		screen.queue_free()
		return

	var expected_evs: Array = [0, 100, 0, 0, 0, 50]
	var expected_ivs: Array = [31, 31, 10, 31, 31, 31]
	var direct := PokemonFactory.create_battle_pokemon(
			1, 20, [33, 45], BattlePokemon.NATURE_ADAMANT, expected_ivs, null,
			expected_evs, chosen_ability_slot)

	_chk("S3.06 UI-built species matches direct-factory species", built.species.species_name == direct.species.species_name)
	_chk("S3.07 UI-built level matches (20)", built.level == 20)
	_chk("S3.08 UI-built nature matches (Adamant)", built.nature == BattlePokemon.NATURE_ADAMANT)
	_chk("S3.09 UI-built stats match a direct PokemonFactory call with the same inputs",
			built.max_hp == direct.max_hp and built.attack == direct.attack
			and built.defense == direct.defense and built.sp_attack == direct.sp_attack
			and built.sp_defense == direct.sp_defense and built.speed == direct.speed)
	_chk("S3.10 UI-built EVs match what was entered", built.evs == expected_evs)
	_chk("S3.11 UI-built IVs match what was entered", built.ivs == expected_ivs)
	_chk("S3.12 UI-built moveset is exactly [Tackle, Growl]",
			built.moves.size() == 2 and built.moves[0].move_name == MoveRegistry.get_move(33).move_name
			and built.moves[1].move_name == MoveRegistry.get_move(45).move_name)
	_chk("S3.13 UI-built ability matches the direct-factory call",
			(built.ability == null and direct.ability == null)
			or (built.ability != null and direct.ability != null and built.ability.ability_id == direct.ability.ability_id))

	screen.queue_free()


func _test_section_4_ui_driven_build_charizard() -> void:
	var screen := _instantiate_screen()

	var species_edit: LineEdit = screen.get_node("Scroll/VBox/SpeciesRow/SpeciesLineEdit")
	var load_btn: Button = screen.get_node("Scroll/VBox/SpeciesRow/LoadSpeciesButton")
	species_edit.text = "6"  # Charizard
	load_btn.pressed.emit()

	var level_spin: SpinBox = screen.get_node("Scroll/VBox/LevelRow/LevelSpinBox")
	level_spin.value = 55

	var nature_option: OptionButton = screen.get_node("Scroll/VBox/NatureRow/NatureOptionButton")
	nature_option.select(nature_option.get_item_index(BattlePokemon.NATURE_TIMID))

	var ability_option: OptionButton = screen.get_node("Scroll/VBox/AbilityRow/AbilityOptionButton")
	var chosen_ability_slot: int = ability_option.get_selected_id()

	var flamethrower_id := MoveNameMap.id_for_name("MOVE_FLAMETHROWER")
	var available_option: OptionButton = screen.get_node("Scroll/VBox/MovesSection/AddMoveRow/AvailableMovesOptionButton")
	var add_move_btn: Button = screen.get_node("Scroll/VBox/MovesSection/AddMoveRow/AddMoveButton")
	var idx := _find_item_by_id(available_option, flamethrower_id)
	_chk("S4.01 Flamethrower is offered for Charizard at level 55", idx >= 0)
	available_option.select(idx)
	add_move_btn.pressed.emit()

	var ev_boxes := _get_ev_spinboxes(screen)
	ev_boxes[BattlePokemon.STAT_SPATK].value = 252
	ev_boxes[BattlePokemon.STAT_SPEED].value = 252
	# [Total-cap enforcement — the real point of this section] A third
	# stat's EV box is pushed toward 252 too, which would put the running
	# total at 756 — well past the real 510 cap — if nothing clamped it.
	ev_boxes[BattlePokemon.STAT_DEF].value = 252

	var total := 0
	for sb in ev_boxes:
		total += int(sb.value)
	_chk("S4.02 EV total never exceeds the real 510 cap even after pushing 3 boxes to 252",
			total <= BattleManager.EV_CAP_TOTAL)
	_chk("S4.03 the third (Def) box was clamped down by the widget itself, not left at 252",
			int(ev_boxes[BattlePokemon.STAT_DEF].value) < 252)

	var iv_boxes := _get_iv_spinboxes(screen)
	iv_boxes[BattlePokemon.STAT_HP].value = 40  # attempt an out-of-range IV
	_chk("S4.04 an out-of-range IV (40) is clamped to the real 31 max by the widget itself",
			int(iv_boxes[BattlePokemon.STAT_HP].value) <= 31)

	var build_btn: Button = screen.get_node("Scroll/VBox/BuildButton")
	build_btn.pressed.emit()

	var built: BattlePokemon = screen._built_pokemon
	_chk("S4.05 a second, distinct BattlePokemon was built", built != null and built.species.species_name == "Charizard")
	if built != null:
		_chk("S4.06 UI-built species/level/nature differ from Section 3's Bulbasaur build",
				built.species.species_name != "Bulbasaur" and built.level == 55 and built.nature == BattlePokemon.NATURE_TIMID)
		var direct := PokemonFactory.create_battle_pokemon(
				6, 55, [flamethrower_id], BattlePokemon.NATURE_TIMID, built.ivs.duplicate(),
				null, built.evs.duplicate(), chosen_ability_slot)
		_chk("S4.07 UI-built stats match a direct PokemonFactory call with the same (post-clamp) inputs",
				built.max_hp == direct.max_hp and built.speed == direct.speed and built.sp_attack == direct.sp_attack)

	screen.queue_free()


func _find_item_by_id(option: OptionButton, item_id: int) -> int:
	for i in range(option.item_count):
		if option.get_item_id(i) == item_id:
			return i
	return -1


func _get_ev_spinboxes(screen: Node) -> Array:
	return [
		screen.get_node("Scroll/VBox/EVSection/EVRowHP/SpinBox"),
		screen.get_node("Scroll/VBox/EVSection/EVRowAtk/SpinBox"),
		screen.get_node("Scroll/VBox/EVSection/EVRowDef/SpinBox"),
		screen.get_node("Scroll/VBox/EVSection/EVRowSpAtk/SpinBox"),
		screen.get_node("Scroll/VBox/EVSection/EVRowSpDef/SpinBox"),
		screen.get_node("Scroll/VBox/EVSection/EVRowSpeed/SpinBox"),
	]


func _get_iv_spinboxes(screen: Node) -> Array:
	return [
		screen.get_node("Scroll/VBox/IVSection/IVRowHP/SpinBox"),
		screen.get_node("Scroll/VBox/IVSection/IVRowAtk/SpinBox"),
		screen.get_node("Scroll/VBox/IVSection/IVRowDef/SpinBox"),
		screen.get_node("Scroll/VBox/IVSection/IVRowSpAtk/SpinBox"),
		screen.get_node("Scroll/VBox/IVSection/IVRowSpDef/SpinBox"),
		screen.get_node("Scroll/VBox/IVSection/IVRowSpeed/SpinBox"),
	]


# ── Section 5: illegal-state blocking ────────────────────────────────────

func _test_section_5_illegal_state_blocking() -> void:
	var screen := _instantiate_screen()

	var species_edit: LineEdit = screen.get_node("Scroll/VBox/SpeciesRow/SpeciesLineEdit")
	var load_btn: Button = screen.get_node("Scroll/VBox/SpeciesRow/LoadSpeciesButton")
	species_edit.text = "1"  # Bulbasaur
	load_btn.pressed.emit()

	var level_spin: SpinBox = screen.get_node("Scroll/VBox/LevelRow/LevelSpinBox")
	level_spin.value = 10

	var available_option: OptionButton = screen.get_node("Scroll/VBox/MovesSection/AddMoveRow/AvailableMovesOptionButton")
	# Solar Beam (76, learned at level 46) must be structurally unreachable
	# at level 10 — not merely "rejected if picked," genuinely absent from
	# the only list the UI ever offers.
	_chk("S5.01 Solar Beam is NOT in the available-moves dropdown at level 10 (illegal move unreachable)",
			_find_item_by_id(available_option, 76) == -1)

	# Add 4 legal moves, then confirm a 5th is structurally impossible.
	var add_move_btn: Button = screen.get_node("Scroll/VBox/MovesSection/AddMoveRow/AddMoveButton")
	for _i in range(4):
		if available_option.item_count == 0:
			break
		available_option.select(0)
		add_move_btn.pressed.emit()
	_chk("S5.02 exactly 4 moves were added", screen._selected_move_ids.size() == 4)
	_chk("S5.03 the Add Move button is disabled once at the 4-move cap", add_move_btn.disabled)
	_chk("S5.04 the available-moves dropdown is disabled once at the 4-move cap", available_option.disabled)

	# Raising the level, then LOWERING it again, must strip any selected
	# move that's no longer legal at the lower level — continuous
	# enforcement, not just at pick-time.
	level_spin.value = 46
	# (4 moves already selected, so the dropdown is empty regardless —
	# confirm the CAP, not availability, is what's blocking it here.)
	_chk("S5.05 at the 4-move cap, dropdown stays empty even after raising the level", available_option.item_count == 0)

	level_spin.value = 1
	var still_legal := true
	for move_id in screen._selected_move_ids:
		if not (move_id in MovepoolResolver.legal_move_ids(1, 1)):
			still_legal = false
	_chk("S5.06 after dropping to level 1, every remaining selected move is still genuinely legal at level 1",
			still_legal)

	# Species change must reset the moveset entirely (old picks are almost
	# certainly illegal for a different species).
	species_edit.text = "6"  # Charizard
	load_btn.pressed.emit()
	_chk("S5.07 changing species clears the previously-selected moveset",
			screen._selected_move_ids.is_empty())

	screen.queue_free()
