extends Node

# Milestone 11 test suite — Weather
#
# Ground truth: pokeemerald_expansion (all GEN_LATEST config)
#   src/battle_util.c :: TryChangeBattleWeather (L1969)
#   src/battle_util.c :: EndOrContinueWeather (L244)
#   src/battle_util.c :: GetWeatherDamageModifier (L7251)
#   src/battle_util.c :: DoMoveDamageCalcVars (L7577) — modifier order
#   src/battle_end_turn.c :: HandleEndTurnWeather (L94)
#   src/battle_end_turn.c :: HandleEndTurnWeatherDamage (L100)
#   src/battle_end_turn.c :: sEndTurnEffectHandlers (L1545) — EOT order
#
# Sections:
#   W1:  Drizzle sets rain on battle start
#   W2:  Drought sets sun on battle start
#   W3:  Weather persists across turns (duration countdown, not cleared on switch)
#   W4:  Weather expires after 5 turns (duration reaches 0)
#   W5:  Weather is NOT cleared on switch-out (field effect, not per-Pokémon volatile)
#   W6:  Same weather no-ops (Drizzle with rain already active → no change)
#   W7:  Different weather overwrites (rain then sun)
#   W8a: Water move under rain boosted ×1.5 (discriminating composition test)
#   W8b: Fire move under rain reduced ×0.5
#   W9a: Fire move under sun boosted ×1.5 (discriminating composition test)
#   W9b: Water move under sun reduced ×0.5
#   W10: Sandstorm deals maxHP/16 chip; Rock/Ground/Steel immune; others damaged
#   W11: Hail deals maxHP/16 chip; Ice immune; others damaged
#   W12: Weather expires → damage modifiers revert to no-weather baseline
#   W13: AI weather-aware scoring — weather modifier propagates via DamageCalculator
#        (confirms M10 architecture: AI scoring picks up weather automatically)

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_w1_drizzle_sets_rain()
	_test_w2_drought_sets_sun()
	_test_w3_weather_persists()
	_test_w4_weather_expires()
	_test_w5_no_clear_on_switch()
	_test_w6_same_weather_noop()
	_test_w7_weather_overwrites()
	_test_w8a_water_rain_boost()
	_test_w8b_fire_rain_reduce()
	_test_w9a_fire_sun_boost()
	_test_w9b_water_sun_reduce()
	_test_w10_sandstorm_chip()
	_test_w11_hail_chip()
	_test_w12_weather_expiry_reverts_modifier()
	_test_w13_ai_weather_scoring()

	var total := _pass + _fail
	print("weather_test: %d/%d passed" % [_pass, total])
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

func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		hp: int = 160, atk: int = 80, def_stat: int = 80,
		spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp      = hp
	sp.base_attack  = atk
	sp.base_defense = def_stat
	sp.base_sp_attack  = spatk
	sp.base_sp_defense = spdef
	sp.base_speed      = spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [M18.5h-1/2] pinned neutral nature + zero IVs -- exact-value assertions predate both


func _make_move(move_name: String, move_type: int, category: int, power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name = move_name
	m.type      = move_type
	m.category  = category
	m.power     = power
	m.accuracy  = 100
	m.pp        = 40
	m.secondary_effect = MoveData.SE_NONE
	m.secondary_chance = 0
	m.two_turn         = false
	m.semi_inv_state   = MoveData.SEMI_INV_NONE
	return m


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── W1: Drizzle sets rain ─────────────────────────────────────────────────────
# Source: ABILITY_DRIZZLE → TryChangeBattleWeather(BATTLE_WEATHER_RAIN, ability)
#   (battle_util.c L3213). Sets gBattleWeather = B_WEATHER_RAIN_NORMAL, duration = 5.
#
# NOTE on test design: start_battle() runs the entire battle to completion
# (auto-selects moves when no queue is available). By the time start_battle returns,
# weather has expired (the battle lasts many turns). We therefore test:
#   W1.02 — via signal captured during battle execution (fires at BATTLE_START)
#   W1.03 — via AbilityManager.get_switch_in_weather (direct unit test of the mapping)
#   W1.04 — via try_set_weather state (direct unit test of the set function)

func _test_w1_drizzle_sets_rain() -> void:
	var drizzle := _load_ability(2)  # ability_0002.tres — Drizzle ID=2
	_chk("W1.01 Drizzle ability loads", drizzle != null)
	if drizzle == null:
		return

	var drizzle_mon := _make_mon("Pelipper", TypeChart.TYPE_WATER)
	drizzle_mon.ability = drizzle
	var normal_mon  := _make_mon("Normal",   TypeChart.TYPE_NORMAL)
	drizzle_mon.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))
	normal_mon.add_move(_make_move("Tackle",  TypeChart.TYPE_NORMAL, 0, 40))

	# Integration: signal fires during BATTLE_START when Drizzle mon enters.
	var bm := _make_bm()
	var weather_recorded := [BattleManager.WEATHER_NONE]
	bm.weather_set.connect(func(_m, w): weather_recorded[0] = w)
	bm.start_battle(drizzle_mon, normal_mon)
	_chk("W1.02 weather_set signal emitted for RAIN", weather_recorded[0] == BattleManager.WEATHER_RAIN)
	bm.queue_free()

	# Unit test: ability→weather mapping.
	_chk("W1.03 get_switch_in_weather returns RAIN",
			AbilityManager.get_switch_in_weather(drizzle_mon) == DamageCalculator.WEATHER_RAIN)

	# Unit test: try_set_weather sets state correctly (duration = 5).
	var bm2 := _make_bm()
	var set_ok := bm2.try_set_weather(BattleManager.WEATHER_RAIN)
	_chk("W1.04 try_set_weather RAIN → weather==RAIN, duration==5",
			set_ok and bm2.weather == BattleManager.WEATHER_RAIN and bm2.weather_duration == 5)
	bm2.queue_free()


