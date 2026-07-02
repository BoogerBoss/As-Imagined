extends Node

# M17b test suite — Tier B move effects: stat-stage-system interactions.
#
# Scope: the 32 abilities locked in docs/decisions.md [M17b]. Three distinct
# mechanism shapes, tested in separate sections:
#   (1) Magnitude modifiers (Simple, Contrary, Unaware)
#   (2) Change-blocking abilities (Clear Body, White Smoke, Hyper Cutter, Keen Eye,
#       Big Pecks, Flower Veil) + the Defiant/Competitive reactive follow-up
#   (3) Reactive triggers (Weak Armor, Justified, Rattled, Anger Point, Steadfast,
#       Download, Moody, Moxie, Gooey/Tangling Hair, Stamina, Water Compaction,
#       Berserk, Cotton Down, Steam Engine, Pastel Veil, Thermal Exchange,
#       Purifying Salt, Supersweet Syrup, Sweet Veil)
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state, for anything observed through a full
#     battle (Steadfast, Rock-Head-style regressions).
#   - Array-wrapper for any lambda that needs to report a result back to the
#     enclosing test function (GDScript captures scalars by value, not reference).
#
# Ground truth: pokeemerald_expansion src/battle_util.c, src/battle_stat_change.c,
# src/battle_move_resolution.c, src/battle_script_commands.c.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_magnitude_modifiers()
	_test_section_3_unaware()
	_test_section_4_change_blocking()
	_test_section_5_defiant_competitive()
	_test_section_6_hit_reactive_effects()
	_test_section_7_contact_reactive_effects()
	_test_section_8_steadfast()
	_test_section_9_download()
	_test_section_10_moody()
	_test_section_11_moxie()
	_test_section_12_status_immunities()
	_test_section_13_supersweet_syrup()
	_test_section_14_rattled_intimidate()

	var total := _pass + _fail
	print("m17b_test: %d/%d passed" % [_pass, total])
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


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var simple := _load_ability(86)
	_chk("S1.01 Simple id=86", simple.ability_id == 86)
	_chk("S1.02 Simple name", simple.ability_name == "Simple")

	var moody := _load_ability(141)
	_chk("S1.03 Moody id=141", moody.ability_id == 141)

	var moxie := _load_ability(153)
	_chk("S1.04 Moxie id=153", moxie.ability_id == 153)

	var purifying_salt := _load_ability(272)
	_chk("S1.05 Purifying Salt id=272", purifying_salt.ability_id == 272)
	_chk("S1.06 Purifying Salt name", purifying_salt.ability_name == "Purifying Salt")

	var supersweet := _load_ability(306)
	_chk("S1.07 Supersweet Syrup id=306", supersweet.ability_id == 306)

	var anger_shell := _load_ability(271)
	_chk("S1.08 Anger Shell id=271", anger_shell.ability_id == 271)


# ── Section 2: Magnitude modifiers — Simple, Contrary ────────────────────────

func _test_section_2_magnitude_modifiers() -> void:
	# Simple doubles the raw stage amount.
	var simple_mon := _make_mon("SimpleMon", 50, [TypeChart.TYPE_NORMAL])
	simple_mon.ability = _load_ability(86)
	var simple_actual: int = StatusManager.apply_stat_change(simple_mon, BattlePokemon.STAGE_ATK, 1)
	_chk("S2.01 Simple: +1 becomes +2", simple_actual == 2)
	var simple_actual_neg: int = StatusManager.apply_stat_change(simple_mon, BattlePokemon.STAGE_DEF, -1)
	_chk("S2.02 Simple: -1 becomes -2", simple_actual_neg == -2)

	# Negative: an ability-less mon gets the plain amount.
	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	var plain_actual: int = StatusManager.apply_stat_change(plain_mon, BattlePokemon.STAGE_ATK, 1)
	_chk("S2.03 No ability: +1 stays +1", plain_actual == 1)

	# Contrary inverts the sign.
	var contrary_mon := _make_mon("ContraryMon", 50, [TypeChart.TYPE_NORMAL])
	contrary_mon.ability = _load_ability(126)
	var contrary_actual: int = StatusManager.apply_stat_change(contrary_mon, BattlePokemon.STAGE_ATK, 1)
	_chk("S2.04 Contrary: +1 becomes -1", contrary_actual == -1)
	var contrary_actual_neg: int = StatusManager.apply_stat_change(contrary_mon, BattlePokemon.STAGE_DEF, -2)
	_chk("S2.05 Contrary: -2 becomes +2", contrary_actual_neg == 2)


# ── Section 3: Unaware — 4 touch-points ───────────────────────────────────────

