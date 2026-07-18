extends Node

# M17n-6 test suite — Group 5: type-effectiveness-pipeline leftovers, including
# Wonder Guard (the highest-risk remaining item in all of M17 per docs/m17_recon.md's
# own flag). 11 abilities: Wonder Guard (25), Scrappy (113), Overcoat (142),
# Normalize (96), Refrigerate (174), Pixilate (182), Galvanize (206),
# Liquid Voice (204), Mind's Eye (300), plus a follow-up session's Aerilate (184)
# and Dragonize (312) — both explicit exclusion reversals confirmed by Rob (see
# docs/decisions.md's [M17n-6] entry for the full flag/confirmation on Dragonize,
# which sits in the reference tree's own hack-custom ability cluster but has since
# become real in a newer generation than that tree models).
#
# Four genuinely different mechanic shapes:
#   A. Wonder Guard — blocks a damaging hit entirely unless the combined type-
#      effectiveness multiplier is strictly >1.0x. Required a genuine pipeline
#      restructure: it reads `effectiveness` AFTER DamageCalculator.calculate computes
#      it (unlike Levitate/the absorb family/Telepathy, all flat 0x-or-nothing checks
#      that ran BEFORE type effectiveness existed as a value).
#   B. Scrappy / Mind's Eye — the ATTACKER's Normal/Fighting moves bypass a Ghost-type
#      defender's flat immunity, threaded into TypeChart's own per-component
#      computation (both get_effectiveness and get_uq412), mirroring the Delta Stream
#      weaken_flying_se precedent. Mind's Eye also independently ignores the
#      defender's evasion stat-stage boosts (reuses the pre-existing
#      ignores_defender_evasion_stage function, which already anticipated this).
#   C. Overcoat — two independent halves: full powder-move immunity (reuses the
#      Soundproof/Bulletproof blocks_move_flag shape) and full sandstorm/hail
#      weather-chip immunity (a new per-mon exemption alongside Air Lock/Cloud Nine's
#      existing field-wide negation).
#   D. Normalize / Refrigerate / Pixilate / Galvanize / Aerilate / Dragonize /
#      Liquid Voice — move-TYPE
#      mutation, a genuinely different shape from every other ability in this project
#      (mutates the move, not the attacker/defender's read of it). Implemented via a
#      shallow-duplicated MoveData with only `.type` overridden, substituted for
#      `move` at the very top of DamageCalculator.calculate — every existing
#      type-aware ability/item check downstream sees the mutated type "for free."
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state.
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing test function.
#   - Type immunity precedes ability logic: neutral (Normal-vs-Normal) matchups chosen
#     by default; Ghost/Flying/etc. matchups used ONLY where the mechanic under test
#     is itself type-specific.
#   - Pairwise damage comparisons force BOTH _force_roll and _force_crit on every
#     scenario compared.
#   - Repeatable-effect auto-select pitfall: no assertion here depends on "this battle
#     ran exactly N turns" — battles are either single direct DamageCalculator.calculate()
#     calls, or full battles where the asserted outcome is invariant across repeats
#     (an ability that blocks something blocks it every time it's retried, so reading
#     the aggregated event list with `.any()`/`.filter()` is safe without first-event
#     slicing) rather than "did this happen exactly once."
#
# Ground truth: pokeemerald_expansion src/battle_util.c ::
#   CalcTypeEffectivenessMultiplierInternal (L8134-8270), MulByTypeEffectiveness
#   (L8036-8083), IsAffectedByPowderMove (L10545-10552), IsPowderMoveBlocked
#   (L2216-2229); src/battle_end_turn.c :: HandleEndTurnWeatherDamage (L100-186);
#   src/battle_main.c :: GetBattleMoveType (L5993-6024), TrySetAteType (L5724-5766);
#   src/battle_util.c :: CalcMoveBasePowerAfterModifiers's ability switch (L6530-6552).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_wonder_guard_direct_unit()
	_test_section_3_wonder_guard_mold_breaker_ng()
	_test_section_4_wonder_guard_full_battle_blocked()
	_test_section_5_wonder_guard_full_battle_not_blocked()
	_test_section_6_wonder_guard_status_move_exempt()
	_test_section_7_wonder_guard_fixed_damage_move()
	_test_section_8_scrappy_direct_and_discriminator()
	_test_section_9_scrappy_full_battle()
	_test_section_10_scrappy_mold_breaker_ng()
	_test_section_11_minds_eye_ghost_bypass_half()
	_test_section_12_minds_eye_evasion_ignore_half()
	_test_section_13_minds_eye_independence_discriminator()
	_test_section_14_overcoat_powder_immunity()
	_test_section_15_overcoat_weather_chip_immunity()
	_test_section_16_overcoat_air_lock_composition()
	_test_section_17_normalize_non_normal_move()
	_test_section_18_normalize_already_normal_move()
	_test_section_19_ate_family()
	_test_section_20_liquid_voice()
	_test_section_21_type_mutation_ng_suppression()
	_test_section_22_negative_control()

	var total := _pass + _fail
	print("m17n6_test: %d/%d passed" % [_pass, total])
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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [M18.5h-1/2] pinned neutral nature + zero IVs -- exact-value assertions predate both


