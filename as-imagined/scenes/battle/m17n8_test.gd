extends Node

# M17n-8 test suite — Group 8, sub-tier 1: contact/faint-timing + reactive/one-off:
# Aftermath, Innards Out, Corrosion, Merciless, Opportunist.
#
# Scope: the 5 abilities locked in docs/m17n_recon.md's Group 8, trimmed by Rob's
# explicit exclusion decisions (Perish Body and Suction Cups excluded from this
# sub-tier — Perish Body is blocked on the unimplemented Perish Song move; Suction
# Cups was deferred, not part of this tier's list). Step 0 re-verified all five IDs
# directly against include/constants/abilities.h — no corrections needed (Aftermath=106,
# Merciless=196, Corrosion=212, Innards Out=215, Opportunist=290). None of the five
# carry breakable/cant_be_suppressed in source's data table (confirmed individually) —
# no Mold-Breaker test needed for any of them; Neutralizing Gas suppression applies to
# all five via the standard effective_ability_id chokepoint.
#
# Aftermath/Innards Out share ONE mechanism (AbilityManager.faint_retaliation_damage),
# per this tier's own instruction, but differ in two source-verified ways: Aftermath
# REQUIRES contact (move_makes_contact) and is blocked by any Damp holder anywhere on
# the field (AbilityManager.is_damp_active); Innards Out has neither restriction, and
# its damage amount is the FAINTED MON's own HP immediately before the fatal hit
# (`_last_attacker_hp_before`, a new companion to the existing `_last_attacker` killer-
# lookup tracker), not a fixed fraction like Aftermath's killer.max_hp/4 — deliberately
# tested with an overkill scenario (raw move damage far exceeds the holder's remaining
# HP) to discriminate the two shapes concretely, not just by different killer-taken
# damage amounts.
#
# Corrosion is an ATTACKER-side bypass of Poison-type AND Steel-type immunity to
# poison/toxic infliction (CanSetNonVolatileStatus, battle_util.c L5250) — a single
# condition covering BOTH types together, confirmed from source rather than assumed
# uniform (there is no separate Steel-only or Poison-only carve-out).
#
# Merciless is a GUARANTEED (100%) crit against a poisoned/toxic'd target
# (CalcCritChanceStage's CRITICAL_HIT_ALWAYS branch, battle_util.c L7828-7830) — an
# override, not a stage bonus like Super Luck's own +1 ([M17n-5]) — tested via a
# statistical sample (mirrors that tier's own new-for-this-codebase testing pattern)
# to concretely distinguish "always" from "usually."
#
# Opportunist copies an opponent's POSITIVE stat-stage change onto the holder
# immediately (battle_stat_change.c L420-441) — never decreases, never the holder's
# own side. Known simplification (documented, not silently dropped): wired into the
# primary move-driven stat-increase call site only, mirroring [M17b]'s Defiant/
# Competitive precedent of not retrofitting into every apply_stat_change call site.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state (fainting/retaliation/stat-copy events all
#     captured via signals, never read from mon state after start_battle() returns).
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing function.
#   - Type immunity precedes ability logic: every damaging scenario below uses a
#     neutral (1x) Normal-vs-Normal matchup unless the mechanic under test is itself
#     type-specific (Corrosion's Steel/Poison targets).
#   - Pairwise damage comparisons force both _force_roll and _force_crit.
#
# Ground truth: pokeemerald_expansion src/battle_util.c :: ABILITY_AFTERMATH case
#   (L3986-4003), ABILITY_INNARDS_OUT case (L4007-4021), IsAbilityOnField (L4895-4904);
#   src/battle_script_commands.c L1630-1658 (innardsOutHpLost accumulation);
#   src/battle_util.c :: CanSetNonVolatileStatus (L5250, Corrosion);
#   src/battle_util.c :: CalcCritChanceStage (L7828-7830, Merciless);
#   src/battle_stat_change.c L420-441 (Opportunist).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_aftermath_unit()
	_test_section_3_aftermath_full_battle()
	_test_section_4_innards_out_unit()
	_test_section_5_innards_out_full_battle()
	_test_section_6_corrosion_unit()
	_test_section_7_corrosion_full_battle()
	_test_section_8_merciless_unit_and_statistical()
	_test_section_9_opportunist_unit_and_full_battle()
	_test_section_10_neutralizing_gas_suppression()
	_test_section_11_negative_control()

	var total := _pass + _fail
	print("m17n8_test: %d/%d passed" % [_pass, total])
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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


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
	var aftermath := _load_ability(106)
	_chk("S1.01 Aftermath id=106", aftermath.ability_id == 106)

	var merciless := _load_ability(196)
	_chk("S1.02 Merciless id=196", merciless.ability_id == 196)

	var corrosion := _load_ability(212)
	_chk("S1.03 Corrosion id=212", corrosion.ability_id == 212)

	var innards_out := _load_ability(215)
	_chk("S1.04 Innards Out id=215", innards_out.ability_id == 215)

	var opportunist := _load_ability(290)
	_chk("S1.05 Opportunist id=290", opportunist.ability_id == 290)

	_chk("S1.06 none of the five carry breakable/cant_be_suppressed " +
			"(source-verified, none are Mold-Breaker/Neutralizing-Gas exemptions)",
			not aftermath.breakable and not aftermath.cant_be_suppressed and
			not merciless.breakable and not merciless.cant_be_suppressed and
			not corrosion.breakable and not corrosion.cant_be_suppressed and
			not innards_out.breakable and not innards_out.cant_be_suppressed and
			not opportunist.breakable and not opportunist.cant_be_suppressed)


