extends Node

# [M19-pre1] Weight and friendship data fields — pre-M19 infrastructure test
# suite, two clearly separated sections. Confirms two genuinely different
# weight-based power formulas (Low Kick/Grass Knot: target-weight-only;
# Heavy Slam/Heat Crash: attacker/target weight-ratio) and two genuinely
# different friendship-based power formulas (Return/Pika Papow/Veevee
# Volley vs. Frustration's exact inverse), plus forced_friendship's
# determinism, matching [M18.5h-1]'s own established override-testing
# pattern.
#
# Ground truth: pokeemerald_expansion
#   Weight:      include/pokemon.h L426 (.weight, hectograms, per-species,
#                fixed — no per-instance override).
#   Low Kick:    battle_util.c L6216-6225, sWeightToDamageTable L6022-6029.
#   Heat Crash:  battle_util.c L6227-6233, sHeatCrashPowerTable L6033.
#   Friendship:  include/pokemon.h L415 (SpeciesInfo.friendship, per-species
#                starting value); battle_util.c L6148-6153 (EFFECT_RETURN/
#                EFFECT_FRUSTRATION); universal power==0->1 floor L6371-6372;
#                MAX_FRIENDSHIP=255 (include/constants/pokemon.h L223).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_weight()
	_test_section_b_friendship()

	var total := _pass + _fail
	print("m19_pre1_test: %d/%d passed" % [_pass, total])
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


func _make_mon(mon_name: String, weight: int = 100, base_friendship: int = 50,
		forced_friendship: Variant = null) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(TypeChart.TYPE_NORMAL)
	sp.base_hp = 200
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	sp.weight = weight
	sp.base_friendship = base_friendship
	return BattlePokemon.from_species(sp, 50, null, null, forced_friendship)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: Weight ────────────────────────────────────────────────────────

