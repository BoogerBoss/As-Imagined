extends Node

# M17a test suite — Tier A move effects: damage-pipeline modifiers, no new infrastructure.
#
# Scope: the 32 abilities locked in docs/decisions.md [M17a] after cross-checking
# docs/m17_recon.md Section 11's proposal against Section 13's exclusions (Shadow Shield/
# Prism Armor/Neuroforce/Full Metal Body/Transistor/Dragon's Maw removed — all
# legendary/mythical-exclusive).
#
# Sections:
#   1. Ability data spot-checks (representative subset of the 32 .tres files)
#   2. attack_modifier_uq412 additions: Overgrow/Blaze/Torrent/Swarm, Guts, Hustle,
#      Defeatist, Rocky Payload
#   3. defense_damage_modifier_uq412 additions: Marvel Scale, Fur Coat, Multiscale,
#      Filter/Solid Rock, Ice Scales, Heatproof
#   4. Crit interactions: Battle Armor/Shell Armor (blocks crit), Sniper (crit ×1.5)
#   5. Tinted Lens (not-very-effective ×2.0)
#   6. Adaptability (STAB ×2.0 instead of ×1.5)
#   7. Rock Head (blocks standard move recoil)
#   8. No Guard (always hits, either side)
#   9. Compound Eyes / Hustle accuracy modifiers
#  10. move_power_modifier_uq412 additions: Toxic Boost, Flare Boost, Sand Force,
#      Tough Claws, Steelworker, Steely Spirit (self + ally), Battery, Power Spot
#  11. Guts burn-halving exemption
#
# Every functional section includes a negative case confirming the ability does NOT
# apply when its trigger condition isn't met, per the M16-established discriminator
# pattern.
#
# Ground truth: pokeemerald_expansion src/battle_util.c, src/battle_move_resolution.c

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_attack_stat_modifiers()
	_test_section_3_defense_modifiers()
	_test_section_4_crit_interactions()
	_test_section_5_tinted_lens()
	_test_section_6_adaptability()
	_test_section_7_rock_head()
	_test_section_8_no_guard()
	_test_section_9_accuracy_modifiers()
	_test_section_10_power_modifiers()
	_test_section_11_guts_burn_exemption()

	var total := _pass + _fail
	print("m17a_test: %d/%d passed" % [_pass, total])
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
	var overgrow := _load_ability(65)
	_chk("S1.01 Overgrow id=65",       overgrow.ability_id == 65)
	_chk("S1.02 Overgrow name",        overgrow.ability_name == "Overgrow")

	var battle_armor := _load_ability(4)
	_chk("S1.03 Battle Armor id=4",    battle_armor.ability_id == 4)

	var no_guard := _load_ability(99)
	_chk("S1.04 No Guard id=99",       no_guard.ability_id == 99)

	var adaptability := _load_ability(91)
	_chk("S1.05 Adaptability id=91",   adaptability.ability_id == 91)

	var steely_spirit := _load_ability(252)
	_chk("S1.06 Steely Spirit id=252", steely_spirit.ability_id == 252)
	_chk("S1.07 Steely Spirit name",   steely_spirit.ability_name == "Steely Spirit")

	var rocky_payload := _load_ability(276)
	_chk("S1.08 Rocky Payload id=276", rocky_payload.ability_id == 276)

	var guts := _load_ability(62)
	_chk("S1.09 Guts id=62",           guts.ability_id == 62)

	var hustle := _load_ability(55)
	_chk("S1.10 Hustle id=55",         hustle.ability_id == 55)


# ── Section 2: attack_modifier_uq412 additions ───────────────────────────────
# Overgrow/Blaze/Torrent/Swarm (type match + hp<=1/3 → ×1.5), Guts (statused+physical
# → ×1.5), Hustle (physical → ×1.5), Defeatist (hp<=1/2 → ×0.5), Rocky Payload
# (Rock-type → ×1.5, unconditional).

