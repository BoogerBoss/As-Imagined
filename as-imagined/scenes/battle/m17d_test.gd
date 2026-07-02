extends Node

# M17d test suite — Weather-setter completions + Primal trio + multi-part abilities
# deferred from M17c.
#
# Scope: the 5 abilities locked in docs/decisions.md [M17d]:
#   Solar Power (damage-pipeline half in attack_modifier_uq412 + end-of-turn
#     self-damage half in try_end_of_turn)
#   Poison Heal (inverts StatusManager.end_of_turn_damage)
#   Primordial Sea, Desolate Land (plain switch-in weather setters, get_switch_in_weather)
#   Delta Stream (new WEATHER_STRONG_WINDS value + Flying-type-weakness cancellation
#     wired into DamageCalculator.calculate's type-effectiveness pipeline)
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state, for anything observed through a full battle.
#   - Array-wrapper for any lambda that needs to report a result back to the enclosing
#     test function (GDScript captures scalars by value, not reference).
#   - Type immunity precedes ability logic: every damage-calc scenario below is checked
#     against TypeChart first to confirm a genuinely-connecting (nonzero) hit — Delta
#     Stream's Flying-type-weakness tests specifically use Electric/Rock/Grass-type
#     moves against Flying-type defenders, all confirmed super-effective (2.0x/4.0x),
#     never an immunity.
#
# Ground truth: pokeemerald_expansion src/battle_util.c, src/battle_end_turn.c.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_solar_power_damage_half()
	_test_section_3_solar_power_end_of_turn_half()
	_test_section_4_poison_heal()
	_test_section_5_primal_trio_weather_setters()
	_test_section_6_delta_stream_type_effectiveness()

	var total := _pass + _fail
	print("m17d_test: %d/%d passed" % [_pass, total])
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


func _make_move(move_type: int, category: int, power: int = 40, accuracy: int = 100,
		makes_contact: bool = false, crit_stage: int = 0) -> MoveData:
	var m := MoveData.new()
	m.type = move_type
	m.category = category
	m.power = power
	m.accuracy = accuracy
	m.makes_contact = makes_contact
	m.critical_hit_stage = crit_stage
	return m


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var solar_power := _load_ability(94)
	_chk("S1.01 Solar Power id=94", solar_power.ability_id == 94)
	var poison_heal := _load_ability(90)
	_chk("S1.02 Poison Heal id=90", poison_heal.ability_id == 90)
	var primordial_sea := _load_ability(189)
	_chk("S1.03 Primordial Sea id=189", primordial_sea.ability_id == 189)
	var desolate_land := _load_ability(190)
	_chk("S1.04 Desolate Land id=190", desolate_land.ability_id == 190)
	var delta_stream := _load_ability(191)
	_chk("S1.05 Delta Stream id=191", delta_stream.ability_id == 191)


# ── Section 2: Solar Power — damage-pipeline half ────────────────────────────

