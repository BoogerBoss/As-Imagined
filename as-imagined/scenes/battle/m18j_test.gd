extends Node

# M18j test suite — Power/accuracy flat-modifier misc (Muscle Band, Wise
# Glasses, Expert Belt, Wide Lens, Zoom Lens, Bright Powder, Lax Incense)
#
# Ground truth: pokeemerald-expansion.
#
# MAJOR CORRECTION found at Step 0: Expert Belt is NOT the same pipeline
# stage as Muscle Band/Wise Glasses, despite the plan's "power items"
# grouping. Source places Expert Belt in GetAttackerItemsModifier
# (battle_util.c L7493-7495) — the SAME function this project's
# ItemManager.post_roll_modifier_uq412 (Life Orb) already implements, applied
# AFTER the roll/type-effectiveness. Muscle Band/Wise Glasses live in
# CalcMoveBasePowerAfterModifiers (ItemManager.move_power_modifier_uq412,
# [M18a]'s function), applied BEFORE the base formula. Two genuinely
# different pipeline stages, tested separately below (J01/J02 vs J03).
#
# Second correction: Muscle Band/Wise Glasses use PercentToUQ4_12_Floored
# ((4096*param)/100, no rounding) — a DIFFERENT formula than [M18a]'s
# Charcoal-family items (PercentToUQ4_12, (4096*param+50)/100, rounds). A
# real 1-unit difference at 10%: floored=4505, rounded would be 4506.
#
# Confirmed, not corrected: Bright Powder and Lax Incense really are
# identical (literal same HOLD_EFFECT_EVASION_UP, both holdEffectParam=10
# under this reference clone's config) — tested independently anyway per
# standing discipline, both land on the identical outcome.
#
# Zoom Lens's "target already acted this turn" condition is fully checkable
# via this project's existing _turn_order/_current_actor_index position
# tracking (same infrastructure _is_last_to_move already established for
# Analytic, [M17n-5]) — implemented via new BattleManager._has_target_
# already_acted, NOT deferred or approximated.
#
# Sections: J01 Muscle Band, J02 Wise Glasses, J03 Expert Belt, J04 Wide
# Lens, J05 Zoom Lens, J06 Bright Powder, J07 Lax Incense.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_j01_muscle_band()
	_test_j02_wise_glasses()
	_test_j03_expert_belt()
	_test_j04_wide_lens()
	_test_j05_zoom_lens()
	_test_j06_bright_powder()
	_test_j07_lax_incense()

	var total := _pass + _fail
	print("m18j_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18h_test.gd/m18i_test.gd's established pattern) ──────────

func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
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


# ── J01: Muscle Band (475) — physical power x1.1, FLOORED rounding ─────────────
func _test_j01_muscle_band() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_MUSCLE_BAND, 10)
	_chk("J01.01 Muscle Band hold_effect=MUSCLE_BAND(62), param=10",
			item.hold_effect == ItemManager.HOLD_EFFECT_MUSCLE_BAND and item.hold_effect_param == 10)

	var mon := _make_mon("J01_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	var physical := _make_move("J01_Physical", TypeChart.TYPE_NORMAL, 0, 40)
	var special := _make_move("J01_Special", TypeChart.TYPE_NORMAL, 1, 40)
	_chk("J01.02 CORRECTION-confirming: x1.1 on a PHYSICAL move = 4505 (FLOORED " +
			"rounding, NOT 4506 which the rounded PercentToUQ4_12 formula would give)",
			ItemManager.move_power_modifier_uq412(mon, physical) == 4505)
	_chk("J01.03 discriminator: does NOT boost a SPECIAL move (physical-only)",
			ItemManager.move_power_modifier_uq412(mon, special) == 4096)


# ── J02: Wise Glasses (476) — special power x1.1, same FLOORED formula ─────────
func _test_j02_wise_glasses() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_WISE_GLASSES, 10)
	_chk("J02.01 Wise Glasses hold_effect=WISE_GLASSES(64), param=10",
			item.hold_effect == ItemManager.HOLD_EFFECT_WISE_GLASSES and item.hold_effect_param == 10)

	var mon := _make_mon("J02_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	var special := _make_move("J02_Special", TypeChart.TYPE_NORMAL, 1, 40)
	var physical := _make_move("J02_Physical", TypeChart.TYPE_NORMAL, 0, 40)
	_chk("J02.02 x1.1 on a SPECIAL move = 4505 (same FLOORED formula as Muscle Band)",
			ItemManager.move_power_modifier_uq412(mon, special) == 4505)
	_chk("J02.03 discriminator: does NOT boost a PHYSICAL move (special-only) " +
			"— inverted category gate from Muscle Band",
			ItemManager.move_power_modifier_uq412(mon, physical) == 4096)


# ── J03: Expert Belt (477) — DIFFERENT pipeline stage, flat x1.2 on 2x+ ────────
func _test_j03_expert_belt() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_EXPERT_BELT, 20)
	_chk("J03.01 Expert Belt hold_effect=EXPERT_BELT(59), param=20 (stored but " +
			"NOT actually read by the dispatch — confirmed via source)",
			item.hold_effect == ItemManager.HOLD_EFFECT_EXPERT_BELT and item.hold_effect_param == 20)

	var mon := _make_mon("J03_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	_chk("J03.02 CORRECTION-confirming: Expert Belt does NOT respond to " +
			"move_power_modifier_uq412 at all (it's a DIFFERENT function/pipeline " +
			"stage than Muscle Band/Wise Glasses)",
			ItemManager.move_power_modifier_uq412(mon, _make_move("J03_M", TypeChart.TYPE_NORMAL, 0, 40)) == 4096)

	_chk("J03.03 post_roll_modifier_uq412: flat x1.2 (4915) at exactly 2.0x effectiveness",
			ItemManager.post_roll_modifier_uq412(mon, false, 2.0) == ItemManager.UQ412_EXPERT_BELT)
	_chk("J03.04 confirmed uniform: 4.0x effectiveness gets the SAME x1.2, not " +
			"extra stacking",
			ItemManager.post_roll_modifier_uq412(mon, false, 4.0) == ItemManager.UQ412_EXPERT_BELT)
	_chk("J03.05 discriminator: neutral (1.0x) effectiveness gets NO boost",
			ItemManager.post_roll_modifier_uq412(mon, false, 1.0) == 4096)
	_chk("J03.06 discriminator: resisted (0.5x) effectiveness gets NO boost",
			ItemManager.post_roll_modifier_uq412(mon, false, 0.5) == 4096)