func _test_section_2_attack_stat_modifiers() -> void:
	var grass_move := _make_move(TypeChart.TYPE_GRASS, 0, 40)  # physical, avoid STAB
	var atk := _make_mon("Attacker", 50, [TypeChart.TYPE_NORMAL])
	var def := _make_mon("Defender", 50, [TypeChart.TYPE_NORMAL])
	atk.ability = _load_ability(65)  # Overgrow

	# Baseline at full HP — should NOT trigger (hp > maxHP/3).
	var no_trigger := DamageCalculator.calculate(atk, def, grass_move, 100, false)
	# Drop to 1/3 HP or below — should trigger ×1.5.
	atk.current_hp = atk.max_hp / 3
	var triggered := DamageCalculator.calculate(atk, def, grass_move, 100, false)
	_chk("S2.01 Overgrow: low HP + matching type boosts damage",
			triggered["damage"] > no_trigger["damage"])

	# Negative: full HP, no boost — same as an ability-less attacker.
	atk.current_hp = atk.max_hp
	var plain_atk := _make_mon("Plain", 50, [TypeChart.TYPE_NORMAL])
	var plain_result := DamageCalculator.calculate(plain_atk, def, grass_move, 100, false)
	_chk("S2.02 Overgrow: full HP does NOT boost (matches no-ability baseline)",
			no_trigger["damage"] == plain_result["damage"])

	# Negative: low HP but non-matching type (Fire move) — Overgrow should not fire.
	var fire_move := _make_move(TypeChart.TYPE_FIRE, 0, 40)
	atk.current_hp = atk.max_hp / 3
	var wrong_type := DamageCalculator.calculate(atk, def, fire_move, 100, false)
	var plain_fire := DamageCalculator.calculate(plain_atk, def, fire_move, 100, false)
	_chk("S2.03 Overgrow: non-Grass move unaffected at low HP",
			wrong_type["damage"] == plain_fire["damage"])

	# Blaze/Torrent/Swarm — one spot-check each (same shape as Overgrow, already
	# fully exercised above).
	var blaze_atk := _make_mon("BlazeMon", 50, [TypeChart.TYPE_NORMAL])
	blaze_atk.ability = _load_ability(66)
	blaze_atk.current_hp = blaze_atk.max_hp / 3
	var blaze_result := DamageCalculator.calculate(blaze_atk, def, fire_move, 100, false)
	var plain_fire2 := DamageCalculator.calculate(plain_atk, def, fire_move, 100, false)
	_chk("S2.04 Blaze: low HP + Fire move boosts damage",
			blaze_result["damage"] > plain_fire2["damage"])

	var water_move := _make_move(TypeChart.TYPE_WATER, 1, 40)
	var torrent_atk := _make_mon("TorrentMon", 50, [TypeChart.TYPE_NORMAL])
	torrent_atk.ability = _load_ability(67)
	torrent_atk.current_hp = torrent_atk.max_hp / 3
	var torrent_result := DamageCalculator.calculate(torrent_atk, def, water_move, 100, false)
	var plain_water := DamageCalculator.calculate(plain_atk, def, water_move, 100, false)
	_chk("S2.05 Torrent: low HP + Water move boosts damage",
			torrent_result["damage"] > plain_water["damage"])

	var bug_move := _make_move(TypeChart.TYPE_BUG, 0, 40)
	var swarm_atk := _make_mon("SwarmMon", 50, [TypeChart.TYPE_NORMAL])
	swarm_atk.ability = _load_ability(68)
	swarm_atk.current_hp = swarm_atk.max_hp / 3
	var swarm_result := DamageCalculator.calculate(swarm_atk, def, bug_move, 100, false)
	var plain_bug := DamageCalculator.calculate(plain_atk, def, bug_move, 100, false)
	_chk("S2.06 Swarm: low HP + Bug move boosts damage",
			swarm_result["damage"] > plain_bug["damage"])

	# Guts: statused + physical → ×1.5. Negative: statused + special does NOT trigger.
	var guts_atk := _make_mon("GutsMon", 50, [TypeChart.TYPE_NORMAL])
	guts_atk.ability = _load_ability(62)
	var normal_phys := _make_move(TypeChart.TYPE_FIGHTING, 0, 40)
	var normal_spec := _make_move(TypeChart.TYPE_FIGHTING, 1, 40)
	guts_atk.status = BattlePokemon.STATUS_PARALYSIS
	var guts_phys := DamageCalculator.calculate(guts_atk, def, normal_phys, 100, false)
	var plain_phys := DamageCalculator.calculate(plain_atk, def, normal_phys, 100, false)
	_chk("S2.07 Guts: statused + physical boosts damage",
			guts_phys["damage"] > plain_phys["damage"])
	var guts_spec := DamageCalculator.calculate(guts_atk, def, normal_spec, 100, false)
	var plain_spec := DamageCalculator.calculate(plain_atk, def, normal_spec, 100, false)
	_chk("S2.08 Guts: statused + SPECIAL does NOT boost",
			guts_spec["damage"] == plain_spec["damage"])
	guts_atk.status = BattlePokemon.STATUS_NONE
	var guts_unstatused := DamageCalculator.calculate(guts_atk, def, normal_phys, 100, false)
	_chk("S2.09 Guts: no status does NOT boost",
			guts_unstatused["damage"] == plain_phys["damage"])

	# Hustle: physical → ×1.5 attack (accuracy piece tested in Section 9).
	var hustle_atk := _make_mon("HustleMon", 50, [TypeChart.TYPE_NORMAL])
	hustle_atk.ability = _load_ability(55)
	var hustle_phys := DamageCalculator.calculate(hustle_atk, def, normal_phys, 100, false)
	_chk("S2.10 Hustle: physical move boosts damage",
			hustle_phys["damage"] > plain_phys["damage"])
	var hustle_spec := DamageCalculator.calculate(hustle_atk, def, normal_spec, 100, false)
	_chk("S2.11 Hustle: special move does NOT boost damage",
			hustle_spec["damage"] == plain_spec["damage"])

	# Defeatist: hp<=1/2 → ×0.5, any category.
	var defeatist_atk := _make_mon("DefeatistMon", 50, [TypeChart.TYPE_NORMAL])
	defeatist_atk.ability = _load_ability(129)
	var full_hp_result := DamageCalculator.calculate(defeatist_atk, def, normal_phys, 100, false)
	_chk("S2.12 Defeatist: full HP does NOT reduce damage",
			full_hp_result["damage"] == plain_phys["damage"])
	defeatist_atk.current_hp = defeatist_atk.max_hp / 2
	var half_hp_result := DamageCalculator.calculate(defeatist_atk, def, normal_phys, 100, false)
	_chk("S2.13 Defeatist: HP at half or below reduces damage",
			half_hp_result["damage"] < plain_phys["damage"])

	# Rocky Payload: Rock-type → ×1.5, unconditional (no HP/status gate).
	var rock_move := _make_move(TypeChart.TYPE_ROCK, 0, 40)
	var rocky_atk := _make_mon("RockyMon", 50, [TypeChart.TYPE_NORMAL])
	rocky_atk.ability = _load_ability(276)
	var rocky_result := DamageCalculator.calculate(rocky_atk, def, rock_move, 100, false)
	var plain_rock := DamageCalculator.calculate(plain_atk, def, rock_move, 100, false)
	_chk("S2.14 Rocky Payload: Rock-type move boosts damage",
			rocky_result["damage"] > plain_rock["damage"])
	var rocky_wrong_type := DamageCalculator.calculate(rocky_atk, def, normal_phys, 100, false)
	_chk("S2.15 Rocky Payload: non-Rock move does NOT boost",
			rocky_wrong_type["damage"] == plain_phys["damage"])


