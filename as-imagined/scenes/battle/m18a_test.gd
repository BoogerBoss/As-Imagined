extends Node

# M18a test suite — Type-boost held items (base-power modifier)
#
# Ground truth: pokeemerald-expansion (I_TYPE_BOOST_POWER = GEN_LATEST)
#   src/battle_util.c :: CalcMoveBasePowerAfterModifiers (L6659-6661) —
#     HOLD_EFFECT_TYPE_POWER / HOLD_EFFECT_PLATE share one case: matching-type
#     move power ×1.2 (holdEffectParam=20 for every one of these 40 items,
#     confirmed via direct read of src/data/items.h).
#   src/data/items.h — .secondaryId holds each item's associated type; this
#     project reuses ItemData.hold_effect_param for the type instead (the same
#     deviation [M17n-4] established for HOLD_EFFECT_PLATE's Multitype read).
#
# Docs: docs/m18_subtier_plan.md (M18a section) — 40 items, one shared mechanism.
#
# Canonical damage-math setup, identical across all 40 items (verified by hand,
# cross-checked against item_test.gd's I8 Occa Berry worked example):
#   Attacker: TYPE_MYSTERY (no STAB possible against any of the 18 real types),
#     base_sp_attack=80 (default) → sp_attack = base+5 = 85 at level 50, iv=ev=0.
#   Defender: TYPE_MYSTERY (TABLE[atk_type][TYPE_MYSTERY] = 1.0 for every atk_type —
#     confirmed by direct read of type_chart.gd's TABLE column 10 — guarantees
#     neutral effectiveness regardless of which of the 18 move types is under test),
#     base_sp_defense=70 → sp_defense = 75.
#   Move: power=40, category=1 (special; category is irrelevant to this mechanism).
#   force_roll=100, force_crit=false (pairwise-comparison RNG-forcing convention).
#
#   Baseline (no item):  dmg = 40*85*22/75/50+2 = 21 (no STAB, no type-eff change).
#   Boosted (item held): effective_power = uq412_half_down(40, 4915) = 48
#                        dmg = 48*85*22/75/50+2 = 25.
#   These two numbers (21 baseline / 25 boosted) are identical for all 40 items,
#   since power/atk/def/level and the ×1.2 multiplier are uniform across the family.
#
# Sections: A01-A16 Charcoal family, A17 Silk Scarf, A18 Fairy Feather,
#   A19-A23 Incenses, A24-A40 Plates. Deliberate deviation from this project's
#   "negative case per ability" convention (that convention was written for
#   abilities; this uniform, cheap item family only needs ONE representative
#   "holds nothing" negative case, covered by A01's own baseline step, rather
#   than repeating it identically 40 times) — each of the 40 tests still gets its
#   own matching-type boost check AND its own non-matching-type discriminator.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_a01_charcoal()
	_test_a02_mystic_water()
	_test_a03_magnet()
	_test_a04_miracle_seed()
	_test_a05_never_melt_ice()
	_test_a06_black_belt()
	_test_a07_poison_barb()
	_test_a08_soft_sand()
	_test_a09_sharp_beak()
	_test_a10_twisted_spoon()
	_test_a11_silver_powder()
	_test_a12_hard_stone()
	_test_a13_spell_tag()
	_test_a14_dragon_fang()
	_test_a15_black_glasses()
	_test_a16_metal_coat()
	_test_a17_silk_scarf()
	_test_a18_fairy_feather()
	_test_a19_sea_incense()
	_test_a20_odd_incense()
	_test_a21_rock_incense()
	_test_a22_rose_incense()
	_test_a23_wave_incense()
	_test_a24_flame_plate()
	_test_a25_splash_plate()
	_test_a26_zap_plate()
	_test_a27_meadow_plate()
	_test_a28_icicle_plate()
	_test_a29_fist_plate()
	_test_a30_toxic_plate()
	_test_a31_earth_plate()
	_test_a32_sky_plate()
	_test_a33_mind_plate()
	_test_a34_insect_plate()
	_test_a35_stone_plate()
	_test_a36_spooky_plate()
	_test_a37_draco_plate()
	_test_a38_dread_plate()
	_test_a39_iron_plate()
	_test_a40_pixie_plate()

	var total := _pass + _fail
	print("m18a_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors item_test.gd's established pattern) ──────────────────────

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


func _make_move(move_name: String, move_type: int, category: int, power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name        = move_name
	m.type             = move_type
	m.category         = category
	m.power            = power
	m.accuracy         = 100
	m.pp               = 40
	m.secondary_effect = MoveData.SE_NONE
	m.secondary_chance = 0
	m.two_turn         = false
	m.semi_inv_state   = MoveData.SEMI_INV_NONE
	m.stat_change_stat = -1
	return m


# ── A01: Charcoal (HOLD_EFFECT_TYPE_POWER, TYPE_FIRE) ─────────────────────────
func _test_a01_charcoal() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_FIRE)
	_chk("A01.01 Charcoal hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_FIRE)

	var attacker := _make_mon("A01_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A01_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A01_Matching", TypeChart.TYPE_FIRE, 1, 40)
	var offtype_move := _make_move("A01_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A01.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A01.03 Charcoal boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A01.04 Charcoal does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A02: Mystic Water (HOLD_EFFECT_TYPE_POWER, TYPE_WATER) ────────────────────
func _test_a02_mystic_water() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_WATER)
	_chk("A02.01 Mystic Water hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_WATER)

	var attacker := _make_mon("A02_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A02_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A02_Matching", TypeChart.TYPE_WATER, 1, 40)
	var offtype_move := _make_move("A02_OffType", TypeChart.TYPE_NORMAL, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A02.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A02.03 Mystic Water boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A02.04 Mystic Water does NOT boost a Normal move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A03: Magnet (HOLD_EFFECT_TYPE_POWER, TYPE_ELECTRIC) ───────────────────────
func _test_a03_magnet() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_ELECTRIC)
	_chk("A03.01 Magnet hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_ELECTRIC)

	var attacker := _make_mon("A03_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A03_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A03_Matching", TypeChart.TYPE_ELECTRIC, 1, 40)
	var offtype_move := _make_move("A03_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A03.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A03.03 Magnet boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A03.04 Magnet does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A04: Miracle Seed (HOLD_EFFECT_TYPE_POWER, TYPE_GRASS) ────────────────────
func _test_a04_miracle_seed() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_GRASS)
	_chk("A04.01 Miracle Seed hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_GRASS)

	var attacker := _make_mon("A04_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A04_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A04_Matching", TypeChart.TYPE_GRASS, 1, 40)
	var offtype_move := _make_move("A04_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A04.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A04.03 Miracle Seed boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A04.04 Miracle Seed does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A05: Never-Melt Ice (HOLD_EFFECT_TYPE_POWER, TYPE_ICE) ────────────────────
func _test_a05_never_melt_ice() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_ICE)
	_chk("A05.01 Never-Melt Ice hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_ICE)

	var attacker := _make_mon("A05_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A05_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A05_Matching", TypeChart.TYPE_ICE, 1, 40)
	var offtype_move := _make_move("A05_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A05.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A05.03 Never-Melt Ice boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A05.04 Never-Melt Ice does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A06: Black Belt (HOLD_EFFECT_TYPE_POWER, TYPE_FIGHTING) ───────────────────
func _test_a06_black_belt() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_FIGHTING)
	_chk("A06.01 Black Belt hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_FIGHTING)

	var attacker := _make_mon("A06_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A06_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A06_Matching", TypeChart.TYPE_FIGHTING, 1, 40)
	var offtype_move := _make_move("A06_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A06.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A06.03 Black Belt boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A06.04 Black Belt does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A07: Poison Barb (HOLD_EFFECT_TYPE_POWER, TYPE_POISON) ────────────────────
func _test_a07_poison_barb() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_POISON)
	_chk("A07.01 Poison Barb hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_POISON)

	var attacker := _make_mon("A07_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A07_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A07_Matching", TypeChart.TYPE_POISON, 1, 40)
	var offtype_move := _make_move("A07_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A07.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A07.03 Poison Barb boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A07.04 Poison Barb does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A08: Soft Sand (HOLD_EFFECT_TYPE_POWER, TYPE_GROUND) ──────────────────────
func _test_a08_soft_sand() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_GROUND)
	_chk("A08.01 Soft Sand hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_GROUND)

	var attacker := _make_mon("A08_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A08_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A08_Matching", TypeChart.TYPE_GROUND, 1, 40)
	var offtype_move := _make_move("A08_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A08.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A08.03 Soft Sand boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A08.04 Soft Sand does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A09: Sharp Beak (HOLD_EFFECT_TYPE_POWER, TYPE_FLYING) ─────────────────────
func _test_a09_sharp_beak() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_FLYING)
	_chk("A09.01 Sharp Beak hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_FLYING)

	var attacker := _make_mon("A09_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A09_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A09_Matching", TypeChart.TYPE_FLYING, 1, 40)
	var offtype_move := _make_move("A09_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A09.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A09.03 Sharp Beak boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A09.04 Sharp Beak does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A10: Twisted Spoon (HOLD_EFFECT_TYPE_POWER, TYPE_PSYCHIC) ─────────────────
func _test_a10_twisted_spoon() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_PSYCHIC)
	_chk("A10.01 Twisted Spoon hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_PSYCHIC)

	var attacker := _make_mon("A10_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A10_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A10_Matching", TypeChart.TYPE_PSYCHIC, 1, 40)
	var offtype_move := _make_move("A10_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A10.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A10.03 Twisted Spoon boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A10.04 Twisted Spoon does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A11: Silver Powder (HOLD_EFFECT_TYPE_POWER, TYPE_BUG) ─────────────────────
func _test_a11_silver_powder() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_BUG)
	_chk("A11.01 Silver Powder hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_BUG)

	var attacker := _make_mon("A11_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A11_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A11_Matching", TypeChart.TYPE_BUG, 1, 40)
	var offtype_move := _make_move("A11_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A11.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A11.03 Silver Powder boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A11.04 Silver Powder does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A12: Hard Stone (HOLD_EFFECT_TYPE_POWER, TYPE_ROCK) ───────────────────────
func _test_a12_hard_stone() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_ROCK)
	_chk("A12.01 Hard Stone hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_ROCK)

	var attacker := _make_mon("A12_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A12_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A12_Matching", TypeChart.TYPE_ROCK, 1, 40)
	var offtype_move := _make_move("A12_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A12.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A12.03 Hard Stone boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A12.04 Hard Stone does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A13: Spell Tag (HOLD_EFFECT_TYPE_POWER, TYPE_GHOST) ───────────────────────
func _test_a13_spell_tag() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_GHOST)
	_chk("A13.01 Spell Tag hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_GHOST)

	var attacker := _make_mon("A13_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A13_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A13_Matching", TypeChart.TYPE_GHOST, 1, 40)
	var offtype_move := _make_move("A13_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A13.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A13.03 Spell Tag boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A13.04 Spell Tag does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A14: Dragon Fang (HOLD_EFFECT_TYPE_POWER, TYPE_DRAGON) ────────────────────
func _test_a14_dragon_fang() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_DRAGON)
	_chk("A14.01 Dragon Fang hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_DRAGON)

	var attacker := _make_mon("A14_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A14_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A14_Matching", TypeChart.TYPE_DRAGON, 1, 40)
	var offtype_move := _make_move("A14_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A14.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A14.03 Dragon Fang boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A14.04 Dragon Fang does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A15: Black Glasses (HOLD_EFFECT_TYPE_POWER, TYPE_DARK) ────────────────────
func _test_a15_black_glasses() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_DARK)
	_chk("A15.01 Black Glasses hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_DARK)

	var attacker := _make_mon("A15_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A15_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A15_Matching", TypeChart.TYPE_DARK, 1, 40)
	var offtype_move := _make_move("A15_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A15.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A15.03 Black Glasses boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A15.04 Black Glasses does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A16: Metal Coat (HOLD_EFFECT_TYPE_POWER, TYPE_STEEL) ──────────────────────
func _test_a16_metal_coat() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_STEEL)
	_chk("A16.01 Metal Coat hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_STEEL)

	var attacker := _make_mon("A16_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A16_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A16_Matching", TypeChart.TYPE_STEEL, 1, 40)
	var offtype_move := _make_move("A16_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A16.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A16.03 Metal Coat boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A16.04 Metal Coat does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A17: Silk Scarf (HOLD_EFFECT_TYPE_POWER, TYPE_NORMAL) ─────────────────────
func _test_a17_silk_scarf() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_NORMAL)
	_chk("A17.01 Silk Scarf hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_NORMAL)

	var attacker := _make_mon("A17_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A17_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A17_Matching", TypeChart.TYPE_NORMAL, 1, 40)
	var offtype_move := _make_move("A17_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A17.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A17.03 Silk Scarf boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A17.04 Silk Scarf does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A18: Fairy Feather (HOLD_EFFECT_TYPE_POWER, TYPE_FAIRY) ───────────────────
func _test_a18_fairy_feather() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_FAIRY)
	_chk("A18.01 Fairy Feather hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_FAIRY)

	var attacker := _make_mon("A18_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A18_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A18_Matching", TypeChart.TYPE_FAIRY, 1, 40)
	var offtype_move := _make_move("A18_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A18.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A18.03 Fairy Feather boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A18.04 Fairy Feather does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A19: Sea Incense (HOLD_EFFECT_TYPE_POWER, TYPE_WATER) ─────────────────────
func _test_a19_sea_incense() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_WATER)
	_chk("A19.01 Sea Incense hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_WATER)

	var attacker := _make_mon("A19_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A19_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A19_Matching", TypeChart.TYPE_WATER, 1, 40)
	var offtype_move := _make_move("A19_OffType", TypeChart.TYPE_NORMAL, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A19.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A19.03 Sea Incense boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A19.04 Sea Incense does NOT boost a Normal move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A20: Odd Incense (HOLD_EFFECT_TYPE_POWER, TYPE_PSYCHIC) ───────────────────
func _test_a20_odd_incense() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_PSYCHIC)
	_chk("A20.01 Odd Incense hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_PSYCHIC)

	var attacker := _make_mon("A20_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A20_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A20_Matching", TypeChart.TYPE_PSYCHIC, 1, 40)
	var offtype_move := _make_move("A20_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A20.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A20.03 Odd Incense boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A20.04 Odd Incense does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A21: Rock Incense (HOLD_EFFECT_TYPE_POWER, TYPE_ROCK) ─────────────────────
func _test_a21_rock_incense() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_ROCK)
	_chk("A21.01 Rock Incense hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_ROCK)

	var attacker := _make_mon("A21_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A21_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A21_Matching", TypeChart.TYPE_ROCK, 1, 40)
	var offtype_move := _make_move("A21_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A21.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A21.03 Rock Incense boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A21.04 Rock Incense does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A22: Rose Incense (HOLD_EFFECT_TYPE_POWER, TYPE_GRASS) ────────────────────
func _test_a22_rose_incense() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_GRASS)
	_chk("A22.01 Rose Incense hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_GRASS)

	var attacker := _make_mon("A22_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A22_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A22_Matching", TypeChart.TYPE_GRASS, 1, 40)
	var offtype_move := _make_move("A22_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A22.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A22.03 Rose Incense boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A22.04 Rose Incense does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A23: Wave Incense (HOLD_EFFECT_TYPE_POWER, TYPE_WATER) ────────────────────
func _test_a23_wave_incense() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TYPE_POWER, TypeChart.TYPE_WATER)
	_chk("A23.01 Wave Incense hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_TYPE_POWER and item.hold_effect_param == TypeChart.TYPE_WATER)

	var attacker := _make_mon("A23_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A23_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A23_Matching", TypeChart.TYPE_WATER, 1, 40)
	var offtype_move := _make_move("A23_OffType", TypeChart.TYPE_NORMAL, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A23.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A23.03 Wave Incense boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A23.04 Wave Incense does NOT boost a Normal move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A24: Flame Plate (HOLD_EFFECT_PLATE, TYPE_FIRE) ───────────────────────────
func _test_a24_flame_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_FIRE)
	_chk("A24.01 Flame Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_FIRE)

	var attacker := _make_mon("A24_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A24_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A24_Matching", TypeChart.TYPE_FIRE, 1, 40)
	var offtype_move := _make_move("A24_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A24.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A24.03 Flame Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A24.04 Flame Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A25: Splash Plate (HOLD_EFFECT_PLATE, TYPE_WATER) ─────────────────────────
func _test_a25_splash_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_WATER)
	_chk("A25.01 Splash Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_WATER)

	var attacker := _make_mon("A25_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A25_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A25_Matching", TypeChart.TYPE_WATER, 1, 40)
	var offtype_move := _make_move("A25_OffType", TypeChart.TYPE_NORMAL, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A25.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A25.03 Splash Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A25.04 Splash Plate does NOT boost a Normal move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A26: Zap Plate (HOLD_EFFECT_PLATE, TYPE_ELECTRIC) ─────────────────────────
func _test_a26_zap_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_ELECTRIC)
	_chk("A26.01 Zap Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_ELECTRIC)

	var attacker := _make_mon("A26_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A26_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A26_Matching", TypeChart.TYPE_ELECTRIC, 1, 40)
	var offtype_move := _make_move("A26_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A26.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A26.03 Zap Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A26.04 Zap Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A27: Meadow Plate (HOLD_EFFECT_PLATE, TYPE_GRASS) ─────────────────────────
func _test_a27_meadow_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_GRASS)
	_chk("A27.01 Meadow Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_GRASS)

	var attacker := _make_mon("A27_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A27_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A27_Matching", TypeChart.TYPE_GRASS, 1, 40)
	var offtype_move := _make_move("A27_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A27.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A27.03 Meadow Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A27.04 Meadow Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A28: Icicle Plate (HOLD_EFFECT_PLATE, TYPE_ICE) ───────────────────────────
func _test_a28_icicle_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_ICE)
	_chk("A28.01 Icicle Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_ICE)

	var attacker := _make_mon("A28_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A28_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A28_Matching", TypeChart.TYPE_ICE, 1, 40)
	var offtype_move := _make_move("A28_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A28.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A28.03 Icicle Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A28.04 Icicle Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A29: Fist Plate (HOLD_EFFECT_PLATE, TYPE_FIGHTING) ────────────────────────
func _test_a29_fist_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_FIGHTING)
	_chk("A29.01 Fist Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_FIGHTING)

	var attacker := _make_mon("A29_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A29_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A29_Matching", TypeChart.TYPE_FIGHTING, 1, 40)
	var offtype_move := _make_move("A29_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A29.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A29.03 Fist Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A29.04 Fist Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A30: Toxic Plate (HOLD_EFFECT_PLATE, TYPE_POISON) ─────────────────────────
func _test_a30_toxic_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_POISON)
	_chk("A30.01 Toxic Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_POISON)

	var attacker := _make_mon("A30_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A30_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A30_Matching", TypeChart.TYPE_POISON, 1, 40)
	var offtype_move := _make_move("A30_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A30.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A30.03 Toxic Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A30.04 Toxic Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A31: Earth Plate (HOLD_EFFECT_PLATE, TYPE_GROUND) ─────────────────────────
func _test_a31_earth_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_GROUND)
	_chk("A31.01 Earth Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_GROUND)

	var attacker := _make_mon("A31_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A31_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A31_Matching", TypeChart.TYPE_GROUND, 1, 40)
	var offtype_move := _make_move("A31_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A31.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A31.03 Earth Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A31.04 Earth Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A32: Sky Plate (HOLD_EFFECT_PLATE, TYPE_FLYING) ───────────────────────────
func _test_a32_sky_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_FLYING)
	_chk("A32.01 Sky Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_FLYING)

	var attacker := _make_mon("A32_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A32_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A32_Matching", TypeChart.TYPE_FLYING, 1, 40)
	var offtype_move := _make_move("A32_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A32.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A32.03 Sky Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A32.04 Sky Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A33: Mind Plate (HOLD_EFFECT_PLATE, TYPE_PSYCHIC) ─────────────────────────
func _test_a33_mind_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_PSYCHIC)
	_chk("A33.01 Mind Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_PSYCHIC)

	var attacker := _make_mon("A33_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A33_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A33_Matching", TypeChart.TYPE_PSYCHIC, 1, 40)
	var offtype_move := _make_move("A33_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A33.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A33.03 Mind Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A33.04 Mind Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A34: Insect Plate (HOLD_EFFECT_PLATE, TYPE_BUG) ───────────────────────────
func _test_a34_insect_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_BUG)
	_chk("A34.01 Insect Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_BUG)

	var attacker := _make_mon("A34_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A34_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A34_Matching", TypeChart.TYPE_BUG, 1, 40)
	var offtype_move := _make_move("A34_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A34.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A34.03 Insect Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A34.04 Insect Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A35: Stone Plate (HOLD_EFFECT_PLATE, TYPE_ROCK) ───────────────────────────
func _test_a35_stone_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_ROCK)
	_chk("A35.01 Stone Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_ROCK)

	var attacker := _make_mon("A35_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A35_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A35_Matching", TypeChart.TYPE_ROCK, 1, 40)
	var offtype_move := _make_move("A35_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A35.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A35.03 Stone Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A35.04 Stone Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A36: Spooky Plate (HOLD_EFFECT_PLATE, TYPE_GHOST) ─────────────────────────
func _test_a36_spooky_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_GHOST)
	_chk("A36.01 Spooky Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_GHOST)

	var attacker := _make_mon("A36_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A36_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A36_Matching", TypeChart.TYPE_GHOST, 1, 40)
	var offtype_move := _make_move("A36_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A36.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A36.03 Spooky Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A36.04 Spooky Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A37: Draco Plate (HOLD_EFFECT_PLATE, TYPE_DRAGON) ─────────────────────────
func _test_a37_draco_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_DRAGON)
	_chk("A37.01 Draco Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_DRAGON)

	var attacker := _make_mon("A37_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A37_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A37_Matching", TypeChart.TYPE_DRAGON, 1, 40)
	var offtype_move := _make_move("A37_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A37.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A37.03 Draco Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A37.04 Draco Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A38: Dread Plate (HOLD_EFFECT_PLATE, TYPE_DARK) ───────────────────────────
func _test_a38_dread_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_DARK)
	_chk("A38.01 Dread Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_DARK)

	var attacker := _make_mon("A38_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A38_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A38_Matching", TypeChart.TYPE_DARK, 1, 40)
	var offtype_move := _make_move("A38_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A38.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A38.03 Dread Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A38.04 Dread Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A39: Iron Plate (HOLD_EFFECT_PLATE, TYPE_STEEL) ───────────────────────────
func _test_a39_iron_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_STEEL)
	_chk("A39.01 Iron Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_STEEL)

	var attacker := _make_mon("A39_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A39_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A39_Matching", TypeChart.TYPE_STEEL, 1, 40)
	var offtype_move := _make_move("A39_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A39.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A39.03 Iron Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A39.04 Iron Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)


# ── A40: Pixie Plate (HOLD_EFFECT_PLATE, TYPE_FAIRY) ──────────────────────────
func _test_a40_pixie_plate() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_PLATE, TypeChart.TYPE_FAIRY)
	_chk("A40.01 Pixie Plate hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_PLATE and item.hold_effect_param == TypeChart.TYPE_FAIRY)

	var attacker := _make_mon("A40_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("A40_Def", TypeChart.TYPE_MYSTERY, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var matching_move := _make_move("A40_Matching", TypeChart.TYPE_FAIRY, 1, 40)
	var offtype_move := _make_move("A40_OffType", TypeChart.TYPE_WATER, 1, 40)

	attacker.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A40.02 No item, matching-type move -> damage=21 (baseline)",
			res_base["damage"] == 21)

	attacker.held_item = item
	var res_boost := DamageCalculator.calculate(attacker, defender, matching_move, 100, false)
	_chk("A40.03 Pixie Plate boosts matching-type move -> damage=25 (x1.2, UQ4.12=4915)",
			res_boost["damage"] == 25)

	var res_offtype := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("A40.04 Pixie Plate does NOT boost a Water move -> damage=21 (unaffected)",
			res_offtype["damage"] == 21)

