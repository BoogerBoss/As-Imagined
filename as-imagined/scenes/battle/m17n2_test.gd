extends Node

# M17n-2 test suite — Weather/evasion + speed family, plus Air Lock (docs/m17n_recon.md
# Group 2). Continues the m17n<N> numeral-suffix naming convention established in
# [M17n-1] (Godot resource names can't contain hyphens).
#
# Scope: 8 abilities, per docs/decisions.md [M17n-2]:
#   Weather-conditional Speed doublers: Swift Swim (33, rain), Chlorophyll (34, sun),
#     Sand Rush (146, sandstorm) — extend the EXISTING StatusManager.effective_speed
#     (the Slush Rush precedent, [M17c]). Swift Swim/Chlorophyll ALSO respect the
#     holder's own Utility Umbrella (a source-confirmed nuance NOT shared with Sand
#     Rush/Slush Rush, since Umbrella only ever strips rain/sun).
#   Weather-conditional evasion (accuracy-reduction shape): Sand Veil (8, sandstorm),
#     Snow Cloak (81, hail) — extend the EXISTING AbilityManager.accuracy_modifier_percent
#     ([M17a]'s Compound Eyes/Hustle precedent), now also defender-aware.
#   Field-wide weather negation: Air Lock (76), Cloud Nine (13) — confirmed genuinely
#     identical from source (same case branch, no asymmetry). New
#     `AbilityManager.is_weather_negated`/`BattleManager._effective_weather()` — ONE
#     substitution point that automatically covers every existing weather-conditional
#     ability (Flower Gift, Solar Power, Dry Skin, Leaf Guard, Slush Rush) as well as
#     this tier's own three new abilities, without touching their individual code.
#   Reactive weather-setter: Sand Spit (245) — sets Sandstorm on any damaging hit,
#     reusing the EXISTING try_set_weather (Drizzle/Drought/Sand Stream's function).
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state.
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing test function.
#   - Type immunity precedes ability logic: all scenarios use Normal-type combatants
#     except where a specific type interaction is the mechanic under test.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_speed_doublers_unit()
	_test_section_3_utility_umbrella_nuance_unit()
	_test_section_4_evasion_unit()
	_test_section_5_weather_negated_unit()
	_test_section_6_swift_swim_full_battle()
	_test_section_7_air_lock_negates_speed_doubler_full_battle()
	_test_section_8_damage_modifier_negation_full_battle()
	_test_section_9_end_of_turn_chip_negation_full_battle()
	_test_section_10_sand_veil_full_battle()
	_test_section_11_sand_spit_full_battle()
	_test_section_12_mold_breaker_bypass()
	_test_section_13_neutralizing_gas_suppression()
	_test_section_14_negative_case()

	var total := _pass + _fail
	print("m17n2_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, types: Array[int], hp: int = 100, atk: int = 80,
		def_stat: int = 80, spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


func _give_item(mon: BattlePokemon, hold_effect: int) -> void:
	var item := ItemData.new()
	item.item_name = "TestItem"
	item.hold_effect = hold_effect
	mon.held_item = item


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var sand_veil := _load_ability(8)
	_chk("S1.01 Sand Veil id=8, breakable=true", sand_veil.ability_id == 8 and sand_veil.breakable)

	var snow_cloak := _load_ability(81)
	_chk("S1.02 Snow Cloak id=81, breakable=true", snow_cloak.ability_id == 81 and snow_cloak.breakable)

	var swift_swim := _load_ability(33)
	_chk("S1.03 Swift Swim id=33, NOT breakable (self-check)",
			swift_swim.ability_id == 33 and not swift_swim.breakable)

	var chlorophyll := _load_ability(34)
	_chk("S1.04 Chlorophyll id=34, NOT breakable", chlorophyll.ability_id == 34 and not chlorophyll.breakable)

	var sand_rush := _load_ability(146)
	_chk("S1.05 Sand Rush id=146, NOT breakable", sand_rush.ability_id == 146 and not sand_rush.breakable)

	var air_lock := _load_ability(76)
	_chk("S1.06 Air Lock id=76, NOT breakable (field-wide passive)",
			air_lock.ability_id == 76 and not air_lock.breakable)

	var cloud_nine := _load_ability(13)
	_chk("S1.07 Cloud Nine id=13, NOT breakable", cloud_nine.ability_id == 13 and not cloud_nine.breakable)

	var sand_spit := _load_ability(245)
	_chk("S1.08 Sand Spit id=245, NOT breakable", sand_spit.ability_id == 245 and not sand_spit.breakable)


# ── Section 2: Speed doublers — direct unit tests ────────────────────────────

func _test_section_2_speed_doublers_unit() -> void:
	var swift_swim := _load_ability(33)
	var chlorophyll := _load_ability(34)
	var sand_rush := _load_ability(146)

	var ss := _make_mon("SwiftSwimMon", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 50)
	ss.ability = swift_swim
	var base_speed: int = StatusManager.effective_speed(ss, DamageCalculator.WEATHER_NONE)
	var rain_speed: int = StatusManager.effective_speed(ss, DamageCalculator.WEATHER_RAIN)
	_chk("S2.01 Swift Swim doubles Speed in rain", rain_speed == base_speed * 2)
	_chk("S2.02 Swift Swim does NOT double outside rain (sun discriminator)",
			StatusManager.effective_speed(ss, DamageCalculator.WEATHER_SUN) == base_speed)

	var ch := _make_mon("ChlorophyllMon", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 50)
	ch.ability = chlorophyll
	var ch_base: int = StatusManager.effective_speed(ch, DamageCalculator.WEATHER_NONE)
	_chk("S2.03 Chlorophyll doubles Speed in sun",
			StatusManager.effective_speed(ch, DamageCalculator.WEATHER_SUN) == ch_base * 2)
	_chk("S2.04 Chlorophyll does NOT double in rain (discriminator)",
			StatusManager.effective_speed(ch, DamageCalculator.WEATHER_RAIN) == ch_base)

	var sr := _make_mon("SandRushMon", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 50)
	sr.ability = sand_rush
	var sr_base: int = StatusManager.effective_speed(sr, DamageCalculator.WEATHER_NONE)
	_chk("S2.05 Sand Rush doubles Speed in sandstorm",
			StatusManager.effective_speed(sr, DamageCalculator.WEATHER_SANDSTORM) == sr_base * 2)
	_chk("S2.06 Sand Rush does NOT double in hail (discriminator)",
			StatusManager.effective_speed(sr, DamageCalculator.WEATHER_HAIL) == sr_base)


# ── Section 3: Utility Umbrella nuance — Swift Swim/Chlorophyll only ─────────

func _test_section_3_utility_umbrella_nuance_unit() -> void:
	var swift_swim := _load_ability(33)
	var sand_rush := _load_ability(146)

	var ss := _make_mon("UmbrellaSwiftSwim", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 50)
	ss.ability = swift_swim
	_give_item(ss, ItemManager.HOLD_EFFECT_UTILITY_UMBRELLA)
	var base: int = StatusManager.effective_speed(ss, DamageCalculator.WEATHER_NONE)
	_chk("S3.01 Utility Umbrella blocks Swift Swim's rain boost",
			StatusManager.effective_speed(ss, DamageCalculator.WEATHER_RAIN) == base)

	# Discriminator: Sand Rush's sandstorm boost is NOT blocked by Utility Umbrella
	# (source only strips rain/sun, never sandstorm/hail).
	var sr := _make_mon("UmbrellaSandRush", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 50)
	sr.ability = sand_rush
	_give_item(sr, ItemManager.HOLD_EFFECT_UTILITY_UMBRELLA)
	var sr_base: int = StatusManager.effective_speed(sr, DamageCalculator.WEATHER_NONE)
	_chk("S3.02 Utility Umbrella does NOT block Sand Rush's sandstorm boost",
			StatusManager.effective_speed(sr, DamageCalculator.WEATHER_SANDSTORM) == sr_base * 2)


# ── Section 4: Evasion (Sand Veil / Snow Cloak) — direct unit tests ──────────

func _test_section_4_evasion_unit() -> void:
	var sand_veil := _load_ability(8)
	var snow_cloak := _load_ability(81)
	var tackle := _load_move(33)

	var attacker := _make_mon("EvasionAttacker", [TypeChart.TYPE_NORMAL])
	var sv := _make_mon("SandVeilMon", [TypeChart.TYPE_NORMAL])
	sv.ability = sand_veil
	_chk("S4.01 Sand Veil: attacker accuracy x0.80 in sandstorm",
			AbilityManager.accuracy_modifier_percent(attacker, tackle, false, sv,
					DamageCalculator.WEATHER_SANDSTORM) == 80)
	_chk("S4.02 Sand Veil: no effect outside sandstorm (discriminator)",
			AbilityManager.accuracy_modifier_percent(attacker, tackle, false, sv,
					DamageCalculator.WEATHER_NONE) == 100)

	var sc := _make_mon("SnowCloakMon", [TypeChart.TYPE_NORMAL])
	sc.ability = snow_cloak
	_chk("S4.03 Snow Cloak: attacker accuracy x0.80 in hail",
			AbilityManager.accuracy_modifier_percent(attacker, tackle, false, sc,
					DamageCalculator.WEATHER_HAIL) == 80)
	_chk("S4.04 Snow Cloak: no effect in sandstorm (discriminator)",
			AbilityManager.accuracy_modifier_percent(attacker, tackle, false, sc,
					DamageCalculator.WEATHER_SANDSTORM) == 100)


# ── Section 5: is_weather_negated — direct unit tests ────────────────────────

func _test_section_5_weather_negated_unit() -> void:
	var air_lock := _load_ability(76)
	var cloud_nine := _load_ability(13)

	var al := _make_mon("AirLockMon", [TypeChart.TYPE_NORMAL])
	al.ability = air_lock
	_chk("S5.01 Air Lock negates weather (field-wide check)",
			AbilityManager.is_weather_negated([al]) == true)

	var cn := _make_mon("CloudNineMon", [TypeChart.TYPE_NORMAL])
	cn.ability = cloud_nine
	_chk("S5.02 Cloud Nine negates weather too (confirmed identical)",
			AbilityManager.is_weather_negated([cn]) == true)

	var plain := _make_mon("NoNegationMon", [TypeChart.TYPE_NORMAL])
	_chk("S5.03 ordinary Pokémon: weather NOT negated",
			AbilityManager.is_weather_negated([plain]) == false)

	# A fainted Air Lock holder does not negate weather.
	var al_fainted := _make_mon("AirLockFainted", [TypeChart.TYPE_NORMAL])
	al_fainted.ability = air_lock
	al_fainted.fainted = true
	_chk("S5.04 a FAINTED Air Lock holder does not negate weather",
			AbilityManager.is_weather_negated([al_fainted]) == false)


# ── Section 6: Swift Swim — full-battle turn-order confirmation ──────────────

func _test_section_6_swift_swim_full_battle() -> void:
	var tackle := _load_move(33)
	var swift_swim := _load_ability(33)

	# Normally slower attacker gets Swift Swim; in rain it should outrun the opponent.
	var slow_ss := _make_mon("BattleSwiftSwim", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	slow_ss.ability = swift_swim
	slow_ss.add_move(tackle)
	var faster_opp := _make_mon("BattleFasterOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	faster_opp.add_move(tackle)

	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.weather = DamageCalculator.WEATHER_RAIN
	bm.weather_duration = 10
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	bm.start_battle_with_parties(BattleParty.single(slow_ss), BattleParty.single(faster_opp))

	_chk("S6.01 Swift Swim's holder (normally slower) acted FIRST in rain",
			not move_executed_events.is_empty() and move_executed_events[0][0] == slow_ss)

	bm.queue_free()


# ── Section 7: Air Lock negates a speed-doubler — key cross-ability test ────

func _test_section_7_air_lock_negates_speed_doubler_full_battle() -> void:
	var tackle := _load_move(33)
	var swift_swim := _load_ability(33)
	var air_lock := _load_ability(76)

	var slow_ss := _make_mon("ALBattleSwiftSwim", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	slow_ss.ability = swift_swim
	slow_ss.add_move(tackle)
	var faster_al := _make_mon("ALBattleFasterOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	faster_al.ability = air_lock
	faster_al.add_move(tackle)

	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.weather = DamageCalculator.WEATHER_RAIN
	bm.weather_duration = 10
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	bm.start_battle_with_parties(BattleParty.single(slow_ss), BattleParty.single(faster_al))

	_chk("S7.01 with Air Lock present, Swift Swim's boost is negated — the naturally " +
			"FASTER Pokémon (Air Lock holder) acts first despite rain being active",
			not move_executed_events.is_empty() and move_executed_events[0][0] == faster_al)

	bm.queue_free()


# ── Section 8: Air Lock negates the weather DAMAGE modifier ──────────────────

func _test_section_8_damage_modifier_negation_full_battle() -> void:
	var water_gun := _load_move(55)
	var air_lock := _load_ability(76)

	var attacker_plain := _make_mon("DmgModAttackerPlain", [TypeChart.TYPE_WATER], 100, 80, 60, 60, 60, 60)
	var target_plain := _make_mon("DmgModTargetPlain", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	var baseline: Dictionary = DamageCalculator.calculate(attacker_plain, target_plain, water_gun, 100, false,
			DamageCalculator.WEATHER_NONE)
	var boosted: Dictionary = DamageCalculator.calculate(attacker_plain, target_plain, water_gun, 100, false,
			DamageCalculator.WEATHER_RAIN)
	_chk("S8.01 sanity: rain boosts a Water move's damage (x1.5) when weather is NOT negated",
			boosted["damage"] > baseline["damage"])

	# Full-battle confirmation: with Air Lock present, damage matches the NO-weather
	# baseline even though bm.weather is set to rain.
	var attacker := _make_mon("DmgModAttacker", [TypeChart.TYPE_WATER], 100, 80, 60, 60, 60, 60)
	attacker.add_move(water_gun)
	var target := _make_mon("DmgModTarget", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 30)
	target.ability = air_lock
	target.add_move(water_gun)

	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.weather = DamageCalculator.WEATHER_RAIN
	bm.weather_duration = 10
	bm._force_roll = 100  # deterministic, matches the forced-roll baseline/boosted calcs above
	bm._force_crit = false  # matches the baseline/boosted calcs' force_crit=false — a stray
	# crit here would inflate damage above the baseline even with the roll forced, a real
	# flaky-test bug caught during this tier's own reruns (see docs/decisions.md [M17n-2])
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(target))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == target)
	_chk("S8.02 with Air Lock present, damage matches the un-boosted baseline (rain negated)",
			not hit.is_empty() and hit[0][3] == baseline["damage"])
	_chk("S8.03 damage is LESS than what rain would have boosted it to",
			not hit.is_empty() and hit[0][3] < boosted["damage"])

	bm.queue_free()


# ── Section 9: Air Lock negates end-of-turn weather chip damage ─────────────

func _test_section_9_end_of_turn_chip_negation_full_battle() -> void:
	var tackle := _load_move(33)
	var air_lock := _load_ability(76)

	# Without Air Lock: sandstorm chip should occur.
	var a1 := _make_mon("ChipAttacker1", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 200)
	a1.add_move(tackle)
	var b1 := _make_mon("ChipTarget1", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	b1.add_move(tackle)

	var chip_events1 := []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.weather = DamageCalculator.WEATHER_SANDSTORM
	bm1.weather_duration = 10
	bm1.weather_damage.connect(func(m, amt): chip_events1.push_back([m, amt]))
	bm1.start_battle_with_parties(BattleParty.single(a1), BattleParty.single(b1))
	_chk("S9.01 sanity: sandstorm chip damage occurs without Air Lock",
			not chip_events1.is_empty())
	bm1.queue_free()

	# With Air Lock present (on either side): no chip damage at all.
	var a2 := _make_mon("ChipAttacker2", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 200)
	a2.ability = air_lock
	a2.add_move(tackle)
	var b2 := _make_mon("ChipTarget2", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	b2.add_move(tackle)

	var chip_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.weather = DamageCalculator.WEATHER_SANDSTORM
	bm2.weather_duration = 10
	bm2.weather_damage.connect(func(m, amt): chip_events2.push_back([m, amt]))
	bm2.start_battle_with_parties(BattleParty.single(a2), BattleParty.single(b2))
	_chk("S9.02 with Air Lock present, NO sandstorm chip damage occurs at all",
			chip_events2.is_empty())
	bm2.queue_free()


# ── Section 10: Sand Veil — full-battle accuracy reduction ──────────────────

func _test_section_10_sand_veil_full_battle() -> void:
	var tackle := _load_move(33)
	var sand_veil := _load_ability(8)

	var attacker := _make_mon("SandVeilAttacker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	attacker.add_move(tackle)
	var target := _make_mon("SandVeilTarget", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	target.ability = sand_veil
	target.add_move(tackle)

	var move_missed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.weather = DamageCalculator.WEATHER_SANDSTORM
	bm.weather_duration = 10
	bm.move_missed.connect(func(a, r): move_missed_events.push_back([a, r]))
	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(target))

	# Not asserting a specific hit/miss outcome (accuracy is probabilistic) — instead
	# confirm the modifier itself is correct via the direct unit test in Section 4;
	# here just confirm the battle runs to completion without error as an integration
	# sanity check.
	_chk("S10.01 Sand Veil full-battle scenario runs without error",
			bm.get_phase() == BattleManager.BattlePhase.BATTLE_END)

	bm.queue_free()


# ── Section 11: Sand Spit — full-battle reactive weather-set ────────────────

func _test_section_11_sand_spit_full_battle() -> void:
	var tackle := _load_move(33)
	var sand_spit := _load_ability(245)

	var attacker := _make_mon("SandSpitAttacker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	attacker.add_move(tackle)
	var target := _make_mon("SandSpitTarget", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 30)
	target.ability = sand_spit
	target.add_move(tackle)

	var weather_set_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.weather_set.connect(func(p, w): weather_set_events.push_back([p, w]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(target))

	_chk("S11.01 Sand Spit set Sandstorm after being hit",
			weather_set_events.any(func(e): return e[0] == target and e[1] == DamageCalculator.WEATHER_SANDSTORM))

	bm.queue_free()

	# Negative-shape: Sand Spit does NOT re-fire the signal once Sandstorm is already active.
	var attacker2 := _make_mon("SandSpitAttacker2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 200)
	attacker2.add_move(tackle)
	var target2 := _make_mon("SandSpitTarget2", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 30)
	target2.ability = sand_spit
	target2.add_move(tackle)

	var weather_set_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.weather = DamageCalculator.WEATHER_SANDSTORM
	bm2.weather_duration = 10
	bm2.weather_set.connect(func(p, w): weather_set_events2.push_back([p, w]))
	bm2.start_battle_with_parties(BattleParty.single(attacker2), BattleParty.single(target2))

	_chk("S11.02 Sand Spit does NOT re-emit weather_set when Sandstorm is already active",
			weather_set_events2.is_empty())

	bm2.queue_free()


# ── Section 12: Mold Breaker bypass — Sand Veil/Snow Cloak only (breakable) ──

func _test_section_12_mold_breaker_bypass() -> void:
	var mold_breaker := _load_ability(104)
	var sand_veil := _load_ability(8)
	var tackle := _load_move(33)

	var mb_attacker := _make_mon("MBAttackerN2", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker

	var sv := _make_mon("SandVeilMB", [TypeChart.TYPE_NORMAL])
	sv.ability = sand_veil
	_chk("S12.01 Mold Breaker bypasses Sand Veil's accuracy reduction",
			AbilityManager.accuracy_modifier_percent(mb_attacker, tackle, false, sv,
					DamageCalculator.WEATHER_SANDSTORM) == 100)


# ── Section 13: Neutralizing Gas suppression ─────────────────────────────────

func _test_section_13_neutralizing_gas_suppression() -> void:
	var sand_veil := _load_ability(8)
	var swift_swim := _load_ability(33)
	var air_lock := _load_ability(76)
	var tackle := _load_move(33)

	var attacker := _make_mon("NGAttackerN2", [TypeChart.TYPE_NORMAL])

	var sv := _make_mon("SandVeilNG", [TypeChart.TYPE_NORMAL])
	sv.ability = sand_veil
	_chk("S13.01 Neutralizing Gas suppresses Sand Veil",
			AbilityManager.accuracy_modifier_percent(attacker, tackle, true, sv,
					DamageCalculator.WEATHER_SANDSTORM) == 100)

	var ss := _make_mon("SwiftSwimNG", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 50)
	ss.ability = swift_swim
	var ss_base: int = StatusManager.effective_speed(ss, DamageCalculator.WEATHER_NONE, true)
	_chk("S13.02 Neutralizing Gas suppresses Swift Swim",
			StatusManager.effective_speed(ss, DamageCalculator.WEATHER_RAIN, true) == ss_base)

	var al := _make_mon("AirLockNG", [TypeChart.TYPE_NORMAL])
	al.ability = air_lock
	_chk("S13.03 Neutralizing Gas suppresses Air Lock's own weather-negation",
			AbilityManager.is_weather_negated([al], true) == false)


# ── Section 14: Negative case ────────────────────────────────────────────────

func _test_section_14_negative_case() -> void:
	var tackle := _load_move(33)
	var plain := _make_mon("NegControlN2", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 50)
	var base: int = StatusManager.effective_speed(plain, DamageCalculator.WEATHER_NONE)
	_chk("S14.01 ordinary Pokémon: no speed change under any weather",
			StatusManager.effective_speed(plain, DamageCalculator.WEATHER_RAIN) == base
			and StatusManager.effective_speed(plain, DamageCalculator.WEATHER_SUN) == base
			and StatusManager.effective_speed(plain, DamageCalculator.WEATHER_SANDSTORM) == base)

	var attacker := _make_mon("NegControlAttackerN2", [TypeChart.TYPE_NORMAL])
	_chk("S14.02 ordinary Pokémon: no accuracy change under any weather",
			AbilityManager.accuracy_modifier_percent(attacker, tackle, false, plain,
					DamageCalculator.WEATHER_SANDSTORM) == 100)

	_chk("S14.03 ordinary Pokémon: does not negate weather",
			AbilityManager.is_weather_negated([plain]) == false)
