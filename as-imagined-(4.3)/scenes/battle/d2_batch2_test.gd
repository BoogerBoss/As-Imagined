extends Node

# [D2 batch 2] Two independent families:
#
# Part A — offense-stat-source-override family (3 moves): Foul Play(492),
#   Body Press(704), Photon Geyser(675).
# Part B — per-mon TypeChart-override family (4 moves): Freeze-Dry(573),
#   Tar Shot(695), Foresight(193), Odor Sleuth(316).
#
# Ground truth: reference/pokeemerald_expansion/src/battle_util.c
# (CalcAttackStat EFFECT_FOUL_PLAY/EFFECT_BODY_PRESS L6737-6763,
# SetDynamicMoveCategory/GetCategoryBasedOnStats L8975-9039,
# MulByTypeEffectiveness L8046-8146, GetTotalAccuracy L10259-10261),
# src/battle_stat_change.c (CheckSpecificMoveCondition EFFECT_TAR_SHOT
# L165-173), data/battle_scripts_1.s (BattleScript_EffectForesight
# L2165-2174), GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_foul_play()
	_test_body_press()
	_test_photon_geyser()
	_test_freeze_dry()
	_test_tar_shot()
	_test_foresight()

	var total := _pass + _fail
	print("d2_batch2_test: %d/%d passed" % [_pass, total])
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


# ── Section A: data integrity (7 moves) ─────────────────────────────────────

func _test_data_integrity() -> void:
	var foul_play := _load_move(492)
	_chk("A.01 Foul Play power=95/acc=100/pp=15/PHYS/Dark",
			foul_play.power == 95 and foul_play.accuracy == 100 and foul_play.pp == 15
			and foul_play.category == 0 and foul_play.type == TypeChart.TYPE_DARK)
	_chk("A.02 Foul Play is_foul_play/makes_contact",
			foul_play.is_foul_play == true and foul_play.makes_contact == true)

	var body_press := _load_move(704)
	_chk("A.03 Body Press power=80/acc=100/pp=10/PHYS/Fighting",
			body_press.power == 80 and body_press.accuracy == 100 and body_press.pp == 10
			and body_press.category == 0 and body_press.type == TypeChart.TYPE_FIGHTING)
	_chk("A.04 Body Press is_body_press", body_press.is_body_press == true)

	var photon_geyser := _load_move(675)
	_chk("A.05 Photon Geyser power=100/acc=100/pp=5/SPEC/Psychic",
			photon_geyser.power == 100 and photon_geyser.accuracy == 100 and photon_geyser.pp == 5
			and photon_geyser.category == 1 and photon_geyser.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.06 Photon Geyser is_photon_geyser/ignores_target_ability",
			photon_geyser.is_photon_geyser == true and photon_geyser.ignores_target_ability == true)

	var freeze_dry := _load_move(573)
	_chk("A.07 Freeze-Dry power=70/acc=100/pp=20/SPEC/Ice",
			freeze_dry.power == 70 and freeze_dry.accuracy == 100 and freeze_dry.pp == 20
			and freeze_dry.category == 1 and freeze_dry.type == TypeChart.TYPE_ICE)
	_chk("A.08 Freeze-Dry super_effective_vs_type=WATER",
			freeze_dry.super_effective_vs_type == TypeChart.TYPE_WATER)
	_chk("A.09 Freeze-Dry 10% Freeze secondary",
			freeze_dry.secondary_effect == MoveData.SE_FREEZE and freeze_dry.secondary_chance == 10)

	var tar_shot := _load_move(695)
	_chk("A.10 Tar Shot acc=100/pp=15/STATUS/Rock",
			tar_shot.accuracy == 100 and tar_shot.pp == 15
			and tar_shot.category == 2 and tar_shot.type == TypeChart.TYPE_ROCK)
	_chk("A.11 Tar Shot is_tar_shot/bounceable + guaranteed -1 Speed",
			tar_shot.is_tar_shot == true and tar_shot.bounceable == true
			and tar_shot.stat_change_stat == BattlePokemon.STAGE_SPEED
			and tar_shot.stat_change_amount == -1)

	var foresight := _load_move(193)
	_chk("A.12 Foresight acc=0/pp=40/STATUS/Normal",
			foresight.accuracy == 0 and foresight.pp == 40
			and foresight.category == 2 and foresight.type == TypeChart.TYPE_NORMAL)
	_chk("A.13 Foresight is_foresight/ignores_substitute/bounceable",
			foresight.is_foresight == true and foresight.ignores_substitute == true
			and foresight.bounceable == true)

	var odor_sleuth := _load_move(316)
	_chk("A.14 Odor Sleuth acc=0/pp=40/STATUS/Normal",
			odor_sleuth.accuracy == 0 and odor_sleuth.pp == 40
			and odor_sleuth.category == 2 and odor_sleuth.type == TypeChart.TYPE_NORMAL)
	_chk("A.15 Odor Sleuth is_foresight (LITERAL SAME effect as Foresight)",
			odor_sleuth.is_foresight == true)