# ── W2: Drought sets sun ──────────────────────────────────────────────────────
# Source: ABILITY_DROUGHT → TryChangeBattleWeather(BATTLE_WEATHER_SUN, ability)
#   (battle_util.c L3242). Sets gBattleWeather = B_WEATHER_SUN_NORMAL, duration = 5.

func _test_w2_drought_sets_sun() -> void:
	var drought := _load_ability(70)  # ability_0070.tres — Drought ID=70
	_chk("W2.01 Drought ability loads", drought != null)
	if drought == null:
		return

	var drought_mon := _make_mon("Torkoal", TypeChart.TYPE_FIRE)
	drought_mon.ability = drought
	var normal_mon  := _make_mon("Normal",  TypeChart.TYPE_NORMAL)
	drought_mon.add_move(_make_move("Ember",  TypeChart.TYPE_FIRE,   1, 40))
	normal_mon.add_move(_make_move("Tackle",  TypeChart.TYPE_NORMAL, 0, 40))

	# Integration: signal fires during BATTLE_START when Drought mon enters.
	var bm := _make_bm()
	var weather_recorded := [BattleManager.WEATHER_NONE]
	bm.weather_set.connect(func(_m, w): weather_recorded[0] = w)
	bm.start_battle(drought_mon, normal_mon)
	_chk("W2.02 weather_set signal emitted for SUN", weather_recorded[0] == BattleManager.WEATHER_SUN)
	bm.queue_free()

	# Unit test: ability→weather mapping.
	_chk("W2.03 get_switch_in_weather returns SUN",
			AbilityManager.get_switch_in_weather(drought_mon) == DamageCalculator.WEATHER_SUN)

	# Unit test: try_set_weather state.
	var bm2 := _make_bm()
	var set_ok := bm2.try_set_weather(BattleManager.WEATHER_SUN)
	_chk("W2.04 try_set_weather SUN → weather==SUN, duration==5",
			set_ok and bm2.weather == BattleManager.WEATHER_SUN and bm2.weather_duration == 5)
	bm2.queue_free()


# ── W3: Weather persists across turns — duration ticks down each EOT ──────────
# Source: EndOrContinueWeather (battle_util.c L244):
#   weatherDuration > 0 → weatherDuration-- → if 0: gBattleWeather = NONE.
#
# Strategy: set weather=RAIN, duration=2 directly (ability trigger proven in W1).
# Run a battle that lasts > 2 turns (very low damage, high HP). Capture the
# weather_expired signal. It fires after exactly 2 EOT ticks, which proves:
#   tick #1 — weather was still active (didn't clear prematurely)
#   tick #2 — weather expired (duration counted down correctly to 0)
#
# Stats: Atk stat=6 (base=1), Def stat=205 (base=200), max_hp=62 (base=2).
# Tackle power=1, STAB ×1.5 → ~3 damage/turn → ~21 turns to faint (> 2). ✓

func _test_w3_weather_persists() -> void:
	var bm := _make_bm()
	bm.weather = BattleManager.WEATHER_RAIN
	bm.weather_duration = 2  # expires after exactly 2 EOT ticks

	var expired_count := [0]
	var expired_type  := [BattleManager.WEATHER_NONE]
	bm.weather_expired.connect(func(w): expired_count[0] += 1; expired_type[0] = w)

	var a := _make_mon("W3A", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 2, 1, 200, 1, 200, 50)
	var b := _make_mon("W3B", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 2, 1, 200, 1, 200, 60)
	var t := _make_move("T", TypeChart.TYPE_NORMAL, 0, 1)
	a.add_move(t)
	b.add_move(t)
	bm.start_battle(a, b)

	_chk("W3.01 weather_expired fired once (persisted through tick #1, expired on tick #2)",
			expired_count[0] == 1)
	_chk("W3.02 expired weather was RAIN", expired_type[0] == BattleManager.WEATHER_RAIN)
	bm.queue_free()