# ── Section 3: defense_damage_modifier_uq412 additions ───────────────────────
# Marvel Scale (statused + physical → ×1.5 def), Fur Coat (physical → ×0.5 dmg taken),
# Multiscale (max HP → ×0.5), Filter/Solid Rock (super-effective → ×0.75), Ice Scales
# (special → ×0.5), Heatproof (Fire-type → ×0.5).

func _test_section_3_defense_modifiers() -> void:
	var atk := _make_mon("Attacker", 50, [TypeChart.TYPE_NORMAL])
	var phys_move := _make_move(TypeChart.TYPE_FIGHTING, 0, 40)
	var spec_move := _make_move(TypeChart.TYPE_FIGHTING, 1, 40)

	# Marvel Scale
	var marvel_def := _make_mon("MarvelMon", 50, [TypeChart.TYPE_NORMAL])
	var plain_def := _make_mon("PlainDef", 50, [TypeChart.TYPE_NORMAL])
	marvel_def.ability = _load_ability(63)
	var no_status := DamageCalculator.calculate(atk, marvel_def, phys_move, 100, false)
	var baseline := DamageCalculator.calculate(atk, plain_def, phys_move, 100, false)
	_chk("S3.01 Marvel Scale: no status does NOT reduce damage taken",
			no_status["damage"] == baseline["damage"])
	marvel_def.status = BattlePokemon.STATUS_BURN
	var statused := DamageCalculator.calculate(atk, marvel_def, phys_move, 100, false)
	_chk("S3.02 Marvel Scale: statused + physical reduces damage taken",
			statused["damage"] < baseline["damage"])
	var statused_spec := DamageCalculator.calculate(atk, marvel_def, spec_move, 100, false)
	var baseline_spec := DamageCalculator.calculate(atk, plain_def, spec_move, 100, false)
	_chk("S3.03 Marvel Scale: statused + SPECIAL does NOT reduce damage taken",
			statused_spec["damage"] == baseline_spec["damage"])

	# Fur Coat: physical only, unconditional.
	var fur_def := _make_mon("FurMon", 50, [TypeChart.TYPE_NORMAL])
	fur_def.ability = _load_ability(169)
	var fur_phys := DamageCalculator.calculate(atk, fur_def, phys_move, 100, false)
	_chk("S3.04 Fur Coat: physical move damage taken halved",
			fur_phys["damage"] < baseline["damage"])
	var fur_spec := DamageCalculator.calculate(atk, fur_def, spec_move, 100, false)
	_chk("S3.05 Fur Coat: special move NOT reduced",
			fur_spec["damage"] == baseline_spec["damage"])

	# Multiscale: max HP only.
	var multi_def := _make_mon("MultiMon", 50, [TypeChart.TYPE_NORMAL])
	multi_def.ability = _load_ability(136)
	var multi_full := DamageCalculator.calculate(atk, multi_def, phys_move, 100, false)
	_chk("S3.06 Multiscale: at max HP, damage taken halved",
			multi_full["damage"] < baseline["damage"])
	multi_def.current_hp -= 1
	var multi_damaged := DamageCalculator.calculate(atk, multi_def, phys_move, 100, false)
	_chk("S3.07 Multiscale: below max HP, no reduction",
			multi_damaged["damage"] == baseline["damage"])

	# Filter/Solid Rock: super-effective only. Use a Fire move vs a Grass/Bug-type
	# defender (double super-effective, 4x) to guarantee effectiveness >= 2.0.
	var fire_move := _make_move(TypeChart.TYPE_FIRE, 1, 40)
	var filter_def := _make_mon("FilterMon", 50, [TypeChart.TYPE_GRASS, TypeChart.TYPE_BUG])
	filter_def.ability = _load_ability(111)
	var plain_se_def := _make_mon("PlainSEDef", 50, [TypeChart.TYPE_GRASS, TypeChart.TYPE_BUG])
	var filter_result := DamageCalculator.calculate(atk, filter_def, fire_move, 100, false)
	var se_baseline := DamageCalculator.calculate(atk, plain_se_def, fire_move, 100, false)
	_chk("S3.08 Filter: super-effective hit reduced",
			filter_result["damage"] < se_baseline["damage"])
	# Negative: neutral-effectiveness hit (Normal move vs Normal-type) unaffected.
	var normal_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var filter_def2 := _make_mon("FilterMon2", 50, [TypeChart.TYPE_NORMAL])
	filter_def2.ability = _load_ability(111)
	var plain_neutral := _make_mon("PlainNeutral", 50, [TypeChart.TYPE_NORMAL])
	var filter_neutral := DamageCalculator.calculate(atk, filter_def2, normal_move, 100, false)
	var neutral_baseline := DamageCalculator.calculate(atk, plain_neutral, normal_move, 100, false)
	_chk("S3.09 Filter: neutral-effectiveness hit NOT reduced",
			filter_neutral["damage"] == neutral_baseline["damage"])

	var solid_rock_def := _make_mon("SolidRockMon", 50, [TypeChart.TYPE_GRASS, TypeChart.TYPE_BUG])
	solid_rock_def.ability = _load_ability(116)
	var solid_rock_result := DamageCalculator.calculate(atk, solid_rock_def, fire_move, 100, false)
	_chk("S3.10 Solid Rock: super-effective hit reduced",
			solid_rock_result["damage"] < se_baseline["damage"])

	# Ice Scales: special only.
	var ice_def := _make_mon("IceMon", 50, [TypeChart.TYPE_NORMAL])
	ice_def.ability = _load_ability(246)
	var ice_spec := DamageCalculator.calculate(atk, ice_def, spec_move, 100, false)
	_chk("S3.11 Ice Scales: special move damage taken halved",
			ice_spec["damage"] < baseline_spec["damage"])
	var ice_phys := DamageCalculator.calculate(atk, ice_def, phys_move, 100, false)
	_chk("S3.12 Ice Scales: physical move NOT reduced",
			ice_phys["damage"] == baseline["damage"])

	# Heatproof: Fire-type moves only.
	var heat_def := _make_mon("HeatMon", 50, [TypeChart.TYPE_NORMAL])
	heat_def.ability = _load_ability(85)
	var plain_fire_def := _make_mon("PlainFireDef", 50, [TypeChart.TYPE_NORMAL])
	var heat_result := DamageCalculator.calculate(atk, heat_def, fire_move, 100, false)
	var fire_baseline := DamageCalculator.calculate(atk, plain_fire_def, fire_move, 100, false)
	_chk("S3.13 Heatproof: Fire-type move damage taken halved",
			heat_result["damage"] < fire_baseline["damage"])
	var heat_normal := DamageCalculator.calculate(atk, heat_def, normal_move, 100, false)
	var plain_normal_result := DamageCalculator.calculate(atk, plain_fire_def, normal_move, 100, false)
	_chk("S3.14 Heatproof: non-Fire move NOT reduced",
			heat_normal["damage"] == plain_normal_result["damage"])


