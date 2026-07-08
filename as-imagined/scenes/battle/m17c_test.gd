extends Node

# M17c test suite — Tier C move effects: switch-in / turn-end triggers, no new
# field-state infrastructure.
#
# Scope: the 22 abilities locked in docs/decisions.md [M17c]:
#   Sand Stream, Snow Warning (weather-setters, get_switch_in_weather)
#   Rain Dish, Ice Body, Dry Skin, Hydration, Shed Skin, Healer (end-of-turn heal/cure)
#   Truant (pre-move canceler + end-of-turn toggle)
#   Poison Point, Effect Spore, Poison Touch (contact status infliction)
#   Cursed Body, Toxic Debris (non-contact-gated hit-reactive)
#   Flower Gift (weather-conditional stat modifiers, self + ally)
#   Slush Rush (weather-conditional speed modifier)
#   Cheek Pouch, Ripen (item-adjacent)
#   Hospitality (switch-in ally heal)
#   Anticipation, Forewarn, Frisk (cosmetic/no-op — registration only)
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state, for anything observed through a full battle.
#   - Array-wrapper for any lambda that needs to report a result back to the enclosing
#     test function (GDScript captures scalars by value, not reference).
#
# Ground truth: pokeemerald_expansion src/battle_util.c, src/battle_move_resolution.c,
# src/battle_script_commands.c.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_weather_setters()
	_test_section_3_end_of_turn_heal_cure()
	_test_section_4_truant()
	_test_section_5_contact_status()
	_test_section_6_cursed_body()
	_test_section_7_toxic_debris()
	_test_section_8_flower_gift()
	_test_section_9_slush_rush()
	_test_section_10_cheek_pouch_ripen()
	_test_section_11_hospitality()
	_test_section_12_cosmetic_no_ops()

	var total := _pass + _fail
	print("m17c_test: %d/%d passed" % [_pass, total])
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


# [M18.5a] minimal item constructor — only Covert Cloak's gate needs an item in
# this suite, matching [M18x]'s own `_make_item(hold_effect, param)` shape.
func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var sand_stream := _load_ability(45)
	_chk("S1.01 Sand Stream id=45", sand_stream.ability_id == 45)
	var truant := _load_ability(54)
	_chk("S1.02 Truant id=54", truant.ability_id == 54)
	var shed_skin := _load_ability(61)
	_chk("S1.03 Shed Skin id=61", shed_skin.ability_id == 61)
	var flower_gift := _load_ability(122)
	_chk("S1.04 Flower Gift id=122", flower_gift.ability_id == 122)
	var hospitality := _load_ability(299)
	_chk("S1.05 Hospitality id=299", hospitality.ability_id == 299)
	var slush_rush := _load_ability(202)
	_chk("S1.06 Slush Rush id=202", slush_rush.ability_id == 202)


# ── Section 2: Weather-setters — Sand Stream, Snow Warning ───────────────────

func _test_section_2_weather_setters() -> void:
	var sand_mon := _make_mon("SandMon", 50, [TypeChart.TYPE_ROCK])
	sand_mon.ability = _load_ability(45)
	_chk("S2.01 Sand Stream: sets Sandstorm on switch-in",
			AbilityManager.get_switch_in_weather(sand_mon) == DamageCalculator.WEATHER_SANDSTORM)

	var snow_mon := _make_mon("SnowMon", 50, [TypeChart.TYPE_ICE])
	snow_mon.ability = _load_ability(117)
	_chk("S2.02 Snow Warning: sets Hail on switch-in",
			AbilityManager.get_switch_in_weather(snow_mon) == DamageCalculator.WEATHER_HAIL)

	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	_chk("S2.03 No ability: does NOT set weather",
			AbilityManager.get_switch_in_weather(plain_mon) == DamageCalculator.WEATHER_NONE)


# ── Section 3: End-of-turn heal/cure — Rain Dish, Ice Body, Dry Skin, ────────
# Hydration, Shed Skin, Healer ────────────────────────────────────────────────