func _test_section_3_unaware() -> void:
	var move := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var unaware_def := _make_mon("UnawareDef", 50, [TypeChart.TYPE_NORMAL])
	unaware_def.ability = _load_ability(109)
	var plain_def := _make_mon("PlainDef", 50, [TypeChart.TYPE_NORMAL])
	var atk := _make_mon("Atk", 50, [TypeChart.TYPE_NORMAL])

	# Attacker's Attack +2 should normally boost damage — Unaware defender ignores it.
	atk.stat_stages[BattlePokemon.STAGE_ATK] = 2
	var vs_unaware := DamageCalculator.calculate(atk, unaware_def, move, 100, false)
	var vs_plain_boosted := DamageCalculator.calculate(atk, plain_def, move, 100, false)
	_chk("S3.01 Unaware (defender) ignores attacker's Attack boost",
			vs_unaware["damage"] < vs_plain_boosted["damage"])
	atk.stat_stages[BattlePokemon.STAGE_ATK] = 0
	var vs_unaware_neutral := DamageCalculator.calculate(atk, unaware_def, move, 100, false)
	var vs_plain_neutral := DamageCalculator.calculate(atk, plain_def, move, 100, false)
	_chk("S3.02 Unaware (defender): neutral Attack stage matches baseline",
			vs_unaware_neutral["damage"] == vs_plain_neutral["damage"])

	# Attacker's Unaware ignores the defender's Defense boost.
	var unaware_atk := _make_mon("UnawareAtk", 50, [TypeChart.TYPE_NORMAL])
	unaware_atk.ability = _load_ability(109)
	var plain_atk := _make_mon("PlainAtk", 50, [TypeChart.TYPE_NORMAL])
	var def_boosted := _make_mon("DefBoosted", 50, [TypeChart.TYPE_NORMAL])
	def_boosted.stat_stages[BattlePokemon.STAGE_DEF] = 2
	var unaware_vs_boosted_def := DamageCalculator.calculate(unaware_atk, def_boosted, move, 100, false)
	var plain_vs_boosted_def := DamageCalculator.calculate(plain_atk, def_boosted, move, 100, false)
	_chk("S3.03 Unaware (attacker) ignores defender's Defense boost",
			unaware_vs_boosted_def["damage"] > plain_vs_boosted_def["damage"])

	# Accuracy: Unaware (defender) ignores the attacker's own Accuracy stage.
	var acc_move := _make_move(TypeChart.TYPE_NORMAL, 0, 50)
	var low_acc_atk := _make_mon("LowAccAtk", 50, [TypeChart.TYPE_NORMAL])
	low_acc_atk.stat_stages[BattlePokemon.STAGE_ACCURACY] = -6
	var unaware_def2 := _make_mon("UnawareDef2", 50, [TypeChart.TYPE_NORMAL])
	unaware_def2.ability = _load_ability(109)
	var hits_vs_unaware := 0
	for i in range(20):
		if StatusManager.check_accuracy(low_acc_atk, unaware_def2, acc_move, null):
			hits_vs_unaware += 1
	var plain_def2 := _make_mon("PlainDef2", 50, [TypeChart.TYPE_NORMAL])
	var hits_vs_plain := 0
	for i in range(20):
		if StatusManager.check_accuracy(low_acc_atk, plain_def2, acc_move, null):
			hits_vs_plain += 1
	_chk("S3.04 Unaware (defender) ignores attacker's lowered accuracy (hits more often)",
			hits_vs_unaware > hits_vs_plain)

	# Accuracy: Unaware or Keen Eye (attacker) ignores the defender's evasion boost.
	var high_eva_def := _make_mon("HighEvaDef", 50, [TypeChart.TYPE_NORMAL])
	high_eva_def.stat_stages[BattlePokemon.STAGE_EVASION] = 6
	var unaware_atk2 := _make_mon("UnawareAtk2", 50, [TypeChart.TYPE_NORMAL])
	unaware_atk2.ability = _load_ability(109)
	var plain_atk2 := _make_mon("PlainAtk2", 50, [TypeChart.TYPE_NORMAL])
	_chk("S3.05 ignores_defender_evasion_stage: Unaware attacker → true",
			AbilityManager.ignores_defender_evasion_stage(unaware_atk2) == true)
	_chk("S3.06 ignores_defender_evasion_stage: plain attacker → false",
			AbilityManager.ignores_defender_evasion_stage(plain_atk2) == false)
	var keen_eye_atk := _make_mon("KeenEyeAtk", 50, [TypeChart.TYPE_NORMAL])
	keen_eye_atk.ability = _load_ability(51)
	_chk("S3.07 ignores_defender_evasion_stage: Keen Eye attacker → true",
			AbilityManager.ignores_defender_evasion_stage(keen_eye_atk) == true)


# ── Section 4: Change-blocking — Clear Body, White Smoke, Hyper Cutter, Keen Eye,
#    Big Pecks, Flower Veil ────────────────────────────────────────────────────