# ── Section 4: Crit interactions — Battle Armor/Shell Armor, Sniper ──────────

func _test_section_4_crit_interactions() -> void:
	var atk := _make_mon("Attacker", 50, [TypeChart.TYPE_NORMAL])
	var move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)

	# Battle Armor blocks even a FORCED crit.
	var armor_def := _make_mon("ArmorMon", 50, [TypeChart.TYPE_NORMAL])
	armor_def.ability = _load_ability(4)
	var forced_crit_result := DamageCalculator.calculate(atk, armor_def, move, 100, true)
	_chk("S4.01 Battle Armor: forced crit is blocked",
			forced_crit_result["is_crit"] == false)

	var shell_def := _make_mon("ShellMon", 50, [TypeChart.TYPE_NORMAL])
	shell_def.ability = _load_ability(75)
	var shell_result := DamageCalculator.calculate(atk, shell_def, move, 100, true)
	_chk("S4.02 Shell Armor: forced crit is blocked",
			shell_result["is_crit"] == false)

	# Negative: an ability-less defender DOES crit when forced.
	var plain_def := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	var plain_result := DamageCalculator.calculate(atk, plain_def, move, 100, true)
	_chk("S4.03 No crit-blocking ability: forced crit goes through",
			plain_result["is_crit"] == true)

	# Sniper: crit → ×1.5 damage on top of the crit multiplier.
	var sniper_atk := _make_mon("SniperMon", 50, [TypeChart.TYPE_NORMAL])
	sniper_atk.ability = _load_ability(97)
	var sniper_crit := DamageCalculator.calculate(sniper_atk, plain_def, move, 100, true)
	var plain_crit := DamageCalculator.calculate(atk, plain_def, move, 100, true)
	_chk("S4.04 Sniper: crit damage boosted beyond the plain crit multiplier",
			sniper_crit["damage"] > plain_crit["damage"])
	var sniper_nocrit := DamageCalculator.calculate(sniper_atk, plain_def, move, 100, false)
	var plain_nocrit := DamageCalculator.calculate(atk, plain_def, move, 100, false)
	_chk("S4.05 Sniper: non-crit hit NOT boosted",
			sniper_nocrit["damage"] == plain_nocrit["damage"])


# ── Section 5: Tinted Lens (not-very-effective → ×2.0) ───────────────────────

