extends Node

# M18p test suite — Contact-reactive damage family (Rocky Helmet/Sticky Barb/
# Protective Pads/Punching Glove)
#
# Ground truth: pokeemerald-expansion
#   src/battle_hold_effects.c :: TryRockyHelmet (L236-254) — CONTACT-gated only
#     (unlike Jaboca/Rowap, [M18d], which are category-gated only despite the
#     family resemblance): holder takes direct damage from a contact move ->
#     maxHP/6 retaliation to the ATTACKER, gated on the attacker's own Magic
#     Guard. Not consumed.
#   src/battle_hold_effects.c :: TryStickyBarbOnTargetHit (L564-583) /
#     TryStickyBarbOnEndTurn (L585-599) — TWO independent triggers: (a)
#     contact-gated item transfer to the attacker (if it holds nothing),
#     explicitly bypassing Sticky Hold ("// No sticky hold checks." — confirmed
#     genuine via CanStealItem/CanBattlerGetOrLoseItem, neither of which
#     reference Sticky Hold anywhere); (b) unconditional maxHP/8 end-of-turn
#     self-damage, gated by the HOLDER's own Magic Guard, unrelated to contact.
#   src/battle_util.c :: CanBattlerAvoidContactEffects (L5717-5726) — Protective
#     Pads' ACTUAL gate, ONE LEVEL ABOVE IsMoveMakingContact. Applies only to
#     genuine contact-RETALIATION consumers (Rough Skin/Rocky Helmet/Sticky
#     Barb-transfer/Aftermath/etc.), confirmed to NOT apply to Tough Claws'
#     power boost or Poison Touch's own check (those call IsMoveMakingContact
#     directly, bypassing the wrapper).
#   src/battle_util.c :: IsMoveMakingContact (L5728-5741) — Punching Glove's
#     contact-strip lives INSIDE this function, the SAME level as Long Reach,
#     so it is UNIVERSAL (affects Tough Claws etc. too), a genuinely different
#     scope from Protective Pads despite the "contact-reactive family" grouping.
#   src/battle_util.c :: GetAttackerItemsModifier, HOLD_EFFECT_PUNCHING_GLOVE
#     case (L6664-6666) — x1.1 power on punching moves.
#
# Docs: docs/m18_subtier_plan.md (M18p section) — 4 items, no cross-tier
# dependencies. The real "don't assume family symmetry" finding this tier is
# the Protective-Pads-vs-Punching-Glove level split, not a contact-vs-category
# confusion like [M18d]'s.
#
# Sections: P01 Rocky Helmet, P02 Sticky Barb, P03 Protective Pads,
# P04 Punching Glove.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_p01_rocky_helmet()
	_test_p02_sticky_barb()
	_test_p03_protective_pads()
	_test_p04_punching_glove()

	var total := _pass + _fail
	print("m18p_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18d_test.gd's established pattern) ───────────────────────

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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [M18.5h-1/2] pinned neutral nature + zero IVs -- exact-value assertions predate both


func _make_move(move_name: String, move_type: int, category: int, power: int,
		makes_contact: bool = false, punching_move: bool = false) -> MoveData:
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
	m.makes_contact    = makes_contact
	m.punching_move    = punching_move
	return m


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


const MAGIC_GUARD_ID := 98
const ROUGH_SKIN_ID := 24
const TOUGH_CLAWS_ID := 181
const STICKY_HOLD_ID := 60
const AFTERMATH_ID := 106
const LONG_REACH_ID := 203


# ── P01: Rocky Helmet (496) ─────────────────────────────────────────────────────
func _test_p01_rocky_helmet() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_ROCKY_HELMET)
	_chk("P01.01 Rocky Helmet hold_effect=ROCKY_HELMET, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_ROCKY_HELMET)

	var holder := _make_mon("P01_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	var attacker := _make_mon("P01_Attacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	# max_hp = 160 for base_hp=100 -> 1/6 = 26 (integer division).
	_chk("P01.02 direct: pure magnitude is the ATTACKER's maxHP/6 (=26 of 160)",
			ItemManager.rocky_helmet_retaliation_damage(holder, attacker) == 26)

	var no_item_holder := _make_mon("P01_NoItem", TypeChart.TYPE_NORMAL)
	_chk("P01.03 discriminator: no item held -> 0",
			ItemManager.rocky_helmet_retaliation_damage(no_item_holder, attacker) == 0)

	# Full-battle: CONTACT move -> retaliation fires.
	var rh_holder := _make_mon("P01_Battle", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 40)
	rh_holder.held_item = item
	rh_holder.add_move(_make_move("P01_HolderMove", TypeChart.TYPE_NORMAL, 0, 5))
	var contact_attacker := _make_mon("P01_ContactAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	contact_attacker.add_move(_make_move("P01_ContactMove", TypeChart.TYPE_NORMAL, 0, 40, true))

	var item_dmg_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.item_damage.connect(func(m, amt): item_dmg_events.push_back([m, amt]))
	bm.start_battle_with_parties(BattleParty.single(rh_holder), BattleParty.single(contact_attacker))
	_chk("P01.04 full-battle: a CONTACT hit triggers Rocky Helmet's retaliation (=26)",
			not item_dmg_events.is_empty() and item_dmg_events[0][0] == contact_attacker \
					and item_dmg_events[0][1] == 26)
	bm.queue_free()

	# Discriminator: a NON-CONTACT move of the same category/power does NOT
	# trigger -- proving Rocky Helmet is contact-gated, NOT category-gated
	# (the mirror-image finding to [M18d]'s Jaboca/Rowap, which DID fire on a
	# non-contact move of the matching category).
	var rh_holder2 := _make_mon("P01_Battle2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 40)
	rh_holder2.held_item = item
	rh_holder2.add_move(_make_move("P01_HolderMove2", TypeChart.TYPE_NORMAL, 0, 5))
	var ranged_attacker := _make_mon("P01_RangedAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	var ranged_move := _make_move("P01_RangedMove", TypeChart.TYPE_NORMAL, 0, 40, false)
	_chk("P01.05 sanity: the test move is genuinely non-contact",
			not ranged_move.makes_contact)
	ranged_attacker.add_move(ranged_move)

	var item_dmg_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_crit = false
	bm2.item_damage.connect(func(m, amt): item_dmg_events2.push_back([m, amt]))
	bm2.start_battle_with_parties(BattleParty.single(rh_holder2), BattleParty.single(ranged_attacker))
	_chk("P01.06 discriminator: a non-contact hit of matching power does NOT " +
			"trigger Rocky Helmet (contact-gated, not category-gated -- the " +
			"mirror-image of [M18d]'s Jaboca/Rowap finding)",
			item_dmg_events2.is_empty())
	bm2.queue_free()

	# Magic Guard (the ATTACKER's own ability, since the attacker takes the
	# damage) blocks the retaliation entirely.
	var mg_holder := _make_mon("P01_MGHolder", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 40)
	mg_holder.held_item = item
	mg_holder.add_move(_make_move("P01_MGHolderMove", TypeChart.TYPE_NORMAL, 0, 5))
	var mg_attacker := _make_mon("P01_MGAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	mg_attacker.ability = _load_ability(MAGIC_GUARD_ID)
	mg_attacker.add_move(_make_move("P01_MGMove", TypeChart.TYPE_NORMAL, 0, 40, true))

	var item_dmg_events3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_hit = true
	bm3._force_crit = false
	bm3.item_damage.connect(func(m, amt): item_dmg_events3.push_back([m, amt]))
	bm3.start_battle_with_parties(BattleParty.single(mg_holder), BattleParty.single(mg_attacker))
	_chk("P01.07 Magic Guard (attacker's own ability) blocks Rocky Helmet's " +
			"retaliation entirely",
			item_dmg_events3.is_empty())
	bm3.queue_free()

	# Not consumed -- the holder still has the item after the battle turn.
	_chk("P01.08 Rocky Helmet is NOT consumed by triggering",
			rh_holder.held_item != null and rh_holder.held_item.hold_effect == ItemManager.HOLD_EFFECT_ROCKY_HELMET)


# ── P02: Sticky Barb (489) ───────────────────────────────────────────────────────
func _test_p02_sticky_barb() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_STICKY_BARB)
	_chk("P02.01 Sticky Barb hold_effect=STICKY_BARB, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_STICKY_BARB)

	var holder := _make_mon("P02_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	# max_hp = 160 for base_hp=100 -> 1/8 = 20.
	_chk("P02.02 direct: EOT pure magnitude is the HOLDER's own maxHP/8 (=20 of 160)",
			ItemManager.sticky_barb_damage(holder) == 20)

	var no_item_holder := _make_mon("P02_NoItem", TypeChart.TYPE_NORMAL)
	_chk("P02.03 discriminator: no Sticky Barb held -> 0",
			ItemManager.sticky_barb_damage(no_item_holder) == 0)

	# Full-battle EOT self-damage: unconditional, no contact needed at all --
	# use a non-contact move exchange to prove it isn't tied to contact.
	var eot_holder := _make_mon("P02_EOT", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 40)
	eot_holder.held_item = item
	eot_holder.add_move(_make_move("P02_EOTMove", TypeChart.TYPE_NORMAL, 0, 1, false))
	var eot_opponent := _make_mon("P02_EOTOpponent", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	eot_opponent.add_move(_make_move("P02_EOTOpponentMove", TypeChart.TYPE_NORMAL, 0, 1, false))

	var item_dmg_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.item_damage.connect(func(m, amt): item_dmg_events.push_back([m, amt]))
	bm.start_battle_with_parties(BattleParty.single(eot_holder), BattleParty.single(eot_opponent))
	_chk("P02.04 full-battle: Sticky Barb's end-of-turn self-damage fires " +
			"unconditionally (=20), NOT contact-related",
			item_dmg_events.any(func(e): return e[0] == eot_holder and e[1] == 20))
	bm.queue_free()

	# Magic Guard on the HOLDER (not the attacker -- self-inflicted damage)
	# blocks the EOT half. Discriminator vs. Rocky Helmet's attacker-side gate.
	var mg_holder := _make_mon("P02_MGHolder", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 40)
	mg_holder.held_item = item
	mg_holder.ability = _load_ability(MAGIC_GUARD_ID)
	mg_holder.add_move(_make_move("P02_MGHolderMove", TypeChart.TYPE_NORMAL, 0, 1, false))
	var mg_opponent := _make_mon("P02_MGOpponent", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	mg_opponent.add_move(_make_move("P02_MGOpponentMove", TypeChart.TYPE_NORMAL, 0, 1, false))

	var item_dmg_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_crit = false
	bm2.item_damage.connect(func(m, amt): item_dmg_events2.push_back([m, amt]))
	bm2.start_battle_with_parties(BattleParty.single(mg_holder), BattleParty.single(mg_opponent))
	_chk("P02.05 Magic Guard on the HOLDER (self-damage, not attacker-directed) " +
			"blocks Sticky Barb's EOT half",
			item_dmg_events2.filter(func(e): return e[0] == mg_holder).is_empty())
	bm2.queue_free()

	# Full-battle CONTACT transfer: attacker holds nothing, hits the barb
	# holder with a contact move -> item moves onto the attacker.
	var transfer_holder := _make_mon("P02_Transfer", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	transfer_holder.held_item = _make_item(ItemManager.HOLD_EFFECT_STICKY_BARB)
	transfer_holder.add_move(_make_move("P02_TransferMove", TypeChart.TYPE_NORMAL, 0, 1, false))
	var contact_attacker := _make_mon("P02_ContactAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	contact_attacker.add_move(_make_move("P02_ContactMove", TypeChart.TYPE_NORMAL, 0, 40, true))

	var transfer_events := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_hit = true
	bm3._force_crit = false
	bm3.item_transferred.connect(func(f, t, i): transfer_events.push_back([f, t, i]))
	bm3.start_battle_with_parties(BattleParty.single(transfer_holder), BattleParty.single(contact_attacker))
	_chk("P02.06 full-battle: a CONTACT hit transfers Sticky Barb from the " +
			"holder onto the attacker (attacker held nothing)",
			not transfer_events.is_empty() and transfer_events[0][0] == transfer_holder \
					and transfer_events[0][1] == contact_attacker)
	_chk("P02.07 after transfer, the attacker now holds the barb and the " +
			"original holder holds nothing",
			contact_attacker.held_item != null \
					and contact_attacker.held_item.hold_effect == ItemManager.HOLD_EFFECT_STICKY_BARB \
					and transfer_holder.held_item == null)
	bm3.queue_free()

	# Discriminator: a NON-CONTACT move does NOT transfer.
	var nc_holder := _make_mon("P02_NC", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	nc_holder.held_item = _make_item(ItemManager.HOLD_EFFECT_STICKY_BARB)
	nc_holder.add_move(_make_move("P02_NCMove", TypeChart.TYPE_NORMAL, 0, 1, false))
	var nc_attacker := _make_mon("P02_NCAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	nc_attacker.add_move(_make_move("P02_NCAttackerMove", TypeChart.TYPE_NORMAL, 0, 40, false))

	var transfer_events2 := []
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4._force_hit = true
	bm4._force_crit = false
	bm4.item_transferred.connect(func(f, t, i): transfer_events2.push_back([f, t, i]))
	bm4.start_battle_with_parties(BattleParty.single(nc_holder), BattleParty.single(nc_attacker))
	_chk("P02.08 discriminator: a non-contact hit does NOT transfer Sticky Barb",
			transfer_events2.is_empty())
	bm4.queue_free()

	# Discriminator: attacker already holds an item -> no transfer.
	var occupied_holder := _make_mon("P02_Occupied", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	occupied_holder.held_item = _make_item(ItemManager.HOLD_EFFECT_STICKY_BARB)
	occupied_holder.add_move(_make_move("P02_OccupiedMove", TypeChart.TYPE_NORMAL, 0, 1, false))
	var occupied_attacker := _make_mon("P02_OccupiedAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	occupied_attacker.held_item = _make_item(ItemManager.HOLD_EFFECT_LEFTOVERS)
	occupied_attacker.add_move(_make_move("P02_OccupiedAttackerMove", TypeChart.TYPE_NORMAL, 0, 40, true))

	var transfer_events3 := []
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5._force_hit = true
	bm5._force_crit = false
	bm5.item_transferred.connect(func(f, t, i): transfer_events3.push_back([f, t, i]))
	bm5.start_battle_with_parties(BattleParty.single(occupied_holder), BattleParty.single(occupied_attacker))
	_chk("P02.09 discriminator: an attacker already holding an item does NOT " +
			"receive the transfer",
			transfer_events3.is_empty() and occupied_attacker.held_item.hold_effect == ItemManager.HOLD_EFFECT_LEFTOVERS)
	bm5.queue_free()

	# Sticky Hold bypass -- a real, source-confirmed exception (see this
	# file's own header comment): a Sticky-Hold-holding Sticky Barb holder
	# STILL has the barb forced onto the attacker, unlike Pickpocket/Magician
	# which both respect Sticky Hold via the shared _try_steal_item primitive.
	_chk("P02.10 direct: AbilityManager.try_sticky_barb_transfer bypasses " +
			"Sticky Hold on the holder (a genuine exception to _try_steal_item's " +
			"normal gate)",
			_test_sticky_hold_bypass())


func _test_sticky_hold_bypass() -> bool:
	var stealer := _make_mon("P02_SHStealer", TypeChart.TYPE_NORMAL)
	var victim := _make_mon("P02_SHVictim", TypeChart.TYPE_NORMAL)
	victim.held_item = _make_item(ItemManager.HOLD_EFFECT_STICKY_BARB)
	victim.ability = _load_ability(STICKY_HOLD_ID)
	var transferred: bool = AbilityManager.try_sticky_barb_transfer(stealer, victim)
	return transferred and stealer.held_item != null and victim.held_item == null


# ── P03: Protective Pads (507) ───────────────────────────────────────────────────
func _test_p03_protective_pads() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PROTECTIVE_PADS)
	_chk("P03.01 Protective Pads hold_effect=PROTECTIVE_PADS, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_PROTECTIVE_PADS)

	var contact_move := _make_move("P03_Contact", TypeChart.TYPE_NORMAL, 0, 40, true)

	# Direct: move_triggers_contact_retaliation is false for a Protective-Pads-
	# holding attacker, even on a genuine contact move.
	var pp_attacker := _make_mon("P03_PPAttacker", TypeChart.TYPE_NORMAL)
	pp_attacker.held_item = item
	_chk("P03.02 direct: move_triggers_contact_retaliation is FALSE for a " +
			"Protective-Pads-holding attacker on a contact move",
			not AbilityManager.move_triggers_contact_retaliation(pp_attacker, contact_move))

	# Discriminator: move_makes_contact (the narrower, universal check) is
	# still TRUE for that same attacker -- proving Protective Pads is a
	# separate, higher-level gate, not folded into move_makes_contact itself.
	_chk("P03.03 discriminator: move_makes_contact itself is still TRUE for " +
			"that same Protective-Pads-holding attacker -- the gate lives ONE " +
			"LEVEL ABOVE move_makes_contact, confirming the two-level " +
			"architecture split",
			AbilityManager.move_makes_contact(pp_attacker, contact_move))

	var no_pp_attacker := _make_mon("P03_NoPP", TypeChart.TYPE_NORMAL)
	_chk("P03.04 discriminator: without Protective Pads, " +
			"move_triggers_contact_retaliation is TRUE for the same contact move",
			AbilityManager.move_triggers_contact_retaliation(no_pp_attacker, contact_move))

	# Full-battle: Protective Pads composes with an EXISTING ability
	# (Rough Skin) already dispatched through try_contact_effects -- proves
	# the shared-chokepoint claim, not just protection for this tier's own
	# 2 new items.
	var rs_holder := _make_mon("P03_RSHolder", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	rs_holder.ability = _load_ability(ROUGH_SKIN_ID)
	rs_holder.add_move(_make_move("P03_RSMove", TypeChart.TYPE_NORMAL, 0, 1, false))
	var pp_contact_attacker := _make_mon("P03_PPContactAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	pp_contact_attacker.held_item = item
	pp_contact_attacker.add_move(_make_move("P03_PPContactMove", TypeChart.TYPE_NORMAL, 0, 40, true))

	var recoil_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.recoil_damage.connect(func(m, amt): recoil_events.push_back([m, amt]))
	bm.start_battle_with_parties(BattleParty.single(rs_holder), BattleParty.single(pp_contact_attacker))
	_chk("P03.05 full-battle: a Protective-Pads-holding attacker is exempt " +
			"from Rough Skin's retaliation (an EXISTING ability, proving the " +
			"gate is genuinely shared, not new-item-only)",
			recoil_events.is_empty())
	bm.queue_free()

	# Baseline discriminator: WITHOUT Protective Pads, Rough Skin DOES fire.
	var rs_holder2 := _make_mon("P03_RSHolder2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	rs_holder2.ability = _load_ability(ROUGH_SKIN_ID)
	rs_holder2.add_move(_make_move("P03_RSMove2", TypeChart.TYPE_NORMAL, 0, 1, false))
	var plain_attacker := _make_mon("P03_PlainAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	plain_attacker.add_move(_make_move("P03_PlainMove", TypeChart.TYPE_NORMAL, 0, 40, true))

	var recoil_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_crit = false
	bm2.recoil_damage.connect(func(m, amt): recoil_events2.push_back([m, amt]))
	bm2.start_battle_with_parties(BattleParty.single(rs_holder2), BattleParty.single(plain_attacker))
	_chk("P03.06 baseline: without Protective Pads, Rough Skin's retaliation " +
			"DOES fire (proving P03.05 wasn't a coincidence)",
			not recoil_events2.is_empty())
	bm2.queue_free()

	# Direct: Aftermath is also gated by the SAME wrapper (confirmed from
	# source's own citation in faint_retaliation_damage's doc comment).
	var aftermath_mon := _make_mon("P03_Aftermath", TypeChart.TYPE_NORMAL)
	aftermath_mon.ability = _load_ability(AFTERMATH_ID)
	var killer_with_pads := _make_mon("P03_KillerPads", TypeChart.TYPE_NORMAL)
	killer_with_pads.held_item = item
	var am_move := _make_move("P03_AMMove", TypeChart.TYPE_NORMAL, 0, 100, true)
	var am_result: Dictionary = AbilityManager.faint_retaliation_damage(
			aftermath_mon, killer_with_pads, am_move, 10)
	_chk("P03.07 direct: a Protective-Pads-holding killer is exempt from " +
			"Aftermath's retaliation too (the same CanBattlerAvoidContactEffects " +
			"wrapper, confirmed independently of try_contact_effects)",
			am_result.is_empty())

	var killer_no_pads := _make_mon("P03_KillerNoPads", TypeChart.TYPE_NORMAL)
	var am_result2: Dictionary = AbilityManager.faint_retaliation_damage(
			aftermath_mon, killer_no_pads, am_move, 10)
	_chk("P03.08 discriminator: without Protective Pads, Aftermath's " +
			"retaliation DOES fire (=killer's own maxHP/4)",
			am_result2.get("damage", -1) == killer_no_pads.max_hp / 4)


# ── P04: Punching Glove (760) ────────────────────────────────────────────────────
func _test_p04_punching_glove() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PUNCHING_GLOVE)
	_chk("P04.01 Punching Glove hold_effect=PUNCHING_GLOVE, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_PUNCHING_GLOVE)

	var holder := _make_mon("P04_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	var punch_move := _make_move("P04_Punch", TypeChart.TYPE_NORMAL, 0, 40, true, true)
	_chk("P04.02 direct: x1.1 power (UQ_4_12(1.1)=4506) on a punching move",
			ItemManager.move_power_modifier_uq412(holder, punch_move) == ItemManager.UQ412_PUNCHING_GLOVE)

	var non_punch_move := _make_move("P04_NonPunch", TypeChart.TYPE_NORMAL, 0, 40, true, false)
	_chk("P04.03 discriminator: no power boost on a non-punching move",
			ItemManager.move_power_modifier_uq412(holder, non_punch_move) == 4096)

	_chk("P04.04 direct: move_makes_contact is FALSE for the holder's own " +
			"punching move (contact flag universally stripped)",
			not AbilityManager.move_makes_contact(holder, punch_move))

	_chk("P04.05 discriminator: move_makes_contact is still TRUE for a " +
			"NON-punching contact move by the same holder",
			AbilityManager.move_makes_contact(holder, non_punch_move))

	# Universal-scope proof: a Tough-Claws-ability holder ALSO holding
	# Punching Glove loses the Tough Claws power boost on a punching contact
	# move, since move_makes_contact (which Tough Claws itself consumes)
	# returns false universally -- the direct proof this is a DIFFERENT scope
	# than Protective Pads (P03.03 proved Protective Pads does NOT touch
	# move_makes_contact/Tough Claws at all).
	var tc_holder := _make_mon("P04_TCHolder", TypeChart.TYPE_NORMAL)
	tc_holder.ability = _load_ability(TOUGH_CLAWS_ID)
	tc_holder.held_item = item
	var tc_punch_move := _make_move("P04_TCPunch", TypeChart.TYPE_NORMAL, 0, 40, true, true)
	_chk("P04.06 universal-scope proof: Tough Claws' power boost does NOT " +
			"apply on the holder's own punching move (Punching Glove strips " +
			"contact at move_makes_contact's own level, unlike Protective Pads)",
			AbilityManager.move_power_modifier_uq412(tc_holder, tc_punch_move, 0) == 4096)

	# Full-battle sanity: a Punching Glove holder's punching contact move
	# does not trigger an opponent's Rocky Helmet (since it's non-contact).
	var pg_attacker := _make_mon("P04_Battle", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	pg_attacker.held_item = _make_item(ItemManager.HOLD_EFFECT_PUNCHING_GLOVE)
	pg_attacker.add_move(_make_move("P04_BattlePunch", TypeChart.TYPE_NORMAL, 0, 40, true, true))
	var rh_opponent := _make_mon("P04_RHOpponent", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	rh_opponent.held_item = _make_item(ItemManager.HOLD_EFFECT_ROCKY_HELMET)
	rh_opponent.add_move(_make_move("P04_RHOpponentMove", TypeChart.TYPE_NORMAL, 0, 1, false))

	var item_dmg_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.item_damage.connect(func(m, amt): item_dmg_events.push_back([m, amt]))
	bm.start_battle_with_parties(BattleParty.single(pg_attacker), BattleParty.single(rh_opponent))
	_chk("P04.07 full-battle: a Punching Glove holder's punching move does " +
			"NOT trigger the opponent's Rocky Helmet (contact stripped)",
			item_dmg_events.filter(func(e): return e[0] == pg_attacker).is_empty())
	bm.queue_free()
