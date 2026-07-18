extends Node

# [D1] "Already effectively free" candidates flagged by the Section D recon:
# Solar Blade(632), Snipe Shot(691), Hidden Power(237), Hyperspace Fury(621).
# Each reuses infrastructure this project already built and tested elsewhere —
# Step 0 re-verified all 4 fresh rather than trusting the recon's own "free"
# label, per this arc's standing rule.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# src/battle_move_resolution.c (IsAffectedByFollowMe L799-817,
# HandleMoveTargetRedirection L822-888), src/battle_main.c
# (GetMoveAteType L5725-5768, GetDynamicMoveType's EFFECT_HIDDEN_POWER case
# L5851-5869), src/data/battle_move_effects.h (EFFECT_HYPERSPACE_FURY),
# src/data/types_info.h (isHiddenPowerType), GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_solar_blade_charge_skip()
	_test_snipe_shot_bypasses_redirection()
	_test_hidden_power_type_from_ivs()
	_test_hidden_power_not_ability_mutated()
	_test_hyperspace_fury_full_battle()

	var total := _pass + _fail
	print("m19_d1_free_test: %d/%d passed" % [_pass, total])
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


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _make_mon(mon_name: String, types: Array[int], base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60, ivs: Array = [0, 0, 0, 0, 0, 0]) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	var typed_ivs: Array[int] = []
	for v in ivs:
		typed_ivs.append(v)
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, typed_ivs)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section A: data integrity (all 4 moves) ─────────────────────────────────

func _test_data_integrity() -> void:
	var solar_blade := _load_move(632)
	_chk("A.01 632 Solar Blade: Grass/PHYSICAL/125/100/10, makes_contact, " +
			"slicing_move, two_turn, is_solar_beam",
			solar_blade.type == TypeChart.TYPE_GRASS and solar_blade.category == 0
					and solar_blade.power == 125 and solar_blade.accuracy == 100
					and solar_blade.pp == 10 and solar_blade.makes_contact
					and solar_blade.slicing_move and solar_blade.two_turn
					and solar_blade.is_solar_beam)

	var snipe_shot := _load_move(691)
	_chk("A.02 691 Snipe Shot: Water/SPECIAL/80/100/15, crit_stage=1, " +
			"ignores_redirection",
			snipe_shot.type == TypeChart.TYPE_WATER and snipe_shot.category == 1
					and snipe_shot.power == 80 and snipe_shot.accuracy == 100
					and snipe_shot.pp == 15 and snipe_shot.critical_hit_stage == 1
					and snipe_shot.ignores_redirection)

	var hidden_power := _load_move(237)
	_chk("A.03 237 Hidden Power: Normal/SPECIAL/60(flat, NOT IV-derived)/100/15, " +
			"is_hidden_power",
			hidden_power.type == TypeChart.TYPE_NORMAL and hidden_power.category == 1
					and hidden_power.power == 60 and hidden_power.accuracy == 100
					and hidden_power.pp == 15 and hidden_power.is_hidden_power)

	var hyperspace_fury := _load_move(621)
	_chk("A.04 621 Hyperspace Fury: Dark/PHYSICAL/100/acc0(never misses)/5, " +
			"ignores_protect, ignores_substitute, breaks_protect, self -1 Def",
			hyperspace_fury.type == TypeChart.TYPE_DARK and hyperspace_fury.category == 0
					and hyperspace_fury.power == 100 and hyperspace_fury.accuracy == 0
					and hyperspace_fury.pp == 5 and hyperspace_fury.ignores_protect
					and hyperspace_fury.ignores_substitute and hyperspace_fury.breaks_protect
					and hyperspace_fury.stat_change_stat == 1  # STAGE_DEF
					and hyperspace_fury.stat_change_amount == -1
					and hyperspace_fury.stat_change_self)


# ── Section B: Solar Blade — charge-skip-in-sun (reusing two_turn_test's own
# established pattern, not re-deriving exact damage numbers) ────────────────