func _test_section_5_tinted_lens() -> void:
	# Water move vs Grass-type defender = not-very-effective (0.5×).
	var water_move := _make_move(TypeChart.TYPE_WATER, 1, 40)
	var tinted_atk := _make_mon("TintedMon", 50, [TypeChart.TYPE_NORMAL])
	tinted_atk.ability = _load_ability(110)
	var plain_atk := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	var grass_def := _make_mon("GrassMon", 50, [TypeChart.TYPE_GRASS])

	var tinted_result := DamageCalculator.calculate(tinted_atk, grass_def, water_move, 100, false)
	var plain_result := DamageCalculator.calculate(plain_atk, grass_def, water_move, 100, false)
	_chk("S5.01 Tinted Lens: not-very-effective hit boosted",
			tinted_result["damage"] > plain_result["damage"])

	# Negative: neutral effectiveness (Water vs Normal) unaffected.
	var normal_def := _make_mon("NormalMon", 50, [TypeChart.TYPE_NORMAL])
	var tinted_neutral := DamageCalculator.calculate(tinted_atk, normal_def, water_move, 100, false)
	var plain_neutral := DamageCalculator.calculate(plain_atk, normal_def, water_move, 100, false)
	_chk("S5.02 Tinted Lens: neutral-effectiveness hit NOT boosted",
			tinted_neutral["damage"] == plain_neutral["damage"])


# ── Section 6: Adaptability (STAB ×2.0 instead of ×1.5) ──────────────────────

func _test_section_6_adaptability() -> void:
	var move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var def := _make_mon("Defender", 50, [TypeChart.TYPE_NORMAL])

	var adapt_atk := _make_mon("AdaptMon", 50, [TypeChart.TYPE_NORMAL])
	adapt_atk.ability = _load_ability(91)
	var plain_atk := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])

	var adapt_result := DamageCalculator.calculate(adapt_atk, def, move, 100, false)
	var plain_result := DamageCalculator.calculate(plain_atk, def, move, 100, false)
	_chk("S6.01 Adaptability: same-type move boosted beyond normal STAB",
			adapt_result["damage"] > plain_result["damage"])

	# Negative: a move that doesn't match the attacker's type gets no STAB at all,
	# so Adaptability has nothing to boost.
	var off_type_move := _make_move(TypeChart.TYPE_WATER, 1, 40)
	var adapt_offtype := DamageCalculator.calculate(adapt_atk, def, off_type_move, 100, false)
	var plain_offtype := DamageCalculator.calculate(plain_atk, def, off_type_move, 100, false)
	_chk("S6.02 Adaptability: non-STAB move unaffected",
			adapt_offtype["damage"] == plain_offtype["damage"])


# ── Section 7: Rock Head (blocks standard move recoil) ───────────────────────
# Uses AbilityManager.blocks_recoil directly plus a full BattleManager battle to
# confirm the recoil gate actually fires (or doesn't) during real move execution.

func _test_section_7_rock_head() -> void:
	var rock_head_mon := _make_mon("RockHeadMon", 50, [TypeChart.TYPE_NORMAL])
	rock_head_mon.ability = _load_ability(69)
	_chk("S7.01 blocks_recoil: Rock Head returns true",
			AbilityManager.blocks_recoil(rock_head_mon) == true)

	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	_chk("S7.02 blocks_recoil: no ability returns false",
			AbilityManager.blocks_recoil(plain_mon) == false)

	# Full-battle confirmation: a recoil move should NOT damage a Rock Head attacker,
	# but SHOULD damage an ability-less attacker. Snapshot via recoil_damage signal
	# per CLAUDE.md's testing convention (never read post-battle state directly).
	var recoil_move := MoveData.new()
	recoil_move.move_name = "TestRecoilMove"
	recoil_move.type = TypeChart.TYPE_NORMAL
	recoil_move.category = 0
	recoil_move.power = 40
	recoil_move.accuracy = 100
	recoil_move.pp = 5
	recoil_move.recoil_percent = 25

	var atk1 := _make_mon("RockHeadAtk", 50, [TypeChart.TYPE_NORMAL])
	atk1.ability = _load_ability(69)
	atk1.add_move(recoil_move)
	var def1 := _make_mon("Def1", 50, [TypeChart.TYPE_NORMAL], 200)
	def1.add_move(recoil_move)

	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1._force_hit = true
	# Array wrapper — GDScript lambdas capture outer scalars by value, not by
	# reference, so a plain `var rock_head_recoil_fired := false` mutated inside the
	# lambda would never be visible out here (see memory: lambda scalar capture gotcha).
	var rock_head_recoil_fired := [false]
	bm1.recoil_damage.connect(func(mon: BattlePokemon, _amount: int) -> void:
		if mon == atk1:
			rock_head_recoil_fired[0] = true)
	bm1.start_battle(atk1, def1)
	_chk("S7.03 Rock Head: attacker takes NO recoil damage (signal never fires)",
			rock_head_recoil_fired[0] == false)

	var atk2 := _make_mon("PlainAtk", 50, [TypeChart.TYPE_NORMAL])
	atk2.add_move(recoil_move)
	var def2 := _make_mon("Def2", 50, [TypeChart.TYPE_NORMAL], 200)
	def2.add_move(recoil_move)

	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2._force_hit = true
	var recoil_taken := [0]
	bm2.recoil_damage.connect(func(mon: BattlePokemon, amount: int) -> void:
		if mon == atk2 and recoil_taken[0] == 0:
			recoil_taken[0] = amount)
	bm2.start_battle(atk2, def2)
	_chk("S7.04 No Rock Head: attacker DOES take recoil damage",
			recoil_taken[0] > 0)