func _test_section_4_change_blocking() -> void:
	# Clear Body blocks ALL reductions.
	var clear_body := _make_mon("ClearBodyMon", 50, [TypeChart.TYPE_NORMAL])
	clear_body.ability = _load_ability(29)
	var cb_atk_actual: int = StatusManager.apply_stat_change(clear_body, BattlePokemon.STAGE_ATK, -1)
	_chk("S4.01 Clear Body blocks Attack reduction", cb_atk_actual == 0)
	var cb_def_actual: int = StatusManager.apply_stat_change(clear_body, BattlePokemon.STAGE_DEF, -1)
	_chk("S4.02 Clear Body blocks Defense reduction (ALL stats)", cb_def_actual == 0)
	var cb_raise_actual: int = StatusManager.apply_stat_change(clear_body, BattlePokemon.STAGE_ATK, 1)
	_chk("S4.03 Clear Body does NOT block a raise", cb_raise_actual == 1)

	var white_smoke := _make_mon("WhiteSmokeMon", 50, [TypeChart.TYPE_NORMAL])
	white_smoke.ability = _load_ability(73)
	_chk("S4.04 White Smoke blocks Attack reduction",
			StatusManager.apply_stat_change(white_smoke, BattlePokemon.STAGE_ATK, -1) == 0)

	# Hyper Cutter — Attack only.
	var hyper_cutter := _make_mon("HyperCutterMon", 50, [TypeChart.TYPE_NORMAL])
	hyper_cutter.ability = _load_ability(52)
	_chk("S4.05 Hyper Cutter blocks Attack reduction",
			StatusManager.apply_stat_change(hyper_cutter, BattlePokemon.STAGE_ATK, -1) == 0)
	_chk("S4.06 Hyper Cutter does NOT block Defense reduction",
			StatusManager.apply_stat_change(hyper_cutter, BattlePokemon.STAGE_DEF, -1) == -1)

	# Keen Eye — Accuracy only.
	var keen_eye := _make_mon("KeenEyeMon", 50, [TypeChart.TYPE_NORMAL])
	keen_eye.ability = _load_ability(51)
	_chk("S4.07 Keen Eye blocks Accuracy reduction",
			StatusManager.apply_stat_change(keen_eye, BattlePokemon.STAGE_ACCURACY, -1) == 0)
	_chk("S4.08 Keen Eye does NOT block Attack reduction",
			StatusManager.apply_stat_change(keen_eye, BattlePokemon.STAGE_ATK, -1) == -1)

	# Big Pecks — Defense only.
	var big_pecks := _make_mon("BigPecksMon", 50, [TypeChart.TYPE_NORMAL])
	big_pecks.ability = _load_ability(145)
	_chk("S4.09 Big Pecks blocks Defense reduction",
			StatusManager.apply_stat_change(big_pecks, BattlePokemon.STAGE_DEF, -1) == 0)
	_chk("S4.10 Big Pecks does NOT block Attack reduction",
			StatusManager.apply_stat_change(big_pecks, BattlePokemon.STAGE_ATK, -1) == -1)

	# Flower Veil — Grass-type self or ally.
	var flower_veil_grass := _make_mon("FlowerVeilGrass", 50, [TypeChart.TYPE_GRASS])
	flower_veil_grass.ability = _load_ability(166)
	_chk("S4.11 Flower Veil (self, Grass-type) blocks reduction",
			StatusManager.apply_stat_change(flower_veil_grass, BattlePokemon.STAGE_ATK, -1) == 0)

	var non_grass_holder := _make_mon("NonGrassHolder", 50, [TypeChart.TYPE_NORMAL])
	non_grass_holder.ability = _load_ability(166)
	_chk("S4.12 Flower Veil holder that is NOT Grass-type does NOT block on itself",
			StatusManager.apply_stat_change(non_grass_holder, BattlePokemon.STAGE_ATK, -1) == -1)

	var grass_no_veil := _make_mon("GrassNoVeil", 50, [TypeChart.TYPE_GRASS])
	var flower_veil_ally := _make_mon("FlowerVeilAlly", 50, [TypeChart.TYPE_NORMAL])
	flower_veil_ally.ability = _load_ability(166)
	_chk("S4.13 Flower Veil (ally) protects a Grass-type teammate",
			StatusManager.apply_stat_change(grass_no_veil, BattlePokemon.STAGE_ATK, -1, flower_veil_ally) == 0)
	_chk("S4.14 Grass-type with NO Flower Veil ally is NOT protected",
			StatusManager.apply_stat_change(grass_no_veil, BattlePokemon.STAGE_DEF, -1, null) == -1)


# ── Section 5: Defiant / Competitive reactive follow-up ──────────────────────

func _test_section_5_defiant_competitive() -> void:
	_chk("S5.01 defiant_competitive_stat: Defiant → STAGE_ATK",
			AbilityManager.defiant_competitive_stat(_with_ability(128)) == BattlePokemon.STAGE_ATK)
	_chk("S5.02 defiant_competitive_stat: Competitive → STAGE_SPATK",
			AbilityManager.defiant_competitive_stat(_with_ability(172)) == BattlePokemon.STAGE_SPATK)
	_chk("S5.03 defiant_competitive_stat: no ability → -1",
			AbilityManager.defiant_competitive_stat(_make_mon("Plain", 50, [TypeChart.TYPE_NORMAL])) == -1)

	# Integration: a Growl-style opponent move lowering Attack triggers Defiant's +2.
	var growl := MoveData.new()
	growl.move_name = "TestGrowl"
	growl.type = TypeChart.TYPE_NORMAL
	growl.category = 2
	growl.accuracy = 100
	growl.pp = 20
	growl.stat_change_stat = BattlePokemon.STAGE_ATK
	growl.stat_change_amount = -1
	growl.stat_change_self = false

	var defiant_mon := _make_mon("DefiantMon", 50, [TypeChart.TYPE_NORMAL])
	defiant_mon.ability = _load_ability(128)
	defiant_mon.add_move(growl)
	var grower := _make_mon("Grower", 50, [TypeChart.TYPE_NORMAL])
	grower.add_move(growl)

	var bm := _make_bm()
	bm._force_hit = true
	var atk_changes: Array = []
	bm.stat_stage_changed.connect(func(mon: BattlePokemon, stat: int, amount: int) -> void:
		if mon == defiant_mon and stat == BattlePokemon.STAGE_ATK and atk_changes.size() < 2:
			atk_changes.append(amount))
	bm.start_battle(grower, defiant_mon)
	_chk("S5.04 Defiant: Growl triggers a -1 then a +2 on the SAME defiant_mon",
			atk_changes.size() >= 2 and atk_changes[0] == -1 and atk_changes[1] == 2)


func _with_ability(ability_id: int) -> BattlePokemon:
	var mon := _make_mon("AbilityMon", 50, [TypeChart.TYPE_NORMAL])
	mon.ability = _load_ability(ability_id)
	return mon


# ── Section 6: Non-contact hit-reactive effects ──────────────────────────────

