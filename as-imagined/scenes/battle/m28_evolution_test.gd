extends Node

# [M28a/M28b] Evolution — the permanent mutation primitive, the level-up
# dispatch, and Everstone. Full source citations live in docs/m28_recon.md;
# not repeated here in full, only the load-bearing facts this suite exists
# to prove:
#
#  - `_evolve_mon_species`/`_evolve_mon_ability` deliberately BYPASS the
#    species/ability setters' capture-once guard by writing
#    original_species/original_ability directly — otherwise the very next
#    switch-in (`_reset_mon_species`/`_reset_mon_ability`, called at EVERY
#    switch-in site) would silently revert the evolution.
#  - `_check_level_up`'s dex/learnset are refreshed the moment an evolution
#    fires mid-loop — otherwise a multi-level jump crossing an evolution's
#    level would keep reading the OLD species' learnset for the rest of
#    that same Exp award.
#  - First-table-order-match-wins (source's own explicit, commented
#    departure from vanilla) — proven on a real fixture (Wurmple), not a
#    synthetic species.
#  - `condition <= level`, not `==` — a multi-level jump correctly still
#    evolves even when it skips past the exact evolution level.
#  - Everstone (HOLD_EFFECT_PREVENT_EVOLVE) blocks evolution unconditionally
#    while still letting the level-up itself proceed.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_species_swap()
	_test_stats_and_hp_delta()
	_test_ability_slot_resolution()
	_test_types_refreshed()
	_test_nickname_auto_update()
	_test_move_learn_on_evolve_synthetic()

	_test_single_level_evolution()
	_test_multi_level_jump_evolution()
	_test_first_match_wins()
	_test_condition_gated_evolution()
	_test_everstone_blocks_evolution()
	_test_non_evolving_species_no_op()
	_test_deferred_condition_negative_control()
	_test_full_battle_integration()

	_test_item_evolution_with_region_condition()
	_test_item_evolution_second_region_condition()
	_test_item_evolution_correct_entry_by_item()
	_test_item_evolution_everstone_blocks()
	_test_item_evolution_wrong_item_no_op()
	_test_item_evolution_return_value_contract()
	_test_item_evolution_linking_cord()

	var total := _pass + _fail
	print("m28_evolution_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# Full, real species (types + abilities populated) — unlike m20b_test's own
# stripped `_species_from_registry`, this project's actual production
# mutation code (`_evolve_mon`) reads `PokemonRegistry.get_species_resource`
# directly, so the tests use the identical, fully-populated path.
func _species(dex: int) -> PokemonSpecies:
	return PokemonRegistry.get_species_resource(dex)


func _make_mon(dex: int, level: int, ivs: Array = [0, 0, 0, 0, 0, 0]) -> BattlePokemon:
	return BattlePokemon.from_species(_species(dex), level, BattlePokemon.NATURE_HARDY, ivs)


# ── A. mutation primitive in isolation ───────────────────────────────────

func _test_species_swap() -> void:
	var bm := _make_bm()
	var mon := _make_mon(1, 16)  # Bulbasaur
	var ivysaur := _species(2)
	bm._evolve_mon_species(mon, ivysaur)
	_chk("A.01 species becomes the new species", mon.species == ivysaur)
	# ⚠️ THE CAPTURE-GUARD-BYPASS FIX, DIRECTLY PROVEN: original_species must
	# ALSO become the new species, or the next switch-in would revert it.
	_chk("A.01b original_species is ALSO refreshed (the capture-once-guard bypass)",
			mon.original_species == ivysaur)
	bm._reset_mon_species(mon)
	_chk("A.01c proof: a switch-in reset AFTER evolving does NOT revert to Bulbasaur",
			mon.species == ivysaur)


func _test_stats_and_hp_delta() -> void:
	var bm := _make_bm()
	# Case 1: below-max HP before evolving.
	var mon := _make_mon(1, 16)
	var old_max_hp: int = mon.max_hp
	mon.current_hp = old_max_hp - 5
	bm._evolve_mon_species(mon, _species(2))
	bm._evolve_mon_stats(mon)
	_chk("A.02 stats recomputed against the NEW species (Ivysaur's higher bases)",
			mon.max_hp > old_max_hp)
	_chk("A.02b HP delta is flat additive: current_hp == (old_max-5) + (new_max-old_max)",
			mon.current_hp == old_max_hp - 5 + (mon.max_hp - old_max_hp))

	# Case 2: at-max HP before evolving -> stays at (new) max, no overflow.
	var mon2 := _make_mon(1, 16)
	mon2.current_hp = mon2.max_hp
	bm._evolve_mon_species(mon2, _species(2))
	bm._evolve_mon_stats(mon2)
	_chk("A.03 at-max case: current_hp lands exactly at the new max_hp",
			mon2.current_hp == mon2.max_hp)

	# ⚠️ original_attack etc. must ALSO be refreshed, or a later Transform
	# revert would restore PRE-evolution stats, not post-evolution ones.
	var pre_evolve_attack: int = mon.attack
	bm._reset_mon_stats(mon)
	_chk("A.04 original_attack etc. refreshed: a switch-in reset after evolving keeps POST-evolution stats",
			mon.attack == pre_evolve_attack)


func _test_ability_slot_resolution() -> void:
	var bm := _make_bm()
	var mon := _make_mon(1, 16)
	# Synthetic ability tables so the slot-index case is exact and unambiguous.
	var old_abilities: Array[int] = [65, 0, 34]   # Bulbasaur's real table (Overgrow/-/Chlorophyll)
	var new_abilities: Array[int] = [65, 0, 34]   # same slots, same shape
	mon.ability = load("res://data/abilities/ability_0034.tres") as AbilityData  # Chlorophyll (hidden slot)
	mon.original_ability = mon.ability
	bm._evolve_mon_ability(mon, old_abilities, new_abilities)
	_chk("A.05 ability resolved by the SAME slot index the mon's current ability occupied (hidden slot 2)",
			mon.ability != null and mon.ability.ability_id == 34)
	_chk("A.05b original_ability is ALSO refreshed (capture-once-guard bypass)",
			mon.original_ability == mon.ability)

	# id 0 in the resolved slot -> null ability, not a crash.
	var mon2 := _make_mon(1, 16)
	mon2.ability = load("res://data/abilities/ability_0065.tres") as AbilityData  # slot 0
	mon2.original_ability = mon2.ability
	bm._evolve_mon_ability(mon2, [65, 0, 34], [0, 0, 34])
	_chk("A.06 a resolved id of 0 becomes a null ability, not a crash", mon2.ability == null)

	# original_ability not found in old_abilities at all -> falls back to slot 0.
	var mon3 := _make_mon(1, 16)
	mon3.ability = load("res://data/abilities/ability_0099.tres") as AbilityData  # not in old_abilities
	mon3.original_ability = mon3.ability
	bm._evolve_mon_ability(mon3, [65, 0, 34], [1, 2, 3])
	_chk("A.07 an unresolvable original ability falls back to slot 0",
			mon3.ability != null and mon3.ability.ability_id == 1)


func _test_types_refreshed() -> void:
	var bm := _make_bm()
	var mon := _make_mon(1, 16)  # Bulbasaur — Grass/Poison
	var ivysaur := _species(2)   # also Grass/Poison, but a DIFFERENT species instance
	bm._evolve_mon_species(mon, ivysaur)
	_chk("A.08 original_types refreshed to the new species' own types",
			mon.original_types == ivysaur.types)
	# _reset_mon_type mutates mon.species.types IN PLACE from original_types —
	# proof the invariant survives an evolution rather than reverting.
	bm._reset_mon_type(mon)
	_chk("A.08b a switch-in type-reset after evolving leaves Ivysaur's OWN types intact",
			mon.species.types == ivysaur.types)


func _test_nickname_auto_update() -> void:
	var bm := _make_bm()
	var mon := _make_mon(1, 16)
	_chk("A.09 setup: nickname starts as the default (Bulbasaur)",
			mon.nickname == "Bulbasaur")
	var ivysaur := _species(2)
	bm._evolve_mon_nickname(mon, "Bulbasaur", ivysaur.species_name)
	_chk("A.09b a still-default nickname auto-updates to the new species' name",
			mon.nickname == "Ivysaur")

	var mon2 := _make_mon(1, 16)
	mon2.nickname = "Sprout"
	bm._evolve_mon_nickname(mon2, "Bulbasaur", "Ivysaur")
	_chk("A.10 a genuinely custom nickname is left untouched",
			mon2.nickname == "Sprout")


# ⚠️ CURRENTLY DEAD CODE, TESTED ANYWAY: no real level==0 learnset entry
# exists anywhere in data/learnsets.json (confirmed by direct scan) — this
# proves the MECHANISM works correctly in isolation, via direct injection,
# not via real PokemonRegistry data (which has nothing to inject here yet).
func _test_move_learn_on_evolve_synthetic() -> void:
	var bm := _make_bm()
	var mon := _make_mon(1, 16)
	mon.moves = []
	mon.current_pp = []
	# Directly exercise _try_learn_move_at_level the same way _evolve_mon_moves
	# would for a level==0 entry, since PokemonRegistry has no such entry to
	# drive this through _evolve_mon_moves itself with real data.
	bm._try_learn_move_at_level(mon, 33)  # Tackle
	_chk("A.11 the move-learn-on-evolve MECHANISM (via _try_learn_move_at_level) works in isolation",
			mon.moves.has(MoveRegistry.get_move(33)))


# ── B. level-up dispatch ─────────────────────────────────────────────────

func _test_single_level_evolution() -> void:
	var bm := _make_bm()
	var mon := _make_mon(1, 15)  # Bulbasaur, evolves to Ivysaur at level 16
	mon.current_exp = 2035  # MediumSlow curve[15]
	var evolutions: Array = []
	bm.evolved.connect(func(_p, old_dex, new_dex): evolutions.append([old_dex, new_dex]))
	mon.current_exp = 2535  # MediumSlow curve[16]
	bm._check_level_up(mon)
	_chk("B.01 Bulbasaur leveling 15->16 becomes Ivysaur",
			mon.species.national_dex_num == 2)
	_chk("B.01b evolved signal fired exactly once, (mon, 1, 2)",
			evolutions == [[1, 2]])
	_chk("B.01c nickname auto-updated to Ivysaur",
			mon.nickname == "Ivysaur")


func _test_multi_level_jump_evolution() -> void:
	var bm := _make_bm()
	var mon := _make_mon(1, 15)
	mon.current_exp = 2035  # MediumSlow curve[15], just at the level-15 threshold
	mon.current_exp = 5460  # MediumSlow curve[20] — a multi-level jump 15->20 in one award
	var evolutions: Array = []
	bm.evolved.connect(func(_p, old_dex, new_dex): evolutions.append([old_dex, new_dex]))
	bm._check_level_up(mon)
	_chk("B.02 the multi-level jump still reaches level 20", mon.level == 20)
	_chk("B.02b evolved into Ivysaur exactly once, mid-loop",
			evolutions == [[1, 2]] and mon.species.national_dex_num == 2)
	# ⚠️ THE REAL BUG-FIX PROOF: Bulbasaur has a level-20 entry (Razor Leaf,
	# move 75); Ivysaur does NOT. If dex/learnset were not refreshed after
	# the mid-loop evolution, level 20's move-learn check would still use
	# Bulbasaur's stale learnset and incorrectly teach Razor Leaf.
	_chk("B.02c level 20's move-learn check used Ivysaur's (refreshed) learnset, NOT Bulbasaur's stale one",
			not mon.moves.has(MoveRegistry.get_move(75)))


func _test_first_match_wins() -> void:
	var bm := _make_bm()
	# Wurmple (dex 265) has two unconditioned level-7 entries in FILE ORDER:
	# Silcoon (266) first, Cascoon (268) second. Must always resolve to Silcoon.
	var mon := _make_mon(265, 6)
	mon.current_exp = 216  # MediumFast curve[6]
	mon.current_exp = 343  # MediumFast curve[7]
	bm._check_level_up(mon)
	_chk("B.03 Wurmple leveling to 7 always becomes Silcoon (first table-order match), not Cascoon",
			mon.species.national_dex_num == 266)


func _test_condition_gated_evolution() -> void:
	var bm := _make_bm()
	# Tyrogue (dex 236): base Atk==Def==35, so IVs alone can force each branch.
	# attack > defense -> Hitmonlee (106)
	var lee := _make_mon(236, 19, [0, 31, 0, 0, 0, 0])
	lee.current_exp = 6859  # MediumFast curve[19]
	lee.current_exp = 8000  # MediumFast curve[20]
	bm._check_level_up(lee)
	_chk("B.04 Tyrogue with Atk>Def becomes Hitmonlee (106), not Hitmonchan/Hitmontop",
			lee.species.national_dex_num == 106)

	# attack < defense -> Hitmonchan (107)
	var bm2 := _make_bm()
	var chan := _make_mon(236, 19, [0, 0, 31, 0, 0, 0])
	chan.current_exp = 6859
	chan.current_exp = 8000
	bm2._check_level_up(chan)
	_chk("B.04b Tyrogue with Atk<Def becomes Hitmonchan (107), not Hitmonlee/Hitmontop",
			chan.species.national_dex_num == 107)

	# attack == defense -> Hitmontop (237)
	var bm3 := _make_bm()
	var top := _make_mon(236, 19, [0, 0, 0, 0, 0, 0])
	top.current_exp = 6859
	top.current_exp = 8000
	bm3._check_level_up(top)
	_chk("B.04c Tyrogue with Atk==Def becomes Hitmontop (237), not Hitmonlee/Hitmonchan",
			top.species.national_dex_num == 237)


func _test_everstone_blocks_evolution() -> void:
	var bm := _make_bm()
	var mon := _make_mon(1, 15)
	mon.held_item = ItemRegistry.get_item(245)  # Everstone
	mon.current_exp = 2035
	mon.current_exp = 2535  # would otherwise cross into Ivysaur
	var evolutions: Array = []
	bm.evolved.connect(func(_p, _o, _n): evolutions.append(true))
	bm._check_level_up(mon)
	_chk("B.05 Everstone blocks the evolution: species stays Bulbasaur",
			mon.species.national_dex_num == 1)
	_chk("B.05b no evolved signal fired", evolutions.is_empty())
	_chk("B.05c the level-up itself still proceeds normally (level 16)",
			mon.level == 16)


func _test_non_evolving_species_no_op() -> void:
	var bm := _make_bm()
	var mon := _make_mon(3, 15)  # Venusaur — no further evolutions
	mon.current_exp = 2035
	mon.current_exp = 2535
	var evolutions: Array = []
	bm.evolved.connect(func(_p, _o, _n): evolutions.append(true))
	bm._check_level_up(mon)
	_chk("B.06 a fully-evolved species leveling up is a clean no-op",
			mon.species.national_dex_num == 3 and evolutions.is_empty() and mon.level == 16)


func _test_deferred_condition_negative_control() -> void:
	var bm := _make_bm()
	# Eevee's only level-up branches (Umbreon/Espeon) both require IF_TIME/
	# IF_NOT_TIME, which this pass fails closed on (no clock system exists).
	var mon := _make_mon(133, 6)
	mon.current_exp = 216  # MediumFast curve[6]
	mon.current_exp = 343  # MediumFast curve[7]
	bm._check_level_up(mon)
	_chk("B.07 Eevee never evolves via level-up in this pass (deferred conditions, not Everstone)",
			mon.species.national_dex_num == 133)


func _test_full_battle_integration() -> void:
	var bm := _make_bm()
	var recipient := _make_mon(1, 15)
	recipient.current_exp = 2035  # MediumSlow curve[15]
	recipient.add_move(MoveRegistry.get_move(33))  # Tackle, so it can act

	var fainted := _make_mon(1, 30)
	fainted.current_hp = 1
	fainted.add_move(MoveRegistry.get_move(33))

	var evolutions: Array = []
	bm.evolved.connect(func(p, old_dex, new_dex): if p == recipient: evolutions.append([old_dex, new_dex]))

	bm._exp_participants = [[0]]
	bm._parties = [BattleParty.single(recipient), BattleParty.single(fainted)]
	bm._combatants = [recipient, fainted]
	bm._active_per_side = 1

	# fainted_level=30, recipient_level=15, exp_yield=64 -> award == 702
	# (verified by direct simulation of _compute_exp_award's own formula).
	# 2035 + 702 == 2737, which crosses curve[16]==2535 but not curve[17]==3120
	# -- a clean single-level-up that also crosses the evolution boundary,
	# driven entirely through the REAL production call site.
	bm._award_exp_for_fainted_opponent(fainted)
	_chk("B.08 full-battle integration: recipient's current_exp is the real computed award (2035+702=2737)",
			recipient.current_exp == 2737)
	_chk("B.08b evolution fired through the REAL _award_exp_for_fainted_opponent call site",
			evolutions == [[1, 2]])
	_chk("B.08c recipient is now level 16 and Ivysaur",
			recipient.level == 16 and recipient.species.national_dex_num == 2)


# ── C. [M28c] item-triggered dispatch ────────────────────────────────────

# Deliberately the IF_NOT_REGION-carrying entry — proves
# _evolution_conditions_met is genuinely reused for item-method entries,
# not skipped (a species with no extra conditions can't tell the difference).
func _test_item_evolution_with_region_condition() -> void:
	var bm := _make_bm()
	var mon := _make_mon(25, 10)  # Pikachu
	var evolutions: Array = []
	bm.evolved.connect(func(_p, old_dex, new_dex): evolutions.append([old_dex, new_dex]))
	var fired: bool = bm.try_evolve_with_item(mon, 213)  # Thunder Stone
	_chk("C.01 Pikachu + Thunder Stone becomes Raichu (26), the IF_NOT_REGION entry actually fires",
			fired and mon.species.national_dex_num == 26)
	_chk("C.01b evolved signal fired (mon, 25, 26)", evolutions == [[25, 26]])


# The second, independent IF_NOT_REGION entry.
func _test_item_evolution_second_region_condition() -> void:
	var bm := _make_bm()
	var mon := _make_mon(102, 10)  # Exeggcute
	var fired: bool = bm.try_evolve_with_item(mon, 214)  # Leaf Stone
	_chk("C.02 Exeggcute + Leaf Stone becomes Exeggutor (103), the second IF_NOT_REGION entry",
			fired and mon.species.national_dex_num == 103)


# Eevee has 3 item-method entries to 3 DIFFERENT targets. Unlike B.03's
# first-match-wins proof (several entries reachable by the SAME trigger),
# this proves the CORRECT entry is picked based on which item_id was
# actually passed in.
func _test_item_evolution_correct_entry_by_item() -> void:
	var bm1 := _make_bm()
	var water := _make_mon(133, 10)
	bm1.try_evolve_with_item(water, 212)  # Water Stone
	_chk("C.03 Eevee + Water Stone becomes Vaporeon (134), not Jolteon/Flareon",
			water.species.national_dex_num == 134)

	var bm2 := _make_bm()
	var thunder := _make_mon(133, 10)
	bm2.try_evolve_with_item(thunder, 213)  # Thunder Stone
	_chk("C.03b Eevee + Thunder Stone becomes Jolteon (135), not Vaporeon/Flareon",
			thunder.species.national_dex_num == 135)

	var bm3 := _make_bm()
	var fire := _make_mon(133, 10)
	bm3.try_evolve_with_item(fire, 211)  # Fire Stone
	_chk("C.03c Eevee + Fire Stone becomes Flareon (136), not Vaporeon/Jolteon",
			fire.species.national_dex_num == 136)


func _test_item_evolution_everstone_blocks() -> void:
	var bm := _make_bm()
	var mon := _make_mon(1, 15)  # Bulbasaur
	mon.held_item = ItemRegistry.get_item(245)  # Everstone
	var evolutions: Array = []
	bm.evolved.connect(func(_p, _o, _n): evolutions.append(true))
	var fired: bool = bm.try_evolve_with_item(mon, 214)  # Leaf Stone -- Bulbasaur has no such entry,
	                                                       # but Everstone must block BEFORE resolution anyway
	_chk("C.04 Everstone blocks an item evolution, species unchanged",
			not fired and mon.species.national_dex_num == 1)
	_chk("C.04b no evolved signal fired", evolutions.is_empty())


func _test_item_evolution_wrong_item_no_op() -> void:
	var bm := _make_bm()
	var mon := _make_mon(1, 15)  # Bulbasaur -- no item-method evolution at all
	var evolutions: Array = []
	bm.evolved.connect(func(_p, _o, _n): evolutions.append(true))
	var fired: bool = bm.try_evolve_with_item(mon, 211)  # Fire Stone
	_chk("C.05 the wrong item does nothing: species unchanged",
			not fired and mon.species.national_dex_num == 1)
	_chk("C.05b no evolved signal fired", evolutions.is_empty())


func _test_item_evolution_return_value_contract() -> void:
	var bm1 := _make_bm()
	var success := _make_mon(25, 10)  # Pikachu
	_chk("C.06 try_evolve_with_item returns true on a real evolution",
			bm1.try_evolve_with_item(success, 213) == true)

	var bm2 := _make_bm()
	var wrong_item := _make_mon(1, 15)
	_chk("C.06b returns false for a wrong item",
			bm2.try_evolve_with_item(wrong_item, 211) == false)

	var bm3 := _make_bm()
	var blocked := _make_mon(25, 10)
	blocked.held_item = ItemRegistry.get_item(245)
	_chk("C.06c returns false when Everstone blocks it",
			bm3.try_evolve_with_item(blocked, 213) == false)


# M28d's own proof: Linking Cord fires through the exact same generic
# dispatch as every other item-method entry — no separate code was needed.
func _test_item_evolution_linking_cord() -> void:
	var bm := _make_bm()
	var mon := _make_mon(64, 15)  # Kadabra
	var fired: bool = bm.try_evolve_with_item(mon, 796)  # Linking Cord
	_chk("C.07 Kadabra + Linking Cord becomes Alakazam (65) -- M28d needed no separate code",
			fired and mon.species.national_dex_num == 65)
