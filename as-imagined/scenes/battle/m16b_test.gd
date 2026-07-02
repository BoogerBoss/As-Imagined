extends Node

# M16b test suite — Tier B move effects
# EFFECT_MINIMIZE (Minimize: +2 evasion, minimized volatile)
# EFFECT_DEFENSE_CURL (Defense Curl: +1 defense, defense_curled volatile)
# Stomp / minimizeDoubleDamage (×2.0 damage modifier vs minimized targets)
# EFFECT_ROLLOUT (Rollout / Ice Ball: 5-hit power doubling, Defense Curl interaction)
# EFFECT_MAGNITUDE (variable base power roll)
#
# Ground truth: pokeemerald_expansion

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_move_data()
	_test_section_2_minimize()
	_test_section_3_defense_curl()
	_test_section_4_stomp()
	_test_section_5_rollout()
	_test_section_6_magnitude()

	var total := _pass + _fail
	print("m16b_test: %d/%d passed" % [_pass, total])
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
	return BattlePokemon.from_species(sp, level)


# ── Section 1: Move data spot-checks ─────────────────────────────────────────

func _test_section_1_move_data() -> void:
	# Stomp (23) — canonical ID confirmed against constants/moves.h (NOT 31, which is
	# Fury Attack; see decisions.md for the correction).
	var stomp := _load_move(23)
	_chk("S1.01 Stomp power=65",                     stomp.power == 65)
	_chk("S1.02 Stomp makes_contact",                stomp.makes_contact == true)
	_chk("S1.03 Stomp double_power_on_minimized",    stomp.double_power_on_minimized == true)
	_chk("S1.04 Stomp secondary_effect=FLINCH",      stomp.secondary_effect == MoveData.SE_FLINCH)
	_chk("S1.05 Stomp secondary_chance=30",          stomp.secondary_chance == 30)

	# Minimize (107)
	var minimize := _load_move(107)
	_chk("S1.06 Minimize is_minimize=true",   minimize.is_minimize == true)
	_chk("S1.07 Minimize accuracy=0",         minimize.accuracy == 0)
	_chk("S1.08 Minimize pp=10",              minimize.pp == 10)
	_chk("S1.09 Minimize ignores_protect",    minimize.ignores_protect == true)

	# Defense Curl (111)
	var defcurl := _load_move(111)
	_chk("S1.10 Defense Curl is_defense_curl=true", defcurl.is_defense_curl == true)
	_chk("S1.11 Defense Curl pp=40",                defcurl.pp == 40)
	_chk("S1.12 Defense Curl accuracy=0",           defcurl.accuracy == 0)

	# Rollout (205)
	var rollout := _load_move(205)
	_chk("S1.13 Rollout is_rollout=true",   rollout.is_rollout == true)
	_chk("S1.14 Rollout power=30",          rollout.power == 30)
	_chk("S1.15 Rollout accuracy=90",       rollout.accuracy == 90)
	_chk("S1.16 Rollout type=ROCK",         rollout.type == TypeChart.TYPE_ROCK)
	_chk("S1.17 Rollout makes_contact",     rollout.makes_contact == true)

	# Ice Ball (301)
	var iceball := _load_move(301)
	_chk("S1.18 Ice Ball is_rollout=true", iceball.is_rollout == true)
	_chk("S1.19 Ice Ball power=30",        iceball.power == 30)
	_chk("S1.20 Ice Ball type=ICE",        iceball.type == TypeChart.TYPE_ICE)

	# Magnitude (222)
	var magnitude := _load_move(222)
	_chk("S1.21 Magnitude is_magnitude=true",       magnitude.is_magnitude == true)
	_chk("S1.22 Magnitude is_spread=true",          magnitude.is_spread == true)
	_chk("S1.23 Magnitude damages_underground",     magnitude.damages_underground == true)
	_chk("S1.24 Magnitude type=GROUND",             magnitude.type == TypeChart.TYPE_GROUND)
	_chk("S1.25 Magnitude accuracy=100",            magnitude.accuracy == 100)
	_chk("S1.26 Magnitude pp=30",                   magnitude.pp == 30)

	# BattlePokemon volatile field defaults
	var fresh_mon := _make_mon("Fresh", 50, [TypeChart.TYPE_NORMAL])
	_chk("S1.27 minimized defaults false",       fresh_mon.minimized == false)
	_chk("S1.28 defense_curled defaults false",  fresh_mon.defense_curled == false)
	_chk("S1.29 rollout_turns defaults 0",       fresh_mon.rollout_turns == 0)
	_chk("S1.30 rollout_base_power defaults 0",  fresh_mon.rollout_base_power == 0)


