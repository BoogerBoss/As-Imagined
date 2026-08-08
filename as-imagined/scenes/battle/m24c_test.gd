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
	_test_section_f_factories()
	_test_section_g_flag_table()
	_test_section_h_name_hints()
	_test_section_i_describe_party()

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


# ── Section F: [M27Q Q1] the two construction factories ─────────────────────
#
# ⚠️ **THIS SECTION EXISTS BECAUSE NOTHING ELSE COVERED THE FIX.** Q1 changed
# how `battle_screen_shared` BUILDS its TrainerAI, and every suite in this
# project constructs a `TrainerAI` by hand and assigns `ai_flags`/`tier`
# directly — so the whole regression sweep stayed green while exercising none
# of the new code. These assert the factories themselves, which is the half a
# headless suite can reach; the call-site branching is covered only by a live
# trainer battle (see this section's own closing note).
func _test_section_f_factories() -> void:
	# --- from_trainer_data: identity copy, matching GetTrainerAIFlagsFromId's
	# own plain `->aiFlags` field read (include/data.h:353).
	var d := TrainerData.new()
	d.ai_flags = TrainerAI.AI_FLAG_CHECK_BAD_MOVE | TrainerAI.AI_FLAG_RISKY  # 17
	var from_data := TrainerAI.from_trainer_data(d)
	_chk("F.01 from_trainer_data copies ai_flags verbatim",
			from_data.ai_flags == 17)

	# ⚠️ The bug Q1 fixed: this used to be Tier.SMART for every trainer alive.
	_chk("F.02 tier derives BASIC when SMART_SWITCHING is absent",
			from_data.tier == TrainerAI.Tier.BASIC)

	var d_smart := TrainerData.new()
	d_smart.ai_flags = TrainerAI.AI_FLAG_BASIC_TRAINER | TrainerAI.AI_FLAG_SMART_SWITCHING
	_chk("F.03 tier derives SMART when SMART_SWITCHING is present",
			TrainerAI.from_trainer_data(d_smart).tier == TrainerAI.Tier.SMART)

	# ⚠️ NOT vacuous, and this is the assertion that would catch a roster
	# regression: zero of the 1,477 converted trainers set bit 14, so F.02 is
	# the case every real battle takes and F.03 is reachable only from data
	# that does not exist yet. Asserting the flag's VALUE keeps the derivation
	# honest if AI_FLAG(14)'s encoding is ever mis-transcribed.
	_chk("F.04 SMART_SWITCHING is AI_FLAG(14), matching constants/battle_ai.h:24",
			TrainerAI.AI_FLAG_SMART_SWITCHING == 1 << 14)

	var d_zero := TrainerData.new()
	d_zero.ai_flags = 0
	var from_zero := TrainerAI.from_trainer_data(d_zero)
	_chk("F.05 ai_flags 0 survives the factory rather than falling back to the default",
			from_zero.ai_flags == 0 and from_zero.tier == TrainerAI.Tier.BASIC)

	# --- from_wild_level: GetWildAiFlags' two implementable thresholds
	# (battle_ai_main.c:231-238).
	_chk("F.06 wild below level 20 gets CHECK_BAD_MOVE alone",
			TrainerAI.from_wild_level(19).ai_flags == TrainerAI.AI_FLAG_CHECK_BAD_MOVE)
	_chk("F.07 wild at exactly level 20 gains CHECK_VIABILITY (>= , not >)",
			TrainerAI.from_wild_level(20).ai_flags
			== (TrainerAI.AI_FLAG_CHECK_BAD_MOVE | TrainerAI.AI_FLAG_CHECK_VIABILITY))
	_chk("F.08 a level-0/absent party still yields the CHECK_BAD_MOVE floor",
			TrainerAI.from_wild_level(0).ai_flags == TrainerAI.AI_FLAG_CHECK_BAD_MOVE)
	# A wild Pokemon has no party to switch to; source never gives one
	# SMART_SWITCHING.
	_chk("F.09 wild AI is never SMART tier",
			TrainerAI.from_wild_level(100).tier == TrainerAI.Tier.BASIC)
	# ⚠️ TRY_TO_2HKO (bit 5, avg>=60) and HP_AWARE (bit 8, avg>=80) are real
	# source thresholds this project does not implement. Asserted as ABSENT so
	# the gap is a recorded fact rather than an oversight — when either flag
	# lands, this assertion is what fails and points at `from_wild_level`.
	_chk("F.10 the two unimplemented high-level wild flags stay off at level 100",
			TrainerAI.from_wild_level(100).ai_flags
			== (TrainerAI.AI_FLAG_CHECK_BAD_MOVE | TrainerAI.AI_FLAG_CHECK_VIABILITY))