func _test_section_2_solar_power_damage_half() -> void:
	# Neutral (1x) Normal-vs-Normal matchup, deliberately chosen to isolate Solar Power
	# from any type-immunity/resistance interference (CLAUDE.md's type-immunity pitfall).
	var spec_move := _make_move(TypeChart.TYPE_NORMAL, 1, 40)
	var phys_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var def := _make_mon("Def", 50, [TypeChart.TYPE_NORMAL])
	var plain_atk := _make_mon("PlainAtk", 50, [TypeChart.TYPE_NORMAL])
	var sp_atk := _make_mon("SolarPowerAtk", 50, [TypeChart.TYPE_NORMAL])
	sp_atk.ability = _load_ability(94)

	var sun_spec := DamageCalculator.calculate(
			sp_atk, def, spec_move, 100, false, DamageCalculator.WEATHER_SUN)
	var sun_spec_baseline := DamageCalculator.calculate(
			plain_atk, def, spec_move, 100, false, DamageCalculator.WEATHER_SUN)
	_chk("S2.01 Solar Power: Sp. Atk boosted in sun (special move)",
			sun_spec["damage"] > sun_spec_baseline["damage"])

	var no_sun_spec := DamageCalculator.calculate(
			sp_atk, def, spec_move, 100, false, DamageCalculator.WEATHER_NONE)
	var no_sun_baseline := DamageCalculator.calculate(
			plain_atk, def, spec_move, 100, false, DamageCalculator.WEATHER_NONE)
	_chk("S2.02 Solar Power: NOT boosted without sun",
			no_sun_spec["damage"] == no_sun_baseline["damage"])

	var sun_phys := DamageCalculator.calculate(
			sp_atk, def, phys_move, 100, false, DamageCalculator.WEATHER_SUN)
	var sun_phys_baseline := DamageCalculator.calculate(
			plain_atk, def, phys_move, 100, false, DamageCalculator.WEATHER_SUN)
	_chk("S2.03 Solar Power: physical moves NOT boosted (special-only)",
			sun_phys["damage"] == sun_phys_baseline["damage"])


# ── Section 3: Solar Power — end-of-turn self-damage half ────────────────────

func _test_section_3_solar_power_end_of_turn_half() -> void:
	var solar_power := _make_mon("SolarPowerMon", 50, [TypeChart.TYPE_NORMAL], 160)
	solar_power.ability = _load_ability(94)
	var r1: Dictionary = AbilityManager.try_end_of_turn(
			solar_power, null, null, DamageCalculator.WEATHER_SUN)
	_chk("S3.01 Solar Power: takes maxHP/8 self-damage in sun",
			r1["damage_amount"] == solar_power.max_hp / 8)

	var solar_power2 := _make_mon("SolarPowerMon2", 50, [TypeChart.TYPE_NORMAL], 160)
	solar_power2.ability = _load_ability(94)
	var r2: Dictionary = AbilityManager.try_end_of_turn(
			solar_power2, null, null, DamageCalculator.WEATHER_NONE)
	_chk("S3.02 Solar Power: no self-damage outside sun", r2["damage_amount"] == 0)

	# Negative: even at full HP, Solar Power's self-damage still applies (unlike the
	# heal abilities, source has no not-at-max-HP gate on this half).
	var solar_power3 := _make_mon("SolarPowerMon3", 50, [TypeChart.TYPE_NORMAL], 160)
	solar_power3.ability = _load_ability(94)
	var r3: Dictionary = AbilityManager.try_end_of_turn(
			solar_power3, null, null, DamageCalculator.WEATHER_SUN)
	_chk("S3.03 Solar Power: self-damage applies even at full HP", r3["damage_amount"] > 0)

	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL], 160)
	var r4: Dictionary = AbilityManager.try_end_of_turn(
			plain_mon, null, null, DamageCalculator.WEATHER_SUN)
	_chk("S3.04 No ability: no self-damage in sun", r4["damage_amount"] == 0)


# ── Section 4: Poison Heal ─────────────────────────────────────────────────────