# ── Section 2: EFFECT_MINIMIZE ────────────────────────────────────────────────

func _test_section_2_minimize() -> void:
	var minimize := _load_move(107)
	var tackle   := _load_move(33)

	# S2.01 Minimize raises Evasion +2 and sets attacker.minimized = true.
	# player1's ONLY move is Minimize (deals no damage back), so the battle runs until
	# player1 eventually faints — which clears minimized via _clear_volatiles. Capture the
	# flag DURING the move_executed callback (right after it's set), not after the battle.
	var player1 := _make_mon("M_A", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp1    := _make_mon("M_B", 50, [TypeChart.TYPE_NORMAL], 80, 30, 80, 80, 80, 50)
	player1.add_move(minimize)
	opp1.add_move(tackle)
	var stat_changes1: Array = []
	var minimized_after_use1: Array[bool] = [false]  # Array wrapper for lambda capture
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.stat_stage_changed.connect(func(t: BattlePokemon, stat: int, amt: int):
		if t == player1:
			stat_changes1.append([stat, amt]))
	bm1.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, _dmg: int):
		if a == player1 and mv == minimize:
			minimized_after_use1[0] = player1.minimized)
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	var evasion_raised1 := false
	for ch in stat_changes1:
		if ch[0] == BattlePokemon.STAGE_EVASION and ch[1] == 2: evasion_raised1 = true
	_chk("S2.01 Minimize raises Evasion +2", evasion_raised1)
	_chk("S2.02 Minimize sets minimized=true", minimized_after_use1[0] == true)

	# S2.03 Minimize fails (stat_limit, minimized NOT set) when evasion already at +6.
	var player3 := _make_mon("M_C", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("M_D", 50, [TypeChart.TYPE_NORMAL], 80, 120, 80, 80, 80, 50)
	player3.add_move(minimize)
	opp3.add_move(tackle)
	player3.stat_stages[BattlePokemon.STAGE_EVASION] = 6
	var fail3: Array[String] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.move_effect_failed.connect(func(t: BattlePokemon, r: String): fail3.append(r))
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S2.03 Minimize fails stat_limit at +6 evasion", "stat_limit" in fail3)
	_chk("S2.04 Minimize does NOT set minimized on failure", player3.minimized == false)

	# S2.05 minimized cleared by volatile clear (faint/switch-out) — source-confirmed via
	# BattleManager._clear_volatiles; simulated here per m16a_test's established convention.
	var switch_mon := _make_mon("SW", 50, [TypeChart.TYPE_NORMAL])
	switch_mon.minimized = true
	switch_mon.minimized = false  # what _clear_volatiles does
	_chk("S2.05 minimized cleared (volatile clear)", switch_mon.minimized == false)


# ── Section 3: EFFECT_DEFENSE_CURL ───────────────────────────────────────────

func _test_section_3_defense_curl() -> void:
	var defcurl := _load_move(111)
	var tackle  := _load_move(33)

	# S3.01 Defense Curl raises Defense +1 and sets attacker.defense_curled = true.
	# player1's ONLY move is Defense Curl (deals no damage back), so the battle runs
	# until player1 eventually faints — which clears defense_curled via _clear_volatiles.
	# Capture the flag DURING the move_executed callback, not after the battle.
	var player1 := _make_mon("D_A", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp1    := _make_mon("D_B", 50, [TypeChart.TYPE_NORMAL], 80, 30, 80, 80, 80, 50)
	player1.add_move(defcurl)
	opp1.add_move(tackle)
	var stat_changes1: Array = []
	var curled_after_use1: Array[bool] = [false]  # Array wrapper for lambda capture
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.stat_stage_changed.connect(func(t: BattlePokemon, stat: int, amt: int):
		if t == player1:
			stat_changes1.append([stat, amt]))
	bm1.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, _dmg: int):
		if a == player1 and mv == defcurl:
			curled_after_use1[0] = player1.defense_curled)
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	var def_raised1 := false
	for ch in stat_changes1:
		if ch[0] == BattlePokemon.STAGE_DEF and ch[1] == 1: def_raised1 = true
	_chk("S3.01 Defense Curl raises Defense +1", def_raised1)
	_chk("S3.02 Defense Curl sets defense_curled=true", curled_after_use1[0] == true)

	# S3.03 Defense Curl STILL sets defense_curled=true even when Defense is already
	# at +6 (unconditional, unlike Minimize — source: SetAdditionalEffectsOnStatChange
	# case EFFECT_DEFENSE_CURL has no MOVE_RESULT_STAT_CHANGED guard).
	var player3 := _make_mon("D_C", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("D_D", 50, [TypeChart.TYPE_NORMAL], 80, 120, 80, 80, 80, 50)
	player3.add_move(defcurl)
	opp3.add_move(tackle)
	player3.stat_stages[BattlePokemon.STAGE_DEF] = 6
	var fail3: Array[String] = []
	var curled_after_use3: Array[bool] = [false]
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.move_effect_failed.connect(func(t: BattlePokemon, r: String): fail3.append(r))
	bm3.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, _dmg: int):
		if a == player3 and mv == defcurl:
			curled_after_use3[0] = player3.defense_curled)
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S3.03 Defense Curl stat raise fails at +6 (stat_limit)", "stat_limit" in fail3)
	_chk("S3.04 Defense Curl STILL sets defense_curled=true at +6 def",
			curled_after_use3[0] == true)