# ── Section G: [M27Q Q2] FLAG_TABLE cannot drift from the flag constants ────
#
# ⚠️ **THE POINT IS THAT THIS GUARD CANNOT GO STALE.** It does not compare
# FLAG_TABLE against a hand-written list of expected names — that would be a
# third copy with the same drift problem. It enumerates the script's OWN
# constants via get_script_constant_map(), so a flag added tomorrow is in the
# expected set automatically and the suite fails until its row exists.
#
# This is the guard the CHECK_VIABILITY bug would have wanted: two lists that
# had to agree, no mechanism forcing them to.
func _test_section_g_flag_table() -> void:
	var consts: Dictionary = TrainerAI.new().get_script().get_script_constant_map()
	var atomic := {}   # name -> value, every AI_FLAG_* except the composite
	for k in consts:
		var name := str(k)
		if name.begins_with("AI_FLAG_") and name != "AI_FLAG_BASIC_TRAINER":
			atomic[name] = consts[k]

	var tabled := {}   # value -> label, as FLAG_TABLE declares them
	var dup := false
	for row in TrainerAI.FLAG_TABLE:
		if tabled.has(row[1]):
			dup = true
		tabled[row[1]] = row[0]

	_chk("G.01 FLAG_TABLE has one row per atomic AI_FLAG_* constant",
			tabled.size() == atomic.size())
	var missing := PackedStringArray()
	for name in atomic:
		if not tabled.has(atomic[name]):
			missing.append(name)
	_chk("G.02 no atomic flag is absent from FLAG_TABLE (missing: %s)"
			% ", ".join(missing), missing.is_empty())
	_chk("G.03 no value appears twice in FLAG_TABLE", not dup)

	# The composite is deliberately NOT offered as a checkbox: it is bits 0-2,
	# so a fourth box could contradict the three beside it.
	_chk("G.04 the BASIC_TRAINER composite is excluded from FLAG_TABLE",
			not tabled.has(TrainerAI.AI_FLAG_BASIC_TRAINER)
			and TrainerAI.AI_FLAG_BASIC_TRAINER == 7)

	# --- the hint string TrainerData actually hands the Inspector
	var hint := TrainerAI.flags_hint_string()
	_chk("G.05 the hint uses Godot's explicit Name:value form, not positional",
			hint.contains("Check Bad Move:1") and hint.contains(":16384"))
	_chk("G.06 the hint has one entry per FLAG_TABLE row",
			hint.split(",").size() == TrainerAI.FLAG_TABLE.size())

	# ⚠️ Asserts the WIRING, not just the string: a correct hint that never
	# reaches the property would look identical from here.
	var td := TrainerData.new()
	var found := false
	for p in td.get_property_list():
		if p.name == "ai_flags":
			found = (p.hint == PROPERTY_HINT_FLAGS and p.hint_string == hint)
	_chk("G.07 TrainerData.ai_flags actually carries that hint via _validate_property",
			found)