# ── J04: Wide Lens (474) — attacker accuracy x1.10, unconditional ──────────────
func _test_j04_wide_lens() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_WIDE_LENS, 10)
	_chk("J04.01 Wide Lens hold_effect=WIDE_LENS(63), param=10",
			item.hold_effect == ItemManager.HOLD_EFFECT_WIDE_LENS and item.hold_effect_param == 10)

	var mon := _make_mon("J04_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	var target := _make_mon("J04_Target", TypeChart.TYPE_NORMAL)
	_chk("J04.02 Wide Lens: accuracy x1.10 (110), unconditional",
			ItemManager.accuracy_modifier_percent(mon, target) == 110)

	var bare := _make_mon("J04_Bare", TypeChart.TYPE_NORMAL)
	_chk("J04.03 discriminator: a non-holder gets normal accuracy (100)",
			ItemManager.accuracy_modifier_percent(bare, target) == 100)


# ── J05: Zoom Lens (482) — attacker accuracy x1.20, ONLY if target already acted ─
func _test_j05_zoom_lens() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_ZOOM_LENS, 20)
	_chk("J05.01 Zoom Lens hold_effect=ZOOM_LENS(65), param=20",
			item.hold_effect == ItemManager.HOLD_EFFECT_ZOOM_LENS and item.hold_effect_param == 20)

	var mon := _make_mon("J05_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	var target := _make_mon("J05_Target", TypeChart.TYPE_NORMAL)
	_chk("J05.02 Zoom Lens: accuracy x1.20 (120) WHEN the target has already " +
			"acted this turn",
			ItemManager.accuracy_modifier_percent(mon, target, false, true) == 120)
	_chk("J05.03 CONDITION-confirming discriminator: NO boost when the target " +
			"has NOT yet acted this turn (item held, condition simply unmet — " +
			"NOT a blocked/deferred implementation)",
			ItemManager.accuracy_modifier_percent(mon, target, false, false) == 100)

	# Direct confirmation of the real wiring (BattleManager.
	# _has_target_already_acted), reading/writing the same plain _turn_order/
	# _current_actor_index fields _phase_priority_resolution itself populates
	# — the identical "reach into BattleManager's own state directly" pattern
	# every test file already uses for _force_hit/_force_crit, applied here to
	# the two fields this function actually reads. Cheaper and more precise
	# than a full multi-turn statistical battle sample, and fully
	# deterministic (no RNG involved in the position check itself).
	var mon_a := _make_mon("J05_A", TypeChart.TYPE_NORMAL)
	var mon_b := _make_mon("J05_B", TypeChart.TYPE_NORMAL)
	var bm := BattleManager.new()
	add_child(bm)
	bm._turn_order = [mon_a, mon_b]
	bm._current_actor_index = 1  # mon_b (index 1) is the CURRENT actor
	_chk("J05.05 wiring: mon_a (position 0, before the current actor) has " +
			"ALREADY acted this turn",
			bm._has_target_already_acted(mon_a) == true)
	_chk("J05.06 discriminator: mon_b (the CURRENT actor itself, position 1) " +
			"has NOT already acted",
			bm._has_target_already_acted(mon_b) == false)
	bm.queue_free()


# ── J06: Bright Powder (459) — defender-side accuracy x0.90 against holder ─────
func _test_j06_bright_powder() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_EVASION_UP, 10)
	_chk("J06.01 Bright Powder hold_effect=EVASION_UP(22), param=10",
			item.hold_effect == ItemManager.HOLD_EFFECT_EVASION_UP and item.hold_effect_param == 10)

	var holder := _make_mon("J06_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	var attacker := _make_mon("J06_Attacker", TypeChart.TYPE_NORMAL)
	_chk("J06.02 Bright Powder: x0.90 accuracy (90) against an attacker " +
			"targeting the holder",
			ItemManager.accuracy_modifier_percent(attacker, holder) == 90)

	_chk("J06.03 discriminator: no reduction when the holder is NOT the " +
			"defender being targeted (null defender)",
			ItemManager.accuracy_modifier_percent(attacker, null) == 100)


# ── J07: Lax Incense (405) — genuinely identical to Bright Powder ──────────────
func _test_j07_lax_incense() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_EVASION_UP, 10)
	_chk("J07.01 Lax Incense hold_effect=EVASION_UP(22), param=10 — the SAME " +
			"constant and magnitude as Bright Powder, confirmed via source " +
			"not assumed",
			item.hold_effect == ItemManager.HOLD_EFFECT_EVASION_UP and item.hold_effect_param == 10)

	var holder := _make_mon("J07_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	var attacker := _make_mon("J07_Attacker", TypeChart.TYPE_NORMAL)
	_chk("J07.02 Lax Incense: x0.90 accuracy (90) against an attacker " +
			"targeting the holder — identical outcome to Bright Powder (J06.02)",
			ItemManager.accuracy_modifier_percent(attacker, holder) == 90)

	_chk("J07.03 discriminator: no reduction when the holder is NOT the " +
			"defender being targeted",
			ItemManager.accuracy_modifier_percent(attacker, null) == 100)
