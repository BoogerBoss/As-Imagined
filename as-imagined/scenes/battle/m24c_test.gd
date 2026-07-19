extends Node

# [M24c] AI-Tier Extension — a narrow orthogonal ai_flags bitmask layered on
# top of the pre-existing tier/Tier enum, covering the 6 real AI-flag
# combinations across all 854 real trainers (docs/m24_recon.md §2), plus a
# deliberately narrow slice of the 2 modifiers (RISKY/FORCE_SETUP_FIRST_TURN)
# — see trainer_ai.gd's own doc comments for the full Step 0 citations and
# explicit "what's ported vs. what's flagged for later" scoping per pass.
#
# Section A: data integrity (flag bit values, from_trainer_data() identity copy).
# Section B: each of the 6 real combinations produces the correct gated
#   scoring behavior, direct _score_move-level (deterministic, no RNG).
# Section C: choose_action()-level — CHECK_VIABILITY gates _apply_best_damage_move.
# Section D: FORCE_SETUP_FIRST_TURN — both a direct is_first_turn=true/false
#   comparison and a real 2-turn full-battle integration (turn 1 prioritizes
#   the setup move, turn 2 reverts to attacking).
# Section E: RISKY — _effective_ai_roll() direct unit tests plus a
#   deterministic (crit-stage-bonus-driven) move-selection integration test.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_data_integrity()
	_test_section_b_six_real_combinations()
	_test_section_c_check_viability_gates_best_damage_move()
	_test_section_d_force_setup_first_turn()
	_test_section_e_risky()

	var total := _pass + _fail
	print("m24c_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		hp: int = 160, atk: int = 80, def_stat: int = 80,
		spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_setup_move(move_name: String) -> MoveData:
	var m := MoveData.new()
	m.move_name = move_name
	m.type = TypeChart.TYPE_NORMAL
	m.category = 2  # status
	m.power = 0
	m.accuracy = 100
	m.pp = 20
	m.stat_change_self = true
	m.stat_change_stat = 1  # STAT_ATK-equivalent ordinal, value itself unused by the AI check
	m.stat_change_amount = 2
	return m


# ── Section A: data integrity ───────────────────────────────────────────────

func _test_section_a_data_integrity() -> void:
	_chk("A.01 AI_FLAG_CHECK_BAD_MOVE == 1", TrainerAI.AI_FLAG_CHECK_BAD_MOVE == 1)
	_chk("A.02 AI_FLAG_TRY_TO_FAINT == 2", TrainerAI.AI_FLAG_TRY_TO_FAINT == 2)
	_chk("A.03 AI_FLAG_CHECK_VIABILITY == 4", TrainerAI.AI_FLAG_CHECK_VIABILITY == 4)
	_chk("A.04 AI_FLAG_FORCE_SETUP_FIRST_TURN == 8", TrainerAI.AI_FLAG_FORCE_SETUP_FIRST_TURN == 8)
	_chk("A.05 AI_FLAG_RISKY == 16", TrainerAI.AI_FLAG_RISKY == 16)
	_chk("A.06 AI_FLAG_BASIC_TRAINER == 7 (CHECK_BAD_MOVE|TRY_TO_FAINT|CHECK_VIABILITY)",
			TrainerAI.AI_FLAG_BASIC_TRAINER == 7)
	_chk("A.07 default ai_flags on a fresh TrainerAI is AI_FLAG_BASIC_TRAINER (backward-compat)",
			TrainerAI.new().ai_flags == TrainerAI.AI_FLAG_BASIC_TRAINER)

	var td := TrainerData.new()
	td.ai_flags = 23  # "Basic Trainer / Risky"
	var ai := TrainerAI.from_trainer_data(td)
	_chk("A.08 from_trainer_data() is a plain identity copy of TrainerData.ai_flags",
			ai.ai_flags == 23)
	_chk("A.09 from_trainer_data() always uses BASIC tier (no real combo uses SMART_SWITCHING)",
			ai.tier == TrainerAI.Tier.BASIC)


# ── Section B: the 6 real combinations, direct _score_move-level ───────────

func _test_section_b_six_real_combinations() -> void:
	var attacker := _make_mon("Attacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 200, 200, 80, 80, 80, 200)
	var lethal_move := _load_move(33)  # Tackle
	var defender := _make_mon("Defender", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 1, 20, 20, 20, 20, 20)

	# Combo: "Check Bad Move" alone (640/854 trainers) — TRY_TO_FAINT is OFF,
	# so a guaranteed-lethal move gets NO FAST_KILL/SLOW_KILL bonus at all.
	var ai_cbm := TrainerAI.new()
	ai_cbm.ai_flags = 1
	ai_cbm._force_roll = 100
	ai_cbm._force_crit = false
	var score_cbm: int = ai_cbm._score_move(attacker, defender, lethal_move)
	_chk("B.01 'Check Bad Move' alone: lethal move scores base default (no TRY_TO_FAINT bonus)",
			score_cbm == TrainerAI.AI_SCORE_DEFAULT)

	# Combo: "Check Bad Move / Try To Faint" (7/854) — TRY_TO_FAINT ON, but
	# CHECK_VIABILITY still OFF.
	var ai_cbmttf := TrainerAI.new()
	ai_cbmttf.ai_flags = 3
	ai_cbmttf._force_roll = 100
	ai_cbmttf._force_crit = false
	var score_cbmttf: int = ai_cbmttf._score_move(attacker, defender, lethal_move)
	_chk("B.02 'Check Bad Move / Try To Faint': lethal move gets the FAST_KILL bonus",
			score_cbmttf == TrainerAI.AI_SCORE_DEFAULT + TrainerAI.FAST_KILL)

	# Combo: "Basic Trainer" (173/854) — all 3 base passes on, matches the
	# OLD pre-M24c default BASIC behavior exactly (regression pin).
	var ai_basic := TrainerAI.new()
	ai_basic._force_roll = 100
	ai_basic._force_crit = false
	var score_basic: int = ai_basic._score_move(attacker, defender, lethal_move)
	_chk("B.03 'Basic Trainer' (default ai_flags): identical score to pre-M24c BASIC behavior",
			score_basic == score_cbmttf)

	# Combo: "Basic Trainer / Force Setup First Turn" (1/854).
	var setup_move := _make_setup_move("SetupMove")
	var ai_fsft := TrainerAI.new()
	ai_fsft.ai_flags = 15
	var score_fsft_turn1: int = ai_fsft._score_move(attacker, defender, setup_move,
			DamageCalculator.WEATHER_NONE, true)
	var score_fsft_turn2: int = ai_fsft._score_move(attacker, defender, setup_move,
			DamageCalculator.WEATHER_NONE, false)
	_chk("B.04 'Basic Trainer / Force Setup First Turn': setup move scores higher on turn 1",
			score_fsft_turn1 > score_fsft_turn2)
	_chk("B.05 ...and turn 1's bonus is exactly +DECENT_EFFECT",
			score_fsft_turn1 == score_fsft_turn2 + TrainerAI.DECENT_EFFECT)

	# Combo: "Basic Trainer / Risky" (5/854).
	var crit_move := _make_setup_move("CritMove")  # reuse as a plain non-lethal base; override category/power below
	crit_move.category = 0
	crit_move.power = 10
	crit_move.stat_change_self = false
	crit_move.stat_change_stat = -1
	crit_move.critical_hit_stage = 1
	var ai_risky := TrainerAI.new()
	ai_risky.ai_flags = 23
	ai_risky._force_roll = 85
	ai_risky._force_crit = false
	var ai_nonrisky := TrainerAI.new()
	ai_nonrisky.ai_flags = 7
	ai_nonrisky._force_roll = 85
	ai_nonrisky._force_crit = false
	var non_lethal_defender := _make_mon("Tanky", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 500, 20, 200, 20, 200, 20)
	var score_risky: int = ai_risky._score_move(attacker, non_lethal_defender, crit_move)
	var score_nonrisky: int = ai_nonrisky._score_move(attacker, non_lethal_defender, crit_move)
	_chk("B.06 'Basic Trainer / Risky': a high-crit-stage move scores higher under RISKY",
			score_risky == score_nonrisky + TrainerAI.DECENT_EFFECT)

	# Combo: "Check Bad Move / Try To Faint / Force Setup First Turn" (13/854).
	var ai_combo6 := TrainerAI.new()
	ai_combo6.ai_flags = 11
	ai_combo6._force_roll = 100
	ai_combo6._force_crit = false
	var combo6_lethal: int = ai_combo6._score_move(attacker, defender, lethal_move)
	var combo6_setup_t1: int = ai_combo6._score_move(attacker, defender, setup_move,
			DamageCalculator.WEATHER_NONE, true)
	_chk("B.07 combo 6: TRY_TO_FAINT fires (FAST_KILL) but CHECK_VIABILITY does not apply",
			combo6_lethal == TrainerAI.AI_SCORE_DEFAULT + TrainerAI.FAST_KILL)
	_chk("B.08 combo 6: FORCE_SETUP_FIRST_TURN still fires even without CHECK_VIABILITY",
			combo6_setup_t1 == TrainerAI.AI_SCORE_DEFAULT + TrainerAI.DECENT_EFFECT)


# ── Section C: choose_action() gates _apply_best_damage_move on CHECK_VIABILITY ──

func _test_section_c_check_viability_gates_best_damage_move() -> void:
	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 200, 200, 80, 80, 80, 100)
	var weak_move := _load_move(33)  # Tackle, low power
	var strong_move := _load_move(5)  # Mega Punch, higher power — should be preferred once BEST_DAMAGE_MOVE applies
	attacker.add_move(weak_move)
	attacker.add_move(strong_move)
	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 300, 20, 20, 20, 20, 20)
	var party := BattleParty.single(attacker)

	var ai_no_viability := TrainerAI.new()
	ai_no_viability.ai_flags = TrainerAI.AI_FLAG_CHECK_BAD_MOVE  # CHECK_VIABILITY off
	ai_no_viability._force_roll = 90
	ai_no_viability._force_crit = false
	var action_no_viability: Dictionary = ai_no_viability.choose_action(attacker, defender, party, party)

	var ai_with_viability := TrainerAI.new()
	ai_with_viability.ai_flags = TrainerAI.AI_FLAG_BASIC_TRAINER
	ai_with_viability._force_roll = 90
	ai_with_viability._force_crit = false
	var action_with_viability: Dictionary = ai_with_viability.choose_action(attacker, defender, party, party)

	_chk("C.01 with CHECK_VIABILITY: the higher-power move (fewer hits to KO) is chosen",
			action_with_viability["index"] == 1)
	_chk("C.02 without CHECK_VIABILITY: no BEST_DAMAGE_MOVE bonus, first tied-score move wins (index 0)",
			action_no_viability["index"] == 0)


