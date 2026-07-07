extends Node

# M18d test suite — Leppa Berry + contact-retaliation-family berries (Jaboca/Rowap)
#
# Ground truth: pokeemerald-expansion
#   src/battle_hold_effects.c :: ItemRestorePp (L855-916) — Leppa Berry scans ALL
#     of the mon's moves in slot order and restores to the FIRST one at exactly 0
#     PP (`break`s on first match), checked at MoveEnd for the ATTACKER (the mon
#     that just acted) — src/battle_move_resolution.c :: MoveEndSprayLeppaBlunder
#     (L4204-4211). NOT tied to whether THIS move was the one that hit 0 PP.
#   src/battle_hold_effects.c :: TryJabocaBerry/TryRowapBerry (L332-376) — 1/8 the
#     ATTACKER's own max HP (Ripen, holder's side: 1/4) on ANY hit of the matching
#     move CATEGORY. MAJOR CORRECTION found at Step 0: neither function calls
#     IsMoveMakingContact anywhere — despite the superficial family resemblance to
#     Rough Skin/Iron Barbs (which genuinely ARE contact-gated), Jaboca/Rowap fire
#     on a non-contact physical/special move too. Gated on the ATTACKER (not the
#     holder) being alive and the attacker's own Magic Guard.
#
# Docs: docs/m18_subtier_plan.md (M18d section) — 3 items, no cross-tier
# dependencies. Reuses [M17n-9]'s AbilityManager.blocks_indirect_damage (Magic
# Guard) at the BattleManager call site, matching that predicate's other five
# call sites — NOT AbilityManager.move_makes_contact, which Jaboca/Rowap turn out
# not to need at all (a real correction to this tier's own task framing).
#
# Sections: D01 Leppa Berry, D02 Jaboca Berry, D03 Rowap Berry.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_d01_leppa_berry()
	_test_d02_jaboca_berry()
	_test_d03_rowap_berry()

	var total := _pass + _fail
	print("m18d_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18c_test.gd's established pattern) ───────────────────────

func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		base_hp: int = 100, base_atk: int = 60, base_def: int = 60,
		base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50)


