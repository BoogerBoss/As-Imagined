extends Node

# M17m test suite — Absorb-family abilities: Volt Absorb, Water Absorb, Sap Sipper,
# Flash Fire, Motor Drive, Well-Baked Body, Earth Eater, plus Dry Skin's previously
# deferred water-absorb heal (a free-rider, not a re-test of [M17c]'s existing work).
#
# Scope: docs/m17m_absorb_recon.md (pre-recon) + docs/decisions.md [M17m] (final list,
# Step 0 re-verified all seven new IDs against Section 13's exclusion sweep — none
# needed correction). All eight route through the SAME source dispatch,
# `CanAbilityAbsorbMove` (battle_util.c L2235-2313), that [M17l]'s Lightning Rod/Storm
# Drain already partially extended via `AbilityManager.absorbs_move_type` — but the
# on-absorb EFFECT is three genuinely different shapes, not one:
#   GROUP 1 (heal maxHP/4): Volt Absorb (Electric), Water Absorb (Water), Earth Eater
#     (Ground), Dry Skin's water half (Water — shares Water Absorb's literal case
#     label in source).
#   GROUP 2 (stat-stage boost, VARYING magnitude): Sap Sipper (Grass → Atk+1), Motor
#     Drive (Electric → Speed+1, NOT Sp.Atk despite the type overlap with Lightning
#     Rod), Well-Baked Body (Fire → Def **+2**, not +1 — the one two-stage entry in
#     this whole dispatch).
#   GROUP 3 (persistent flag, no immediate effect): Flash Fire (Fire) — sets
#     `BattlePokemon.flash_fire_active`; the actual payoff is a LATER Fire-type move
#     from the SAME holder getting a x1.5 power boost, handled entirely separately in
#     `attack_modifier_uq412` (battle_util.c L6817-6819).
#
# Cross-cutting design decision (docs/decisions.md [M17m]): `absorbs_move_type`'s
# return type was widened from a bare `int` (STAGE_* or -1) to a `Dictionary`
# (`{}` = not absorbed; `{"kind": "stat"/"heal"/"flag", ...}` otherwise) to express all
# three shapes through one function, matching source's single dispatch — this changed
# [M17l]'s existing direct unit tests (Section 2 of m17l_test.gd), updated in place.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state (ability_triggered/ability_healed/
#     stat_stage_changed connections, never reading final BattlePokemon state after
#     start_battle returns).
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing test function.
#   - Type immunity precedes ability logic: all scenarios use Normal-type combatants
#     except where the matching type itself is the mechanic under test.
#
# Ground truth: pokeemerald_expansion src/battle_util.c ::
#   CanAbilityAbsorbMove (L2235-2313), AbsorbedByDrainHpAbility (L2315-2326),
#   AbsorbedByStatIncreaseAbility (L2328-2340), AbsorbedByFlashFire (L2342-2355),
#   GetAttackStatModifier's ABILITY_FLASH_FIRE case (L6817-6819).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_group1_heal_unit()
	_test_section_3_group2_stat_unit()
	_test_section_4_group3_flag_unit()
	_test_section_5_mold_breaker_bypass()
	_test_section_6_neutralizing_gas_suppression()
	_test_section_7_volt_absorb_full_battle()
	_test_section_8_volt_absorb_full_hp_still_absorbs()
	_test_section_9_water_absorb_full_battle()
	_test_section_10_earth_eater_full_battle()
	_test_section_11_dry_skin_water_absorb_heal_full_battle()
	_test_section_12_sap_sipper_full_battle()
	_test_section_13_motor_drive_full_battle()
	_test_section_14_well_baked_body_full_battle()
	_test_section_15_flash_fire_absorb_full_battle()
	_test_section_16_flash_fire_boost_direct_calculate()
	_test_section_17_negative_case()

	var total := _pass + _fail
	print("m17m_test: %d/%d passed" % [_pass, total])
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


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var volt_absorb := _load_ability(10)
	_chk("S1.01 Volt Absorb id=10, breakable=true", volt_absorb.ability_id == 10 and volt_absorb.breakable)

	var water_absorb := _load_ability(11)
	_chk("S1.02 Water Absorb id=11, breakable=true", water_absorb.ability_id == 11 and water_absorb.breakable)

	var flash_fire := _load_ability(18)
	_chk("S1.03 Flash Fire id=18, breakable=true", flash_fire.ability_id == 18 and flash_fire.breakable)

	var motor_drive := _load_ability(78)
	_chk("S1.04 Motor Drive id=78, breakable=true", motor_drive.ability_id == 78 and motor_drive.breakable)

	var dry_skin := _load_ability(87)
	_chk("S1.05 Dry Skin id=87, breakable=true (unchanged from [M17c])",
			dry_skin.ability_id == 87 and dry_skin.breakable)

	var sap_sipper := _load_ability(157)
	_chk("S1.06 Sap Sipper id=157, breakable=true", sap_sipper.ability_id == 157 and sap_sipper.breakable)

	var well_baked_body := _load_ability(273)
	_chk("S1.07 Well-Baked Body id=273, breakable=true",
			well_baked_body.ability_id == 273 and well_baked_body.breakable)

	var earth_eater := _load_ability(297)
	_chk("S1.08 Earth Eater id=297, breakable=true", earth_eater.ability_id == 297 and earth_eater.breakable)