# ── Section D: FORCE_SETUP_FIRST_TURN ───────────────────────────────────────

func _test_section_d_force_setup_first_turn() -> void:
	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 200, 20, 80, 20, 80, 100)
	var setup_move := _make_setup_move("SwordsDanceLike")
	var weak_attack := _load_move(33)  # Tackle — deliberately weak relative to attacker's own low Atk, no KO
	attacker.add_move(weak_attack)
	attacker.add_move(setup_move)
	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 300, 20, 200, 20, 200, 20)
	var party := BattleParty.single(attacker)

	var ai := TrainerAI.new()
	ai.ai_flags = TrainerAI.AI_FLAG_BASIC_TRAINER | TrainerAI.AI_FLAG_FORCE_SETUP_FIRST_TURN

	var action_turn1: Dictionary = ai.choose_action(attacker, defender, party, party,
			DamageCalculator.WEATHER_NONE, true)
	var action_turn2: Dictionary = ai.choose_action(attacker, defender, party, party,
			DamageCalculator.WEATHER_NONE, false)

	_chk("D.01 turn 1 (is_first_turn=true): the setup move is chosen (index 1)",
			action_turn1["index"] == 1)
	_chk("D.02 turn 2+ (is_first_turn=false): reverts to the ordinary tied-default choice (index 0)",
			action_turn2["index"] == 0)

	# Full-battle integration: confirm the SAME real distinction holds when
	# is_first_turn is threaded all the way from BattleManager's own
	# _pending_initial_switch_in, not just a direct choose_action() call.
	var moves_used := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(atk, _def, mv, _dmg):
		if atk == attacker:
			moves_used.append(mv.move_name))
	bm.set_trainer_ai(1, ai)
	var player := _make_mon("Player", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 300, 5, 200, 5, 200, 1)
	player.add_move(weak_attack)
	bm.start_battle(player, attacker)

	_chk("D.03 full-battle integration: the AI's first real move was the setup move",
			moves_used.size() > 0 and moves_used[0] == "SwordsDanceLike")
	bm.queue_free()


