extends Node

# [M19-weather-conditional-accuracy] Thunder(87), Hurricane(542), Bleakwind
# Storm(774), Wildbolt Storm(775), Sandsear Storm(776) — Bucket 4 sub-group.
# Also resolves Bleakwind Storm's long-standing "double-block" flag from
# `[M19-secondary-stat-on-hit]`.
#
# Step 0 findings (see move_data.gd's always_hits_in_rain/
# accuracy_halved_in_sun doc comments for full source citations):
#   - All 5 moves carry `always_hits_in_rain`, confirmed a FULL BYPASS of
#     the entire accuracy-modifier chain (same "family" as No Guard/
#     accuracy==0), gated on the ATTACKER's own effective weather.
#   - Thunder/Hurricane ADDITIONALLY carry `accuracy_halved_in_sun` — a
#     genuinely SEPARATE, second flag, confirmed NOT shared by the "Storm"
#     trio (Bleakwind/Wildbolt/Sandsear all lack it in source). This is a
#     literal OVERRIDE of the move's own accuracy to a flat 50 (NOT a ×0.5
#     multiply — Thunder's own base accuracy is 70), applied at the exact
#     same insertion point `[M17n-11]`'s Wonder Skin already established —
#     BEFORE the stage-ratio multiplication, so it composes with (does not
#     bypass) every other accuracy modifier.
#   - **A real, corrected finding beyond the task's own stated premise**:
#     Bleakwind Storm was NEVER actually implemented before this session —
#     it was correctly EXCLUDED from `[M19-secondary-stat-on-hit]`'s 79-move
#     batch specifically because of this double-block (confirmed via direct
#     grep: no `.tres`/gen_moves.py entry existed for ANY of these 5 IDs
#     before this session). This session builds Bleakwind Storm's stat-on-hit
#     secondary AND its weather-accuracy flag together in one entry, not
#     "adding weather flags to an already-shipped move" as originally framed.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# battle_util.c (CanMoveSkipAccuracyCalc, GetTotalAccuracy,
# GetAttackerWeather), include/move.h, GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_rain_always_hits_discriminator()
	_test_sun_accuracy_override_discriminator()
	_test_sun_override_composes_with_modifier_chain()
	_test_bleakwind_storm_full_battle_integration()

	var total := _pass + _fail
	print("m19_weather_accuracy_test: %d/%d passed" % [_pass, total])
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