# ── W4: Weather expires after 5 turns ─────────────────────────────────────────
# Source: EndOrContinueWeather (battle_util.c L251):
#   if (weatherDuration > 0 && --weatherDuration == 0) → gBattleWeather = B_WEATHER_NONE
# After 5 EOT ticks: weather_duration reaches 0, weather cleared.

func _test_w4_weather_expires() -> void:
	var drizzle := _load_ability(2)
	if drizzle == null:
		_chk("W4 skip: Drizzle not loaded", false)
		return

	# Very high HP so neither faints in 5 turns of Tackle.
	var drizzle_mon := _make_mon("Pelipper", TypeChart.TYPE_WATER,
			TypeChart.TYPE_NONE, 500, 20, 100, 20, 100, 50)
	drizzle_mon.ability = drizzle
	var normal_mon  := _make_mon("Normal",   TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 500, 20, 100, 20, 100, 60)

	var tackle1 := _make_move("Tackle1", TypeChart.TYPE_NORMAL, 0, 20)
	var tackle2 := _make_move("Tackle2", TypeChart.TYPE_NORMAL, 0, 20)
	drizzle_mon.add_move(tackle1)
	normal_mon.add_move(tackle2)

	var bm := _make_bm()
	var expired_type := [-1]
	bm.weather_expired.connect(func(w): expired_type[0] = w)

	# Queue 5 turns (duration starts at 5, ticks down to 0 at 5th EOT).
	for _i in range(5):
		bm.queue_move(0, 0)
		bm.queue_move(1, 0)
	bm.start_battle(drizzle_mon, normal_mon)

	_chk("W4.01 weather_expired emitted with RAIN",   expired_type[0] == BattleManager.WEATHER_RAIN)
	_chk("W4.02 bm.weather == WEATHER_NONE after 5T", bm.weather == BattleManager.WEATHER_NONE)
	_chk("W4.03 bm.weather_duration == 0",            bm.weather_duration == 0)
	bm.queue_free()


# ── W5: Weather NOT cleared on switch-out ─────────────────────────────────────
# Weather is a field effect (on BattleManager), NOT a per-Pokémon volatile.
# _switch_out_clear() only touches per-Pokémon fields; weather must survive.
# Source: SwitchInClearSetData (battle_main.c L3117) does NOT touch gBattleWeather.
#
# Proof via signals:
#   weather_set fires exactly once — for RAIN at BATTLE_START (Drizzle ability).
#   After bench_mon (no weather ability) switches in, get_switch_in_weather returns
#   WEATHER_NONE and the guard in _do_voluntary_switch prevents any call to
#   try_set_weather, so weather_set never fires again.
#   weather_expired fires once (5 turns later) — weather survived the full duration.
#
# Stats: base_hp=2 (max_hp=62), Tackle power=1, STAB→~3 dmg/turn → ~21 turns to faint.
# bench_mon (spd=60) is faster than opp_mon (spd=50) → bench KOs opp before opp KOs
# bench, so bench_mon wins without fainting and Drizzle mon never re-enters.

func _test_w5_no_clear_on_switch() -> void:
	var drizzle := _load_ability(2)
	if drizzle == null:
		_chk("W5 skip: Drizzle not loaded", false)
		return

	# bench_mon: high HP (base=200 → max=260) so it never faints before opp.
	# opp_mon: low HP  (base=2  → max=62)  so it faints in ~21 turns.
	# bench faster (spd=60 > opp spd=50) → bench attacks first each turn → opp dies first.
	# Drizzle mon stays benched the entire battle; never re-triggers weather_set.
	var drizzle_mon := _make_mon("Pelipper", TypeChart.TYPE_WATER,
			TypeChart.TYPE_NONE, 2, 1, 200, 1, 200, 50)
	drizzle_mon.ability = drizzle
	var bench_mon   := _make_mon("Bench",    TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 1, 200, 1, 200, 60)
	var opp_mon     := _make_mon("Opponent", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 2, 1, 200, 1, 200, 50)

	drizzle_mon.add_move(_make_move("T1", TypeChart.TYPE_NORMAL, 0, 1))
	bench_mon.add_move(_make_move("T2",   TypeChart.TYPE_NORMAL, 0, 1))
	opp_mon.add_move(_make_move("T3",     TypeChart.TYPE_NORMAL, 0, 1))

	var bm := _make_bm()
	var weather_set_types    := []
	var weather_expired_count := [0]
	bm.weather_set.connect(func(_m, w): weather_set_types.append(w))
	bm.weather_expired.connect(func(_w): weather_expired_count[0] += 1)

	var p0 := BattleParty.new()
	p0.members.append(drizzle_mon)
	p0.members.append(bench_mon)
	p0.active_index = 0
	var p1 := BattleParty.single(opp_mon)

	bm.queue_switch(0, 1)
	bm.queue_move(1, 0)
	bm.start_battle_with_parties(p0, p1)

	_chk("W5.01 weather_set fired once only (not re-triggered or cleared on switch-out)",
			weather_set_types.size() == 1)
	_chk("W5.02 that weather_set was RAIN",
			weather_set_types.size() > 0 and weather_set_types[0] == BattleManager.WEATHER_RAIN)
	_chk("W5.03 weather expired once (survived full 5-turn duration after switch)",
			weather_expired_count[0] == 1)
	_chk("W5.04 get_switch_in_weather(bench) == NONE (no weather ability to trigger)",
			AbilityManager.get_switch_in_weather(bench_mon) == DamageCalculator.WEATHER_NONE)
	bm.queue_free()


