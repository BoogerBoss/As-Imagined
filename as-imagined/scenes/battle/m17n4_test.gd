extends Node

# M17n-4 test suite — Group 7: type-mutation/choice-lock cheap reuses. Continues the
# m17n<N> numeral-suffix naming convention. This tier was originally queued to run
# BEFORE [M17n-5] but didn't — see docs/decisions.md's [M17n-3] follow-up and [M17n-5]
# entries for the flagged gap this file finally closes.
#
# Scope: 5 abilities (not 6 — RKS System (225) excluded per Rob's explicit decision,
# recorded in memory, not implemented here):
#   Color Change (16)    — hit-reactive type mutation (AbilityManager.try_hit_reactive_effects)
#   Protean (168)         — pre-move self type mutation, once per switch-in stint
#   Libero (236)          — confirmed genuinely identical mechanism to Protean
#   Multitype (121)       — switch-in-only type set from a held Plate item (NOT
#                           live-updating on a mid-battle held-item change — a real
#                           correction to this tier's own recon, confirmed by checking
#                           source's FORM_CHANGE_ITEM_HOLD dispatch, not assumed)
#   Gorilla Tactics (255) — reuses the EXISTING choice_locked_move field (same storage
#                           slot as an actual Choice item, confirmed via source) +
#                           physical-move base power x1.5, confirmed to compose
#                           multiplicatively with an actual Choice item (2.25x total)
#
# All five reuse pre-existing infrastructure with ZERO new BattleManager mechanisms:
# _set_mon_type/_reset_mon_type/BattlePokemon.original_types (Color Change/Protean/
# Libero/Multitype) and BattlePokemon.choice_locked_move (Gorilla Tactics).
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Pairwise damage comparisons force BOTH _force_roll and _force_crit.
#   - Signal-snapshot, not post-battle state, for anything that could re-trigger or
#     that a switch/extra turn could invalidate.
#   - Type immunity precedes ability logic: Ghost-vs-Normal used DELIBERATELY in S2 to
#     prove Color Change does NOT fire on an immune (0-damage) hit — the one place in
#     this file where the immunity is the point of the test, not a pitfall to avoid.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_color_change()
	_test_section_3_protean()
	_test_section_4_libero()
	_test_section_5_multitype()
	_test_section_6_gorilla_tactics()
	_test_section_7_mold_breaker()
	_test_section_8_neutralizing_gas()
	_test_section_9_negative_control()

	var total := _pass + _fail
	print("m17n4_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, types: Array[int], hp: int = 100, atk: int = 80,
		def_stat: int = 80, spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


func _synth_move(power: int = 40, category: int = 0, move_type: int = TypeChart.TYPE_NORMAL) -> MoveData:
	var m := MoveData.new()
	m.type = move_type
	m.category = category
	m.power = power
	m.accuracy = 100
	return m


func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var color_change := _load_ability(16)
	_chk("S1.01 Color Change id=16, NOT breakable (re-verified narrowly — source has " +
			"no breakable flag on this entry at all)",
			color_change.ability_id == 16 and not color_change.breakable)

	var protean := _load_ability(168)
	_chk("S1.02 Protean id=168, NOT breakable", protean.ability_id == 168 and not protean.breakable)

	var libero := _load_ability(236)
	_chk("S1.03 Libero id=236, NOT breakable", libero.ability_id == 236 and not libero.breakable)

	var multitype := _load_ability(121)
	_chk("S1.04 Multitype id=121, cant_be_copied/swapped/traced/suppressed/overwritten " +
			"all TRUE",
			multitype.ability_id == 121 and multitype.cant_be_copied and multitype.cant_be_swapped
			and multitype.cant_be_traced and multitype.cant_be_suppressed
			and multitype.cant_be_overwritten)

	var gorilla_tactics := _load_ability(255)
	_chk("S1.05 Gorilla Tactics id=255, NOT breakable, no cant_be_* flags",
			gorilla_tactics.ability_id == 255 and not gorilla_tactics.breakable
			and not gorilla_tactics.cant_be_suppressed)

	# RKS System (225) is intentionally NOT implemented this tier — excluded per Rob's
	# explicit decision (recorded in memory). No .tres entry expected/checked for it.


# ── Section 2: Color Change ───────────────────────────────────────────────────

func _test_section_2_color_change() -> void:
	var color_change := _load_ability(16)
	var water_gun := _load_move(55)    # WATER, special
	var ember := _load_move(52)        # FIRE, special
	var night_shade := _load_move(101) # GHOST, special, level_damage — 0 dmg vs Normal
	var tackle := _load_move(33)       # NORMAL, physical

	# S2.01: type changes to match an incoming damaging move's type.
	var defender := _make_mon("CCDefender", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 100)
	defender.ability = color_change
	defender.add_move(tackle)
	var attacker := _make_mon("CCAttacker1", [TypeChart.TYPE_WATER], 300, 60, 40, 60, 40, 50)
	attacker.add_move(water_gun)

	var type_changes: Array = []
	var triggered: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	bm.type_changed.connect(func(p, t): type_changes.append([p, t]))
	bm.ability_triggered.connect(func(m, tag): triggered.append([m, tag]))
	bm.queue_move(0, 0)
	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(defender))
	bm.queue_free()

	_chk("S2.01 Color Change: type changes to match the incoming Water move",
			type_changes.size() >= 1 and type_changes[0][0] == defender
			and type_changes[0][1] == TypeChart.TYPE_WATER)
	_chk("S2.02 the 'color_change' ability_triggered signal fired",
			triggered.any(func(e): return e[0] == defender and e[1] == "color_change"))

	# S2.03: does NOT change on an immune (0-damage) hit — Ghost vs Normal-type
	# defender is a flat 0x immunity, deliberately used here as the point of the test.
	var defender2 := _make_mon("CCDefender2", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 100)
	defender2.ability = color_change
	defender2.add_move(tackle)
	var attacker2 := _make_mon("CCAttacker2", [TypeChart.TYPE_GHOST], 300, 60, 40, 60, 40, 50)
	attacker2.add_move(night_shade)

	var type_changes2: Array = []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.type_changed.connect(func(p, t): type_changes2.append([p, t]))
	bm2.queue_move(0, 0)
	bm2.start_battle_with_parties(BattleParty.single(attacker2), BattleParty.single(defender2))
	bm2.queue_free()

	_chk("S2.03 discriminator: Color Change does NOT fire on a Ghost-vs-Normal " +
			"immune (0-damage) hit",
			type_changes2.is_empty())
	_chk("S2.04 defender2 remains Normal-type (unaffected)",
			defender2.species.types[0] == TypeChart.TYPE_NORMAL)

	# S2.05: a second hit of a DIFFERENT type changes it again (not stacked/dual-typed).
	var defender3 := _make_mon("CCDefender3", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 30)
	defender3.ability = color_change
	defender3.add_move(tackle)
	var attacker3 := _make_mon("CCAttacker3", [TypeChart.TYPE_WATER], 300, 60, 40, 60, 40, 100)
	attacker3.add_move(water_gun)
	attacker3.add_move(ember)

	var type_changes3: Array = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.type_changed.connect(func(p, t):
		if p == defender3:
			type_changes3.append(t))
	bm3.queue_move(0, 0)  # turn 1: Water Gun -> defender3 becomes Water
	bm3.queue_move(0, 1)  # turn 2: Ember -> defender3 becomes Fire
	bm3.start_battle_with_parties(BattleParty.single(attacker3), BattleParty.single(defender3))
	bm3.queue_free()

	# Only 2 moves were queued (Water Gun, Ember) — once the queue drains, the battle
	# keeps running and attacker3 auto-selects moves[0] (Water Gun) again for as many
	# further turns as it takes to resolve (CLAUDE.md's documented "repeatable-effect
	# auto-select" pitfall), so a 3rd, 4th, etc. type_changed event for this same
	# defender is expected and not itself informative. Check the first two events only.
	_chk("S2.05 a second hit of a different type re-triggers Color Change " +
			"(Water then Fire, not stacked)",
			type_changes3.size() >= 2 and type_changes3[0] == TypeChart.TYPE_WATER
			and type_changes3[1] == TypeChart.TYPE_FIRE)

	# S2.06: direct function-level Struggle exclusion (cheaper than depleting real PP
	# in a full battle to force Struggle).
	var struggle_move := MoveData.new()
	struggle_move.type = TypeChart.TYPE_MYSTERY
	struggle_move.category = 0
	struggle_move.power = 50
	struggle_move.is_struggle = true
	var cc_mon := _make_mon("CCStruggleTarget", [TypeChart.TYPE_NORMAL])
	cc_mon.ability = color_change
	var struggle_result: Dictionary = AbilityManager.try_hit_reactive_effects(
			attacker, cc_mon, struggle_move, 10, cc_mon.max_hp, false, null, false)
	_chk("S2.06 Color Change does not fire from Struggle",
			struggle_result["color_change_new_type"] == TypeChart.TYPE_NONE)

	# S2.07 negative control: an ordinary Pokemon's type is unaffected by the same hit.
	var plain_defender := _make_mon("CCPlain", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 100)
	plain_defender.add_move(tackle)
	var plain_attacker := _make_mon("CCPlainAttacker", [TypeChart.TYPE_WATER], 300, 60, 40, 60, 40, 50)
	plain_attacker.add_move(water_gun)
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4._force_roll = 100
	bm4._force_crit = false
	bm4.queue_move(0, 0)
	bm4.start_battle_with_parties(BattleParty.single(plain_attacker), BattleParty.single(plain_defender))
	bm4.queue_free()
	_chk("S2.07 negative control: non-Color-Change defender keeps its Normal type",
			plain_defender.species.types[0] == TypeChart.TYPE_NORMAL)