func _test_section_3_end_of_turn_heal_cure() -> void:
	# Rain Dish: heal maxHP/16 in rain, only if not at max HP.
	var rain_dish := _make_mon("RainDishMon", 50, [TypeChart.TYPE_WATER], 160)
	rain_dish.ability = _load_ability(44)
	rain_dish.current_hp = 100
	var r1: Dictionary = AbilityManager.try_end_of_turn(
			rain_dish, null, null, DamageCalculator.WEATHER_RAIN)
	_chk("S3.01 Rain Dish: heals maxHP/16 in rain", r1["heal_amount"] == rain_dish.max_hp / 16)
	var r1b: Dictionary = AbilityManager.try_end_of_turn(
			rain_dish, null, null, DamageCalculator.WEATHER_SUN)
	_chk("S3.02 Rain Dish: does NOT heal outside rain", r1b["heal_amount"] == 0)
	var rain_dish_full := _make_mon("RainDishFull", 50, [TypeChart.TYPE_WATER], 160)
	rain_dish_full.ability = _load_ability(44)
	var r1c: Dictionary = AbilityManager.try_end_of_turn(
			rain_dish_full, null, null, DamageCalculator.WEATHER_RAIN)
	_chk("S3.03 Rain Dish: does NOT heal at full HP", r1c["heal_amount"] == 0)

	# Ice Body: heal maxHP/16 in hail.
	var ice_body := _make_mon("IceBodyMon", 50, [TypeChart.TYPE_ICE], 160)
	ice_body.ability = _load_ability(115)
	ice_body.current_hp = 100
	var r2: Dictionary = AbilityManager.try_end_of_turn(
			ice_body, null, null, DamageCalculator.WEATHER_HAIL)
	_chk("S3.04 Ice Body: heals maxHP/16 in hail", r2["heal_amount"] == ice_body.max_hp / 16)
	var r2b: Dictionary = AbilityManager.try_end_of_turn(
			ice_body, null, null, DamageCalculator.WEATHER_RAIN)
	_chk("S3.05 Ice Body: does NOT heal outside hail", r2b["heal_amount"] == 0)

	# Dry Skin: heal maxHP/8 in rain; damage maxHP/8 in sun.
	var dry_skin := _make_mon("DrySkinMon", 50, [TypeChart.TYPE_NORMAL], 160)
	dry_skin.ability = _load_ability(87)
	dry_skin.current_hp = 100
	var r3: Dictionary = AbilityManager.try_end_of_turn(
			dry_skin, null, null, DamageCalculator.WEATHER_RAIN)
	_chk("S3.06 Dry Skin: heals maxHP/8 in rain", r3["heal_amount"] == dry_skin.max_hp / 8)
	var dry_skin2 := _make_mon("DrySkinMon2", 50, [TypeChart.TYPE_NORMAL], 160)
	dry_skin2.ability = _load_ability(87)
	var r3b: Dictionary = AbilityManager.try_end_of_turn(
			dry_skin2, null, null, DamageCalculator.WEATHER_SUN)
	_chk("S3.07 Dry Skin: takes maxHP/8 damage in sun", r3b["damage_amount"] == dry_skin2.max_hp / 8)
	var r3c: Dictionary = AbilityManager.try_end_of_turn(
			dry_skin2, null, null, DamageCalculator.WEATHER_SANDSTORM)
	_chk("S3.08 Dry Skin: no effect in sandstorm", r3c["heal_amount"] == 0 and r3c["damage_amount"] == 0)

	# Dry Skin's Fire-type damage-taken increase (damage pipeline half).
	var fire_move := _make_move(TypeChart.TYPE_FIRE, 1, 40)
	var water_move := _make_move(TypeChart.TYPE_WATER, 1, 40)
	var atk := _make_mon("Atk", 50, [TypeChart.TYPE_NORMAL])
	var dry_def := _make_mon("DryDef", 50, [TypeChart.TYPE_NORMAL])
	dry_def.ability = _load_ability(87)
	var plain_def := _make_mon("PlainDef", 50, [TypeChart.TYPE_NORMAL])
	var fire_result := DamageCalculator.calculate(atk, dry_def, fire_move, 100, false)
	var fire_baseline := DamageCalculator.calculate(atk, plain_def, fire_move, 100, false)
	_chk("S3.09 Dry Skin: takes MORE damage from Fire-type moves",
			fire_result["damage"] > fire_baseline["damage"])
	# M17m update: the Water-move absorb+heal half, deferred at M17c's own writing
	# (needed Volt-Absorb/Water-Absorb-style immunity+heal infra this project didn't
	# have yet), is now implemented — see docs/decisions.md [M17m]. This assertion is
	# updated in place (not duplicated) because the OLD assertion here directly encoded
	# the now-superseded "not implemented" premise as a passing test; leaving it would
	# be a permanent, known-false regression, not a preserved historical test. The
	# dedicated heal-amount/full-battle coverage for this new piece lives in
	# scenes/battle/m17m_test.gd's Section 11 (Water-move absorb heals maxHP/4, a
	# DIFFERENT divisor than this ability's own end-of-turn maxHP/8 tick above) — not
	# duplicated here, this is just the pre-existing damage-pipeline discriminator
	# updated to match reality.
	var water_result := DamageCalculator.calculate(atk, dry_def, water_move, 100, false)
	_chk("S3.10 Dry Skin: Water-move hits are now absorbed (0 damage, M17m)",
			water_result["damage"] == 0)

	# Hydration: cures own status in rain.
	var hydration := _make_mon("HydrationMon", 50, [TypeChart.TYPE_WATER])
	hydration.ability = _load_ability(93)
	hydration.status = BattlePokemon.STATUS_PARALYSIS
	var r4: Dictionary = AbilityManager.try_end_of_turn(
			hydration, null, null, DamageCalculator.WEATHER_RAIN)
	_chk("S4.11 Hydration: cures status in rain", r4["cured_status"] == true)
	var hydration2 := _make_mon("HydrationMon2", 50, [TypeChart.TYPE_WATER])
	hydration2.ability = _load_ability(93)
	hydration2.status = BattlePokemon.STATUS_PARALYSIS
	var r4b: Dictionary = AbilityManager.try_end_of_turn(
			hydration2, null, null, DamageCalculator.WEATHER_SUN)
	_chk("S3.12 Hydration: does NOT cure status outside rain", r4b["cured_status"] == false)

	# Shed Skin: 1/3 chance to cure own status (any weather).
	var shed_skin := _make_mon("ShedSkinMon", 50, [TypeChart.TYPE_NORMAL])
	shed_skin.ability = _load_ability(61)
	shed_skin.status = BattlePokemon.STATUS_BURN
	var r5: Dictionary = AbilityManager.try_end_of_turn(shed_skin, null, null,
			DamageCalculator.WEATHER_NONE, null, true)
	_chk("S3.13 Shed Skin: forced roll cures status", r5["cured_status"] == true)
	var shed_skin2 := _make_mon("ShedSkinMon2", 50, [TypeChart.TYPE_NORMAL])
	shed_skin2.ability = _load_ability(61)
	shed_skin2.status = BattlePokemon.STATUS_BURN
	var r5b: Dictionary = AbilityManager.try_end_of_turn(shed_skin2, null, null,
			DamageCalculator.WEATHER_NONE, null, false)
	_chk("S3.14 Shed Skin: forced-failed roll does NOT cure", r5b["cured_status"] == false)
	var shed_skin3 := _make_mon("ShedSkinMon3", 50, [TypeChart.TYPE_NORMAL])
	shed_skin3.ability = _load_ability(61)
	var r5c: Dictionary = AbilityManager.try_end_of_turn(shed_skin3, null, null,
			DamageCalculator.WEATHER_NONE, null, true)
	_chk("S3.15 Shed Skin: no status present → does NOT cure (nothing to cure)",
			r5c["cured_status"] == false)

	# Healer: 30% chance to cure the ALLY's status (doubles-only).
	var healer := _make_mon("HealerMon", 50, [TypeChart.TYPE_NORMAL])
	healer.ability = _load_ability(131)
	var healer_ally := _make_mon("HealerAlly", 50, [TypeChart.TYPE_NORMAL])
	healer_ally.status = BattlePokemon.STATUS_POISON
	var r6: Dictionary = AbilityManager.try_end_of_turn(healer, null, null,
			DamageCalculator.WEATHER_NONE, healer_ally, null, true)
	_chk("S3.16 Healer: forced roll cures the ally's status", r6["healed_ally_status"] == true)
	var healer2 := _make_mon("HealerMon2", 50, [TypeChart.TYPE_NORMAL])
	healer2.ability = _load_ability(131)
	var healer_ally2 := _make_mon("HealerAlly2", 50, [TypeChart.TYPE_NORMAL])
	healer_ally2.status = BattlePokemon.STATUS_POISON
	var r6b: Dictionary = AbilityManager.try_end_of_turn(healer2, null, null,
			DamageCalculator.WEATHER_NONE, healer_ally2, null, false)
	_chk("S3.17 Healer: forced-failed roll does NOT cure the ally", r6b["healed_ally_status"] == false)
	var healer3 := _make_mon("HealerMon3", 50, [TypeChart.TYPE_NORMAL])
	healer3.ability = _load_ability(131)
	var r6c: Dictionary = AbilityManager.try_end_of_turn(healer3, null, null,
			DamageCalculator.WEATHER_NONE, null, null, true)
	_chk("S3.18 Healer: no ally (singles) does NOT cure anything", r6c["healed_ally_status"] == false)


# ── Section 4: Truant ─────────────────────────────────────────────────────────