func _synth_move(power: int, category: int, move_type: int) -> MoveData:
	var m := MoveData.new()
	m.type = move_type
	m.category = category
	m.power = power
	m.accuracy = 100
	return m


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var wonder_guard := _load_ability(25)
	_chk("S1.01 Wonder Guard id=25, breakable=true, cant_be_copied=true, cant_be_swapped=true",
			wonder_guard.ability_id == 25 and wonder_guard.breakable
			and wonder_guard.cant_be_copied and wonder_guard.cant_be_swapped)

	var normalize := _load_ability(96)
	_chk("S1.02 Normalize id=96, no breakable flag (attacker-self-check)",
			normalize.ability_id == 96 and not normalize.breakable)

	var scrappy := _load_ability(113)
	_chk("S1.03 Scrappy id=113, no breakable flag (attacker-self-check)",
			scrappy.ability_id == 113 and not scrappy.breakable)

	var overcoat := _load_ability(142)
	_chk("S1.04 Overcoat id=142, breakable=true",
			overcoat.ability_id == 142 and overcoat.breakable)

	var refrigerate := _load_ability(174)
	_chk("S1.05 Refrigerate id=174, no breakable flag", refrigerate.ability_id == 174 and not refrigerate.breakable)

	var pixilate := _load_ability(182)
	_chk("S1.06 Pixilate id=182, no breakable flag", pixilate.ability_id == 182 and not pixilate.breakable)

	var liquid_voice := _load_ability(204)
	_chk("S1.07 Liquid Voice id=204, no breakable flag", liquid_voice.ability_id == 204 and not liquid_voice.breakable)

	var galvanize := _load_ability(206)
	_chk("S1.08 Galvanize id=206, no breakable flag", galvanize.ability_id == 206 and not galvanize.breakable)

	var minds_eye := _load_ability(300)
	_chk("S1.09 Mind's Eye id=300, breakable=true (source-faithful, though structurally " +
			"unreachable by either of its own two attacker-self-check mechanics)",
			minds_eye.ability_id == 300 and minds_eye.breakable)

	# M17n-6 follow-up: Aerilate (Mega-exclusivity exclusion reversed) and Dragonize
	# (hack-ID-to-canon reclassification, an explicit deliberate override — see
	# docs/decisions.md's [M17n-6] entry for the full flag/confirmation). Neither
	# carries a breakable flag in source (both attacker-self-checks, same as the
	# rest of this family).
	var aerilate := _load_ability(184)
	_chk("S1.10 Aerilate id=184, no breakable flag", aerilate.ability_id == 184 and not aerilate.breakable)

	var dragonize := _load_ability(312)
	_chk("S1.11 Dragonize id=312, no breakable flag", dragonize.ability_id == 312 and not dragonize.breakable)


# ── Section 2: Wonder Guard — direct blocks_non_super_effective_hit unit tests ──

func _test_section_2_wonder_guard_direct_unit() -> void:
	var tackle := _load_move(33)     # Normal, physical
	var ice_beam := _load_move(58)   # Ice, special
	var ember := _load_move(52)      # Fire, special
	var wonder_guard := _load_ability(25)

	var wg_water := _make_mon("WGWater", [TypeChart.TYPE_WATER])
	wg_water.ability = wonder_guard
	var eff_nve: float = TypeChart.get_effectiveness(TypeChart.TYPE_ICE, wg_water.species.types)
	_chk("S2.01 sanity: Ice vs Water is 0.5x (NVE)", eff_nve == 0.5)
	_chk("S2.02 Wonder Guard blocks a 0.5x (NVE) hit",
			AbilityManager.blocks_non_super_effective_hit(wg_water, eff_nve, ice_beam))

	var wg_normal := _make_mon("WGNormal", [TypeChart.TYPE_NORMAL])
	wg_normal.ability = wonder_guard
	var eff_neutral: float = TypeChart.get_effectiveness(TypeChart.TYPE_NORMAL, wg_normal.species.types)
	_chk("S2.03 sanity: Normal vs Normal is 1.0x (neutral)", eff_neutral == 1.0)
	_chk("S2.04 Wonder Guard blocks a 1.0x (neutral) hit",
			AbilityManager.blocks_non_super_effective_hit(wg_normal, eff_neutral, tackle))

	var wg_grass := _make_mon("WGGrass", [TypeChart.TYPE_GRASS])
	wg_grass.ability = wonder_guard
	var eff_se: float = TypeChart.get_effectiveness(TypeChart.TYPE_FIRE, wg_grass.species.types)
	_chk("S2.05 sanity: Fire vs Grass is 2.0x (super effective)", eff_se == 2.0)
	_chk("S2.06 Wonder Guard does NOT block a 2.0x (super effective) hit",
			not AbilityManager.blocks_non_super_effective_hit(wg_grass, eff_se, ember))

	# Struggle exclusion — TYPE_MYSTERY never reaches this project's own
	# type-effectiveness computation at all, matching source's separate
	# `ctx->move != MOVE_STRUGGLE` guard.
	var struggle := MoveData.new()
	struggle.type = TypeChart.TYPE_MYSTERY
	struggle.category = 0
	struggle.power = 50
	struggle.is_struggle = true
	_chk("S2.07 Wonder Guard does NOT block Struggle (TYPE_MYSTERY excluded, matching " +
			"the existing move.type != TYPE_MYSTERY guards this function mirrors)",
			not AbilityManager.blocks_non_super_effective_hit(wg_normal, 1.0, struggle))

	var plain := _make_mon("PlainWG", [TypeChart.TYPE_NORMAL])
	_chk("S2.08 negative control: an ordinary Pokemon is never blocked regardless of effectiveness",
			not AbilityManager.blocks_non_super_effective_hit(plain, 0.5, tackle))


# ── Section 3: Wonder Guard — Mold Breaker bypass + Neutralizing Gas suppression ──