func _test_section_4_poison_heal() -> void:
	# Regular poison: heals maxHP/8 instead of damaging.
	var ph_poison := _make_mon("PHPoison", 50, [TypeChart.TYPE_NORMAL], 160)
	ph_poison.ability = _load_ability(90)
	ph_poison.status = BattlePokemon.STATUS_POISON
	ph_poison.current_hp = 100
	var r1: int = StatusManager.end_of_turn_damage(ph_poison)
	_chk("S4.01 Poison Heal: poison heals maxHP/8 (negative return)",
			r1 == -(ph_poison.max_hp / 8))

	# Toxic: still a FLAT maxHP/8 heal, NOT scaled by the toxic counter — but the
	# counter itself still increments (source keeps ticking it even though the
	# ability heals instead of damaging).
	var ph_toxic := _make_mon("PHToxic", 50, [TypeChart.TYPE_NORMAL], 160)
	ph_toxic.ability = _load_ability(90)
	ph_toxic.status = BattlePokemon.STATUS_TOXIC
	ph_toxic.current_hp = 100
	ph_toxic.toxic_counter = 0
	var r2: int = StatusManager.end_of_turn_damage(ph_toxic)
	_chk("S4.02 Poison Heal: toxic heals a FLAT maxHP/8 (not counter-scaled)",
			r2 == -(ph_toxic.max_hp / 8))
	_chk("S4.03 Poison Heal: toxic counter still increments", ph_toxic.toxic_counter == 1)

	# Negative: already at max HP → no heal (0, not a negative amount).
	var ph_full := _make_mon("PHFull", 50, [TypeChart.TYPE_NORMAL], 160)
	ph_full.ability = _load_ability(90)
	ph_full.status = BattlePokemon.STATUS_POISON
	var r3: int = StatusManager.end_of_turn_damage(ph_full)
	_chk("S4.04 Poison Heal: no heal at full HP", r3 == 0)

	# Negative: Poison Heal does NOT affect burn (scope is poison/toxic only).
	var ph_burn := _make_mon("PHBurn", 50, [TypeChart.TYPE_NORMAL], 160)
	ph_burn.ability = _load_ability(90)
	ph_burn.status = BattlePokemon.STATUS_BURN
	var r4: int = StatusManager.end_of_turn_damage(ph_burn)
	_chk("S4.05 Poison Heal: burn still deals normal damage (positive)", r4 > 0)

	# Regression: no ability → poison/toxic still damage normally.
	var plain_poison := _make_mon("PlainPoison", 50, [TypeChart.TYPE_NORMAL], 160)
	plain_poison.status = BattlePokemon.STATUS_POISON
	var r5: int = StatusManager.end_of_turn_damage(plain_poison)
	_chk("S4.06 No ability: poison still damages (positive, regression)", r5 > 0)


# ── Section 5: Primordial Sea / Desolate Land — plain switch-in weather setters ──

func _test_section_5_primal_trio_weather_setters() -> void:
	# No item/species gate of any kind — a plain switch-in with the ability alone,
	# and no held_item at all, is sufficient (the Primal-Reversion-item gate is
	# deliberately dropped, per docs/decisions.md [M17d]).
	var primordial_sea := _make_mon("PrimordialSeaMon", 50, [TypeChart.TYPE_WATER])
	primordial_sea.ability = _load_ability(189)
	_chk("S5.01 Primordial Sea: sets Rain on switch-in, no item required",
			AbilityManager.get_switch_in_weather(primordial_sea) == DamageCalculator.WEATHER_RAIN)
	_chk("S5.02 Primordial Sea: held_item is null (no orb gate)",
			primordial_sea.held_item == null)

	var desolate_land := _make_mon("DesolateLandMon", 50, [TypeChart.TYPE_GROUND])
	desolate_land.ability = _load_ability(190)
	_chk("S5.03 Desolate Land: sets Sun on switch-in, no item required",
			AbilityManager.get_switch_in_weather(desolate_land) == DamageCalculator.WEATHER_SUN)

	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	_chk("S5.04 No ability: does NOT set weather",
			AbilityManager.get_switch_in_weather(plain_mon) == DamageCalculator.WEATHER_NONE)


# ── Section 6: Delta Stream — weather-setting + type-effectiveness wiring ────

