extends Node

# M16 Milestone-End Review — Area 3: Trick Room x Pursuit turn-order integrity
#
# M16d added Trick Room's speed-reversal to _phase_priority_resolution's sort_custom
# comparator. M16e added Pursuit's mid-resolution re-targeting (_pursuit_targets_switcher)
# to the same phase. This suite exercises the two together, which neither m16d_test.gd nor
# m16e_test.gd did in isolation.
#
# Doubles x Trick Room x Pursuit is explicitly OUT of scope here (both prior suites are
# singles-only) — flagged in docs/decisions.md's [M16 Review] entry rather than tested.
#
# Ground truth: pokeemerald_expansion

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_trick_room_pursuit_interception()
	_test_section_2_trick_room_unaffected_by_pursuit_presence()

	var total := _pass + _fail
	print("m16_review_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_move(id: int) -> MoveData:
	var path := "res://data/moves/move_%04d.tres" % id
	return load(path) as MoveData


func _make_mon(species_name: String, level: int, types: Array[int],
		base_hp: int = 80, base_atk: int = 80, base_def: int = 80,
		base_spatk: int = 80, base_spdef: int = 80, base_speed: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = species_name
	sp.types = types
	sp.base_hp = base_hp
	sp.base_attack = base_atk
	sp.base_defense = base_def
	sp.base_sp_attack = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed = base_speed
	return BattlePokemon.from_species(sp, level, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [M18.5h-1/2] pinned neutral nature + zero IVs -- exact-value assertions predate both


# ── Section 1: Trick Room active + Pursuit interception still fires correctly ────────────

func _test_section_1_trick_room_pursuit_interception() -> void:
	var pursuit := _load_move(228)
	var tackle := _load_move(33)

	# S1.01 Pursuit user is SLOWER than the switcher. Under Trick Room, speed comparisons
	# invert — but Pursuit's interception branches in the comparator return before the
	# speed-comparison code is ever reached for this pair, so the (slower) pursuer should
	# still strike the (faster) switcher before its switch resolves, same as without Trick
	# Room. Confirms Trick Room's inversion doesn't accidentally suppress interception.
	var atk1 := _make_mon("TRP_A1", 50, [TypeChart.TYPE_NORMAL], 300, 100, 100, 80, 80, 30)
	var def1 := _make_mon("TRP_D1", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 100)
	var bench1 := _make_mon("TRP_B1", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 100)
	atk1.add_move(pursuit)
	def1.add_move(tackle)
	bench1.add_move(tackle)
	var opp_party1 := BattleParty.new()
	opp_party1.members = [def1, bench1]
	opp_party1.active_index = 0
	var dmg1_target: Array = [null]
	var bench1_hp_at_pursuit: Array[int] = [-1]
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.trick_room_turns = 5
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.move_executed.connect(func(_a, d, mv: MoveData, _dmg: int):
		if mv == pursuit and dmg1_target[0] == null:
			dmg1_target[0] = d
			bench1_hp_at_pursuit[0] = bench1.current_hp)
	bm1.queue_switch(1, 1)
	bm1.start_battle_with_parties(BattleParty.single(atk1), opp_party1)
	bm1.queue_free()
	_chk("S1.01 Under Trick Room, a SLOWER Pursuit user still intercepts the switcher",
			dmg1_target[0] == def1)
	_chk("S1.02 Under Trick Room, the replacement took no Pursuit damage at that moment",
			bench1_hp_at_pursuit[0] == bench1.max_hp)

	# S1.03 Mirror case: Pursuit user is FASTER than the switcher. Interception should still
	# fire identically (speed direction is irrelevant to the interception decision either
	# way — it's a jump-the-queue override, not a speed comparison).
	var atk3 := _make_mon("TRP_A3", 50, [TypeChart.TYPE_NORMAL], 300, 100, 100, 80, 80, 150)
	var def3 := _make_mon("TRP_D3", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 40)
	var bench3 := _make_mon("TRP_B3", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 40)
	atk3.add_move(pursuit)
	def3.add_move(tackle)
	bench3.add_move(tackle)
	var opp_party3 := BattleParty.new()
	opp_party3.members = [def3, bench3]
	opp_party3.active_index = 0
	var dmg3_target: Array = [null]
	var bench3_hp_at_pursuit: Array[int] = [-1]
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.trick_room_turns = 5
	bm3._force_hit = true
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.move_executed.connect(func(_a, d, mv: MoveData, _dmg: int):
		if mv == pursuit and dmg3_target[0] == null:
			dmg3_target[0] = d
			bench3_hp_at_pursuit[0] = bench3.current_hp)
	bm3.queue_switch(1, 1)
	bm3.start_battle_with_parties(BattleParty.single(atk3), opp_party3)
	bm3.queue_free()
	_chk("S1.03 Under Trick Room, a FASTER Pursuit user still intercepts the switcher",
			dmg3_target[0] == def3)
	_chk("S1.04 Under Trick Room, the replacement (faster-pursuer case) took no damage",
			bench3_hp_at_pursuit[0] == bench3.max_hp)

	# S1.05/S1.06 Power still doubles under Trick Room (matches the M16e non-Trick-Room
	# result via direct DamageCalculator comparison) and the queued switch still completes.
	var expected1: Dictionary = DamageCalculator.calculate(
			atk1, def1, pursuit, 100, false, 0, false, false, 80)
	var dmg1_amount: Array[int] = [-1]
	var switched_in1: Array = []
	var bm1b := BattleManager.new()
	add_child(bm1b)
	bm1b.trick_room_turns = 5
	bm1b._force_hit = true
	bm1b._force_roll = 100
	bm1b._force_crit = false
	var atk1b := _make_mon("TRP_A1b", 50, [TypeChart.TYPE_NORMAL], 300, 100, 100, 80, 80, 30)
	var def1b := _make_mon("TRP_D1b", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 100)
	var bench1b := _make_mon("TRP_B1b", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 100)
	atk1b.add_move(pursuit)
	def1b.add_move(tackle)
	bench1b.add_move(tackle)
	var opp_party1b := BattleParty.new()
	opp_party1b.members = [def1b, bench1b]
	opp_party1b.active_index = 0
	bm1b.move_executed.connect(func(_a, _d, mv: MoveData, dmg: int):
		if mv == pursuit and dmg1_amount[0] == -1:
			dmg1_amount[0] = dmg)
	bm1b.pokemon_switched_in.connect(func(p: BattlePokemon, _s: int, _sl: int):
		switched_in1.append(p))
	bm1b.queue_switch(1, 1)
	bm1b.start_battle_with_parties(BattleParty.single(atk1b), opp_party1b)
	bm1b.queue_free()
	_chk("S1.05 Doubled power under Trick Room matches the calculator's power_override=80 result",
			dmg1_amount[0] == expected1["damage"])
	_chk("S1.06 The queued switch still completes after Pursuit's hit under Trick Room",
			switched_in1.any(func(p): return p == bench1b))


# ── Section 2: Trick Room's own speed-reversal unaffected by an idle Pursuit move ────────

func _test_section_2_trick_room_unaffected_by_pursuit_presence() -> void:
	var pursuit := _load_move(228)
	var tackle := _load_move(33)

	# S2.01 Trick Room active, target does NOT switch this turn (ordinary move exchange).
	# The naturally SLOWER Pursuit-carrying Pokémon should still act FIRST, exactly as any
	# other slower Pokémon would under Trick Room — proving Pursuit's interception branches
	# (which gate on an actual queued switch) don't leak into or short-circuit the ordinary
	# Trick-Room-governed comparison when nobody is switching.
	var slow_pursuiter := _make_mon("TRP_S1", 50, [TypeChart.TYPE_NORMAL], 300, 100, 100, 80, 80, 30)
	var fast_mon := _make_mon("TRP_F1", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 150)
	slow_pursuiter.add_move(pursuit)
	fast_mon.add_move(tackle)
	var order2: Array[BattlePokemon] = []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.trick_room_turns = 5
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_executed.connect(func(a: BattlePokemon, _d, _mv: MoveData, _dmg: int):
		if order2.size() < 2:
			order2.append(a))
	bm2.start_battle(slow_pursuiter, fast_mon)
	bm2.queue_free()
	_chk("S2.01 Trick Room's speed reversal still applies normally to a Pursuit-carrying "
			+ "Pokémon when its target isn't switching (slower Pursuit user acts first)",
			order2.size() == 2 and order2[0] == slow_pursuiter and order2[1] == fast_mon)

	# S2.02 Sanity check without Trick Room: the same matchup has the faster mon act first,
	# confirming S2.01 is really Trick Room's doing.
	var slow_pursuiter2 := _make_mon("TRP_S2", 50, [TypeChart.TYPE_NORMAL], 300, 100, 100, 80, 80, 30)
	var fast_mon2 := _make_mon("TRP_F2", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 150)
	slow_pursuiter2.add_move(pursuit)
	fast_mon2.add_move(tackle)
	var order3: Array[BattlePokemon] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_hit = true
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.move_executed.connect(func(a: BattlePokemon, _d, _mv: MoveData, _dmg: int):
		if order3.size() < 2:
			order3.append(a))
	bm3.start_battle(slow_pursuiter2, fast_mon2)
	bm3.queue_free()
	_chk("S2.02 Without Trick Room, the faster (non-Pursuit-carrying) mon acts first",
			order3.size() == 2 and order3[0] == fast_mon2 and order3[1] == slow_pursuiter2)