# ── Section 8: No Guard (always hits, either side) ───────────────────────────

func _test_section_8_no_guard() -> void:
	var atk := _make_mon("Attacker", 50, [TypeChart.TYPE_NORMAL])
	var def := _make_mon("Defender", 50, [TypeChart.TYPE_NORMAL])
	_chk("S8.01 bypasses_accuracy_check: neither has No Guard → false",
			AbilityManager.bypasses_accuracy_check(atk, def) == false)

	var no_guard_atk := _make_mon("NoGuardAtk", 50, [TypeChart.TYPE_NORMAL])
	no_guard_atk.ability = _load_ability(99)
	_chk("S8.02 bypasses_accuracy_check: attacker has No Guard → true",
			AbilityManager.bypasses_accuracy_check(no_guard_atk, def) == true)

	var no_guard_def := _make_mon("NoGuardDef", 50, [TypeChart.TYPE_NORMAL])
	no_guard_def.ability = _load_ability(99)
	_chk("S8.03 bypasses_accuracy_check: defender has No Guard → true",
			AbilityManager.bypasses_accuracy_check(atk, no_guard_def) == true)

	# A move with 0% accuracy would always miss on the roll; No Guard forces a hit
	# even then (deterministic proof it truly bypasses the roll, not just boosts it).
	var never_hits := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 1)
	var hit_count := 0
	for i in range(20):
		if StatusManager.check_accuracy(no_guard_atk, def, never_hits, null):
			hit_count += 1
	_chk("S8.04 No Guard: 1%-accuracy move always hits over repeated rolls",
			hit_count == 20)

	# Negative: without No Guard, a 1%-accuracy move essentially never hits over
	# the same number of rolls (probabilistically indistinguishable from "not always").
	var plain_atk := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	var plain_hit_count := 0
	for i in range(20):
		if StatusManager.check_accuracy(plain_atk, def, never_hits, null):
			plain_hit_count += 1
	_chk("S8.05 No No Guard: 1%-accuracy move does NOT always hit",
			plain_hit_count < 20)


# ── Section 9: Compound Eyes / Hustle accuracy modifiers ─────────────────────

func _test_section_9_accuracy_modifiers() -> void:
	var compound_atk := _make_mon("CompoundMon", 50, [TypeChart.TYPE_NORMAL])
	compound_atk.ability = _load_ability(14)
	var move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	_chk("S9.01 Compound Eyes: accuracy_modifier_percent = 130",
			AbilityManager.accuracy_modifier_percent(compound_atk, move) == 130)

	var hustle_atk := _make_mon("HustleMon", 50, [TypeChart.TYPE_NORMAL])
	hustle_atk.ability = _load_ability(55)
	_chk("S9.02 Hustle: accuracy_modifier_percent = 80 for physical",
			AbilityManager.accuracy_modifier_percent(hustle_atk, move) == 80)

	var spec_move := _make_move(TypeChart.TYPE_NORMAL, 1, 40)
	_chk("S9.03 Hustle: accuracy_modifier_percent = 100 for special (no accuracy loss)",
			AbilityManager.accuracy_modifier_percent(hustle_atk, spec_move) == 100)

	var plain_atk := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	_chk("S9.04 No ability: accuracy_modifier_percent = 100",
			AbilityManager.accuracy_modifier_percent(plain_atk, move) == 100)


# ── Section 10: move_power_modifier_uq412 additions ──────────────────────────
# Toxic Boost, Flare Boost, Sand Force, Tough Claws, Steelworker, Steely Spirit
# (self + ally), Battery, Power Spot.