func _test_section_4_truant() -> void:
	var truant_mon := _make_mon("TruantMon", 50, [TypeChart.TYPE_NORMAL])
	truant_mon.ability = _load_ability(54)

	# Turn 1: not loafing yet, can move.
	var c1: Dictionary = StatusManager.pre_move_check(truant_mon)
	_chk("S4.01 Truant: can move on the first turn (not yet loafing)", c1["can_move"] == true)
	_chk("S4.02 Truant: loafing flag is false on the first turn", c1["loafing"] == false)

	# End of turn 1: toggles truantCounter on.
	AbilityManager.try_end_of_turn(truant_mon)
	_chk("S4.03 Truant: end-of-turn toggles loafing ON", truant_mon.truant_loafing == true)

	# Turn 2: loafing — move fails.
	var c2: Dictionary = StatusManager.pre_move_check(truant_mon)
	_chk("S4.04 Truant: cannot move while loafing", c2["can_move"] == false)
	_chk("S4.05 Truant: loafing flag is true", c2["loafing"] == true)

	# End of turn 2: toggles truantCounter back off.
	AbilityManager.try_end_of_turn(truant_mon)
	_chk("S4.06 Truant: end-of-turn toggles loafing back OFF", truant_mon.truant_loafing == false)

	# Turn 3: can move again.
	var c3: Dictionary = StatusManager.pre_move_check(truant_mon)
	_chk("S4.07 Truant: can move again on the third turn", c3["can_move"] == true)

	# Negative: no ability → try_end_of_turn never touches truant_loafing.
	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	AbilityManager.try_end_of_turn(plain_mon)
	_chk("S4.08 No ability: truant_loafing stays false", plain_mon.truant_loafing == false)


# ── Section 5: Contact status — Poison Point, Poison Touch, Effect Spore ─────