func _test_section_6_hit_reactive_effects() -> void:
	var dark_move := _make_move(TypeChart.TYPE_DARK, 0, 40)
	var bug_move := _make_move(TypeChart.TYPE_BUG, 0, 40)
	var water_move := _make_move(TypeChart.TYPE_WATER, 1, 40)
	var normal_phys := _make_move(TypeChart.TYPE_NORMAL, 0, 40)
	var fire_move := _make_move(TypeChart.TYPE_FIRE, 0, 40)
	var attacker := _make_mon("Attacker", 50, [TypeChart.TYPE_NORMAL])

	# Justified: Dark-type hit → Atk +1.
	var justified := _make_mon("JustifiedMon", 50, [TypeChart.TYPE_NORMAL])
	justified.ability = _load_ability(154)
	var r1: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, justified, dark_move, 10, justified.max_hp, false)
	_chk("S6.01 Justified: Dark-type hit boosts Attack", r1["justified_change"] == 1)
	var r1b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, justified, normal_phys, 10, justified.max_hp, false)
	_chk("S6.02 Justified: non-Dark hit does NOT boost", r1b["justified_change"] == 0)

	# Rattled: Bug/Dark/Ghost hit → Spe +1.
	var rattled := _make_mon("RattledMon", 50, [TypeChart.TYPE_NORMAL])
	rattled.ability = _load_ability(155)
	var r2: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, rattled, bug_move, 10, rattled.max_hp, false)
	_chk("S6.03 Rattled: Bug-type hit boosts Speed", r2["rattled_change"] == 1)
	var r2b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, rattled, water_move, 10, rattled.max_hp, false)
	_chk("S6.04 Rattled: Water-type hit does NOT boost", r2b["rattled_change"] == 0)

	# Water Compaction: Water-type hit → Def +2.
	var water_comp := _make_mon("WaterCompactionMon", 50, [TypeChart.TYPE_NORMAL])
	water_comp.ability = _load_ability(195)
	var r3: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, water_comp, water_move, 10, water_comp.max_hp, false)
	_chk("S6.05 Water Compaction: Water hit → Def +2", r3["water_compaction_change"] == 2)
	var r3b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, water_comp, normal_phys, 10, water_comp.max_hp, false)
	_chk("S6.06 Water Compaction: non-Water hit does NOT boost", r3b["water_compaction_change"] == 0)

	# Stamina: any hit → Def +1.
	var stamina := _make_mon("StaminaMon", 50, [TypeChart.TYPE_NORMAL])
	stamina.ability = _load_ability(192)
	var r4: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, stamina, normal_phys, 10, stamina.max_hp, false)
	_chk("S6.07 Stamina: any damaging hit → Def +1", r4["stamina_change"] == 1)
	var r4b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, stamina, normal_phys, 0, stamina.max_hp, false)
	_chk("S6.08 Stamina: zero damage does NOT boost", r4b["stamina_change"] == 0)

	# Weak Armor: physical hit → Def -1, Spe +2.
	var weak_armor := _make_mon("WeakArmorMon", 50, [TypeChart.TYPE_NORMAL])
	weak_armor.ability = _load_ability(133)
	var r5: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, weak_armor, normal_phys, 10, weak_armor.max_hp, false)
	_chk("S6.09 Weak Armor: physical hit → Def -1", r5["weak_armor_def_change"] == -1)
	_chk("S6.10 Weak Armor: physical hit → Spe +2", r5["weak_armor_speed_change"] == 2)
	var r5b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, weak_armor, water_move, 10, weak_armor.max_hp, false)
	_chk("S6.11 Weak Armor: special hit does NOT trigger", r5b["weak_armor_def_change"] == 0 and r5b["weak_armor_speed_change"] == 0)

	# Anger Point: crit received → Atk set to max.
	var anger_point := _make_mon("AngerPointMon", 50, [TypeChart.TYPE_NORMAL])
	anger_point.ability = _load_ability(83)
	var r6: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, anger_point, normal_phys, 10, anger_point.max_hp, true)
	# Requested delta is +12 (source's raw 0-12 scale), but apply_stat_change clamps to
	# this project's -6..+6 range and reports the ACTUAL delta applied: from a fresh
	# mon's neutral stage (0), that's +6 (0 → +6), not the raw +12 requested.
	_chk("S6.12 Anger Point: crit received → Atk set to +6 (change=6)", r6["anger_point_change"] == 6)
	var r6b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, anger_point, normal_phys, 10, anger_point.max_hp, false)
	_chk("S6.13 Anger Point: non-crit hit does NOT trigger", r6b["anger_point_change"] == 0)

	# Berserk: HP crosses >50% → <=50% THIS hit.
	var berserk := _make_mon("BerserkMon", 50, [TypeChart.TYPE_NORMAL], 100)
	berserk.ability = _load_ability(201)
	berserk.current_hp = 40  # <=50% of 100 after the hit
	var r7: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, berserk, normal_phys, 60, 100, false)
	_chk("S6.14 Berserk: crossed >50%→<=50% this hit → SpA +1", r7["berserk_change"] == 1)
	# Negative: already below half BEFORE this hit (no crossing).
	var berserk2 := _make_mon("BerserkMon2", 50, [TypeChart.TYPE_NORMAL], 100)
	berserk2.ability = _load_ability(201)
	berserk2.current_hp = 20
	var r7b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, berserk2, normal_phys, 20, 40, false)
	_chk("S6.15 Berserk: no crossing (already <=50% before hit) does NOT trigger", r7b["berserk_change"] == 0)

	# Anger Shell: same crossing check, 5 stat changes.
	var anger_shell := _make_mon("AngerShellMon", 50, [TypeChart.TYPE_NORMAL], 100)
	anger_shell.ability = _load_ability(271)
	anger_shell.current_hp = 40
	var r8: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, anger_shell, normal_phys, 60, 100, false)
	var changes: Dictionary = r8["anger_shell_changes"]
	_chk("S6.16 Anger Shell: Def -1", changes.get(BattlePokemon.STAGE_DEF, 0) == -1)
	_chk("S6.17 Anger Shell: SpDef -1", changes.get(BattlePokemon.STAGE_SPDEF, 0) == -1)
	_chk("S6.18 Anger Shell: Atk +1", changes.get(BattlePokemon.STAGE_ATK, 0) == 1)
	_chk("S6.19 Anger Shell: SpA +1", changes.get(BattlePokemon.STAGE_SPATK, 0) == 1)
	_chk("S6.20 Anger Shell: Spe +1", changes.get(BattlePokemon.STAGE_SPEED, 0) == 1)
	var anger_shell2 := _make_mon("AngerShellMon2", 50, [TypeChart.TYPE_NORMAL], 100)
	anger_shell2.ability = _load_ability(271)
	anger_shell2.current_hp = 90
	var r8b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, anger_shell2, normal_phys, 10, 100, false)
	_chk("S6.21 Anger Shell: still above 50% after hit does NOT trigger", r8b["anger_shell_changes"].is_empty())

	# Steam Engine: Fire/Water hit → Spe +6.
	var steam_engine := _make_mon("SteamEngineMon", 50, [TypeChart.TYPE_NORMAL])
	steam_engine.ability = _load_ability(243)
	var r9: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, steam_engine, fire_move, 10, steam_engine.max_hp, false)
	_chk("S6.22 Steam Engine: Fire-type hit → Spe +6", r9["steam_engine_change"] == 6)
	var r9b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, steam_engine, dark_move, 10, steam_engine.max_hp, false)
	_chk("S6.23 Steam Engine: non-Fire/Water hit does NOT trigger", r9b["steam_engine_change"] == 0)

	# Thermal Exchange: Fire-type hit → Atk +1.
	var thermal := _make_mon("ThermalExchangeMon", 50, [TypeChart.TYPE_NORMAL])
	thermal.ability = _load_ability(270)
	var r10: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, thermal, fire_move, 10, thermal.max_hp, false)
	_chk("S6.24 Thermal Exchange: Fire-type hit → Atk +1", r10["thermal_exchange_change"] == 1)
	var r10b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, thermal, dark_move, 10, thermal.max_hp, false)
	_chk("S6.25 Thermal Exchange: non-Fire hit does NOT trigger", r10b["thermal_exchange_change"] == 0)

	# Cotton Down: any hit → flag (BattleManager applies to attacker + ally).
	var cotton_down := _make_mon("CottonDownMon", 50, [TypeChart.TYPE_NORMAL])
	cotton_down.ability = _load_ability(238)
	var r11: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, cotton_down, normal_phys, 10, cotton_down.max_hp, false)
	_chk("S6.26 Cotton Down: damaging hit fires the flag", r11["cotton_down_fired"] == true)
	var r11b: Dictionary = AbilityManager.try_hit_reactive_effects(attacker, cotton_down, normal_phys, 0, cotton_down.max_hp, false)
	_chk("S6.27 Cotton Down: zero damage does NOT fire", r11b["cotton_down_fired"] == false)

	# Integration: Cotton Down lowers the ATTACKER's Speed via a full battle.
	var cd_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, false)
	var cd_holder := _make_mon("CDHolder", 50, [TypeChart.TYPE_NORMAL], 200)
	cd_holder.ability = _load_ability(238)
	cd_holder.add_move(cd_move)
	var cd_attacker := _make_mon("CDAttacker", 50, [TypeChart.TYPE_NORMAL], 200)
	cd_attacker.add_move(cd_move)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm._force_roll = 100
	var cd_speed_drop := [false]
	bm.stat_stage_changed.connect(func(mon: BattlePokemon, stat: int, amount: int) -> void:
		if mon == cd_attacker and stat == BattlePokemon.STAGE_SPEED and amount < 0:
			cd_speed_drop[0] = true)
	bm.start_battle(cd_attacker, cd_holder)
	_chk("S6.28 Cotton Down integration: attacker's Speed dropped after hitting the holder",
			cd_speed_drop[0] == true)