# ── Section 3: Protean ────────────────────────────────────────────────────────

func _test_section_3_protean() -> void:
	var protean := _load_ability(168)
	var ember := _load_move(52)      # FIRE
	var water_gun := _load_move(55)  # WATER
	var tackle := _load_move(33)     # NORMAL

	# Direct function-level checks.
	var p_mon := _make_mon("ProteanUnit", [TypeChart.TYPE_NORMAL])
	p_mon.ability = protean
	_chk("S3.01 protean_new_type: returns the move's type on first use",
			AbilityManager.protean_new_type(p_mon, ember, false) == TypeChart.TYPE_FIRE)

	p_mon.used_protean_libero = true
	_chk("S3.02 protean_new_type: returns TYPE_NONE once already used this stint",
			AbilityManager.protean_new_type(p_mon, ember, false) == TypeChart.TYPE_NONE)

	p_mon.used_protean_libero = false
	var struggle_move := MoveData.new()
	struggle_move.type = TypeChart.TYPE_MYSTERY
	struggle_move.is_struggle = true
	_chk("S3.03 protean_new_type: returns TYPE_NONE for Struggle",
			AbilityManager.protean_new_type(p_mon, struggle_move, false) == TypeChart.TYPE_NONE)

	var already_fire := _make_mon("ProteanAlreadyFire", [TypeChart.TYPE_FIRE])
	already_fire.ability = protean
	_chk("S3.04 protean_new_type: returns TYPE_NONE when already exactly that type",
			AbilityManager.protean_new_type(already_fire, ember, false) == TypeChart.TYPE_NONE)

	_chk("S3.05 protean_new_type: null guards",
			AbilityManager.protean_new_type(null, ember, false) == TypeChart.TYPE_NONE
			and AbilityManager.protean_new_type(p_mon, null, false) == TypeChart.TYPE_NONE)

	var non_protean := _make_mon("NonProteanUnit", [TypeChart.TYPE_NORMAL])
	_chk("S3.06 protean_new_type: TYPE_NONE for a Pokemon without Protean/Libero",
			AbilityManager.protean_new_type(non_protean, ember, false) == TypeChart.TYPE_NONE)

	# S3.07/S3.08: full-battle — type changes on first move use; does NOT change
	# again on a second move use in the same stint (signal-snapshot, not post-battle
	# state, since the battle may run more turns than the two under direct test).
	var user := _make_mon("ProteanUser", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 100)
	user.ability = protean
	user.add_move(ember)
	user.add_move(water_gun)
	var opp := _make_mon("ProteanOpp", [TypeChart.TYPE_NORMAL], 300, 5, 200, 5, 200, 30)
	opp.add_move(tackle)

	var type_changes: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	bm.type_changed.connect(func(p, t):
		if p == user:
			type_changes.append(t))
	bm.queue_move(0, 0)  # turn 1: Ember -> user becomes Fire
	bm.queue_move(0, 1)  # turn 2: Water Gun -> should NOT change (already used this stint)
	bm.start_battle_with_parties(BattleParty.single(user), BattleParty.single(opp))
	bm.queue_free()

	_chk("S3.07 Protean changes the user's type to match its own move on first use",
			type_changes.size() >= 1 and type_changes[0] == TypeChart.TYPE_FIRE)
	_chk("S3.08 discriminator: no second type_changed fires on the second move use " +
			"in the same switch-in stint",
			type_changes.size() == 1)

	# S3.09: resets after switching out and back in — can trigger again.
	var user2 := _make_mon("ProteanUser2", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 100)
	user2.ability = protean
	user2.add_move(ember)
	var bench := _make_mon("ProteanBench", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 50)
	bench.add_move(tackle)
	var opp2 := _make_mon("ProteanOpp2", [TypeChart.TYPE_NORMAL], 400, 5, 200, 5, 200, 20)
	opp2.add_move(tackle)

	var player_party := BattleParty.new()
	player_party.members = [user2, bench]
	player_party.active_index = 0

	var type_changes2: Array = []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.type_changed.connect(func(p, t):
		if p == user2:
			type_changes2.append(t))
	bm2.queue_move(0, 0)    # turn 1: Ember -> user2 becomes Fire (protean fires)
	bm2.queue_switch(0, 1)  # turn 2: user2 switches out to bench
	bm2.queue_switch(0, 0)  # turn 3: bench switches out, user2 switches back in
	bm2.queue_move(0, 0)    # turn 4: Ember again -> should fire AGAIN (stint reset)
	bm2.start_battle_with_parties(player_party, BattleParty.single(opp2))
	bm2.queue_free()

	_chk("S3.09 Protean fires again after a switch-out/switch-in cycle (stint reset, " +
			"not once-per-whole-battle despite source's own loosely-worded comment)",
			type_changes2.size() == 2 and type_changes2[0] == TypeChart.TYPE_FIRE
			and type_changes2[1] == TypeChart.TYPE_FIRE)