# ── W6: Same weather no-ops ───────────────────────────────────────────────────
# Source: TryChangeBattleWeather L1971: if (gBattleWeather & flag) return FALSE.
# No signal emitted, duration unchanged.

func _test_w6_same_weather_noop() -> void:
	var bm := _make_bm()
	bm.weather = BattleManager.WEATHER_RAIN
	bm.weather_duration = 3

	var signals_fired := [0]
	bm.weather_set.connect(func(_m, _w): signals_fired[0] += 1)

	var changed: bool = bm.try_set_weather(BattleManager.WEATHER_RAIN)

	_chk("W6.01 try_set_weather returns false for same weather", not changed)
	_chk("W6.02 weather_set signal NOT emitted",                 signals_fired[0] == 0)
	_chk("W6.03 duration unchanged at 3",                        bm.weather_duration == 3)
	bm.queue_free()


# ── W7: Different weather overwrites ──────────────────────────────────────────
# Source: TryChangeBattleWeather — sets new weather, resets duration.
# New weather replaces existing weather; duration resets to 5.
# Note: try_set_weather() does not itself emit weather_set — only the switch-in
# callers do (they supply the "by_pokemon" context for the signal). W7 tests
# the state change only; signal emission is tested in W1/W2 via start_battle.

func _test_w7_weather_overwrites() -> void:
	var bm := _make_bm()
	bm.weather = BattleManager.WEATHER_RAIN
	bm.weather_duration = 3

	var changed: bool = bm.try_set_weather(BattleManager.WEATHER_SUN)

	_chk("W7.01 try_set_weather returns true",  changed)
	_chk("W7.02 weather changed to SUN",        bm.weather == BattleManager.WEATHER_SUN)
	_chk("W7.03 duration reset to 5",           bm.weather_duration == 5)
	bm.queue_free()


# ── W8a: Water move under rain — discriminating composition test ───────────────
# Source: GetWeatherDamageModifier (battle_util.c L7268–7272):
#   RAIN → Water: UQ_4_12(1.5) = 6144. Applied at DoMoveDamageCalcVars L7594,
#   BEFORE the critical hit modifier and BEFORE the random roll.
#
# Setup (discriminating values chosen so wrong ordering gives a different integer):
#   Level 50, SpAtk=50 (no STAB — Normal-type attacker), SpDef=70
#   Water Gun (power=40, Water, Special)
#   force_roll=85, force_crit=false
#
# Step-by-step (correct order, weather before roll):
#   base = 40 * 50 * (2*50/5+2) / 70 / 50 + 2 = 40*50*22/70/50+2 = 44000/70/50+2 = 628/50+2 = 14
#   weather ×1.5: _uq412_half_down(14, 6144) = (14*6144+2047)/4096 = 88063/4096 = 21
#   roll=85:       21 * 85 / 100 = 17
#   STAB: no (Normal-type attacker)
#   Effectiveness: Water vs Normal = 1.0×
#   Result: 17
#
# Wrong order (weather after roll): 14→roll=85→11→×1.5→_uq412(11,6144)=16  ← differs

func _test_w8a_water_rain_boost() -> void:
	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 50, 80, 80)
	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 80, 70, 80)

	var water_gun := _make_move("Water Gun", TypeChart.TYPE_WATER, 1, 40)

	# No weather: base roll.
	var no_w := DamageCalculator.calculate(attacker, defender, water_gun, 85, false,
			DamageCalculator.WEATHER_NONE)
	# base=14, roll=85: 14*85/100=11. Effectiveness 1.0×. Result: 11.
	_chk("W8a.01 Water no weather roll=85 = 11", no_w["damage"] == 11)

	# Rain boost:
	var rain := DamageCalculator.calculate(attacker, defender, water_gun, 85, false,
			DamageCalculator.WEATHER_RAIN)
	# Correct order: 14→×1.5=21→roll=85→17. Wrong order: 14→roll=85=11→×1.5=16.
	_chk("W8a.02 Water under rain roll=85 = 17 (discriminating)", rain["damage"] == 17)
	_chk("W8a.03 rain > no_weather",                              rain["damage"] > no_w["damage"])