# ── Section E: RISKY ─────────────────────────────────────────────────────────

func _test_section_e_risky() -> void:
	var ai_risky := TrainerAI.new()
	ai_risky.ai_flags = TrainerAI.AI_FLAG_RISKY
	_chk("E.01 _effective_ai_roll() returns DMG_ROLL_HI (max) under RISKY with no test pin",
			ai_risky._effective_ai_roll() == DamageCalculator.DMG_ROLL_HI)

	var ai_non_risky := TrainerAI.new()
	ai_non_risky.ai_flags = TrainerAI.AI_FLAG_BASIC_TRAINER
	_chk("E.02 _effective_ai_roll() returns -1 (real random) without RISKY",
			ai_non_risky._effective_ai_roll() == -1)

	# A test-level force_roll pin always wins over RISKY's own assumption.
	ai_risky._force_roll = 90
	_chk("E.03 an explicit _force_roll pin overrides RISKY's own max-roll assumption",
			ai_risky._effective_ai_roll() == 90)

	# Explosion-move bonus (is_self_faint), a deterministic direct check.
	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 200, 80, 80, 80, 80, 80)
	var non_lethal_defender := _make_mon("Tanky", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 500, 20, 200, 20, 200, 20)
	var explosion_move := MoveData.new()
	explosion_move.move_name = "SelfDestructLike"
	explosion_move.type = TypeChart.TYPE_NORMAL
	explosion_move.category = 0
	explosion_move.power = 5  # deliberately weak so no other pass's bonus confounds the comparison
	explosion_move.accuracy = 100
	explosion_move.pp = 5
	explosion_move.is_self_faint = true

	var ai_risky2 := TrainerAI.new()
	ai_risky2.ai_flags = TrainerAI.AI_FLAG_RISKY
	ai_risky2._force_roll = 85
	ai_risky2._force_crit = false
	var score_explosion_risky: int = ai_risky2._score_move(attacker, non_lethal_defender, explosion_move)

	var ai_no_risky2 := TrainerAI.new()
	ai_no_risky2.ai_flags = 0
	ai_no_risky2._force_roll = 85
	ai_no_risky2._force_crit = false
	var score_explosion_no_risky: int = ai_no_risky2._score_move(attacker, non_lethal_defender, explosion_move)

	_chk("E.04 an explosion-shaped move (is_self_faint) scores +BEST_EFFECT under RISKY",
			score_explosion_risky == TrainerAI.AI_SCORE_DEFAULT + TrainerAI.BEST_EFFECT)
	_chk("E.05 ...and gets no such bonus without RISKY",
			score_explosion_no_risky == TrainerAI.AI_SCORE_DEFAULT)

	# Deterministic move-selection integration test (crit-stage-bonus-driven,
	# per the task's own "Risky measurably changes move selection" ask) —
	# two otherwise-equal-power moves, only one with an elevated crit stage;
	# RISKY should prefer it, non-RISKY should treat them as tied.
	var plain_move := MoveData.new()
	plain_move.move_name = "PlainMove"
	plain_move.type = TypeChart.TYPE_NORMAL
	plain_move.category = 0
	plain_move.power = 40
	plain_move.accuracy = 100
	plain_move.pp = 20
	var crit_move := MoveData.new()
	crit_move.move_name = "CritMove"
	crit_move.type = TypeChart.TYPE_NORMAL
	crit_move.category = 0
	crit_move.power = 40
	crit_move.accuracy = 100
	crit_move.pp = 20
	crit_move.critical_hit_stage = 2

	var risky_attacker := _make_mon("RiskyAtk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 200, 80, 80, 80, 80, 80)
	risky_attacker.add_move(plain_move)
	risky_attacker.add_move(crit_move)
	var tanky_defender := _make_mon("Tanky2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 500, 20, 200, 20, 200, 20)
	var risky_party := BattleParty.single(risky_attacker)

	var ai_pick_risky := TrainerAI.new()
	ai_pick_risky.ai_flags = TrainerAI.AI_FLAG_RISKY
	ai_pick_risky._force_roll = 85
	ai_pick_risky._force_crit = false
	ai_pick_risky._force_tie_rng = 0
	var risky_action: Dictionary = ai_pick_risky.choose_action(risky_attacker, tanky_defender, risky_party, risky_party)
	_chk("E.06 RISKY prefers the crit-stage move over an otherwise-identical plain move (index 1)",
			risky_action["index"] == 1)