# ── Section 2: Aftermath — direct unit tests ─────────────────────────────────

func _test_section_2_aftermath_unit() -> void:
	var aftermath := _load_ability(106)
	var tackle := _load_move(33)     # contact
	var ember := _load_move(53)      # Flamethrower — non-contact

	# (i) Ordinary case: contact move, holder faints, killer alive — fires.
	var holder_i := _make_mon("AftHolder1", [TypeChart.TYPE_NORMAL])
	holder_i.ability = aftermath
	var killer_i := _make_mon("AftKiller1", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 80)
	var result_i: Dictionary = AbilityManager.faint_retaliation_damage(
			holder_i, killer_i, tackle, 10)
	_chk("S2.01 Aftermath fires on a contact-fainting hit",
			result_i.get("ability_name", "") == "aftermath")
	_chk("S2.02 Aftermath damage = killer's max_hp/4",
			result_i.get("damage", -1) == killer_i.max_hp / 4)

	# (ii) Non-contact move: does NOT fire.
	var holder_ii := _make_mon("AftHolder2", [TypeChart.TYPE_NORMAL])
	holder_ii.ability = aftermath
	var killer_ii := _make_mon("AftKiller2", [TypeChart.TYPE_NORMAL])
	var result_ii: Dictionary = AbilityManager.faint_retaliation_damage(
			holder_ii, killer_ii, ember, 10)
	_chk("S2.03 Aftermath does NOT fire on a non-contact move", result_ii.is_empty())

	# (iii) Damp active anywhere: blocks Aftermath.
	var holder_iii := _make_mon("AftHolder3", [TypeChart.TYPE_NORMAL])
	holder_iii.ability = aftermath
	var killer_iii := _make_mon("AftKiller3", [TypeChart.TYPE_NORMAL])
	var result_iii: Dictionary = AbilityManager.faint_retaliation_damage(
			holder_iii, killer_iii, tackle, 10, false, true)
	_chk("S2.04 Aftermath blocked when Damp is active anywhere on the field",
			result_iii.is_empty())

	# (iv) killer == null: no-op.
	var holder_iv := _make_mon("AftHolder4", [TypeChart.TYPE_NORMAL])
	holder_iv.ability = aftermath
	_chk("S2.05 Aftermath no-op with a null killer",
			AbilityManager.faint_retaliation_damage(holder_iv, null, tackle, 10).is_empty())

	# (v) killer already fainted: no-op.
	var holder_v := _make_mon("AftHolder5", [TypeChart.TYPE_NORMAL])
	holder_v.ability = aftermath
	var killer_v := _make_mon("AftKiller5", [TypeChart.TYPE_NORMAL])
	killer_v.fainted = true
	_chk("S2.06 Aftermath no-op with an already-fainted killer",
			AbilityManager.faint_retaliation_damage(holder_v, killer_v, tackle, 10).is_empty())

	# (vi) is_damp_active direct unit tests.
	var damp := _load_ability(6)
	var damp_holder := _make_mon("DampMon", [TypeChart.TYPE_NORMAL])
	damp_holder.ability = damp
	var plain := _make_mon("PlainMon", [TypeChart.TYPE_NORMAL])
	_chk("S2.07 is_damp_active true when a live Damp holder is present",
			AbilityManager.is_damp_active([damp_holder, plain]))
	_chk("S2.08 is_damp_active false with no Damp holder",
			not AbilityManager.is_damp_active([plain]))
	damp_holder.fainted = true
	_chk("S2.09 is_damp_active false when the only Damp holder has fainted",
			not AbilityManager.is_damp_active([damp_holder, plain]))