func _test_section_5_contact_status() -> void:
	var contact_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, true)
	var attacker := _make_mon("Attacker", 50, [TypeChart.TYPE_NORMAL])

	# Poison Point: 30% chance to poison the attacker on contact.
	var poison_point := _make_mon("PoisonPointMon", 50, [TypeChart.TYPE_NORMAL])
	poison_point.ability = _load_ability(38)
	var r1: Dictionary = AbilityManager.try_contact_effects(
			attacker, poison_point, contact_move, 10, true)
	_chk("S5.01 Poison Point: forced roll poisons the attacker",
			r1["status_applied"] == BattlePokemon.STATUS_POISON)
	var attacker2 := _make_mon("Attacker2", 50, [TypeChart.TYPE_NORMAL])
	var r1b: Dictionary = AbilityManager.try_contact_effects(
			attacker2, poison_point, contact_move, 10, false)
	_chk("S5.02 Poison Point: forced-failed roll does NOT poison", r1b["status_applied"] == 0)

	# [M18.5a] Poison Touch: a GENUINELY DIFFERENT dispatch shape from Poison Point
	# above, corrected from a [M17c]-era bug (found at [M18x], fixed here) that
	# merged it into the same defender-keyed branch as Poison Point and poisoned
	# the wrong battler. Real source dispatches Poison Touch via the ATTACKER's own
	# ability and poisons the DEFENDER — the fixture below is now ability-holder-
	# on-attacker, poison-observed-on-defender, the mirror image of S5.01/S5.02.
	var pt_attacker := _make_mon("PTAttacker", 50, [TypeChart.TYPE_NORMAL])
	pt_attacker.ability = _load_ability(143)
	var pt_defender := _make_mon("PTDefender", 50, [TypeChart.TYPE_NORMAL])
	var r2: Dictionary = AbilityManager.try_contact_effects(
			pt_attacker, pt_defender, contact_move, 10, true)
	_chk("S5.03 Poison Touch: forced roll poisons the DEFENDER (corrected direction)",
			r2["status_applied"] == BattlePokemon.STATUS_POISON)
	_chk("S5.03b discriminator: the Poison Touch HOLDER (attacker) itself is never " +
			"poisoned by its own ability", pt_attacker.status != BattlePokemon.STATUS_POISON)

	# Discriminator: Poison Touch held by the DEFENDER (the old, buggy direction)
	# does NOT fire — proves S5.03 isn't accidentally passing via the old defender-
	# keyed branch still matching by coincidence.
	var pt_defender_holds_it := _make_mon("PTDefenderHoldsIt", 50, [TypeChart.TYPE_NORMAL])
	pt_defender_holds_it.ability = _load_ability(143)
	var pt_plain_attacker := _make_mon("PTPlainAttacker", 50, [TypeChart.TYPE_NORMAL])
	var r2b: Dictionary = AbilityManager.try_contact_effects(
			pt_plain_attacker, pt_defender_holds_it, contact_move, 10, true)
	_chk("S5.03c discriminator: Poison Touch held by the DEFENDER (not the " +
			"attacker) does not fire at all", r2b["status_applied"] == 0)

	# Shield Dust gate ([M18x]'s own flagged gap, closed here): the DEFENDER's
	# Shield Dust blocks an attacking Poison Touch holder from poisoning it.
	var pt_atk_vs_shield_dust := _make_mon("PTAtkVsShieldDust", 50, [TypeChart.TYPE_NORMAL])
	pt_atk_vs_shield_dust.ability = _load_ability(143)
	var shield_dust_defender := _make_mon("ShieldDustDefender", 50, [TypeChart.TYPE_NORMAL])
	shield_dust_defender.ability = _load_ability(19)
	var r2c: Dictionary = AbilityManager.try_contact_effects(
			pt_atk_vs_shield_dust, shield_dust_defender, contact_move, 10, true)
	_chk("S5.03d Shield Dust blocks an attacking Poison Touch holder",
			r2c["status_applied"] == 0)

	# Covert Cloak gate (the item-side twin of Shield Dust's gate above, same
	# `IsMoveEffectBlockedByTarget` source function): the DEFENDER's held Covert
	# Cloak likewise blocks it.
	var pt_atk_vs_covert_cloak := _make_mon("PTAtkVsCovertCloak", 50, [TypeChart.TYPE_NORMAL])
	pt_atk_vs_covert_cloak.ability = _load_ability(143)
	var covert_cloak_defender := _make_mon("CovertCloakDefender", 50, [TypeChart.TYPE_NORMAL])
	covert_cloak_defender.held_item = _make_item(ItemManager.HOLD_EFFECT_COVERT_CLOAK)
	var r2d: Dictionary = AbilityManager.try_contact_effects(
			pt_atk_vs_covert_cloak, covert_cloak_defender, contact_move, 10, true)
	_chk("S5.03e Covert Cloak blocks an attacking Poison Touch holder",
			r2d["status_applied"] == 0)

	# Effect Spore: weighted 3-way roll (9% poison / 10% paralysis / 11% sleep).
	var effect_spore := _make_mon("EffectSporeMon", 50, [TypeChart.TYPE_NORMAL])
	effect_spore.ability = _load_ability(27)
	var atk_poison := _make_mon("AtkPoison", 50, [TypeChart.TYPE_NORMAL])
	var r3: Dictionary = AbilityManager.try_contact_effects(
			atk_poison, effect_spore, contact_move, 10, null, 0)
	_chk("S5.04 Effect Spore: roll=0 → poison", r3["status_applied"] == BattlePokemon.STATUS_POISON)
	var atk_para := _make_mon("AtkPara", 50, [TypeChart.TYPE_NORMAL])
	var r4: Dictionary = AbilityManager.try_contact_effects(
			atk_para, effect_spore, contact_move, 10, null, 10)
	_chk("S5.05 Effect Spore: roll=10 → paralysis", r4["status_applied"] == BattlePokemon.STATUS_PARALYSIS)
	var atk_sleep := _make_mon("AtkSleep", 50, [TypeChart.TYPE_NORMAL])
	var r5: Dictionary = AbilityManager.try_contact_effects(
			atk_sleep, effect_spore, contact_move, 10, null, 20)
	_chk("S5.06 Effect Spore: roll=20 → sleep", r5["status_applied"] == BattlePokemon.STATUS_SLEEP)
	var atk_none := _make_mon("AtkNone", 50, [TypeChart.TYPE_NORMAL])
	var r6: Dictionary = AbilityManager.try_contact_effects(
			atk_none, effect_spore, contact_move, 10, null, 50)
	_chk("S5.07 Effect Spore: roll=50 → no effect", r6["status_applied"] == 0)

	# Negative: Grass-type attacker is immune to Effect Spore (powder immunity).
	var grass_attacker := _make_mon("GrassAtk", 50, [TypeChart.TYPE_GRASS])
	var r7: Dictionary = AbilityManager.try_contact_effects(
			grass_attacker, effect_spore, contact_move, 10, null, 0)
	_chk("S5.08 Effect Spore: Grass-type attacker is immune", r7["status_applied"] == 0)

	# [M17.5 Batch Fix] S5.08b: an Overcoat-holding ATTACKER is likewise immune to
	# Effect Spore's proc — the OTHER half of `IsAffectedByPowderMove`, confirmed via
	# source read to be evaluated against gBattlerAttacker (the mon making contact,
	# who is the one at risk of being afflicted), not the Effect Spore holder itself.
	# Previously only the Grass-type half (S5.08 above) was wired; this closes the gap
	# the M17.5 recon found (the function's own header comment already mentioned
	# "Grass-type/Overcoat exemption" but only Grass-type was actually implemented).
	var overcoat_attacker := _make_mon("OvercoatAtk", 50, [TypeChart.TYPE_NORMAL])
	overcoat_attacker.ability = _load_ability(142)
	var r7b: Dictionary = AbilityManager.try_contact_effects(
			overcoat_attacker, effect_spore, contact_move, 10, null, 0)
	_chk("S5.08b Effect Spore: Overcoat-holding attacker is immune", r7b["status_applied"] == 0)

	# Discriminator: a plain (non-Grass, non-Overcoat) attacker is NOT immune —
	# confirms S5.08/S5.08b are genuine exemptions, not the roll always failing.
	var plain_attacker := _make_mon("PlainAtkS5", 50, [TypeChart.TYPE_NORMAL])
	var r7c: Dictionary = AbilityManager.try_contact_effects(
			plain_attacker, effect_spore, contact_move, 10, null, 0)
	_chk("S5.08c Effect Spore: ordinary attacker (no exemption) is NOT immune",
			r7c["status_applied"] == BattlePokemon.STATUS_POISON)

	# Negative: no contact → none of these fire.
	var non_contact_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, false)
	var atk_no_contact := _make_mon("AtkNoContact", 50, [TypeChart.TYPE_NORMAL])
	var r8: Dictionary = AbilityManager.try_contact_effects(
			atk_no_contact, poison_point, non_contact_move, 10, true)
	_chk("S5.09 Poison Point: does NOT fire without contact", r8["status_applied"] == 0)

	# [M18.5g-followup / M18.5g-followup-2] S5.10/S5.11: full-battle integration
	# through BattleManager, checking the secondary_applied signal's SE_* payload AND
	# (as of [M18.5g-followup-2]) WHICH battler it's emitted on, plus Synchronize
	# direction and cure-berry target. S5.01-S5.09 above all call
	# AbilityManager.try_contact_effects directly — one layer BELOW where
	# BattleManager derives status_target/status_source and converts via
	# _status_to_se — so none of them exercise any of this.
	var pp_atk_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, true)
	pp_atk_move.pp = 20
	var pp_int_attacker := _make_mon("PPIntAttacker", 50, [TypeChart.TYPE_NORMAL], 200)
	pp_int_attacker.add_move(pp_atk_move)
	var pp_int_holder := _make_mon("PPIntHolder", 50, [TypeChart.TYPE_NORMAL], 200)
	pp_int_holder.ability = _load_ability(38)
	var pp_int_filler := _make_move(TypeChart.TYPE_NORMAL, 0, 20)
	pp_int_filler.pp = 20
	pp_int_holder.add_move(pp_int_filler)
	var pp_bm := _make_bm()
	pp_bm._force_hit = true
	pp_bm._force_crit = false
	pp_bm._force_roll = 100
	pp_bm._force_contact_roll = true
	var pp_signal_se := [-1]
	var pp_signal_target: Array = [null]
	pp_bm.secondary_applied.connect(func(t: BattlePokemon, eff: int) -> void:
		if pp_signal_se[0] == -1 and (t == pp_int_attacker or t == pp_int_holder):
			pp_signal_se[0] = eff
			pp_signal_target[0] = t)
	pp_bm.start_battle(pp_int_attacker, pp_int_holder)
	_chk("S5.10a Poison Point integration: secondary_applied signal carries SE_POISON, " +
			"not SE_TOXIC", pp_signal_se[0] == MoveData.SE_POISON)
	_chk("S5.10b Poison Point integration: secondary_applied signal names the ATTACKER " +
			"(unchanged by [M18.5g-followup-2] — Poison Point is defender-keyed, poisons " +
			"whoever touched it)", pp_signal_target[0] == pp_int_attacker)

	# S5.10c: Synchronize discriminator, Poison Point direction. The AFFLICTED mon
	# (attacker) holds Synchronize, so it should reflect the poison back onto the
	# Poison Point HOLDER (defender) — confirms _try_synchronize's holder/source
	# pair is (status_target, status_source), unchanged for this already-correct
	# direction. Source: [M18.5a]/AbilityManager.try_synchronize's own holder=
	# afflicted-mon, source=inflictor contract.
	var pps_atk_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, true)
	pps_atk_move.pp = 20
	var pps_attacker := _make_mon("PPSyncAttacker", 50, [TypeChart.TYPE_NORMAL], 200)
	pps_attacker.ability = _load_ability(28)  # Synchronize
	pps_attacker.add_move(pps_atk_move)
	var pps_holder := _make_mon("PPSyncHolder", 50, [TypeChart.TYPE_NORMAL], 200)
	pps_holder.ability = _load_ability(38)  # Poison Point
	var pps_filler := _make_move(TypeChart.TYPE_NORMAL, 0, 20)
	pps_filler.pp = 20
	pps_holder.add_move(pps_filler)
	var pps_bm := _make_bm()
	pps_bm._force_hit = true
	pps_bm._force_crit = false
	pps_bm._force_roll = 100
	pps_bm._force_contact_roll = true
	var pps_sync_fired_on: Array = [null]
	var pps_reflected_onto: Array = [null]
	pps_bm.ability_triggered.connect(func(mon: BattlePokemon, ability_name: String) -> void:
		if ability_name == "synchronize" and pps_sync_fired_on[0] == null:
			pps_sync_fired_on[0] = mon)
	var pps_se_count := [0]
	pps_bm.secondary_applied.connect(func(t: BattlePokemon, eff: int) -> void:
		pps_se_count[0] += 1
		if pps_se_count[0] == 2:  # 1st = original poison, 2nd = Synchronize's reflection
			pps_reflected_onto[0] = t)
	pps_bm.start_battle(pps_attacker, pps_holder)
	_chk("S5.10c Poison Point + Synchronize: fires on the AFFLICTED mon (attacker), " +
			"not the Poison Point holder", pps_sync_fired_on[0] == pps_attacker)
	_chk("S5.10d Poison Point + Synchronize: reflects the poison onto the INFLICTOR " +
			"(the Poison Point holder)", pps_reflected_onto[0] == pps_holder)

	# S5.10e: cure-berry discriminator, Poison Point direction. The AFFLICTED mon
	# (attacker) holds Pecha Berry — should auto-cure and consume its OWN item.
	var ppc_atk_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, true)
	ppc_atk_move.pp = 20
	var ppc_attacker := _make_mon("PPCureAttacker", 50, [TypeChart.TYPE_NORMAL], 200)
	ppc_attacker.held_item = _make_item(ItemManager.HOLD_EFFECT_CURE_PSN)
	ppc_attacker.add_move(ppc_atk_move)
	var ppc_holder := _make_mon("PPCureHolder", 50, [TypeChart.TYPE_NORMAL], 200)
	ppc_holder.ability = _load_ability(38)  # Poison Point
	var ppc_filler := _make_move(TypeChart.TYPE_NORMAL, 0, 20)
	ppc_filler.pp = 20
	ppc_holder.add_move(ppc_filler)
	var ppc_bm := _make_bm()
	ppc_bm._force_hit = true
	ppc_bm._force_crit = false
	ppc_bm._force_roll = 100
	ppc_bm._force_contact_roll = true
	var ppc_consumed_from: Array = [null]
	ppc_bm.item_consumed.connect(func(mon: BattlePokemon, _item: ItemData) -> void:
		if ppc_consumed_from[0] == null:
			ppc_consumed_from[0] = mon)
	ppc_bm.start_battle(ppc_attacker, ppc_holder)
	_chk("S5.10e Poison Point + Pecha Berry: cure-berry consumed from the AFFLICTED " +
			"mon (attacker), unchanged by [M18.5g-followup-2]",
			ppc_consumed_from[0] == ppc_attacker)

	# S5.11: Poison Touch's own direction (attacker holds the ability, DEFENDER gets
	# poisoned) — [M18.5g-followup] found that BattleManager's contact-status
	# follow-up (_do_damaging_hit, right after try_contact_effects) hardcoded
	# `attacker` as the poisoned battler for the signal/Synchronize/cure-berry
	# follow-up, correct for Poison Point/Static/Flame Body/Effect Spore (all
	# defender-keyed) but wrong for Poison Touch (attacker-keyed, DEFENDER-poisoning
	# per [M18.5a]). [M18.5g-followup-2] fixed this via try_contact_effects's new
	# "status_target" key; S5.11b/c/d below assert the corrected identity directly
	# (S5.11 in [M18.5g-followup] deliberately avoided this — see that entry).
	var pt_int_atk_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, true)
	pt_int_atk_move.pp = 20
	var pt_int_attacker := _make_mon("PTIntAttacker", 50, [TypeChart.TYPE_NORMAL], 200)
	pt_int_attacker.ability = _load_ability(143)
	pt_int_attacker.add_move(pt_int_atk_move)
	var pt_int_defender := _make_mon("PTIntDefender", 50, [TypeChart.TYPE_NORMAL], 200)
	var pt_int_filler := _make_move(TypeChart.TYPE_NORMAL, 0, 20)
	pt_int_filler.pp = 20
	pt_int_defender.add_move(pt_int_filler)
	var pt_bm := _make_bm()
	pt_bm._force_hit = true
	pt_bm._force_crit = false
	pt_bm._force_roll = 100
	pt_bm._force_contact_roll = true
	var pt_signal_se := [-1]
	var pt_signal_target: Array = [null]
	pt_bm.secondary_applied.connect(func(t: BattlePokemon, eff: int) -> void:
		if pt_signal_se[0] == -1 and (t == pt_int_attacker or t == pt_int_defender):
			pt_signal_se[0] = eff
			pt_signal_target[0] = t)
	pt_bm.start_battle(pt_int_attacker, pt_int_defender)
	_chk("S5.11a Poison Touch integration: secondary_applied signal carries SE_POISON, " +
			"not SE_TOXIC", pt_signal_se[0] == MoveData.SE_POISON)
	_chk("S5.11b Poison Touch integration: secondary_applied signal names the DEFENDER " +
			"(the real victim) — the [M18.5g-followup-2] fix", pt_signal_target[0] == pt_int_defender)

	# S5.11c/d: Synchronize discriminator, Poison Touch direction. The AFFLICTED mon
	# is the DEFENDER — if IT holds Synchronize, it should reflect the poison onto
	# the Poison Touch HOLDER (attacker). Pre-fix, this could never fire: the old
	# code checked `attacker`'s (the Poison Touch holder's) own ability for
	# Synchronize, not the defender's.
	var pts_atk_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, true)
	pts_atk_move.pp = 20
	var pts_attacker := _make_mon("PTSyncAttacker", 50, [TypeChart.TYPE_NORMAL], 200)
	pts_attacker.ability = _load_ability(143)  # Poison Touch
	pts_attacker.add_move(pts_atk_move)
	var pts_defender := _make_mon("PTSyncDefender", 50, [TypeChart.TYPE_NORMAL], 200)
	pts_defender.ability = _load_ability(28)  # Synchronize
	var pts_filler := _make_move(TypeChart.TYPE_NORMAL, 0, 20)
	pts_filler.pp = 20
	pts_defender.add_move(pts_filler)
	var pts_bm := _make_bm()
	pts_bm._force_hit = true
	pts_bm._force_crit = false
	pts_bm._force_roll = 100
	pts_bm._force_contact_roll = true
	var pts_sync_fired_on: Array = [null]
	var pts_reflected_onto: Array = [null]
	pts_bm.ability_triggered.connect(func(mon: BattlePokemon, ability_name: String) -> void:
		if ability_name == "synchronize" and pts_sync_fired_on[0] == null:
			pts_sync_fired_on[0] = mon)
	var pts_se_count := [0]
	pts_bm.secondary_applied.connect(func(t: BattlePokemon, eff: int) -> void:
		pts_se_count[0] += 1
		if pts_se_count[0] == 2:  # 1st = original poison, 2nd = Synchronize's reflection
			pts_reflected_onto[0] = t)
	pts_bm.start_battle(pts_attacker, pts_defender)
	_chk("S5.11c Poison Touch + Synchronize: fires on the AFFLICTED mon (defender), " +
			"not the Poison Touch holder — was unreachable before [M18.5g-followup-2]",
			pts_sync_fired_on[0] == pts_defender)
	_chk("S5.11d Poison Touch + Synchronize: reflects the poison onto the INFLICTOR " +
			"(the Poison Touch holder)", pts_reflected_onto[0] == pts_attacker)

	# S5.11e: cure-berry discriminator, Poison Touch direction. The AFFLICTED mon is
	# the DEFENDER — if IT holds Pecha Berry, it should auto-cure ITS OWN poison and
	# consume ITS OWN item, not the attacker's. Pre-fix, the caller checked
	# `attacker`'s held item instead, so this defender-held berry would never fire.
	var ptc_atk_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, true)
	ptc_atk_move.pp = 20
	var ptc_attacker := _make_mon("PTCureAttacker", 50, [TypeChart.TYPE_NORMAL], 200)
	ptc_attacker.ability = _load_ability(143)  # Poison Touch
	ptc_attacker.add_move(ptc_atk_move)
	var ptc_defender := _make_mon("PTCureDefender", 50, [TypeChart.TYPE_NORMAL], 200)
	ptc_defender.held_item = _make_item(ItemManager.HOLD_EFFECT_CURE_PSN)
	var ptc_filler := _make_move(TypeChart.TYPE_NORMAL, 0, 20)
	ptc_filler.pp = 20
	ptc_defender.add_move(ptc_filler)
	var ptc_bm := _make_bm()
	ptc_bm._force_hit = true
	ptc_bm._force_crit = false
	ptc_bm._force_roll = 100
	ptc_bm._force_contact_roll = true
	var ptc_consumed_from: Array = [null]
	ptc_bm.item_consumed.connect(func(mon: BattlePokemon, _item: ItemData) -> void:
		if ptc_consumed_from[0] == null:
			ptc_consumed_from[0] = mon)
	ptc_bm.start_battle(ptc_attacker, ptc_defender)
	_chk("S5.11e Poison Touch + Pecha Berry: cure-berry consumed from the AFFLICTED " +
			"mon (defender), not the attacker — was unreachable before " +
			"[M18.5g-followup-2]", ptc_consumed_from[0] == ptc_defender)