func _test_solar_blade_charge_skip() -> void:
	var solar_blade := _load_move(632)
	var tackle := _load_move(33)

	var atk := _make_mon("B1Atk", [TypeChart.TYPE_GRASS], 100, 100, 60, 60, 60, 100)
	atk.add_move(solar_blade)
	var def := _make_mon("B1Def", [TypeChart.TYPE_NORMAL], 400, 10, 60, 10, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm.weather = BattleManager.WEATHER_SUN
	# weather_duration left at 0 so sun never expires mid-battle.
	var charge_count := [0]
	var damaged := [false]
	bm.charge_started.connect(func(_a, _m): charge_count[0] += 1)
	bm.move_executed.connect(func(a, _d, _m, dmg):
		if a == atk and dmg > 0:
			damaged[0] = true)
	bm.queue_move(1, 0)
	bm.start_battle_with_parties(BattleParty.single(atk), BattleParty.single(def))
	_chk("B.01 Solar Blade fires immediately in sun (no charge_started, matching " +
			"Solar Beam's own is_solar_beam dispatch)",
			charge_count[0] == 0)
	_chk("B.02 Solar Blade dealt real damage on turn 1 (Physical category, uses " +
			"Attack/Defense correctly despite reusing Solar Beam's Special-shaped " +
			"dispatch)",
			damaged[0] == true)

	# Discriminator: NOT sun -> takes 2 turns (charges first).
	var atk2 := _make_mon("B2Atk", [TypeChart.TYPE_GRASS], 100, 100, 60, 60, 60, 100)
	atk2.add_move(solar_blade)
	var def2 := _make_mon("B2Def", [TypeChart.TYPE_NORMAL], 400, 10, 60, 10, 60, 40)
	def2.add_move(tackle)
	var bm2 := _make_bm()
	var charge_count2 := [0]
	bm2.charge_started.connect(func(_a, _m): charge_count2[0] += 1)
	bm2.queue_move(1, 0)
	bm2.start_battle_with_parties(BattleParty.single(atk2), BattleParty.single(def2))
	_chk("B.03 discriminator: without sun, Solar Blade DOES charge first (charge_started fired)",
			charge_count2[0] >= 1)


# ── Section C: Snipe Shot bypasses redirection ──────────────────────────────

func _test_snipe_shot_bypasses_redirection() -> void:
	var snipe_shot := _load_move(691)
	var tackle := _load_move(33)
	var follow_me := _load_move(266)

	# (i) Snipe Shot ignores an active Follow Me and hits the ORIGINAL target,
	# not the Follow Me user.
	var atk := _make_mon("C1Atk", [TypeChart.TYPE_WATER], 100, 60, 60, 100, 60, 100)
	atk.add_move(snipe_shot)
	var atk_ally := _make_mon("C1AtkAlly", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk_ally.add_move(tackle)
	var fm_target := _make_mon("C1FMTarget", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	fm_target.add_move(tackle)
	var fm_user := _make_mon("C1FMUser", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 90)
	fm_user.add_move(follow_me)

	# Whole-battle-aggregation guard: this battle runs to completion, and later
	# turns can legitimately retarget once fm_target faints — isolate atk's own
	# FIRST hit only, matching the established "queue exactly the action under
	# test, read the first matching signal" convention.
	var first_hit := [false, null]
	var bm := _make_bm()
	bm._force_hit = true
	bm.move_executed.connect(func(a, d, _m, dmg):
		if a == atk and dmg > 0 and not first_hit[0]:
			first_hit[0] = true
			first_hit[1] = d)
	bm.queue_move(1, 0)  # atk uses Snipe Shot on turn 1 (targets fm_target by default)
	bm.start_battle_doubles(_doubles_party(atk, atk_ally), _doubles_party(fm_target, fm_user))
	_chk("C.01 Snipe Shot bypasses an active Follow Me and hits its real target, " +
			"not the Follow Me user (first_hit=%s)" % [first_hit],
			first_hit[0] == true and first_hit[1] == fm_target)

	# (ii) Discriminator: a plain move (Tackle) IS redirected to the Follow Me user
	# in the same setup.
	var atk2 := _make_mon("C2Atk", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	atk2.add_move(tackle)
	var atk2_ally := _make_mon("C2AtkAlly", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk2_ally.add_move(tackle)
	var fm_target2 := _make_mon("C2FMTarget", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	fm_target2.add_move(tackle)
	var fm_user2 := _make_mon("C2FMUser", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 90)
	fm_user2.add_move(follow_me)

	var first_hit2 := [false, null]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_executed.connect(func(a, d, _m, dmg):
		if a == atk2 and dmg > 0 and not first_hit2[0]:
			first_hit2[0] = true
			first_hit2[1] = d)
	bm2.queue_move(1, 0)
	bm2.start_battle_doubles(_doubles_party(atk2, atk2_ally), _doubles_party(fm_target2, fm_user2))
	_chk("C.02 discriminator: a plain Tackle IS redirected to the Follow Me user " +
			"in the same setup (first_hit2=%s)" % [first_hit2],
			first_hit2[0] == true and first_hit2[1] == fm_user2)


# ── Section D: Hidden Power's IV-derived type ───────────────────────────────

func _test_hidden_power_type_from_ivs() -> void:
	var hidden_power := _load_move(237)
	var splash := MoveData.new()
	splash.move_name = "Splash"
	splash.type = TypeChart.TYPE_NORMAL
	splash.category = 2
	splash.accuracy = 0
	splash.pp = 40

	# Direct unit tests via DamageCalculator._hidden_power_type, matching
	# CLAUDE.md's own testing-scope convention (deterministic formula check,
	# no RNG/battle needed) — 3 different synthetic IV spreads, per the
	# task's explicit instruction not to trust just one.
	# Bit order: bit0=HP, bit1=Atk, bit2=Def, bit3=SPEED, bit4=SpAtk, bit5=SpDef
	# (source order — NOT this project's own ivs[] array order, which places
	# Speed LAST at index 5, not bit-position 3).
	# hpTypes = [FIGHTING,FLYING,POISON,GROUND,ROCK,BUG,GHOST,STEEL,FIRE,WATER,
	#            GRASS,ELECTRIC,PSYCHIC,ICE,DRAGON,DARK]  (16 entries)

	# All IVs even (all low bits 0) -> type_bits=0 -> index=0 -> FIGHTING.
	var mon_a := _make_mon("D1All0", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60,
			[0, 0, 0, 0, 0, 0])
	_chk("D.01 all-even IVs (type_bits=0) -> Fighting (index 0)",
			DamageCalculator._hidden_power_type(mon_a) == TypeChart.TYPE_FIGHTING)

	# All IVs odd (all low bits 1) -> type_bits=63 -> index=(15*63)/63=15 -> DARK (last).
	var mon_b := _make_mon("D2All1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60,
			[31, 31, 31, 31, 31, 31])
	_chk("D.02 all-odd IVs (type_bits=63) -> Dark (index 15, the LAST entry)",
			DamageCalculator._hidden_power_type(mon_b) == TypeChart.TYPE_DARK)

	# KEY discriminator for the ordering trap: only Speed IV is odd (bit3=1,
	# everything else 0) -> type_bits=8 -> index=(15*8)/63=1 -> FLYING.
	# If the implementation wrongly read this project's own ivs[3] (SpAtk in
	# this project's array, not Speed), it would instead read SpAtk's IV
	# (even, 0) and produce type_bits=0 -> Fighting instead — a silently
	# wrong type that this specific spread is designed to catch.
	var mon_c := _make_mon("D3OnlySpeedOdd", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60,
			[0, 0, 0, 0, 0, 31])  # ivs array order: HP,Atk,Def,SpAtk,SpDef,Speed
	_chk("D.03 discriminator (ordering trap): only Speed IV odd -> Flying (index 1), " +
			"NOT Fighting (which a SpAtk/Speed index mixup would silently produce)",
			DamageCalculator._hidden_power_type(mon_c) == TypeChart.TYPE_FLYING)

	# Full-battle confirmation: the real dispatch produces the same type as the
	# direct unit test for a representative spread.
	var atk := _make_mon("D4Atk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 100, 60, 100,
			[31, 31, 31, 31, 31, 31])
	atk.add_move(hidden_power)
	var def := _make_mon("D4Def", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def.add_move(splash)
	var bm := _make_bm()
	bm._force_hit = true
	var damaged := [false, -1]
	bm.move_executed.connect(func(a, _d, _m, dmg):
		if a == atk and not damaged[0]:
			damaged[0] = true
			damaged[1] = dmg)
	bm.start_battle(atk, def)
	_chk("D.04 Hidden Power deals real damage through the actual dispatch path " +
			"(dark-type, all-odd IVs) (%s)" % [damaged],
			damaged[0] == true and damaged[1] > 0)


func _test_hidden_power_not_ability_mutated() -> void:
	var hidden_power := _load_move(237)

	# Pixilate would normally convert a Normal-type move to Fairy — confirm
	# Hidden Power is explicitly excluded from that pipeline.
	var pixilate_holder := _make_mon("E1Pix", [TypeChart.TYPE_NORMAL], 100, 60, 60, 100, 60, 100,
			[0, 0, 0, 0, 0, 0])  # -> Fighting-type Hidden Power
	pixilate_holder.ability = _load_ability(182)  # Pixilate
	var mutated: int = AbilityManager.effective_move_type(pixilate_holder, hidden_power, false)
	_chk("E.01 effective_move_type returns -1 (no override) for Hidden Power even " +
			"with a Pixilate holder — Normalize-family abilities must never touch " +
			"its IV-derived type (got=%d)" % [mutated],
			mutated == -1)

	# Discriminator: Pixilate DOES still convert an ordinary Normal-type move.
	var tackle := _load_move(33)
	var mutated2: int = AbilityManager.effective_move_type(pixilate_holder, tackle, false)
	_chk("E.02 discriminator: the same Pixilate holder's Tackle IS converted to " +
			"Fairy (got=%d)" % [mutated2],
			mutated2 == TypeChart.TYPE_FAIRY)


# ── Section F: Hyperspace Fury — Protect-break + self stat-drop together ────

func _test_hyperspace_fury_full_battle() -> void:
	var hyperspace_fury := _load_move(621)
	var protect := _load_move(182)
	var tackle := _load_move(33)

	var atk := _make_mon("F1Atk", [TypeChart.TYPE_DARK], 100, 100, 60, 60, 60, 100)
	atk.add_move(hyperspace_fury)
	var def := _make_mon("F1Def", [TypeChart.TYPE_NORMAL], 300, 60, 60, 60, 60, 40)
	def.add_move(protect)
	def.protect_active = true  # simulate an already-up Protect

	var bm := _make_bm()
	bm._force_hit = true
	var protect_broken := [false]
	bm.protect_broken.connect(func(mon):
		if mon == def:
			protect_broken[0] = true)
	# Signal-snapshot discipline: this battle runs to completion, and Hyperspace
	# Fury's guaranteed self -1 Defense re-fires every turn the attacker acts
	# (no "already applied" gate) — reading atk.stat_stages post-battle would
	# see it accumulated across however many turns elapsed, a fresh instance of
	# the documented whole-battle-aggregation pitfall. Snapshot both facts live.
	# A real ordering trap found while writing this test: `_do_damaging_hit`
	# emits `move_executed` BEFORE its own later recoil/drain/breaks_protect/
	# stat-change-on-hit dispatch blocks run (confirmed via direct source
	# read — `move_executed.emit(...)` sits right after `target.current_hp`
	# is reduced, well before the stat-change block further down the same
	# function) — so the stat-drop must be snapshotted via its OWN
	# `stat_stage_changed` signal instead, not inferred from move_executed's
	# own timing.
	var damaged := [false, -1]
	var stage_snapshot := [false, 0]
	bm.stat_stage_changed.connect(func(mon, stat, _delta):
		if mon == atk and stat == 1 and not stage_snapshot[0]:
			stage_snapshot[0] = true
			stage_snapshot[1] = atk.stat_stages[1])
	bm.move_executed.connect(func(a, _d, _m, dmg):
		if a == atk and not damaged[0]:
			damaged[0] = true
			damaged[1] = dmg)
	bm.start_battle_with_parties(BattleParty.single(atk), BattleParty.single(def))
	_chk("F.01 Hyperspace Fury breaks an already-up Protect (ignores_protect + " +
			"breaks_protect both fire)",
			protect_broken[0] == true)
	_chk("F.02 Hyperspace Fury deals real damage in the SAME hit that broke Protect " +
			"(damage=%s)" % [damaged],
			damaged[0] == true and damaged[1] > 0)
	_chk("F.03 Hyperspace Fury's guaranteed self -1 Defense ALSO fires in the same " +
			"hit (snapshotted live via stat_stage_changed: %s)" % [stage_snapshot],
			stage_snapshot[0] == true and stage_snapshot[1] == -1)
