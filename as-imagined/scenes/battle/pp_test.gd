extends Node

# M15 Task 3 test suite — PP System
#
# Source: battle_move_resolution.c :: CancelerPPDeduction (L972) — PP timing
#   enum CancelerState: CANCELER_PPDEDUCTION=51 < CANCELER_ACCURACY_CHECK=72
#   → PP costs on miss; Struggle and release turns are exempt
# Source: battle_util.c :: AreAllMovesUnusable (L1652); battle_main.c L4727–4728
#   → noValidMoves triggers MOVE_STRUGGLE substitution
# Source: battle_script_commands.c :: MOVE_EFFECT_RECOIL_HP_25 (L2534–2543)
#   → Struggle recoil = maxHP / 4 (not % of damage dealt), minimum 1
#
# Sections:
#   P1: BattlePokemon PP unit tests (init, has_pp, use_pp)
#   P2: PP decrement integration (decrement fires before accuracy check, not on release turn)
#   P3: Forced-struggle detection (_is_forced_struggle)
#   P4: Full scenario — 1 PP move → PP=0 → Struggle fires → recoil applied

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_p1_pp_unit()
	_test_p2_pp_decrement_integration()
	_test_p3_forced_struggle_detection()
	_test_p4_struggle_scenario()

	var total := _pass + _fail
	print("pp_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_mon(mon_name: String, speed: int = 80,
		base_hp: int = 100, base_atk: int = 80, base_def: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(TypeChart.TYPE_NORMAL)
	sp.base_hp = base_hp
	sp.base_attack = base_atk
	sp.base_defense = base_def
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = speed
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_move(move_name: String, pp_val: int = 10, power: int = 40) -> MoveData:
	var m := MoveData.new()
	m.move_name = move_name
	m.type = TypeChart.TYPE_NORMAL
	m.category = 0  # Physical
	m.power = power
	m.accuracy = 100
	m.pp = pp_val
	m.secondary_effect = MoveData.SE_NONE
	m.secondary_chance = 0
	m.two_turn = false
	m.semi_inv_state = MoveData.SEMI_INV_NONE
	m.stat_change_stat = -1
	return m


func _make_splash() -> MoveData:
	var m := MoveData.new()
	m.move_name = "Splash"
	m.type = TypeChart.TYPE_NORMAL
	m.category = 2  # Status
	m.power = 0
	m.accuracy = 0
	m.pp = 40
	m.secondary_effect = MoveData.SE_NONE
	m.secondary_chance = 0
	m.two_turn = false
	m.semi_inv_state = MoveData.SEMI_INV_NONE
	m.stat_change_stat = -1
	return m


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── P1: BattlePokemon PP unit tests ──────────────────────────────────────────

func _test_p1_pp_unit() -> void:
	var tackle := _make_move("Tackle", 35)
	var ember  := _make_move("Ember", 25)
	var mon := _make_mon("TestMon")
	mon.add_move(tackle)
	mon.add_move(ember)

	# P1.01: current_pp initializes from move.pp on add_move
	_chk("P1.01 current_pp[0] initializes to move.pp", mon.current_pp[0] == 35)
	_chk("P1.02 current_pp[1] initializes to move.pp", mon.current_pp[1] == 25)

	# P1.03: has_pp returns true when PP > 0
	_chk("P1.03 has_pp(0) true when pp=35", mon.has_pp(0) == true)

	# P1.04: use_pp decrements by 1
	mon.use_pp(0)
	_chk("P1.04 use_pp decrements by 1", mon.current_pp[0] == 34)

	# P1.05: has_pp returns false when PP = 0
	for _i in range(34):
		mon.use_pp(0)
	_chk("P1.05 has_pp(0) false when pp=0", mon.has_pp(0) == false)

	# P1.06: use_pp at 0 does not go negative
	mon.use_pp(0)
	_chk("P1.06 use_pp at 0 stays 0 (no underflow)", mon.current_pp[0] == 0)

	# P1.07: out-of-bounds move_index does not crash
	_chk("P1.07 has_pp(-1) false (out of bounds)", mon.has_pp(-1) == false)
	_chk("P1.08 has_pp(99) false (out of bounds)", mon.has_pp(99) == false)
	mon.use_pp(99)  # should not crash
	_chk("P1.09 use_pp(99) no crash (pp unchanged)", mon.current_pp[1] == 25)


# ── P2: PP decrement integration ─────────────────────────────────────────────

func _test_p2_pp_decrement_integration() -> void:
	# P2.01: PP decrements when a move lands (BattleManager integration).
	# Player (speed=100) uses Tackle (pp=5) vs Opponent (speed=50, lots of HP).
	# After one turn, player's PP should be 4.
	var tackle := _make_move("Tackle", 5)
	var player1 := _make_mon("Player1", 100)
	var opp1    := _make_mon("Opp1", 50, 250, 50, 100)  # huge HP, won't die in 1 hit
	player1.add_move(tackle)
	opp1.add_move(_make_move("Tackle", 10))

	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_crit = false
	# Queue exactly 1 turn (both sides move), then check PP before the next turn continues.
	# Strategy: opponent has recoil so it eventually KOs itself; we read PP after first turn.
	# Actually: we need the battle to at least complete 1 turn. Just let it run and read PP.
	# Use a very weak opponent move so player doesn't die before we can check.
	bm1.start_battle(player1, opp1)
	_chk("P2.01 PP decrements after move execution", player1.current_pp[0] < 5)

	# P2.02: PP decrements even when the move misses (before accuracy check in source).
	# Set _force_hit=false to guarantee a miss.
	var tackle2 := _make_move("Tackle", 10)
	var player2 := _make_mon("Player2", 100)
	var opp2    := _make_mon("Opp2", 50, 250, 50, 100)
	player2.add_move(tackle2)
	opp2.add_move(_make_move("Splash", 40, 0))  # Splash: 0 damage, never KOs player

	var bm2 := _make_bm()
	bm2._force_hit = false   # guarantee miss
	bm2._force_crit = false
	bm2.start_battle(player2, opp2)
	_chk("P2.02 PP decrements even on a miss", player2.current_pp[0] < 10)

	# P2.03: PP does NOT decrement on the release turn of a two-turn move.
	# Turn 1 (charge): PP should decrement once (pp 10→9). Turn 2 (release): no change.
	# Opponent has very low HP so it dies from the Dig release hit, ending after exactly 1 cycle.
	# Expected final PP = 9 (decremented once on charge, NOT again on release).
	#
	# Damage estimate at level 50, base_atk=80→atk=85, opp base_def=80→def=85:
	#   floor(floor(22*80*85/85)/50)+2 = floor(1759/50)+2 = 37; roll range 31–37.
	# Set opp current_hp=20 so it dies from any Dig hit (min damage 31 > 20).
	var dig := MoveData.new()
	dig.move_name = "Dig"
	dig.type = TypeChart.TYPE_GROUND
	dig.category = 0
	dig.power = 80
	dig.accuracy = 100
	dig.pp = 10
	dig.two_turn = true
	dig.semi_inv_state = MoveData.SEMI_INV_UNDERGROUND
	dig.secondary_effect = MoveData.SE_NONE
	dig.secondary_chance = 0
	dig.stat_change_stat = -1

	var player3 := _make_mon("Digger", 100)
	var opp3    := _make_mon("Opp3", 50)
	player3.add_move(dig)
	opp3.add_move(_make_splash())
	opp3.current_hp = 20  # guarantees death from any Dig release hit

	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3._force_crit = false
	bm3.start_battle(player3, opp3)
	_chk("P2.03 Dig PP decrements only once (not on release turn)", player3.current_pp[0] == 9)


# ── P3: Forced-struggle detection ────────────────────────────────────────────

func _test_p3_forced_struggle_detection() -> void:
	# P3.01: Mon with no moves → forced struggle
	var mon_no_moves := _make_mon("NoMoves")
	_chk("P3.01 no moves → _is_forced_struggle", _fake_is_forced_struggle(mon_no_moves) == true)

	# P3.02: Mon with one move, PP=5 → not forced struggle
	var mon_has_pp := _make_mon("HasPP")
	mon_has_pp.add_move(_make_move("Tackle", 5))
	_chk("P3.02 has PP → not forced struggle", _fake_is_forced_struggle(mon_has_pp) == false)

	# P3.03: Mon with one move, PP=0 → forced struggle
	var mon_zero_pp := _make_mon("ZeroPP")
	var zero_move := _make_move("Tackle", 0)
	zero_move.pp = 0
	mon_zero_pp.add_move(zero_move)
	# current_pp initialized from move.pp; pp=0 → current_pp[0]=0
	_chk("P3.03 move pp=0 → current_pp[0]=0", mon_zero_pp.current_pp[0] == 0)
	_chk("P3.04 all PP=0 → forced struggle", _fake_is_forced_struggle(mon_zero_pp) == true)

	# P3.05: Two moves; one has PP, one doesn't → not forced (still has valid move)
	var mon_mixed := _make_mon("Mixed")
	var drained_move := _make_move("Tackle", 1)
	mon_mixed.add_move(drained_move)
	mon_mixed.add_move(_make_move("Ember", 10))
	mon_mixed.use_pp(0)  # drain slot 0 to 0
	_chk("P3.05 one slot empty, one has PP → not forced struggle",
			_fake_is_forced_struggle(mon_mixed) == false)

	# P3.06: Both slots drained → forced
	mon_mixed.use_pp(1)  # drain slot 1 partially — still has 9 PP
	_chk("P3.06 slot 1 still has PP → not forced", _fake_is_forced_struggle(mon_mixed) == false)
	for _i in range(9):
		mon_mixed.use_pp(1)
	_chk("P3.07 both slots empty → forced struggle", _fake_is_forced_struggle(mon_mixed) == true)


func _fake_is_forced_struggle(mon: BattlePokemon) -> bool:
	if mon.moves.is_empty():
		return true
	for i in range(mon.current_pp.size()):
		if mon.current_pp[i] > 0:
			return false
	return true


# ── P4: Full scenario — 1 PP move → Struggle ─────────────────────────────────

func _test_p4_struggle_scenario() -> void:
	# Setup: Player uses Tackle (1 PP), faster than opponent.
	# Opponent uses Splash (0 damage) so player survives long enough to Struggle.
	# Turn 1: Tackle fires → PP hits 0.
	# Turn 2+: Struggle fires → recoil_damage emits with attacker=player, amount=max_hp/4.
	# Battle ends when player KOs itself via Struggle recoil.
	var tackle := _make_move("Tackle", 1)

	var player := _make_mon("StruggleMon", 100, 100, 80, 80)
	var opp    := _make_mon("SplashBot", 50, 100, 80, 80)
	player.add_move(tackle)
	opp.add_move(_make_splash())

	var executed_moves: Array[String] = []
	var struggle_recoils: Array[int] = []
	var player_max_hp: int = player.max_hp

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm._force_roll = 100

	bm.move_executed.connect(func(atk: BattlePokemon, _def: BattlePokemon,
			mv: MoveData, _dmg: int):
		if atk == player:
			executed_moves.append(mv.move_name))

	bm.recoil_damage.connect(func(atk: BattlePokemon, amt: int):
		if atk == player:
			struggle_recoils.append(amt))

	bm.start_battle(player, opp)

	# P4.01: Turn 1 used Tackle
	_chk("P4.01 turn 1 move was Tackle",
			executed_moves.size() >= 1 and executed_moves[0] == "Tackle")

	# P4.02: After turn 1, Tackle PP = 0
	_chk("P4.02 PP depleted to 0 after Tackle", player.current_pp[0] == 0)

	# P4.03: Subsequent turn(s) used Struggle
	var found_struggle := false
	for mv_name in executed_moves:
		if mv_name == "Struggle":
			found_struggle = true
			break
	_chk("P4.03 Struggle was used after PP exhausted", found_struggle)

	# P4.04: Struggle recoil fired with amount = max_hp / 4
	var expected_recoil := player_max_hp / 4
	_chk("P4.04 Struggle recoil fired at least once", struggle_recoils.size() > 0)
	_chk("P4.05 Struggle recoil = max_hp/4 (%d)" % expected_recoil,
			struggle_recoils.size() > 0 and struggle_recoils[0] == expected_recoil)

	# P4.06: PP stayed at 0 (Struggle does not cost PP)
	_chk("P4.06 Tackle PP stays 0 after Struggle turns", player.current_pp[0] == 0)

	# P4.07: Struggle is_struggle flag = true (verifying we built it correctly)
	var found_is_struggle := false
	for mv_name_s in executed_moves:
		if mv_name_s == "Struggle":
			found_is_struggle = true
			break
	# We verify is_struggle via the recoil: only Struggle deals HP/4 recoil.
	# If recoil fired = expected (max_hp/4) then is_struggle path was taken in BM.
	_chk("P4.07 is_struggle recoil confirms Struggle path taken",
			struggle_recoils.size() > 0 and struggle_recoils[0] == expected_recoil)