# ── Section 7: Contact-gated reactive effects — Gooey, Tangling Hair ─────────

func _test_section_7_contact_reactive_effects() -> void:
	var contact_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, true)
	var non_contact_move := _make_move(TypeChart.TYPE_NORMAL, 0, 40, 100, false)
	var attacker := _make_mon("Attacker", 50, [TypeChart.TYPE_NORMAL])

	var gooey := _make_mon("GooeyMon", 50, [TypeChart.TYPE_NORMAL])
	gooey.ability = _load_ability(183)
	var r1: Dictionary = AbilityManager.try_contact_effects(attacker, gooey, contact_move, 10, false)
	_chk("S7.01 Gooey: contact move lowers attacker's Speed", r1["speed_change"] == -1)
	var attacker2 := _make_mon("Attacker2", 50, [TypeChart.TYPE_NORMAL])
	var r1b: Dictionary = AbilityManager.try_contact_effects(attacker2, gooey, non_contact_move, 10, false)
	_chk("S7.02 Gooey: non-contact move does NOT lower Speed", r1b["speed_change"] == 0)

	var tangling_hair := _make_mon("TanglingHairMon", 50, [TypeChart.TYPE_NORMAL])
	tangling_hair.ability = _load_ability(221)
	var attacker3 := _make_mon("Attacker3", 50, [TypeChart.TYPE_NORMAL])
	var r2: Dictionary = AbilityManager.try_contact_effects(attacker3, tangling_hair, contact_move, 10, false)
	_chk("S7.03 Tangling Hair: contact move lowers attacker's Speed", r2["speed_change"] == -1)

	# Composition check: an attacker with Clear Body correctly resists Gooey.
	var clear_body_attacker := _make_mon("ClearBodyAttacker", 50, [TypeChart.TYPE_NORMAL])
	clear_body_attacker.ability = _load_ability(29)
	var r3: Dictionary = AbilityManager.try_contact_effects(clear_body_attacker, gooey, contact_move, 10, false)
	_chk("S7.04 Gooey vs Clear Body attacker: blocked, no Speed change", r3["speed_change"] == 0)


# ── Section 8: Steadfast (flinch-triggered, full-battle integration) ────────

