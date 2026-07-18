extends Node

# M18e test suite — Crit-stage item bonus (Scope Lens, Razor Claw)
#
# Ground truth: pokeemerald-expansion
#   src/battle_util.c :: GetHoldEffectCritChanceIncrease (L7795-7810) — HOLD_EFFECT_SCOPE_LENS
#     grants +1 crit stage, unconditional (no move-category check).
#   src/data/items.h — Scope Lens(471, L9921) AND Razor Claw(492, L10436) both set
#     `.holdEffect = HOLD_EFFECT_SCOPE_LENS` — the literal SAME enum value, not two
#     separate constants. Confirmed during Step 0: this project's classic "Razor
#     Claw = physical crit only" assumption does not hold in this expanded engine.
#   src/battle_util.c :: CalcCritChanceStage (L7839-7842) — item_bonus sums into the
#     SAME total as focus_energy's +2, dragonCheer, move.critical_hit_stage, and
#     ABILITY_SUPER_LUCK's +1, all combined before the 0-3 clamp.
#
# Docs: docs/m18_subtier_plan.md (M18e section) — 2 items, one shared mechanism.
#
# TESTING-APPROACH CORRECTION (found during implementation, not assumed at Step 0):
# force_crit (DamageCalculator.calculate's parameter) does NOT isolate the crit-STAGE
# math — when force_crit != null, `_roll_crit` is never even called; is_crit is set
# directly from force_crit's bool value, bypassing move.critical_hit_stage, focus_energy,
# ability_bonus, AND item_bonus entirely. [M17n-5]'s Section 12 already discovered
# this for Super Luck and used a statistical crit-RATE sample instead, since no
# deterministic seam into the roll exists. This tier applies the SAME statistical
# pattern for its one true pipeline-integration test (item + Super Luck composing),
# but for the two per-item tests below, a more precise and fully deterministic option
# exists that Section 12 didn't have available: ItemManager.crit_stage_bonus() is a
# pure function with no RNG in it at all — calling it directly proves the stage-bonus
# VALUE with zero flakiness, which is a strictly better isolation of "the stage math"
# than a forced boolean outcome would have been anyway.
#
# Sections: E01 Scope Lens, E02 Razor Claw (each: data + direct crit_stage_bonus
# check + discriminator), E03 composition (item_bonus + Super Luck's ability_bonus
# sum correctly within the real DamageCalculator.calculate pipeline, statistical).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_e01_scope_lens()
	_test_e02_razor_claw()
	_test_e03_composition_with_super_luck()

	var total := _pass + _fail
	print("m18e_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18a_test.gd's established pattern) ──────────────────────

func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		base_hp: int = 100, base_atk: int = 80, base_def: int = 80,
		base_spatk: int = 80, base_spdef: int = 80, base_spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


# ── E01: Scope Lens (471) ──────────────────────────────────────────────────────
func _test_e01_scope_lens() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_SCOPE_LENS)
	_chk("E01.01 Scope Lens hold_effect == HOLD_EFFECT_SCOPE_LENS(40)",
			item.hold_effect == ItemManager.HOLD_EFFECT_SCOPE_LENS)

	var holder := _make_mon("E01_Holder", TypeChart.TYPE_MYSTERY)
	holder.held_item = item
	_chk("E01.02 crit_stage_bonus == 1 when holding Scope Lens",
			ItemManager.crit_stage_bonus(holder) == 1)

	var bare := _make_mon("E01_Bare", TypeChart.TYPE_MYSTERY)
	bare.held_item = null
	_chk("E01.03 crit_stage_bonus == 0 when holding nothing (discriminator)",
			ItemManager.crit_stage_bonus(bare) == 0)


# ── E02: Razor Claw (492) ──────────────────────────────────────────────────────
func _test_e02_razor_claw() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_SCOPE_LENS)
	_chk("E02.01 Razor Claw hold_effect == HOLD_EFFECT_SCOPE_LENS(40) " +
			"(same constant as Scope Lens, confirmed via source, not a data-entry error)",
			item.hold_effect == ItemManager.HOLD_EFFECT_SCOPE_LENS)

	var holder := _make_mon("E02_Holder", TypeChart.TYPE_MYSTERY)
	holder.held_item = item
	_chk("E02.02 crit_stage_bonus == 1 when holding Razor Claw",
			ItemManager.crit_stage_bonus(holder) == 1)

	var bare := _make_mon("E02_Bare", TypeChart.TYPE_MYSTERY)
	bare.held_item = null
	_chk("E02.03 crit_stage_bonus == 0 when holding nothing (discriminator)",
			ItemManager.crit_stage_bonus(bare) == 0)


# ── E03: composition with Super Luck (ability, [M17n-5]) — statistical ─────────
# CRIT_ODDS_GEN7 = {24, 8, 2, 1} indexed by stage. Expected rates:
#   stage 0 (neither):            1/24 ≈ 4.17%
#   stage 1 (item OR ability alone): 1/8 = 12.5%
#   stage 2 (item AND ability, SUMMED): 1/2 = 50%
# Wide margins (many standard deviations at n=5000) to avoid flakiness, matching
# [M17n-5] Section 12's established precedent exactly.
func _test_e03_composition_with_super_luck() -> void:
	var super_luck := _load_ability(105)
	var tackle := _load_move(33)
	var item := _make_item(ItemManager.HOLD_EFFECT_SCOPE_LENS)

	var plain := _make_mon("E03_Plain", TypeChart.TYPE_NORMAL)
	var item_only := _make_mon("E03_ItemOnly", TypeChart.TYPE_NORMAL)
	item_only.held_item = item
	var both := _make_mon("E03_Both", TypeChart.TYPE_NORMAL)
	both.held_item = item
	both.ability = super_luck
	var target := _make_mon("E03_Target", TypeChart.TYPE_NORMAL)

	var n := 5000
	var plain_crits := 0
	var item_crits := 0
	var both_crits := 0
	for _i in range(n):
		var r_plain: Dictionary = DamageCalculator.calculate(plain, target, tackle, 100, null)
		if r_plain["is_crit"]:
			plain_crits += 1
		var r_item: Dictionary = DamageCalculator.calculate(item_only, target, tackle, 100, null)
		if r_item["is_crit"]:
			item_crits += 1
		var r_both: Dictionary = DamageCalculator.calculate(both, target, tackle, 100, null)
		if r_both["is_crit"]:
			both_crits += 1

	var plain_rate: float = float(plain_crits) / n
	var item_rate: float = float(item_crits) / n
	var both_rate: float = float(both_crits) / n

	_chk("E03.01 no item/ability: observed crit rate near expected 1/24 " +
			"(well under 7%%, n=%d, observed=%.3f)" % [n, plain_rate],
			plain_rate < 0.07)
	_chk("E03.02 item alone: observed crit rate near expected 1/8 " +
			"(between 9%% and 16%%, n=%d, observed=%.3f)" % [n, item_rate],
			item_rate > 0.09 and item_rate < 0.16)
	_chk("E03.03 item + Super Luck SUMMED: observed crit rate near expected 1/2, " +
			"NOT stuck at 1/8 (between 40%% and 60%%, n=%d, observed=%.3f)" % [n, both_rate],
			both_rate > 0.40 and both_rate < 0.60)