# ── Section 6: Cursed Body ─────────────────────────────────────────────────────

func _test_section_6_cursed_body() -> void:
	var move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var cursed_body := _make_mon("CursedBodyMon", 50, [TypeChart.TYPE_GHOST])
	cursed_body.ability = _load_ability(130)
	var attacker := _make_mon("Attacker", 50, [TypeChart.TYPE_NORMAL])
	var r1: Dictionary = AbilityManager.try_hit_reactive_effects(
			attacker, cursed_body, move, 10, cursed_body.max_hp, false, true)
	_chk("S6.01 Cursed Body: forced roll fires", r1["cursed_body_fired"] == true)

	var attacker2 := _make_mon("Attacker2", 50, [TypeChart.TYPE_NORMAL])
	var r1b: Dictionary = AbilityManager.try_hit_reactive_effects(
			attacker2, cursed_body, move, 10, cursed_body.max_hp, false, false)
	_chk("S6.02 Cursed Body: forced-failed roll does NOT fire", r1b["cursed_body_fired"] == false)

	# Negative: attacker already has a disabled move.
	var attacker3 := _make_mon("Attacker3", 50, [TypeChart.TYPE_NORMAL])
	attacker3.disabled_move = move
	var r1c: Dictionary = AbilityManager.try_hit_reactive_effects(
			attacker3, cursed_body, move, 10, cursed_body.max_hp, false, true)
	_chk("S6.03 Cursed Body: does NOT fire if attacker already disabled", r1c["cursed_body_fired"] == false)

	# Negative: Struggle can never be disabled.
	var struggle := _make_move(TypeChart.TYPE_NORMAL, 0, 50)
	struggle.is_struggle = true
	var attacker4 := _make_mon("Attacker4", 50, [TypeChart.TYPE_NORMAL])
	var r1d: Dictionary = AbilityManager.try_hit_reactive_effects(
			attacker4, cursed_body, struggle, 10, cursed_body.max_hp, false, true)
	_chk("S6.04 Cursed Body: does NOT fire against Struggle", r1d["cursed_body_fired"] == false)

	# Full-battle integration: BattleManager actually applies the disable.
	var atk_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, false)
	atk_move.pp = 20
	var cb_attacker := _make_mon("CBAttacker", 50, [TypeChart.TYPE_NORMAL], 200)
	cb_attacker.add_move(atk_move)
	# Normal-type is used for the holder (not Ghost, Cursed Body's flavor type) since
	# Normal-type MOVES are outright immune (0x) against Ghost-type DEFENDERS — the same
	# pitfall M17b's Purifying Salt test hit; Cursed Body's mechanic has no type
	# restriction of its own, so any ordinary type pairing is fine here.
	var cb_holder := _make_mon("CBHolder", 50, [TypeChart.TYPE_NORMAL], 200)
	cb_holder.ability = _load_ability(130)
	var filler := _make_move(TypeChart.TYPE_NORMAL, 0, 20)
	filler.pp = 20
	cb_holder.add_move(filler)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm._force_roll = 100
	bm._force_cursed_body_roll = true
	var cb_disabled := [false]
	bm.disabled.connect(func(target: BattlePokemon, disabled_move: MoveData) -> void:
		if target == cb_attacker and disabled_move == atk_move:
			cb_disabled[0] = true)
	bm.start_battle(cb_attacker, cb_holder)
	_chk("S6.05 Cursed Body integration: attacker's move gets disabled after hitting the holder",
			cb_disabled[0] == true)