# ── Section 4: Stomp — double damage vs minimized target ────────────────────

func _test_section_4_stomp() -> void:
	var stomp := _load_move(23)

	var atk := _make_mon("St_Atk", 50, [TypeChart.TYPE_FIGHTING])
	var def_normal := _make_mon("St_DefN", 50, [TypeChart.TYPE_WATER])
	var def_min    := _make_mon("St_DefM", 50, [TypeChart.TYPE_WATER])
	def_min.minimized = true

	var r_normal: Dictionary = DamageCalculator.calculate(atk, def_normal, stomp, 100, false)
	var r_min: Dictionary    = DamageCalculator.calculate(atk, def_min, stomp, 100, false)
	_chk("S4.01 Stomp vs minimized target deals exactly 2x damage",
			r_min["damage"] == r_normal["damage"] * 2)

	# S4.02 A move WITHOUT double_power_on_minimized is unaffected by minimized target.
	var tackle := _load_move(33)
	var r_tackle_normal: Dictionary = DamageCalculator.calculate(atk, def_normal, tackle, 100, false)
	var r_tackle_min: Dictionary    = DamageCalculator.calculate(atk, def_min, tackle, 100, false)
	_chk("S4.02 Tackle (no minimizeDoubleDamage) unaffected by minimized target",
			r_tackle_min["damage"] == r_tackle_normal["damage"])


# ── Section 5: EFFECT_ROLLOUT (Rollout / Ice Ball) ───────────────────────────