func _make_move(move_name: String, move_type: int, category: int, power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name        = move_name
	m.type             = move_type
	m.category         = category
	m.power            = power
	m.accuracy         = 100
	m.pp               = 40
	m.secondary_effect = MoveData.SE_NONE
	m.secondary_chance = 0
	m.two_turn         = false
	m.semi_inv_state   = MoveData.SEMI_INV_NONE
	m.stat_change_stat = -1
	return m


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


const RIPEN_ID := 247
const MAGIC_GUARD_ID := 98


# ── D01: Leppa Berry (519) ──────────────────────────────────────────────────────
func _test_d01_leppa_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESTORE_PP, 10)
	_chk("D01.01 Leppa Berry hold_effect=RESTORE_PP, param=10",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESTORE_PP and item.hold_effect_param == 10)

	var mon := _make_mon("D01_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.add_move(_make_move("D01_Move", TypeChart.TYPE_NORMAL, 0, 40))
	mon.current_pp[0] = 0
	var trig: Dictionary = ItemManager.leppa_berry_restore(mon)
	_chk("D01.02 Leppa triggers when a move is at exactly 0 PP: move_index=0, amount=10",
			trig.get("move_index", -1) == 0 and trig.get("amount", -1) == 10)

	var mon2 := _make_mon("D01_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.add_move(_make_move("D01_Move2", TypeChart.TYPE_NORMAL, 0, 40))
	mon2.current_pp[0] = 5  # nonzero
	_chk("D01.03 discriminator: does NOT trigger while PP remains",
			ItemManager.leppa_berry_restore(mon2).is_empty())

	# Slot-order confirmation: TWO moves, only the SECOND is at 0 PP — must find
	# index 1, not blindly restore index 0 or "whichever move was just used."
	var mon3 := _make_mon("D01_Mon3", TypeChart.TYPE_NORMAL)
	mon3.held_item = item
	mon3.add_move(_make_move("D01_First", TypeChart.TYPE_NORMAL, 0, 40))
	mon3.add_move(_make_move("D01_Second", TypeChart.TYPE_NORMAL, 0, 40))
	mon3.current_pp[0] = 5
	mon3.current_pp[1] = 0
	var trig3: Dictionary = ItemManager.leppa_berry_restore(mon3)
	_chk("D01.04 finds the FIRST zero-PP move in slot order (index 1 here, not 0)",
			trig3.get("move_index", -1) == 1)

	var mon4 := _make_mon("D01_Mon4", TypeChart.TYPE_NORMAL)
	mon4.held_item = item
	mon4.add_move(_make_move("D01_Move4", TypeChart.TYPE_NORMAL, 0, 40))
	mon4.current_pp[0] = 0
	mon4.ability = _load_ability(RIPEN_ID)
	var trig4: Dictionary = ItemManager.leppa_berry_restore(mon4)
	_chk("D01.05 Ripen doubles Leppa's restore amount to 20",
			trig4.get("amount", -1) == 20)

	# Full-battle: attacker's move starts at 1 PP so using it once brings it to 0,
	# triggering Leppa at the SAME MoveEnd step -> restored back up to 10.
	var attacker := _make_mon("D01_Battle", TypeChart.TYPE_NORMAL)
	attacker.held_item = item
	var atk_move := _make_move("D01_AtkMove", TypeChart.TYPE_NORMAL, 0, 40)
	attacker.add_move(atk_move)
	attacker.current_pp[0] = 1
	var defender := _make_mon("D01_Def", TypeChart.TYPE_NORMAL)
	defender.add_move(_make_move("D01_DefMove", TypeChart.TYPE_NORMAL, 0, 40))

	var pp_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.pp_restored.connect(func(m, idx, new_pp): pp_events.push_back([m, idx, new_pp]))
	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(defender))
	_chk("D01.06 full-battle: using the last-PP move triggers Leppa at MoveEnd, " +
			"restoring PP to 10 (capped at the move's own base PP of 40, well " +
			"under the cap here)",
			not pp_events.is_empty() and pp_events[0][0] == attacker \
					and pp_events[0][1] == 0 and pp_events[0][2] == 10)
	bm.queue_free()


# ── D02: Jaboca Berry (577) ──────────────────────────────────────────────────────
func _test_d02_jaboca_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_JABOCA_BERRY)
	_chk("D02.01 Jaboca Berry hold_effect=JABOCA_BERRY, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_JABOCA_BERRY)

	var holder := _make_mon("D02_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	var attacker := _make_mon("D02_Attacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	# max_hp = 160 for base_hp=100 -> 1/8 = 20.
	var physical_move := _make_move("D02_Physical", TypeChart.TYPE_NORMAL, 0, 40)
	_chk("D02.02 direct: 1/8 the ATTACKER's max HP (=20 of 160) on a PHYSICAL hit",
			ItemManager.jaboca_rowap_retaliation_damage(holder, attacker, physical_move) == 20)

	var special_move := _make_move("D02_Special", TypeChart.TYPE_NORMAL, 1, 40)
	_chk("D02.03 discriminator: does NOT trigger on a SPECIAL-category hit",
			ItemManager.jaboca_rowap_retaliation_damage(holder, attacker, special_move) == 0)

	var holder2 := _make_mon("D02_Holder2", TypeChart.TYPE_NORMAL)
	holder2.held_item = item
	holder2.ability = _load_ability(RIPEN_ID)
	_chk("D02.04 Ripen (holder's own ability) doubles Jaboca's retaliation to 1/4 (=40)",
			ItemManager.jaboca_rowap_retaliation_damage(holder2, attacker, physical_move) == 40)

	# CORRECTION-confirming full-battle test: a PHYSICAL, NON-CONTACT move (the
	# _make_move default is makes_contact=false, confirmed unset) still triggers
	# Jaboca — proving this is genuinely NOT a contact-gated mechanism.
	var jaboca_holder := _make_mon("D02_Battle", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 40)
	jaboca_holder.held_item = item
	jaboca_holder.add_move(_make_move("D02_HolderMove", TypeChart.TYPE_NORMAL, 0, 5))
	var ranged_attacker := _make_mon("D02_RangedAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	var ranged_physical := _make_move("D02_RangedPhysical", TypeChart.TYPE_NORMAL, 0, 40)
	_chk("D02.05 sanity: the test move is genuinely non-contact (makes_contact=false)",
			not ranged_physical.makes_contact)
	ranged_attacker.add_move(ranged_physical)

	var item_dmg_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.item_damage.connect(func(m, amt): item_dmg_events.push_back([m, amt]))
	bm.start_battle_with_parties(BattleParty.single(jaboca_holder), BattleParty.single(ranged_attacker))
	_chk("D02.06 full-battle CORRECTION-confirming: a non-contact physical move " +
			"still triggers Jaboca's retaliation against the attacker (=20)",
			not item_dmg_events.is_empty() and item_dmg_events[0][0] == ranged_attacker \
					and item_dmg_events[0][1] == 20)
	bm.queue_free()

	# Edge case: the HOLDER faints from this exact hit, but retaliation still
	# fires — source gates only on the ATTACKER's aliveness, never the holder's.
	var fragile_holder := _make_mon("D02_Fragile", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			50, 60, 60, 60, 60, 30)
	fragile_holder.held_item = item
	fragile_holder.current_hp = 5  # guaranteed OHKO below
	fragile_holder.add_move(_make_move("D02_FragileMove", TypeChart.TYPE_NORMAL, 0, 5))
	var lethal_attacker := _make_mon("D02_Lethal", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 200, 60, 60, 60, 100)  # max_hp=160 -> 1/8=20
	lethal_attacker.add_move(_make_move("D02_LethalMove", TypeChart.TYPE_NORMAL, 0, 150))

	var item_dmg_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_crit = false
	bm2.item_damage.connect(func(m, amt): item_dmg_events2.push_back([m, amt]))
	bm2.start_battle_with_parties(BattleParty.single(fragile_holder), BattleParty.single(lethal_attacker))
	_chk("D02.07 the holder fainting from this exact hit does NOT block Jaboca's " +
			"retaliation (gated on the ATTACKER's aliveness only, per source)",
			not item_dmg_events2.is_empty() and item_dmg_events2[0][0] == lethal_attacker \
					and item_dmg_events2[0][1] == 20)
	_chk("D02.08 sanity: the holder actually fainted from that hit",
			fragile_holder.current_hp == 0)
	bm2.queue_free()


# ── D03: Rowap Berry (578) ───────────────────────────────────────────────────────
func _test_d03_rowap_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_ROWAP_BERRY)
	_chk("D03.01 Rowap Berry hold_effect=ROWAP_BERRY, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_ROWAP_BERRY)

	var holder := _make_mon("D03_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	var attacker := _make_mon("D03_Attacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	var special_move := _make_move("D03_Special", TypeChart.TYPE_NORMAL, 1, 40)
	_chk("D03.02 direct: 1/8 the ATTACKER's max HP (=20 of 160) on a SPECIAL hit",
			ItemManager.jaboca_rowap_retaliation_damage(holder, attacker, special_move) == 20)

	var physical_move := _make_move("D03_Physical", TypeChart.TYPE_NORMAL, 0, 40)
	_chk("D03.03 discriminator: does NOT trigger on a PHYSICAL-category hit " +
			"(inverted category from Jaboca)",
			ItemManager.jaboca_rowap_retaliation_damage(holder, attacker, physical_move) == 0)

	# Full-battle: a special, non-contact move still triggers Rowap.
	var rowap_holder := _make_mon("D03_Battle", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 40)
	rowap_holder.held_item = item
	rowap_holder.add_move(_make_move("D03_HolderMove", TypeChart.TYPE_NORMAL, 0, 5))
	var special_attacker := _make_mon("D03_SpecialAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	special_attacker.add_move(_make_move("D03_SpecialMove", TypeChart.TYPE_NORMAL, 1, 40))

	var item_dmg_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.item_damage.connect(func(m, amt): item_dmg_events.push_back([m, amt]))
	bm.start_battle_with_parties(BattleParty.single(rowap_holder), BattleParty.single(special_attacker))
	_chk("D03.04 full-battle: a special hit triggers Rowap's retaliation (=20)",
			not item_dmg_events.is_empty() and item_dmg_events[0][0] == special_attacker \
					and item_dmg_events[0][1] == 20)
	bm.queue_free()

	# Magic Guard blocks the retaliation entirely (attacker's own ability).
	var mg_holder := _make_mon("D03_MGHolder", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 40)
	mg_holder.held_item = item
	mg_holder.add_move(_make_move("D03_MGHolderMove", TypeChart.TYPE_NORMAL, 0, 5))
	var mg_attacker := _make_mon("D03_MGAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	mg_attacker.ability = _load_ability(MAGIC_GUARD_ID)
	mg_attacker.add_move(_make_move("D03_MGMove", TypeChart.TYPE_NORMAL, 1, 40))

	var item_dmg_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_crit = false
	bm2.item_damage.connect(func(m, amt): item_dmg_events2.push_back([m, amt]))
	bm2.start_battle_with_parties(BattleParty.single(mg_holder), BattleParty.single(mg_attacker))
	_chk("D03.05 Magic Guard (attacker's own ability) blocks Rowap's retaliation " +
			"entirely, reusing [M17n-9]'s blocks_indirect_damage",
			item_dmg_events2.is_empty())
	bm2.queue_free()