func _test_section_8_steadfast() -> void:
	var flinch_move := MoveData.new()
	flinch_move.move_name = "TestFlinchMove"
	flinch_move.type = TypeChart.TYPE_NORMAL
	flinch_move.category = 0
	flinch_move.power = 40
	flinch_move.accuracy = 100
	flinch_move.pp = 20
	flinch_move.secondary_effect = MoveData.SE_FLINCH
	flinch_move.secondary_chance = 100

	var filler_move := _make_move(TypeChart.TYPE_NORMAL, 0, 30)
	filler_move.pp = 20

	var steadfast_mon := _make_mon("SteadfastMon", 50, [TypeChart.TYPE_NORMAL], 200, 60, 200, 60, 200, 60)
	steadfast_mon.ability = _load_ability(80)
	steadfast_mon.add_move(filler_move)
	var flincher := _make_mon("Flincher", 50, [TypeChart.TYPE_NORMAL], 200, 200, 200, 200, 200, 200)
	flincher.add_move(flinch_move)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm._force_roll = 100
	var steadfast_speed_boost := [false]
	bm.stat_stage_changed.connect(func(mon: BattlePokemon, stat: int, amount: int) -> void:
		if mon == steadfast_mon and stat == BattlePokemon.STAGE_SPEED and amount > 0:
			steadfast_speed_boost[0] = true)
	bm.start_battle(flincher, steadfast_mon)
	_chk("S8.01 Steadfast: flinching raises the flinched Pokémon's own Speed",
			steadfast_speed_boost[0] == true)


# ── Section 9: Download ───────────────────────────────────────────────────────

func _test_section_9_download() -> void:
	var download_mon := _make_mon("DownloadMon", 50, [TypeChart.TYPE_NORMAL])
	download_mon.ability = _load_ability(88)

	# Opponent with LOW Defense, high Sp. Def → Download picks Attack.
	var low_def_opp := _make_mon("LowDefOpp", 50, [TypeChart.TYPE_NORMAL], 80, 80, 40, 80, 150, 80)
	var stage1: int = AbilityManager.download_stat(download_mon, [low_def_opp])
	_chk("S9.01 Download: opponent's Def < SpDef → raises Attack", stage1 == BattlePokemon.STAGE_ATK)

	# Opponent with LOW Sp. Def, high Defense → Download picks Sp. Atk.
	var low_spdef_opp := _make_mon("LowSpDefOpp", 50, [TypeChart.TYPE_NORMAL], 80, 80, 150, 80, 40, 80)
	var download_mon2 := _make_mon("DownloadMon2", 50, [TypeChart.TYPE_NORMAL])
	download_mon2.ability = _load_ability(88)
	var stage2: int = AbilityManager.download_stat(download_mon2, [low_spdef_opp])
	_chk("S9.02 Download: opponent's SpDef < Def → raises Sp. Atk", stage2 == BattlePokemon.STAGE_SPATK)

	# Negative: no ability → -1.
	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	_chk("S9.03 Download: no ability → -1", AbilityManager.download_stat(plain_mon, [low_def_opp]) == -1)

	# Negative: relevant stat already maxed → -1.
	var maxed_download := _make_mon("MaxedDownload", 50, [TypeChart.TYPE_NORMAL])
	maxed_download.ability = _load_ability(88)
	maxed_download.stat_stages[BattlePokemon.STAGE_ATK] = 6
	_chk("S9.04 Download: already-maxed relevant stat → -1",
			AbilityManager.download_stat(maxed_download, [low_def_opp]) == -1)


# ── Section 10: Moody ──────────────────────────────────────────────────────────

func _test_section_10_moody() -> void:
	var moody_mon := _make_mon("MoodyMon", 50, [TypeChart.TYPE_NORMAL])
	moody_mon.ability = _load_ability(141)
	var result: Dictionary = AbilityManager.try_end_of_turn(
			moody_mon, BattlePokemon.STAGE_ATK, BattlePokemon.STAGE_DEF)
	_chk("S10.01 Moody: forced raise stat is Atk", result["moody_raised_stat"] == BattlePokemon.STAGE_ATK)
	_chk("S10.02 Moody: raise amount is +2", result["moody_raised_amount"] == 2)
	_chk("S10.03 Moody: forced lower stat is Def", result["moody_lowered_stat"] == BattlePokemon.STAGE_DEF)
	_chk("S10.04 Moody: lower amount is -1", result["moody_lowered_amount"] == -1)

	# Negative: cannot lower the SAME stat that was just raised, even if forced.
	var moody_mon2 := _make_mon("MoodyMon2", 50, [TypeChart.TYPE_NORMAL])
	moody_mon2.ability = _load_ability(141)
	var result2: Dictionary = AbilityManager.try_end_of_turn(
			moody_mon2, BattlePokemon.STAGE_SPEED, BattlePokemon.STAGE_SPEED)
	_chk("S10.05 Moody: cannot force-lower the just-raised stat",
			result2["moody_lowered_stat"] != BattlePokemon.STAGE_SPEED)

	# Negative: no ability → no Moody changes.
	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	var result3: Dictionary = AbilityManager.try_end_of_turn(plain_mon)
	_chk("S10.06 No ability: Moody does NOT fire", result3["moody_raised_stat"] == -1)

	# Speed Boost still works via the same function (regression, not a new ability).
	var sb_mon := _make_mon("SpeedBoostMon", 50, [TypeChart.TYPE_NORMAL])
	sb_mon.ability = _load_ability(3)
	var result4: Dictionary = AbilityManager.try_end_of_turn(sb_mon)
	_chk("S10.07 Speed Boost regression: still fires via try_end_of_turn",
			result4["speed_boost_change"] == 1)


# ── Section 11: Moxie ──────────────────────────────────────────────────────────