func _test_section_6_delta_stream_type_effectiveness() -> void:
	var delta_stream := _make_mon("DeltaStreamMon", 50, [TypeChart.TYPE_DRAGON])
	delta_stream.ability = _load_ability(191)
	_chk("S6.01 Delta Stream: sets Strong Winds on switch-in",
			AbilityManager.get_switch_in_weather(delta_stream) == DamageCalculator.WEATHER_STRONG_WINDS)

	# Electric vs pure Flying: confirmed super-effective (2.0x, not an immunity — Flying
	# has no immunity to Electric, only a weakness) via TypeChart.TABLE directly before
	# writing this scenario, per CLAUDE.md's type-immunity-precedes-ability-logic rule.
	var electric_move := _make_move(TypeChart.TYPE_ELECTRIC, 1, 40)
	var atk := _make_mon("Atk", 50, [TypeChart.TYPE_NORMAL])
	var flying_def := _make_mon("FlyingDef", 50, [TypeChart.TYPE_FLYING])
	var baseline := DamageCalculator.calculate(
			atk, flying_def, electric_move, 100, false, DamageCalculator.WEATHER_NONE)
	_chk("S6.02 Baseline (no weather): Electric vs Flying is super-effective (2.0x)",
			baseline["effectiveness"] == 2.0)
	var strong_winds_result := DamageCalculator.calculate(
			atk, flying_def, electric_move, 100, false, DamageCalculator.WEATHER_STRONG_WINDS)
	_chk("S6.03 Delta Stream: Strong Winds weakens the hit to neutral (1.0x)",
			strong_winds_result["effectiveness"] == 1.0)
	_chk("S6.04 Delta Stream: actual damage is lower under Strong Winds",
			strong_winds_result["damage"] < baseline["damage"])

	# Dual-type Bug/Flying defender vs Rock (Rock vs Bug=2.0, Rock vs Flying=2.0,
	# combined baseline=4.0x — confirmed via TypeChart.TABLE, not assumed). Strong
	# Winds cancels ONLY the Flying component (per-type, matching source's exact
	# granularity), so the combined result should drop to 2.0x (Bug's 2.0x survives),
	# not all the way to 1.0x.
	var rock_move := _make_move(TypeChart.TYPE_ROCK, 0, 40)
	var bug_flying_def := _make_mon("BugFlyingDef", 50, [TypeChart.TYPE_BUG, TypeChart.TYPE_FLYING])
	var dual_baseline := DamageCalculator.calculate(
			atk, bug_flying_def, rock_move, 100, false, DamageCalculator.WEATHER_NONE)
	_chk("S6.05 Baseline: Rock vs Bug/Flying is 4x", dual_baseline["effectiveness"] == 4.0)
	var dual_strong_winds := DamageCalculator.calculate(
			atk, bug_flying_def, rock_move, 100, false, DamageCalculator.WEATHER_STRONG_WINDS)
	_chk("S6.06 Delta Stream: only the Flying component is weakened (4x → 2x, not 1x)",
			dual_strong_winds["effectiveness"] == 2.0)

	# Negative: Strong Winds does NOT weaken a super-effective hit against a
	# non-Flying defender (Grass vs Water is neutral — use a real super-effective
	# pairing instead: Water vs Fire is 2.0x, confirmed via TypeChart.TABLE).
	var water_move := _make_move(TypeChart.TYPE_WATER, 1, 40)
	var fire_def := _make_mon("FireDef", 50, [TypeChart.TYPE_FIRE])
	var non_flying_baseline := DamageCalculator.calculate(
			atk, fire_def, water_move, 100, false, DamageCalculator.WEATHER_NONE)
	var non_flying_strong_winds := DamageCalculator.calculate(
			atk, fire_def, water_move, 100, false, DamageCalculator.WEATHER_STRONG_WINDS)
	_chk("S6.07 Delta Stream: does NOT weaken hits against non-Flying defenders",
			non_flying_strong_winds["effectiveness"] == non_flying_baseline["effectiveness"])

	# Negative: Strong Winds does NOT touch a merely-neutral or resisted hit against
	# a Flying-type defender (only >=2.0x components are weakened).
	var normal_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var neutral_result := DamageCalculator.calculate(
			atk, flying_def, normal_move, 100, false, DamageCalculator.WEATHER_STRONG_WINDS)
	_chk("S6.08 Delta Stream: does NOT alter a neutral (1.0x) hit against Flying",
			neutral_result["effectiveness"] == 1.0)
