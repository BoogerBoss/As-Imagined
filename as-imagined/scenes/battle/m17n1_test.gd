extends Node

# M17n-1 test suite — Status-immunity family + simple no-ops (docs/m17n_recon.md
# Group 1). Naming note: uses a numeral suffix (m17n1, not m17n-1) since M17n itself is
# sub-tiered across multiple implementation tiers — this departs from the single-letter
# m17a-m17m convention deliberately, not a naming collision risk (Godot scene/script
# names can't contain hyphens anyway).
#
# Scope: 22 abilities across four categories, per docs/decisions.md [M17n-1]:
#   Category A (genuine status-immunity, 12): Insomnia/Vital Spirit (sleep),
#     Immunity (poison/toxic), Limber (paralysis), Water Veil (burn), Magma Armor
#     (freeze), Inner Focus (flinch + Intimidate-block), Own Tempo (confusion +
#     Intimidate-block), Shield Dust (all secondary effects), Leaf Guard (all statuses,
#     sun-gated), Early Bird (2x sleep-counter decrement), Aroma Veil (Disable/Encore).
#     Oblivious rides along here too (Intimidate-block only — its OWN primary effect,
#     Attract/Taunt immunity, is Category C's no-op shape).
#   Category B (move-flag immunity via pre-existing dormant MoveData flags, 2):
#     Soundproof (sound_move), Bulletproof (ballistic_move).
#   Category C (documented cosmetic no-ops, 2): Illuminate, Honey Gather.
#   Category D (confirmed out-of-battle-engine scope, 3, NO code/data footprint):
#     Run Away, Pickup, Ball Fetch — not tested here, nothing to test.
#
# A real, source-verified finding beyond the recon's own scope: all seven immunity
# abilities ALSO cure a matching PRE-EXISTING status/confusion on switch-in
# (TryImmunityAbilityHealStatus, battle_util.c L8817-8889) — a separate trigger point
# from the infliction-blocking checks, tested in its own section below. Also:
# Inner Focus/Own Tempo/Oblivious/Scrappy(not yet implemented) fully block Intimidate's
# Attack drop under this project's GEN_LATEST config (IsIntimidateBlocked,
# battle_stat_change.c L660-675) — tested via full-battle Intimidate scenarios.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state.
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing test function.
#   - Type immunity precedes ability logic: all scenarios use Normal-type combatants
#     except where a specific type interaction is the mechanic under test.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_sleep_immunity_unit()
	_test_section_3_immunity_unit()
	_test_section_4_limber_unit()
	_test_section_5_water_veil_unit()
	_test_section_6_magma_armor_unit()
	_test_section_7_leaf_guard_unit()
	_test_section_8_own_tempo_confusion_unit()
	_test_section_9_inner_focus_flinch_unit()
	_test_section_10_shield_dust_unit()
	_test_section_11_early_bird_unit()
	_test_section_12_switch_in_cure_unit()
	_test_section_13_intimidate_block_full_battle()
	_test_section_14_aroma_veil_full_battle()
	_test_section_15_soundproof_full_battle()
	_test_section_16_bulletproof_full_battle()
	_test_section_17_cosmetic_no_ops()
	_test_section_18_mold_breaker_bypass()
	_test_section_19_neutralizing_gas_suppression()
	_test_section_20_negative_case()
	_test_section_21_scrappy_blocks_intimidate_full_battle()
	_test_section_22_grass_powder_immunity_full_battle()

	var total := _pass + _fail
	print("m17n1_test: %d/%d passed" % [_pass, total])
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
	var insomnia := _load_ability(15)
	_chk("S1.01 Insomnia id=15, breakable=true", insomnia.ability_id == 15 and insomnia.breakable)

	var vital_spirit := _load_ability(72)
	_chk("S1.02 Vital Spirit id=72, breakable=true", vital_spirit.ability_id == 72 and vital_spirit.breakable)

	var immunity := _load_ability(17)
	_chk("S1.03 Immunity id=17, breakable=true", immunity.ability_id == 17 and immunity.breakable)

	var limber := _load_ability(7)
	_chk("S1.04 Limber id=7, breakable=true", limber.ability_id == 7 and limber.breakable)

	var water_veil := _load_ability(41)
	_chk("S1.05 Water Veil id=41, breakable=true", water_veil.ability_id == 41 and water_veil.breakable)

	var magma_armor := _load_ability(40)
	_chk("S1.06 Magma Armor id=40, breakable=true", magma_armor.ability_id == 40 and magma_armor.breakable)

	var inner_focus := _load_ability(39)
	_chk("S1.07 Inner Focus id=39, breakable=true", inner_focus.ability_id == 39 and inner_focus.breakable)

	var own_tempo := _load_ability(20)
	_chk("S1.08 Own Tempo id=20, breakable=true", own_tempo.ability_id == 20 and own_tempo.breakable)

	var shield_dust := _load_ability(19)
	_chk("S1.09 Shield Dust id=19, breakable=true", shield_dust.ability_id == 19 and shield_dust.breakable)

	var leaf_guard := _load_ability(102)
	_chk("S1.10 Leaf Guard id=102, breakable=true", leaf_guard.ability_id == 102 and leaf_guard.breakable)

	var early_bird := _load_ability(48)
	_chk("S1.11 Early Bird id=48, NOT breakable (self-check)", early_bird.ability_id == 48 and not early_bird.breakable)

	var aroma_veil := _load_ability(165)
	_chk("S1.12 Aroma Veil id=165, breakable=true", aroma_veil.ability_id == 165 and aroma_veil.breakable)

	var soundproof := _load_ability(43)
	_chk("S1.13 Soundproof id=43, breakable=true", soundproof.ability_id == 43 and soundproof.breakable)

	var bulletproof := _load_ability(171)
	_chk("S1.14 Bulletproof id=171, breakable=true", bulletproof.ability_id == 171 and bulletproof.breakable)

	var illuminate := _load_ability(35)
	_chk("S1.15 Illuminate id=35 (documented no-op)", illuminate.ability_id == 35)

	var honey_gather := _load_ability(118)
	_chk("S1.16 Honey Gather id=118 (documented no-op)", honey_gather.ability_id == 118)

	var oblivious := _load_ability(12)
	_chk("S1.17 Oblivious id=12, breakable=true", oblivious.ability_id == 12 and oblivious.breakable)

	var cute_charm := _load_ability(56)
	_chk("S1.18 Cute Charm id=56 (no-op dependency, NOT breakable)",
			cute_charm.ability_id == 56 and not cute_charm.breakable)

	var damp := _load_ability(6)
	_chk("S1.19 Damp id=6 (no-op dependency), breakable=true", damp.ability_id == 6 and damp.breakable)