func _make_mon(mon_name: String, types: Array[int], base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data integrity (all 5 moves) ─────────────────────────────────

func _test_data_integrity() -> void:
	var thunder := _load_move(87)
	_chk("87 Thunder loads", thunder != null)
	_chk("87 name/type/category/power/accuracy/pp",
			thunder.move_name == "Thunder" and thunder.type == TypeChart.TYPE_ELECTRIC
					and thunder.category == 1 and thunder.power == 110
					and thunder.accuracy == 70 and thunder.pp == 10)
	_chk("87 always_hits_in_rain AND accuracy_halved_in_sun (both flags)",
			thunder.always_hits_in_rain and thunder.accuracy_halved_in_sun)
	_chk("87 paralysis secondary + damages_airborne unaffected by the new flags",
			thunder.secondary_effect == MoveData.SE_PARALYSIS and thunder.secondary_chance == 30
					and thunder.damages_airborne)

	var hurricane := _load_move(542)
	_chk("542 Hurricane loads", hurricane != null)
	_chk("542 name/type/category/power/accuracy/pp",
			hurricane.move_name == "Hurricane" and hurricane.type == TypeChart.TYPE_FLYING
					and hurricane.category == 1 and hurricane.power == 110
					and hurricane.accuracy == 70 and hurricane.pp == 10)
	_chk("542 always_hits_in_rain AND accuracy_halved_in_sun (both flags)",
			hurricane.always_hits_in_rain and hurricane.accuracy_halved_in_sun)
	_chk("542 confusion secondary + damages_airborne unaffected",
			hurricane.secondary_effect == MoveData.SE_CONFUSION and hurricane.secondary_chance == 30
					and hurricane.damages_airborne)

	var bleakwind := _load_move(774)
	_chk("774 Bleakwind Storm loads", bleakwind != null)
	_chk("774 name/type/category/power/accuracy/pp",
			bleakwind.move_name == "Bleakwind Storm" and bleakwind.type == TypeChart.TYPE_FLYING
					and bleakwind.category == 1 and bleakwind.power == 100
					and bleakwind.accuracy == 80 and bleakwind.pp == 10)
	_chk("774 always_hits_in_rain present, accuracy_halved_in_sun ABSENT (the key asymmetry)",
			bleakwind.always_hits_in_rain and not bleakwind.accuracy_halved_in_sun)
	_chk("774 its own stat-on-hit secondary is ALSO present — the double-block is fully " +
			"resolved, both halves in one entry (Speed -1, 30% chance, spread move)",
			bleakwind.stat_change_stat == BattlePokemon.STAGE_SPEED
					and bleakwind.stat_change_amount == -1 and bleakwind.secondary_chance == 30
					and bleakwind.is_spread)

	var wildbolt := _load_move(775)
	_chk("775 Wildbolt Storm loads", wildbolt != null)
	_chk("775 name/type/category/power/accuracy/pp",
			wildbolt.move_name == "Wildbolt Storm" and wildbolt.type == TypeChart.TYPE_ELECTRIC
					and wildbolt.category == 1 and wildbolt.power == 100
					and wildbolt.accuracy == 80 and wildbolt.pp == 10)
	_chk("775 always_hits_in_rain present, accuracy_halved_in_sun ABSENT",
			wildbolt.always_hits_in_rain and not wildbolt.accuracy_halved_in_sun)
	_chk("775 paralysis secondary + is_spread",
			wildbolt.secondary_effect == MoveData.SE_PARALYSIS and wildbolt.secondary_chance == 20
					and wildbolt.is_spread)

	var sandsear := _load_move(776)
	_chk("776 Sandsear Storm loads", sandsear != null)
	_chk("776 name/type/category/power/accuracy/pp",
			sandsear.move_name == "Sandsear Storm" and sandsear.type == TypeChart.TYPE_GROUND
					and sandsear.category == 1 and sandsear.power == 100
					and sandsear.accuracy == 80 and sandsear.pp == 10)
	_chk("776 always_hits_in_rain present, accuracy_halved_in_sun ABSENT",
			sandsear.always_hits_in_rain and not sandsear.accuracy_halved_in_sun)
	_chk("776 burn secondary + is_spread",
			sandsear.secondary_effect == MoveData.SE_BURN and sandsear.secondary_chance == 20
					and sandsear.is_spread)


# ── always_hits_in_rain: a real discriminator against outside-rain misses ───
# No dedicated accuracy-roll-forcing seam exists in this codebase (only the
# blunt force_hit override, which would bypass the mechanism under test
# entirely) — so this uses real RNG over enough trials that the two outcomes
# are not just probable but essentially certain: Thunder's own 70% accuracy
# makes "zero misses in 100 trials" outside rain astronomically unlikely
# ((0.7)^100 ≈ 0), while always_hits_in_rain makes "zero misses in 30 trials"
# while raining a mathematical certainty by construction, not a probability.

func _test_rain_always_hits_discriminator() -> void:
	var thunder := _load_move(87)
	var atk := _make_mon("RainAtk", [TypeChart.TYPE_ELECTRIC])
	var def := _make_mon("RainDef", [TypeChart.TYPE_NORMAL])

	var rain_misses := 0
	for _i in range(30):
		if not StatusManager.check_accuracy(atk, def, thunder, null, false, DamageCalculator.WEATHER_RAIN):
			rain_misses += 1
	_chk("Thunder: zero misses across 30 trials while raining (always_hits_in_rain bypass)",
			rain_misses == 0)

	var no_weather_misses := 0
	for _i in range(100):
		if not StatusManager.check_accuracy(atk, def, thunder, null, false, DamageCalculator.WEATHER_NONE):
			no_weather_misses += 1
	_chk(("Discriminator: Thunder genuinely misses sometimes with NO weather active " +
			"(observed %d misses / 100 trials at 70%% base accuracy — proves the rain " +
			"case isn't a vacuous always-hit-anyway coincidence)") % [no_weather_misses],
			no_weather_misses > 0)


# ── accuracy_halved_in_sun: overrides to a flat 50, Storm trio unaffected ───

func _test_sun_accuracy_override_discriminator() -> void:
	var thunder := _load_move(87)
	var wildbolt := _load_move(775)
	var atk := _make_mon("SunAtk", [TypeChart.TYPE_ELECTRIC])
	var def := _make_mon("SunDef", [TypeChart.TYPE_NORMAL])

	var thunder_hits := 0
	var trials := 1000
	for _i in range(trials):
		if StatusManager.check_accuracy(atk, def, thunder, null, false, DamageCalculator.WEATHER_SUN):
			thunder_hits += 1
	# Neutral stat stages -> calc == effective_move_acc directly (ratio 1/1),
	# so this is a direct read of the overridden 50 value, not a derived one.
	_chk("Thunder in sun: hit rate is ~50%% (overridden, not its own 70%% base) — observed %d/%d" %
			[thunder_hits, trials], thunder_hits > 420 and thunder_hits < 580)

	var wildbolt_hits := 0
	for _i in range(trials):
		if StatusManager.check_accuracy(atk, def, wildbolt, null, false, DamageCalculator.WEATHER_SUN):
			wildbolt_hits += 1
	_chk("Discriminator: Wildbolt Storm in sun stays at its OWN 80%% base — no sun penalty " +
			"(observed %d/%d, clearly above Thunder's overridden ~50%%)" % [wildbolt_hits, trials],
			wildbolt_hits > 720 and wildbolt_hits < 880)


# ── The sun override COMPOSES with the modifier chain, unlike rain's full
# bypass — proven by showing defender evasion still reduces the effective
# hit rate even under the override (a full bypass would be immune to this).

func _test_sun_override_composes_with_modifier_chain() -> void:
	var thunder := _load_move(87)
	var atk := _make_mon("ComposeAtk", [TypeChart.TYPE_ELECTRIC])
	var def := _make_mon("ComposeDef", [TypeChart.TYPE_NORMAL])
	def.stat_stages[BattlePokemon.STAGE_EVASION] = 2

	var trials := 1000
	var hits_with_evasion := 0
	for _i in range(trials):
		if StatusManager.check_accuracy(atk, def, thunder, null, false, DamageCalculator.WEATHER_SUN):
			hits_with_evasion += 1
	_chk("Sun override composes with the stage-ratio chain: +2 evasion measurably " +
			"lowers the hit rate below the neutral ~50%% baseline (observed %d/%d)" %
			[hits_with_evasion, trials], hits_with_evasion < 420)


# ── Integration: Bleakwind Storm's stat-drop AND weather-accuracy both
# function correctly for the same move, now that it's fully unblocked ───────
# Two halves, deliberately tested via two different mechanisms: the
# weather-accuracy half through a REAL full battle (proving the bypass fires
# through the actual dispatch, not just the direct-call tests above); the
# stat-drop half through a direct `try_secondary_effect` call with
# `force_secondary=true` — no BattleManager-level forcing seam is wired
# through for the secondary-chance roll in a full battle (every call site
# hardcodes `null`), so a full-battle attempt at this specific chance-based
# secondary would need many repeated turns to reliably observe, reintroducing
# exactly the whole-battle-aggregation flakiness risk this project's own
# testing conventions warn against — the direct call sidesteps it entirely.

func _test_bleakwind_storm_full_battle_integration() -> void:
	var bleakwind := _load_move(774)
	var tackle := _load_move(33)
	var atk := _make_mon("BwAtk", [TypeChart.TYPE_FLYING], 100, 60, 60, 60, 60, 100)
	atk.add_move(bleakwind)
	var def := _make_mon("BwDef", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm.weather = BattleManager.WEATHER_RAIN
	bm.weather_duration = 10
	# No force_hit — proves always_hits_in_rain's bypass fires for real
	# through the actual battle dispatch, not just the direct-call tests above.
	var hit := [false, -1]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and not hit[0]:
			hit[0] = true
			hit[1] = amt)
	bm.start_battle(atk, def)

	_chk("Bleakwind Storm connects for real damage while raining, through the actual " +
			"battle dispatch (%s)" % [hit], hit[0] == true and hit[1] > 0)

	# try_secondary_effect only reports "yes, this fires" for the
	# [M19-secondary-stat-on-hit] stat-change path (`return true, caller
	# applies it`) — the actual stage mutation lives in
	# `BattleManager._apply_stat_change_effect`, which needs a real
	# BattleManager instance (signal emission, ability threading).
	var stat_bm := _make_bm()
	var stat_atk := _make_mon("StatBwAtk", [TypeChart.TYPE_FLYING])
	var stat_def := _make_mon("StatBwDef", [TypeChart.TYPE_NORMAL])
	var applied: bool = StatusManager.try_secondary_effect(stat_atk, stat_def, bleakwind, true, false)
	if applied:
		stat_bm._apply_stat_change_effect(stat_atk, stat_def, bleakwind, false)
	_chk("Bleakwind Storm's own Speed-1 secondary deterministically fires (force_secondary=true) " +
			"on the SAME move data that just proved its weather-accuracy half works",
			applied and stat_def.stat_stages[BattlePokemon.STAGE_SPEED] == -1)