# ── Section H: [M27Q Q2 follow-up] name dropdowns for the int fields ────────
#
# ⚠️ **H.03/H.04 ARE THE POINT OF THIS SECTION.** A "Name:value" dropdown that
# omits an id already present in the data does not merely look wrong — the
# control renders blank and the first click overwrites a real value with an
# unrelated one. Building the list from NAMED classes alone did exactly that:
# 11 of 117 converted classes carry no class_name_text and 7 of them are in
# use. These assertions are what caught it.
func _test_section_h_name_hints() -> void:
	var probe: TrainerData = ResourceLoader.load(
			"res://data/trainers/TRAINER_LASS_ROBIN_FRLG.tres")
	var class_hint := ""
	var item_hint := ""
	var class_kind := -1
	var item_kind := -1
	for p in probe.get_property_list():
		if p.name == "trainer_class_id":
			class_hint = str(p.hint_string); class_kind = p.hint
		elif p.name == "battle_items":
			item_hint = str(p.hint_string); item_kind = p.hint

	_chk("H.01 trainer_class_id is an enum of names", class_kind == PROPERTY_HINT_ENUM
			and class_hint.contains("COOLTRAINER:"))
	# An ARRAY hints its ELEMENTS through a packed type-string payload; setting
	# the enum on the array itself would hint the array, not the ints in it.
	_chk("H.02 battle_items hints its elements, not the array",
			item_kind == PROPERTY_HINT_TYPE_STRING
			and item_hint.begins_with("%d/%d:" % [TYPE_INT, PROPERTY_HINT_ENUM]))

	var class_ids := _hint_ids(class_hint)
	var item_ids := _hint_ids(item_hint)
	var missing_class := PackedStringArray()
	var missing_item := PackedStringArray()
	var dir := DirAccess.open("res://data/trainers")
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var t: TrainerData = ResourceLoader.load("res://data/trainers/" + f)
		if t == null:
			continue
		if not class_ids.has(t.trainer_class_id):
			missing_class.append(str(t.trainer_class_id))
		for it in t.battle_items:
			if not item_ids.has(int(it)):
				missing_item.append(str(it))
	_chk("H.03 every trainer_class_id in the roster is offered (missing: %s)"
			% ", ".join(missing_class), missing_class.is_empty())
	_chk("H.04 every battle item id in the roster is offered (missing: %s)"
			% ", ".join(missing_item), missing_item.is_empty())
	# The unnamed-but-used classes must be present AND legible as gaps.
	_chk("H.05 unnamed classes are listed as gaps rather than dropped",
			class_hint.contains("(unnamed)"))
	# ⚠️ Stored value is the real id, never a dropdown index — a positional
	# enum would reinterpret every existing .tres if a class were inserted.
	_chk("H.06 the hint encodes real ids, not positions",
			class_ids.has(probe.trainer_class_id) and probe.trainer_class_id == 68)


## ids out of a "Name:value,Name:value" hint, tolerating the array prefix.
func _hint_ids(hint: String) -> Dictionary:
	var out := {}
	var body := hint
	var colon := body.find(":")
	if body.begins_with("%d/%d:" % [TYPE_INT, PROPERTY_HINT_ENUM]):
		body = body.substr(colon + 1)
	for part in body.split(","):
		var bits := part.rsplit(":", true, 1)
		if bits.size() == 2:
			out[bits[1].to_int()] = true
	return out


# ── Section I: [M27Q Q3] the read-only party roster ─────────────────────────
#
# The panel that shows this contains no rules — it prints what describe_party()
# returns. These drive the rules.
func _test_section_i_describe_party() -> void:
	var robin: TrainerData = ResourceLoader.load(
			"res://data/trainers/TRAINER_LASS_ROBIN_FRLG.tres")
	var lines := robin.describe_party()
	_chk("I.01 one line per party member", lines.size() == robin.party.size())
	# Robin is the Kanto content anchor used elsewhere in this project:
	# dex 39 Jigglypuff at level 14.
	_chk("I.02 species resolves to a NAME, not a dex number",
			lines.size() > 0 and lines[0].contains("Jigglypuff"))
	_chk("I.03 the level is shown", lines.size() > 0 and lines[0].contains("Lv14"))

	# ⚠️ An empty move list is a REAL, common state — trainerproc leaves moves
	# unspecified and the engine derives them from the learnset at battle
	# start. Saying so beats an empty bracket, which reads as data loss.
	var blank := TrainerData.new()
	var m := TrainerPartyMon.new()
	m.species_dex = 25
	m.level = 5
	blank.party = [m]
	var bl := blank.describe_party()
	_chk("I.04 a mon with no moves says where they come from",
			bl[0].contains("moves from learnset"))

	# ⚠️ THE ASSERTION THAT MATTERS MOST. This project implements 717 of 935
	# moves, so an id with no shipped .tres is reachable. Rendering nothing for
	# it would make a real gap look like a three-move Pokémon.
	m.move_ids = [1, 999999]
	var gap := blank.describe_party()
	_chk("I.05 a real move id renders as its name", gap[0].contains("Pound"))
	_chk("I.06 an UNRESOLVABLE move id renders as its number, never as nothing",
			gap[0].contains("#999999"))

	# Same rule for a species with no entry at all.
	m.species_dex = 999999
	_chk("I.07 an unresolvable species falls back to its number",
			blank.describe_party()[0].contains("Species #999999"))

	# Held item, when there is one.
	m.species_dex = 25
	m.held_item_id = 28  # Potion
	_chk("I.08 a held item is shown by name",
			blank.describe_party()[0].contains("@Potion"))
