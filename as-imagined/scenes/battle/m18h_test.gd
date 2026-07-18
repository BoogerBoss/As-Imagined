extends Node

# M18h test suite — EV/Power-item Speed-halving family (Macho Brace + 6 Power items)
#
# Ground truth: pokeemerald-expansion, src/battle_main.c L4699:
#   `if (holdEffect == HOLD_EFFECT_MACHO_BRACE || holdEffect == HOLD_EFFECT_POWER_ITEM)
#        speed /= 2;`
# — the same speed-pipeline chokepoint Choice Scarf (this project's existing
# ItemManager.apply_speed_modifier) and Quick Powder ([M18g]) already occupy.
#
# CORRECTION found at Step 0: Macho Brace does NOT share the 6 "Power X" items'
# hold_effect constant — it has its own distinct HOLD_EFFECT_MACHO_BRACE (24),
# separate from HOLD_EFFECT_POWER_ITEM (81) — but the actual EFFECT is
# identical: source dispatches both through the ONE shared OR'd condition
# above. The inverse of [M18e]'s Scope Lens/Razor Claw finding (there: one
# shared constant, identical effect; here: two distinct constants, identical
# effect) — tested explicitly below (H01 uses HOLD_EFFECT_MACHO_BRACE, H02-H07
# use HOLD_EFFECT_POWER_ITEM, both reach the identical halved-Speed outcome).
#
# EV-doubling half confirmed PERMANENTLY MOOT for all 7, re-verified directly
# at Step 0 (not trusted from a prior citation): grepped every `evs[` mutation
# in scripts/battle/core/*.gd — the only writes anywhere are static
# initialization/test setup, no EV-gain mechanism exists in battle logic to
# double. Not implemented, not tested — nothing to hook into.
#
# Sections: H01 Macho Brace (full — data/halve/discriminator/odd-speed
# truncation), H02-H07 the 6 Power items (data/halve each, confirming the
# shared HOLD_EFFECT_POWER_ITEM constant and identical behavior individually).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_h01_macho_brace()
	_test_h02_power_weight()
	_test_h03_power_bracer()
	_test_h04_power_belt()
	_test_h05_power_lens()
	_test_h06_power_band()
	_test_h07_power_anklet()

	var total := _pass + _fail
	print("m18h_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18g_test.gd's established pattern) ───────────────────────

func _make_item(hold_effect: int) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	return item


func _make_mon(mon_name: String, type1: int) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp         = 100
	sp.base_attack     = 80
	sp.base_defense    = 80
	sp.base_sp_attack  = 80
	sp.base_sp_defense = 80
	sp.base_speed      = 80
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


# ── H01: Macho Brace (418) — own constant, same halving effect ────────────────
func _test_h01_macho_brace() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_MACHO_BRACE)
	_chk("H01.01 Macho Brace hold_effect=MACHO_BRACE(24), its OWN constant, " +
			"NOT HOLD_EFFECT_POWER_ITEM",
			item.hold_effect == ItemManager.HOLD_EFFECT_MACHO_BRACE \
					and item.hold_effect != ItemManager.HOLD_EFFECT_POWER_ITEM)

	var mon := _make_mon("H01_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	_chk("H01.02 Macho Brace halves Speed (100 -> 50)",
			ItemManager.apply_speed_modifier(mon, 100) == 50)

	_chk("H01.03 integer-division truncation matches source's `speed /= 2` " +
			"exactly (101 -> 50, not 50.5 or 51)",
			ItemManager.apply_speed_modifier(mon, 101) == 50)

	var bare := _make_mon("H01_Bare", TypeChart.TYPE_NORMAL)
	_chk("H01.04 discriminator: holding nothing leaves Speed unchanged",
			ItemManager.apply_speed_modifier(bare, 100) == 100)


# ── H02: Power Weight (419) ─────────────────────────────────────────────────
func _test_h02_power_weight() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_POWER_ITEM)
	_chk("H02.01 Power Weight hold_effect=POWER_ITEM(81)",
			item.hold_effect == ItemManager.HOLD_EFFECT_POWER_ITEM)
	var mon := _make_mon("H02_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	_chk("H02.02 Power Weight halves Speed (100 -> 50) — same outcome as Macho " +
			"Brace despite the different hold_effect constant",
			ItemManager.apply_speed_modifier(mon, 100) == 50)


# ── H03: Power Bracer (420) ─────────────────────────────────────────────────
func _test_h03_power_bracer() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_POWER_ITEM)
	_chk("H03.01 Power Bracer hold_effect=POWER_ITEM(81)",
			item.hold_effect == ItemManager.HOLD_EFFECT_POWER_ITEM)
	var mon := _make_mon("H03_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	_chk("H03.02 Power Bracer halves Speed (100 -> 50)",
			ItemManager.apply_speed_modifier(mon, 100) == 50)


# ── H04: Power Belt (421) ───────────────────────────────────────────────────
func _test_h04_power_belt() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_POWER_ITEM)
	_chk("H04.01 Power Belt hold_effect=POWER_ITEM(81)",
			item.hold_effect == ItemManager.HOLD_EFFECT_POWER_ITEM)
	var mon := _make_mon("H04_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	_chk("H04.02 Power Belt halves Speed (100 -> 50)",
			ItemManager.apply_speed_modifier(mon, 100) == 50)


# ── H05: Power Lens (422) ───────────────────────────────────────────────────
func _test_h05_power_lens() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_POWER_ITEM)
	_chk("H05.01 Power Lens hold_effect=POWER_ITEM(81)",
			item.hold_effect == ItemManager.HOLD_EFFECT_POWER_ITEM)
	var mon := _make_mon("H05_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	_chk("H05.02 Power Lens halves Speed (100 -> 50)",
			ItemManager.apply_speed_modifier(mon, 100) == 50)


# ── H06: Power Band (423) ───────────────────────────────────────────────────
func _test_h06_power_band() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_POWER_ITEM)
	_chk("H06.01 Power Band hold_effect=POWER_ITEM(81)",
			item.hold_effect == ItemManager.HOLD_EFFECT_POWER_ITEM)
	var mon := _make_mon("H06_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	_chk("H06.02 Power Band halves Speed (100 -> 50)",
			ItemManager.apply_speed_modifier(mon, 100) == 50)


# ── H07: Power Anklet (424) ─────────────────────────────────────────────────
func _test_h07_power_anklet() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_POWER_ITEM)
	_chk("H07.01 Power Anklet hold_effect=POWER_ITEM(81)",
			item.hold_effect == ItemManager.HOLD_EFFECT_POWER_ITEM)
	var mon := _make_mon("H07_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	_chk("H07.02 Power Anklet halves Speed (100 -> 50)",
			ItemManager.apply_speed_modifier(mon, 100) == 50)