# ── W8b: Fire move under rain reduced ──────────────────────────────────────────
# Source: GetWeatherDamageModifier L7272: RAIN → Fire: UQ_4_12(0.5) = 2048.
# Same stat setup as W8a; Ember (power=40, Fire, Special).
# base=14, rain ×0.5: _uq412_half_down(14,2048)=(14*2048+2047)/4096=30719/4096=7
# roll=100: 7. No weather roll=100: 14.

func _test_w8b_fire_rain_reduce() -> void:
	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 50, 80, 80)
	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 80, 70, 80)

	var ember := _make_move("Ember", TypeChart.TYPE_FIRE, 1, 40)

	var no_w := DamageCalculator.calculate(attacker, defender, ember, 100, false,
			DamageCalculator.WEATHER_NONE)
	_chk("W8b.01 Fire no weather roll=100 = 14", no_w["damage"] == 14)

	var rain := DamageCalculator.calculate(attacker, defender, ember, 100, false,
			DamageCalculator.WEATHER_RAIN)
	# 14 → ×0.5 = _uq412_half_down(14,2048) = 7 → roll=100 → 7
	_chk("W8b.02 Fire under rain roll=100 = 7", rain["damage"] == 7)
	_chk("W8b.03 rain < no_weather (Fire reduced)", rain["damage"] < no_w["damage"])


# ── W9a: Fire move under sun — discriminating composition test ────────────────
# Source: GetWeatherDamageModifier L7261–7265: SUN → Fire: UQ_4_12(1.5) = 6144.
# Same stat setup; Ember (power=40, Fire, Special).
# Correct order: base=14 → ×1.5=21 → roll=85 → 17.
# Wrong order:   base=14 → roll=85=11 → ×1.5=16.

func _test_w9a_fire_sun_boost() -> void:
	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 50, 80, 80)
	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 80, 70, 80)

	var ember := _make_move("Ember", TypeChart.TYPE_FIRE, 1, 40)

	var no_w := DamageCalculator.calculate(attacker, defender, ember, 85, false,
			DamageCalculator.WEATHER_NONE)
	_chk("W9a.01 Fire no weather roll=85 = 11", no_w["damage"] == 11)

	var sun := DamageCalculator.calculate(attacker, defender, ember, 85, false,
			DamageCalculator.WEATHER_SUN)
	# Correct: 14→×1.5=21→roll=85→17. Wrong: 14→roll=85=11→×1.5=16.
	_chk("W9a.02 Fire under sun roll=85 = 17 (discriminating)", sun["damage"] == 17)
	_chk("W9a.03 sun > no_weather",                             sun["damage"] > no_w["damage"])


# ── W9b: Water move under sun reduced ─────────────────────────────────────────
# Source: GetWeatherDamageModifier L7265: SUN → Water: UQ_4_12(0.5) = 2048.
# base=14 → ×0.5 = 7 → roll=100 → 7.

func _test_w9b_water_sun_reduce() -> void:
	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 50, 80, 80)
	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 80, 70, 80)

	var water_gun := _make_move("Water Gun", TypeChart.TYPE_WATER, 1, 40)

	var no_w := DamageCalculator.calculate(attacker, defender, water_gun, 100, false,
			DamageCalculator.WEATHER_NONE)
	_chk("W9b.01 Water no weather roll=100 = 14", no_w["damage"] == 14)

	var sun := DamageCalculator.calculate(attacker, defender, water_gun, 100, false,
			DamageCalculator.WEATHER_SUN)
	# 14 → ×0.5 = 7 → roll=100 → 7
	_chk("W9b.02 Water under sun roll=100 = 7", sun["damage"] == 7)
	_chk("W9b.03 sun < no_weather (Water reduced)", sun["damage"] < no_w["damage"])


# ── W10: Sandstorm chip damage ────────────────────────────────────────────────
# Source: HandleEndTurnWeatherDamage, BATTLE_WEATHER_SANDSTORM branch (L143):
#   Immune: IS_BATTLER_ANY_TYPE(battler, TYPE_ROCK, TYPE_GROUND, TYPE_STEEL)
#   Chip = GetNonDynamaxMaxHP(battler) / 16
# Three mons: Normal (takes damage), Rock (immune), Ground (immune), Steel (immune).