func _test_section_11_moxie() -> void:
	var moxie_mon := _make_mon("MoxieMon", 50, [TypeChart.TYPE_NORMAL])
	moxie_mon.ability = _load_ability(153)
	_chk("S11.01 Moxie: boosts killer's Attack", AbilityManager.moxie_boost(moxie_mon) == 1)

	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	_chk("S11.02 Moxie: no ability does NOT boost", AbilityManager.moxie_boost(plain_mon) == 0)
	_chk("S11.03 Moxie: null killer does NOT boost", AbilityManager.moxie_boost(null) == 0)

	# Integration: fainting the opponent via a full battle boosts the killer's Attack.
	var strong_move := _make_move(TypeChart.TYPE_NORMAL, 0, 100, 100)
	strong_move.pp = 20
	var moxie_killer := _make_mon("MoxieKiller", 50, [TypeChart.TYPE_NORMAL], 200, 150, 80, 80, 80, 100)
	moxie_killer.ability = _load_ability(153)
	moxie_killer.add_move(strong_move)
	var victim := _make_mon("Victim", 50, [TypeChart.TYPE_NORMAL], 30, 60, 60, 60, 60, 50)
	victim.add_move(strong_move)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm._force_roll = 100
	var moxie_boosted := [false]
	bm.stat_stage_changed.connect(func(mon: BattlePokemon, stat: int, amount: int) -> void:
		if mon == moxie_killer and stat == BattlePokemon.STAGE_ATK and amount > 0:
			moxie_boosted[0] = true)
	bm.start_battle(moxie_killer, victim)
	_chk("S11.04 Moxie integration: KO'ing the opponent boosts the killer's Attack",
			moxie_boosted[0] == true)


# ── Section 12: Status immunities — Sweet Veil, Pastel Veil, Purifying Salt ──

func _test_section_12_status_immunities() -> void:
	# Sweet Veil: blocks sleep, self or ally.
	var sweet_veil := _make_mon("SweetVeilMon", 50, [TypeChart.TYPE_NORMAL])
	sweet_veil.ability = _load_ability(175)
	_chk("S12.01 Sweet Veil (self) blocks sleep",
			StatusManager.try_apply_status(sweet_veil, BattlePokemon.STATUS_SLEEP) == false)
	var no_veil := _make_mon("NoVeilMon", 50, [TypeChart.TYPE_NORMAL])
	_chk("S12.02 No Sweet Veil: sleep applies normally",
			StatusManager.try_apply_status(no_veil, BattlePokemon.STATUS_SLEEP) == true)
	var no_veil2 := _make_mon("NoVeilMon2", 50, [TypeChart.TYPE_NORMAL])
	var sweet_veil_ally := _make_mon("SweetVeilAlly", 50, [TypeChart.TYPE_NORMAL])
	sweet_veil_ally.ability = _load_ability(175)
	_chk("S12.03 Sweet Veil (ally) blocks sleep on a teammate",
			StatusManager.try_apply_status(no_veil2, BattlePokemon.STATUS_SLEEP, null, sweet_veil_ally) == false)
	var sweet_veil_burn_test := _make_mon("SweetVeilBurnTest", 50, [TypeChart.TYPE_NORMAL])
	sweet_veil_burn_test.ability = _load_ability(175)
	_chk("S12.04 Sweet Veil does NOT block burn (sleep-specific)",
			StatusManager.try_apply_status(sweet_veil_burn_test, BattlePokemon.STATUS_BURN) == true)

	# Pastel Veil: blocks poison/toxic, self or ally.
	var pastel_veil := _make_mon("PastelVeilMon", 50, [TypeChart.TYPE_NORMAL])
	pastel_veil.ability = _load_ability(257)
	_chk("S12.05 Pastel Veil (self) blocks poison",
			StatusManager.try_apply_status(pastel_veil, BattlePokemon.STATUS_POISON) == false)
	_chk("S12.06 Pastel Veil (self) blocks toxic",
			StatusManager.try_apply_status(_load_fresh_pastel_veil(), BattlePokemon.STATUS_TOXIC) == false)
	var no_pastel := _make_mon("NoPastelMon", 50, [TypeChart.TYPE_NORMAL])
	var pastel_ally := _make_mon("PastelAlly", 50, [TypeChart.TYPE_NORMAL])
	pastel_ally.ability = _load_ability(257)
	_chk("S12.07 Pastel Veil (ally) blocks poison on a teammate",
			StatusManager.try_apply_status(no_pastel, BattlePokemon.STATUS_POISON, null, pastel_ally) == false)
	var pastel_burn_test := _make_mon("PastelBurnTest", 50, [TypeChart.TYPE_NORMAL])
	pastel_burn_test.ability = _load_ability(257)
	_chk("S12.08 Pastel Veil does NOT block burn (poison-specific)",
			StatusManager.try_apply_status(pastel_burn_test, BattlePokemon.STATUS_BURN) == true)

	# Pastel Veil switch-in cure.
	var poisoned_pastel := _make_mon("PoisonedPastel", 50, [TypeChart.TYPE_NORMAL])
	poisoned_pastel.ability = _load_ability(257)
	poisoned_pastel.status = BattlePokemon.STATUS_POISON
	var opp := _make_mon("Opp", 50, [TypeChart.TYPE_NORMAL])
	var si_result: Dictionary = AbilityManager.try_switch_in(poisoned_pastel, opp)
	_chk("S12.09 Pastel Veil: cures own poison on switch-in", si_result["cured_own_poison"] == true)
	_chk("S12.10 Pastel Veil: status actually cleared", poisoned_pastel.status == BattlePokemon.STATUS_NONE)

	# Purifying Salt: blocks ALL statuses, self only + halves Ghost damage.
	var purifying_salt := _make_mon("PurifyingSaltMon", 50, [TypeChart.TYPE_NORMAL])
	purifying_salt.ability = _load_ability(272)
	_chk("S12.11 Purifying Salt blocks burn", StatusManager.try_apply_status(purifying_salt, BattlePokemon.STATUS_BURN) == false)
	var purifying_salt2 := _make_mon("PurifyingSaltMon2", 50, [TypeChart.TYPE_NORMAL])
	purifying_salt2.ability = _load_ability(272)
	_chk("S12.12 Purifying Salt blocks paralysis", StatusManager.try_apply_status(purifying_salt2, BattlePokemon.STATUS_PARALYSIS) == false)

	# Normal-type defenders are immune to Ghost-type moves (0x, unrelated to Purifying
	# Salt), so a Water-type defender is used here to actually measure the ×0.5 modifier.
	var ghost_move := _make_move(TypeChart.TYPE_GHOST, 1, 40)
	var water_move2 := _make_move(TypeChart.TYPE_WATER, 1, 40)
	var atk := _make_mon("Atk", 50, [TypeChart.TYPE_NORMAL])
	var salt_def := _make_mon("SaltDef", 50, [TypeChart.TYPE_WATER])
	salt_def.ability = _load_ability(272)
	var plain_def := _make_mon("PlainDef", 50, [TypeChart.TYPE_WATER])
	var ghost_result := DamageCalculator.calculate(atk, salt_def, ghost_move, 100, false)
	var ghost_baseline := DamageCalculator.calculate(atk, plain_def, ghost_move, 100, false)
	_chk("S12.13 Purifying Salt: Ghost-type damage halved", ghost_result["damage"] < ghost_baseline["damage"])
	var water_result := DamageCalculator.calculate(atk, salt_def, water_move2, 100, false)
	var water_baseline := DamageCalculator.calculate(atk, plain_def, water_move2, 100, false)
	_chk("S12.14 Purifying Salt: non-Ghost damage NOT reduced", water_result["damage"] == water_baseline["damage"])