# ── Section B: Foul Play ─────────────────────────────────────────────────────

func _test_foul_play() -> void:
	var foul_play := _load_move(492)
	# Weak-Attack user, strong-Attack target — should still hit hard, scaled
	# off the TARGET's own Attack, not the attacker's.
	var weak_atk := _make_mon("FPWeak", [TypeChart.TYPE_DARK], 200, 10, 60, 60, 60, 60)
	var strong_target := _make_mon("FPStrong", [TypeChart.TYPE_NORMAL], 200, 200, 60, 60, 60, 60)
	var weak_target := _make_mon("FPWeakTarget", [TypeChart.TYPE_NORMAL], 200, 10, 60, 60, 60, 60)

	var dmg_strong: int = DamageCalculator.calculate(
			weak_atk, strong_target, foul_play, 100, false)["damage"]
	var dmg_weak: int = DamageCalculator.calculate(
			weak_atk, weak_target, foul_play, 100, false)["damage"]
	_chk("B.01 Foul Play: same weak-Attack user deals MORE damage to a " +
			"strong-Attack target than a weak-Attack target",
			dmg_strong > dmg_weak)

	# Discriminator: a normal move (Tackle-shaped, same power) would deal
	# the SAME damage regardless of the target's own Attack stat (since a
	# plain physical move reads the ATTACKER's Attack, not the target's).
	var plain := MoveData.new()
	plain.type = TypeChart.TYPE_NORMAL
	plain.category = 0
	plain.power = 95
	plain.accuracy = 100
	var plain_strong: int = DamageCalculator.calculate(
			weak_atk, strong_target, plain, 100, false)["damage"]
	var plain_weak: int = DamageCalculator.calculate(
			weak_atk, weak_target, plain, 100, false)["damage"]
	_chk("B.02 discriminator: an ordinary physical move deals the SAME " +
			"damage regardless of the target's own Attack stat",
			plain_strong == plain_weak)

	# Defense stat still comes from the target normally (unaffected).
	var high_def_target := _make_mon("FPHighDef", [TypeChart.TYPE_NORMAL], 200, 200, 300, 60, 60, 60)
	var low_def_target := _make_mon("FPLowDef", [TypeChart.TYPE_NORMAL], 200, 200, 5, 60, 60, 60)
	var dmg_high_def: int = DamageCalculator.calculate(
			weak_atk, high_def_target, foul_play, 100, false)["damage"]
	var dmg_low_def: int = DamageCalculator.calculate(
			weak_atk, low_def_target, foul_play, 100, false)["damage"]
	_chk("B.03 Foul Play's own Defense-side read is unaffected (still the " +
			"target's own Defense, normal physical-category selection)",
			dmg_low_def > dmg_high_def)


# ── Section C: Body Press ────────────────────────────────────────────────────