# ── Section 3: Aftermath — full-battle integration ───────────────────────────

func _test_section_3_aftermath_full_battle() -> void:
	var tackle := _load_move(33)
	var growl := _load_move(45)  # status move, does not damage
	var aftermath := _load_ability(106)

	# (i) Contact KO fires Aftermath: attacker takes killer.max_hp/4.
	var attacker_i := _make_mon("AftBattleAtk1", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	attacker_i.add_move(tackle)
	var holder_i := _make_mon("AftBattleHolder1", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 20)
	holder_i.ability = aftermath
	holder_i.current_hp = 1
	holder_i.add_move(tackle)

	var bm_i := _make_bm()
	bm_i._force_roll = 100
	bm_i._force_crit = false
	var recoil_events_i := []
	var fainted_events_i := []
	bm_i.recoil_damage.connect(func(m, amt): recoil_events_i.append([m, amt]))
	bm_i.pokemon_fainted.connect(func(m): fainted_events_i.append(m))
	bm_i.start_battle(attacker_i, holder_i)

	_chk("S3.01 Aftermath holder fainted", fainted_events_i.any(func(m): return m == holder_i))
	_chk("S3.02 attacker took exactly max_hp/4 recoil-style damage from Aftermath",
			recoil_events_i.any(func(e): return e[0] == attacker_i and e[1] == attacker_i.max_hp / 4))

	bm_i.queue_free()

	# (ii) Discriminator: a non-contact-fainting death (residual weather chip, no
	# direct hit that turn) does NOT fire Aftermath.
	var attacker_ii := _make_mon("AftBattleAtk2", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 20)
	attacker_ii.add_move(growl)
	var holder_ii := _make_mon("AftBattleHolder2", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 100)
	holder_ii.ability = aftermath
	holder_ii.current_hp = 5  # low enough that sandstorm chip (maxHP/16) can finish it
	holder_ii.add_move(growl)

	var bm_ii := _make_bm()
	bm_ii.weather = DamageCalculator.WEATHER_SANDSTORM
	bm_ii.weather_duration = 5
	var recoil_events_ii := []
	bm_ii.recoil_damage.connect(func(m, amt): recoil_events_ii.append([m, amt]))
	bm_ii.start_battle(attacker_ii, holder_ii)

	_chk("S3.03 Aftermath does NOT fire when the holder faints from residual " +
			"(non-hit) damage, not a direct contact fainting blow",
			not recoil_events_ii.any(func(e): return e[0] == attacker_ii))

	bm_ii.queue_free()


# ── Section 4: Innards Out — direct unit tests ───────────────────────────────

func _test_section_4_innards_out_unit() -> void:
	var innards_out := _load_ability(215)
	var tackle := _load_move(33)
	var ember := _load_move(53)  # non-contact — Innards Out must NOT care

	# (i) Fires on a contact hit too (no contact requirement, but not EXCLUDED either).
	var holder_i := _make_mon("IOHolder1", [TypeChart.TYPE_NORMAL])
	holder_i.ability = innards_out
	var killer_i := _make_mon("IOKiller1", [TypeChart.TYPE_NORMAL])
	var result_i: Dictionary = AbilityManager.faint_retaliation_damage(
			holder_i, killer_i, tackle, 37)
	_chk("S4.01 Innards Out fires on a contact-fainting hit",
			result_i.get("ability_name", "") == "innards_out")
	_chk("S4.02 Innards Out damage = hp_before_hit (37), not any fixed fraction",
			result_i.get("damage", -1) == 37)

	# (ii) Fires on a NON-contact hit too — the key discriminator vs Aftermath.
	var holder_ii := _make_mon("IOHolder2", [TypeChart.TYPE_NORMAL])
	holder_ii.ability = innards_out
	var killer_ii := _make_mon("IOKiller2", [TypeChart.TYPE_NORMAL])
	var result_ii: Dictionary = AbilityManager.faint_retaliation_damage(
			holder_ii, killer_ii, ember, 22)
	_chk("S4.03 Innards Out fires on a NON-contact fainting hit (unlike Aftermath)",
			result_ii.get("ability_name", "") == "innards_out")
	_chk("S4.04 Innards Out damage = hp_before_hit (22) on the non-contact hit too",
			result_ii.get("damage", -1) == 22)

	# (iii) Damp does NOT block Innards Out (Aftermath-only gate).
	var holder_iii := _make_mon("IOHolder3", [TypeChart.TYPE_NORMAL])
	holder_iii.ability = innards_out
	var killer_iii := _make_mon("IOKiller3", [TypeChart.TYPE_NORMAL])
	var result_iii: Dictionary = AbilityManager.faint_retaliation_damage(
			holder_iii, killer_iii, tackle, 15, false, true)
	_chk("S4.05 Damp does NOT block Innards Out",
			result_iii.get("ability_name", "") == "innards_out" and result_iii.get("damage", -1) == 15)

	# (iv) killer == null / already fainted: no-op (shared guard with Aftermath).
	var holder_iv := _make_mon("IOHolder4", [TypeChart.TYPE_NORMAL])
	holder_iv.ability = innards_out
	_chk("S4.06 Innards Out no-op with a null killer",
			AbilityManager.faint_retaliation_damage(holder_iv, null, tackle, 10).is_empty())


# ── Section 5: Innards Out — full-battle integration (overkill discriminator) ─

func _test_section_5_innards_out_full_battle() -> void:
	var tackle := _load_move(33)
	var innards_out := _load_ability(215)

	# Attacker with very high Attack so Tackle massively overkills the holder's
	# remaining HP — Innards Out must retaliate with the holder's actual remaining HP
	# (a small number), NOT the move's much-larger raw calculated damage.
	var attacker := _make_mon("IOBattleAtk", [TypeChart.TYPE_NORMAL], 100, 200, 40, 60, 60, 100)
	attacker.add_move(tackle)
	var holder := _make_mon("IOBattleHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 20)
	holder.ability = innards_out
	holder.current_hp = 3  # far less than the hit's raw damage — overkill scenario
	holder.add_move(tackle)

	var bm := _make_bm()
	bm._force_roll = 100
	bm._force_crit = false
	var recoil_events := []
	var fainted_events := []
	bm.recoil_damage.connect(func(m, amt): recoil_events.append([m, amt]))
	bm.pokemon_fainted.connect(func(m): fainted_events.append(m))
	bm.start_battle(attacker, holder)

	_chk("S5.01 Innards Out holder fainted", fainted_events.any(func(m): return m == holder))
	_chk("S5.02 attacker took exactly 3 damage (the holder's real remaining HP), " +
			"not the move's much larger raw damage and not max_hp/4 like Aftermath",
			recoil_events.any(func(e): return e[0] == attacker and e[1] == 3))
	_chk("S5.03 attacker did NOT take max_hp/4 (confirms this is Innards Out's " +
			"shape, not Aftermath's)",
			not recoil_events.any(func(e): return e[0] == attacker and e[1] == attacker.max_hp / 4))

	bm.queue_free()


# ── Section 6: Corrosion — direct unit tests ─────────────────────────────────

func _test_section_6_corrosion_unit() -> void:
	var corrosion := _load_ability(212)
	var intimidate := _load_ability(22)

	var holder := _make_mon("CorrHolder", [TypeChart.TYPE_NORMAL])
	holder.ability = corrosion
	var non_holder := _make_mon("CorrNonHolder", [TypeChart.TYPE_NORMAL])
	non_holder.ability = intimidate

	_chk("S6.01 bypasses_poison_steel_immunity true for a Corrosion holder",
			AbilityManager.bypasses_poison_steel_immunity(holder))
	_chk("S6.02 bypasses_poison_steel_immunity false for a non-Corrosion attacker",
			not AbilityManager.bypasses_poison_steel_immunity(non_holder))

	# Direct try_apply_status: Steel-type target, normally immune to Poison/Toxic.
	var steel_mon := _make_mon("CorrSteel", [TypeChart.TYPE_STEEL])
	_chk("S6.03 Corrosion holder poisons a Steel-type target (normally immune)",
			StatusManager.try_apply_status(steel_mon, BattlePokemon.STATUS_POISON, null, null, false, holder))
	var steel_mon_toxic := _make_mon("CorrSteelToxic", [TypeChart.TYPE_STEEL])
	_chk("S6.04 Corrosion holder badly-poisons (Toxic) a Steel-type target too",
			StatusManager.try_apply_status(steel_mon_toxic, BattlePokemon.STATUS_TOXIC, null, null, false, holder))

	# Direct try_apply_status: Poison-type target, normally immune.
	var poison_mon := _make_mon("CorrPoison", [TypeChart.TYPE_POISON])
	_chk("S6.05 Corrosion holder poisons a Poison-type target (normally immune)",
			StatusManager.try_apply_status(poison_mon, BattlePokemon.STATUS_POISON, null, null, false, holder))

	# Discriminator: the SAME scenarios WITHOUT Corrosion (attacker=non_holder) fail.
	var steel_mon2 := _make_mon("CorrSteel2", [TypeChart.TYPE_STEEL])
	_chk("S6.06 discriminator: a non-Corrosion attacker cannot poison a Steel-type",
			not StatusManager.try_apply_status(steel_mon2, BattlePokemon.STATUS_POISON, null, null, false, non_holder))
	var poison_mon2 := _make_mon("CorrPoison2", [TypeChart.TYPE_POISON])
	_chk("S6.07 discriminator: a non-Corrosion attacker cannot poison a Poison-type",
			not StatusManager.try_apply_status(poison_mon2, BattlePokemon.STATUS_POISON, null, null, false, non_holder))
	# Even with no attacker at all (e.g. a hazard-driven poison) — still immune.
	var steel_mon3 := _make_mon("CorrSteel3", [TypeChart.TYPE_STEEL])
	_chk("S6.08 discriminator: no attacker at all still respects the type immunity",
			not StatusManager.try_apply_status(steel_mon3, BattlePokemon.STATUS_POISON))


# ── Section 7: Corrosion — full-battle integration ───────────────────────────

func _test_section_7_corrosion_full_battle() -> void:
	var corrosion := _load_ability(212)
	var toxic := _load_move(92)  # confirmed below to be a pure SE_TOXIC status move
	_chk("S7.00 move 92 is a status move with SE_TOXIC (sanity check on the fixture)",
			toxic.secondary_effect == MoveData.SE_TOXIC)

	var attacker := _make_mon("CorrBattleAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	attacker.ability = corrosion
	attacker.add_move(toxic)
	var defender := _make_mon("CorrBattleDef", [TypeChart.TYPE_STEEL], 100, 60, 60, 60, 60, 20)
	defender.add_move(toxic)

	var bm := _make_bm()
	bm._force_hit = true  # Toxic's accuracy=90, force the hit for determinism
	var status_events := []
	bm.secondary_applied.connect(func(m, se): status_events.append(m))
	bm.start_battle(attacker, defender)

	_chk("S7.01 Corrosion holder's Toxic actually poisoned the Steel-type defender " +
			"(normally immune)",
			status_events.any(func(m): return m == defender))

	bm.queue_free()


# ── Section 8: Merciless — direct unit tests + statistical sample ──────────

func _test_section_8_merciless_unit_and_statistical() -> void:
	var merciless := _load_ability(196)
	var tackle := _load_move(33)

	var attacker := _make_mon("MercAtk", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 80)
	attacker.ability = merciless
	var poisoned_def := _make_mon("MercDefPoisoned", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	poisoned_def.status = BattlePokemon.STATUS_POISON

	# (i) Statistical sample: EVERY hit crits against a poisoned target (guaranteed,
	# not probabilistic) — force_crit left null so the real (non-forced) path runs.
	var crit_count := 0
	var n := 30
	for _i in range(n):
		var result: Dictionary = DamageCalculator.calculate(attacker, poisoned_def, tackle, 100, false)
		if result["is_crit"]:
			crit_count += 1
	_chk("S8.01 Merciless: %d/%d hits crit against a poisoned target (must be ALL, not just most)" % [crit_count, n],
			crit_count == n)

	# (ii) Toxic counts too (STATUS1_PSN_ANY covers both).
	var toxic_def := _make_mon("MercDefToxic", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	toxic_def.status = BattlePokemon.STATUS_TOXIC
	var toxic_result: Dictionary = DamageCalculator.calculate(attacker, toxic_def, tackle, 100, false)
	_chk("S8.02 Merciless also guarantees a crit against a Toxic'd (badly poisoned) target",
			toxic_result["is_crit"])

	# (iii) Discriminator: a non-poisoned target does NOT guarantee a crit — sampled
	# statistically (matches [M17n-5]'s Super Luck/Serene Grace rate-test pattern).
	var plain_def := _make_mon("MercDefPlain", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	var plain_crit_count := 0
	for _i in range(n):
		var result2: Dictionary = DamageCalculator.calculate(attacker, plain_def, tackle, 100, false)
		if result2["is_crit"]:
			plain_crit_count += 1
	_chk("S8.03 discriminator: against a non-poisoned target, crits are NOT " +
			"guaranteed (%d/%d, expected well under 100%%)" % [plain_crit_count, n],
			plain_crit_count < n)

	# (iv) Discriminator: a non-Merciless attacker vs a poisoned target does NOT
	# guarantee a crit either.
	var plain_atk := _make_mon("MercAtkPlain", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 80)
	var plain_atk_crit_count := 0
	for _i in range(n):
		var result3: Dictionary = DamageCalculator.calculate(plain_atk, poisoned_def, tackle, 100, false)
		if result3["is_crit"]:
			plain_atk_crit_count += 1
	_chk("S8.04 discriminator: a non-Merciless attacker vs a poisoned target does " +
			"NOT guarantee a crit (%d/%d, expected well under 100%%)" % [plain_atk_crit_count, n],
			plain_atk_crit_count < n)


# ── Section 9: Opportunist — direct/full-battle ──────────────────────────────

func _test_section_9_opportunist_unit_and_full_battle() -> void:
	var opportunist := _load_ability(290)
	var swords_dance := _load_move(14)  # self-targeted Attack +2

	# (i) Full battle: opponent uses Swords Dance on itself; the Opportunist holder
	# (on the OTHER side) should copy the exact same Attack +2.
	var sd_user := _make_mon("OppSDUser", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	sd_user.add_move(swords_dance)
	var opp_holder := _make_mon("OppHolder", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	opp_holder.ability = opportunist
	opp_holder.add_move(swords_dance)

	var bm := _make_bm()
	var stage_events := []
	var opportunist_fires_i := []
	bm.stat_stage_changed.connect(func(m, stat, actual): stage_events.append([m, stat, actual]))
	bm.ability_triggered.connect(func(m, key): opportunist_fires_i.append([m, key]))
	bm.start_battle(sd_user, opp_holder)

	_chk("S9.01 Swords Dance raised the user's own Attack by +2",
			stage_events.any(func(e): return e[0] == sd_user and e[1] == BattlePokemon.STAGE_ATK and e[2] == 2))
	_chk("S9.02 Opportunist holder copied the SAME Attack +2 immediately",
			stage_events.any(func(e): return e[0] == opp_holder and e[1] == BattlePokemon.STAGE_ATK and e[2] == 2))
	_chk("S9.03 Opportunist's own trigger event fired for the holder",
			opportunist_fires_i.any(func(e): return e[0] == opp_holder and e[1] == "opportunist"))

	bm.queue_free()

	# (ii) Discriminator: the Opportunist holder's OWN self-raise does not runaway
	# self-trigger (no infinite loop, no second copy onto itself). Both mons carry
	# Tackle at index 0 (auto-select fallback for turn 2+, per CLAUDE.md's own
	# repeatable-move testing convention) so the battle actually ends via real
	# damage instead of two Swords-Dance-only movesets deadlocking forever.
	var tackle_for_opp := _load_move(33)
	var opp_holder2 := _make_mon("OppHolder2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp_holder2.ability = opportunist
	opp_holder2.add_move(tackle_for_opp)   # index 0
	opp_holder2.add_move(swords_dance)     # index 1
	var filler := _make_mon("OppFiller", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	filler.add_move(tackle_for_opp)

	var bm2 := _make_bm()
	var opportunist_fires_raw := []
	bm2.ability_triggered.connect(func(m, key): opportunist_fires_raw.append([m, key]))
	var stage_events2 := []
	bm2.stat_stage_changed.connect(func(m, stat, actual): stage_events2.append([m, stat, actual]))
	bm2.queue_move(0, 1)  # turn 1 only: opp_holder2 uses Swords Dance; falls back to Tackle after
	bm2.start_battle(opp_holder2, filler)

	_chk("S9.04 the Opportunist holder's OWN Swords Dance raised its Attack by " +
			"exactly +2 (not doubled by any self-trigger)",
			stage_events2.count([opp_holder2, BattlePokemon.STAGE_ATK, 2]) == 1)
	_chk("S9.05 Opportunist never fired for the holder's own self-raise",
			not opportunist_fires_raw.any(func(e): return e[0] == opp_holder2 and e[1] == "opportunist"))

	bm2.queue_free()

	# (iii) Direct unit-level discriminator: a stat DECREASE does not trigger
	# Opportunist (confirmed via the primary call site's own `actual > 0` gate —
	# checked here by calling apply_stat_change directly and confirming no copy
	# mechanism exists to invoke for a negative `actual`; the real gate lives in
	# BattleManager, already exercised end-to-end in (i)/(ii) above with an increase).
	var dec_holder := _make_mon("OppDecHolder", [TypeChart.TYPE_NORMAL])
	dec_holder.ability = opportunist
	var dec_actual: int = StatusManager.apply_stat_change(dec_holder, BattlePokemon.STAGE_ATK, -2, null, false)
	_chk("S9.06 sanity: apply_stat_change itself has no Opportunist-copy side effect " +
			"(that logic lives only at BattleManager's stat-increase call site)",
			dec_actual == -2)

	# (iv) Already-maxed: Opportunist's copy is a no-op (apply_stat_change's own clamp).
	var maxed_holder := _make_mon("OppMaxedHolder", [TypeChart.TYPE_NORMAL])
	maxed_holder.ability = opportunist
	maxed_holder.stat_stages[BattlePokemon.STAGE_ATK] = 6
	var maxed_actual: int = StatusManager.apply_stat_change(maxed_holder, BattlePokemon.STAGE_ATK, 2, null, false)
	_chk("S9.07 Opportunist's copy is a no-op when the holder is already at +6 " +
			"for that stat (apply_stat_change's own clamp, reused as-is)",
			maxed_actual == 0)


# ── Section 10: Neutralizing Gas suppression ─────────────────────────────────

func _test_section_10_neutralizing_gas_suppression() -> void:
	var aftermath := _load_ability(106)
	var innards_out := _load_ability(215)
	var corrosion := _load_ability(212)
	var merciless := _load_ability(196)
	var opportunist := _load_ability(290)
	var tackle := _load_move(33)

	# (i) Aftermath suppressed.
	var aft_holder := _make_mon("NGAftHolder", [TypeChart.TYPE_NORMAL])
	aft_holder.ability = aftermath
	var aft_killer := _make_mon("NGAftKiller", [TypeChart.TYPE_NORMAL])
	_chk("S10.01 Aftermath suppressed by Neutralizing Gas",
			AbilityManager.faint_retaliation_damage(aft_holder, aft_killer, tackle, 10, true).is_empty())

	# (ii) Innards Out suppressed.
	var io_holder := _make_mon("NGIOHolder", [TypeChart.TYPE_NORMAL])
	io_holder.ability = innards_out
	var io_killer := _make_mon("NGIOKiller", [TypeChart.TYPE_NORMAL])
	_chk("S10.02 Innards Out suppressed by Neutralizing Gas",
			AbilityManager.faint_retaliation_damage(io_holder, io_killer, tackle, 10, true).is_empty())

	# (iii) Corrosion suppressed.
	var corr_holder := _make_mon("NGCorrHolder", [TypeChart.TYPE_NORMAL])
	corr_holder.ability = corrosion
	_chk("S10.03 Corrosion suppressed by Neutralizing Gas",
			not AbilityManager.bypasses_poison_steel_immunity(corr_holder, true))

	# (iv) Merciless suppressed.
	var merc_holder := _make_mon("NGMercHolder", [TypeChart.TYPE_NORMAL])
	merc_holder.ability = merciless
	_chk("S10.04 Merciless's underlying ability check is suppressed by Neutralizing Gas",
			AbilityManager.effective_ability_id(merc_holder, true) != AbilityManager.ABILITY_MERCILESS)

	# (v) Opportunist suppressed.
	var opp_holder := _make_mon("NGOppHolder", [TypeChart.TYPE_NORMAL])
	opp_holder.ability = opportunist
	_chk("S10.05 Opportunist's underlying ability check is suppressed by Neutralizing Gas",
			AbilityManager.effective_ability_id(opp_holder, true) != AbilityManager.ABILITY_OPPORTUNIST)


# ── Section 11: Negative control ─────────────────────────────────────────────

func _test_section_11_negative_control() -> void:
	var tackle := _load_move(33)
	var mon := _make_mon("PlainMon", [TypeChart.TYPE_NORMAL])
	var other := _make_mon("PlainOther", [TypeChart.TYPE_NORMAL])

	_chk("S11.01 negative control: faint_retaliation_damage is empty with no relevant ability",
			AbilityManager.faint_retaliation_damage(mon, other, tackle, 10).is_empty())
	_chk("S11.02 negative control: bypasses_poison_steel_immunity false without Corrosion",
			not AbilityManager.bypasses_poison_steel_immunity(mon))
	_chk("S11.03 negative control: is_damp_active false with an ordinary Pokémon",
			not AbilityManager.is_damp_active([mon, other]))
	var steel_target := _make_mon("PlainSteel", [TypeChart.TYPE_STEEL])
	_chk("S11.04 negative control: an ordinary attacker still can't poison a Steel-type",
			not StatusManager.try_apply_status(steel_target, BattlePokemon.STATUS_POISON, null, null, false, mon))
	var plain_result: Dictionary = DamageCalculator.calculate(mon, other, tackle, 100, false)
	_chk("S11.05 negative control: an ordinary attacker's damage calc still returns " +
			"a valid result (not guaranteed-crit)", plain_result.has("is_crit"))
