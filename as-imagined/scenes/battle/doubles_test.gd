extends Node

# Milestone 14a + 14b test suite — Doubles (state machine, spread moves, ally effects)
#
# Sections:
#   D1: BattleParty doubles API + BattleManager 4-combatant setup
#   D2: Turn order — 4 distinct speeds, correct priority across all 4 combatants
#   D3: Battle ends only when a FULL SIDE is fainted (not just one field slot)
#   D4: Targeting — queue_move_targeted sends damage to the correct opposing slot
#   D5: Faint replacement — fainted slot is replaced without disturbing the partner slot
#   D6: Voluntary switch in doubles — queue_switch_for swaps one slot, leaves other intact
#   B1: Spread move damages both opponents (integration + composition order unit test)
#   B2: Spread + immune target — immune gets 0, non-immune gets 0.75× (immune still counts)
#   B3: Spread with one target fainted mid-turn — survivor gets 1.0× (no reduction)
#   B4: Helping Hand grants ally 1.5× base-power boost (integration + composition unit)
#   B5: Helping Hand boost is cleared at turn end (does not persist)
#   B6: Follow Me redirects single-target move to Follow Me user
#   B7: Follow Me does NOT redirect spread moves (both targets still hit)
#   B8: Destiny Bond kills actual fatal attacker (second slot, not first slot)
#   B9: Roar forces out specifically targeted field slot (both slots tested)
#
# Ground truth: pokeemerald_expansion
#   battle.h :: gBattlerPositions, B_POSITION_PLAYER_LEFT/RIGHT
#   battle_main.c :: turn order resolution / action execution loop
#   battle_main.c :: SwitchInClearSetData, FaintClearSetData
#   battle_util.c :: GetTargetDamageModifier (spread 0.75×, L7220)
#   battle_util.c :: CalcMoveBasePowerAfterModifiers (Helping Hand 1.5× to base power, L6436)
#   battle_script_commands.c :: Cmd_trysethelpinghand (L8850), Cmd_setforcedtarget (L8748)
#   battle_move_resolution.c :: IsAffectedByFollowMe (L799) — spread bypasses
#   ChooseMoveOrAction_Doubles (battle_ai_main.c) — skipped (M14c scope)
#
# Note on captured state in lambdas: GDScript 4.x lambdas only share REFERENCE types
# with the enclosing scope. Use single-element Arrays ([value]) for all scalar state
# that must be readable after signal emission.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_d1_party_and_setup()
	_test_d2_turn_order()
	_test_d3_full_side_faint()
	_test_d4a_target_near_slot()
	_test_d4b_target_far_slot()
	_test_d5_faint_replacement()
	_test_d6_voluntary_switch()
	_test_b1_spread_hits_both()
	_test_b2_spread_immune_target()
	_test_b3_spread_single_no_reduction()
	_test_b4_helping_hand_boosts()
	_test_b5_helping_hand_clears()
	_test_b6_follow_me_redirects()
	_test_b7_follow_me_bypasses_spread()
	_test_b8_destiny_bond_real_killer()
	_test_b9_roar_targets_field_slot()
	_test_c1_ai_prefers_spread_two_targets()
	_test_c2_ai_avoids_immune_spread()
	_test_c3_ai_targets_weak_slot()

	var total := _pass + _fail
	print("doubles_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, hp: int = 100, atk: int = 80, def_stat: int = 80,
		spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


# BattleParty with both slots active (no bench).
func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)   # starts as [0], becomes [0, 1]
	return p


# BattleParty with both slots active plus one bench mon.
func _doubles_party_bench(m0: BattlePokemon, m1: BattlePokemon,
		bench: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1, bench]
	p.active_indices.append(1)
	return p


# ── D1: BattleParty doubles API + 4-combatant BattleManager setup ─────────────
#
# BattleParty unit tests cover the new API introduced in M14a:
#   active_indices (Array[int] of field slots), get_active_at, num_active,
#   has_valid_switch_target / get_first_non_fainted_not_active in multi-active context.
# BattleManager tests verify the 4-element _combatants array and _active_per_side=2.

func _test_d1_party_and_setup() -> void:
	var tackle := _load_move(33)

	# BattleParty API tests
	var m0 := _make_mon("M0")
	var m1 := _make_mon("M1")
	var m2 := _make_mon("M2")

	var p := _doubles_party(m0, m1)
	_chk("D1.01 active_indices.size == 2",    p.active_indices.size() == 2)
	_chk("D1.02 active_indices[0] == 0",      p.active_indices[0] == 0)
	_chk("D1.03 active_indices[1] == 1",      p.active_indices[1] == 1)
	_chk("D1.04 get_active_at(0) == m0",      p.get_active_at(0) == m0)
	_chk("D1.05 get_active_at(1) == m1",      p.get_active_at(1) == m1)
	_chk("D1.06 num_active() == 2",           p.num_active() == 2)
	_chk("D1.07 active_index compat (slot 0)", p.active_index == 0)
	_chk("D1.08 no bench → no valid switch",  not p.has_valid_switch_target())

	var pb := _doubles_party_bench(m0, m1, m2)
	_chk("D1.09 bench → valid switch",        pb.has_valid_switch_target())
	_chk("D1.10 first bench slot == 2",       pb.get_first_non_fainted_not_active() == 2)

	# BattleManager setup
	m0.add_move(tackle); m1.add_move(tackle)
	var b0 := _make_mon("B0"); var b1 := _make_mon("B1")
	b0.add_move(tackle); b1.add_move(tackle)

	var pp := _doubles_party(m0, m1)
	var op := _doubles_party(b0, b1)

	var combatant_count := [-1]
	var active_per_side  := [-1]
	var bm := BattleManager.new()
	add_child(bm)
	bm.phase_changed.connect(func(_p):
		if combatant_count[0] < 0:
			combatant_count[0] = bm._combatants.size()
			active_per_side[0]  = bm._active_per_side
	)
	var ended := [false]
	bm.battle_ended.connect(func(_w): ended[0] = true)
	bm.start_battle_doubles(pp, op)

	_chk("D1.11 _combatants.size == 4",       combatant_count[0] == 4)
	_chk("D1.12 _active_per_side == 2",       active_per_side[0] == 2)
	_chk("D1.13 2v2 battle runs to completion", ended[0])
	bm.queue_free()