func _test_body_press() -> void:
	var body_press := _load_move(704)
	# High-Defense/low-Attack user hits harder than its listed category
	# (Physical, driven by Attack normally) would suggest.
	var tank := _make_mon("BPTank", [TypeChart.TYPE_FIGHTING], 200, 10, 200, 60, 60, 60)
	var glass_cannon := _make_mon("BPGlass", [TypeChart.TYPE_FIGHTING], 200, 200, 10, 60, 60, 60)
	var def := _make_mon("BPDef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)

	var dmg_tank: int = DamageCalculator.calculate(
			tank, def, body_press, 100, false)["damage"]
	var dmg_glass: int = DamageCalculator.calculate(
			glass_cannon, def, body_press, 100, false)["damage"]
	_chk("C.01 Body Press: the high-Defense/low-Attack user deals MORE " +
			"damage than the low-Defense/high-Attack user",
			dmg_tank > dmg_glass)

	# Discriminator: an ordinary physical move flips this comparison (the
	# glass cannon, with its high Attack, deals more).
	var plain := MoveData.new()
	plain.type = TypeChart.TYPE_FIGHTING
	plain.category = 0
	plain.power = 80
	plain.accuracy = 100
	var plain_tank: int = DamageCalculator.calculate(
			tank, def, plain, 100, false)["damage"]
	var plain_glass: int = DamageCalculator.calculate(
			glass_cannon, def, plain, 100, false)["damage"]
	_chk("C.02 discriminator: an ordinary physical move deals MORE damage " +
			"from the high-Attack user instead (the comparison flips)",
			plain_glass > plain_tank)


# ── Section D: Photon Geyser ─────────────────────────────────────────────────

func _test_photon_geyser() -> void:
	var photon_geyser := _load_move(675)
	var def := _make_mon("PGDef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)

	# Physically-skewed attacker: Atk > SpAtk -> category swaps to Physical.
	var phys_mon := _make_mon("PGPhys", [TypeChart.TYPE_PSYCHIC], 200, 200, 60, 10, 60, 60)
	var phys_result: Dictionary = DamageCalculator.calculate(
			phys_mon, def, photon_geyser, 100, false)
	# A plain Physical move (same power/type) as a comparison baseline —
	# should deal IDENTICAL damage if Photon Geyser really did swap to
	# Physical and read the Attack stat.
	var plain_phys := MoveData.new()
	plain_phys.type = TypeChart.TYPE_PSYCHIC
	plain_phys.category = 0
	plain_phys.power = 100
	plain_phys.accuracy = 100
	var plain_phys_result: Dictionary = DamageCalculator.calculate(
			phys_mon, def, plain_phys, 100, false)
	_chk("D.01 Photon Geyser: a physically-skewed attacker (Atk>SpAtk) " +
			"deals damage identical to an ordinary Physical move (category " +
			"genuinely swapped, not just a bigger raw number)",
			phys_result["damage"] == plain_phys_result["damage"])

	# Specially-skewed attacker: SpAtk > Atk -> category stays Special.
	var spec_mon := _make_mon("PGSpec", [TypeChart.TYPE_PSYCHIC], 200, 10, 60, 200, 60, 60)
	var spec_result: Dictionary = DamageCalculator.calculate(
			spec_mon, def, photon_geyser, 100, false)
	var plain_spec := MoveData.new()
	plain_spec.type = TypeChart.TYPE_PSYCHIC
	plain_spec.category = 1
	plain_spec.power = 100
	plain_spec.accuracy = 100
	var plain_spec_result: Dictionary = DamageCalculator.calculate(
			spec_mon, def, plain_spec, 100, false)
	_chk("D.02 discriminator: a specially-skewed attacker (SpAtk>Atk) " +
			"stays Special, deals damage identical to an ordinary Special move",
			spec_result["damage"] == plain_spec_result["damage"])

	# Tie (SpAtk == Atk) goes to SPECIAL per source's own `>=` comparison.
	var tie_mon := _make_mon("PGTie", [TypeChart.TYPE_PSYCHIC], 200, 100, 60, 100, 60, 60)
	var tie_result: Dictionary = DamageCalculator.calculate(
			tie_mon, def, photon_geyser, 100, false)
	var plain_spec_tie: Dictionary = DamageCalculator.calculate(
			tie_mon, def, plain_spec, 100, false)
	_chk("D.03 a tied Atk==SpAtk attacker resolves to SPECIAL (source's " +
			"own `spAttack >= attack` tie-break)",
			tie_result["damage"] == plain_spec_tie["damage"])


# ── Section E: Freeze-Dry ─────────────────────────────────────────────────────

func _test_freeze_dry() -> void:
	var freeze_dry := _load_move(573)
	var atk := _make_mon("FDAtk", [TypeChart.TYPE_ICE], 200, 60, 60, 100, 60, 60)
	var water_def := _make_mon("FDWaterDef", [TypeChart.TYPE_WATER], 200, 60, 60, 60, 60, 60)
	var normal_def := _make_mon("FDNormalDef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)

	var water_result: Dictionary = DamageCalculator.calculate(
			atk, water_def, freeze_dry, 100, false)
	_chk("E.01 Freeze-Dry is super-effective (2x) against a pure-Water " +
			"target, which the raw type chart would otherwise leave neutral",
			water_result["effectiveness"] == 2.0)

	var normal_result: Dictionary = DamageCalculator.calculate(
			atk, normal_def, freeze_dry, 100, false)
	_chk("E.02 discriminator: Freeze-Dry is ordinary (neutral) against a " +
			"non-Water target",
			normal_result["effectiveness"] == 1.0)

	# Dual-type defender: only the Water component is forced to 2.0, the
	# OTHER type's own real chart value still applies independently.
	var dual_def := _make_mon("FDDualDef", [TypeChart.TYPE_WATER, TypeChart.TYPE_GROUND],
			200, 60, 60, 60, 60, 60)
	var dual_result: Dictionary = DamageCalculator.calculate(
			atk, dual_def, freeze_dry, 100, false)
	# Ice vs Water=2.0(forced) * Ice vs Ground=2.0(real chart) = 4.0
	_chk("E.03 dual-type defender: only the Water component is forced to " +
			"2.0, the OTHER type's own real chart value still composes " +
			"independently (Water forced 2.0 * Ground real 2.0 = 4.0)",
			dual_result["effectiveness"] == 4.0)


# ── Section F: Tar Shot ──────────────────────────────────────────────────────

func _test_tar_shot() -> void:
	var tar_shot := _load_move(695)
	var fire_move := MoveData.new()
	fire_move.type = TypeChart.TYPE_FIRE
	fire_move.category = 1
	fire_move.power = 40
	fire_move.accuracy = 100
	var water_move := MoveData.new()
	water_move.type = TypeChart.TYPE_WATER
	water_move.category = 1
	water_move.power = 40
	water_move.accuracy = 100

	var target := _make_mon("TSTarget", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	var atk := _make_mon("TSAtk", [TypeChart.TYPE_FIRE], 200, 60, 60, 100, 60, 60)

	var before: Dictionary = DamageCalculator.calculate(atk, target, fire_move, 100, false)
	target.tar_shot_active = true
	var after: Dictionary = DamageCalculator.calculate(atk, target, fire_move, 100, false)
	_chk("F.01 Tar Shot doubles a Fire-type move's effectiveness against " +
			"the flagged target", after["effectiveness"] == before["effectiveness"] * 2.0)

	var water_after: Dictionary = DamageCalculator.calculate(atk, target, water_move, 100, false)
	_chk("F.02 discriminator: Tar Shot does NOT affect a non-Fire-type move",
			water_after["effectiveness"] == 1.0)

	# Persists across multiple hits/turns — a full-battle confirmation.
	# atk2 (not target2) must be the one CASTING Tar Shot, since it's a
	# foe-targeting move — a fixture bug caught on the first run: giving
	# target2 the Tar Shot move would have it cast Tar Shot ONTO atk2
	# instead of receiving it.
	var atk2 := _make_mon("TSAtk2", [TypeChart.TYPE_FIRE], 200, 60, 60, 30, 60, 100)
	atk2.add_move(tar_shot)
	atk2.add_move(fire_move)
	var target2 := _make_mon("TSTarget2", [TypeChart.TYPE_NORMAL], 300, 60, 60, 60, 60, 40)
	var filler := MoveData.new()
	filler.type = TypeChart.TYPE_NORMAL
	filler.category = 0
	filler.power = 10
	filler.accuracy = 100
	target2.add_move(filler)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm._force_roll = 100  # CLAUDE.md: pairwise damage comparisons must force every RNG input
	var dmg_events: Array = []
	bm.move_executed.connect(func(a, _t, m, amt):
		if a == atk2 and m == fire_move:
			dmg_events.append(amt))
	bm.queue_move(0, 0)  # atk2 casts Tar Shot on target2, turn 1
	for _t in range(3):
		bm.queue_move(0, 1)  # atk2 uses fire_move repeatedly afterward
	bm.start_battle(atk2, target2)
	_chk("F.03 Tar Shot's doubling persists across MULTIPLE hits/turns on " +
			"the same target, not a one-shot modifier",
			dmg_events.size() >= 2 and dmg_events[0] > 0 and dmg_events[1] == dmg_events[0])

	# Already-active discriminator: the whole move fails (no re-set, no
	# Speed drop) once already active — direct unit test, not full-battle.
	var already := _make_mon("TSAlready", [TypeChart.TYPE_NORMAL])
	already.tar_shot_active = true
	var bm2 := _make_bm()
	bm2._force_hit = true
	var speed_before: int = already.stat_stages[BattlePokemon.STAGE_SPEED]
	var attacker2 := _make_mon("TSAttacker2", [TypeChart.TYPE_ROCK])
	attacker2.add_move(tar_shot)
	already.add_move(tar_shot)
	var fail_events: Array[String] = []
	bm2.move_effect_failed.connect(func(_a, r: String): fail_events.append(r))
	bm2.start_battle(attacker2, already)
	_chk("F.04 discriminator: Tar Shot fails outright (no Speed drop " +
			"either) once the target is already Tar-Shot'd",
			"tar_shot_already_active" in fail_events
			and already.stat_stages[BattlePokemon.STAGE_SPEED] == speed_before)


# ── Section G: Foresight / Odor Sleuth ───────────────────────────────────────

func _test_foresight() -> void:
	var foresight := _load_move(193)
	var normal_move := MoveData.new()
	normal_move.type = TypeChart.TYPE_NORMAL
	normal_move.category = 0
	normal_move.power = 40
	normal_move.accuracy = 100

	var ghost_def := _make_mon("FGhostDef", [TypeChart.TYPE_GHOST], 200, 60, 60, 60, 60, 60)
	var atk := _make_mon("FAtk", [TypeChart.TYPE_NORMAL], 200, 100, 60, 60, 60, 60)

	var before: Dictionary = DamageCalculator.calculate(atk, ghost_def, normal_move, 100, false)
	_chk("G.01 baseline: a Normal-type move is immune (0x) against a " +
			"Ghost-type target without Foresight", before["effectiveness"] == 0.0)

	ghost_def.foresight_active = true
	var after: Dictionary = DamageCalculator.calculate(atk, ghost_def, normal_move, 100, false)
	_chk("G.02 Foresight bypasses the Ghost-type's Normal-move immunity " +
			"(0x -> 1x, not 2x — a fixed-up neutral, not a boost)",
			after["effectiveness"] == 1.0)

	# Evasion-ignore half — direct StatusManager.check_accuracy unit test.
	var evasive_def := _make_mon("FEvasive", [TypeChart.TYPE_NORMAL])
	evasive_def.stat_stages[BattlePokemon.STAGE_EVASION] = 6  # max evasion
	var tackle := MoveData.new()
	tackle.type = TypeChart.TYPE_NORMAL
	tackle.category = 0
	tackle.power = 40
	tackle.accuracy = 100
	var attacker3 := _make_mon("FAttacker3", [TypeChart.TYPE_NORMAL])

	var hits_low := 0
	for i in range(200):
		if StatusManager.check_accuracy(attacker3, evasive_def, tackle, null, false):
			hits_low += 1
	evasive_def.foresight_active = true
	var hits_high := 0
	for i in range(200):
		if StatusManager.check_accuracy(attacker3, evasive_def, tackle, null, false):
			hits_high += 1
	_chk("G.03 Foresight ignores the target's own evasion stage in the " +
			"accuracy formula (a heavily-evasive target is hit far more " +
			"often once Foresight is active)",
			hits_high > hits_low)

	# Full-battle integration + already-active discriminator.
	var atk4 := _make_mon("FAtk4", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 100)
	atk4.add_move(foresight)
	var def4 := _make_mon("FDef4", [TypeChart.TYPE_GHOST], 200, 60, 60, 60, 60, 40)
	def4.add_move(foresight)
	var bm := _make_bm()
	bm._force_hit = true
	var set_events: Array = []
	bm.foresight_set.connect(func(target: BattlePokemon): set_events.append(target))
	bm.start_battle(atk4, def4)
	_chk("G.04 full-battle: Foresight sets the target's own foresight_active flag",
			def4 in set_events)

	var already := _make_mon("FAlready", [TypeChart.TYPE_GHOST])
	already.foresight_active = true
	var attacker5 := _make_mon("FAttacker5", [TypeChart.TYPE_NORMAL])
	attacker5.add_move(foresight)
	already.add_move(foresight)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var fail_events: Array[String] = []
	bm2.move_effect_failed.connect(func(_a, r: String): fail_events.append(r))
	bm2.start_battle(attacker5, already)
	_chk("G.05 discriminator: Foresight fails once the target already has it",
			"foresight_already_active" in fail_events)
