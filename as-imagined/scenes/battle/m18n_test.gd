extends Node

# M18n test suite — Forced-switch items (Red Card, Eject Button)
#
# Ground truth: pokeemerald-expansion
#   include/constants/items.h -- ITEM_RED_CARD=498, ITEM_EJECT_BUTTON=501.
#   src/battle_move_resolution.c :: TryRedCard (L3730-3752) / TryEjectButton
#     (L3757-3773), both dispatched from MoveEndCardButton -- an item-reactive
#     path entirely separate from the general ItemBattleEffects switch (both
#     hold effects' data/hold_effects.h entries are EMPTY, confirmed by direct
#     inspection).
#   Genuinely different mechanics despite the "forced-switch items" grouping:
#     Red Card forces the ATTACKER to switch; Eject Button forces the HOLDER
#     itself. Both require: holder alive, holder took DIRECT damage this hit
#     (IsBattlerTurnDamaged, EXCLUDING_SUBSTITUTES -- no category gate, no
#     contact gate, confirmed absent from both functions), and a valid
#     replacement in the SWITCHING side's own party (CanBattlerSwitch -- a pure
#     party-composition check, NOT a trapping check, confirmed by reading its
#     body). No valid replacement -> the item does NOT activate/consume at all
#     (CanBattlerSwitch is checked BEFORE any activation code runs).
#   Red Card additionally requires the ATTACKER to still be alive
#     (!IsBattlerAlive(battlerAtk) -- an attacker that faints from its own
#     recoil earlier in the same hit resolution blocks Red Card entirely, no
#     consumption). Guard Dog on the ATTACKER blocks the SWITCH specifically
#     (BattleScript_RedCardActivationNoSwitch) but the item still consumes --
#     a different "no switch" reason than the no-valid-target case, with a
#     different consumption outcome. Eject Button has NO Guard Dog interaction
#     at all -- confirmed absent from its own source function (Guard Dog only
#     blocks being forced out BY AN OPPONENT's effect, not a self-triggered
#     switch).
#   Magic Guard: confirmed NO interaction with either item -- neither function
#     references ABILITY_MAGIC_GUARD; forced switching deals no damage.
#   AbilityManager.blocks_forced_switch's own doc comment (ability_manager.gd)
#     explicitly anticipated this gap ("this project has no Red Card item") --
#     reused UNCHANGED here, roles swapped from Roar's own call (the ATTACKER
#     being forced out goes in the `defender` slot, the item HOLDER goes in
#     the `attacker` slot).
#
# Docs: docs/m18_subtier_plan.md (M18n section) -- 2 items, no cross-tier
# dependencies for this tier itself; completing it unblocks M18m's Eject Pack.
# New ItemManager.holds_red_card()/holds_eject_button() (pure data checks);
# all orchestration (valid-target lookup, Guard Dog branch, consumption,
# _do_forced_switch_in) lives in BattleManager, reusing Roar/Whirlwind's exact
# forced-switch mechanism ([M9]/[M14b]) and _force_roar_rng seam.
#
# Sections: N01 Red Card, N02 Eject Button (incl. the Guard-Dog-does-NOT-block
# discriminator and a Magic Guard non-interaction check).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_n01_red_card()
	_test_n02_eject_button()

	var total := _pass + _fail
	print("m18n_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18k_test.gd's established pattern) ───────────────────────

func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_mon(mon_name: String, type1: int, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


# Builds a 2-member party (holder at slot 0, a bench mon at slot 1) -- the
# same shape [M17n-10]'s own Roar/Guard-Dog full-battle test uses.
func _two_member_party(active_mon: BattlePokemon, bench_mon: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [active_mon, bench_mon]
	return p


# ── N01: Red Card (498) ──────────────────────────────────────────────────────────
func _test_n01_red_card() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RED_CARD)
	_chk("N01.01 Red Card hold_effect == HOLD_EFFECT_RED_CARD(97)",
			item.hold_effect == ItemManager.HOLD_EFFECT_RED_CARD)

	var holder := _make_mon("N01_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("N01.02 direct: holds_red_card == true when holding Red Card",
			ItemManager.holds_red_card(holder))
	var bare := _make_mon("N01_Bare", TypeChart.TYPE_NORMAL)
	_chk("N01.03 discriminator: holding nothing -> false",
			not ItemManager.holds_red_card(bare))

	var tackle := _load_move(33)

	# Full-battle: attacker hits the Red Card holder; the ATTACKER (not the
	# holder) is forced to switch, and the holder's item is consumed.
	var atk1 := _make_mon("N01_Atk1", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk1.add_move(tackle)
	var atk1_bench := _make_mon("N01_Atk1Bench", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 20)
	var atk1_party := _two_member_party(atk1, atk1_bench)
	var rc_holder1 := _make_mon("N01_Holder1", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 40)
	rc_holder1.held_item = item
	rc_holder1.add_move(tackle)

	var switches1 := []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.forced_switch.connect(func(o, n): switches1.push_back([o, n]))
	bm1.start_battle_with_parties(atk1_party, BattleParty.single(rc_holder1))
	_chk("N01.04 full-battle: Red Card forces the ATTACKER (not the holder) to switch",
			switches1.any(func(e): return e[0] == atk1 and e[1] == atk1_bench))
	_chk("N01.05 the holder's Red Card is consumed",
			rc_holder1.held_item == null)
	bm1.queue_free()

	# Discriminator: the holder does NOT hold Red Card -> no forced switch.
	var atk2 := _make_mon("N01_Atk2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk2.add_move(tackle)
	var atk2_bench := _make_mon("N01_Atk2Bench", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 20)
	var atk2_party := _two_member_party(atk2, atk2_bench)
	var plain_holder2 := _make_mon("N01_Holder2", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 40)
	plain_holder2.add_move(tackle)

	var switches2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.forced_switch.connect(func(o, n): switches2.push_back([o, n]))
	bm2.start_battle_with_parties(atk2_party, BattleParty.single(plain_holder2))
	_chk("N01.06 discriminator: no Red Card held -> the attacker is never forced to switch",
			not switches2.any(func(e): return e[0] == atk2))
	bm2.queue_free()

	# Guard Dog on the ATTACKER blocks the SWITCH specifically, but the item
	# still consumes -- a different "no switch" reason and outcome than the
	# no-valid-target case below.
	var guard_dog := _load_ability(275)
	var gd_atk := _make_mon("N01_GDAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	gd_atk.ability = guard_dog
	gd_atk.add_move(tackle)
	var gd_atk_bench := _make_mon("N01_GDAtkBench", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 20)
	var gd_atk_party := _two_member_party(gd_atk, gd_atk_bench)
	var rc_holder3 := _make_mon("N01_Holder3", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 40)
	rc_holder3.held_item = item
	rc_holder3.add_move(tackle)

	var switches3 := []
	var triggered3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.forced_switch.connect(func(o, n): switches3.push_back([o, n]))
	bm3.ability_triggered.connect(func(m, a): triggered3.push_back([m, a]))
	bm3.start_battle_with_parties(gd_atk_party, BattleParty.single(rc_holder3))
	_chk("N01.07 Guard Dog on the attacker BLOCKS the forced switch",
			not switches3.any(func(e): return e[0] == gd_atk))
	_chk("N01.08 Guard Dog's block still emits ability_triggered 'guard_dog'",
			triggered3.any(func(e): return e[0] == gd_atk and e[1] == "guard_dog"))
	_chk("N01.09 CORRECTION-confirming: the item still CONSUMES even though Guard " +
			"Dog blocked the switch itself -- a different outcome than the " +
			"no-valid-target case (N01.11)",
			rc_holder3.held_item == null)
	bm3.queue_free()

	# No-valid-target edge case: the attacker has NO bench (single-member
	# party) -> Red Card does NOT activate/consume at all, confirmed distinct
	# from the Guard-Dog case above (that one still consumes).
	var atk4 := _make_mon("N01_Atk4", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk4.add_move(tackle)
	var rc_holder4 := _make_mon("N01_Holder4", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 40)
	rc_holder4.held_item = item
	rc_holder4.add_move(tackle)

	var switches4 := []
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4.forced_switch.connect(func(o, n): switches4.push_back([o, n]))
	bm4.start_battle_with_parties(BattleParty.single(atk4), BattleParty.single(rc_holder4))
	_chk("N01.10 no-valid-target: the attacker's party has no bench -> no forced switch",
			not switches4.any(func(e): return e[0] == atk4))
	_chk("N01.11 no-valid-target: the item is NOT consumed (no activation at all, " +
			"unlike the Guard-Dog case)",
			rc_holder4.held_item == item)
	bm4.queue_free()

	# Attacker-alive requirement: an attacker that faints from its OWN recoil
	# (Double-Edge, 33%) in the very same hit resolution does not get forced
	# to switch, and the item is NOT consumed -- confirmed via
	# !IsBattlerAlive(battlerAtk) in TryRedCard's own gate list.
	var double_edge := _load_move(38)
	var rc_atk5 := _make_mon("N01_RecoilAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	rc_atk5.add_move(double_edge)
	rc_atk5.current_hp = 5  # far less than 33% recoil of a Double-Edge hit will produce
	var rc_atk5_bench := _make_mon("N01_RecoilAtkBench", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 20)
	var rc_atk5_party := _two_member_party(rc_atk5, rc_atk5_bench)
	var rc_holder5 := _make_mon("N01_Holder5", TypeChart.TYPE_NORMAL, 250, 60, 60, 60, 60, 40)
	rc_holder5.held_item = item
	rc_holder5.add_move(double_edge)

	var switches5 := []
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5.forced_switch.connect(func(o, n): switches5.push_back([o, n]))
	bm5.start_battle_with_parties(rc_atk5_party, BattleParty.single(rc_holder5))
	_chk("N01.12 fixture check: the attacker fainted from its own Double-Edge recoil " +
			"before Red Card's check would run",
			rc_atk5.fainted)
	_chk("N01.13 CORRECTION-confirming: an attacker that faints from its own recoil " +
			"is never forced to switch by Red Card",
			not switches5.any(func(e): return e[0] == rc_atk5))
	_chk("N01.14 CORRECTION-confirming: the item is NOT consumed when the attacker " +
			"is already dead (a third distinct 'no switch' outcome)",
			rc_holder5.held_item == item)
	bm5.queue_free()


# ── N02: Eject Button (501) ──────────────────────────────────────────────────────
func _test_n02_eject_button() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_EJECT_BUTTON)
	_chk("N02.01 Eject Button hold_effect == HOLD_EFFECT_EJECT_BUTTON(100)",
			item.hold_effect == ItemManager.HOLD_EFFECT_EJECT_BUTTON)

	var holder := _make_mon("N02_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("N02.02 direct: holds_eject_button == true when holding Eject Button",
			ItemManager.holds_eject_button(holder))
	var bare := _make_mon("N02_Bare", TypeChart.TYPE_NORMAL)
	_chk("N02.03 discriminator: holding nothing -> false",
			not ItemManager.holds_eject_button(bare))

	var tackle := _load_move(33)

	# Full-battle: the ATTACKER hits the Eject Button HOLDER; the HOLDER
	# ITSELF (not the attacker) is forced to switch -- the opposite direction
	# from Red Card (N01.04).
	var atk1 := _make_mon("N02_Atk1", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk1.add_move(tackle)
	var eb_holder1 := _make_mon("N02_Holder1", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 40)
	eb_holder1.held_item = item
	eb_holder1.add_move(tackle)
	var eb_holder1_bench := _make_mon("N02_Holder1Bench", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 20)
	var eb_party1 := _two_member_party(eb_holder1, eb_holder1_bench)

	var switches1 := []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.forced_switch.connect(func(o, n): switches1.push_back([o, n]))
	bm1.start_battle_with_parties(BattleParty.single(atk1), eb_party1)
	_chk("N02.04 full-battle: Eject Button forces the HOLDER itself (not the attacker) " +
			"to switch",
			switches1.any(func(e): return e[0] == eb_holder1 and e[1] == eb_holder1_bench))
	_chk("N02.05 the holder's Eject Button is consumed",
			eb_holder1.held_item == null)
	bm1.queue_free()

	# Discriminator: no Eject Button held -> no forced switch.
	var atk2 := _make_mon("N02_Atk2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk2.add_move(tackle)
	var plain_holder2 := _make_mon("N02_Holder2", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 40)
	plain_holder2.add_move(tackle)
	var plain_holder2_bench := _make_mon("N02_Holder2Bench", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 20)
	var plain_party2 := _two_member_party(plain_holder2, plain_holder2_bench)

	var switches2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.forced_switch.connect(func(o, n): switches2.push_back([o, n]))
	bm2.start_battle_with_parties(BattleParty.single(atk2), plain_party2)
	_chk("N02.06 discriminator: no Eject Button held -> the holder is never forced to switch",
			not switches2.any(func(e): return e[0] == plain_holder2))
	bm2.queue_free()

	# Guard Dog non-interaction: unlike Red Card, a Guard Dog HOLDER is still
	# ejected -- confirmed absent from TryEjectButton's own source.
	var guard_dog := _load_ability(275)
	var atk3 := _make_mon("N02_Atk3", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk3.add_move(tackle)
	var gd_holder3 := _make_mon("N02_GDHolder3", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 40)
	gd_holder3.ability = guard_dog
	gd_holder3.held_item = item
	gd_holder3.add_move(tackle)
	var gd_holder3_bench := _make_mon("N02_GDHolder3Bench", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 20)
	var gd_party3 := _two_member_party(gd_holder3, gd_holder3_bench)

	var switches3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.forced_switch.connect(func(o, n): switches3.push_back([o, n]))
	bm3.start_battle_with_parties(BattleParty.single(atk3), gd_party3)
	_chk("N02.07 CORRECTION-confirming: Guard Dog does NOT block Eject Button -- the " +
			"holder is still forced out despite holding the ability that blocks Red " +
			"Card (N01.07)",
			switches3.any(func(e): return e[0] == gd_holder3 and e[1] == gd_holder3_bench))
	bm3.queue_free()

	# Magic Guard non-interaction: confirmed via source (neither TryRedCard nor
	# TryEjectButton references ABILITY_MAGIC_GUARD) -- a Magic Guard holder
	# is still ejected normally, since forced switching deals no damage for
	# Magic Guard to have anything to block.
	var magic_guard := _load_ability(98)
	var atk4 := _make_mon("N02_Atk4", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk4.add_move(tackle)
	var mg_holder4 := _make_mon("N02_MGHolder4", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 40)
	mg_holder4.ability = magic_guard
	mg_holder4.held_item = item
	mg_holder4.add_move(tackle)
	var mg_holder4_bench := _make_mon("N02_MGHolder4Bench", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 20)
	var mg_party4 := _two_member_party(mg_holder4, mg_holder4_bench)

	var switches4 := []
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4.forced_switch.connect(func(o, n): switches4.push_back([o, n]))
	bm4.start_battle_with_parties(BattleParty.single(atk4), mg_party4)
	_chk("N02.08 Magic Guard non-interaction: a Magic Guard holder is still forced " +
			"to switch normally",
			switches4.any(func(e): return e[0] == mg_holder4 and e[1] == mg_holder4_bench))
	bm4.queue_free()