# ── D2: Turn order — 4 distinct speeds ────────────────────────────────────────
#
# Setup: A0(spd=100), A1(spd=60), B0(spd=80), B1(spd=40). All same priority bracket.
# Expected turn-1 order: A0 → B0 → A1 → B1.
# HP set large enough (1000) so nobody faints in turn 1 — all 4 moves execute.
# Source: speed sort within priority bracket (battle_main.c L5004-L5015)

func _test_d2_turn_order() -> void:
	var tackle := _load_move(33)
	var a0 := _make_mon("A0", 1000, 80, 80, 80, 80, 100)
	var a1 := _make_mon("A1", 1000, 80, 80, 80, 80,  60)
	var b0 := _make_mon("B0", 1000, 80, 80, 80, 80,  80)
	var b1 := _make_mon("B1", 1000, 80, 80, 80, 80,  40)
	for mon in [a0, a1, b0, b1]:
		mon.add_move(tackle)

	var pp := _doubles_party(a0, a1)
	var op := _doubles_party(b0, b1)

	# Capture the first 4 move_executed signals to record turn-1 order.
	var order: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, _def, _mv, _dmg):
		if order.size() < 4:
			order.append(attacker)
	)
	bm.start_battle_doubles(pp, op)

	_chk("D2.01 first actor is A0 (spd 100)",  order.size() >= 1 and order[0] == a0)
	_chk("D2.02 second actor is B0 (spd 80)",  order.size() >= 2 and order[1] == b0)
	_chk("D2.03 third actor is A1 (spd 60)",   order.size() >= 3 and order[2] == a1)
	_chk("D2.04 fourth actor is B1 (spd 40)",  order.size() >= 4 and order[3] == b1)
	bm.queue_free()


# ── D3: Battle ends only when a full side is fainted ─────────────────────────
#
# With two opponent slots, fainting one slot must NOT trigger battle_ended.
# Only when both field slots AND all bench members are fainted does is_fully_fainted()
# return true and the battle end.
# Setup: B0(HP=1), B1(HP=500). Player attacks default (B0's slot). B0 faints in turn 1.
# B1 is still alive → battle_ended must not have fired when B0 faints.
# Battle eventually ends when B1 also faints.

func _test_d3_full_side_faint() -> void:
	var tackle := _load_move(33)
	# High-attack player mons: KO B0 in turn 1. B1 survives many turns.
	var a0 := _make_mon("A0", 500, 255, 80, 80, 80, 80)
	var a1 := _make_mon("A1", 500, 255, 80, 80, 80, 80)
	var b0 := _make_mon("B0",   1,  80, 80, 80, 80, 80)
	var b1 := _make_mon("B1", 500,  80, 80, 80, 80, 80)
	for mon in [a0, a1, b0, b1]:
		mon.add_move(tackle)

	var pp := _doubles_party(a0, a1)
	var op := _doubles_party(b0, b1)

	var battle_ended := [false]
	var b0_faint_before_end := [false]

	var bm := BattleManager.new()
	add_child(bm)
	bm.battle_ended.connect(func(_w): battle_ended[0] = true)
	bm.pokemon_fainted.connect(func(mon):
		if mon == b0 and not battle_ended[0]:
			b0_faint_before_end[0] = true
	)
	bm.start_battle_doubles(pp, op)

	_chk("D3.01 B0 faint does not end battle (B1 still alive)", b0_faint_before_end[0])
	_chk("D3.02 battle ends when full side is fainted",          battle_ended[0])
	bm.queue_free()


# ── D4a: Targeting — queue_move_targeted to the near opposing slot (combatant 2) ──
#
# Player combatant 0 (A0) queues a move explicitly targeting combatant 2 (B0).
# Verify: move_executed fires with defender == B0, not B1.
# B0 and B1 start with distinct HP so the signal captures the right target.

func _test_d4a_target_near_slot() -> void:
	var tackle := _load_move(33)
	var a0 := _make_mon("A0", 500, 80, 80, 80, 80, 100)
	var a1 := _make_mon("A1", 500, 80, 80, 80, 80,  60)
	var b0 := _make_mon("B0", 500, 80, 80, 80, 80,  80)
	var b1 := _make_mon("B1", 500, 80, 80, 80, 80,  40)
	for mon in [a0, a1, b0, b1]:
		mon.add_move(tackle)

	var pp := _doubles_party(a0, a1)
	var op := _doubles_party(b0, b1)

	var a0_target := [null]
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, _mv, _dmg):
		if attacker == a0 and a0_target[0] == null:
			a0_target[0] = defender
	)
	# Explicitly target combatant 2 (B0 — near slot of opponent side).
	bm.queue_move_targeted(0, 0, 2)
	bm.start_battle_doubles(pp, op)

	_chk("D4a A0 targeting combatant 2 hits B0", a0_target[0] == b0)
	bm.queue_free()


# ── D4b: Targeting — queue_move_targeted to the far opposing slot (combatant 3) ───
#
# Player combatant 0 (A0) queues a move explicitly targeting combatant 3 (B1).
# Verify: move_executed fires with defender == B1, not B0.

func _test_d4b_target_far_slot() -> void:
	var tackle := _load_move(33)
	var a0 := _make_mon("A0", 500, 80, 80, 80, 80, 100)
	var a1 := _make_mon("A1", 500, 80, 80, 80, 80,  60)
	var b0 := _make_mon("B0", 500, 80, 80, 80, 80,  80)
	var b1 := _make_mon("B1", 500, 80, 80, 80, 80,  40)
	for mon in [a0, a1, b0, b1]:
		mon.add_move(tackle)

	var pp := _doubles_party(a0, a1)
	var op := _doubles_party(b0, b1)

	var a0_target := [null]
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, _mv, _dmg):
		if attacker == a0 and a0_target[0] == null:
			a0_target[0] = defender
	)
	# Explicitly target combatant 3 (B1 — far slot of opponent side).
	bm.queue_move_targeted(0, 0, 3)
	bm.start_battle_doubles(pp, op)

	_chk("D4b A0 targeting combatant 3 hits B1", a0_target[0] == b1)
	bm.queue_free()