# ── Section 2: Group 1 (heal) — direct absorbs_move_type unit tests ─────────

func _test_section_2_group1_heal_unit() -> void:
	var volt_absorb := _load_ability(10)
	var water_absorb := _load_ability(11)
	var earth_eater := _load_ability(297)
	var dry_skin := _load_ability(87)

	var va_holder := _make_mon("VAHolder", [TypeChart.TYPE_NORMAL])
	va_holder.ability = volt_absorb
	_chk("S2.01 Volt Absorb: Electric hit → heal, fraction 4",
			AbilityManager.absorbs_move_type(va_holder, TypeChart.TYPE_ELECTRIC) \
					== {"kind": "heal", "fraction": 4})
	_chk("S2.02 Volt Absorb: Water hit → not absorbed",
			AbilityManager.absorbs_move_type(va_holder, TypeChart.TYPE_WATER).is_empty())

	var wa_holder := _make_mon("WAHolder", [TypeChart.TYPE_NORMAL])
	wa_holder.ability = water_absorb
	_chk("S2.03 Water Absorb: Water hit → heal, fraction 4",
			AbilityManager.absorbs_move_type(wa_holder, TypeChart.TYPE_WATER) \
					== {"kind": "heal", "fraction": 4})

	var ee_holder := _make_mon("EEHolder", [TypeChart.TYPE_NORMAL])
	ee_holder.ability = earth_eater
	_chk("S2.04 Earth Eater: Ground hit → heal, fraction 4",
			AbilityManager.absorbs_move_type(ee_holder, TypeChart.TYPE_GROUND) \
					== {"kind": "heal", "fraction": 4})

	var ds_holder := _make_mon("DSHolder", [TypeChart.TYPE_NORMAL])
	ds_holder.ability = dry_skin
	_chk("S2.05 Dry Skin: Water hit → heal, fraction 4 (the previously-deferred third of [M17c])",
			AbilityManager.absorbs_move_type(ds_holder, TypeChart.TYPE_WATER) \
					== {"kind": "heal", "fraction": 4})
	_chk("S2.06 Dry Skin: Fire hit → NOT absorbed by this function " +
			"(Fire-vulnerability is a separate, already-shipped defense_damage_modifier_uq412 path)",
			AbilityManager.absorbs_move_type(ds_holder, TypeChart.TYPE_FIRE).is_empty())


# ── Section 3: Group 2 (stat boost) — direct absorbs_move_type unit tests ───