# ── Section 4: Libero ─────────────────────────────────────────────────────────

func _test_section_4_libero() -> void:
	var libero := _load_ability(236)
	var ember := _load_move(52)
	var tackle := _load_move(33)

	# Direct: confirmed genuinely the same mechanism as Protean, not just a
	# flavor-text twin — same protean_new_type function, same gate.
	var l_mon := _make_mon("LiberoUnit", [TypeChart.TYPE_NORMAL])
	l_mon.ability = libero
	_chk("S4.01 protean_new_type: Libero behaves identically to Protean on first use",
			AbilityManager.protean_new_type(l_mon, ember, false) == TypeChart.TYPE_FIRE)

	l_mon.used_protean_libero = true
	_chk("S4.02 protean_new_type: Libero also gated by used_protean_libero",
			AbilityManager.protean_new_type(l_mon, ember, false) == TypeChart.TYPE_NONE)

	# Full-battle confirmation + correct ability_triggered tag ("libero", not "protean").
	var user := _make_mon("LiberoUser", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 100)
	user.ability = libero
	user.add_move(ember)
	var opp := _make_mon("LiberoOpp", [TypeChart.TYPE_NORMAL], 300, 5, 200, 5, 200, 30)
	opp.add_move(tackle)

	var type_changes: Array = []
	var triggered: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	bm.type_changed.connect(func(p, t):
		if p == user:
			type_changes.append(t))
	bm.ability_triggered.connect(func(m, tag): triggered.append([m, tag]))
	bm.queue_move(0, 0)
	bm.start_battle_with_parties(BattleParty.single(user), BattleParty.single(opp))
	bm.queue_free()

	_chk("S4.03 Libero changes the user's type to match its own move",
			type_changes.size() >= 1 and type_changes[0] == TypeChart.TYPE_FIRE)
	_chk("S4.04 the ability_triggered tag is 'libero', not 'protean'",
			triggered.any(func(e): return e[0] == user and e[1] == "libero"))