func _load_fresh_pastel_veil() -> BattlePokemon:
	var mon := _make_mon("FreshPastelVeil", 50, [TypeChart.TYPE_NORMAL])
	mon.ability = _load_ability(257)
	return mon


# ── Section 13: Supersweet Syrup ───────────────────────────────────────────────

func _test_section_13_supersweet_syrup() -> void:
	var syrup_mon := _make_mon("SyrupMon", 50, [TypeChart.TYPE_NORMAL])
	syrup_mon.ability = _load_ability(306)
	var opp := _make_mon("Opp", 50, [TypeChart.TYPE_NORMAL])
	var first_actual: int = AbilityManager.try_switch_in_evasion(syrup_mon, opp)
	_chk("S13.01 Supersweet Syrup: first switch-in lowers opponent's Evasion", first_actual == -1)

	# Negative: fires only ONCE per Pokémon, even across multiple switch-ins.
	var opp2 := _make_mon("Opp2", 50, [TypeChart.TYPE_NORMAL])
	var second_actual: int = AbilityManager.try_switch_in_evasion(syrup_mon, opp2)
	_chk("S13.02 Supersweet Syrup: does NOT fire a second time for the same Pokémon",
			second_actual == 0)

	# Negative: no ability → never fires.
	var plain_mon := _make_mon("PlainMon", 50, [TypeChart.TYPE_NORMAL])
	_chk("S13.03 Supersweet Syrup: no ability does NOT fire",
			AbilityManager.try_switch_in_evasion(plain_mon, opp) == 0)


# ── Section 14: Rattled's "being Intimidated" trigger + Intimidate/Defiant ───

func _test_section_14_rattled_intimidate() -> void:
	var intimidate_mon := _make_mon("IntimidateMon", 50, [TypeChart.TYPE_NORMAL])
	intimidate_mon.ability = _load_ability(22)

	var rattled_opp := _make_mon("RattledOpp", 50, [TypeChart.TYPE_NORMAL])
	rattled_opp.ability = _load_ability(155)
	var result: Dictionary = AbilityManager.try_switch_in(intimidate_mon, rattled_opp)
	_chk("S14.01 Intimidate lowers Rattled opponent's Attack", result["atk_change"] == -1)
	_chk("S14.02 Rattled: being Intimidated raises its own Speed", result["opponent_speed_change"] == 1)

	# Negative: an ordinary opponent doesn't get the Rattled Speed bonus.
	var plain_opp := _make_mon("PlainOpp", 50, [TypeChart.TYPE_NORMAL])
	var intimidate_mon2 := _make_mon("IntimidateMon2", 50, [TypeChart.TYPE_NORMAL])
	intimidate_mon2.ability = _load_ability(22)
	var result2: Dictionary = AbilityManager.try_switch_in(intimidate_mon2, plain_opp)
	_chk("S14.03 Intimidate vs plain opponent: no Speed change reported", result2["opponent_speed_change"] == 0)

	# Defiant/Competitive also react to being Intimidated.
	var defiant_opp := _make_mon("DefiantOpp", 50, [TypeChart.TYPE_NORMAL])
	defiant_opp.ability = _load_ability(128)
	var intimidate_mon3 := _make_mon("IntimidateMon3", 50, [TypeChart.TYPE_NORMAL])
	intimidate_mon3.ability = _load_ability(22)
	var result3: Dictionary = AbilityManager.try_switch_in(intimidate_mon3, defiant_opp)
	_chk("S14.04 Intimidate vs Defiant: Attack still drops by 1", result3["atk_change"] == -1)
	_chk("S14.05 Defiant: being Intimidated triggers a +2 Attack follow-up",
			result3["opponent_defiant_change"] == 2)
	_chk("S14.06 Defiant: follow-up stat is STAGE_ATK",
			result3["opponent_defiant_stat"] == BattlePokemon.STAGE_ATK)