func _test_section_10_power_modifiers() -> void:
	var def := _make_mon("Defender", 50, [TypeChart.TYPE_NORMAL])
	var plain_atk := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	var phys_move := _make_move(TypeChart.TYPE_FIGHTING, 0, 40)
	var spec_move := _make_move(TypeChart.TYPE_FIGHTING, 1, 40)

	# Toxic Boost: poisoned + physical.
	var toxic_atk := _make_mon("ToxicBoostMon", 50, [TypeChart.TYPE_NORMAL])
	toxic_atk.ability = _load_ability(137)
	var plain_phys := DamageCalculator.calculate(plain_atk, def, phys_move, 100, false)
	var toxic_unstatused := DamageCalculator.calculate(toxic_atk, def, phys_move, 100, false)
	_chk("S10.01 Toxic Boost: no status does NOT boost",
			toxic_unstatused["damage"] == plain_phys["damage"])
	toxic_atk.status = BattlePokemon.STATUS_POISON
	var toxic_poisoned := DamageCalculator.calculate(toxic_atk, def, phys_move, 100, false)
	_chk("S10.02 Toxic Boost: poisoned + physical boosts damage",
			toxic_poisoned["damage"] > plain_phys["damage"])
	var toxic_spec_result := DamageCalculator.calculate(toxic_atk, def, spec_move, 100, false)
	var plain_spec := DamageCalculator.calculate(plain_atk, def, spec_move, 100, false)
	_chk("S10.03 Toxic Boost: poisoned + SPECIAL does NOT boost",
			toxic_spec_result["damage"] == plain_spec["damage"])

	# Flare Boost: burned + special. The physical-move negative case compares against
	# a BURNED-but-ability-less baseline (not the fully-plain baseline) since burn's
	# own physical-damage-halving is a separate, unrelated mechanic that would
	# otherwise confound the comparison.
	var flare_atk := _make_mon("FlareBoostMon", 50, [TypeChart.TYPE_NORMAL])
	flare_atk.ability = _load_ability(138)
	flare_atk.status = BattlePokemon.STATUS_BURN
	var flare_spec := DamageCalculator.calculate(flare_atk, def, spec_move, 100, false)
	_chk("S10.04 Flare Boost: burned + special boosts damage",
			flare_spec["damage"] > plain_spec["damage"])
	var burned_plain_atk := _make_mon("BurnedPlainMon", 50, [TypeChart.TYPE_NORMAL])
	burned_plain_atk.status = BattlePokemon.STATUS_BURN
	var burned_plain_phys := DamageCalculator.calculate(burned_plain_atk, def, phys_move, 100, false)
	var flare_phys := DamageCalculator.calculate(flare_atk, def, phys_move, 100, false)
	_chk("S10.05 Flare Boost: burned + PHYSICAL does NOT boost beyond burn's own halving",
			flare_phys["damage"] == burned_plain_phys["damage"])

	# Sand Force: {Steel,Rock,Ground} type + sandstorm.
	var rock_move := _make_move(TypeChart.TYPE_ROCK, 0, 40)
	var sand_atk := _make_mon("SandForceMon", 50, [TypeChart.TYPE_NORMAL])
	sand_atk.ability = _load_ability(159)
	var plain_rock := DamageCalculator.calculate(plain_atk, def, rock_move, 100, false)
	var sand_no_weather := DamageCalculator.calculate(
			sand_atk, def, rock_move, 100, false, DamageCalculator.WEATHER_NONE)
	_chk("S10.06 Sand Force: no sandstorm does NOT boost",
			sand_no_weather["damage"] == plain_rock["damage"])
	var sand_with_weather := DamageCalculator.calculate(
			sand_atk, def, rock_move, 100, false, DamageCalculator.WEATHER_SANDSTORM)
	_chk("S10.07 Sand Force: Rock-type move in sandstorm boosts damage",
			sand_with_weather["damage"] > plain_rock["damage"])
	var normal_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var sand_wrong_type := DamageCalculator.calculate(
			sand_atk, def, normal_move, 100, false, DamageCalculator.WEATHER_SANDSTORM)
	var plain_normal := DamageCalculator.calculate(plain_atk, def, normal_move, 100, false)
	_chk("S10.08 Sand Force: non-{Steel/Rock/Ground} move in sandstorm NOT boosted",
			sand_wrong_type["damage"] == plain_normal["damage"])

	# Tough Claws: contact moves.
	var contact_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, true)
	var non_contact_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, false)
	var claws_atk := _make_mon("ToughClawsMon", 50, [TypeChart.TYPE_NORMAL])
	claws_atk.ability = _load_ability(181)
	var claws_contact := DamageCalculator.calculate(claws_atk, def, contact_move, 100, false)
	var plain_contact := DamageCalculator.calculate(plain_atk, def, contact_move, 100, false)
	_chk("S10.09 Tough Claws: contact move boosts damage",
			claws_contact["damage"] > plain_contact["damage"])
	var claws_noncontact := DamageCalculator.calculate(claws_atk, def, non_contact_move, 100, false)
	var plain_noncontact := DamageCalculator.calculate(plain_atk, def, non_contact_move, 100, false)
	_chk("S10.10 Tough Claws: non-contact move NOT boosted",
			claws_noncontact["damage"] == plain_noncontact["damage"])

	# Steelworker: Steel-type moves, self only (no ally).
	var steel_move := _make_move(TypeChart.TYPE_STEEL, 0, 40)
	var steelworker_atk := _make_mon("SteelworkerMon", 50, [TypeChart.TYPE_NORMAL])
	steelworker_atk.ability = _load_ability(200)
	var plain_steel := DamageCalculator.calculate(plain_atk, def, steel_move, 100, false)
	var steelworker_result := DamageCalculator.calculate(steelworker_atk, def, steel_move, 100, false)
	_chk("S10.11 Steelworker: Steel-type move boosts damage",
			steelworker_result["damage"] > plain_steel["damage"])
	var steelworker_wrongtype := DamageCalculator.calculate(steelworker_atk, def, normal_move, 100, false)
	_chk("S10.12 Steelworker: non-Steel move NOT boosted",
			steelworker_wrongtype["damage"] == plain_normal["damage"])

	# Steely Spirit: self AND ally, both independently gated on Steel-type move.
	var steely_atk := _make_mon("SteelySpiritMon", 50, [TypeChart.TYPE_NORMAL])
	steely_atk.ability = _load_ability(252)
	var steely_self_result := DamageCalculator.calculate(steely_atk, def, steel_move, 100, false)
	_chk("S10.13 Steely Spirit (self): Steel-type move boosts damage",
			steely_self_result["damage"] > plain_steel["damage"])

	var ally_with_steely := _make_mon("AllySteely", 50, [TypeChart.TYPE_NORMAL])
	ally_with_steely.ability = _load_ability(252)
	var steely_ally_result := DamageCalculator.calculate(
			plain_atk, def, steel_move, 100, false, DamageCalculator.WEATHER_NONE,
			false, false, -1, false, true, ally_with_steely)
	_chk("S10.14 Steely Spirit (ally, attacker has no ability): Steel move boosted",
			steely_ally_result["damage"] > plain_steel["damage"])
	var steely_ally_wrongtype := DamageCalculator.calculate(
			plain_atk, def, normal_move, 100, false, DamageCalculator.WEATHER_NONE,
			false, false, -1, false, true, ally_with_steely)
	_chk("S10.15 Steely Spirit (ally): non-Steel move NOT boosted",
			steely_ally_wrongtype["damage"] == plain_normal["damage"])

	# Battery: ally only, special moves only.
	var ally_with_battery := _make_mon("AllyBattery", 50, [TypeChart.TYPE_NORMAL])
	ally_with_battery.ability = _load_ability(217)
	var battery_spec_result := DamageCalculator.calculate(
			plain_atk, def, spec_move, 100, false, DamageCalculator.WEATHER_NONE,
			false, false, -1, false, true, ally_with_battery)
	_chk("S10.16 Battery (ally): special move boosted",
			battery_spec_result["damage"] > plain_spec["damage"])
	var battery_phys_result := DamageCalculator.calculate(
			plain_atk, def, phys_move, 100, false, DamageCalculator.WEATHER_NONE,
			false, false, -1, false, true, ally_with_battery)
	_chk("S10.17 Battery (ally): physical move NOT boosted",
			battery_phys_result["damage"] == plain_phys["damage"])
	var no_ally_spec := DamageCalculator.calculate(plain_atk, def, spec_move, 100, false)
	_chk("S10.18 No Battery ally (singles): special move NOT boosted",
			no_ally_spec["damage"] == plain_spec["damage"])

	# Power Spot: ally only, unconditional (any move category/type).
	var ally_with_power_spot := _make_mon("AllyPowerSpot", 50, [TypeChart.TYPE_NORMAL])
	ally_with_power_spot.ability = _load_ability(249)
	var power_spot_result := DamageCalculator.calculate(
			plain_atk, def, phys_move, 100, false, DamageCalculator.WEATHER_NONE,
			false, false, -1, false, true, ally_with_power_spot)
	_chk("S10.19 Power Spot (ally): any move boosted",
			power_spot_result["damage"] > plain_phys["damage"])
	var power_spot_spec := DamageCalculator.calculate(
			plain_atk, def, spec_move, 100, false, DamageCalculator.WEATHER_NONE,
			false, false, -1, false, true, ally_with_power_spot)
	_chk("S10.20 Power Spot (ally): special move also boosted",
			power_spot_spec["damage"] > plain_spec["damage"])