# ── D5: Faint replacement in doubles ─────────────────────────────────────────
#
# When combatant 2 (B0) faints, the opponent's bench mon (B2) should enter
# combatant slot 2. Combatant 3 (B1) must remain on the field, unchanged.
# Source: SWITCH_PROMPT → _do_switch_in(combatant_idx=2, slot=2)
#   _combatants[2] = B2; _combatants[3] = B1 (unaffected).

func _test_d5_faint_replacement() -> void:
	var tackle := _load_move(33)
	var a0 := _make_mon("A0", 500, 255, 80, 80, 80, 80)
	var a1 := _make_mon("A1", 500, 255, 80, 80, 80, 80)
	var b0 := _make_mon("B0",   1,  80, 80, 80, 80, 80)
	var b1 := _make_mon("B1", 500,  80, 80, 80, 80, 80)
	var b2 := _make_mon("B2", 500,  80, 80, 80, 80, 80)
	for mon in [a0, a1, b0, b1, b2]:
		mon.add_move(tackle)

	var pp := _doubles_party(a0, a1)
	# Opponent: both active + B2 on bench (party slot 2).
	var op := _doubles_party_bench(b0, b1, b2)

	# Capture which mon entered and what was at slot 3 when B0 fainted.
	var replaced_by := [null]
	var slot3_at_b0_faint := [null]
	var bm := BattleManager.new()
	add_child(bm)
	bm.pokemon_switched_in.connect(func(mon, side, _slot):
		if side == 1 and replaced_by[0] == null:
			replaced_by[0] = mon
	)
	bm.pokemon_fainted.connect(func(mon):
		if mon == b0 and slot3_at_b0_faint[0] == null:
			slot3_at_b0_faint[0] = bm._combatants[3]
	)
	bm.start_battle_doubles(pp, op)

	_chk("D5.01 B2 entered to replace fainted B0",         replaced_by[0] == b2)
	_chk("D5.02 partner slot (B1, combatant 3) unaffected", slot3_at_b0_faint[0] == b1)
	bm.queue_free()


# ── D6: Voluntary switch in doubles ──────────────────────────────────────────
#
# queue_switch_for(combatant_idx, slot) swaps one field slot without affecting
# the other. Queue combatant 1 (A1) to switch to bench slot 2 (A2).
# Verify: pokemon_switched_out fires for A1, pokemon_switched_in fires for A2.
# A0 must remain unaffected (no switch signal for it).
# Source: voluntary switch action in ACTION_EXECUTION → _do_voluntary_switch.

func _test_d6_voluntary_switch() -> void:
	var tackle := _load_move(33)
	# Player bench mon A2 comes in for A1.
	var a0 := _make_mon("A0", 500, 255, 80, 80, 80, 80)
	var a1 := _make_mon("A1", 500, 255, 80, 80, 80, 80)
	var a2 := _make_mon("A2", 500, 255, 80, 80, 80, 80)
	# Opponent with low HP so the battle ends quickly after the switch.
	var b0 := _make_mon("B0",   1,  80, 80, 80, 80, 80)
	var b1 := _make_mon("B1",   1,  80, 80, 80, 80, 80)
	for mon in [a0, a1, a2, b0, b1]:
		mon.add_move(tackle)

	var pp := _doubles_party_bench(a0, a1, a2)
	var op := _doubles_party(b0, b1)

	var switch_out := [null]
	var switch_in  := [null]
	var bm := BattleManager.new()
	add_child(bm)
	bm.pokemon_switched_out.connect(func(mon, side):
		if side == 0 and switch_out[0] == null:
			switch_out[0] = mon
	)
	bm.pokemon_switched_in.connect(func(mon, side, _slot):
		if side == 0 and switch_in[0] == null:
			switch_in[0] = mon
	)
	# Queue A1 (combatant 1) to switch to party slot 2 (A2).
	bm.queue_switch_for(1, 2)
	bm.start_battle_doubles(pp, op)

	_chk("D6.01 A1 switched out", switch_out[0] == a1)
	_chk("D6.02 A2 switched in",  switch_in[0]  == a2)
	bm.queue_free()


# ── M14b helpers ──────────────────────────────────────────────────────────────