# ── Section 7: Toxic Debris ────────────────────────────────────────────────────

func _test_section_7_toxic_debris() -> void:
	var phys_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var spec_move := _make_move(TypeChart.TYPE_NORMAL, 1, 40)
	var toxic_debris := _make_mon("ToxicDebrisMon", 50, [TypeChart.TYPE_POISON])
	toxic_debris.ability = _load_ability(295)
	var attacker := _make_mon("Attacker", 50, [TypeChart.TYPE_NORMAL])
	var r1: Dictionary = AbilityManager.try_hit_reactive_effects(
			attacker, toxic_debris, phys_move, 10, toxic_debris.max_hp, false)
	_chk("S7.01 Toxic Debris: physical hit fires the flag", r1["toxic_debris_fired"] == true)
	var r1b: Dictionary = AbilityManager.try_hit_reactive_effects(
			attacker, toxic_debris, spec_move, 10, toxic_debris.max_hp, false)
	_chk("S7.02 Toxic Debris: special hit does NOT fire", r1b["toxic_debris_fired"] == false)

	# Full-battle integration: BattleManager sets a Toxic Spikes layer on the attacker's side.
	var atk_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, false)
	atk_move.pp = 20
	var td_attacker := _make_mon("TDAttacker", 50, [TypeChart.TYPE_NORMAL], 200)
	td_attacker.add_move(atk_move)
	var td_holder := _make_mon("TDHolder", 50, [TypeChart.TYPE_POISON], 200)
	td_holder.ability = _load_ability(295)
	var filler := _make_move(TypeChart.TYPE_NORMAL, 0, 20)
	filler.pp = 20
	td_holder.add_move(filler)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm._force_roll = 100
	var td_hazard_set := [false]
	bm.hazard_set.connect(func(side: int, hazard_name: String, layers: int) -> void:
		if hazard_name == "toxic_spikes" and side == 0 and layers == 1:
			td_hazard_set[0] = true)
	bm.start_battle(td_attacker, td_holder)
	_chk("S7.03 Toxic Debris integration: sets a Toxic Spikes layer on the attacker's side",
			td_hazard_set[0] == true)