func _test_section_3_group2_stat_unit() -> void:
	var sap_sipper := _load_ability(157)
	var motor_drive := _load_ability(78)
	var well_baked_body := _load_ability(273)

	var ss_holder := _make_mon("SSHolder", [TypeChart.TYPE_NORMAL])
	ss_holder.ability = sap_sipper
	_chk("S3.01 Sap Sipper: Grass hit → Atk +1",
			AbilityManager.absorbs_move_type(ss_holder, TypeChart.TYPE_GRASS) \
					== {"kind": "stat", "stat": BattlePokemon.STAGE_ATK, "amount": 1})

	var md_holder := _make_mon("MDHolder", [TypeChart.TYPE_NORMAL])
	md_holder.ability = motor_drive
	var md_result: Dictionary = AbilityManager.absorbs_move_type(md_holder, TypeChart.TYPE_ELECTRIC)
	_chk("S3.02 Motor Drive: Electric hit → Speed +1 (NOT Sp.Atk, despite the same " +
			"Electric type-match Lightning Rod uses)",
			md_result == {"kind": "stat", "stat": BattlePokemon.STAGE_SPEED, "amount": 1})
	_chk("S3.03 Motor Drive's stat is explicitly NOT Sp.Atk",
			md_result.get("stat", -1) != BattlePokemon.STAGE_SPATK)

	var wbb_holder := _make_mon("WBBHolder", [TypeChart.TYPE_NORMAL])
	wbb_holder.ability = well_baked_body
	var wbb_result: Dictionary = AbilityManager.absorbs_move_type(wbb_holder, TypeChart.TYPE_FIRE)
	_chk("S3.04 Well-Baked Body: Fire hit → Def +2 (NOT +1 — the highest-risk detail this tier)",
			wbb_result == {"kind": "stat", "stat": BattlePokemon.STAGE_DEF, "amount": 2})
	_chk("S3.05 Well-Baked Body's amount is explicitly NOT 1",
			wbb_result.get("amount", -1) != 1)


# ── Section 4: Group 3 (persistent flag) — direct unit tests ────────────────

func _test_section_4_group3_flag_unit() -> void:
	var flash_fire := _load_ability(18)
	var ember := _load_move(52)
	var water_gun := _load_move(55)

	var ff_holder := _make_mon("FFHolder", [TypeChart.TYPE_NORMAL])
	ff_holder.ability = flash_fire
	_chk("S4.01 Flash Fire: Fire hit → flag kind, no stat/heal payload",
			AbilityManager.absorbs_move_type(ff_holder, TypeChart.TYPE_FIRE) == {"kind": "flag"})
	_chk("S4.02 Flash Fire: Water hit → not absorbed",
			AbilityManager.absorbs_move_type(ff_holder, TypeChart.TYPE_WATER).is_empty())

	# attack_modifier_uq412: the delayed payoff — only applies with the flag active AND
	# a Fire-type move; a non-Fire move from the same flagged holder is unaffected.
	var neutral_attacker := _make_mon("FFAttacker", [TypeChart.TYPE_NORMAL])
	neutral_attacker.flash_fire_active = false
	_chk("S4.03 no flag active → ordinary x1.0 on a Fire move",
			AbilityManager.attack_modifier_uq412(neutral_attacker, ember) == 4096)

	var flagged_attacker := _make_mon("FFAttackerFlagged", [TypeChart.TYPE_NORMAL])
	flagged_attacker.ability = flash_fire
	flagged_attacker.flash_fire_active = true
	_chk("S4.04 flag active + Fire move → x1.5 (6144)",
			AbilityManager.attack_modifier_uq412(flagged_attacker, ember) == 6144)
	_chk("S4.05 flag active + NON-Fire move (Water Gun) → still x1.0, unaffected",
			AbilityManager.attack_modifier_uq412(flagged_attacker, water_gun) == 4096)


# ── Section 5: Mold Breaker bypass — one representative per group ───────────