# Typed variant of _make_mon — allows specifying the mon's type.
func _make_mon_typed(mon_name: String, type: int, hp: int = 100, atk: int = 80,
		def_stat: int = 80, spatk: int = 80, spdef: int = 80,
		spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [type]
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


func _make_spread(move_name: String, power: int,
		move_type: int = TypeChart.TYPE_NORMAL, cat: int = 0) -> MoveData:
	var m := MoveData.new()
	m.move_name = move_name
	m.power = power
	m.type = move_type
	m.category = cat
	m.accuracy = 100
	m.is_spread = true
	return m


func _make_hh() -> MoveData:
	var m := MoveData.new()
	m.move_name = "HelpingHand"
	m.power = 0
	m.priority = 5
	m.is_helping_hand = true
	return m


func _make_fm() -> MoveData:
	var m := MoveData.new()
	m.move_name = "FollowMe"
	m.power = 0
	m.priority = 2
	m.is_follow_me = true
	return m


func _make_db() -> MoveData:
	var m := MoveData.new()
	m.move_name = "DestinyBond"
	m.power = 0
	m.destiny_bond = true
	return m


func _make_roar() -> MoveData:
	var m := MoveData.new()
	m.move_name = "Roar"
	m.power = 0
	m.priority = -6
	m.accuracy = 0
	m.is_roar = true
	return m


func _make_atk_move(move_name: String, power: int,
		move_type: int = TypeChart.TYPE_NORMAL, cat: int = 0) -> MoveData:
	var m := MoveData.new()
	m.move_name = move_name
	m.power = power
	m.type = move_type
	m.category = cat
	m.accuracy = 100
	return m


# ── B1: Spread move damages both opponents ────────────────────────────────────
#
# A0 (Normal, atk=200, spd=100) uses a Normal Physical spread move (power=90)
# against B0 and B1 (both base_def=80, base_hp=1 → max_hp=61).
#
# Damage with 0.75× spread (2 live targets): base=97 → reduced=73 → min at roll 85: 62.
# 62 > 61 → both always faint, proving each was hit independently.
#
# B1.03 (composition order, unit): Electric spread (power=20) vs Water-type defender.
#   Attacker spatk=50 (→55), defender spdef=50 (→55), both level 50.
#   base=10. Correct (spread→type_eff): 10→7→14. Wrong (type_eff→spread): 10→20→15.
#   Source: DoMoveDamageCalcVars (battle_util.c L7592) — DAMAGE_APPLY_MODIFIER ordering.

func _test_b1_spread_hits_both() -> void:
	var tackle := _load_move(33)
	var spread := _make_spread("NormSpread", 90)

	var a0 := _make_mon("A0", 100, 200, 80, 80, 80, 100)
	var a1 := _make_mon("A1", 100,  80, 80, 80, 80,  60)
	var b0 := _make_mon("B0",   1,  80, 80, 80, 80,  80)
	var b1 := _make_mon("B1",   1,  80, 80, 80, 80,  40)
	a0.add_move(spread)
	for mon in [a1, b0, b1]:
		mon.add_move(tackle)

	var b0_dmg := [0]
	var b1_dmg := [0]
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, _mv, dmg):
		if attacker == a0:
			if defender == b0:
				b0_dmg[0] = dmg
			elif defender == b1:
				b1_dmg[0] = dmg
	)
	bm.start_battle_doubles(_doubles_party(a0, a1), _doubles_party(b0, b1))

	_chk("B1.01 spread hit B0 (non-zero damage)", b0_dmg[0] > 0)
	_chk("B1.02 spread hit B1 (non-zero damage)", b1_dmg[0] > 0)

	# B1.03: composition order unit test on DamageCalculator directly.
	# Spread reduction (0.75×) must be applied BEFORE type-effectiveness (2.0×).
	# With base=10, roll=100: spread→type_eff = 10→7→14. type_eff→spread = 10→20→15.
	# Source: DoMoveDamageCalcVars modifier ordering (battle_util.c L7577–7620).
	var att := _make_mon_typed("Att", TypeChart.TYPE_NORMAL, 100, 80, 80, 50, 80, 80)
	var def := _make_mon_typed("Def", TypeChart.TYPE_WATER,  100, 80, 80, 80, 50, 80)
	var elec_spread := _make_spread("ElecSpread", 20, TypeChart.TYPE_ELECTRIC, 1)
	var r: Dictionary = DamageCalculator.calculate(att, def, elec_spread,
			100, false, DamageCalculator.WEATHER_NONE, true)
	_chk("B1.03 spread×type_eff composition: 14 (not 15 wrong-order)", r["damage"] == 14)

	bm.queue_free()


# ── B2: Spread with one immune target ────────────────────────────────────────
#
# A0 uses a Ground spread move. B0 is Flying-type (immune). B1 is Normal-type.
# The immune B0 receives 0 damage but still counts toward live_target_count,
# so the 0.75× spread reduction applies to B1's hit.
#
# B0: Flying, base_hp=1 (max=61), base_def=80 (def=85). Ground→Flying = 0×.
# B1: Normal, base_hp=14 (max=74), base_def=80 (def=85). Ground→Normal = 1×.
# A0: atk=205 (base=200), Ground spread power=90, Physical.
#   base=97. With 0.75×: 73. min at roll 85: 62. max at roll 100: 73.
#   Both < 74 (B1 max_hp) → B1 always survives A0's first spread.
#   Without reduction (if immune target not counted): min 82 > 74 → B1 faints.
# A1 pre-queued to attack B0 so A1 doesn't also damage B1 in turn 1.
#
# Source: GetMoveTargetCount (battle_util.c L5982) — counts non-absent regardless of immunity.

func _test_b2_spread_immune_target() -> void:
	var tackle := _load_move(33)
	var gnd_spread := _make_spread("GndSpread", 90, TypeChart.TYPE_GROUND)

	var a0 := _make_mon_typed("A0", TypeChart.TYPE_NORMAL, 100, 200, 80, 80, 80, 100)
	var a1 := _make_mon(        "A1", 100,  80, 80, 80, 80,  60)
	var b0 := _make_mon_typed("B0", TypeChart.TYPE_FLYING,   1,  80, 80, 80, 80,  80)
	var b1 := _make_mon(        "B1",  14,  80, 80, 80, 80,  40)
	a0.add_move(gnd_spread)
	for mon in [a1, b0, b1]:
		mon.add_move(tackle)

	var b0_dmg := [0]
	var b1_hp_after := [-1]
	var b1_dmg := [0]
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, _mv, dmg):
		if attacker == a0:
			if defender == b0:
				b0_dmg[0] = dmg
			elif defender == b1 and b1_hp_after[0] == -1:
				b1_dmg[0] = dmg
				b1_hp_after[0] = b1.current_hp
	)
	# Pre-queue A1 → B0 (combatant 2) so A1 doesn't also damage B1 in turn 1.
	bm.queue_move_targeted(1, 0, 2)
	bm.start_battle_doubles(_doubles_party(a0, a1), _doubles_party(b0, b1))

	_chk("B2.01 immune B0 took 0 damage from Ground spread",  b0_dmg[0] == 0)
	_chk("B2.02 non-immune B1 took damage from Ground spread", b1_dmg[0] > 0)
	# B2.03: immune B0 still counted as live target → 0.75× reduction applied to B1.
	# With reduction max=73 < 74 (B1 max_hp). Without: min=82 > 74 (B1 faints).
	_chk("B2.03 immune target counted for spread reduction (B1 survived first hit)",
			b1_hp_after[0] > 0)
	bm.queue_free()