func _test_section_a_weight() -> void:
	# A1: Low Kick / Grass Knot — target-weight-only formula, direct unit tests
	# at every threshold boundary plus edge cases.
	_chk("A1a weight=1 (very light) -> 20", BattleManager._low_kick_power(1) == 20)
	_chk("A1b weight=99 (just under 100) -> 20", BattleManager._low_kick_power(99) == 20)
	_chk("A1c weight=100 (exact boundary) -> 40", BattleManager._low_kick_power(100) == 40)
	_chk("A1d weight=249 -> 40", BattleManager._low_kick_power(249) == 40)
	_chk("A1e weight=250 (exact boundary) -> 60", BattleManager._low_kick_power(250) == 60)
	_chk("A1f weight=499 -> 60", BattleManager._low_kick_power(499) == 60)
	_chk("A1g weight=500 (exact boundary) -> 80", BattleManager._low_kick_power(500) == 80)
	_chk("A1h weight=999 -> 80", BattleManager._low_kick_power(999) == 80)
	_chk("A1i weight=1000 (exact boundary) -> 100", BattleManager._low_kick_power(1000) == 100)
	_chk("A1j weight=1999 -> 100", BattleManager._low_kick_power(1999) == 100)
	_chk("A1k weight=2000 (exact boundary) -> 120", BattleManager._low_kick_power(2000) == 120)
	_chk("A1l weight=9999 (very heavy) -> 120", BattleManager._low_kick_power(9999) == 120)

	# A2: Heavy Slam / Heat Crash — attacker/target weight-RATIO formula,
	# a genuinely different shape from A1's target-weight-only lookup.
	_chk("A2a ratio 0 (attacker much lighter) -> 40",
			BattleManager._heat_crash_power(50, 1000) == 40)
	_chk("A2b ratio 1 (roughly equal weight) -> 40",
			BattleManager._heat_crash_power(100, 100) == 40)
	_chk("A2c ratio 2 -> 60", BattleManager._heat_crash_power(200, 100) == 60)
	_chk("A2d ratio 3 -> 80", BattleManager._heat_crash_power(300, 100) == 80)
	_chk("A2e ratio 4 -> 100", BattleManager._heat_crash_power(400, 100) == 100)
	_chk("A2f ratio 5 (exact cap boundary) -> 120", BattleManager._heat_crash_power(500, 100) == 120)
	_chk("A2g ratio 100 (very heavy attacker vs very light target) -> 120 (capped)",
			BattleManager._heat_crash_power(10000, 100) == 120)

	# A3: full-battle integration — confirms move.is_low_kick_power/
	# is_heat_crash_power actually drive real damage output, not just the
	# pure formula in isolation. Comparative (heavier target takes more
	# Low Kick damage; higher weight-ratio attacker deals more Heat Crash
	# damage), not a hand-derived exact number, to avoid fragile UQ4.12
	# rounding assumptions.
	var low_kick := _load_move(67)
	_chk("A3 data-integrity: Low Kick is_low_kick_power flag set", low_kick.is_low_kick_power)
	var grass_knot := _load_move(447)
	_chk("A3b data-integrity: Grass Knot is_low_kick_power flag set", grass_knot.is_low_kick_power)

	var light_target := _make_mon("A3_LightTarget", 50)
	var heavy_target := _make_mon("A3_HeavyTarget", 3000)
	var atk_light := _make_mon("A3_AtkLight")
	atk_light.add_move(low_kick)
	light_target.add_move(low_kick)
	var atk_heavy := _make_mon("A3_AtkHeavy")
	atk_heavy.add_move(low_kick)
	heavy_target.add_move(low_kick)

	var light_dmg := [0]
	var bm_light := _make_bm()
	bm_light._force_hit = true
	bm_light._force_crit = false
	bm_light._force_roll = 100
	bm_light.move_executed.connect(func(a, d, m, dmg):
		if light_dmg[0] == 0 and a == atk_light:
			light_dmg[0] = dmg)
	bm_light.queue_move(0, 0)
	bm_light.queue_move(1, 0)
	bm_light.start_battle(atk_light, light_target)

	var heavy_dmg := [0]
	var bm_heavy := _make_bm()
	bm_heavy._force_hit = true
	bm_heavy._force_crit = false
	bm_heavy._force_roll = 100
	bm_heavy.move_executed.connect(func(a, d, m, dmg):
		if heavy_dmg[0] == 0 and a == atk_heavy:
			heavy_dmg[0] = dmg)
	bm_heavy.queue_move(0, 0)
	bm_heavy.queue_move(1, 0)
	bm_heavy.start_battle(atk_heavy, heavy_target)

	_chk("A3c Low Kick vs a heavier target deals MORE damage (real dispatch path)",
			heavy_dmg[0] > light_dmg[0])

	var heat_crash := _load_move(535)
	var heavy_atk_species_mon := _make_mon("A3_HeavyRatioAtk", 2000)
	heavy_atk_species_mon.add_move(heat_crash)
	var light_atk_species_mon := _make_mon("A3_LightRatioAtk", 50)
	light_atk_species_mon.add_move(heat_crash)
	var hc_target1 := _make_mon("A3_HCTarget1", 100)
	hc_target1.add_move(low_kick)
	var hc_target2 := _make_mon("A3_HCTarget2", 100)
	hc_target2.add_move(low_kick)

	var hc_high_ratio_dmg := [0]
	var bm_hc1 := _make_bm()
	bm_hc1._force_hit = true
	bm_hc1._force_crit = false
	bm_hc1._force_roll = 100
	bm_hc1.move_executed.connect(func(a, d, m, dmg):
		if hc_high_ratio_dmg[0] == 0 and a == heavy_atk_species_mon:
			hc_high_ratio_dmg[0] = dmg)
	bm_hc1.queue_move(0, 0)
	bm_hc1.queue_move(1, 0)
	bm_hc1.start_battle(heavy_atk_species_mon, hc_target1)

	var hc_low_ratio_dmg := [0]
	var bm_hc2 := _make_bm()
	bm_hc2._force_hit = true
	bm_hc2._force_crit = false
	bm_hc2._force_roll = 100
	bm_hc2.move_executed.connect(func(a, d, m, dmg):
		if hc_low_ratio_dmg[0] == 0 and a == light_atk_species_mon:
			hc_low_ratio_dmg[0] = dmg)
	bm_hc2.queue_move(0, 0)
	bm_hc2.queue_move(1, 0)
	bm_hc2.start_battle(light_atk_species_mon, hc_target2)

	_chk("A3d Heat Crash with a higher weight ratio deals MORE damage (real dispatch path)",
			hc_high_ratio_dmg[0] > hc_low_ratio_dmg[0])