# ── Section 8: Flower Gift ─────────────────────────────────────────────────────

func _test_section_8_flower_gift() -> void:
	var phys_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var spec_move := _make_move(TypeChart.TYPE_NORMAL, 1, 40)
	var def := _make_mon("Def", 50, [TypeChart.TYPE_NORMAL])
	var plain_atk := _make_mon("PlainAtk", 50, [TypeChart.TYPE_NORMAL])

	# Self Attack boost: sun active, physical move only.
	var fg_atk := _make_mon("FGAtk", 50, [TypeChart.TYPE_NORMAL])
	fg_atk.ability = _load_ability(122)
	var sun_phys := DamageCalculator.calculate(
			fg_atk, def, phys_move, 100, false, DamageCalculator.WEATHER_SUN)
	var sun_phys_baseline := DamageCalculator.calculate(
			plain_atk, def, phys_move, 100, false, DamageCalculator.WEATHER_SUN)
	_chk("S8.01 Flower Gift: self Attack boosted in sun (physical)",
			sun_phys["damage"] > sun_phys_baseline["damage"])
	var no_sun_phys := DamageCalculator.calculate(
			fg_atk, def, phys_move, 100, false, DamageCalculator.WEATHER_NONE)
	var no_sun_baseline := DamageCalculator.calculate(
			plain_atk, def, phys_move, 100, false, DamageCalculator.WEATHER_NONE)
	_chk("S8.02 Flower Gift: no Attack boost without sun",
			no_sun_phys["damage"] == no_sun_baseline["damage"])
	var sun_spec := DamageCalculator.calculate(
			fg_atk, def, spec_move, 100, false, DamageCalculator.WEATHER_SUN)
	var sun_spec_baseline := DamageCalculator.calculate(
			plain_atk, def, spec_move, 100, false, DamageCalculator.WEATHER_SUN)
	_chk("S8.03 Flower Gift: special moves NOT boosted (Attack-only)",
			sun_spec["damage"] == sun_spec_baseline["damage"])

	# Ally-shared Sp. Def boost: sun active, special move only, self OR ally.
	var fg_def := _make_mon("FGDef", 50, [TypeChart.TYPE_NORMAL])
	fg_def.ability = _load_ability(122)
	var plain_def := _make_mon("PlainDef", 50, [TypeChart.TYPE_NORMAL])
	var self_spdef_sun := DamageCalculator.calculate(
			plain_atk, fg_def, spec_move, 100, false, DamageCalculator.WEATHER_SUN)
	var self_spdef_baseline := DamageCalculator.calculate(
			plain_atk, plain_def, spec_move, 100, false, DamageCalculator.WEATHER_SUN)
	_chk("S8.04 Flower Gift: self Sp. Def reduces damage taken (special, sun)",
			self_spdef_sun["damage"] < self_spdef_baseline["damage"])
	var self_spdef_no_sun := DamageCalculator.calculate(
			plain_atk, fg_def, spec_move, 100, false, DamageCalculator.WEATHER_NONE)
	_chk("S8.05 Flower Gift: no Sp. Def reduction without sun",
			self_spdef_no_sun["damage"] == self_spdef_baseline["damage"])
	var self_phys_sun := DamageCalculator.calculate(
			plain_atk, fg_def, phys_move, 100, false, DamageCalculator.WEATHER_SUN)
	var self_phys_baseline := DamageCalculator.calculate(
			plain_atk, plain_def, phys_move, 100, false, DamageCalculator.WEATHER_SUN)
	_chk("S8.06 Flower Gift: physical moves NOT reduced (Sp. Def-only)",
			self_phys_sun["damage"] == self_phys_baseline["damage"])

	# Ally case: the DEFENDER's ally holds Flower Gift (defender itself has no ability).
	var fg_ally := _make_mon("FGAlly", 50, [TypeChart.TYPE_NORMAL])
	fg_ally.ability = _load_ability(122)
	var ally_spdef_sun := DamageCalculator.calculate(
			plain_atk, plain_def, spec_move, 100, false, DamageCalculator.WEATHER_SUN,
			false, false, -1, false, false, null, fg_ally)
	_chk("S8.07 Flower Gift (ally): reduces damage taken by the defender too",
			ally_spdef_sun["damage"] < self_spdef_baseline["damage"])


# ── Section 9: Slush Rush ──────────────────────────────────────────────────────