# ── B3: Spread with fainted mid-turn target — survivor gets 1.0× ─────────────
#
# A1 (spd=90) kills B0 (HP=1) before A0 (spd=60) acts. When A0 uses spread:
# live_target_count=1 → spread_dmg_reduction=false → B1 gets 1.0× (no reduction).
#
# A0: Normal, spatk=200 (→205), Special spread, power=20, spd=60, level 50.
# B1: Normal, base_spdef=50 (→55). base=20*205*22/55/50+2=34. Range 28–34.
# With reduction (wrong code): max=25 at roll 100. Min=21 at roll 85.
# B3.01 check: captured damage > 25 → proves no reduction was applied.
#
# Source: GetMoveTargetCount recounted at use time; fainted targets excluded.

func _test_b3_spread_single_no_reduction() -> void:
	var tackle := _load_move(33)
	var sp_spread := _make_spread("SpSpread", 20, TypeChart.TYPE_NORMAL, 1)  # Special

	# A1 uses high-attack tackle to guarantee B0 (def=55) faints before A0 acts.
	# A1 atk=260 (base=255), B0 def=55 (base=50): base=85, min=72 > 61 (B0 max_hp). ✓
	var a0 := _make_mon("A0", 100,  80, 80, 200, 80,  60)
	var a1 := _make_mon("A1", 100, 255, 50,  80, 80,  90)
	var b0 := _make_mon("B0",   1,  80, 50,  80, 80,  80)
	var b1 := _make_mon("B1", 100,  80, 80,  80, 50,  40)
	a0.add_move(sp_spread)
	for mon in [a1, b0, b1]:
		mon.add_move(tackle)

	var b1_spread_dmg := [0]
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, _mv, dmg):
		if attacker == a0 and defender == b1 and b1_spread_dmg[0] == 0:
			b1_spread_dmg[0] = dmg
	)
	bm.start_battle_doubles(_doubles_party(a0, a1), _doubles_party(b0, b1))

	# STAB-corrected ranges (Normal mons, Normal move, STAB applies after roll):
	# With reduction (wrong): 31–37.  Without reduction (correct, 1 live target): 42–51.
	# Threshold 40 sits between the two ranges.
	_chk("B3.01 single live target → no spread reduction (damage > 40)", b1_spread_dmg[0] > 40)
	bm.queue_free()


# ── B4: Helping Hand grants 1.5× base-power boost to ally ────────────────────
#
# A0 (spd=100) uses Helping Hand (priority=5) → A1 gets boost.
# A1 (spd=60) attacks B0 with boosted tackle.
#
# A1: base_atk=100 (→105). B0: base_def=50 (→55). Tackle power=40.
# base no-HH = 40*105*22/55/50+2 = 35. Max at roll=100: 35.
# Effective power with HH = _uq412_half_down(40, 6144) = 60.
# base with HH = 60*105*22/55/50+2 = 52. Min at roll=85: 44. All > 35. ✓
#
# B4.02 (composition, unit): HH applied to base power BEFORE formula.
#   Attacker base_atk=80 (→85), defender base_def=50 (→55), Fire move power=40.
#   Correct: effective_power=60, base=42. Wrong (post-formula): base=29→43. 42≠43. ✓
#   Source: CalcMoveBasePowerAfterModifiers (battle_util.c L6436).

func _test_b4_helping_hand_boosts() -> void:
	var tackle := _load_move(33)
	var hh := _make_hh()

	# A0 has two moves: HH (index 0) and tackle (index 1).
	var a0 := _make_mon("A0", 100,  80, 80, 80, 80, 100)
	var a1 := _make_mon("A1", 100, 100, 80, 80, 80,  60)
	var b0 := _make_mon("B0", 100,  80, 50, 80, 80,  80)
	var b1 := _make_mon("B1", 100,  80, 80, 80, 80,  40)
	a0.add_move(hh)
	a0.add_move(tackle)
	for mon in [a1, b0, b1]:
		mon.add_move(tackle)

	# Capture A1's damage on B0. Turn 1: A0 HH→A1; A1 tackle→B0.
	# Turn 2: A0 tackle→B0; A1 tackle→B0 (no re-HH in turn 2 — tested in B5).
	var a1_b0_dmgs := [[]]
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, _mv, dmg):
		if attacker == a1 and defender == b0:
			a1_b0_dmgs[0].append(dmg)
	)
	# Turn 1: A0 uses HH (move 0) targeting ally A1 (combatant 1).
	bm.queue_move_targeted(0, 0, 1)
	# Turn 1: A1 uses tackle (move 0) targeting B0 (combatant 2).
	bm.queue_move_targeted(1, 0, 2)
	# Turn 2: A0 uses tackle (move 1) so HH is NOT re-applied (B5 relies on this).
	bm.queue_move_targeted(0, 1, 2)
	# Turn 2: A1 uses tackle (move 0) targeting B0 (combatant 2) — second B0 hit.
	bm.queue_move_targeted(1, 0, 2)
	bm.start_battle_doubles(_doubles_party(a0, a1), _doubles_party(b0, b1))

	# A1's turn-1 damage: HH-boosted (min 44 > 35 max no-HH).
	_chk("B4.01 Helping Hand boosted A1's damage (> 35 max unboosted)",
			a1_b0_dmgs[0].size() > 0 and a1_b0_dmgs[0][0] > 35)

	# B4.02 composition: HH multiplies base power BEFORE formula (not post-formula).
	# atk=85 (base 80), def=55 (base 50), Fire move power=40, Normal attacker (no STAB).
	# Correct: effective_power=60 → base=42 → at roll=100: 42.
	# Wrong (post-formula ×1.5): base=29 → at roll=100: (29×1.5 rounded) = 43. 42≠43.
	var att := _make_mon("AttHH", 100, 80, 50, 80, 80, 80)
	var def := _make_mon("DefHH", 100, 80, 50, 80, 80, 80)
	var fire_mv := _make_atk_move("Fire", 40, TypeChart.TYPE_FIRE)
	var r: Dictionary = DamageCalculator.calculate(att, def, fire_mv,
			100, false, DamageCalculator.WEATHER_NONE, false, true)
	_chk("B4.02 HH base-power composition: 42 (not 43 wrong-order)", r["damage"] == 42)

	bm.queue_free()