# ── Section 5: Multitype ──────────────────────────────────────────────────────

func _test_section_5_multitype() -> void:
	var multitype := _load_ability(121)
	var magician := _load_ability(170)
	var tackle := _load_move(33)
	var iron_plate := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_STEEL)

	# S5.01: type set from the held Plate item at switch-in.
	var mt_mon := _make_mon("MultitypeUnit", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 50)
	mt_mon.ability = multitype
	mt_mon.held_item = iron_plate
	mt_mon.add_move(tackle)
	var opp1 := _make_mon("MTOpp1", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 30)
	opp1.add_move(tackle)
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.start_battle_with_parties(BattleParty.single(mt_mon), BattleParty.single(opp1))
	bm1.queue_free()
	_chk("S5.01 Multitype's type is set from the held Iron Plate (Steel) at switch-in",
			mt_mon.species.types[0] == TypeChart.TYPE_STEEL)

	# S5.02: no Plate -> stays the natural species type.
	var mt_mon2 := _make_mon("MultitypeNoPlate", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 50)
	mt_mon2.ability = multitype
	mt_mon2.add_move(tackle)
	var opp2 := _make_mon("MTOpp2", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 30)
	opp2.add_move(tackle)
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.start_battle_with_parties(BattleParty.single(mt_mon2), BattleParty.single(opp2))
	bm2.queue_free()
	_chk("S5.02 Multitype with no held Plate keeps its natural species type",
			mt_mon2.species.types[0] == TypeChart.TYPE_NORMAL)

	# S5.03 negative control: a Plate alone (no Multitype ability) does nothing.
	var plain_holder := _make_mon("PlainPlateHolder", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 50)
	plain_holder.held_item = _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_STEEL)
	plain_holder.add_move(tackle)
	var opp3 := _make_mon("MTOpp3", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 30)
	opp3.add_move(tackle)
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.start_battle_with_parties(BattleParty.single(plain_holder), BattleParty.single(opp3))
	bm3.queue_free()
	_chk("S5.03 negative control: a Plate holder without Multitype is unaffected",
			plain_holder.species.types[0] == TypeChart.TYPE_NORMAL)

	# S5.04: does NOT live-update on a mid-battle held-item change. Confirmed via
	# source that FORM_CHANGE_ITEM_HOLD is an overworld-only trigger, never dispatched
	# from any in-battle FORM_CHANGE_BATTLE_* call — so a real in-battle item theft
	# (this project's own Magician, M17j) should NOT retype the Multitype holder.
	var mt_mon4 := _make_mon("MultitypeStolen", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 30)
	mt_mon4.ability = multitype
	mt_mon4.held_item = _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_STEEL)
	mt_mon4.add_move(tackle)
	var thief := _make_mon("MagicianThief", [TypeChart.TYPE_NORMAL], 300, 60, 40, 40, 40, 100)
	thief.ability = magician
	thief.add_move(tackle)

	var item_events: Array = []
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4._force_roll = 100
	bm4._force_crit = false
	bm4.item_transferred.connect(func(_f, _t, item): item_events.append(item))
	bm4.queue_move(0, 0)
	bm4.start_battle_with_parties(BattleParty.single(thief), BattleParty.single(mt_mon4))
	bm4.queue_free()

	_chk("S5.04 setup check: Magician actually stole the Plate (held_item now null)",
			item_events.size() == 1 and mt_mon4.held_item == null)
	_chk("S5.04 Multitype's type is UNCHANGED after losing its Plate mid-battle " +
			"(no re-switch has happened)",
			mt_mon4.species.types[0] == TypeChart.TYPE_STEEL)


