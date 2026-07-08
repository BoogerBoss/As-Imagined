extends Node

# M18.5d Phase 2 test suite — gender-dependent mechanics: Attract, Rivalry,
# Cute Charm, Oblivious (4 genuinely separate mechanics, tested in 4 clearly
# distinguished sections, matching the tier's own combined-session framing).
#
# Ground truth: pokeemerald_expansion
#   Attract:    battle_scripts_1.s :: BattleScript_EffectAttract (L2220+) ->
#               Cmd_tryinfatuating (battle_script_commands.c L7613-7650);
#               CancelerInfatuation (battle_move_resolution.c L460-479, 50% roll).
#   Rivalry:    battle_util.c :: CalcMoveBasePowerAfterModifiers, case
#               ABILITY_RIVALRY (L6490-6494).
#   Cute Charm: battle_util.c L4130-4146 (ABILITY_CUTE_CHARM case, same switch
#               as Static/Flame Body/Poison Point).
#   Oblivious:  battle_stat_change.c :: IsIntimidateBlocked (L660-675, pre-
#               existing [M17n-1] half, untouched); battle_util.c ::
#               TryImmunityAbilityHealStatus (L8875-8886, new switch-in cure).
#
# Every statistical-sample assertion uses a fixed, explicit n (matching
# [M17n-5]/[M18e]/[M18.5d]'s established tolerance-band convention) — no
# whole-battle-aggregation risk anywhere in this file; every non-statistical
# assertion is scoped to one direct function call or one signal-snapshot.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_attract()
	_test_section_2_rivalry()
	_test_section_3_cute_charm()
	_test_section_4_oblivious()

	var total := _pass + _fail
	print("m18_5d2_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, type1: int, gender: int = BattlePokemon.GENDER_MALE,
		base_hp: int = 100, base_atk: int = 60, base_def: int = 60,
		base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	var bp := BattlePokemon.from_species(sp, 50)
	bp.gender = gender
	return bp


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section 1: Attract ───────────────────────────────────────────────────────

func _test_section_1_attract() -> void:
	var attract := _load_move(213)
	_chk("A00 Attract id=213, is_attract, ignores_substitute, Normal/Status/100/15",
			attract.is_attract and attract.ignores_substitute
			and attract.type == TypeChart.TYPE_NORMAL and attract.category == 2
			and attract.accuracy == 100 and attract.pp == 15)

	# A01: success — opposite gender, no blocker, not already infatuated.
	var atk1 := _make_mon("A_Atk1", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var def1 := _make_mon("A_Def1", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	var r1: String = StatusManager.try_apply_attract(def1, atk1)
	_chk("A01 opposite-gender infliction succeeds (empty reason, victim.infatuated=true)",
			r1 == "" and def1.infatuated)

	# A02: same gender — fails, not blocked.
	var atk2 := _make_mon("A_Atk2", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var def2 := _make_mon("A_Def2", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var r2: String = StatusManager.try_apply_attract(def2, atk2)
	_chk("A02 same-gender fails (not_opposite_gender), victim NOT infatuated",
			r2 == "not_opposite_gender" and not def2.infatuated)

	# A03/A04: genderless on either side — fails, not blocked.
	var atk3 := _make_mon("A_Atk3", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_GENDERLESS)
	var def3 := _make_mon("A_Def3", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	_chk("A03 genderless attacker -> not_opposite_gender",
			StatusManager.try_apply_attract(def3, atk3) == "not_opposite_gender")
	var atk4 := _make_mon("A_Atk4", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var def4 := _make_mon("A_Def4", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_GENDERLESS)
	_chk("A04 genderless defender -> not_opposite_gender",
			StatusManager.try_apply_attract(def4, atk4) == "not_opposite_gender")

	# A05: already infatuated — fails, not blocked.
	var atk5 := _make_mon("A_Atk5", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var def5 := _make_mon("A_Def5", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	def5.infatuated = true
	_chk("A05 already-infatuated victim fails (already_infatuated)",
			StatusManager.try_apply_attract(def5, atk5) == "already_infatuated")

	# A06: victim's own Oblivious blocks.
	var atk6 := _make_mon("A_Atk6", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var def6 := _make_mon("A_Def6", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	def6.ability = _load_ability(12)  # Oblivious
	_chk("A06 victim's own Oblivious blocks (reason=oblivious)",
			StatusManager.try_apply_attract(def6, atk6) == "oblivious")

	# A07: Aroma Veil on victim's own side blocks.
	var atk7 := _make_mon("A_Atk7", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var def7 := _make_mon("A_Def7", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	def7.ability = _load_ability(165)  # Aroma Veil
	_chk("A07 victim's own Aroma Veil blocks (reason=aroma_veil)",
			StatusManager.try_apply_attract(def7, atk7) == "aroma_veil")

	# A08: Aroma Veil on victim's ALLY blocks (doubles side-wide protection).
	var atk8 := _make_mon("A_Atk8", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var def8 := _make_mon("A_Def8", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	var def8_ally := _make_mon("A_Def8Ally", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	def8_ally.ability = _load_ability(165)  # Aroma Veil
	_chk("A08 victim's ALLY holding Aroma Veil also blocks (side-wide)",
			StatusManager.try_apply_attract(def8, atk8, def8_ally) == "aroma_veil")

	# A09: Mold Breaker bypasses the (breakable) Oblivious/Aroma Veil block.
	var atk9 := _make_mon("A_Atk9", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	atk9.ability = _load_ability(104)  # Mold Breaker
	var def9 := _make_mon("A_Def9", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	def9.ability = _load_ability(12)  # Oblivious
	var r9: String = StatusManager.try_apply_attract(def9, atk9, null, false, atk9, attract)
	_chk("A09 Mold Breaker bypasses victim's Oblivious (succeeds despite it)",
			r9 == "" and def9.infatuated)

	# A10: Neutralizing Gas suppresses Oblivious's block.
	var atk10 := _make_mon("A_Atk10", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var def10 := _make_mon("A_Def10", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	def10.ability = _load_ability(12)  # Oblivious
	var r10: String = StatusManager.try_apply_attract(def10, atk10, null, true)
	_chk("A10 Neutralizing Gas suppresses Oblivious's block (succeeds despite it)",
			r10 == "" and def10.infatuated)

	# A11: pre_move_check statistical rate — ~50% stuck while infatuated.
	# n=2000, wide margin (matching [M17n-5]/[M18.5d] Phase 1's own tolerance bands).
	var a11_mon := _make_mon("A11Mon", TypeChart.TYPE_NORMAL)
	a11_mon.infatuated = true
	var n := 2000
	var stuck_count := 0
	for _i in range(n):
		var check: Dictionary = StatusManager.pre_move_check(a11_mon)
		if check["infatuated_stuck"]:
			stuck_count += 1
	var stuck_rate: float = float(stuck_count) / n
	_chk(("A11 infatuated mon's stuck rate is near the expected 50%% " +
			"(within [42.5%%, 57.5%%], n=%d, observed=%.3f)") % [n, stuck_rate],
			stuck_rate > 0.425 and stuck_rate < 0.575)

	# A12: discriminator — a non-infatuated mon is never stuck.
	var a12_mon := _make_mon("A12Mon", TypeChart.TYPE_NORMAL)
	var a12_check: Dictionary = StatusManager.pre_move_check(a12_mon)
	_chk("A12 discriminator: a non-infatuated mon is never marked infatuated_stuck",
			not a12_check["infatuated_stuck"] and a12_check["can_move"])

	# A13: force_infatuation_hit seam — deterministic true/false.
	var a13_mon := _make_mon("A13Mon", TypeChart.TYPE_NORMAL)
	a13_mon.infatuated = true
	_chk("A13 force_infatuation_hit=true forces stuck",
			StatusManager.pre_move_check(a13_mon, null, null, null, null, null, false, true)["infatuated_stuck"])
	_chk("A13b force_infatuation_hit=false forces NOT stuck",
			not StatusManager.pre_move_check(a13_mon, null, null, null, null, null, false, false)["infatuated_stuck"])

	# A14: cured by switch-out (_clear_volatiles, the established mechanism every
	# other one-battle-stint volatile — confusion/focus_energy/etc. — already uses).
	var a14_bm := _make_bm()
	var a14_mon := _make_mon("A14Mon", TypeChart.TYPE_NORMAL)
	a14_mon.infatuated = true
	a14_bm._clear_volatiles(a14_mon)
	_chk("A14 switch-out (_clear_volatiles) cures infatuation",
			not a14_mon.infatuated)
	a14_bm.queue_free()

	# A15: full move-execution integration — Attract inflicted via a real battle turn.
	var a15_atk := _make_mon("A15Atk", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE,
			100, 60, 60, 60, 60, 100)
	a15_atk.add_move(attract)
	var a15_def := _make_mon("A15Def", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE,
			100, 60, 60, 60, 60, 20)
	a15_def.add_move(attract)
	var a15_bm := _make_bm()
	var a15_events := []
	a15_bm.infatuated.connect(func(m): a15_events.append(m))
	a15_bm._force_hit = true
	a15_bm.start_battle_with_parties(BattleParty.single(a15_atk), BattleParty.single(a15_def))
	_chk("A15 full-battle: Attract move inflicts infatuation on the opposite-gender " +
			"defender (signal-snapshot, first occurrence)",
			a15_events.size() > 0 and a15_events[0] == a15_def)
	a15_bm.queue_free()

	# A16: full move-execution integration — blocked by Oblivious, distinguishable tag.
	var a16_atk := _make_mon("A16Atk", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE,
			100, 60, 60, 60, 60, 100)
	a16_atk.add_move(attract)
	var a16_def := _make_mon("A16Def", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE,
			100, 60, 60, 60, 60, 20)
	a16_def.ability = _load_ability(12)  # Oblivious
	a16_def.add_move(attract)
	var a16_bm := _make_bm()
	var a16_failed := []
	var a16_triggered := []
	a16_bm.move_effect_failed.connect(func(m, reason): a16_failed.append(reason))
	a16_bm.ability_triggered.connect(func(m, tag): a16_triggered.append(tag))
	a16_bm._force_hit = true
	a16_bm.start_battle_with_parties(BattleParty.single(a16_atk), BattleParty.single(a16_def))
	_chk("A16 full-battle: Oblivious blocks Attract (attract_blocked + oblivious tag, " +
			"first occurrence)",
			a16_failed.size() > 0 and a16_failed[0] == "attract_blocked"
			and a16_triggered.has("oblivious") and not a16_def.infatuated)
	a16_bm.queue_free()


# ── Section 2: Rivalry ───────────────────────────────────────────────────────

func _test_section_2_rivalry() -> void:
	var rivalry := _load_ability(79)
	_chk("R00 Rivalry id=79, NOT breakable", rivalry.ability_id == 79 and not rivalry.breakable)

	var tackle := _load_move(33)
	var weather := DamageCalculator.WEATHER_NONE

	# R1: same gender -> UQ_4_12(1.25) = 5120.
	var r_atk1 := _make_mon("R_Atk1", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	r_atk1.ability = rivalry
	var r_def1 := _make_mon("R_Def1", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	_chk("R1 same-gender: modifier == 5120 (UQ_4_12(1.25))",
			AbilityManager.move_power_modifier_uq412(
					r_atk1, tackle, weather, null, false, false, false, r_def1) == 5120)

	# R2: opposite gender -> UQ_4_12(0.75) = 3072.
	var r_atk2 := _make_mon("R_Atk2", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	r_atk2.ability = rivalry
	var r_def2 := _make_mon("R_Def2", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	_chk("R2 opposite-gender: modifier == 3072 (UQ_4_12(0.75))",
			AbilityManager.move_power_modifier_uq412(
					r_atk2, tackle, weather, null, false, false, false, r_def2) == 3072)

	# R3/R4: genderless attacker or defender -> neutral (4096).
	var r_atk3 := _make_mon("R_Atk3", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_GENDERLESS)
	r_atk3.ability = rivalry
	var r_def3 := _make_mon("R_Def3", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	_chk("R3 genderless attacker: modifier == 4096 (neutral)",
			AbilityManager.move_power_modifier_uq412(
					r_atk3, tackle, weather, null, false, false, false, r_def3) == 4096)
	var r_atk4 := _make_mon("R_Atk4", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	r_atk4.ability = rivalry
	var r_def4 := _make_mon("R_Def4", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_GENDERLESS)
	_chk("R4 genderless defender: modifier == 4096 (neutral)",
			AbilityManager.move_power_modifier_uq412(
					r_atk4, tackle, weather, null, false, false, false, r_def4) == 4096)

	# R5: Neutralizing Gas suppresses Rivalry entirely.
	var r_atk5 := _make_mon("R_Atk5", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	r_atk5.ability = rivalry
	var r_def5 := _make_mon("R_Def5", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	_chk("R5 Neutralizing Gas suppresses Rivalry (modifier == 4096 despite same gender)",
			AbilityManager.move_power_modifier_uq412(
					r_atk5, tackle, weather, null, true, false, false, r_def5) == 4096)

	# R6: discriminator — a plain (no Rivalry) attacker gets no modifier regardless
	# of gender pairing, proving R1/R2 aren't vacuously true.
	var r_atk6 := _make_mon("R_Atk6", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var r_def6 := _make_mon("R_Def6", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	_chk("R6 discriminator: no Rivalry -> modifier == 4096 even with a same-gender pairing",
			AbilityManager.move_power_modifier_uq412(
					r_atk6, tackle, weather, null, false, false, false, r_def6) == 4096)

	# R7: real damage-pipeline integration — same-gender deals MORE damage than
	# opposite-gender, via a real DamageCalculator.calculate call with BOTH roll and
	# crit forced on every scenario (this project's established pairwise-damage-
	# comparison convention).
	var r_atk7 := _make_mon("R_Atk7", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE,
			100, 100, 60, 60, 60, 100)
	r_atk7.ability = rivalry
	var r_def7_same := _make_mon("R_Def7Same", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE,
			200, 60, 60, 60, 60, 60)
	var r_def7_opp := _make_mon("R_Def7Opp", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE,
			200, 60, 60, 60, 60, 60)
	var dmg_same: Dictionary = DamageCalculator.calculate(
			r_atk7, r_def7_same, tackle, 100, false)
	var dmg_opp: Dictionary = DamageCalculator.calculate(
			r_atk7, r_def7_opp, tackle, 100, false)
	_chk(("R7 pipeline integration: same-gender damage (%d) > opposite-gender damage (%d), " +
			"both forced roll=100/crit=false") % [dmg_same["damage"], dmg_opp["damage"]],
			dmg_same["damage"] > dmg_opp["damage"])


# ── Section 3: Cute Charm ────────────────────────────────────────────────────

func _test_section_3_cute_charm() -> void:
	var cute_charm := _load_ability(56)
	_chk("C00 Cute Charm id=56, NOT breakable",
			cute_charm.ability_id == 56 and not cute_charm.breakable)

	var contact_move := _load_move(33)  # Tackle, makes_contact=true
	var non_contact_move := _load_move(55)  # Water Gun, no contact
	# Confirm the non-contact move really doesn't make contact before relying on it.
	_chk("C00b sanity: Water Gun does not make contact (needed for C05 below)",
			not non_contact_move.makes_contact)

	# C1: success — opposite-gender attacker, forced roll.
	var c_atk1 := _make_mon("C_Atk1", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var c_def1 := _make_mon("C_Def1", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_def1.ability = cute_charm
	var res1: Dictionary = AbilityManager.try_contact_effects(
			c_atk1, c_def1, contact_move, 10, true)
	_chk("C1 Cute Charm infatuates an opposite-gender contact attacker",
			res1["attract_inflicted"] and c_atk1.infatuated and res1["ability_name"] == "cute_charm")

	# C2: discriminator — same-gender attacker, no infliction.
	var c_atk2 := _make_mon("C_Atk2", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	var c_def2 := _make_mon("C_Def2", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_def2.ability = cute_charm
	var res2: Dictionary = AbilityManager.try_contact_effects(
			c_atk2, c_def2, contact_move, 10, true)
	_chk("C2 discriminator: same-gender attacker is NOT infatuated",
			not res2["attract_inflicted"] and not c_atk2.infatuated)

	# C3: discriminator — genderless attacker, no infliction.
	var c_atk3 := _make_mon("C_Atk3", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_GENDERLESS)
	var c_def3 := _make_mon("C_Def3", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_def3.ability = cute_charm
	var res3: Dictionary = AbilityManager.try_contact_effects(
			c_atk3, c_def3, contact_move, 10, true)
	_chk("C3 discriminator: genderless attacker is NOT infatuated",
			not res3["attract_inflicted"])

	# C4: discriminator — genderless Cute Charm holder, no infliction.
	var c_atk4 := _make_mon("C_Atk4", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var c_def4 := _make_mon("C_Def4", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_GENDERLESS)
	c_def4.ability = cute_charm
	var res4: Dictionary = AbilityManager.try_contact_effects(
			c_atk4, c_def4, contact_move, 10, true)
	_chk("C4 discriminator: genderless Cute Charm holder does NOT infatuate",
			not res4["attract_inflicted"])

	# C5: discriminator — non-contact hit never triggers it, even with a forced roll.
	var c_atk5 := _make_mon("C_Atk5", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var c_def5 := _make_mon("C_Def5", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_def5.ability = cute_charm
	var res5: Dictionary = AbilityManager.try_contact_effects(
			c_atk5, c_def5, non_contact_move, 10, true)
	_chk("C5 discriminator: a non-contact hit never triggers Cute Charm",
			not res5["attract_inflicted"])

	# C6: blocked by the attacker's own Oblivious.
	var c_atk6 := _make_mon("C_Atk6", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	c_atk6.ability = _load_ability(12)  # Oblivious
	var c_def6 := _make_mon("C_Def6", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_def6.ability = cute_charm
	var res6: Dictionary = AbilityManager.try_contact_effects(
			c_atk6, c_def6, contact_move, 10, true)
	_chk("C6 attacker's own Oblivious blocks Cute Charm's infliction",
			not res6["attract_inflicted"] and not c_atk6.infatuated)

	# C7: blocked by Aroma Veil on the attacker's own side.
	var c_atk7 := _make_mon("C_Atk7", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	c_atk7.ability = _load_ability(165)  # Aroma Veil
	var c_def7 := _make_mon("C_Def7", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_def7.ability = cute_charm
	var res7: Dictionary = AbilityManager.try_contact_effects(
			c_atk7, c_def7, contact_move, 10, true)
	_chk("C7 Aroma Veil on the attacker's own side blocks Cute Charm",
			not res7["attract_inflicted"])

	# C8: blocked by Aroma Veil on the attacker's ALLY (doubles side-wide).
	var c_atk8 := _make_mon("C_Atk8", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var c_atk8_ally := _make_mon("C_Atk8Ally", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_atk8_ally.ability = _load_ability(165)  # Aroma Veil
	var c_def8 := _make_mon("C_Def8", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_def8.ability = cute_charm
	var res8: Dictionary = AbilityManager.try_contact_effects(
			c_atk8, c_def8, contact_move, 10, true, null, false, c_atk8_ally)
	_chk("C8 Aroma Veil on the attacker's ALLY also blocks Cute Charm (side-wide)",
			not res8["attract_inflicted"])

	# C9: discriminator — the attacker's own Mold Breaker does NOT bypass anything
	# here (Cute Charm has no `.breakable` flag; its own trigger doesn't check the
	# attacker's ability for a bypass at all). Fires normally.
	var c_atk9 := _make_mon("C_Atk9", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	c_atk9.ability = _load_ability(104)  # Mold Breaker
	var c_def9 := _make_mon("C_Def9", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_def9.ability = cute_charm
	var res9: Dictionary = AbilityManager.try_contact_effects(
			c_atk9, c_def9, contact_move, 10, true)
	_chk("C9 discriminator: an attacking Mold Breaker holder is still infatuated " +
			"normally (Cute Charm isn't itself Mold-Breaker-bypassable)",
			res9["attract_inflicted"])

	# C10: Neutralizing Gas suppresses Cute Charm's own trigger (the holder's ability).
	var c_atk10 := _make_mon("C_Atk10", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var c_def10 := _make_mon("C_Def10", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_def10.ability = cute_charm
	var res10: Dictionary = AbilityManager.try_contact_effects(
			c_atk10, c_def10, contact_move, 10, true, null, true)
	_chk("C10 Neutralizing Gas suppresses Cute Charm's own trigger",
			not res10["attract_inflicted"])

	# C11: forced-failed roll — no infliction despite everything else lining up.
	var c_atk11 := _make_mon("C_Atk11", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var c_def11 := _make_mon("C_Def11", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	c_def11.ability = cute_charm
	var res11: Dictionary = AbilityManager.try_contact_effects(
			c_atk11, c_def11, contact_move, 10, false)
	_chk("C11 a forced-failed roll produces no infliction",
			not res11["attract_inflicted"])


# ── Section 4: Oblivious ─────────────────────────────────────────────────────

func _test_section_4_oblivious() -> void:
	var oblivious := _load_ability(12)
	_chk("O00 Oblivious id=12, breakable", oblivious.ability_id == 12 and oblivious.breakable)

	# O1: blocks Attract's own move-based infliction (already exercised as A06/A16
	# above from Attract's own side; re-confirmed here from Oblivious's section for
	# completeness).
	var o_atk1 := _make_mon("O_Atk1", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	var o_def1 := _make_mon("O_Def1", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	o_def1.ability = oblivious
	_chk("O1 Oblivious blocks Attract's move-based infliction",
			StatusManager.try_apply_attract(o_def1, o_atk1) == "oblivious")

	# O2: blocks Cute Charm's infliction (attacker holds Oblivious).
	var cute_charm := _load_ability(56)
	var o_atk2 := _make_mon("O_Atk2", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_MALE)
	o_atk2.ability = oblivious
	var o_def2 := _make_mon("O_Def2", TypeChart.TYPE_NORMAL, BattlePokemon.GENDER_FEMALE)
	o_def2.ability = cute_charm
	var contact_move := _load_move(33)
	var res2: Dictionary = AbilityManager.try_contact_effects(
			o_atk2, o_def2, contact_move, 10, true)
	_chk("O2 Oblivious blocks Cute Charm's infliction on the holder",
			not res2["attract_inflicted"])

	# O3: existing Intimidate-block behavior is UNCHANGED (light smoke check — the
	# full regression suite for this is m17n1_test.tscn, rerun separately).
	var intimidate := _load_ability(22)
	var o_holder3 := _make_mon("O_Holder3", TypeChart.TYPE_NORMAL)
	o_holder3.ability = intimidate
	var o_opp3 := _make_mon("O_Opp3", TypeChart.TYPE_NORMAL)
	o_opp3.ability = oblivious
	var si_result3: Dictionary = AbilityManager.try_switch_in(o_holder3, o_opp3)
	_chk("O3 Oblivious still blocks Intimidate's Attack drop (existing [M17n-1] " +
			"behavior, unchanged)",
			si_result3["atk_change"] == 0 and o_opp3.stat_stages[BattlePokemon.STAGE_ATK] == 0)

	# O4: NEW — switch-in cures the holder's own PRE-EXISTING infatuation.
	var o_mon4 := _make_mon("O_Mon4", TypeChart.TYPE_NORMAL)
	o_mon4.ability = oblivious
	o_mon4.infatuated = true
	var o_opp4 := _make_mon("O_Opp4", TypeChart.TYPE_NORMAL)
	var si_result4: Dictionary = AbilityManager.try_switch_in(o_mon4, o_opp4)
	_chk("O4 Oblivious cures pre-existing infatuation on switch-in " +
			"(cured_infatuation=true, mon.infatuated becomes false)",
			si_result4["cured_infatuation"] and not o_mon4.infatuated)

	# O5: discriminator — a non-Oblivious holder does NOT get this cure.
	var o_mon5 := _make_mon("O_Mon5", TypeChart.TYPE_NORMAL)
	o_mon5.infatuated = true
	var o_opp5 := _make_mon("O_Opp5", TypeChart.TYPE_NORMAL)
	var si_result5: Dictionary = AbilityManager.try_switch_in(o_mon5, o_opp5)
	_chk("O5 discriminator: a non-Oblivious holder's switch-in does NOT cure " +
			"infatuation", not si_result5["cured_infatuation"] and o_mon5.infatuated)

	# O6: Neutralizing Gas suppresses Oblivious's NEW switch-in cure too.
	var o_mon6 := _make_mon("O_Mon6", TypeChart.TYPE_NORMAL)
	o_mon6.ability = oblivious
	o_mon6.infatuated = true
	var o_opp6 := _make_mon("O_Opp6", TypeChart.TYPE_NORMAL)
	var si_result6: Dictionary = AbilityManager.try_switch_in(o_mon6, o_opp6, null, true)
	_chk("O6 Neutralizing Gas suppresses Oblivious's switch-in cure too",
			not si_result6["cured_infatuation"] and o_mon6.infatuated)