# ── B5: Helping Hand boost does NOT persist to next turn ─────────────────────
#
# Uses the same B4 battle (A0 queues HH in turn 1, tackle in turn 2).
# In turn 2, A0 uses tackle instead of HH → _helping_hand flag cleared at turn start.
# A1's turn-2 tackle on B0 must be within the no-HH range (≤35).
#
# Source: TurnValuesCleanUp (battle_main.c) — memset clears gProtectStructs
#   (which includes helpingHand) at the start of each turn's priority resolution.

func _test_b5_helping_hand_clears() -> void:
	var tackle := _load_move(33)
	var hh := _make_hh()

	var a0 := _make_mon("A0", 100,  80, 80, 80, 80, 100)
	var a1 := _make_mon("A1", 100, 100, 80, 80, 80,  60)
	var b0 := _make_mon("B0", 100,  80, 50, 80, 80,  80)
	var b1 := _make_mon("B1", 100,  80, 80, 80, 80,  40)
	a0.add_move(hh)
	a0.add_move(tackle)
	for mon in [a1, b0, b1]:
		mon.add_move(tackle)

	var a1_b0_dmgs := [[]]
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, _mv, dmg):
		if attacker == a1 and defender == b0:
			a1_b0_dmgs[0].append(dmg)
	)
	bm.queue_move_targeted(0, 0, 1)  # Turn 1: A0 HH → A1
	bm.queue_move_targeted(1, 0, 2)  # Turn 1: A1 tackle → B0
	bm.queue_move_targeted(0, 1, 2)  # Turn 2: A0 tackle → B0 (no HH)
	bm.queue_move_targeted(1, 0, 2)  # Turn 2: A1 tackle → B0
	bm.start_battle_doubles(_doubles_party(a0, a1), _doubles_party(b0, b1))

	# STAB-corrected ranges (Normal mons, Normal Tackle, STAB applies after roll):
	# With HH (wrong — persisted): 66–78.  Without HH (correct — cleared): 43–52.
	# Threshold 60 sits between the two ranges.
	_chk("B5.01 Helping Hand did not persist to turn 2 (A1 damage ≤ 60)",
			a1_b0_dmgs[0].size() >= 2 and a1_b0_dmgs[0][1] <= 60)
	bm.queue_free()


# ── B6: Follow Me redirects single-target move ───────────────────────────────
#
# B0 (spd=80) uses Follow Me (priority=2) — fires before A0's priority=0 attack.
# A0 is pre-queued to target B1 (combatant 3). Follow Me redirect fires for
# non-spread moves (move.power > 0) → defender changed to B0.
# Verify: A0's move_executed reports defender == B0, not B1.
#
# Source: IsAffectedByFollowMe (battle_move_resolution.c L799) + GetBattleMoveTarget
#   (battle_util.c L5529) — redirects TARGET_SELECTED/SMART/OPPONENT/RANDOM.

func _test_b6_follow_me_redirects() -> void:
	var tackle := _load_move(33)
	var fm := _make_fm()

	var a0 := _make_mon("A0", 100, 100, 80, 80, 80, 100)
	var a1 := _make_mon("A1", 100,  80, 80, 80, 80,  60)
	var b0 := _make_mon("B0", 100,  80, 80, 80, 80,  80)
	var b1 := _make_mon("B1", 100,  80, 80, 80, 80,  40)
	a0.add_move(tackle)
	a1.add_move(tackle)
	b0.add_move(fm)
	b1.add_move(tackle)

	var a0_target := [null]
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, _mv, _dmg):
		if attacker == a0 and a0_target[0] == null:
			a0_target[0] = defender
	)
	# A0 explicitly targets B1 (combatant 3) — but Follow Me should redirect to B0.
	bm.queue_move_targeted(0, 0, 3)
	bm.start_battle_doubles(_doubles_party(a0, a1), _doubles_party(b0, b1))

	_chk("B6.01 Follow Me redirected A0's targeted attack to B0", a0_target[0] == b0)
	bm.queue_free()


# ── B7: Follow Me does NOT redirect spread moves ──────────────────────────────
#
# B0 (spd=80) uses Follow Me. A0 (spd=100) uses a spread move.
# Spread path iterates all opposing slots independently — Follow Me is bypassed.
# B7.01: B1 still receives damage from A0's spread despite Follow Me being active.
#
# Source: IsAffectedByFollowMe (battle_move_resolution.c L799) —
#   spread moves are excluded by the TARGET_BOTH / FOES_AND_ALLY check.

func _test_b7_follow_me_bypasses_spread() -> void:
	var tackle := _load_move(33)
	var spread := _make_spread("NormSpread", 90)
	var fm := _make_fm()

	var a0 := _make_mon("A0", 100, 200, 80, 80, 80, 100)
	var a1 := _make_mon("A1", 100,  80, 80, 80, 80,  60)
	var b0 := _make_mon("B0", 100,  80, 80, 80, 80,  80)
	var b1 := _make_mon("B1", 100,  80, 80, 80, 80,  40)
	a0.add_move(spread)
	a1.add_move(tackle)
	b0.add_move(fm)
	b1.add_move(tackle)

	var b1_received_dmg := [false]
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, _mv, dmg):
		if attacker == a0 and defender == b1 and dmg > 0:
			b1_received_dmg[0] = true
	)
	bm.start_battle_doubles(_doubles_party(a0, a1), _doubles_party(b0, b1))

	_chk("B7.01 Follow Me did not block spread — B1 received damage", b1_received_dmg[0])
	bm.queue_free()


# ── B8: Destiny Bond kills the actual fatal attacker (second slot) ────────────
#
# A0 (spd=100, HP=1) uses Destiny Bond. B1 (spd=40) deals the killing blow.
# B0 (spd=80) attacks A1 (not A0) — B0 must NOT be the Destiny Bond killer.
#
# Turn order: A0(DB,100) → B0(80, tackle→A1) → A1(60, tackle→B0) → B1(40, tackle→A0)
# _last_attacker[A0] = B1 (set when B1 hits A0 for damage > 0).
# Faint check: A0 fainted, had_destiny_bond=true → killer=B1, not B0.
# Verify: destiny_bond_triggered fires with killer == B1.
#
# Source: _last_attacker tracks gBattlerAttacker at each hit (M14b Destiny Bond fix).