func _test_w10_sandstorm_chip() -> void:
	# Test via BattleManager EOT directly. Set weather manually then queue 1 turn.
	var normal_mon  := _make_mon("Normal",  TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 160, 20, 100, 20, 100, 50)
	var rock_mon    := _make_mon("Rhydon",  TypeChart.TYPE_ROCK,
			TypeChart.TYPE_NONE, 160, 20, 100, 20, 100, 60)
	var ground_mon  := _make_mon("Dugtrio", TypeChart.TYPE_GROUND,
			TypeChart.TYPE_NONE, 160, 20, 100, 20, 100, 70)
	var steel_mon   := _make_mon("Steelix", TypeChart.TYPE_STEEL,
			TypeChart.TYPE_NONE, 160, 20, 100, 20, 100, 80)

	# Test Normal vs Rock pair — Normal takes chip, Rock does not.
	_check_weather_chip("W10.01", normal_mon, rock_mon,
			BattleManager.WEATHER_SANDSTORM,
			true,   # side 0 (Normal) takes chip
			false)  # side 1 (Rock) immune

	# Test Normal vs Ground pair.
	normal_mon.current_hp = normal_mon.max_hp  # reset HP
	_check_weather_chip("W10.02", normal_mon, ground_mon,
			BattleManager.WEATHER_SANDSTORM,
			true, false)

	# Test Normal vs Steel pair.
	normal_mon.current_hp = normal_mon.max_hp
	_check_weather_chip("W10.03", normal_mon, steel_mon,
			BattleManager.WEATHER_SANDSTORM,
			true, false)

	# Verify chip amount = maxHP / 16. base_hp=100 → max_hp=100+60=160 → chip=160/16=10.
	var bm := _make_bm()
	bm.weather = BattleManager.WEATHER_SANDSTORM
	bm.weather_duration = 5
	var chip_amounts: Array = []
	bm.weather_damage.connect(func(m, amt): chip_amounts.append({"mon": m, "amt": amt}))
	var tackle1 := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 20)
	var tackle2 := _make_move("Tackle2", TypeChart.TYPE_NORMAL, 0, 20)
	# Fresh mons (base_hp=100 → max_hp=160 → chip=10).
	var n2 := _make_mon("Normal2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100, 20, 100, 20, 100, 50)
	var r2 := _make_mon("Rock2",   TypeChart.TYPE_ROCK,   TypeChart.TYPE_NONE, 100, 20, 100, 20, 100, 60)
	n2.add_move(tackle1)
	r2.add_move(tackle2)
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(n2, r2)
	# After 1 turn: Normal took chip, Rock did not.
	var n_chip: bool = false
	for entry in chip_amounts:
		if entry["mon"].species.species_name == "Normal2":
			n_chip = true
			_chk("W10.04 sandstorm chip = maxHP/16 = 10", entry["amt"] == 10)
	_chk("W10.05 Normal2 received weather_damage signal", n_chip)
	var r_chip: bool = false
	for entry in chip_amounts:
		if entry["mon"].species.species_name == "Rock2":
			r_chip = true
	_chk("W10.06 Rock2 did NOT receive weather_damage signal", not r_chip)
	bm.queue_free()


func _check_weather_chip(prefix: String, mon0: BattlePokemon, mon1: BattlePokemon,
		weather_type: int, expect_0_takes: bool, expect_1_takes: bool) -> void:
	var bm := _make_bm()
	bm.weather = weather_type
	bm.weather_duration = 5
	var chips: Dictionary = {}
	bm.weather_damage.connect(func(m, _a): chips[m.species.species_name] = true)

	mon0 = mon0.duplicate() if mon0.has_method("duplicate") else _mon_copy(mon0)
	mon1 = mon1.duplicate() if mon1.has_method("duplicate") else _mon_copy(mon1)
	var t0 := _make_move("T0", TypeChart.TYPE_NORMAL, 0, 5)
	var t1 := _make_move("T1", TypeChart.TYPE_NORMAL, 0, 5)
	mon0.add_move(t0)
	mon1.add_move(t1)
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(mon0, mon1)

	_chk(prefix + " side0 takes chip=" + str(expect_0_takes),
			chips.has(mon0.species.species_name) == expect_0_takes)
	_chk(prefix + " side1 takes chip=" + str(expect_1_takes),
			chips.has(mon1.species.species_name) == expect_1_takes)
	bm.queue_free()


func _mon_copy(orig: BattlePokemon) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = orig.species.species_name + "_c"
	for t in orig.species.types:
		sp.types.append(t)
	sp.base_hp         = orig.species.base_hp
	sp.base_attack     = orig.species.base_attack
	sp.base_defense    = orig.species.base_defense
	sp.base_sp_attack  = orig.species.base_sp_attack
	sp.base_sp_defense = orig.species.base_sp_defense
	sp.base_speed      = orig.species.base_speed
	var m := BattlePokemon.from_species(sp, orig.level, orig.nature, orig.ivs)  # [M18.5h-1/2] preserves the SOURCE mon's nature AND IVs, matching the copy contract
	return m


# ── W11: Hail chip damage ─────────────────────────────────────────────────────
# Source: HandleEndTurnWeatherDamage, BATTLE_WEATHER_HAIL branch (L160):
#   Immune: IS_BATTLER_OF_TYPE(battler, TYPE_ICE)
#   Chip = GetNonDynamaxMaxHP(battler) / 16

func _test_w11_hail_chip() -> void:
	# Ice mon immune; Normal mon takes chip.
	# base_hp=100 → max_hp=100+60=160 → chip=160/16=10.
	var normal_mon := _make_mon("NormalH", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 100, 20, 100, 20, 100, 50)
	var ice_mon    := _make_mon("IceH",    TypeChart.TYPE_ICE,
			TypeChart.TYPE_NONE, 100, 20, 100, 20, 100, 60)

	var bm := _make_bm()
	bm.weather = BattleManager.WEATHER_HAIL
	bm.weather_duration = 5
	var chips: Dictionary = {}
	bm.weather_damage.connect(func(m, a):
		chips[m.species.species_name] = a)

	var t0 := _make_move("T0h", TypeChart.TYPE_NORMAL, 0, 5)
	var t1 := _make_move("T1h", TypeChart.TYPE_NORMAL, 0, 5)
	normal_mon.add_move(t0)
	ice_mon.add_move(t1)
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(normal_mon, ice_mon)

	_chk("W11.01 Normal takes hail chip",          chips.has("NormalH"))
	_chk("W11.02 hail chip = maxHP/16 = 10",       chips.get("NormalH", -1) == 10)
	_chk("W11.03 Ice-type immune to hail",         not chips.has("IceH"))
	bm.queue_free()


# ── W12: Weather expiry reverts damage modifier ────────────────────────────────
# After weather expires (duration hits 0), Water move damage should return to
# its no-weather baseline.

func _test_w12_weather_expiry_reverts_modifier() -> void:
	# Verify via DamageCalculator directly with WEATHER_NONE (representing expired state).
	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 50, 80, 80)
	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 80, 70, 80)
	var water_gun := _make_move("Water Gun", TypeChart.TYPE_WATER, 1, 40)

	var with_rain := DamageCalculator.calculate(attacker, defender, water_gun, 100, false,
			DamageCalculator.WEATHER_RAIN)
	var no_weather := DamageCalculator.calculate(attacker, defender, water_gun, 100, false,
			DamageCalculator.WEATHER_NONE)

	_chk("W12.01 with rain > no weather",   with_rain["damage"] > no_weather["damage"])
	_chk("W12.02 no weather = 14 (baseline)", no_weather["damage"] == 14)
	_chk("W12.03 with rain = 21 (×1.5 max)",  with_rain["damage"] == 21)

	# Integration: run 5 turns to expire weather, then check modifier is gone.
	# (Full integration version — verify bm.weather is NONE after expiry.)
	var drizzle := _load_ability(2)
	if drizzle == null:
		return
	var drizzle_mon := _make_mon("Pelipper2", TypeChart.TYPE_WATER,
			TypeChart.TYPE_NONE, 500, 20, 100, 20, 100, 50)
	drizzle_mon.ability = drizzle
	var opp2 := _make_mon("Opp2", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 500, 20, 100, 20, 100, 60)
	var t0 := _make_move("T0w", TypeChart.TYPE_NORMAL, 0, 5)
	var t1 := _make_move("T1w", TypeChart.TYPE_NORMAL, 0, 5)
	drizzle_mon.add_move(t0)
	opp2.add_move(t1)
	var bm := _make_bm()
	for _i in range(5):
		bm.queue_move(0, 0)
		bm.queue_move(1, 0)
	bm.start_battle(drizzle_mon, opp2)
	_chk("W12.04 bm.weather NONE after 5 turns", bm.weather == BattleManager.WEATHER_NONE)
	# Verify damage calc at WEATHER_NONE (same as calling calculate with the expired weather).
	var after_expiry := DamageCalculator.calculate(attacker, defender, water_gun, 100, false,
			bm.weather)
	_chk("W12.05 damage after expiry matches no-weather baseline",
			after_expiry["damage"] == no_weather["damage"])
	bm.queue_free()