# ── Section B: Friendship ────────────────────────────────────────────────────

func _test_section_b_friendship() -> void:
	# B1: Return / Pika Papow / Veevee Volley — direct unit tests across the
	# full friendship range including both extremes.
	_chk("B1a friendship=0 -> floored to 1 (not 0)", BattleManager._return_power(0) == 1)
	_chk("B1b friendship=25 -> 10", BattleManager._return_power(25) == 10)
	_chk("B1c friendship=125 -> 50", BattleManager._return_power(125) == 50)
	_chk("B1d friendship=200 -> 80", BattleManager._return_power(200) == 80)
	_chk("B1e friendship=255 (MAX_FRIENDSHIP) -> 102", BattleManager._return_power(255) == 102)

	# B2: Frustration — direct unit tests, confirming the INVERSE relationship
	# explicitly (a discriminator against B1, not assumed to mirror Return).
	_chk("B2a friendship=0 -> 102 (max, since 255-0=255)", BattleManager._frustration_power(0) == 102)
	_chk("B2b friendship=25 -> 92", BattleManager._frustration_power(25) == 92)
	_chk("B2c friendship=130 -> 50", BattleManager._frustration_power(130) == 50)
	_chk("B2d friendship=200 -> 22", BattleManager._frustration_power(200) == 22)
	_chk("B2e friendship=255 (MAX_FRIENDSHIP) -> floored to 1 (not 0)",
			BattleManager._frustration_power(255) == 1)

	# B3: explicit discriminator — Return and Frustration produce OPPOSITE
	# power trends for the SAME friendship value (not just "different
	# formulas" in the abstract).
	# Crossover point (10*f/25 == 10*(255-f)/25) is between f=127 and f=128,
	# per integer division (f=127: Return=50<Frustration=51; f=128:
	# Return=51>Frustration=50) — hand-verified, not assumed symmetric.
	for f in [0, 50, 130, 200, 255]:
		var ret: int = BattleManager._return_power(f)
		var frust: int = BattleManager._frustration_power(f)
		if f < 127:
			_chk("B3 friendship=%d: Return(%d) < Frustration(%d) (low friendship favors Frustration)" % [f, ret, frust],
					ret < frust)
		else:
			_chk("B3 friendship=%d: Return(%d) > Frustration(%d) (high friendship favors Return)" % [f, ret, frust],
					ret > frust)

	# B4: Pika Papow / Veevee Volley share Return's EXACT formula — confirmed
	# via their own loaded .tres data flag, not assumed from their similar
	# descriptions.
	var pika_papow := _load_move(679)
	_chk("B4a Pika Papow is_return_power flag set (shares Return's formula)",
			pika_papow.is_return_power)
	var veevee_volley := _load_move(688)
	_chk("B4b Veevee Volley is_return_power flag set (shares Return's formula)",
			veevee_volley.is_return_power)
	var frustration_move := _load_move(218)
	_chk("B4c Frustration is_frustration_power flag set (its OWN distinct formula)",
			frustration_move.is_frustration_power)
	_chk("B4d Frustration does NOT also carry is_return_power",
			not frustration_move.is_return_power)

	# B5: forced_friendship determinism (n=50, zero variance), matching
	# [M18.5h-1]'s own established override-testing pattern.
	var all_forced_50 := true
	for _i in range(50):
		var mon := _make_mon("B5_Forced", 100, 50, 50)
		if mon.friendship != 50:
			all_forced_50 = false
	_chk("B5a forced_friendship=50 pins exactly 50 across n=50", all_forced_50)

	var all_forced_255 := true
	for _i in range(50):
		var mon := _make_mon("B5_Forced255", 100, 50, 255)
		if mon.friendship != 255:
			all_forced_255 = false
	_chk("B5b forced_friendship=255 pins exactly 255 across n=50", all_forced_255)

	# B5c: unforced default falls back to the species' own base_friendship
	# (deterministic, not a roll -- n=1 is sufficient, but check a few
	# distinct species values to confirm this isn't hardcoded).
	var default_mon := _make_mon("B5_Default", 100, 140)
	_chk("B5c unforced friendship defaults to species.base_friendship (140)",
			default_mon.friendship == 140)
	var default_mon2 := _make_mon("B5_Default2", 100, 0)
	_chk("B5d unforced friendship defaults to species.base_friendship (0)",
			default_mon2.friendship == 0)

	# B6: full-battle integration — confirms move.is_return_power/
	# is_frustration_power actually drive real damage output. Comparative
	# (higher friendship deals more Return damage; higher friendship deals
	# LESS Frustration damage), not a hand-derived exact number.
	var return_move := _load_move(216)
	var low_friend_mon := _make_mon("B6_LowFriend", 100, 50, 10)
	low_friend_mon.add_move(return_move)
	var high_friend_mon := _make_mon("B6_HighFriend", 100, 50, 250)
	high_friend_mon.add_move(return_move)
	var b6_target1 := _make_mon("B6_Target1")
	b6_target1.add_move(return_move)
	var b6_target2 := _make_mon("B6_Target2")
	b6_target2.add_move(return_move)

	var low_friend_dmg := [0]
	var bm_low := _make_bm()
	bm_low._force_hit = true
	bm_low._force_crit = false
	bm_low._force_roll = 100
	bm_low.move_executed.connect(func(a, d, m, dmg):
		if low_friend_dmg[0] == 0 and a == low_friend_mon:
			low_friend_dmg[0] = dmg)
	bm_low.queue_move(0, 0)
	bm_low.queue_move(1, 0)
	bm_low.start_battle(low_friend_mon, b6_target1)

	var high_friend_dmg := [0]
	var bm_high := _make_bm()
	bm_high._force_hit = true
	bm_high._force_crit = false
	bm_high._force_roll = 100
	bm_high.move_executed.connect(func(a, d, m, dmg):
		if high_friend_dmg[0] == 0 and a == high_friend_mon:
			high_friend_dmg[0] = dmg)
	bm_high.queue_move(0, 0)
	bm_high.queue_move(1, 0)
	bm_high.start_battle(high_friend_mon, b6_target2)

	_chk("B6a Return: higher friendship deals MORE damage (real dispatch path)",
			high_friend_dmg[0] > low_friend_dmg[0])

	var frustration_dmg_low_friend := [0]
	var frust_mon_low := _make_mon("B6_FrustLow", 100, 50, 10)
	frust_mon_low.add_move(frustration_move)
	var b6_target3 := _make_mon("B6_Target3")
	b6_target3.add_move(return_move)
	var bm_fl := _make_bm()
	bm_fl._force_hit = true
	bm_fl._force_crit = false
	bm_fl._force_roll = 100
	bm_fl.move_executed.connect(func(a, d, m, dmg):
		if frustration_dmg_low_friend[0] == 0 and a == frust_mon_low:
			frustration_dmg_low_friend[0] = dmg)
	bm_fl.queue_move(0, 0)
	bm_fl.queue_move(1, 0)
	bm_fl.start_battle(frust_mon_low, b6_target3)

	var frustration_dmg_high_friend := [0]
	var frust_mon_high := _make_mon("B6_FrustHigh", 100, 50, 250)
	frust_mon_high.add_move(frustration_move)
	var b6_target4 := _make_mon("B6_Target4")
	b6_target4.add_move(return_move)
	var bm_fh := _make_bm()
	bm_fh._force_hit = true
	bm_fh._force_crit = false
	bm_fh._force_roll = 100
	bm_fh.move_executed.connect(func(a, d, m, dmg):
		if frustration_dmg_high_friend[0] == 0 and a == frust_mon_high:
			frustration_dmg_high_friend[0] = dmg)
	bm_fh.queue_move(0, 0)
	bm_fh.queue_move(1, 0)
	bm_fh.start_battle(frust_mon_high, b6_target4)

	_chk("B6b Frustration: higher friendship deals LESS damage (inverse, real dispatch path)",
			frustration_dmg_high_friend[0] < frustration_dmg_low_friend[0])
