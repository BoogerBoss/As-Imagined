extends Node

# Milestone 14a test suite — Doubles foundation (4-combatant state machine + turn order)
#
# Sections:
#   D1: BattleParty doubles API + BattleManager 4-combatant setup
#   D2: Turn order — 4 distinct speeds, correct priority across all 4 combatants
#   D3: Battle ends only when a FULL SIDE is fainted (not just one field slot)
#   D4: Targeting — queue_move_targeted sends damage to the correct opposing slot
#   D5: Faint replacement — fainted slot is replaced without disturbing the partner slot
#   D6: Voluntary switch in doubles — queue_switch_for swaps one slot, leaves other intact
#
# Ground truth: pokeemerald_expansion
#   battle.h :: gBattlerPositions, B_POSITION_PLAYER_LEFT/RIGHT
#   battle_main.c :: turn order resolution / action execution loop
#   battle_main.c :: SwitchInClearSetData, FaintClearSetData
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