# ── Section 2: Sleep immunity — Insomnia / Vital Spirit ──────────────────────

func _test_section_2_sleep_immunity_unit() -> void:
	var insomnia := _load_ability(15)
	var vital_spirit := _load_ability(72)

	var im := _make_mon("InsomniaMon", [TypeChart.TYPE_NORMAL])
	im.ability = insomnia
	_chk("S2.01 Insomnia blocks sleep",
			StatusManager.try_apply_status(im, BattlePokemon.STATUS_SLEEP) == false)

	var vsm := _make_mon("VitalSpiritMon", [TypeChart.TYPE_NORMAL])
	vsm.ability = vital_spirit
	_chk("S2.02 Vital Spirit blocks sleep",
			StatusManager.try_apply_status(vsm, BattlePokemon.STATUS_SLEEP) == false)

	var im2 := _make_mon("InsomniaMon2", [TypeChart.TYPE_NORMAL])
	im2.ability = insomnia
	_chk("S2.03 Insomnia does NOT block poison (sleep-specific discriminator)",
			StatusManager.try_apply_status(im2, BattlePokemon.STATUS_POISON) == true)

	var plain := _make_mon("PlainSleepMon", [TypeChart.TYPE_NORMAL])
	_chk("S2.04 ordinary Pokémon: sleep applies normally",
			StatusManager.try_apply_status(plain, BattlePokemon.STATUS_SLEEP) == true)


# ── Section 3: Immunity — poison/toxic ───────────────────────────────────────

func _test_section_3_immunity_unit() -> void:
	var immunity := _load_ability(17)

	var m1 := _make_mon("ImmunityMon1", [TypeChart.TYPE_NORMAL])
	m1.ability = immunity
	_chk("S3.01 Immunity blocks poison",
			StatusManager.try_apply_status(m1, BattlePokemon.STATUS_POISON) == false)

	var m2 := _make_mon("ImmunityMon2", [TypeChart.TYPE_NORMAL])
	m2.ability = immunity
	_chk("S3.02 Immunity blocks toxic",
			StatusManager.try_apply_status(m2, BattlePokemon.STATUS_TOXIC) == false)

	var m3 := _make_mon("ImmunityMon3", [TypeChart.TYPE_NORMAL])
	m3.ability = immunity
	_chk("S3.03 Immunity does NOT block paralysis (poison-specific discriminator)",
			StatusManager.try_apply_status(m3, BattlePokemon.STATUS_PARALYSIS) == true)


