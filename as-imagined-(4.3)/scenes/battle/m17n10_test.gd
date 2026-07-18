extends Node

# M17n-10 test suite — Group 8, "unique/standalone" part 1: Screen Cleaner, Liquid
# Ooze, Pressure, Quick Feet, Guard Dog, Forecast.
#
# RECOVERY CONTEXT: a prior session crashed mid-implementation. Step 0 of the
# recovery re-verified everything from scratch against actual code state (not the
# crashed session's own comments): Liquid Ooze and Forecast were BOTH already fully
# implemented and correctly wired (confirmed independently against source in this
# session), but NONE of the 6 abilities' AbilityData `.tres` files had been
# regenerated yet — all 6 still had empty placeholder descriptions/ai_rating=0 even
# though Liquid Ooze/Forecast's GDScript logic was complete, confirming the crash
# left a real, if narrow, gap even in the "already done" abilities. Screen Cleaner,
# Pressure, Quick Feet, and Guard Dog had only their ability-ID constants defined —
# zero implementation logic existed for any of the four. This session completed all
# 4, regenerated all 6 `.tres` files, and wrote this test suite from scratch.
#
# IDs re-verified fresh against include/constants/abilities.h: Screen Cleaner=251,
# Liquid Ooze=64, Pressure=46, Quick Feet=95, Guard Dog=275, Forecast=59.
#
# Screen Cleaner: TryRemoveScreens (battle_util.c L9001-9022) clears
# Reflect/Light Screen/Aurora Veil (SIDE_STATUS_SCREEN_ANY — NOT Safeguard/Mist) from
# BOTH sides unconditionally on switch-in, reusing Brick Break's exact clear-and-
# signal shape from `[M16c]`.
#
# Liquid Ooze: SetHealScript (battle_move_resolution.c L2586-2600) — the drained
# Pokémon's OWN ability inverts the attacker's heal into damage of the identical
# amount, at the single existing drain-application chokepoint. No `breakable` flag.
#
# Pressure: CancelerPPDeduction (battle_move_resolution.c L982-1002) — +1 PP per
# live, non-ally Pressure holder for spread/TARGET_ALL_BATTLERS/TARGET_FIELD moves
# (the doubles-spread edge case: 2 Pressure holders costs 3 PP, not 2); +1 PP only if
# the single resolved target itself has Pressure otherwise; TARGET_OPPONENTS_FIELD
# hazards are explicitly excluded from the single-target branch and don't match the
# other list either.
#
# Quick Feet: battle_main.c L4676-4677 (unconditional ×1.5 boost for ANY major
# status1 condition) + L4712-4713 (paralysis's OWN speed-halving check is gated
# `ability != ABILITY_QUICK_FEET`) — a REPLACE, not a stack: a paralyzed Quick Feet
# holder gets ×1.5, never ×1.5×0.5. Resolves the stale M3-era decisions.md gap note
# which additionally cited the wrong ability_id (7, not 95 — see this session's
# decisions.md entry for the correction).
#
# Guard Dog: TWO independent halves, both confirmed from source, not just the
# Intimidate-reversal half the recon originally described. (1) IsIntimidateBlocked
# (battle_stat_change.c L676-690) — reverses (not blocks) Intimidate's -1 Attack drop
# into a +1 raise for the INTIMIDATED Pokémon itself, reusing
# BattleScript_DefiantActivates (confirming Defiant's own reactive-raise shape, but
# Intimidate-specific, not "any Attack decrease"). Gated on Attack not already at the
# -6 floor (the same no-op gate `[M17b]` established for Defiant/Competitive). (2)
# EFFECT_HIT_SWITCH_TARGET handling (battle_move_resolution.c L3517-3524) — a
# completely separate mechanic that unconditionally blocks a forced-switch move
# (Roar/Whirlwind) from ever applying, no stat interaction at all. `.breakable =
# TRUE` covers BOTH halves — a Mold-Breaker attacker's Intimidate is not reversed,
# and a Mold-Breaker attacker's Roar still forces the switch. Source's Red-Card
# forced-switch reference (L3748) has no equivalent here (no Red Card item in this
# project, confirmed via grep) and its Suction-Cups reference is a different,
# unimplemented ability — both out of scope. Its Flower-Veil-ally speed-order
# tie-break (L678-681, a doubles-only double-application guard) is also out of
# scope, flagged not implemented.
#
# Forecast: ABILITYEFFECT_ON_WEATHER dispatch (battle_util.c L4696-4712), Castform's
# own form-change table (sun→Fire, rain→Water, hail/snow→Ice — this project's single
# WEATHER_HAIL constant covers both per its existing weather model — else→Normal).
# Utility Umbrella exempts sun/rain specifically (IsBattlerWeatherAffected,
# L9295), NOT hail — the same asymmetry `[M17n-2]` already established for Swift
# Swim/Chlorophyll vs Sand Rush/Slush Rush. Reacts through the new
# `BattleManager._notify_weather_changed()` broadcast hook, fired from all 4 places
# weather actually changes in this project (switch-in setter, Baton Pass, Sand Spit,
# natural end-of-turn expiration).
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state, EXCEPT where a mon's own action is
#     permanently frozen by fainting partway through the battle (Pressure's PP
#     tests) — reading a fainted mon's own current_pp/stat_stages afterward is safe
#     since nothing can change them further, the same reasoning `[M17n-9]`'s Magic
#     Bounce section used for a KO'd attacker.
#   - Type immunity precedes ability logic: neutral Normal-vs-Normal / Grass-vs-
#     Normal matchups throughout.
#   - Pairwise comparisons force both _force_roll and _force_crit identically.
#   - _force_hit = true on any non-100-accuracy move used as a mechanism probe.
#
# Ground truth: pokeemerald_expansion src/battle_util.c (TryRemoveScreens L9001-9022,
#   ABILITYEFFECT_ON_WEATHER L4696-4712, IsBattlerWeatherAffected L9293-9302);
#   src/battle_move_resolution.c (SetHealScript L2586-2600, CancelerPPDeduction
#   L982-1002, EFFECT_HIT_SWITCH_TARGET L3517-3524); src/battle_main.c
#   (GetBattlerTotalSpeedStat L4670-4714); src/battle_stat_change.c
#   (IsIntimidateBlocked L676-690); src/data/pokemon/form_change_tables.h (Castform
#   weather table L667-672); include/constants/battle.h (SIDE_STATUS_SCREEN_ANY,
#   B_WEATHER_ICY_ANY); src/data/abilities.h (all 6 ability data entries).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_liquid_ooze()
	_test_section_3_forecast()
	_test_section_4_screen_cleaner()
	_test_section_5_pressure_unit()
	_test_section_6_pressure_full_battle()
	_test_section_7_quick_feet()
	_test_section_8_guard_dog_intimidate()
	_test_section_9_guard_dog_forced_switch()
	_test_section_10_mold_breaker_and_neutralizing_gas()
	_test_section_11_negative_control()

	var total := _pass + _fail
	print("m17n10_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


# ── Helpers ───────────────────────────────────────────────────────────────────

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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [M18.5h-1/2] pinned neutral nature + zero IVs -- exact-value assertions predate both


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var screen_cleaner := _load_ability(251)
	_chk("S1.01 Screen Cleaner id=251, not breakable, not cant_be_suppressed",
			screen_cleaner.ability_id == 251 and not screen_cleaner.breakable
					and not screen_cleaner.cant_be_suppressed)

	var liquid_ooze := _load_ability(64)
	_chk("S1.02 Liquid Ooze id=64, not breakable (source-verified: no such flag exists)",
			liquid_ooze.ability_id == 64 and not liquid_ooze.breakable)

	var pressure := _load_ability(46)
	_chk("S1.03 Pressure id=46, not breakable", pressure.ability_id == 46 and not pressure.breakable)

	var quick_feet := _load_ability(95)
	_chk("S1.04 Quick Feet id=95, not breakable", quick_feet.ability_id == 95 and not quick_feet.breakable)

	var guard_dog := _load_ability(275)
	_chk("S1.05 Guard Dog id=275, IS breakable (covers BOTH halves — source-verified)",
			guard_dog.ability_id == 275 and guard_dog.breakable == true)

	var forecast := _load_ability(59)
	_chk("S1.06 Forecast id=59, cant_be_copied AND cant_be_traced, not breakable",
			forecast.ability_id == 59 and forecast.cant_be_copied and forecast.cant_be_traced
					and not forecast.breakable)


# ── Section 2: Liquid Ooze — re-verified (already implemented pre-crash) ────

func _test_section_2_liquid_ooze() -> void:
	var liquid_ooze := _load_ability(64)
	var drained := _make_mon("LODrained", [TypeChart.TYPE_NORMAL])
	drained.ability = liquid_ooze
	_chk("S2.01 inverts_drain true for a Liquid Ooze holder",
			AbilityManager.inverts_drain(drained))
	var plain := _make_mon("LOPlain", [TypeChart.TYPE_NORMAL])
	_chk("S2.02 inverts_drain false for a plain Pokémon",
			not AbilityManager.inverts_drain(plain))

	# Full-battle: Absorb (Grass, 50% drain) against a Liquid Ooze holder damages
	# the ATTACKER by the same amount it would otherwise have healed, instead of
	# healing it.
	var absorb := _load_move(71)
	var atk_i := _make_mon("LOAtk1", [TypeChart.TYPE_NORMAL], 100, 100, 60, 100, 60, 100)
	atk_i.add_move(absorb)
	var def_i := _make_mon("LODef1", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 20)
	def_i.ability = liquid_ooze
	def_i.add_move(absorb)

	var bm_i := _make_bm()
	bm_i._force_roll = 100
	bm_i._force_crit = false
	atk_i.current_hp = 60  # below max so a normal drain-heal would visibly raise it
	var recoil_events_i := []
	var drain_heal_events_i := []
	bm_i.recoil_damage.connect(func(m, amt): recoil_events_i.append([m, amt]))
	bm_i.drain_heal.connect(func(m, amt): drain_heal_events_i.append([m, amt]))
	bm_i.start_battle(atk_i, def_i)

	_chk("S2.03 Liquid Ooze: the attacker takes recoil_damage from its own drain move",
			recoil_events_i.any(func(e): return e[0] == atk_i))
	_chk("S2.04 Liquid Ooze: the attacker never receives a normal drain_heal this turn",
			not drain_heal_events_i.any(func(e): return e[0] == atk_i))
	bm_i.queue_free()

	# Discriminator: the SAME Absorb against a plain defender heals the attacker
	# normally instead.
	var atk_ii := _make_mon("LOAtk2", [TypeChart.TYPE_NORMAL], 100, 100, 60, 100, 60, 100)
	atk_ii.add_move(absorb)
	atk_ii.current_hp = 60
	var def_ii := _make_mon("LODef2", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 20)
	def_ii.add_move(absorb)

	var bm_ii := _make_bm()
	bm_ii._force_roll = 100
	bm_ii._force_crit = false
	var recoil_events_ii := []
	var drain_heal_events_ii := []
	bm_ii.recoil_damage.connect(func(m, amt): recoil_events_ii.append([m, amt]))
	bm_ii.drain_heal.connect(func(m, amt): drain_heal_events_ii.append([m, amt]))
	bm_ii.start_battle(atk_ii, def_ii)

	_chk("S2.05 discriminator: a plain defender's drained HP heals the attacker " +
			"(no recoil_damage)", not recoil_events_ii.any(func(e): return e[0] == atk_ii))
	_chk("S2.06 discriminator: drain_heal DOES fire for the attacker against a plain " +
			"defender", drain_heal_events_ii.any(func(e): return e[0] == atk_ii))
	bm_ii.queue_free()


# ── Section 3: Forecast — re-verified (already implemented pre-crash) ───────

func _test_section_3_forecast() -> void:
	var forecast := _load_ability(59)

	_chk("S3.01 forecast_type: Normal (no weather)",
			AbilityManager.forecast_type(_forecast_mon(forecast), false, DamageCalculator.WEATHER_NONE)
					== TypeChart.TYPE_NORMAL)
	_chk("S3.02 forecast_type: Fire in Sun",
			AbilityManager.forecast_type(_forecast_mon(forecast), false, DamageCalculator.WEATHER_SUN)
					== TypeChart.TYPE_FIRE)
	_chk("S3.03 forecast_type: Water in Rain",
			AbilityManager.forecast_type(_forecast_mon(forecast), false, DamageCalculator.WEATHER_RAIN)
					== TypeChart.TYPE_WATER)
	_chk("S3.04 forecast_type: Ice in Hail",
			AbilityManager.forecast_type(_forecast_mon(forecast), false, DamageCalculator.WEATHER_HAIL)
					== TypeChart.TYPE_ICE)
	_chk("S3.05 forecast_type: TYPE_NONE for a non-Forecast holder",
			AbilityManager.forecast_type(_make_mon("NotForecast", [TypeChart.TYPE_NORMAL]), false,
					DamageCalculator.WEATHER_SUN) == TypeChart.TYPE_NONE)

	# Full-battle: switching in under active Sun immediately sets the Forecast
	# holder's type to Fire.
	var tackle := _load_move(33)
	var holder_i := _forecast_mon(forecast)
	holder_i.add_move(tackle)
	var opp_i := _make_mon("ForecastOpp1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	opp_i.add_move(tackle)

	var bm_i := _make_bm()
	bm_i.weather = DamageCalculator.WEATHER_SUN
	bm_i.weather_duration = 10
	var type_events_i := []
	bm_i.type_changed.connect(func(m, t): type_events_i.append([m, t]))
	bm_i.start_battle(holder_i, opp_i)

	_chk("S3.06 Forecast holder's type changes to Fire on switch-in under active Sun",
			type_events_i.any(func(e): return e[0] == holder_i and e[1] == TypeChart.TYPE_FIRE))
	bm_i.queue_free()

	# Weather changing mid-battle (via the _notify_weather_changed hook) reverts a
	# Forecast holder back to Normal once Sun expires.
	var holder_ii := _forecast_mon(forecast)
	holder_ii.add_move(tackle)
	var opp_ii := _make_mon("ForecastOpp2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	opp_ii.add_move(tackle)

	var bm_ii := _make_bm()
	bm_ii.weather = DamageCalculator.WEATHER_SUN
	bm_ii.weather_duration = 1  # expires at end of turn 1
	var type_events_ii := []
	bm_ii.type_changed.connect(func(m, t): type_events_ii.append([m, t]))
	bm_ii.weather_expired.connect(func(w): pass)
	bm_ii.start_battle(holder_ii, opp_ii)

	_chk("S3.07 Forecast holder's type reverts to Normal once Sun naturally expires",
			type_events_ii.any(func(e): return e[0] == holder_ii and e[1] == TypeChart.TYPE_NORMAL))
	bm_ii.queue_free()


func _forecast_mon(forecast: AbilityData) -> BattlePokemon:
	var m := _make_mon("Castform", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	m.ability = forecast
	return m


# ── Section 4: Screen Cleaner — full-battle (both-sides clear) ──────────────

func _test_section_4_screen_cleaner() -> void:
	var screen_cleaner := _load_ability(251)
	var tackle := _load_move(33)

	var holder_i := _make_mon("SCHolder1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	holder_i.ability = screen_cleaner
	holder_i.add_move(tackle)
	var opp_i := _make_mon("SCOpp1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp_i.add_move(tackle)

	var bm_i := _make_bm()
	bm_i._side_conditions[0]["reflect_turns"] = 5
	bm_i._side_conditions[1]["light_screen_turns"] = 5
	var broken_events_i := []
	bm_i.screens_broken.connect(func(side): broken_events_i.append(side))
	bm_i.start_battle(holder_i, opp_i)

	_chk("S4.01 Screen Cleaner clears the HOLDER's own side's Reflect on switch-in",
			broken_events_i.has(0))
	_chk("S4.02 Screen Cleaner ALSO clears the OPPONENT's side's Light Screen",
			broken_events_i.has(1))
	bm_i.queue_free()

	# Discriminator: a plain Pokémon switching in over the same screens clears
	# neither side.
	var holder_ii := _make_mon("SCPlain1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	holder_ii.add_move(tackle)
	var opp_ii := _make_mon("SCOpp2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp_ii.add_move(tackle)

	var bm_ii := _make_bm()
	bm_ii._side_conditions[0]["reflect_turns"] = 5
	bm_ii._side_conditions[1]["light_screen_turns"] = 5
	var broken_events_ii := []
	bm_ii.screens_broken.connect(func(side): broken_events_ii.append(side))
	bm_ii.start_battle(holder_ii, opp_ii)

	_chk("S4.03 discriminator: a plain Pokémon's switch-in clears no screens at all",
			broken_events_ii.is_empty())
	bm_ii.queue_free()


# ── Section 5: Pressure — direct unit tests ──────────────────────────────────

func _test_section_5_pressure_unit() -> void:
	var pressure := _load_ability(46)
	var tackle := _load_move(33)  # TARGET_SELECTED, single-target
	var magnitude := _load_move(222)  # is_spread = true

	var pressure_mon := _make_mon("PressureMon1", [TypeChart.TYPE_NORMAL])
	pressure_mon.ability = pressure
	var plain_mon := _make_mon("PlainMon1", [TypeChart.TYPE_NORMAL])
	var attacker := _make_mon("PressureAtk", [TypeChart.TYPE_NORMAL])

	_chk("S5.01 single-target move vs a Pressure-holding defender costs 2 PP (1+1)",
			AbilityManager.pressure_pp_cost(tackle, attacker, pressure_mon, 0, [attacker, pressure_mon], 1) == 2)
	_chk("S5.02 single-target move vs a plain defender costs 1 PP (discriminator)",
			AbilityManager.pressure_pp_cost(tackle, attacker, plain_mon, 0, [attacker, plain_mon], 1) == 1)
	_chk("S5.03 a self-targeting move (defender == attacker) never counts the " +
			"attacker's own Pressure",
			AbilityManager.pressure_pp_cost(tackle, attacker, attacker, 0, [attacker], 1) == 1)

	# Doubles-spread edge case: a spread move vs TWO Pressure holders costs 3 PP
	# (1 base + 2), not 2.
	var pressure_mon_b := _make_mon("PressureMon2", [TypeChart.TYPE_NORMAL])
	pressure_mon_b.ability = pressure
	var ally := _make_mon("PressureAlly", [TypeChart.TYPE_NORMAL])
	var combatants_doubles: Array = [attacker, ally, pressure_mon, pressure_mon_b]
	_chk("S5.04 spread move vs TWO Pressure holders costs 3 PP (1 base + 2) — the " +
			"doubles-spread edge case",
			AbilityManager.pressure_pp_cost(magnitude, attacker, pressure_mon, 0, combatants_doubles, 2) == 3)

	var combatants_one: Array = [attacker, ally, pressure_mon, plain_mon]
	_chk("S5.05 spread move vs ONE Pressure holder + one plain opponent costs 2 PP " +
			"(1 base + 1)",
			AbilityManager.pressure_pp_cost(magnitude, attacker, pressure_mon, 0, combatants_one, 2) == 2)

	var combatants_none: Array = [attacker, ally, plain_mon, _make_mon("PlainMon2", [TypeChart.TYPE_NORMAL])]
	_chk("S5.06 spread move vs zero Pressure holders costs 1 PP (discriminator)",
			AbilityManager.pressure_pp_cost(magnitude, attacker, plain_mon, 0, combatants_none, 2) == 1)

	# TARGET_OPPONENTS_FIELD hazards never draw extra PP, even vs a Pressure holder.
	var hazard_move := MoveData.new()
	hazard_move.move_name = "TestHazard"
	hazard_move.target = MoveData.TARGET_OPPONENTS_FIELD
	_chk("S5.07 a TARGET_OPPONENTS_FIELD hazard move never costs extra PP for an " +
			"opposing Pressure holder",
			AbilityManager.pressure_pp_cost(hazard_move, attacker, pressure_mon, 0, [attacker, pressure_mon], 1) == 1)


# ── Section 6: Pressure — full-battle integration ────────────────────────────

func _test_section_6_pressure_full_battle() -> void:
	var pressure := _load_ability(46)
	var tackle := _load_move(33)

	# Attacker faints from the Pressure holder's retaliation right after using
	# Tackle exactly once — freezes current_pp permanently, safe to read post-battle
	# (the same reasoning [M17n-9]'s Magic-Bounce-vs-Magic-Bounce KO'd-attacker
	# section already established).
	var atk_i := _make_mon("PPAtk1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 200)
	atk_i.current_hp = 1
	atk_i.add_move(tackle)
	var def_i := _make_mon("PPDef1", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 20)
	def_i.ability = pressure
	def_i.add_move(tackle)

	var bm_i := _make_bm()
	bm_i._force_hit = true
	bm_i.start_battle(atk_i, def_i)

	_chk("S6.01 Tackle costs 2 PP against a Pressure-holding defender in a real battle " +
			"(35 starting PP - 2 = 33)", atk_i.current_pp[0] == 33)
	bm_i.queue_free()

	# Discriminator: the same setup against a plain defender costs only 1 PP.
	var atk_ii := _make_mon("PPAtk2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 200)
	atk_ii.current_hp = 1
	atk_ii.add_move(tackle)
	var def_ii := _make_mon("PPDef2", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 20)
	def_ii.add_move(tackle)

	var bm_ii := _make_bm()
	bm_ii._force_hit = true
	bm_ii.start_battle(atk_ii, def_ii)

	_chk("S6.02 discriminator: Tackle costs only 1 PP against a plain defender " +
			"(35 - 1 = 34)", atk_ii.current_pp[0] == 34)
	bm_ii.queue_free()

	# Doubles-spread edge case in a real battle: Magnitude vs two Pressure holders
	# costs 3 PP.
	var magnitude := _load_move(222)
	var atk_iii := _make_mon("PPAtk3", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 200)
	atk_iii.current_hp = 1
	atk_iii.add_move(magnitude)
	var ally_iii := _make_mon("PPAlly3", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	ally_iii.add_move(tackle)
	var opp0_iii := _make_mon("PPOpp3a", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 60)
	opp0_iii.ability = pressure
	opp0_iii.add_move(tackle)
	var opp1_iii := _make_mon("PPOpp3b", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 60)
	opp1_iii.ability = pressure
	opp1_iii.add_move(tackle)

	var bm_iii := _make_bm()
	bm_iii._force_hit = true
	bm_iii.start_battle_doubles(_doubles_party(atk_iii, ally_iii), _doubles_party(opp0_iii, opp1_iii))

	_chk("S6.03 Magnitude (spread) vs two Pressure holders in doubles costs 3 PP " +
			"(30 starting PP - 3 = 27)", atk_iii.current_pp[0] == 27)
	bm_iii.queue_free()


# ── Section 7: Quick Feet ─────────────────────────────────────────────────────

func _test_section_7_quick_feet() -> void:
	var quick_feet := _load_ability(95)

	var para_qf := _make_mon("QFPara", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	para_qf.ability = quick_feet
	para_qf.status = BattlePokemon.STATUS_PARALYSIS
	var base_speed_qf: int = StatusManager.effective_speed(
			_make_mon("QFBase", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100))
	_chk("S7.01 a paralyzed Quick Feet holder's speed is ×1.5 the base (150/100), " +
			"NOT ×1.5×0.5", StatusManager.effective_speed(para_qf) == base_speed_qf * 150 / 100)

	var para_plain := _make_mon("QFParaPlain", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	para_plain.status = BattlePokemon.STATUS_PARALYSIS
	_chk("S7.02 discriminator: a paralyzed PLAIN Pokémon's speed is halved as normal",
			StatusManager.effective_speed(para_plain) == base_speed_qf / 2)

	# Any major status (not just paralysis) triggers the ×1.5 boost.
	var poison_qf := _make_mon("QFPoison", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	poison_qf.ability = quick_feet
	poison_qf.status = BattlePokemon.STATUS_POISON
	_chk("S7.03 a POISONED Quick Feet holder also gets the ×1.5 boost (not " +
			"paralysis-specific)", StatusManager.effective_speed(poison_qf) == base_speed_qf * 150 / 100)

	# No status at all: no boost.
	var healthy_qf := _make_mon("QFHealthy", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	healthy_qf.ability = quick_feet
	_chk("S7.04 a Quick Feet holder with NO status gets no boost at all",
			StatusManager.effective_speed(healthy_qf) == base_speed_qf)

	# Full-battle turn-order confirmation: a Quick Feet holder that would normally
	# be SLOWER than its opponent now moves FIRST because ×1.5 overtakes the
	# opponent's raw speed. Uses POISON, not paralysis — paralysis carries its own
	# independent 25% full-para chance to skip the turn entirely with no test-level
	# override available in this codebase, which would make this turn-order
	# assertion intermittently (and misleadingly) fail regardless of Quick Feet's
	# own correctness; poison still triggers the SAME unconditional ×1.5 boost
	# (confirmed in S7.03 above) with no such RNG risk.
	var tackle := _load_move(33)
	var qf_holder := _make_mon("QFTurnOrder", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	qf_holder.ability = quick_feet
	qf_holder.status = BattlePokemon.STATUS_POISON
	qf_holder.add_move(tackle)
	var opp := _make_mon("QFTurnOrderOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 120)
	opp.add_move(tackle)
	# Raw speed: 100 vs 120 (opp faster). Poisoned Quick Feet: 100*1.5=150 > 120.

	var bm := _make_bm()
	bm._force_hit = true
	var move_events := []
	bm.move_executed.connect(func(a, d, m, dmg): move_events.append(a))
	bm.start_battle(qf_holder, opp)

	_chk("S7.05 the poisoned Quick Feet holder (raw 100 spd) moves BEFORE its " +
			"raw-faster (120 spd) opponent, thanks to the ×1.5 boost",
			not move_events.is_empty() and move_events[0] == qf_holder)
	bm.queue_free()


# ── Section 8: Guard Dog — Intimidate reversal ───────────────────────────────

func _test_section_8_guard_dog_intimidate() -> void:
	var guard_dog := _load_ability(275)
	var intimidate := _load_ability(22)
	var mold_breaker := _load_ability(104)

	var gd_mon := _make_mon("GDIntim1", [TypeChart.TYPE_NORMAL])
	gd_mon.ability = guard_dog
	var intim_mon := _make_mon("GDIntimAtk1", [TypeChart.TYPE_NORMAL])
	intim_mon.ability = intimidate

	var result := AbilityManager.try_switch_in(intim_mon, gd_mon, null, false)
	_chk("S8.01 try_switch_in: Guard Dog reverses Intimidate into a +1 Attack raise",
			result["opponent_guard_dog_change"] == 1)
	_chk("S8.02 try_switch_in: the normal -1 atk_change never applies when Guard Dog " +
			"intercepts", result["atk_change"] == 0)

	# Gate: if Attack is already at the -6 floor, Guard Dog does not intercept at all
	# (the incoming drop would be a no-op anyway).
	var gd_floored := _make_mon("GDIntimFloored", [TypeChart.TYPE_NORMAL])
	gd_floored.ability = guard_dog
	gd_floored.stat_stages[BattlePokemon.STAGE_ATK] = -6
	var result_floored := AbilityManager.try_switch_in(intim_mon, gd_floored, null, false)
	_chk("S8.03 Guard Dog does NOT intercept when Attack is already at -6 " +
			"(the no-op gate)", result_floored["opponent_guard_dog_change"] == 0)

	# NOT Mold-Breaker-aware, and not independently dynamically testable: traced
	# moldBreakerActive's own source set-site (battle_util.c L9799: `if
	# (gCurrentMove != MOVE_NONE) moldBreakerActive = ...; else moldBreakerActive =
	# FALSE;`) and confirmed it's FALSE whenever no move is currently resolving — a
	# switch-in ability trigger structurally never has a "current move," so Guard
	# Dog's `.breakable=true` flag does not apply to this half at all (it only
	# matters for `blocks_forced_switch`, tested in Section 9). This can't be probed
	# with an actual Mold-Breaker-holding switch-in mon the way Section 9's own
	# Mold-Breaker test works, since a single mon can't simultaneously hold
	# Intimidate AND Mold Breaker to even trigger this interaction — confirmed at the
	# source-citation level above (`try_switch_in`'s own doc comment) rather than via
	# a mon-configuration scenario. S8.01/S8.02 above already confirm the reversal
	# fires via `try_switch_in`'s real (attacker-less) call to
	# `effective_ability_id` — there is nothing further to probe dynamically.

	# Full-battle: Intimidate switch-in vs a Guard Dog holder raises the HOLDER's
	# own Attack, never lowers it.
	var tackle := _load_move(33)
	var intim_holder := _make_mon("GDIntimBattleAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	intim_holder.ability = intimidate
	intim_holder.add_move(tackle)
	var gd_holder := _make_mon("GDIntimBattleDef", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	gd_holder.ability = guard_dog
	gd_holder.add_move(tackle)

	var bm := _make_bm()
	var stat_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle(intim_holder, gd_holder)

	_chk("S8.04 full battle: the Guard Dog holder's Attack RISES (+1) from an " +
			"opposing Intimidate switch-in, never drops",
			stat_events.any(func(e): return e[0] == gd_holder and e[1] == BattlePokemon.STAGE_ATK and e[2] == 1)
					and not stat_events.any(func(e): return e[0] == gd_holder and e[2] < 0))
	bm.queue_free()

	# Discriminator: the same Intimidate switch-in against a plain defender lowers
	# its Attack as normal.
	var intim_holder2 := _make_mon("GDIntimBattleAtk2", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	intim_holder2.ability = intimidate
	intim_holder2.add_move(tackle)
	var plain_def2 := _make_mon("GDPlainDef2", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	plain_def2.add_move(tackle)

	var bm2 := _make_bm()
	var stat_events2 := []
	bm2.stat_stage_changed.connect(func(t, s, a): stat_events2.append([t, s, a]))
	bm2.start_battle(intim_holder2, plain_def2)

	_chk("S8.05 discriminator: a plain defender's Attack DROPS (-1) from Intimidate " +
			"as normal", stat_events2.any(
					func(e): return e[0] == plain_def2 and e[1] == BattlePokemon.STAGE_ATK and e[2] == -1))
	bm2.queue_free()


# ── Section 9: Guard Dog — forced-switch block (Roar) ────────────────────────

func _test_section_9_guard_dog_forced_switch() -> void:
	var guard_dog := _load_ability(275)
	var mold_breaker := _load_ability(104)

	var gd_defender := _make_mon("GDRoarDef1", [TypeChart.TYPE_NORMAL])
	gd_defender.ability = guard_dog
	var plain_attacker := _make_mon("GDRoarAtk1", [TypeChart.TYPE_NORMAL])
	_chk("S9.01 blocks_forced_switch true for a Guard Dog defender vs a plain attacker",
			AbilityManager.blocks_forced_switch(gd_defender, plain_attacker))

	var mb_attacker := _make_mon("GDRoarAtkMB", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker
	_chk("S9.02 blocks_forced_switch false when the attacker has Mold Breaker " +
			"(Guard Dog IS breakable)", not AbilityManager.blocks_forced_switch(gd_defender, mb_attacker))

	var plain_defender := _make_mon("GDRoarDef2", [TypeChart.TYPE_NORMAL])
	_chk("S9.03 blocks_forced_switch false for a plain (non-Guard-Dog) defender",
			not AbilityManager.blocks_forced_switch(plain_defender, plain_attacker))

	# Full-battle: Roar against a Guard Dog holder never forces a switch.
	var roar := _load_move(46)
	var roar_attacker := _make_mon("GDRoarBattleAtk1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	roar_attacker.add_move(roar)
	var gd_holder := _make_mon("GDRoarBattleDef1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	gd_holder.ability = guard_dog
	gd_holder.add_move(roar)

	var gd_party := BattleParty.new()
	var gd_bench := _make_mon("GDRoarBench1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	gd_party.members = [gd_holder, gd_bench]

	var bm := _make_bm()
	var forced_switch_events := []
	var failed_events := []
	bm.forced_switch.connect(func(o, n): forced_switch_events.append([o, n]))
	bm.move_effect_failed.connect(func(t, r): failed_events.append([t, r]))
	bm.start_battle_with_parties(BattleParty.single(roar_attacker), gd_party)

	_chk("S9.04 Roar against a Guard Dog holder never fires forced_switch",
			not forced_switch_events.any(func(e): return e[0] == gd_holder))
	_chk("S9.05 the move fails specifically as guard_dog_blocks_switch",
			failed_events.any(func(e): return e[1] == "guard_dog_blocks_switch"))
	bm.queue_free()

	# Discriminator: the same Roar against a plain defender WITH a valid bench
	# target DOES force the switch.
	var roar_attacker2 := _make_mon("GDRoarBattleAtk2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	roar_attacker2.add_move(roar)
	var plain_holder2 := _make_mon("GDRoarBattleDef2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	plain_holder2.add_move(roar)
	var plain_bench2 := _make_mon("GDRoarBench2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	var plain_party2 := BattleParty.new()
	plain_party2.members = [plain_holder2, plain_bench2]

	var bm2 := _make_bm()
	var forced_switch_events2 := []
	bm2.forced_switch.connect(func(o, n): forced_switch_events2.append([o, n]))
	bm2.start_battle_with_parties(BattleParty.single(roar_attacker2), plain_party2)

	_chk("S9.06 discriminator: Roar against a plain defender DOES force the switch",
			forced_switch_events2.any(func(e): return e[0] == plain_holder2))
	bm2.queue_free()


# ── Section 10: Mold Breaker / Neutralizing Gas suppression matrix ──────────

func _test_section_10_mold_breaker_and_neutralizing_gas() -> void:
	# Screen Cleaner, Liquid Ooze, Pressure, Quick Feet are all suppressible by
	# Neutralizing Gas (none carry cant_be_suppressed) — one confirming check each.
	var screen_cleaner := _load_ability(251)
	var sc_mon := _make_mon("NGScreenCleaner", [TypeChart.TYPE_NORMAL])
	sc_mon.ability = screen_cleaner
	_chk("S10.01 Screen Cleaner suppressed by Neutralizing Gas",
			AbilityManager.effective_ability_id(sc_mon, true) != AbilityManager.ABILITY_SCREEN_CLEANER)

	var liquid_ooze := _load_ability(64)
	var lo_mon := _make_mon("NGLiquidOoze", [TypeChart.TYPE_NORMAL])
	lo_mon.ability = liquid_ooze
	_chk("S10.02 Liquid Ooze suppressed by Neutralizing Gas: inverts_drain false",
			not AbilityManager.inverts_drain(lo_mon, true))

	var pressure := _load_ability(46)
	var pr_mon := _make_mon("NGPressure", [TypeChart.TYPE_NORMAL])
	pr_mon.ability = pressure
	var attacker := _make_mon("NGPressureAtk", [TypeChart.TYPE_NORMAL])
	var tackle := _load_move(33)
	_chk("S10.03 Pressure suppressed by Neutralizing Gas: no extra PP cost",
			AbilityManager.pressure_pp_cost(tackle, attacker, pr_mon, 0, [attacker, pr_mon], 1, true) == 1)

	var quick_feet := _load_ability(95)
	var qf_mon := _make_mon("NGQuickFeet", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	qf_mon.ability = quick_feet
	qf_mon.status = BattlePokemon.STATUS_PARALYSIS
	var base_ng: int = StatusManager.effective_speed(
			_make_mon("NGQFBase", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100))
	_chk("S10.04 Quick Feet suppressed by Neutralizing Gas: paralysis halves speed as normal",
			StatusManager.effective_speed(qf_mon, DamageCalculator.WEATHER_NONE, true) == base_ng / 2)

	# Guard Dog — both halves.
	var guard_dog := _load_ability(275)
	var gd_mon := _make_mon("NGGuardDog", [TypeChart.TYPE_NORMAL])
	gd_mon.ability = guard_dog
	var intim_mon := _make_mon("NGIntimAtk", [TypeChart.TYPE_NORMAL])
	intim_mon.ability = _load_ability(22)
	var result_ng := AbilityManager.try_switch_in(intim_mon, gd_mon, null, true)
	_chk("S10.05 Guard Dog's Intimidate-reversal half suppressed by Neutralizing Gas",
			result_ng["opponent_guard_dog_change"] == 0)
	_chk("S10.06 Guard Dog's forced-switch-block half suppressed by Neutralizing Gas",
			not AbilityManager.blocks_forced_switch(gd_mon, attacker, true))

	# Forecast.
	var forecast := _load_ability(59)
	var fc_mon := _make_mon("NGForecast", [TypeChart.TYPE_NORMAL])
	fc_mon.ability = forecast
	_chk("S10.07 Forecast suppressed by Neutralizing Gas: forecast_type returns NONE",
			AbilityManager.forecast_type(fc_mon, true, DamageCalculator.WEATHER_SUN) == TypeChart.TYPE_NONE)


# ── Section 11: Negative control ─────────────────────────────────────────────

func _test_section_11_negative_control() -> void:
	var plain_atk := _make_mon("NegCtrlAtk10", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	plain_atk.current_hp = 1
	plain_atk.add_move(_load_move(33))
	var plain_def := _make_mon("NegCtrlDef10", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	plain_def.add_move(_load_move(33))

	var bm := _make_bm()
	bm._force_hit = true
	var recoil_events := []
	bm.recoil_damage.connect(func(m, amt): recoil_events.append(m))
	bm.start_battle(plain_atk, plain_def)

	_chk("S11.01 two plain Pokémon: Tackle costs exactly 1 PP",
			plain_atk.current_pp[0] == 34)
	_chk("S11.02 two plain Pokémon: no Liquid-Ooze-style recoil ever fires",
			recoil_events.is_empty())
	bm.queue_free()

	_chk("S11.03 forecast_type false for a plain Pokémon with no ability at all",
			AbilityManager.forecast_type(_make_mon("NegCtrlPlain1", [TypeChart.TYPE_NORMAL]), false,
					DamageCalculator.WEATHER_SUN) == TypeChart.TYPE_NONE)
	_chk("S11.04 blocks_forced_switch false for a plain Pokémon",
			not AbilityManager.blocks_forced_switch(
					_make_mon("NegCtrlPlain2", [TypeChart.TYPE_NORMAL]),
					_make_mon("NegCtrlPlain3", [TypeChart.TYPE_NORMAL])))