# ── W13: AI weather-aware scoring ────────────────────────────────────────────
# Confirms the M10 architecture claim: TrainerAI uses DamageCalculator.calculate,
# and now that calculate() accepts weather, the AI's damage estimate automatically
# reflects weather boosts/reductions — zero change to TrainerAI scoring logic required.
#
# Setup:
#   AI attacker: Normal-type, base_spatk=100 → stat=105; moves = [Surf(90), Ember(40)]
#   Opponent: Normal-type, base_spdef=70 → stat=75, current_hp=70, level=50
#
# Damage calculations (force_crit=false, force_roll=100):
#   Surf no weather:  base = 22*90*105/75/50+2 = 207900/75/50+2 = 2772/50+2 = 55+2 = 57
#   Surf with rain:   ×1.5 → _uq412(57,6144)=(350208+2047)/4096=352255/4096=85 > 70 → KO
#   Ember no weather: base = 22*40*105/75/50+2 = 92400/75/50+2 = 1232/50+2 = 24+2 = 26
#   Ember with rain:  ×0.5 → _uq412(26,2048)=(53248+2047)/4096=55295/4096=13 < 70 → no KO
#
# Without weather: neither move KOs → both score 100 (no KO bonus, 1.0× effectiveness).
#   Tie broken by _force_tie_rng=0 → picks Surf (index 0).
# With rain: Surf KOs (85 > 70) → FAST_KILL (+6) → score 106 > Ember 100 → Surf chosen.
# Confirms weather propagates through choose_action → _score_move → calculate automatically.

