extends Node

# M18b test suite — Berry/misc items on existing (now-extended) exact dispatches
#
# Ground truth: pokeemerald-expansion (GEN_LATEST config)
#   src/battle_util.c :: GetDefenderItemsModifier (L7510) — resist berries, unchanged
#     mechanism from M12/[M17c], applied AFTER type effectiveness (source order).
#   src/battle_hold_effects.c :: TryCureParalysis/TryCurePoison/TryCureBurn/
#     TryCureFreezeOrFrostbite/TryCureSleep/TryCureConfusion (L665-761) — the 6 new
#     M18b status/confusion-cure berries, each its own HOLD_EFFECT_CURE_* constant.
#   src/battle_hold_effects.c :: ItemHealHp (L826-849) — Oran Berry, same <=50%-max-HP
#     threshold as Sitrus Berry, flat (not percent) heal amount.
#
# Docs: docs/m18_subtier_plan.md (M18b section), docs/decisions.md's [M18b] entry for
# the corrections found during this tier's own Step 0 (cure berries needed their own
# HOLD_EFFECT_CURE_* constants, not a bare reuse of Lum Berry's HOLD_EFFECT_CURE_STATUS;
# Oran needed its own HOLD_EFFECT_RESTORE_HP, not Sitrus's HOLD_EFFECT_RESTORE_PCT_HP).
#
# Canonical resist-berry damage-math setup, identical across all 16 (verified by hand,
# cross-checked against item_test.gd's I8 Occa Berry worked example for the exact
# post-type-effectiveness modifier-composition order):
#   Attacker: TYPE_MYSTERY (no STAB possible), base_sp_attack=80(default) -> sp_attack=85.
#   Defender: a single type genuinely 2.0x WEAK to the berry's resisted type (confirmed
#     per-item against type_chart.gd's TABLE directly, not assumed from memory),
#     base_sp_defense=70 -> sp_defense=75.
#   Move: power=40, category=1 (special). force_roll=100, force_crit=false.
#   Base (pre-type-eff): 40*85*22/75/50+2 = 21 (identical to M18a's own baseline).
#   SE, no berry:  uq412_half_down(21, 8192{2.0x}) = 42.
#   SE, with berry (x0.5 post-type-eff): uq412_half_down(42, 2048{0.5x}) = 21.
#   These two numbers (42 no-berry / 21 with-berry) are identical for all 16 resist
#   berries, since power/atk/def/level and the halving are uniform across the family.
#
# Cure-berry / Oran tests call ItemManager's dispatch functions directly (unit-style),
# matching item_test.gd's own I6/I7 precedent for Sitrus/Lum, rather than full-battle
# integration — these are pure state-in/bool-or-int-out functions with no damage math.
#
# Sections: B01-B16 resist berries, B17-B22 status/confusion-cure berries, B23 Oran
# Berry. Deliberate deviation from "negative case per item," matching M18a's own
# precedent for this uniform item-family shape: only B01 (Passho) carries an extra
# "holds nothing behaves normally" check; every one of the 23 tests still gets its own
# full positive-and-discriminator pair.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_b01_passho_berry()
	_test_b02_wacan_berry()
	_test_b03_rindo_berry()
	_test_b04_yache_berry()
	_test_b05_chople_berry()
	_test_b06_kebia_berry()
	_test_b07_shuca_berry()
	_test_b08_coba_berry()
	_test_b09_payapa_berry()
	_test_b10_tanga_berry()
	_test_b11_charti_berry()
	_test_b12_kasib_berry()
	_test_b13_haban_berry()
	_test_b14_colbur_berry()
	_test_b15_babiri_berry()
	_test_b16_roseli_berry()
	_test_b17_cheri_berry()
	_test_b18_chesto_berry()
	_test_b19_rawst_berry()
	_test_b20_aspear_berry()
	_test_b21_pecha_berry()
	_test_b22_persim_berry()
	_test_b23_oran_berry()

	var total := _pass + _fail
	print("m18b_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors item_test.gd/m18a_test.gd's established pattern) ─────────

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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [M18.5h-1/2] pinned neutral nature + zero IVs -- exact-value assertions predate both


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


func _test_b01_passho_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_WATER)
	_chk("B01.01 Passho Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_WATER)

	var attacker := _make_mon("B01_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B01_Def", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B01_SE", TypeChart.TYPE_WATER, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B01.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B01.03 Passho Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B01.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B01_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B01.05 Passho Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])

	# Representative "holds nothing behaves normally" negative case (not repeated
	# per item, matching M18a's precedent for this uniform item-family shape).
	var plain_defender := _make_mon("B01_Plain", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	plain_defender.held_item = null
	var res_plain := DamageCalculator.calculate(attacker, plain_defender, se_move, 100, false)
	_chk("B01.06 An ordinary Pokemon holding nothing takes normal super-effective damage=42",
			res_plain["damage"] == 42)


func _test_b02_wacan_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_ELECTRIC)
	_chk("B02.01 Wacan Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_ELECTRIC)

	var attacker := _make_mon("B02_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B02_Def", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B02_SE", TypeChart.TYPE_ELECTRIC, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B02.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B02.03 Wacan Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B02.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B02_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B02.05 Wacan Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b03_rindo_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_GRASS)
	_chk("B03.01 Rindo Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_GRASS)

	var attacker := _make_mon("B03_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B03_Def", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B03_SE", TypeChart.TYPE_GRASS, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B03.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B03.03 Rindo Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B03.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B03_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B03.05 Rindo Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b04_yache_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_ICE)
	_chk("B04.01 Yache Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_ICE)

	var attacker := _make_mon("B04_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B04_Def", TypeChart.TYPE_GRASS, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B04_SE", TypeChart.TYPE_ICE, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B04.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B04.03 Yache Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B04.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B04_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B04.05 Yache Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b05_chople_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_FIGHTING)
	_chk("B05.01 Chople Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_FIGHTING)

	var attacker := _make_mon("B05_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B05_Def", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B05_SE", TypeChart.TYPE_FIGHTING, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B05.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B05.03 Chople Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B05.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B05_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B05.05 Chople Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b06_kebia_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_POISON)
	_chk("B06.01 Kebia Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_POISON)

	var attacker := _make_mon("B06_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B06_Def", TypeChart.TYPE_GRASS, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B06_SE", TypeChart.TYPE_POISON, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B06.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B06.03 Kebia Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B06.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B06_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B06.05 Kebia Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b07_shuca_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_GROUND)
	_chk("B07.01 Shuca Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_GROUND)

	var attacker := _make_mon("B07_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B07_Def", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B07_SE", TypeChart.TYPE_GROUND, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B07.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B07.03 Shuca Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B07.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B07_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B07.05 Shuca Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b08_coba_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_FLYING)
	_chk("B08.01 Coba Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_FLYING)

	var attacker := _make_mon("B08_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B08_Def", TypeChart.TYPE_FIGHTING, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B08_SE", TypeChart.TYPE_FLYING, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B08.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B08.03 Coba Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B08.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B08_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B08.05 Coba Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b09_payapa_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_PSYCHIC)
	_chk("B09.01 Payapa Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_PSYCHIC)

	var attacker := _make_mon("B09_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B09_Def", TypeChart.TYPE_FIGHTING, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B09_SE", TypeChart.TYPE_PSYCHIC, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B09.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B09.03 Payapa Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B09.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B09_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B09.05 Payapa Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b10_tanga_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_BUG)
	_chk("B10.01 Tanga Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_BUG)

	var attacker := _make_mon("B10_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B10_Def", TypeChart.TYPE_GRASS, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B10_SE", TypeChart.TYPE_BUG, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B10.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B10.03 Tanga Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B10.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B10_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B10.05 Tanga Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b11_charti_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_ROCK)
	_chk("B11.01 Charti Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_ROCK)

	var attacker := _make_mon("B11_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B11_Def", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B11_SE", TypeChart.TYPE_ROCK, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B11.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B11.03 Charti Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B11.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B11_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B11.05 Charti Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b12_kasib_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_GHOST)
	_chk("B12.01 Kasib Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_GHOST)

	var attacker := _make_mon("B12_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B12_Def", TypeChart.TYPE_PSYCHIC, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B12_SE", TypeChart.TYPE_GHOST, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B12.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B12.03 Kasib Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B12.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B12_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B12.05 Kasib Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b13_haban_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_DRAGON)
	_chk("B13.01 Haban Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_DRAGON)

	var attacker := _make_mon("B13_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B13_Def", TypeChart.TYPE_DRAGON, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B13_SE", TypeChart.TYPE_DRAGON, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B13.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B13.03 Haban Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B13.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B13_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B13.05 Haban Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b14_colbur_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_DARK)
	_chk("B14.01 Colbur Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_DARK)

	var attacker := _make_mon("B14_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B14_Def", TypeChart.TYPE_PSYCHIC, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B14_SE", TypeChart.TYPE_DARK, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B14.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B14.03 Colbur Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B14.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B14_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B14.05 Colbur Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b15_babiri_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_STEEL)
	_chk("B15.01 Babiri Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_STEEL)

	var attacker := _make_mon("B15_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B15_Def", TypeChart.TYPE_ROCK, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B15_SE", TypeChart.TYPE_STEEL, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B15.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B15.03 Babiri Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B15.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B15_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B15.05 Babiri Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b16_roseli_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_FAIRY)
	_chk("B16.01 Roseli Berry hold_effect and param correct",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESIST_BERRY and item.hold_effect_param == TypeChart.TYPE_FAIRY)

	var attacker := _make_mon("B16_Atk", TypeChart.TYPE_MYSTERY)
	var defender := _make_mon("B16_Def", TypeChart.TYPE_FIGHTING, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 80)
	var se_move := _make_move("B16_SE", TypeChart.TYPE_FAIRY, 1, 40)

	defender.held_item = null
	var res_base := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B16.02 No item, super-effective hit -> damage=42 (baseline)",
			res_base["damage"] == 42)

	defender.held_item = item
	var res_berry := DamageCalculator.calculate(attacker, defender, se_move, 100, false)
	_chk("B16.03 Roseli Berry halves the super-effective hit -> damage=21 (x0.5 post-type-eff)",
			res_berry["damage"] == 21)
	_chk("B16.04 defender_item_consumed=true when berry triggers",
			res_berry["defender_item_consumed"] == true)

	var offtype_move := _make_move("B16_OffType", TypeChart.TYPE_NORMAL, 1, 40)
	defender.held_item = null
	var res_offtype_no_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	defender.held_item = item
	var res_offtype_with_item := DamageCalculator.calculate(attacker, defender, offtype_move, 100, false)
	_chk("B16.05 Roseli Berry does NOT reduce a non-matching-type (Normal) hit",
			res_offtype_with_item["damage"] == res_offtype_no_item["damage"])


func _test_b17_cheri_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_CURE_PAR)
	_chk("B17.01 Cheri Berry hold_effect correct", item.hold_effect == ItemManager.HOLD_EFFECT_CURE_PAR)

	var mon := _make_mon("B17_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.status = BattlePokemon.STATUS_PARALYSIS
	_chk("B17.02 Cheri Berry cures STATUS_PARALYSIS",
			ItemManager.status_cure_berry_cures(mon) == true)

	var mon2 := _make_mon("B17_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.status = BattlePokemon.STATUS_BURN
	_chk("B17.03 Cheri Berry does NOT cure STATUS_BURN",
			ItemManager.status_cure_berry_cures(mon2) == false)


func _test_b18_chesto_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_CURE_SLP)
	_chk("B18.01 Chesto Berry hold_effect correct", item.hold_effect == ItemManager.HOLD_EFFECT_CURE_SLP)

	var mon := _make_mon("B18_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.status = BattlePokemon.STATUS_SLEEP
	_chk("B18.02 Chesto Berry cures STATUS_SLEEP",
			ItemManager.status_cure_berry_cures(mon) == true)

	var mon2 := _make_mon("B18_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.status = BattlePokemon.STATUS_PARALYSIS
	_chk("B18.03 Chesto Berry does NOT cure STATUS_PARALYSIS",
			ItemManager.status_cure_berry_cures(mon2) == false)


func _test_b19_rawst_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_CURE_BRN)
	_chk("B19.01 Rawst Berry hold_effect correct", item.hold_effect == ItemManager.HOLD_EFFECT_CURE_BRN)

	var mon := _make_mon("B19_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.status = BattlePokemon.STATUS_BURN
	_chk("B19.02 Rawst Berry cures STATUS_BURN",
			ItemManager.status_cure_berry_cures(mon) == true)

	var mon2 := _make_mon("B19_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.status = BattlePokemon.STATUS_SLEEP
	_chk("B19.03 Rawst Berry does NOT cure STATUS_SLEEP",
			ItemManager.status_cure_berry_cures(mon2) == false)


func _test_b20_aspear_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_CURE_FRZ)
	_chk("B20.01 Aspear Berry hold_effect correct", item.hold_effect == ItemManager.HOLD_EFFECT_CURE_FRZ)

	var mon := _make_mon("B20_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.status = BattlePokemon.STATUS_FREEZE
	_chk("B20.02 Aspear Berry cures STATUS_FREEZE",
			ItemManager.status_cure_berry_cures(mon) == true)

	var mon2 := _make_mon("B20_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.status = BattlePokemon.STATUS_POISON
	_chk("B20.03 Aspear Berry does NOT cure STATUS_POISON",
			ItemManager.status_cure_berry_cures(mon2) == false)


func _test_b21_pecha_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_CURE_PSN)
	_chk("B21.01 Pecha Berry hold_effect correct", item.hold_effect == ItemManager.HOLD_EFFECT_CURE_PSN)

	var mon_psn := _make_mon("B21_Poison", TypeChart.TYPE_NORMAL)
	mon_psn.held_item = item
	mon_psn.status = BattlePokemon.STATUS_POISON
	_chk("B21.02 Pecha Berry cures regular Poison",
			ItemManager.status_cure_berry_cures(mon_psn) == true)

	var mon_tox := _make_mon("B21_Toxic", TypeChart.TYPE_NORMAL)
	mon_tox.held_item = item
	mon_tox.status = BattlePokemon.STATUS_TOXIC
	_chk("B21.03 Pecha Berry ALSO cures Toxic (STATUS1_PSN_ANY in source, not just plain poison)",
			ItemManager.status_cure_berry_cures(mon_tox) == true)

	var mon_brn := _make_mon("B21_Burn", TypeChart.TYPE_NORMAL)
	mon_brn.held_item = item
	mon_brn.status = BattlePokemon.STATUS_BURN
	_chk("B21.04 Pecha Berry does NOT cure Burn",
			ItemManager.status_cure_berry_cures(mon_brn) == false)


func _test_b22_persim_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_CURE_CONFUSION)
	_chk("B22.01 Persim Berry hold_effect correct", item.hold_effect == ItemManager.HOLD_EFFECT_CURE_CONFUSION)

	var mon := _make_mon("B22_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.confusion_turns = 3
	_chk("B22.02 Persim Berry cures confusion (confusion_turns > 0)",
			ItemManager.confusion_cure_berry_cures(mon) == true)

	var mon2 := _make_mon("B22_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.status = BattlePokemon.STATUS_PARALYSIS  # a non-volatile status, not confusion
	_chk("B22.03 Persim Berry does NOT cure a non-volatile status (only confusion_turns)",
			ItemManager.confusion_cure_berry_cures(mon2) == false)

	var mon3 := _make_mon("B22_Mon3", TypeChart.TYPE_NORMAL)
	mon3.held_item = item
	_chk("B22.04 Persim Berry does NOT cure when not confused (confusion_turns == 0)",
			ItemManager.confusion_cure_berry_cures(mon3) == false)


func _test_b23_oran_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RESTORE_HP, 10)
	_chk("B23.01 Oran Berry hold_effect=RESTORE_HP, param=10 (flat)",
			item.hold_effect == ItemManager.HOLD_EFFECT_RESTORE_HP and item.hold_effect_param == 10)

	# base_hp=100 -> max_hp = floor(2*100*50/100)+50+10 = 100+50+10 = 160; 50% threshold = 80.
	var mon := _make_mon("B23_Mon", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	mon.held_item = item
	mon.current_hp = 80  # exactly at max_hp/2 -> triggers (HasEnoughHpToEatBerry: hp <= max_hp/fraction)
	_chk("B23.02 Oran Berry heals flat 10 HP at <=50% max HP (threshold, matching Sitrus)",
			ItemManager.hp_threshold_berry_heal(mon) == 10)

	var mon2 := _make_mon("B23_Mon2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	mon2.held_item = item
	mon2.current_hp = 81  # just above the 50% threshold -> does NOT trigger
	_chk("B23.03 Oran Berry does NOT trigger above the 50% threshold",
			ItemManager.hp_threshold_berry_heal(mon2) == 0)