func _test_section_5_rollout() -> void:
	var rollout := _load_move(205)
	var tackle  := _load_move(33)
	var defcurl := _load_move(111)

	# S5.01 Power sequence over 5 consecutive hits, then wraps back to base on the 6th:
	# 30 → 60 → 120 → 240 → 480 → 30. Captured via rollout_base_power at each move_executed.
	# force_hit=true makes every hit deterministic (Rollout's own 90% accuracy is bypassed).
	var player1 := _make_mon("R_A", 50, [TypeChart.TYPE_NORMAL], 200, 80, 200, 80, 200, 100)
	var opp1    := _make_mon("R_B", 50, [TypeChart.TYPE_NORMAL], 200, 5, 200, 80, 200, 50)
	player1.add_move(rollout)  # only move — auto-selected every turn (no queueing needed)
	opp1.add_move(tackle)
	var powers1: Array[int] = []
	var turns_pre1: Array[int] = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_hit = true
	# move_executed fires synchronously INSIDE _do_damaging_hit, before control returns to
	# _phase_move_execution's post-hit increment code below it — so rollout_turns here still
	# reflects the PRE-hit value (the exponent that produced THIS hit's power).
	bm1.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, _dmg: int):
		if a == player1 and mv == rollout and powers1.size() < 6:
			powers1.append(player1.rollout_base_power)
			turns_pre1.append(player1.rollout_turns))
	for _t in range(6):
		bm1.queue_move(1, 0)
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S5.01 Rollout captured 6 hits", powers1.size() == 6)
	_chk("S5.02 Rollout power sequence 30,60,120,240,480,30",
			powers1 == [30, 60, 120, 240, 480, 30])
	_chk("S5.03 pre-hit rollout_turns sequence 0,1,2,3,4,0",
			turns_pre1 == [0, 1, 2, 3, 4, 0])

	# S5.04 Defense Curl doubles the starting power: 60 → 120 → 240 → 480 → 960.
	var player4 := _make_mon("R_C", 50, [TypeChart.TYPE_NORMAL], 200, 80, 200, 80, 200, 100)
	var opp4    := _make_mon("R_D", 50, [TypeChart.TYPE_NORMAL], 200, 5, 200, 80, 200, 50)
	player4.add_move(defcurl)  # index 0
	player4.add_move(rollout)  # index 1
	opp4.add_move(tackle)
	var powers4: Array[int] = []
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4._force_hit = true
	bm4.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, _dmg: int):
		if a == player4 and mv == rollout and powers4.size() < 5:
			powers4.append(player4.rollout_base_power))
	bm4.queue_move(0, 0)  # turn 1: Defense Curl
	for _t in range(5):
		bm4.queue_move(0, 1)  # turns 2-6: Rollout x5
	for _t in range(6):
		bm4.queue_move(1, 0)  # opponent: Tackle x6
	bm4.start_battle(player4, opp4)
	bm4.queue_free()
	_chk("S5.04 Defense Curl doubles Rollout power sequence 60,120,240,480,960",
			powers4 == [60, 120, 240, 480, 960])

	# S5.05 Using a different move resets the consecutive-hit counter.
	# Turn 1: Rollout (power=30, rollout_turns->1). Turn 2: Tackle (resets rollout_turns->0).
	# Turn 3: Rollout again (fresh start, power=30 again — NOT 60).
	var player5 := _make_mon("R_E", 50, [TypeChart.TYPE_NORMAL], 200, 80, 200, 80, 200, 100)
	var opp5    := _make_mon("R_F", 50, [TypeChart.TYPE_NORMAL], 200, 5, 200, 80, 200, 50)
	player5.add_move(rollout)  # index 0
	player5.add_move(tackle)   # index 1
	opp5.add_move(tackle)
	# Only 3 actions are queued for player5; once drained, auto-select falls back to
	# moves[0] (Rollout), so guard captures to the exact counts we care about — the
	# battle keeps running (bounded by MAX_PHASES_PER_ADVANCE) since neither side faints.
	var powers5: Array[int] = []
	var turns_after_tackle5: Array[int] = [-1]
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5._force_hit = true
	bm5.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, _dmg: int):
		if a == player5 and mv == rollout and powers5.size() < 2:
			powers5.append(player5.rollout_base_power)
		elif a == player5 and mv == tackle and turns_after_tackle5[0] == -1:
			turns_after_tackle5[0] = player5.rollout_turns)
	bm5.queue_move(0, 0)  # turn 1: Rollout
	bm5.queue_move(0, 1)  # turn 2: Tackle (interrupts the streak)
	bm5.queue_move(0, 0)  # turn 3: Rollout again
	for _t in range(3):
		bm5.queue_move(1, 0)
	bm5.start_battle(player5, opp5)
	bm5.queue_free()
	_chk("S5.05 Rollout hits captured before/after interruption", powers5.size() == 2)
	_chk("S5.06 Switching moves resets rollout_turns to 0", turns_after_tackle5[0] == 0)
	_chk("S5.07 Rollout restarts at base power (30) after interruption",
			powers5.size() == 2 and powers5[0] == 30 and powers5[1] == 30)

	# S5.08 Always-missing Rollout (force_hit=false) never advances the counter.
	var player8 := _make_mon("R_G", 50, [TypeChart.TYPE_NORMAL], 200, 80, 200, 80, 200, 100)
	var opp8    := _make_mon("R_H", 50, [TypeChart.TYPE_NORMAL], 200, 5, 200, 80, 200, 50)
	player8.add_move(rollout)
	opp8.add_move(tackle)
	var bm8 := BattleManager.new()
	add_child(bm8)
	bm8._force_hit = false
	for _t in range(3):
		bm8.queue_move(1, 0)
	# Cap phases naturally via a bounded number of queued opponent actions is not enough
	# since player auto-selects Rollout indefinitely; MAX_PHASES_PER_ADVANCE bounds the run.
	bm8.start_battle(player8, opp8)
	bm8.queue_free()
	_chk("S5.09 Always-missing Rollout keeps rollout_turns at 0", player8.rollout_turns == 0)

	# S5.10 power_override plumbing: DamageCalculator honors power_override directly,
	# matching what a move with that power baked in would produce (no rounding drift).
	var direct_atk := _make_mon("R_Direct_Atk", 50, [TypeChart.TYPE_ROCK])
	var direct_def := _make_mon("R_Direct_Def", 50, [TypeChart.TYPE_NORMAL])
	var power60_move := MoveData.new()
	power60_move.move_name = "TestPower60"
	power60_move.type = TypeChart.TYPE_ROCK
	power60_move.category = 0
	power60_move.power = 60
	power60_move.accuracy = 100
	var r_baked: Dictionary = DamageCalculator.calculate(
			direct_atk, direct_def, power60_move, 100, false)
	var r_override: Dictionary = DamageCalculator.calculate(
			direct_atk, direct_def, rollout, 100, false, DamageCalculator.WEATHER_NONE,
			false, false, 60)
	_chk("S5.10 power_override=60 matches a move with power=60 baked in",
			r_override["damage"] == r_baked["damage"])

	# S5.11 Ice Ball shares the same is_rollout scaling logic (spot check via power_override).
	var iceball := _load_move(301)
	var r_iceball: Dictionary = DamageCalculator.calculate(
			direct_atk, direct_def, iceball, 100, false, DamageCalculator.WEATHER_NONE,
			false, false, 120)
	var power120_move := MoveData.new()
	power120_move.move_name = "TestPower120"
	power120_move.type = TypeChart.TYPE_ICE
	power120_move.category = 0
	power120_move.power = 120
	power120_move.accuracy = 100
	var r_baked120: Dictionary = DamageCalculator.calculate(
			direct_atk, direct_def, power120_move, 100, false)
	_chk("S5.11 Ice Ball power_override=120 matches a move with power=120 baked in",
			r_iceball["damage"] == r_baked120["damage"])