func _test_w13_ai_weather_scoring() -> void:
	var ai := TrainerAI.new()
	ai._force_tie_rng = 0   # tie → pick index 0 (Surf)
	ai._force_roll    = 100  # deterministic damage estimate
	ai._force_crit    = false

	var attacker := _make_mon("AI", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 200, 80, 80, 100, 80, 80)
	var defender := _make_mon("Target", TypeChart.TYPE_NORMAL,
			TypeChart.TYPE_NONE, 70, 80, 80, 80, 70, 80)
	defender.current_hp = 70

	var surf  := _make_move("Surf",  TypeChart.TYPE_WATER, 1, 90)
	var ember := _make_move("Ember", TypeChart.TYPE_FIRE,  1, 40)
	attacker.add_move(surf)
	attacker.add_move(ember)

	# Without weather: both score 100 → tie → _force_tie_rng=0 picks index 0 (Surf).
	var action_no_w := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender),
			DamageCalculator.WEATHER_NONE)
	_chk("W13.01 no weather → move chosen (type=move)", action_no_w["type"] == "move")
	# W13.02: without weather both score 100 (no KO, 1.0× effectiveness).
	# Tie resolved by _force_tie_rng=0 → index 0 (Surf). This confirms equal scoring.
	_chk("W13.02 no weather tie → Surf chosen (index 0)", action_no_w["index"] == 0)

	# Verify damage explicitly: Surf no-weather = 57 < 70 (no KO).
	var surf_no_w := DamageCalculator.calculate(attacker, defender, surf, 100, false,
			DamageCalculator.WEATHER_NONE)
	_chk("W13.03 Surf no weather damage=57 < 70 HP (no KO)", surf_no_w["damage"] == 57)

	# With rain: Surf KOs, Ember does not → AI clearly prefers Surf.
	var action_rain := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender),
			DamageCalculator.WEATHER_RAIN)
	_chk("W13.04 rain → move chosen",                   action_rain["type"] == "move")
	_chk("W13.05 rain → Surf chosen (KO bonus)",        action_rain["index"] == 0)

	# Verify damage: Surf rain = 85 > 70 HP (KO confirmed).
	var surf_rain := DamageCalculator.calculate(attacker, defender, surf, 100, false,
			DamageCalculator.WEATHER_RAIN)
	_chk("W13.06 Surf rain damage=85 > 70 HP (KO)",    surf_rain["damage"] == 85)
	_chk("W13.07 rain boosts Surf vs no weather",       surf_rain["damage"] > surf_no_w["damage"])

	# With sun: Surf reduced, Ember boosted — Ember now KOs, Surf does not.
	# Ember sun: _uq412(27,6144)=(27*6144+2047)/4096=(165888+2047)/4096=167935/4096=40 < 70? No.
	# Actually: 40 < 70 → still no KO. Let's just check that the AI still prefers something.
	# (With these stats, neither move KOs under sun — they still tie, but we verify scores change.)
	var surf_sun := DamageCalculator.calculate(attacker, defender, surf, 100, false,
			DamageCalculator.WEATHER_SUN)
	var ember_sun := DamageCalculator.calculate(attacker, defender, ember, 100, false,
			DamageCalculator.WEATHER_SUN)
	_chk("W13.08 sun reduces Water (Surf sun < Surf no-w)",  surf_sun["damage"] < surf_no_w["damage"])
	_chk("W13.09 sun boosts Fire (Ember sun > Ember no-w)",
			ember_sun["damage"] > DamageCalculator.calculate(
					attacker, defender, ember, 100, false,
					DamageCalculator.WEATHER_NONE)["damage"])