# ── Section 6: Gorilla Tactics ────────────────────────────────────────────────

func _test_section_6_gorilla_tactics() -> void:
	var gorilla_tactics := _load_ability(255)
	var tackle := _load_move(33)     # NORMAL, physical
	var water_gun := _load_move(55)  # WATER, special

	# S6.01: locks the holder into its first-used move.
	var gt_mon := _make_mon("GTUser", [TypeChart.TYPE_NORMAL], 300, 60, 40, 60, 40, 100)
	gt_mon.ability = gorilla_tactics
	gt_mon.add_move(tackle)
	gt_mon.add_move(water_gun)
	var opp := _make_mon("GTOpp", [TypeChart.TYPE_NORMAL], 400, 5, 200, 5, 200, 30)
	opp.add_move(tackle)
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	bm.queue_move(0, 0)
	bm.start_battle_with_parties(BattleParty.single(gt_mon), BattleParty.single(opp))
	bm.queue_free()
	_chk("S6.01 Gorilla Tactics locks the holder into its first-used move",
			gt_mon.choice_locked_move == tackle)

	# S6.02/S6.03: physical-move base power x1.5; NOT applied to a special move.
	var boost_holder := _make_mon("GTBoostHolder", [TypeChart.TYPE_NORMAL])
	boost_holder.ability = gorilla_tactics
	var target := _make_mon("GTTarget", [TypeChart.TYPE_NORMAL])
	var phys_move := _synth_move(60, 0)
	var spec_move := _synth_move(60, 1)

	var boosted: Dictionary = DamageCalculator.calculate(boost_holder, target, phys_move, 100, false)
	var plain_holder := _make_mon("GTPlain", [TypeChart.TYPE_NORMAL])
	var unboosted: Dictionary = DamageCalculator.calculate(plain_holder, target, phys_move, 100, false)
	_chk("S6.02 Gorilla Tactics boosts a physical move's damage",
			boosted["damage"] > unboosted["damage"])

	var spec_boosted: Dictionary = DamageCalculator.calculate(boost_holder, target, spec_move, 100, false)
	var spec_unboosted: Dictionary = DamageCalculator.calculate(plain_holder, target, spec_move, 100, false)
	_chk("S6.03 discriminator: Gorilla Tactics does NOT boost a special move",
			spec_boosted["damage"] == spec_unboosted["damage"])

	# S6.04: composition with an actual Choice item — stacks multiplicatively to
	# 2.25x, confirmed from source's own test
	# ("stacks with Choice Band to reach 2.25x Attack"). The two boosts occupy
	# genuinely different pipeline stages in this project (ItemManager's attack-STAT
	# modifier vs. AbilityManager's base-power modifier), so this is a real
	# integration check that they compose correctly, not just a restated assumption.
	var band_holder := _make_mon("GTBandHolder", [TypeChart.TYPE_NORMAL])
	band_holder.ability = gorilla_tactics
	band_holder.held_item = _make_item(ItemManager.HOLD_EFFECT_CHOICE_BAND)
	var band_only := _make_mon("GTBandOnly", [TypeChart.TYPE_NORMAL])
	band_only.held_item = _make_item(ItemManager.HOLD_EFFECT_CHOICE_BAND)

	var both: Dictionary = DamageCalculator.calculate(band_holder, target, phys_move, 100, false)
	var band_alone: Dictionary = DamageCalculator.calculate(band_only, target, phys_move, 100, false)
	var neither: Dictionary = DamageCalculator.calculate(plain_holder, target, phys_move, 100, false)
	# both/neither should be 2.25x (within integer-rounding tolerance); band_alone/neither
	# should be 1.5x alone — confirming the extra factor really is Gorilla Tactics' own
	# 1.5x on top of the item's 1.5x, not some other coincidental ratio.
	_chk("S6.04 Gorilla Tactics + Choice Band together deal MORE than Choice Band alone",
			both["damage"] > band_alone["damage"])
	_chk("S6.05 composition is multiplicative (~2.25x vs ~1.5x baseline, not additive " +
			"or capped at either single boost)",
			both["damage"] >= band_alone["damage"] * 3 / 2)

	# S6.06 negative control: an ordinary Pokemon with a Choice Band alone gets only
	# the item's 1.5x, matching the plain Choice Band precedent from item_test.tscn.
	_chk("S6.06 negative control: Choice Band alone (no Gorilla Tactics) does not " +
			"reach Gorilla Tactics' extra boost",
			band_alone["damage"] < both["damage"] and band_alone["damage"] > neither["damage"])