func _test_b8_destiny_bond_real_killer() -> void:
	var tackle := _load_move(33)
	var db := _make_db()

	var a0 := _make_mon("A0",   1,  80, 80, 80, 80, 100)  # HP=1 → max_hp=61
	var a1 := _make_mon("A1", 100,  80, 80, 80, 80,  60)
	# B1 base_atk=230 → stat=235. A0 base_def=80 → stat=85.
	# Damage: base=40*235*22/85/50+2=50. roll=85: 42. STAB: 63 ≥ 61. Guaranteed OHKO. ✓
	var b0 := _make_mon("B0", 100,  80, 80, 80, 80,  80)
	var b1 := _make_mon("B1", 100, 230, 80, 80, 80,  40)
	a0.add_move(db)
	for mon in [a1, b0, b1]:
		mon.add_move(tackle)

	var db_killer := [null]
	var bm := BattleManager.new()
	add_child(bm)
	bm.destiny_bond_triggered.connect(func(_victim, killer):
		db_killer[0] = killer
	)
	# B0 attacks A1 (not A0) so B0 is not _last_attacker[A0].
	bm.queue_move_targeted(2, 0, 1)  # B0 (combatant 2) → A1 (combatant 1)
	# B1 attacks A0 — fatal blow sets _last_attacker[A0] = B1.
	bm.queue_move_targeted(3, 0, 0)  # B1 (combatant 3) → A0 (combatant 0)
	bm.start_battle_doubles(_doubles_party(a0, a1), _doubles_party(b0, b1))

	_chk("B8.01 Destiny Bond killed actual killer B1, not B0", db_killer[0] == b1)
	bm.queue_free()


# ── B9: Roar forces out specifically targeted field slot ──────────────────────
#
# M14b fix: Roar uses _combatants.find(defender) % _active_per_side to determine
# which field slot to clear, rather than always using slot 0.
#
# B9a (B9.01): A0 pre-queued to use Roar targeting B1 (combatant 3).
#   forced_switch old == B1 → B2 enters at combatant 3; B0 (combatant 2) untouched.
# B9b (B9.02): A0 auto-targets default (B0, combatant 2) with Roar.
#   forced_switch old == B0 → B2 enters at combatant 2; B1 (combatant 3) untouched.
#
# Source: Cmd_BS_JumpIfRoarFails (battle_script_commands.c L7426) —
#   gProtectStructs[gBattlerTarget].forcedSwitch applies to the actual targeted battler.

func _test_b9_roar_targets_field_slot() -> void:
	var tackle := _load_move(33)
	var roar := _make_roar()

	# B9a — Roar targeting B1 (combatant 3, the "far" opposing slot).
	var a0a := _make_mon("A0a", 100, 80, 80, 80, 80, 100)
	var a1a := _make_mon("A1a", 100, 80, 80, 80, 80,  60)
	var b0a := _make_mon("B0a", 100, 80, 80, 80, 80,  80)
	var b1a := _make_mon("B1a", 100, 80, 80, 80, 80,  40)
	var b2a := _make_mon("B2a", 100, 80, 80, 80, 80,  50)
	a0a.add_move(roar)
	for mon in [a1a, b0a, b1a, b2a]:
		mon.add_move(tackle)

	var roar_out_a := [null]
	var bm_a := BattleManager.new()
	add_child(bm_a)
	bm_a.forced_switch.connect(func(old, _new):
		if roar_out_a[0] == null:
			roar_out_a[0] = old
	)
	# Roar targeting B1 (combatant 3): def_field_slot = 3 % 2 = 1 → forces B1's slot.
	bm_a.queue_move_targeted(0, 0, 3)
	bm_a.start_battle_doubles(
			_doubles_party(a0a, a1a), _doubles_party_bench(b0a, b1a, b2a))

	_chk("B9.01 Roar targeting combatant 3 forced out B1 (not B0)", roar_out_a[0] == b1a)
	bm_a.queue_free()

	# B9b — Roar targeting B0 (combatant 2, the "near" opposing slot, default target).
	var a0b := _make_mon("A0b", 100, 80, 80, 80, 80, 100)
	var a1b := _make_mon("A1b", 100, 80, 80, 80, 80,  60)
	var b0b := _make_mon("B0b", 100, 80, 80, 80, 80,  80)
	var b1b := _make_mon("B1b", 100, 80, 80, 80, 80,  40)
	var b2b := _make_mon("B2b", 100, 80, 80, 80, 80,  50)
	a0b.add_move(roar)
	for mon in [a1b, b0b, b1b, b2b]:
		mon.add_move(tackle)

	var roar_out_b := [null]
	var bm_b := BattleManager.new()
	add_child(bm_b)
	bm_b.forced_switch.connect(func(old, _new):
		if roar_out_b[0] == null:
			roar_out_b[0] = old
	)
	# No pre-queue: A0 auto-targets B0 (combatant 2, default for combatant 0).
	# def_field_slot = 2 % 2 = 0 → forces B0's slot.
	bm_b.start_battle_doubles(
			_doubles_party(a0b, a1b), _doubles_party_bench(b0b, b1b, b2b))

	_chk("B9.02 Roar targeting combatant 2 forced out B0 (not B1)", roar_out_b[0] == b0b)
	bm_b.queue_free()


# ── C1-C3: Doubles AI decision tests ─────────────────────────────────────────
#
# All three are TrainerAI unit tests (no BattleManager) using choose_action_doubles
# directly. Force-roll=100 and force-crit=false make damage estimates deterministic.
#
# Source: ChooseMoveOrAction_Doubles (battle_ai_main.c L918-1038).
#   Per-(move, target) scoring: scores all moves vs each opponent slot independently,
#   then picks the (move, target) pair with the highest score.
#
# AI_AttacksPartner (flag 30, L6045) — confirmed absent for trainer AI.
#   Only fires for IsNaturalEnemy wild battles or AI_FLAG_ATTACKS_PARTNER_FOCUSES_PARTNER.
#   Trainer doubles AI never deliberately targets its own ally. See docs/decisions.md.