func _test_section_3_wonder_guard_mold_breaker_ng() -> void:
	var tackle := _load_move(33)
	var wonder_guard := _load_ability(25)
	var mold_breaker := _load_ability(104)

	var wg_holder := _make_mon("WGMoldBreaker", [TypeChart.TYPE_NORMAL])
	wg_holder.ability = wonder_guard
	var mb_attacker := _make_mon("MBAttackerWG", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker

	_chk("S3.01 Mold Breaker bypasses Wonder Guard (breakable=true, genuinely reachable " +
			"since attacker and holder are always different battlers)",
			not AbilityManager.blocks_non_super_effective_hit(wg_holder, 1.0, tackle, false, mb_attacker))
	_chk("S3.02 without Mold Breaker, the same scenario IS blocked (sanity check)",
			AbilityManager.blocks_non_super_effective_hit(wg_holder, 1.0, tackle))

	_chk("S3.03 Neutralizing Gas suppresses Wonder Guard",
			not AbilityManager.blocks_non_super_effective_hit(wg_holder, 1.0, tackle, true))


# ── Section 4: Wonder Guard — full battle, NVE hit blocked ──────────────────

func _test_section_4_wonder_guard_full_battle_blocked() -> void:
	var ice_beam := _load_move(58)  # Ice, special
	var wonder_guard := _load_ability(25)

	var attacker := _make_mon("WGBattleAttacker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 80, 60, 60)
	attacker.add_move(ice_beam)
	var wg_holder := _make_mon("WGBattleHolder", [TypeChart.TYPE_WATER], 100, 40, 40, 40, 40, 40)
	wg_holder.ability = wonder_guard
	wg_holder.add_move(ice_beam)

	var move_executed_events := []
	var triggered_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.ability_triggered.connect(func(p, k): triggered_events.push_back([p, k]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(wg_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == wg_holder)
	_chk("S4.01 Wonder Guard blocked the NVE (Ice vs Water, 0.5x) hit entirely",
			not hit.is_empty() and hit[0][3] == 0)
	_chk("S4.02 wonder_guard signal fired (discriminator vs ordinary type immunity)",
			triggered_events.any(func(e): return e[0] == wg_holder and e[1] == "wonder_guard"))

	bm.queue_free()


# ── Section 5: Wonder Guard — full battle, super-effective hit connects ─────

func _test_section_5_wonder_guard_full_battle_not_blocked() -> void:
	var ember := _load_move(52)  # Fire, special
	var wonder_guard := _load_ability(25)

	var attacker := _make_mon("WGSEAttacker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 80, 60, 60)
	attacker.add_move(ember)
	var wg_holder := _make_mon("WGSEHolder", [TypeChart.TYPE_GRASS], 100, 40, 40, 40, 40, 40)
	wg_holder.ability = wonder_guard
	wg_holder.add_move(ember)

	var move_executed_events := []
	var triggered_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.ability_triggered.connect(func(p, k): triggered_events.push_back([p, k]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(wg_holder))

	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == wg_holder)
	_chk("S5.01 Wonder Guard does NOT block a super-effective (Fire vs Grass, 2.0x) hit",
			not hit.is_empty() and hit[0][3] > 0)
	_chk("S5.02 wonder_guard signal did NOT fire for the super-effective hit",
			not triggered_events.any(func(e): return e[1] == "wonder_guard"))

	bm.queue_free()


# ── Section 6: Wonder Guard — status moves are exempt (power=0) ─────────────

func _test_section_6_wonder_guard_status_move_exempt() -> void:
	var growl := _load_move(45)  # Normal, status, power=0
	var wonder_guard := _load_ability(25)

	_chk("S6.01 direct: Wonder Guard's own check never fires for a power=0 move",
			not AbilityManager.blocks_non_super_effective_hit(
					_make_with_ability("WGStatusHolder", wonder_guard), 1.0, growl))

	var attacker := _make_mon("WGStatusAttacker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	attacker.add_move(growl)
	var wg_holder := _make_mon("WGStatusBattleHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	wg_holder.ability = wonder_guard
	wg_holder.add_move(growl)

	var stat_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))
	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(wg_holder))

	_chk("S6.02 full battle: Growl still lowers the Wonder Guard holder's Attack " +
			"(status moves are entirely unaffected by Wonder Guard)",
			stat_events.any(func(e): return e[0] == wg_holder and e[1] == BattlePokemon.STAGE_ATK and e[2] < 0))

	bm.queue_free()


func _make_with_ability(mon_name: String, ability: AbilityData) -> BattlePokemon:
	var mon := _make_mon(mon_name, [TypeChart.TYPE_NORMAL])
	mon.ability = ability
	return mon


# ── Section 7: Wonder Guard — fixed/level-damage moves still blocked ────────

func _test_section_7_wonder_guard_fixed_damage_move() -> void:
	var night_shade := _load_move(101)  # Ghost, level_damage, power=1 (placeholder)
	var wonder_guard := _load_ability(25)

	var attacker := _make_mon("WGFixedAttacker", [TypeChart.TYPE_GHOST], 100, 60, 60, 60, 60, 60)

	var wg_dark := _make_mon("WGFixedDark", [TypeChart.TYPE_DARK], 100, 40, 40, 40, 40, 40)
	wg_dark.ability = wonder_guard
	var result_nve: Dictionary = DamageCalculator.calculate(attacker, wg_dark, night_shade, 100, false)
	_chk("S7.01 sanity: Ghost vs Dark is 0.5x (NVE)", result_nve["effectiveness"] == 0.5)
	_chk("S7.02 Wonder Guard blocks Night Shade (a level-damage move) when NVE, " +
			"despite it normally bypassing the standard formula entirely",
			result_nve["damage"] == 0 and result_nve.get("wonder_guard_blocked", false))

	var wg_ghost := _make_mon("WGFixedGhost", [TypeChart.TYPE_GHOST], 100, 40, 40, 40, 40, 40)
	wg_ghost.ability = wonder_guard
	var result_se: Dictionary = DamageCalculator.calculate(attacker, wg_ghost, night_shade, 100, false)
	_chk("S7.03 sanity: Ghost vs Ghost is 2.0x (super effective)", result_se["effectiveness"] == 2.0)
	_chk("S7.04 Wonder Guard does NOT block Night Shade when super effective — the " +
			"level-based damage (attacker.level) connects normally",
			result_se["damage"] == attacker.level and not result_se.get("wonder_guard_blocked", false))


# ── Section 8: Scrappy — direct TypeChart bypass + discriminator ────────────

func _test_section_8_scrappy_direct_and_discriminator() -> void:
	var scrappy := _load_ability(113)
	var scrappy_holder := _make_mon("ScrappyHolder", [TypeChart.TYPE_NORMAL])
	scrappy_holder.ability = scrappy
	var plain := _make_mon("PlainScrappy", [TypeChart.TYPE_NORMAL])

	_chk("S8.01 bypasses_ghost_immunity: Scrappy holder → true",
			AbilityManager.bypasses_ghost_immunity(scrappy_holder) == true)
	_chk("S8.02 bypasses_ghost_immunity: plain attacker → false",
			AbilityManager.bypasses_ghost_immunity(plain) == false)

	_chk("S8.03 sanity: Normal vs Ghost is normally 0.0x (flat immune)",
			TypeChart.get_effectiveness(TypeChart.TYPE_NORMAL, [TypeChart.TYPE_GHOST]) == 0.0)
	_chk("S8.04 Scrappy bypass: Normal vs Ghost becomes 1.0x",
			TypeChart.get_effectiveness(TypeChart.TYPE_NORMAL, [TypeChart.TYPE_GHOST], false, true) == 1.0)
	_chk("S8.05 Scrappy bypass: Fighting vs Ghost becomes 1.0x too",
			TypeChart.get_effectiveness(TypeChart.TYPE_FIGHTING, [TypeChart.TYPE_GHOST], false, true) == 1.0)
	_chk("S8.06 get_uq412 mirrors the same bypass",
			TypeChart.get_uq412(TypeChart.TYPE_NORMAL, TypeChart.TYPE_GHOST, true) == TypeChart.UQ412_NEUTRAL)

	# Discriminator: Scrappy does NOT bypass an UNRELATED type immunity (Ground vs
	# Flying) — it is Ghost/Normal/Fighting-specific by construction.
	_chk("S8.07 sanity: Ground vs Flying is normally 0.0x (Levitate-style immunity, " +
			"unrelated to Scrappy)",
			TypeChart.get_effectiveness(TypeChart.TYPE_GROUND, [TypeChart.TYPE_FLYING]) == 0.0)
	_chk("S8.08 Scrappy's bypass flag does NOT affect Ground vs Flying",
			TypeChart.get_effectiveness(TypeChart.TYPE_GROUND, [TypeChart.TYPE_FLYING], false, true) == 0.0)


# ── Section 9: Scrappy — full battle ─────────────────────────────────────────

func _test_section_9_scrappy_full_battle() -> void:
	var tackle := _load_move(33)  # Normal, physical
	var scrappy := _load_ability(113)

	var scrappy_attacker := _make_mon("ScrappyBattleAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	scrappy_attacker.ability = scrappy
	scrappy_attacker.add_move(tackle)
	var ghost_target := _make_mon("ScrappyBattleGhost", [TypeChart.TYPE_GHOST], 100, 40, 40, 40, 40, 40)
	ghost_target.add_move(tackle)

	var move_executed_events := []
	var move_missed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.move_missed.connect(func(a, r): move_missed_events.push_back([a, r]))
	bm.start_battle_with_parties(BattleParty.single(scrappy_attacker), BattleParty.single(ghost_target))

	var hit := move_executed_events.filter(func(e): return e[0] == scrappy_attacker and e[1] == ghost_target)
	_chk("S9.01 Scrappy's Normal-type Tackle connects against a Ghost-type target " +
			"that would otherwise be immune",
			not hit.is_empty() and hit[0][3] > 0)
	bm.queue_free()

	# Control: the SAME scenario without Scrappy — the hit never connects (0 damage,
	# flat type immunity).
	var plain_attacker := _make_mon("ScrappyControlAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	plain_attacker.add_move(tackle)
	var ghost_target2 := _make_mon("ScrappyControlGhost", [TypeChart.TYPE_GHOST], 100, 40, 40, 40, 40, 40)
	ghost_target2.add_move(tackle)

	var move_executed_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2.move_executed.connect(func(a, d, m, dmg): move_executed_events2.push_back([a, d, m, dmg]))
	bm2.start_battle_with_parties(BattleParty.single(plain_attacker), BattleParty.single(ghost_target2))

	var hit2 := move_executed_events2.filter(func(e): return e[0] == plain_attacker and e[1] == ghost_target2)
	_chk("S9.02 control: WITHOUT Scrappy, the same Tackle-vs-Ghost scenario deals 0 damage",
			not hit2.is_empty() and hit2[0][3] == 0)
	bm2.queue_free()


# ── Section 10: Scrappy — Mold Breaker N/A (attacker-self-check) + NG suppression ──

func _test_section_10_scrappy_mold_breaker_ng() -> void:
	# Scrappy has no breakable flag in source (confirmed in Section 1) since it is
	# always read as the ATTACKER's own ability, never a defender's ability being
	# broken through — Mold Breaker structurally never applies here (same reasoning
	# as ignores_defender_evasion_stage's existing precedent). No bypass test needed;
	# documented here rather than silently skipped.
	var scrappy := _load_ability(113)
	var scrappy_holder := _make_mon("ScrappyNG", [TypeChart.TYPE_NORMAL])
	scrappy_holder.ability = scrappy

	_chk("S10.01 Neutralizing Gas suppresses Scrappy's Ghost-bypass " +
			"(field-wide suppression applies to the attacker's OWN ability too)",
			AbilityManager.bypasses_ghost_immunity(scrappy_holder, true) == false)
	_chk("S10.02 sanity: without NG active, the same holder's bypass is active",
			AbilityManager.bypasses_ghost_immunity(scrappy_holder, false) == true)


# ── Section 11: Mind's Eye — Ghost-immunity-bypass half ─────────────────────

func _test_section_11_minds_eye_ghost_bypass_half() -> void:
	var minds_eye := _load_ability(300)
	var me_holder := _make_mon("MindsEyeGhostBypass", [TypeChart.TYPE_NORMAL])
	me_holder.ability = minds_eye

	_chk("S11.01 bypasses_ghost_immunity: Mind's Eye holder → true (same OR condition " +
			"as Scrappy, source-confirmed literal shared branch)",
			AbilityManager.bypasses_ghost_immunity(me_holder) == true)
	_chk("S11.02 Mind's Eye bypass: Normal vs Ghost becomes 1.0x",
			TypeChart.get_effectiveness(TypeChart.TYPE_NORMAL, [TypeChart.TYPE_GHOST], false, true) == 1.0)


# ── Section 12: Mind's Eye — evasion-ignore half ────────────────────────────

func _test_section_12_minds_eye_evasion_ignore_half() -> void:
	var minds_eye := _load_ability(300)
	var me_holder := _make_mon("MindsEyeEvasion", [TypeChart.TYPE_NORMAL])
	me_holder.ability = minds_eye
	var plain := _make_mon("PlainEvasionAtk", [TypeChart.TYPE_NORMAL])

	_chk("S12.01 ignores_defender_evasion_stage: Mind's Eye attacker → true (this " +
			"function's own pre-existing doc comment already anticipated this addition)",
			AbilityManager.ignores_defender_evasion_stage(me_holder) == true)
	_chk("S12.02 ignores_defender_evasion_stage: plain attacker → false",
			AbilityManager.ignores_defender_evasion_stage(plain) == false)

	# Statistical confirmation via the real accuracy formula (same pattern already
	# established in m17b_test.gd for Unaware/Keen Eye) — a high-evasion target is
	# hit more often by the Mind's Eye holder than by a plain attacker.
	var acc_move := _synth_move(40, 0, TypeChart.TYPE_NORMAL)
	acc_move.accuracy = 100
	var high_eva_def := _make_mon("MindsEyeHighEva", [TypeChart.TYPE_NORMAL])
	high_eva_def.stat_stages[BattlePokemon.STAGE_EVASION] = 6

	var hits_vs_minds_eye := 0
	for i in range(20):
		if StatusManager.check_accuracy(me_holder, high_eva_def, acc_move, null):
			hits_vs_minds_eye += 1
	var hits_vs_plain := 0
	for i in range(20):
		if StatusManager.check_accuracy(plain, high_eva_def, acc_move, null):
			hits_vs_plain += 1
	_chk("S12.03 Mind's Eye hits a maximally-evasive target far more often than a " +
			"plain attacker (statistical, 20 trials each)",
			hits_vs_minds_eye > hits_vs_plain)


# ── Section 13: Mind's Eye — independence discriminator ─────────────────────

func _test_section_13_minds_eye_independence_discriminator() -> void:
	var minds_eye := _load_ability(300)
	var me_holder := _make_mon("MindsEyeIndep", [TypeChart.TYPE_NORMAL])
	me_holder.ability = minds_eye

	# (a) Ghost-bypass half fires even with NO evasion boost on the target at all —
	# proving it doesn't depend on the evasion-ignore half.
	_chk("S13.01 Ghost-bypass fires independent of any evasion boost (target evasion=0)",
			TypeChart.get_effectiveness(TypeChart.TYPE_NORMAL, [TypeChart.TYPE_GHOST], false,
					AbilityManager.bypasses_ghost_immunity(me_holder)) == 1.0)

	# (b) evasion-ignore half fires against a NON-Ghost target — proving it doesn't
	# depend on the Ghost-bypass half being relevant at all.
	_chk("S13.02 evasion-ignore is unconditional on the target's typing (still true " +
			"for a Normal-type, non-Ghost target)",
			AbilityManager.ignores_defender_evasion_stage(me_holder) == true)
	_chk("S13.03 and the Ghost-bypass check for a Normal-type (non-Ghost) target is " +
			"simply moot (1.0x either way) rather than interfering",
			TypeChart.get_effectiveness(TypeChart.TYPE_NORMAL, [TypeChart.TYPE_NORMAL], false, true) == 1.0)


# ── Section 14: Overcoat — powder-move immunity ─────────────────────────────

func _test_section_14_overcoat_powder_immunity() -> void:
	var sleep_powder := _load_move(79)  # Grass, status, powder_move=true
	var overcoat := _load_ability(142)
	var mold_breaker := _load_ability(104)

	var overcoat_holder := _make_mon("OvercoatPowder", [TypeChart.TYPE_NORMAL])
	overcoat_holder.ability = overcoat
	var plain := _make_mon("PlainPowder", [TypeChart.TYPE_NORMAL])

	_chk("S14.01 Overcoat blocks a powder move (Sleep Powder)",
			AbilityManager.blocks_move_flag(overcoat_holder, sleep_powder) == true)
	_chk("S14.02 plain defender: powder move NOT blocked",
			AbilityManager.blocks_move_flag(plain, sleep_powder) == false)

	var mb_attacker := _make_mon("MBAttackerOvercoat", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker
	_chk("S14.03 Mold Breaker bypasses Overcoat's powder immunity (breakable=true)",
			AbilityManager.blocks_move_flag(overcoat_holder, sleep_powder, false, mb_attacker) == false)
	_chk("S14.04 Neutralizing Gas suppresses Overcoat's powder immunity",
			AbilityManager.blocks_move_flag(overcoat_holder, sleep_powder, true) == false)

	# Full-battle confirmation.
	var attacker := _make_mon("OvercoatBattleAttacker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	attacker.add_move(sleep_powder)
	var battle_holder := _make_mon("OvercoatBattleHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	battle_holder.ability = overcoat
	battle_holder.add_move(sleep_powder)

	var move_effect_failed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.move_effect_failed.connect(func(t, r): move_effect_failed_events.push_back([t, r]))
	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(battle_holder))

	_chk("S14.05 full battle: Sleep Powder fails against the Overcoat holder " +
			"(move_flag_blocked, the same shared tag Soundproof/Bulletproof use)",
			move_effect_failed_events.any(func(e): return e[0] == battle_holder and e[1] == "move_flag_blocked"))

	bm.queue_free()


# ── Section 15: Overcoat — sandstorm/hail weather-chip immunity ─────────────

func _test_section_15_overcoat_weather_chip_immunity() -> void:
	var overcoat := _load_ability(142)
	var tackle := _load_move(33)

	_chk("S15.01 direct: Overcoat blocks weather chip damage",
			AbilityManager.blocks_weather_chip_damage(_make_with_ability("OvercoatChipDirect", overcoat)) == true)
	_chk("S15.02 direct: plain Pokemon is not immune",
			AbilityManager.blocks_weather_chip_damage(_make_mon("PlainChipDirect", [TypeChart.TYPE_NORMAL])) == false)
	_chk("S15.03 Neutralizing Gas suppresses Overcoat's weather-chip immunity",
			AbilityManager.blocks_weather_chip_damage(_make_with_ability("OvercoatChipNG", overcoat), true) == false)

	# Sandstorm: control (no Overcoat) takes chip; Overcoat holder (same stats) does not.
	var control := _make_mon("SandChipControl", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	control.add_move(tackle)
	var control_atk := _make_mon("SandChipControlAtk", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 200)
	control_atk.add_move(tackle)
	var chip_events_control := []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.weather = DamageCalculator.WEATHER_SANDSTORM
	bm1.weather_duration = 10
	bm1.weather_damage.connect(func(m, amt): chip_events_control.push_back([m, amt]))
	bm1.start_battle_with_parties(BattleParty.single(control_atk), BattleParty.single(control))
	_chk("S15.04 sanity: without Overcoat, sandstorm chip damage occurs",
			chip_events_control.any(func(e): return e[0] == control))
	bm1.queue_free()

	var overcoat_holder := _make_mon("SandChipOvercoat", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	overcoat_holder.ability = overcoat
	overcoat_holder.add_move(tackle)
	var oc_atk := _make_mon("SandChipOvercoatAtk", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 200)
	oc_atk.add_move(tackle)
	var chip_events_oc := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.weather = DamageCalculator.WEATHER_SANDSTORM
	bm2.weather_duration = 10
	bm2.weather_damage.connect(func(m, amt): chip_events_oc.push_back([m, amt]))
	bm2.start_battle_with_parties(BattleParty.single(oc_atk), BattleParty.single(overcoat_holder))
	_chk("S15.05 the Overcoat holder never takes sandstorm chip damage",
			not chip_events_oc.any(func(e): return e[0] == overcoat_holder))
	bm2.queue_free()

	# Hail: same pattern, one representative scenario.
	var overcoat_holder_hail := _make_mon("HailChipOvercoat", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	overcoat_holder_hail.ability = overcoat
	overcoat_holder_hail.add_move(tackle)
	var hail_atk := _make_mon("HailChipAtk", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 200)
	hail_atk.add_move(tackle)
	var chip_events_hail := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.weather = DamageCalculator.WEATHER_HAIL
	bm3.weather_duration = 10
	bm3.weather_damage.connect(func(m, amt): chip_events_hail.push_back([m, amt]))
	bm3.start_battle_with_parties(BattleParty.single(hail_atk), BattleParty.single(overcoat_holder_hail))
	_chk("S15.06 the Overcoat holder never takes hail chip damage either",
			not chip_events_hail.any(func(e): return e[0] == overcoat_holder_hail))
	bm3.queue_free()


# ── Section 16: Overcoat × Air Lock composition ──────────────────────────────

func _test_section_16_overcoat_air_lock_composition() -> void:
	var overcoat := _load_ability(142)
	var air_lock := _load_ability(76)
	var tackle := _load_move(33)

	var al_side := _make_mon("CompAirLock", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 200)
	al_side.ability = air_lock
	al_side.add_move(tackle)
	var oc_side := _make_mon("CompOvercoat", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	oc_side.ability = overcoat
	oc_side.add_move(tackle)

	var chip_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.weather = DamageCalculator.WEATHER_SANDSTORM
	bm.weather_duration = 10
	bm.weather_damage.connect(func(m, amt): chip_events.push_back([m, amt]))
	bm.start_battle_with_parties(BattleParty.single(al_side), BattleParty.single(oc_side))

	_chk("S16.01 Overcoat's per-mon exemption and Air Lock's field-wide negation " +
			"compose cleanly — no chip damage anywhere, no double-negation, no crash " +
			"(Air Lock's field-wide check means Overcoat's own per-mon branch is never " +
			"even reached in this scenario)",
			chip_events.is_empty())

	bm.queue_free()


# ── Section 17: Normalize — a non-Normal move becomes Normal ────────────────

func _test_section_17_normalize_non_normal_move() -> void:
	var vine_whip := _load_move(22)  # Grass, physical, power 45
	var normalize := _load_ability(96)

	var attacker := _make_mon("NormalizeAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	attacker.ability = normalize
	var plain_attacker := _make_mon("NormalizePlainAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	var target := _make_mon("NormalizeTarget", [TypeChart.TYPE_FIRE], 200, 40, 60, 40, 60, 40)

	_chk("S17.01 effective_move_type: Normalize mutates a non-Normal move to TYPE_NORMAL",
			AbilityManager.effective_move_type(attacker, vine_whip) == TypeChart.TYPE_NORMAL)
	_chk("S17.02 effective_move_type: no ability → unaffected (-1)",
			AbilityManager.effective_move_type(plain_attacker, vine_whip) == -1)

	var result_normalized: Dictionary = DamageCalculator.calculate(attacker, target, vine_whip, 100, false)
	var result_plain: Dictionary = DamageCalculator.calculate(plain_attacker, target, vine_whip, 100, false)
	_chk("S17.03 sanity: unmutated Vine Whip (Grass) vs Fire-type target is 0.5x (NVE)",
			result_plain["effectiveness"] == 0.5)
	_chk("S17.04 Normalize'd Vine Whip's effectiveness is computed against the NEW " +
			"type (Normal vs Fire = 1.0x), NOT the original Grass typing",
			result_normalized["effectiveness"] == 1.0)
	_chk("S17.05 the Normalize'd hit deals strictly more damage (both the 0.5x->1.0x " +
			"effectiveness change AND the +20% power boost)",
			result_normalized["damage"] > result_plain["damage"])


# ── Section 18: Normalize — an already-Normal move is a type no-op, but still boosted ──

func _test_section_18_normalize_already_normal_move() -> void:
	var tackle := _load_move(33)  # Normal, physical, power 40
	var normalize := _load_ability(96)

	var attacker := _make_mon("NormalizeNoOpAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	attacker.ability = normalize
	var plain_attacker := _make_mon("NormalizeNoOpPlain", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	var target := _make_mon("NormalizeNoOpTarget", [TypeChart.TYPE_NORMAL], 200, 40, 60, 40, 60, 40)

	_chk("S18.01 effective_move_type: Normalize on an already-Normal move still " +
			"reports TYPE_NORMAL (mutated, deliberately, not -1 — see doc comment: " +
			"Normalize sets its equivalent of ateBoost unconditionally)",
			AbilityManager.effective_move_type(attacker, tackle) == TypeChart.TYPE_NORMAL)

	var result_normalized: Dictionary = DamageCalculator.calculate(attacker, target, tackle, 100, false)
	var result_plain: Dictionary = DamageCalculator.calculate(plain_attacker, target, tackle, 100, false)
	_chk("S18.02 the type itself is a genuine no-op — both scenarios see 1.0x effectiveness",
			result_normalized["effectiveness"] == 1.0 and result_plain["effectiveness"] == 1.0)
	_chk("S18.03 but Normalize STILL boosts an already-Normal move's damage " +
			"(the deliberate not-a-bug nuance this tier flagged in advance)",
			result_normalized["damage"] > result_plain["damage"])

	_chk("S18.04 move_power_modifier_uq412: exactly x1.2 (4915) when move_type_changed=true",
			AbilityManager.move_power_modifier_uq412(
					attacker, tackle, DamageCalculator.WEATHER_NONE, null, false, false, true) == 4915)
	_chk("S18.05 move_power_modifier_uq412: x1.0 (4096) when move_type_changed=false " +
			"(the gate this function actually reads, not a re-derived move.type check)",
			AbilityManager.move_power_modifier_uq412(
					attacker, tackle, DamageCalculator.WEATHER_NONE, null, false, false, false) == 4096)


# ── Section 19: Refrigerate / Pixilate / Galvanize / Aerilate / Dragonize — each
# converts Normal, +20% ────────────────────────────────────────────────────────

func _test_section_19_ate_family() -> void:
	var tackle := _load_move(33)     # Normal, physical
	var vine_whip := _load_move(22)  # Grass, physical — unaffected control
	var refrigerate := _load_ability(174)
	var pixilate := _load_ability(182)
	var galvanize := _load_ability(206)
	var aerilate := _load_ability(184)
	var dragonize := _load_ability(312)

	var refrig_atk := _make_mon("RefrigerateAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	refrig_atk.ability = refrigerate
	_chk("S19.01 Refrigerate: Normal move -> Ice",
			AbilityManager.effective_move_type(refrig_atk, tackle) == TypeChart.TYPE_ICE)
	_chk("S19.02 Refrigerate: non-Normal move (Vine Whip) unaffected",
			AbilityManager.effective_move_type(refrig_atk, vine_whip) == -1)

	var pixi_atk := _make_mon("PixilateAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	pixi_atk.ability = pixilate
	_chk("S19.03 Pixilate: Normal move -> Fairy",
			AbilityManager.effective_move_type(pixi_atk, tackle) == TypeChart.TYPE_FAIRY)
	_chk("S19.04 Pixilate: non-Normal move (Vine Whip) unaffected",
			AbilityManager.effective_move_type(pixi_atk, vine_whip) == -1)

	var galva_atk := _make_mon("GalvanizeAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	galva_atk.ability = galvanize
	_chk("S19.05 Galvanize: Normal move -> Electric",
			AbilityManager.effective_move_type(galva_atk, tackle) == TypeChart.TYPE_ELECTRIC)
	_chk("S19.06 Galvanize: non-Normal move (Vine Whip) unaffected",
			AbilityManager.effective_move_type(galva_atk, vine_whip) == -1)

	# M17n-6 follow-up: Aerilate (Normal->Flying) and Dragonize (Normal->Dragon) —
	# same mechanism/switch as the original three, confirmed from source.
	var aerilate_atk := _make_mon("AerilateAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	aerilate_atk.ability = aerilate
	_chk("S19.11 Aerilate: Normal move -> Flying",
			AbilityManager.effective_move_type(aerilate_atk, tackle) == TypeChart.TYPE_FLYING)
	_chk("S19.12 Aerilate: non-Normal move (Vine Whip) unaffected",
			AbilityManager.effective_move_type(aerilate_atk, vine_whip) == -1)

	var dragonize_atk := _make_mon("DragonizeAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	dragonize_atk.ability = dragonize
	_chk("S19.13 Dragonize: Normal move -> Dragon",
			AbilityManager.effective_move_type(dragonize_atk, tackle) == TypeChart.TYPE_DRAGON)
	_chk("S19.14 Dragonize: non-Normal move (Vine Whip) unaffected",
			AbilityManager.effective_move_type(dragonize_atk, vine_whip) == -1)

	# One representative full DamageCalculator comparison (Pixilate) confirming the
	# +20% power boost is real, forcing both roll and crit per the pairwise-comparison
	# convention. `pixi_atk2` is deliberately dual Normal/Fairy-typed so BOTH the
	# original Tackle (matches Normal) and the Pixilate-mutated Tackle (matches Fairy)
	# get the SAME 1.5x STAB — otherwise mutating away from the attacker's own type
	# would cost STAB and confound the comparison (caught by this test's own first
	# draft: a single-Normal-type attacker's Pixilate'd Tackle actually dealt LESS
	# damage than unboosted, because losing STAB outweighs the +20% power gain —
	# a real, correctly-modeled mechanic, not a bug, but the wrong scenario to isolate
	# the power boost specifically).
	var pixi_atk2 := _make_mon("PixilateAtkDualType", [TypeChart.TYPE_NORMAL, TypeChart.TYPE_FAIRY],
			100, 80, 60, 60, 60, 60)
	pixi_atk2.ability = pixilate
	var plain_atk := _make_mon("AtePlainAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	var target := _make_mon("AteTarget", [TypeChart.TYPE_WATER], 200, 40, 60, 40, 60, 40)
	var result_pixi: Dictionary = DamageCalculator.calculate(pixi_atk2, target, tackle, 100, false)
	var result_plain: Dictionary = DamageCalculator.calculate(plain_atk, target, tackle, 100, false)
	_chk("S19.07 sanity: unmutated Tackle (Normal) vs Water-type target is 1.0x (neutral)",
			result_plain["effectiveness"] == 1.0)
	_chk("S19.08 Pixilate'd Tackle (now Fairy) vs Water-type target is STILL 1.0x " +
			"(Fairy has no special relation to Water) — isolates the power boost as " +
			"the sole source of the damage difference",
			result_pixi["effectiveness"] == 1.0)
	_chk("S19.09 Pixilate deals strictly more damage than the same move unboosted, " +
			"with STAB held equal via a dual Normal/Fairy-typed attacker (the +20% " +
			"power boost, isolated from any effectiveness OR STAB change)",
			result_pixi["damage"] > result_plain["damage"])
	_chk("S19.10 move_power_modifier_uq412 confirms exactly x1.2 (4915) for all five",
			AbilityManager.move_power_modifier_uq412(
					refrig_atk, tackle, DamageCalculator.WEATHER_NONE, null, false, false, true) == 4915
			and AbilityManager.move_power_modifier_uq412(
					pixi_atk, tackle, DamageCalculator.WEATHER_NONE, null, false, false, true) == 4915
			and AbilityManager.move_power_modifier_uq412(
					galva_atk, tackle, DamageCalculator.WEATHER_NONE, null, false, false, true) == 4915
			and AbilityManager.move_power_modifier_uq412(
					aerilate_atk, tackle, DamageCalculator.WEATHER_NONE, null, false, false, true) == 4915
			and AbilityManager.move_power_modifier_uq412(
					dragonize_atk, tackle, DamageCalculator.WEATHER_NONE, null, false, false, true) == 4915)


# ── Section 20: Liquid Voice — sound-flagged move becomes Water ─────────────

func _test_section_20_liquid_voice() -> void:
	var liquid_voice := _load_ability(204)
	# No damaging sound move exists in this project's current roster (confirmed via
	# grep, matching the Strong Jaw/Sharpness/Mega Launcher precedent in [M17n-5]) —
	# tested via a synthetic MoveData, same established pattern.
	var sound_move := _synth_move(60, 0, TypeChart.TYPE_NORMAL)
	sound_move.sound_move = true
	var non_sound_move := _synth_move(60, 0, TypeChart.TYPE_NORMAL)
	sound_move.accuracy = 100
	non_sound_move.accuracy = 100

	var lv_atk := _make_mon("LiquidVoiceAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	lv_atk.ability = liquid_voice
	_chk("S20.01 Liquid Voice: a sound-flagged move becomes Water-type",
			AbilityManager.effective_move_type(lv_atk, sound_move) == TypeChart.TYPE_WATER)
	_chk("S20.02 Liquid Voice: a non-sound move of the same original type is unaffected",
			AbilityManager.effective_move_type(lv_atk, non_sound_move) == -1)
	_chk("S20.03 Liquid Voice grants NO power boost of its own (confirmed absent from " +
			"CalcMoveBasePowerAfterModifiers's ability switch in source)",
			AbilityManager.move_power_modifier_uq412(
					lv_atk, sound_move, DamageCalculator.WEATHER_NONE, null, false, false, true) == 4096)

	# Full DamageCalculator confirmation: type changes, but Liquid Voice's own boost
	# is absent (any difference from a plain attacker would be effectiveness-only,
	# never power). `lv_atk2` is deliberately dual Normal/Water-typed so STAB applies
	# identically before AND after the mutation (Normal matches one type, the
	# mutated Water matches the other) — otherwise losing STAB on the mutated move
	# would make it deal LESS damage even though Liquid Voice itself grants no
	# boost, confounding the "no power effect" claim (same pitfall caught and fixed
	# for Pixilate's comparison above).
	var lv_atk2 := _make_mon("LiquidVoiceAtkDualType", [TypeChart.TYPE_NORMAL, TypeChart.TYPE_WATER],
			100, 80, 60, 60, 60, 60)
	lv_atk2.ability = liquid_voice
	var plain_atk := _make_mon("LiquidVoicePlainAtk", [TypeChart.TYPE_NORMAL, TypeChart.TYPE_WATER],
			100, 80, 60, 60, 60, 60)
	var neutral_target := _make_mon("LiquidVoiceTarget", [TypeChart.TYPE_NORMAL], 200, 40, 60, 40, 60, 40)
	var result_lv: Dictionary = DamageCalculator.calculate(lv_atk2, neutral_target, sound_move, 100, false)
	var result_plain: Dictionary = DamageCalculator.calculate(plain_atk, neutral_target, sound_move, 100, false)
	_chk("S20.04 against a Normal-type target (Water and Normal are both neutral vs " +
			"Normal), with STAB held equal via a dual Normal/Water-typed attacker, " +
			"Liquid Voice's mutation causes no damage difference at all (no power " +
			"boost, effectiveness unchanged 1.0x either way)",
			result_lv["damage"] == result_plain["damage"])


# ── Section 21: type-mutation family — Neutralizing Gas suppression (representative) ──

func _test_section_21_type_mutation_ng_suppression() -> void:
	var tackle := _load_move(33)
	var normalize := _load_ability(96)
	var normalize_atk := _make_mon("NormalizeNG", [TypeChart.TYPE_GRASS], 100, 80, 60, 60, 60, 60)
	normalize_atk.ability = normalize
	var vine_whip := _load_move(22)

	_chk("S21.01 sanity: Normalize mutates Vine Whip without Neutralizing Gas",
			AbilityManager.effective_move_type(normalize_atk, vine_whip) == TypeChart.TYPE_NORMAL)
	_chk("S21.02 Neutralizing Gas suppresses Normalize's mutation entirely",
			AbilityManager.effective_move_type(normalize_atk, vine_whip, true) == -1)
	# No Mold-Breaker-bypass test for this family — none of the five carry a
	# breakable flag in source (all attacker-self-checks, confirmed in Section 1),
	# so there is nothing for Mold Breaker to break through.


# ── Section 22: Negative control — ordinary Pokemon across every mechanism ──

func _test_section_22_negative_control() -> void:
	var tackle := _load_move(33)
	var vine_whip := _load_move(22)

	var plain_atk := _make_mon("NegControlAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	var plain_def := _make_mon("NegControlDef", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)

	_chk("S22.01 ordinary Pokemon: blocks_non_super_effective_hit is always false",
			not AbilityManager.blocks_non_super_effective_hit(plain_def, 1.0, tackle))
	_chk("S22.02 ordinary Pokemon: bypasses_ghost_immunity is false",
			not AbilityManager.bypasses_ghost_immunity(plain_atk))
	_chk("S22.03 ordinary Pokemon: ignores_defender_evasion_stage is false",
			not AbilityManager.ignores_defender_evasion_stage(plain_atk))
	_chk("S22.04 ordinary Pokemon: blocks_move_flag is false for a powder move",
			not AbilityManager.blocks_move_flag(plain_def, _load_move(79)))
	_chk("S22.05 ordinary Pokemon: blocks_weather_chip_damage is false",
			not AbilityManager.blocks_weather_chip_damage(plain_def))
	_chk("S22.06 ordinary Pokemon: effective_move_type reports -1 (unaffected)",
			AbilityManager.effective_move_type(plain_atk, vine_whip) == -1)

	var result: Dictionary = DamageCalculator.calculate(plain_atk, plain_def, tackle, 100, false)
	_chk("S22.07 ordinary Pokemon takes real, unblocked, unboosted damage",
			result["damage"] > 0 and not result.get("wonder_guard_blocked", false))