func _test_section_9_slush_rush() -> void:
	var slush_mon := _make_mon("SlushRushMon", 50, [TypeChart.TYPE_ICE], 80, 80, 80, 80, 80, 60)
	slush_mon.ability = _load_ability(202)
	var hail_speed: int = StatusManager.effective_speed(slush_mon, DamageCalculator.WEATHER_HAIL)
	var no_weather_speed: int = StatusManager.effective_speed(slush_mon, DamageCalculator.WEATHER_NONE)
	_chk("S9.01 Slush Rush: doubles Speed in hail", hail_speed == no_weather_speed * 2)
	var sun_speed: int = StatusManager.effective_speed(slush_mon, DamageCalculator.WEATHER_SUN)
	_chk("S9.02 Slush Rush: no boost outside hail", sun_speed == no_weather_speed)

	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 60)
	var plain_hail_speed: int = StatusManager.effective_speed(plain_mon, DamageCalculator.WEATHER_HAIL)
	var plain_no_weather_speed: int = StatusManager.effective_speed(plain_mon, DamageCalculator.WEATHER_NONE)
	_chk("S9.03 No ability: hail does NOT double Speed", plain_hail_speed == plain_no_weather_speed)


# ── Section 10: Cheek Pouch, Ripen ────────────────────────────────────────────

func _test_section_10_cheek_pouch_ripen() -> void:
	var cheek_pouch := _make_mon("CheekPouchMon", 50, [TypeChart.TYPE_NORMAL], 160)
	cheek_pouch.ability = _load_ability(167)
	cheek_pouch.current_hp = 100
	_chk("S10.01 Cheek Pouch: heals maxHP/3",
			AbilityManager.cheek_pouch_heal(cheek_pouch) == cheek_pouch.max_hp / 3)
	var cheek_pouch_full := _make_mon("CheekPouchFull", 50, [TypeChart.TYPE_NORMAL], 160)
	cheek_pouch_full.ability = _load_ability(167)
	_chk("S10.02 Cheek Pouch: does NOT heal at full HP",
			AbilityManager.cheek_pouch_heal(cheek_pouch_full) == 0)
	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL], 160)
	plain_mon.current_hp = 100
	_chk("S10.03 No ability: no Cheek Pouch heal", AbilityManager.cheek_pouch_heal(plain_mon) == 0)

	# Ripen: doubles the resist berry's effectiveness (0.25x instead of 0.5x).
	var occa_berry := ItemData.new()
	occa_berry.hold_effect = ItemManager.HOLD_EFFECT_RESIST_BERRY
	occa_berry.hold_effect_param = TypeChart.TYPE_FIRE
	var fire_move := _make_move(TypeChart.TYPE_FIRE, 0, 40)
	var ripen_def := _make_mon("RipenDef", 50, [TypeChart.TYPE_GRASS])
	ripen_def.ability = _load_ability(247)
	ripen_def.held_item = occa_berry
	var plain_berry_def := _make_mon("PlainBerryDef", 50, [TypeChart.TYPE_GRASS])
	plain_berry_def.held_item = occa_berry
	var ripen_mod: int = ItemManager.defender_item_modifier_uq412(ripen_def, fire_move, 2.0)
	var plain_mod: int = ItemManager.defender_item_modifier_uq412(plain_berry_def, fire_move, 2.0)
	_chk("S10.04 Ripen: resist berry reduction is stronger (0.25x vs 0.5x)",
			ripen_mod < plain_mod)
	_chk("S10.05 Ripen: exact 0.25x multiplier", ripen_mod == 1024)


# ── Section 11: Hospitality ────────────────────────────────────────────────────

func _test_section_11_hospitality() -> void:
	var hospitality := _make_mon("HospitalityMon", 50, [TypeChart.TYPE_NORMAL])
	hospitality.ability = _load_ability(299)
	var ally := _make_mon("Ally", 50, [TypeChart.TYPE_NORMAL], 160)
	ally.current_hp = 100
	_chk("S11.01 Hospitality: heals the ally maxHP/4",
			AbilityManager.try_switch_in_ally_heal(hospitality, ally) == ally.max_hp / 4)

	var ally_full := _make_mon("AllyFull", 50, [TypeChart.TYPE_NORMAL], 160)
	_chk("S11.02 Hospitality: does NOT heal an ally already at max HP",
			AbilityManager.try_switch_in_ally_heal(hospitality, ally_full) == 0)

	_chk("S11.03 Hospitality: no ally (singles) → no heal",
			AbilityManager.try_switch_in_ally_heal(hospitality, null) == 0)

	var ally_fainted := _make_mon("AllyFainted", 50, [TypeChart.TYPE_NORMAL], 160)
	ally_fainted.fainted = true
	_chk("S11.04 Hospitality: fainted ally → no heal",
			AbilityManager.try_switch_in_ally_heal(hospitality, ally_fainted) == 0)

	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	var ally2 := _make_mon("Ally2", 50, [TypeChart.TYPE_NORMAL], 160)
	ally2.current_hp = 100
	_chk("S11.05 No ability: no Hospitality heal",
			AbilityManager.try_switch_in_ally_heal(plain_mon, ally2) == 0)


# ── Section 12: Cosmetic no-op abilities — Anticipation, Forewarn, Frisk ──────

func _test_section_12_cosmetic_no_ops() -> void:
	var anticipation := _load_ability(107)
	_chk("S12.01 Anticipation: registered with correct id", anticipation.ability_id == 107)
	_chk("S12.02 Anticipation: flagged cosmetic/info-only",
			AbilityManager.ABILITY_ANTICIPATION in AbilityManager.ABILITY_COSMETIC_INFO_ONLY)

	var forewarn := _load_ability(108)
	_chk("S12.03 Forewarn: registered with correct id", forewarn.ability_id == 108)
	_chk("S12.04 Forewarn: flagged cosmetic/info-only",
			AbilityManager.ABILITY_FOREWARN in AbilityManager.ABILITY_COSMETIC_INFO_ONLY)

	var frisk := _load_ability(119)
	_chk("S12.05 Frisk: registered with correct id", frisk.ability_id == 119)
	_chk("S12.06 Frisk: flagged cosmetic/info-only",
			AbilityManager.ABILITY_FRISK in AbilityManager.ABILITY_COSMETIC_INFO_ONLY)

	# Negative: none of these three interfere with an ordinary damage calc or stat
	# change — holding one shouldn't silently change unrelated engine behavior.
	var move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var anticipation_mon := _make_mon("AnticipationMon", 50, [TypeChart.TYPE_NORMAL])
	anticipation_mon.ability = anticipation
	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	var atk := _make_mon("Atk", 50, [TypeChart.TYPE_NORMAL])
	var result := DamageCalculator.calculate(atk, anticipation_mon, move, 100, false)
	var baseline := DamageCalculator.calculate(atk, plain_mon, move, 100, false)
	_chk("S12.07 Anticipation: does not alter ordinary damage calc",
			result["damage"] == baseline["damage"])