# ── Section 11: Guts burn-halving exemption ───────────────────────────────────

func _test_section_11_guts_burn_exemption() -> void:
	var def := _make_mon("Defender", 50, [TypeChart.TYPE_NORMAL])
	var phys_move := _make_move(TypeChart.TYPE_FIGHTING, 0, 40)

	var burned_plain := _make_mon("BurnedPlain", 50, [TypeChart.TYPE_NORMAL])
	burned_plain.status = BattlePokemon.STATUS_BURN
	var burned_result := DamageCalculator.calculate(burned_plain, def, phys_move, 100, false)

	var unburned_plain := _make_mon("UnburnedPlain", 50, [TypeChart.TYPE_NORMAL])
	var unburned_result := DamageCalculator.calculate(unburned_plain, def, phys_move, 100, false)
	_chk("S11.01 Baseline: burn halves physical damage (no Guts)",
			burned_result["damage"] < unburned_result["damage"])

	# Guts holder: burned + physical should NOT be halved by burn (Guts is exempt),
	# even though Guts's own Attack-boost also applies — the assertion here is
	# specifically that burn's halving didn't ALSO apply on top of the Guts boost by
	# comparing against an unstatused Guts holder's damage at the same nominal Attack
	# (both get the Guts ×1.5 Attack boost; only burn-halving differs).
	var guts_burned := _make_mon("GutsBurned", 50, [TypeChart.TYPE_NORMAL])
	guts_burned.ability = _load_ability(62)
	guts_burned.status = BattlePokemon.STATUS_BURN
	var guts_burned_result := DamageCalculator.calculate(guts_burned, def, phys_move, 100, false)

	var guts_paralyzed := _make_mon("GutsParalyzed", 50, [TypeChart.TYPE_NORMAL])
	guts_paralyzed.ability = _load_ability(62)
	guts_paralyzed.status = BattlePokemon.STATUS_PARALYSIS
	var guts_paralyzed_result := DamageCalculator.calculate(guts_paralyzed, def, phys_move, 100, false)

	_chk("S11.02 Guts: burned physical damage NOT halved (matches a non-burn status)",
			guts_burned_result["damage"] == guts_paralyzed_result["damage"])