# ── C1: AI picks spread move that KOs despite 0.75× reduction ─────────────────
#
# AI has spread (Normal, power=90) and tackle (Normal, power=40). Both opponents alive.
# Spread triggers 0.75× per-target reduction. Spread still OHKOs (109 ≥ 70) → FAST_KILL.
# Tackle does not OHKO (66 < 70) → no bonus. No separate spread bonus exists in source:
# AI_CalcDamage → GetTargetDamageModifier already incorporates 0.75× into simulatedDmg.
#
# Arithmetic (AI base_atk=200→stat=205, Normal type, defenders base_def=80→stat=85,
#              base_hp=10→max_hp=70 at L50, force_roll=100, no weather, AI faster):
#
#   Spread (is_spread=true, 2 live targets), power=90:
#     Base: 90*205*22/85/50+2 = 97.  Spread 0.75×: (97*3072+2047)/4096 = 73.
#     Roll=100: 73.  STAB: (73*6144+2047)/4096 = 109 ≥ 70 → OHKO → +FAST_KILL(6).
#     Score = 106.
#
#   Tackle (is_spread=false), power=40:
#     Base: 40*205*22/85/50+2 = 44.  Roll=100: 44.  STAB: (44*6144+2047)/4096 = 66.
#     66 < 70 → no OHKO.  Score = 100.
#
# 106 > 100 → AI chooses spread (index 0).

func _test_c1_ai_prefers_spread_two_targets() -> void:
	var ai := TrainerAI.new()
	ai._force_roll = 100
	ai._force_crit = false

	var spread_move := _make_spread("TestSpread", 90, TypeChart.TYPE_NORMAL)
	var tackle := _load_move(33)

	var ai_mon := _make_mon("AI", 100, 200, 80, 80, 80, 100)
	ai_mon.add_move(spread_move)   # index 0
	ai_mon.add_move(tackle)        # index 1

	var b0 := _make_mon("B0", 10, 80, 80, 80, 80, 80)
	var b1 := _make_mon("B1", 10, 80, 80, 80, 80, 40)

	var action := ai.choose_action_doubles(
			ai_mon, null,
			b0, 2, b1, 3,
			BattleParty.new(), BattleParty.new())

	_chk("C1.01 AI picks spread (index 0) when 2 live opponents", action["index"] == 0)
	_chk("C1.02 action type is move", action["type"] == "move")


# ── C2: AI avoids immune spread, picks non-immune single-target move ───────────
#
# AI has ground-spread (Ground, power=80) and tackle (Normal, power=40).
# Only 1 live opponent (B0 is Flying type, immune to Ground; B1 is fainted).
# Ground effectiveness vs Flying = 0.0 → spread scores -20 (early return = 80).
# Tackle scores 100 (no KO at force-roll=100, no type bonus; Normal vs Flying = 1×).
#
# Score ground-spread vs B0: 80.  Score tackle vs B0: 100.  Tackle wins → index 1.

func _test_c2_ai_avoids_immune_spread() -> void:
	var ai := TrainerAI.new()
	ai._force_roll = 100
	ai._force_crit = false

	var ground_spread := _make_spread("TestGroundSpread", 80, TypeChart.TYPE_GROUND)
	var tackle := _load_move(33)

	var ai_mon := _make_mon("AI", 100, 80, 80, 80, 80, 80)
	ai_mon.add_move(ground_spread)  # index 0
	ai_mon.add_move(tackle)         # index 1

	var b0 := _make_mon_typed("B0", TypeChart.TYPE_FLYING)
	var b1 := _make_mon("B1", 1, 80, 80, 80, 80, 40)
	b1.fainted = true  # only B0 is alive

	var action := ai.choose_action_doubles(
			ai_mon, null,
			b0, 2, b1, 3,
			BattleParty.new(), BattleParty.new())

	_chk("C2.01 AI picks tackle (index 1) over immune ground-spread", action["index"] == 1)
	_chk("C2.02 AI targets live opponent (B0 slot, opp0_idx=2)", action["target"] == 2)


# ── C3: AI targets the weakened slot (KO opportunity) ─────────────────────────
#
# AI has tackle (Normal, power=40). Two live opponents: B0 at full HP, B1 at 1 HP.
# Score tackle vs B0: 100 (no KO).
# Score tackle vs B1: 106 (KO → +FAST_KILL=6).
# B1 wins → AI targets opp1_idx=3.
#
# Arithmetic (AI base_atk=100→stat=105, base_spd=100→stat=105 > B1 spd stat=85):
#   Base: 40*105*22/85/50+2 = 23.  Roll=100: 23.  STAB: (23*6144+2047)/4096 = 34.
#   B1.current_hp=1 → 34 ≥ 1 → KO → AI faster → FAST_KILL(+6) → score=106.
#   B0 max_hp=61, damage=34 < 61 → no KO → score=100.

func _test_c3_ai_targets_weak_slot() -> void:
	var ai := TrainerAI.new()
	ai._force_roll = 100
	ai._force_crit = false

	var tackle := _load_move(33)

	var ai_mon := _make_mon("AI", 100, 100, 80, 80, 80, 100)
	ai_mon.add_move(tackle)

	var b0 := _make_mon("B0", 1, 80, 80, 80, 80, 80)   # full HP (max_hp=61)
	var b1 := _make_mon("B1", 1, 80, 80, 80, 80, 80)   # at 1 HP
	b1.current_hp = 1

	var action := ai.choose_action_doubles(
			ai_mon, null,
			b0, 2, b1, 3,
			BattleParty.new(), BattleParty.new())

	_chk("C3.01 AI targets weakened B1 (opp1_idx=3)", action["target"] == 3)
	_chk("C3.02 AI chooses tackle (index 0)", action["index"] == 0)