func _test_section_5_mold_breaker_bypass() -> void:
	var mold_breaker := _load_ability(104)
	var volt_absorb := _load_ability(10)
	var sap_sipper := _load_ability(157)
	var flash_fire := _load_ability(18)

	var mb_attacker := _make_mon("MBAttacker5", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker

	var va_holder := _make_mon("VAHolder5", [TypeChart.TYPE_NORMAL])
	va_holder.ability = volt_absorb
	_chk("S5.01 Mold Breaker bypasses Volt Absorb's heal (Group 1)",
			AbilityManager.absorbs_move_type(va_holder, TypeChart.TYPE_ELECTRIC, false, mb_attacker).is_empty())

	var ss_holder := _make_mon("SSHolder5", [TypeChart.TYPE_NORMAL])
	ss_holder.ability = sap_sipper
	_chk("S5.02 Mold Breaker bypasses Sap Sipper's stat boost (Group 2)",
			AbilityManager.absorbs_move_type(ss_holder, TypeChart.TYPE_GRASS, false, mb_attacker).is_empty())

	var ff_holder := _make_mon("FFHolder5", [TypeChart.TYPE_NORMAL])
	ff_holder.ability = flash_fire
	_chk("S5.03 Mold Breaker bypasses Flash Fire's flag-set (Group 3)",
			AbilityManager.absorbs_move_type(ff_holder, TypeChart.TYPE_FIRE, false, mb_attacker).is_empty())


# ── Section 6: Neutralizing Gas suppression — one representative per group ──

func _test_section_6_neutralizing_gas_suppression() -> void:
	var volt_absorb := _load_ability(10)
	var motor_drive := _load_ability(78)
	var flash_fire := _load_ability(18)

	var va_holder := _make_mon("VAHolder6", [TypeChart.TYPE_NORMAL])
	va_holder.ability = volt_absorb
	_chk("S6.01 Neutralizing Gas suppresses Volt Absorb's heal (Group 1)",
			AbilityManager.absorbs_move_type(va_holder, TypeChart.TYPE_ELECTRIC, true).is_empty())

	var md_holder := _make_mon("MDHolder6", [TypeChart.TYPE_NORMAL])
	md_holder.ability = motor_drive
	_chk("S6.02 Neutralizing Gas suppresses Motor Drive's stat boost (Group 2)",
			AbilityManager.absorbs_move_type(md_holder, TypeChart.TYPE_ELECTRIC, true).is_empty())

	var ff_holder := _make_mon("FFHolder6", [TypeChart.TYPE_NORMAL])
	ff_holder.ability = flash_fire
	_chk("S6.03 Neutralizing Gas suppresses Flash Fire's flag-set (Group 3)",
			AbilityManager.absorbs_move_type(ff_holder, TypeChart.TYPE_FIRE, true).is_empty())


# ── Section 7: Volt Absorb — full-battle heal + damage-block ────────────────

func _test_section_7_volt_absorb_full_battle() -> void:
	var thunder_shock := _load_move(84)
	var volt_absorb := _load_ability(10)

	var attacker := _make_mon("BattleVAAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(thunder_shock)
	var va_holder := _make_mon("BattleVAHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	va_holder.ability = volt_absorb
	va_holder.add_move(thunder_shock)
	va_holder.current_hp = va_holder.max_hp - 50  # room to heal, not at max

	var move_executed_events := []
	var healed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.ability_healed.connect(func(p, amt): healed_events.push_back([p, amt]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(va_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == va_holder)
	_chk("S7.01 Volt Absorb absorbed the hit (0 damage)",
			not hit.is_empty() and hit[0][3] == 0)
	var heal := healed_events.filter(func(e): return e[0] == va_holder)
	_chk("S7.02 Volt Absorb healed exactly maxHP/4",
			not heal.is_empty() and heal[0][1] == va_holder.max_hp / 4)

	bm.queue_free()


# ── Section 8: Volt Absorb at full HP — absorb still happens, no heal ───────

func _test_section_8_volt_absorb_full_hp_still_absorbs() -> void:
	var thunder_shock := _load_move(84)
	var volt_absorb := _load_ability(10)

	var attacker := _make_mon("BattleVAAttackerFull", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	var va_holder := _make_mon("BattleVAHolderFull", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	va_holder.ability = volt_absorb
	# va_holder.current_hp already == max_hp from from_species — no damage taken yet.

	var result: Dictionary = DamageCalculator.calculate(attacker, va_holder, thunder_shock, 100, false)
	_chk("S8.01 direct calculate(): still 0 damage at full HP (absorbed regardless of heal outcome)",
			result["damage"] == 0)
	_chk("S8.02 absorb_result reports the heal kind even though no HP will actually be restored",
			result.get("absorb_result", {}) == {"kind": "heal", "fraction": 4})

	# Full-battle confirmation: no heal signal fires, and current_hp never exceeds max.
	attacker.add_move(thunder_shock)
	va_holder.add_move(thunder_shock)
	var healed_events := []
	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.ability_healed.connect(func(p, amt): healed_events.push_back([p, amt]))
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(va_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == va_holder)
	_chk("S8.03 full-battle: still 0 damage at full HP",
			not hit.is_empty() and hit[0][3] == 0)
	_chk("S8.04 full-battle: no heal signal fired for an already-full-HP holder",
			healed_events.filter(func(e): return e[0] == va_holder).is_empty())

	bm.queue_free()


# ── Section 9: Water Absorb — full-battle heal + damage-block ───────────────

func _test_section_9_water_absorb_full_battle() -> void:
	var water_gun := _load_move(55)
	var water_absorb := _load_ability(11)

	var attacker := _make_mon("BattleWAAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(water_gun)
	var wa_holder := _make_mon("BattleWAHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	wa_holder.ability = water_absorb
	wa_holder.add_move(water_gun)
	wa_holder.current_hp = wa_holder.max_hp - 50

	var move_executed_events := []
	var healed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.ability_healed.connect(func(p, amt): healed_events.push_back([p, amt]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(wa_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == wa_holder)
	_chk("S9.01 Water Absorb absorbed the hit (0 damage)",
			not hit.is_empty() and hit[0][3] == 0)
	var heal := healed_events.filter(func(e): return e[0] == wa_holder)
	_chk("S9.02 Water Absorb healed exactly maxHP/4",
			not heal.is_empty() and heal[0][1] == wa_holder.max_hp / 4)

	bm.queue_free()


# ── Section 10: Earth Eater — full-battle heal + damage-block ───────────────

func _test_section_10_earth_eater_full_battle() -> void:
	var earthquake := _load_move(89)
	var earth_eater := _load_ability(297)

	var attacker := _make_mon("BattleEEAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(earthquake)
	var ee_holder := _make_mon("BattleEEHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	ee_holder.ability = earth_eater
	ee_holder.add_move(earthquake)
	ee_holder.current_hp = ee_holder.max_hp - 50

	var move_executed_events := []
	var healed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.ability_healed.connect(func(p, amt): healed_events.push_back([p, amt]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(ee_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == ee_holder)
	_chk("S10.01 Earth Eater absorbed the hit (0 damage)",
			not hit.is_empty() and hit[0][3] == 0)
	var heal := healed_events.filter(func(e): return e[0] == ee_holder)
	_chk("S10.02 Earth Eater healed exactly maxHP/4",
			not heal.is_empty() and heal[0][1] == ee_holder.max_hp / 4)

	bm.queue_free()


# ── Section 11: Dry Skin's water-absorb heal — dedicated, separate from [M17c] ──
#
# [M17c] already tests Dry Skin's Fire-vulnerability (x1.25) and end-of-turn rain/sun
# tick (maxHP/8) in m17c_test.gd — NOT touched or duplicated here. This section is
# scoped ONLY to the new water-absorb-heal piece (maxHP/4, a DIFFERENT divisor).

func _test_section_11_dry_skin_water_absorb_heal_full_battle() -> void:
	var water_gun := _load_move(55)
	var dry_skin := _load_ability(87)

	var attacker := _make_mon("BattleDSAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(water_gun)
	var ds_holder := _make_mon("BattleDSHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	ds_holder.ability = dry_skin
	ds_holder.add_move(water_gun)
	ds_holder.current_hp = ds_holder.max_hp - 50

	var move_executed_events := []
	var healed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.ability_healed.connect(func(p, amt): healed_events.push_back([p, amt]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(ds_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == ds_holder)
	_chk("S11.01 Dry Skin absorbed the Water hit (0 damage) — distinct from its Fire " +
			"damage-INCREASE (which does not block anything)",
			not hit.is_empty() and hit[0][3] == 0)
	var heal := healed_events.filter(func(e): return e[0] == ds_holder)
	_chk("S11.02 Dry Skin's water-absorb heal is exactly maxHP/4 (NOT the end-of-turn /8 divisor)",
			not heal.is_empty() and heal[0][1] == ds_holder.max_hp / 4)
	_chk("S11.03 the healed amount does NOT match the /8 end-of-turn divisor " +
			"(would indicate the wrong branch fired)",
			heal.is_empty() or heal[0][1] != ds_holder.max_hp / 8)

	bm.queue_free()


# ── Section 12: Sap Sipper — full-battle Atk+1 ───────────────────────────────

func _test_section_12_sap_sipper_full_battle() -> void:
	var vine_whip := _load_move(22)
	var sap_sipper := _load_ability(157)

	var attacker := _make_mon("BattleSSAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(vine_whip)
	var ss_holder := _make_mon("BattleSSHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	ss_holder.ability = sap_sipper
	ss_holder.add_move(vine_whip)

	var move_executed_events := []
	var stat_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(ss_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == ss_holder)
	_chk("S12.01 Sap Sipper absorbed the Grass hit (0 damage)",
			not hit.is_empty() and hit[0][3] == 0)
	_chk("S12.02 Sap Sipper's holder gained Atk +1",
			stat_events.any(func(e): return e[0] == ss_holder and e[1] == BattlePokemon.STAGE_ATK and e[2] == 1))

	bm.queue_free()


# ── Section 13: Motor Drive — full-battle Speed+1, NOT Sp.Atk ────────────────

func _test_section_13_motor_drive_full_battle() -> void:
	var thunder_shock := _load_move(84)
	var motor_drive := _load_ability(78)

	var attacker := _make_mon("BattleMDAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(thunder_shock)
	var md_holder := _make_mon("BattleMDHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	md_holder.ability = motor_drive
	md_holder.add_move(thunder_shock)

	var move_executed_events := []
	var stat_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(md_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == md_holder)
	_chk("S13.01 Motor Drive absorbed the Electric hit (0 damage)",
			not hit.is_empty() and hit[0][3] == 0)
	_chk("S13.02 Motor Drive's holder gained Speed +1",
			stat_events.any(func(e): return e[0] == md_holder and e[1] == BattlePokemon.STAGE_SPEED and e[2] == 1))
	_chk("S13.03 Motor Drive's holder did NOT gain Sp.Atk (discriminator vs. Lightning Rod's shape)",
			not stat_events.any(func(e): return e[0] == md_holder and e[1] == BattlePokemon.STAGE_SPATK))

	bm.queue_free()


# ── Section 14: Well-Baked Body — full-battle Def+2, NOT +1 ──────────────────

func _test_section_14_well_baked_body_full_battle() -> void:
	var ember := _load_move(52)
	var well_baked_body := _load_ability(273)

	var attacker := _make_mon("BattleWBBAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(ember)
	var wbb_holder := _make_mon("BattleWBBHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	wbb_holder.ability = well_baked_body
	wbb_holder.add_move(ember)

	var move_executed_events := []
	var stat_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(wbb_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == wbb_holder)
	_chk("S14.01 Well-Baked Body absorbed the Fire hit (0 damage)",
			not hit.is_empty() and hit[0][3] == 0)
	var def_change := stat_events.filter(
			func(e): return e[0] == wbb_holder and e[1] == BattlePokemon.STAGE_DEF)
	_chk("S14.02 Well-Baked Body's holder gained EXACTLY Def +2",
			not def_change.is_empty() and def_change[0][2] == 2)
	_chk("S14.03 the change is explicitly NOT +1 (the highest-risk detail this tier)",
			not def_change.is_empty() and def_change[0][2] != 1)

	bm.queue_free()


# ── Section 15: Flash Fire — full-battle absorb (flag set, 0 damage) ────────

func _test_section_15_flash_fire_absorb_full_battle() -> void:
	var ember := _load_move(52)
	var water_gun := _load_move(55)
	var flash_fire := _load_ability(18)

	var attacker := _make_mon("BattleFFAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(ember)
	var ff_holder := _make_mon("BattleFFHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	ff_holder.ability = flash_fire
	ff_holder.add_move(ember)

	var move_executed_events := []
	var triggered_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.ability_triggered.connect(func(p, k): triggered_events.push_back([p, k]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(ff_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == ff_holder)
	_chk("S15.01 Flash Fire absorbed the Fire hit (0 damage)",
			not hit.is_empty() and hit[0][3] == 0)
	_chk("S15.02 Flash Fire's flag-set fired (signal snapshot, not post-battle state)",
			triggered_events.any(func(e): return e[0] == ff_holder and e[1] == "flash_fire_boosted"))

	# Negative-shape control in the same battle: the attacker (no Flash Fire) never
	# reports the flash_fire_boosted trigger, even though it's the one dealing the hit.
	_chk("S15.03 the attacker itself (no Flash Fire) never triggers flash_fire_boosted",
			not triggered_events.any(func(e): return e[1] == "flash_fire_boosted" and e[0] == attacker))

	bm.queue_free()


# ── Section 16: Flash Fire's delayed payoff — direct calculate() comparison ─

func _test_section_16_flash_fire_boost_direct_calculate() -> void:
	var ember := _load_move(52)
	var water_gun := _load_move(55)
	var flash_fire := _load_ability(18)
	var target := _make_mon("BattleFFTarget", [TypeChart.TYPE_NORMAL], 200, 40, 40, 40, 40, 40)

	var unboosted := _make_mon("BattleFFUnboosted", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	unboosted.ability = flash_fire
	unboosted.flash_fire_active = false

	var boosted := _make_mon("BattleFFBoosted", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	boosted.ability = flash_fire
	boosted.flash_fire_active = true

	var result_unboosted: Dictionary = DamageCalculator.calculate(unboosted, target, ember, 100, false)
	var result_boosted: Dictionary = DamageCalculator.calculate(boosted, target, ember, 100, false)
	_chk("S16.01 Flash Fire's flag boosts a LATER Fire move's damage (real DamageCalculator " +
			"comparison, not just an assertion the flag exists)",
			result_boosted["damage"] > result_unboosted["damage"])
	_chk("S16.02 the boost is EXACTLY x1.5 (attack_modifier_uq412 = 6144, not an approximation)",
			AbilityManager.attack_modifier_uq412(boosted, ember) == 6144 \
					and AbilityManager.attack_modifier_uq412(unboosted, ember) == 4096)

	var result_boosted_water: Dictionary = DamageCalculator.calculate(boosted, target, water_gun, 100, false)
	var result_unboosted_water: Dictionary = DamageCalculator.calculate(unboosted, target, water_gun, 100, false)
	_chk("S16.03 the flag does NOT boost a non-Fire move (Water Gun) from the same flagged holder",
			result_boosted_water["damage"] == result_unboosted_water["damage"])


# ── Section 17: Negative case — ordinary Pokémon gains nothing ──────────────

func _test_section_17_negative_case() -> void:
	var thunder_shock := _load_move(84)
	var vine_whip := _load_move(22)
	var ember := _load_move(52)

	var plain_electric_target := _make_mon("PlainElectricTarget", [TypeChart.TYPE_NORMAL], 100)
	_chk("S17.01 ordinary Pokémon: absorbs_move_type is empty for Electric",
			AbilityManager.absorbs_move_type(plain_electric_target, TypeChart.TYPE_ELECTRIC).is_empty())
	_chk("S17.02 ordinary Pokémon: absorbs_move_type is empty for Grass",
			AbilityManager.absorbs_move_type(plain_electric_target, TypeChart.TYPE_GRASS).is_empty())
	_chk("S17.03 ordinary Pokémon: absorbs_move_type is empty for Fire",
			AbilityManager.absorbs_move_type(plain_electric_target, TypeChart.TYPE_FIRE).is_empty())

	var attacker := _make_mon("BattleNegAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(thunder_shock)
	var plain_defender := _make_mon("BattleNegDefender", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	plain_defender.add_move(thunder_shock)

	var move_executed_events := []
	var healed_events := []
	var stat_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.ability_healed.connect(func(p, amt): healed_events.push_back([p, amt]))
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(plain_defender))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == plain_defender)
	_chk("S17.04 ordinary Pokémon takes real damage (not absorbed)",
			not hit.is_empty() and hit[0][3] > 0)
	_chk("S17.05 ordinary Pokémon gains no heal signal",
			healed_events.filter(func(e): return e[0] == plain_defender).is_empty())
	_chk("S17.06 ordinary Pokémon gains no stat boost",
			stat_events.filter(func(e): return e[0] == plain_defender).is_empty())

	bm.queue_free()