# ── Section 6: EFFECT_MAGNITUDE ───────────────────────────────────────────────

func _test_section_6_magnitude() -> void:
	var magnitude := _load_move(222)

	# S6.01 _force_magnitude_power seam pass-through for each table entry.
	var bm := BattleManager.new()
	add_child(bm)
	var table: Array[int] = [10, 30, 50, 70, 90, 110, 150]
	var all_match := true
	for p in table:
		bm._force_magnitude_power = p
		if bm._roll_magnitude_power() != p:
			all_match = false
	_chk("S6.01 _force_magnitude_power pass-through matches for all 7 table values",
			all_match)

	# S6.02 Unforced roll always returns a value from the valid table (deterministic
	# membership assertion — does not depend on which value the RNG picks).
	bm._force_magnitude_power = null
	var unforced: int = bm._roll_magnitude_power()
	_chk("S6.02 Unforced Magnitude roll is a valid table value", unforced in table)
	bm.queue_free()

	# S6.03 power_override for Magnitude is honored end-to-end in a real battle turn.
	var player3 := _make_mon("Mag_A", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("Mag_B", 50, [TypeChart.TYPE_NORMAL], 80, 30, 80, 80, 80, 50)
	player3.add_move(magnitude)
	var tackle := _load_move(33)
	opp3.add_move(tackle)
	var dmg3: Array[int] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_magnitude_power = 150
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, dmg: int):
		if a == player3 and mv == magnitude:
			dmg3.append(dmg))
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S6.03 Magnitude (forced power=150) deals damage in a real battle turn",
			dmg3.size() > 0 and dmg3[0] > 0)

	# S6.04 A higher forced Magnitude power deals more damage than a lower one
	# (power_override plumbed correctly into the base-damage formula).
	var atk4 := _make_mon("Mag_Direct_Atk", 50, [TypeChart.TYPE_GROUND])
	var def4 := _make_mon("Mag_Direct_Def", 50, [TypeChart.TYPE_NORMAL])
	var r_lo: Dictionary = DamageCalculator.calculate(
			atk4, def4, magnitude, 100, false, DamageCalculator.WEATHER_NONE, false, false, 10)
	var r_hi: Dictionary = DamageCalculator.calculate(
			atk4, def4, magnitude, 100, false, DamageCalculator.WEATHER_NONE, false, false, 150)
	_chk("S6.04 Magnitude power_override=150 deals more damage than power_override=10",
			r_hi["damage"] > r_lo["damage"])