# ── Section 7: Mold Breaker non-bypass ────────────────────────────────────────
# None of this tier's five abilities carry a breakable flag in source (re-verified
# narrowly per Section 1) — confirm Mold Breaker does NOT bypass any of them, using
# Color Change and Multitype as representative cases (a hit-reactive trigger and a
# switch-in effect).

func _test_section_7_mold_breaker() -> void:
	var mold_breaker := _load_ability(104)
	var color_change := _load_ability(16)
	var multitype := _load_ability(121)
	var water_gun := _load_move(55)
	var tackle := _load_move(33)

	var mb_attacker := _make_mon("MBAttackerN4", [TypeChart.TYPE_WATER], 300, 60, 40, 60, 40, 100)
	mb_attacker.ability = mold_breaker
	mb_attacker.add_move(water_gun)
	var cc_target := _make_mon("MBCCTarget", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 30)
	cc_target.ability = color_change
	cc_target.add_move(tackle)

	var type_changes: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	bm.type_changed.connect(func(p, t):
		if p == cc_target:
			type_changes.append(t))
	bm.queue_move(0, 0)
	bm.start_battle_with_parties(BattleParty.single(mb_attacker), BattleParty.single(cc_target))
	bm.queue_free()
	_chk("S7.01 Mold Breaker does NOT bypass Color Change (no breakable flag in " +
			"source — still fires normally against a Mold Breaker attacker)",
			type_changes.size() == 1 and type_changes[0] == TypeChart.TYPE_WATER)

	# Multitype: Mold Breaker's bypass is a defender-role, per-hit concept; Multitype
	# fires at switch-in with no "attacker" in play at all, so it's unaffected by
	# construction, not by a special-cased exemption.
	var mt_mon := _make_mon("MBMultitypeUnit", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 50)
	mt_mon.ability = multitype
	mt_mon.held_item = _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_STEEL)
	mt_mon.add_move(tackle)
	var mb_opp := _make_mon("MBOppN4", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 30)
	mb_opp.ability = mold_breaker
	mb_opp.add_move(tackle)
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.start_battle_with_parties(BattleParty.single(mt_mon), BattleParty.single(mb_opp))
	bm2.queue_free()
	_chk("S7.02 Multitype is unaffected by an opposing Mold Breaker",
			mt_mon.species.types[0] == TypeChart.TYPE_STEEL)