# ── Section 4: Limber — paralysis ─────────────────────────────────────────────

func _test_section_4_limber_unit() -> void:
	var limber := _load_ability(7)

	var m1 := _make_mon("LimberMon1", [TypeChart.TYPE_NORMAL])
	m1.ability = limber
	_chk("S4.01 Limber blocks paralysis",
			StatusManager.try_apply_status(m1, BattlePokemon.STATUS_PARALYSIS) == false)

	var m2 := _make_mon("LimberMon2", [TypeChart.TYPE_NORMAL])
	m2.ability = limber
	_chk("S4.02 Limber does NOT block burn (paralysis-specific discriminator)",
			StatusManager.try_apply_status(m2, BattlePokemon.STATUS_BURN) == true)


# ── Section 5: Water Veil — burn ─────────────────────────────────────────────

func _test_section_5_water_veil_unit() -> void:
	var water_veil := _load_ability(41)

	var m1 := _make_mon("WaterVeilMon1", [TypeChart.TYPE_NORMAL])
	m1.ability = water_veil
	_chk("S5.01 Water Veil blocks burn",
			StatusManager.try_apply_status(m1, BattlePokemon.STATUS_BURN) == false)

	var m2 := _make_mon("WaterVeilMon2", [TypeChart.TYPE_NORMAL])
	m2.ability = water_veil
	_chk("S5.02 Water Veil does NOT block freeze (burn-specific discriminator)",
			StatusManager.try_apply_status(m2, BattlePokemon.STATUS_FREEZE) == true)


# ── Section 6: Magma Armor — freeze ──────────────────────────────────────────

func _test_section_6_magma_armor_unit() -> void:
	var magma_armor := _load_ability(40)

	var m1 := _make_mon("MagmaArmorMon1", [TypeChart.TYPE_NORMAL])
	m1.ability = magma_armor
	_chk("S6.01 Magma Armor blocks freeze",
			StatusManager.try_apply_status(m1, BattlePokemon.STATUS_FREEZE) == false)

	var m2 := _make_mon("MagmaArmorMon2", [TypeChart.TYPE_NORMAL])
	m2.ability = magma_armor
	_chk("S6.02 Magma Armor does NOT block sleep (freeze-specific discriminator)",
			StatusManager.try_apply_status(m2, BattlePokemon.STATUS_SLEEP) == true)


# ── Section 7: Leaf Guard — all statuses, sun-gated ──────────────────────────

func _test_section_7_leaf_guard_unit() -> void:
	var leaf_guard := _load_ability(102)

	var m1 := _make_mon("LeafGuardMon1", [TypeChart.TYPE_NORMAL])
	m1.ability = leaf_guard
	_chk("S7.01 Leaf Guard blocks burn in sun",
			StatusManager.try_apply_status(m1, BattlePokemon.STATUS_BURN, null, null, false, null,
					DamageCalculator.WEATHER_SUN) == false)

	var m2 := _make_mon("LeafGuardMon2", [TypeChart.TYPE_NORMAL])
	m2.ability = leaf_guard
	_chk("S7.02 Leaf Guard blocks paralysis in sun (all-statuses, not burn-specific)",
			StatusManager.try_apply_status(m2, BattlePokemon.STATUS_PARALYSIS, null, null, false, null,
					DamageCalculator.WEATHER_SUN) == false)

	var m3 := _make_mon("LeafGuardMon3", [TypeChart.TYPE_NORMAL])
	m3.ability = leaf_guard
	_chk("S7.03 Leaf Guard does NOT block burn OUTSIDE sun (sun-gate discriminator)",
			StatusManager.try_apply_status(m3, BattlePokemon.STATUS_BURN, null, null, false, null,
					DamageCalculator.WEATHER_NONE) == true)

	var m4 := _make_mon("LeafGuardMon4", [TypeChart.TYPE_NORMAL])
	m4.ability = leaf_guard
	_chk("S7.04 Leaf Guard does NOT block in rain either (specifically sun-gated)",
			StatusManager.try_apply_status(m4, BattlePokemon.STATUS_BURN, null, null, false, null,
					DamageCalculator.WEATHER_RAIN) == true)


# ── Section 8: Own Tempo — confusion ─────────────────────────────────────────

func _test_section_8_own_tempo_confusion_unit() -> void:
	var own_tempo := _load_ability(20)

	var m1 := _make_mon("OwnTempoMon1", [TypeChart.TYPE_NORMAL])
	m1.ability = own_tempo
	_chk("S8.01 Own Tempo blocks confusion",
			StatusManager.try_apply_confusion(m1) == false)

	var plain := _make_mon("PlainConfusionMon", [TypeChart.TYPE_NORMAL])
	_chk("S8.02 ordinary Pokémon: confusion applies normally",
			StatusManager.try_apply_confusion(plain) == true)

	# Mold Breaker bypasses Own Tempo's confusion block.
	var mold_breaker := _load_ability(104)
	var mb_attacker := _make_mon("MBAttackerS8", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker
	var m2 := _make_mon("OwnTempoMon2", [TypeChart.TYPE_NORMAL])
	m2.ability = own_tempo
	_chk("S8.03 Mold Breaker bypasses Own Tempo's confusion block",
			StatusManager.try_apply_confusion(m2, null, false, mb_attacker) == true)


# ── Section 9: Inner Focus — flinch (via try_secondary_effect's SE_FLINCH) ───

func _test_section_9_inner_focus_flinch_unit() -> void:
	var inner_focus := _load_ability(39)
	var flinch_move := _make_flinch_move()

	var m1 := _make_mon("InnerFocusMon1", [TypeChart.TYPE_NORMAL])
	m1.ability = inner_focus
	var attacker := _make_mon("FlinchAttacker1", [TypeChart.TYPE_NORMAL])
	_chk("S9.01 Inner Focus blocks flinch",
			StatusManager.try_secondary_effect(attacker, m1, flinch_move, true) == false)

	var plain := _make_mon("PlainFlinchMon", [TypeChart.TYPE_NORMAL])
	_chk("S9.02 ordinary Pokémon: flinch roll succeeds normally",
			StatusManager.try_secondary_effect(attacker, plain, flinch_move, true) == true)

	# Discriminator: Inner Focus does NOT block confusion (flinch-specific, not Shield-Dust-broad).
	var m2 := _make_mon("InnerFocusMon2", [TypeChart.TYPE_NORMAL])
	m2.ability = inner_focus
	_chk("S9.03 Inner Focus does NOT block confusion infliction (flinch-specific)",
			StatusManager.try_apply_confusion(m2) == true)


func _make_flinch_move() -> MoveData:
	var m := MoveData.new()
	m.move_name = "TestFlinchMove"
	m.type = TypeChart.TYPE_NORMAL
	m.category = 0
	m.power = 40
	m.secondary_effect = MoveData.SE_FLINCH
	m.secondary_chance = 30
	return m


# ── Section 10: Shield Dust — blocks ALL true secondary effects ─────────────

func _test_section_10_shield_dust_unit() -> void:
	var shield_dust := _load_ability(19)
	var flinch_move := _make_flinch_move()
	var thunder_wave := _load_move(86)  # guaranteed paralysis, secondary_chance == 0 (primary)

	var m1 := _make_mon("ShieldDustMon1", [TypeChart.TYPE_NORMAL])
	m1.ability = shield_dust
	var attacker := _make_mon("SDAttacker1", [TypeChart.TYPE_NORMAL])
	_chk("S10.01 Shield Dust blocks a TRUE secondary effect (flinch, chance-based)",
			StatusManager.try_secondary_effect(attacker, m1, flinch_move, true) == false)

	var m2 := _make_mon("ShieldDustMon2", [TypeChart.TYPE_NORMAL])
	m2.ability = shield_dust
	_chk("S10.02 Shield Dust does NOT block a GUARANTEED/primary status move " +
			"(secondary_chance == 0 — matches source's !primary condition)",
			StatusManager.try_secondary_effect(attacker, m2, thunder_wave) == true)

	var mold_breaker := _load_ability(104)
	var mb_attacker := _make_mon("MBAttackerS10", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker
	var m3 := _make_mon("ShieldDustMon3", [TypeChart.TYPE_NORMAL])
	m3.ability = shield_dust
	_chk("S10.03 Mold Breaker bypasses Shield Dust",
			StatusManager.try_secondary_effect(mb_attacker, m3, flinch_move, true) == true)


# ── Section 11: Early Bird — 2x sleep-counter decrement ──────────────────────

func _test_section_11_early_bird_unit() -> void:
	var early_bird := _load_ability(48)

	var eb_mon := _make_mon("EarlyBirdMon", [TypeChart.TYPE_NORMAL])
	eb_mon.ability = early_bird
	eb_mon.status = BattlePokemon.STATUS_SLEEP
	eb_mon.sleep_turns = 4
	var result_eb: Dictionary = StatusManager.pre_move_check(eb_mon, false)
	_chk("S11.01 Early Bird decrements sleep_turns by 2 (4 -> 2)", eb_mon.sleep_turns == 2)
	_chk("S11.02 Early Bird: still asleep, can't move this turn", result_eb["can_move"] == false)

	var plain_mon := _make_mon("PlainSleepMon2", [TypeChart.TYPE_NORMAL])
	plain_mon.status = BattlePokemon.STATUS_SLEEP
	plain_mon.sleep_turns = 4
	StatusManager.pre_move_check(plain_mon, false)
	_chk("S11.03 ordinary Pokémon decrements sleep_turns by only 1 (4 -> 3, discriminator)",
			plain_mon.sleep_turns == 3)

	# Clamp: Early Bird never goes negative even from a low counter.
	var eb_mon2 := _make_mon("EarlyBirdMon2", [TypeChart.TYPE_NORMAL])
	eb_mon2.ability = early_bird
	eb_mon2.status = BattlePokemon.STATUS_SLEEP
	eb_mon2.sleep_turns = 1
	StatusManager.pre_move_check(eb_mon2, true)
	_chk("S11.04 Early Bird's decrement clamps at 0, never negative", eb_mon2.sleep_turns == 0)


# ── Section 12: Switch-in status/confusion self-cure ─────────────────────────

func _test_section_12_switch_in_cure_unit() -> void:
	var immunity := _load_ability(17)
	var own_tempo := _load_ability(20)
	var limber := _load_ability(7)
	var opponent := _make_mon("SwitchInCureOpp", [TypeChart.TYPE_NORMAL])

	var im := _make_mon("SwitchInImmunity", [TypeChart.TYPE_NORMAL])
	im.ability = immunity
	im.status = BattlePokemon.STATUS_TOXIC
	im.toxic_counter = 5
	var r1: Dictionary = AbilityManager.try_switch_in(im, opponent)
	_chk("S12.01 Immunity cures pre-existing toxic on switch-in", r1["cured_status"] == true)
	_chk("S12.02 status actually cleared", im.status == BattlePokemon.STATUS_NONE and im.toxic_counter == 0)

	var otm := _make_mon("SwitchInOwnTempo", [TypeChart.TYPE_NORMAL])
	otm.ability = own_tempo
	otm.confusion_turns = 3
	var r2: Dictionary = AbilityManager.try_switch_in(otm, opponent)
	_chk("S12.03 Own Tempo cures pre-existing confusion on switch-in", r2["cured_confusion"] == true)
	_chk("S12.04 confusion actually cleared", otm.confusion_turns == 0)

	var lm := _make_mon("SwitchInLimber", [TypeChart.TYPE_NORMAL])
	lm.ability = limber
	lm.status = BattlePokemon.STATUS_BURN  # mismatched status — Limber only cures paralysis
	var r3: Dictionary = AbilityManager.try_switch_in(lm, opponent)
	_chk("S12.05 Limber does NOT cure a mismatched status (burn, not paralysis)",
			r3["cured_status"] == false and lm.status == BattlePokemon.STATUS_BURN)


# ── Section 13: Intimidate-block — Inner Focus / Own Tempo / Oblivious ───────

func _test_section_13_intimidate_block_full_battle() -> void:
	var tackle := _load_move(33)
	var intimidate := _load_ability(22)
	var inner_focus := _load_ability(39)

	var holder := _make_mon("IntimidateHolder", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	holder.ability = intimidate
	holder.add_move(tackle)
	var blocked_target := _make_mon("InnerFocusBlocker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	blocked_target.ability = inner_focus
	blocked_target.add_move(tackle)

	var stat_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))

	bm.start_battle_with_parties(BattleParty.single(holder), BattleParty.single(blocked_target))

	_chk("S13.01 Inner Focus fully blocks Intimidate's Attack drop",
			not stat_events.any(func(e): return e[0] == blocked_target and e[1] == BattlePokemon.STAGE_ATK))

	bm.queue_free()

	# Ordinary target: Intimidate applies normally (negative control for this section).
	var holder2 := _make_mon("IntimidateHolder2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	holder2.ability = intimidate
	holder2.add_move(tackle)
	var plain_target := _make_mon("PlainIntimidateTarget", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	plain_target.add_move(tackle)

	var stat_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.stat_stage_changed.connect(func(t, si, ac): stat_events2.push_back([t, si, ac]))
	bm2.start_battle_with_parties(BattleParty.single(holder2), BattleParty.single(plain_target))

	_chk("S13.02 ordinary Pokémon: Intimidate lowers Attack normally",
			stat_events2.any(func(e): return e[0] == plain_target and e[1] == BattlePokemon.STAGE_ATK and e[2] == -1))

	bm2.queue_free()


# ── Section 21: [M17.5 Batch Fix] Scrappy also blocks Intimidate's Attack drop ──
#
# Source confirms Scrappy (113) sits in the exact SAME case block as Inner Focus/Own
# Tempo/Oblivious in IsIntimidateBlocked (battle_stat_change.c L667-675) — a plain
# block, not Guard Dog's separate +1-reversal case (L676-691). This tier's own
# original comment flagged Scrappy as "not yet implemented... add it here once it
# exists" — Scrappy WAS implemented five tiers later in [M17n-6], but this specific
# wire-in was never followed up until the M17.5 recon caught it as a live gap.
# No Mold-Breaker/Neutralizing-Gas coverage needed here: like every other Intimidate-
# block check in this section, `opp_blocks_intimidate` is evaluated at switch-in time,
# outside any move-processing window, so Mold Breaker structurally cannot apply —
# matching the SAME established precedent already covering Inner Focus/Own Tempo/
# Oblivious above (never Mold-Breaker-tested either, for the identical reason) and
# Guard Dog/Mirror Armor's own switch-in-only checks elsewhere in this project.
func _test_section_21_scrappy_blocks_intimidate_full_battle() -> void:
	var tackle := _load_move(33)
	var intimidate := _load_ability(22)
	var scrappy := _load_ability(113)

	var holder := _make_mon("IntimidateHolderS21", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	holder.ability = intimidate
	holder.add_move(tackle)
	var blocked_target := _make_mon("ScrappyBlocker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	blocked_target.ability = scrappy
	blocked_target.add_move(tackle)

	var stat_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))

	bm.start_battle_with_parties(BattleParty.single(holder), BattleParty.single(blocked_target))

	_chk("S21.01 Scrappy fully blocks Intimidate's Attack drop",
			not stat_events.any(func(e): return e[0] == blocked_target and e[1] == BattlePokemon.STAGE_ATK))

	bm.queue_free()


# ── Section 22: [M17.5 Batch Fix] Grass-type general powder-move immunity ────
#
# Source: `IsAffectedByPowderMove` (battle_util.c L10545-10552) — Overcoat ability,
# Grass-type, and Safety Goggles (item, not implemented in this project) are three
# INDEPENDENT exemptions. Only Overcoat's half was ever wired into
# `AbilityManager.blocks_move_flag` before this fix; Sleep Powder (move 79,
# powder_move=true, Grass-type, status category) is this project's one roster move
# that actually carries the flag, so it's the vehicle for all these assertions.
func _test_section_22_grass_powder_immunity_full_battle() -> void:
	var sleep_powder := _load_move(79)

	var attacker := _make_mon("PowderAttacker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	attacker.add_move(sleep_powder)
	var grass_target := _make_mon("GrassPowderTarget", [TypeChart.TYPE_GRASS], 100, 60, 60, 60, 60, 30)
	grass_target.add_move(sleep_powder)

	var move_effect_failed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.move_effect_failed.connect(func(t, r): move_effect_failed_events.push_back([t, r]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(grass_target))

	_chk("S22.01 Grass-type target: Sleep Powder blocked entirely (move_flag_blocked)",
			move_effect_failed_events.any(func(e): return e[0] == grass_target and e[1] == "move_flag_blocked"))
	_chk("S22.02 Grass-type target: never put to sleep",
			grass_target.status != BattlePokemon.STATUS_SLEEP)

	bm.queue_free()

	# Direct unit-level discriminators.
	var tackle := _load_move(33)
	var grass_direct := _make_mon("GrassPowderDirect", [TypeChart.TYPE_GRASS])
	_chk("S22.03 Grass-type: DOES block a powder move (direct check)",
			AbilityManager.blocks_move_flag(grass_direct, sleep_powder) == true)
	_chk("S22.04 Grass-type: does NOT block a non-powder move (Tackle)",
			AbilityManager.blocks_move_flag(grass_direct, tackle) == false)

	var normal_direct := _make_mon("NonGrassPowderDirect", [TypeChart.TYPE_NORMAL])
	_chk("S22.05 negative control: a non-Grass, non-Overcoat target is NOT immune to Sleep Powder",
			AbilityManager.blocks_move_flag(normal_direct, sleep_powder) == false)

	# Composition: Overcoat's pre-existing ability-based exemption and this fix's new
	# type-based exemption must both independently grant immunity, with no conflict —
	# a dual-typed Grass/Overcoat-irrelevant case isn't meaningful here (Overcoat is an
	# ability, not a type), so this checks a NON-Grass Overcoat holder still blocks
	# independently of the new Grass check added right next to it.
	var overcoat := _load_ability(142)
	var overcoat_direct := _make_mon("OvercoatPowderDirect", [TypeChart.TYPE_NORMAL])
	overcoat_direct.ability = overcoat
	_chk("S22.06 Overcoat (non-Grass holder) still independently blocks Sleep Powder",
			AbilityManager.blocks_move_flag(overcoat_direct, sleep_powder) == true)


# ── Section 14: Aroma Veil — blocks Disable and Encore ───────────────────────

func _test_section_14_aroma_veil_full_battle() -> void:
	var tackle := _load_move(33)
	var disable := _load_move(50)
	var aroma_veil := _load_ability(165)

	var attacker := _make_mon("AromaVeilAttacker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	attacker.add_move(disable)
	var target := _make_mon("AromaVeilTarget", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	target.ability = aroma_veil
	target.add_move(tackle)
	target.last_move_used = tackle  # Disable needs a last-used move to target

	var move_effect_failed_events := []
	var disabled_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_effect_failed.connect(func(t, r): move_effect_failed_events.push_back([t, r]))
	bm.disabled.connect(func(t, m): disabled_events.push_back([t, m]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(target))

	_chk("S14.01 Aroma Veil blocks Disable (move_effect_failed fired, not applied)",
			move_effect_failed_events.any(func(e): return e[0] == target and e[1] == "aroma_veil_blocked"))
	_chk("S14.02 Disable was never actually applied", disabled_events.is_empty())

	bm.queue_free()


# ── Section 15: Soundproof — blocks sound-flagged moves (Growl, a status move) ──

func _test_section_15_soundproof_full_battle() -> void:
	var growl := _load_move(45)  # sound_move = true, -1 Atk
	var soundproof := _load_ability(43)

	var attacker := _make_mon("SoundproofAttacker", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	attacker.add_move(growl)
	var target := _make_mon("SoundproofTarget", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	target.ability = soundproof
	target.add_move(growl)

	var stat_events := []
	var move_effect_failed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))
	bm.move_effect_failed.connect(func(t, r): move_effect_failed_events.push_back([t, r]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(target))

	_chk("S15.01 Soundproof blocks Growl (a sound-flagged status move) entirely",
			move_effect_failed_events.any(func(e): return e[0] == target and e[1] == "move_flag_blocked"))
	_chk("S15.02 Soundproof holder's Attack was never lowered",
			not stat_events.any(func(e): return e[0] == target and e[1] == BattlePokemon.STAGE_ATK))

	bm.queue_free()

	# Direct unit-level discriminator: Soundproof does NOT block a non-sound move.
	var tackle := _load_move(33)
	var sp_holder := _make_mon("SoundproofDirect", [TypeChart.TYPE_NORMAL])
	sp_holder.ability = soundproof
	_chk("S15.03 Soundproof does NOT block a non-sound move (Tackle)",
			AbilityManager.blocks_move_flag(sp_holder, tackle) == false)
	_chk("S15.04 Soundproof DOES block a sound move (direct check)",
			AbilityManager.blocks_move_flag(sp_holder, growl) == true)


# ── Section 16: Bulletproof — blocks ballistic-flagged moves (Ice Ball) ──────

func _test_section_16_bulletproof_full_battle() -> void:
	var ice_ball := _load_move(301)  # ballistic_move = true (retroactively fixed this tier)
	var bulletproof := _load_ability(171)

	var attacker := _make_mon("BulletproofAttacker", [TypeChart.TYPE_ICE], 100, 80, 60, 60, 60, 60)
	attacker.add_move(ice_ball)
	var target := _make_mon("BulletproofTarget", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	target.ability = bulletproof
	target.add_move(ice_ball)

	var move_executed_events := []
	var move_effect_failed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.move_effect_failed.connect(func(t, r): move_effect_failed_events.push_back([t, r]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(target))

	_chk("S16.01 Bulletproof blocks Ice Ball (a ballistic move) entirely",
			move_effect_failed_events.any(func(e): return e[0] == target and e[1] == "move_flag_blocked"))
	var hit := move_executed_events.filter(func(e): return e[0] == attacker and e[1] == target)
	_chk("S16.02 zero damage dealt (blocked before accuracy/damage calc)",
			not hit.is_empty() and hit[0][3] == 0)

	bm.queue_free()

	var tackle := _load_move(33)
	var bp_holder := _make_mon("BulletproofDirect", [TypeChart.TYPE_NORMAL])
	bp_holder.ability = bulletproof
	_chk("S16.03 Bulletproof does NOT block a non-ballistic move (Tackle)",
			AbilityManager.blocks_move_flag(bp_holder, tackle) == false)


# ── Section 17: Category C — cosmetic no-ops ─────────────────────────────────

func _test_section_17_cosmetic_no_ops() -> void:
	var illuminate := _load_ability(35)
	_chk("S17.01 Illuminate exists in AbilityData with no mechanical function to test",
			illuminate.ability_id == 35 and illuminate.ability_name == "Illuminate")

	var honey_gather := _load_ability(118)
	_chk("S17.02 Honey Gather exists in AbilityData with no mechanical function to test",
			honey_gather.ability_id == 118 and honey_gather.ability_name == "Honey Gather")

	# Sanity: neither produces any status/stat/damage side effect via the shared checks.
	var ill_mon := _make_mon("IlluminateMon", [TypeChart.TYPE_NORMAL])
	ill_mon.ability = illuminate
	_chk("S17.03 Illuminate: no status-immunity side effect",
			StatusManager.try_apply_status(ill_mon, BattlePokemon.STATUS_SLEEP) == true)


# ── Section 18: Mold Breaker bypass — one representative per category ───────

func _test_section_18_mold_breaker_bypass() -> void:
	var mold_breaker := _load_ability(104)
	var insomnia := _load_ability(15)
	var soundproof := _load_ability(43)
	var growl := _load_move(45)

	var mb_attacker := _make_mon("MBAttackerS18", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker

	var im := _make_mon("InsomniaMB", [TypeChart.TYPE_NORMAL])
	im.ability = insomnia
	_chk("S18.01 Mold Breaker bypasses Insomnia's sleep block (Category A)",
			StatusManager.try_apply_status(im, BattlePokemon.STATUS_SLEEP, null, null, false, mb_attacker) == true)

	var sp := _make_mon("SoundproofMB", [TypeChart.TYPE_NORMAL])
	sp.ability = soundproof
	_chk("S18.02 Mold Breaker bypasses Soundproof's move-flag block (Category B)",
			AbilityManager.blocks_move_flag(sp, growl, false, mb_attacker) == false)


# ── Section 19: Neutralizing Gas suppression — one representative per category ──

func _test_section_19_neutralizing_gas_suppression() -> void:
	var insomnia := _load_ability(15)
	var soundproof := _load_ability(43)
	var growl := _load_move(45)

	var im := _make_mon("InsomniaNG", [TypeChart.TYPE_NORMAL])
	im.ability = insomnia
	_chk("S19.01 Neutralizing Gas suppresses Insomnia's sleep block (Category A)",
			StatusManager.try_apply_status(im, BattlePokemon.STATUS_SLEEP, null, null, true) == true)

	var sp := _make_mon("SoundproofNG", [TypeChart.TYPE_NORMAL])
	sp.ability = soundproof
	_chk("S19.02 Neutralizing Gas suppresses Soundproof's move-flag block (Category B)",
			AbilityManager.blocks_move_flag(sp, growl, true) == false)


# ── Section 20: Negative case — ordinary Pokémon unaffected by any of this tier ──

func _test_section_20_negative_case() -> void:
	var plain := _make_mon("NegativeControlMon", [TypeChart.TYPE_NORMAL])
	_chk("S20.01 ordinary Pokémon: sleep applies", StatusManager.try_apply_status(plain, BattlePokemon.STATUS_SLEEP) == true)

	var plain2 := _make_mon("NegativeControlMon2", [TypeChart.TYPE_NORMAL])
	_chk("S20.02 ordinary Pokémon: confusion applies", StatusManager.try_apply_confusion(plain2) == true)

	var tackle := _load_move(33)
	var plain3 := _make_mon("NegativeControlMon3", [TypeChart.TYPE_NORMAL])
	_chk("S20.03 ordinary Pokémon: no move-flag block on an ordinary move",
			AbilityManager.blocks_move_flag(plain3, tackle) == false)