# ── Section 8: Neutralizing Gas ───────────────────────────────────────────────
# Color Change/Protean/Libero/Gorilla Tactics have no cant_be_suppressed flag — NG
# should suppress all four normally. Multitype has cant_be_suppressed=TRUE — NG
# should NOT suppress it. This asymmetry is the key cross-ability finding for this
# section, not incidental coverage.

func _test_section_8_neutralizing_gas() -> void:
	var neutralizing_gas := _load_ability(256)
	var color_change := _load_ability(16)
	var protean := _load_ability(168)
	var gorilla_tactics := _load_ability(255)
	var multitype := _load_ability(121)
	var water_gun := _load_move(55)
	var ember := _load_move(52)
	var tackle := _load_move(33)

	# Color Change suppressed.
	var cc_mon := _make_mon("NGCCUnit", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 30)
	cc_mon.ability = color_change
	cc_mon.add_move(tackle)
	var ng_attacker := _make_mon("NGAttacker1", [TypeChart.TYPE_WATER], 300, 60, 40, 60, 40, 100)
	ng_attacker.ability = neutralizing_gas
	ng_attacker.add_move(water_gun)
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.queue_move(0, 0)
	bm1.start_battle_with_parties(BattleParty.single(ng_attacker), BattleParty.single(cc_mon))
	bm1.queue_free()
	_chk("S8.01 Neutralizing Gas suppresses Color Change",
			cc_mon.species.types[0] == TypeChart.TYPE_NORMAL)

	# Protean suppressed.
	var protean_mon := _make_mon("NGProteanUnit", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 100)
	protean_mon.ability = protean
	protean_mon.add_move(ember)
	var ng_opp2 := _make_mon("NGOpp2", [TypeChart.TYPE_NORMAL], 300, 5, 200, 5, 200, 30)
	ng_opp2.ability = neutralizing_gas
	ng_opp2.add_move(tackle)
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.queue_move(0, 0)
	bm2.start_battle_with_parties(BattleParty.single(protean_mon), BattleParty.single(ng_opp2))
	bm2.queue_free()
	_chk("S8.02 Neutralizing Gas suppresses Protean",
			protean_mon.species.types[0] == TypeChart.TYPE_NORMAL)

	# Gorilla Tactics suppressed (choice-lock no longer set from the ability half —
	# confirmed via effective_ability_id directly, cheaper than a full battle).
	var gt_mon := _make_mon("NGGTUnit", [TypeChart.TYPE_NORMAL])
	gt_mon.ability = gorilla_tactics
	_chk("S8.03 Neutralizing Gas suppresses Gorilla Tactics (effective_ability_id " +
			"no longer resolves to it)",
			AbilityManager.effective_ability_id(gt_mon, true) != AbilityManager.ABILITY_GORILLA_TACTICS)

	# Multitype NOT suppressed — cant_be_suppressed=true.
	var mt_mon := _make_mon("NGMultitypeUnit", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 50)
	mt_mon.ability = multitype
	mt_mon.held_item = _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_STEEL)
	mt_mon.add_move(tackle)
	var ng_opp3 := _make_mon("NGOpp3", [TypeChart.TYPE_NORMAL], 300, 40, 40, 40, 40, 30)
	ng_opp3.ability = neutralizing_gas
	ng_opp3.add_move(tackle)
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.start_battle_with_parties(BattleParty.single(mt_mon), BattleParty.single(ng_opp3))
	bm3.queue_free()
	_chk("S8.04 Neutralizing Gas does NOT suppress Multitype (cant_be_suppressed=true)",
			mt_mon.species.types[0] == TypeChart.TYPE_STEEL)


# ── Section 9: Negative control ───────────────────────────────────────────────

func _test_section_9_negative_control() -> void:
	var tackle := _load_move(33)
	var water_gun := _load_move(55)

	var plain := _make_mon("N4NegControl", [TypeChart.TYPE_NORMAL], 300, 60, 40, 60, 40, 100)
	plain.add_move(tackle)
	plain.add_move(water_gun)
	var opp := _make_mon("N4NegOpp", [TypeChart.TYPE_NORMAL], 400, 5, 200, 5, 200, 30)
	opp.add_move(tackle)

	var type_changes: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	bm.type_changed.connect(func(p, t):
		if p == plain:
			type_changes.append(t))
	bm.queue_move(0, 0)
	bm.start_battle_with_parties(BattleParty.single(plain), BattleParty.single(opp))
	bm.queue_free()

	_chk("S9.01 negative control: an ordinary Pokemon with none of this tier's " +
			"abilities never has its type changed",
			type_changes.is_empty())
	_chk("S9.02 negative control: an ordinary Pokemon is never choice-locked without " +
			"a Choice item or Gorilla Tactics",
			plain.choice_locked_move == null)
