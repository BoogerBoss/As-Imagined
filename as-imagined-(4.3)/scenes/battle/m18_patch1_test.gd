extends Node

# M18-patch-1 test suite — Cheek Pouch berry-gate fix
#
# Bug: `_consume_item` (battle_manager.gd) called `AbilityManager.cheek_pouch_heal`
# and set `mon.last_consumed_berry` unconditionally for ANY item reaching that
# function — a comment there asserted "every item reaching this function today is
# already a berry," which was true when Cheek Pouch was first implemented ([M17c])
# but went stale once [M18n] (Red Card, Eject Button) and [M18o] (Focus Sash) added
# non-berry items that are also consumed via the exact same choke point. This meant
# a Cheek Pouch holder got a free maxHP/3 heal from consuming ANY of those three
# items, and Harvest/Cud Chew (which both read `last_consumed_berry`) would
# incorrectly arm/regenerate off a non-berry consumption too.
#
# Ground truth: pokeemerald-expansion
#   src/battle_script_commands.c :: TryCheekPouch (L6175-6188) — gates directly on
#     `GetItemPocket(itemId) == POCKET_BERRIES` at the item-removal site, not a
#     generic "was anything consumed" hook.
#   include/constants/item.h :: enum Pocket — POCKET_ITEMS=0, POCKET_POKE_BALLS=1,
#     POCKET_TM_HM=2, POCKET_BERRIES=3, POCKET_KEY_ITEMS=4.
#
# Fix: `ItemData.pocket` already existed in the schema (added alongside M18's
# item-data infrastructure) but was never populated for any item — confirmed via
# grep, not assumed. Populated `pocket = POCKET_BERRIES` on all 36 real berry
# entries in gen_items.py; `_consume_item` now gates both `cheek_pouch_heal` and
# `last_consumed_berry`'s assignment on `item.pocket == ItemManager.POCKET_BERRIES`.
# Confirmed via direct code read (not carried forward from prior session
# narrative): exactly THREE non-berry items reach `_consume_item` today — Focus
# Sash ([M18o]), Red Card, and Eject Button (both [M18n], a correction to the
# task's own two-item list). King's Rock is a passive, never-consumed proc — it
# does NOT reach `_consume_item` at all, confirmed absent from that block, so it
# was never actually a counterexample despite being informally flagged as one.
#
# Sections: P01 positive case (Cheek Pouch + real berry, unchanged), P02
# discriminator (Cheek Pouch + all 3 confirmed non-berry items, the actual fix),
# P03 negative case (no Cheek Pouch, berry consumed, unaffected), P04
# Harvest/Cud Chew discriminator (the second confirmed instance of the same bug).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_p01_positive_berry_case()
	_test_p02_discriminator_non_berry()
	_test_p03_negative_no_ability()
	_test_p04_harvest_cud_chew_discriminator()

	var total := _pass + _fail
	print("m18_patch1_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers ──────────────────────────────────────────────────────────────────────

func _make_mon(mon_name: String, type1: int, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


# Loads the REAL generated item via ItemRegistry (not a hand-rolled ItemData) so
# this suite exercises the actual gen_items.py/.tres data pipeline this patch
# touched, not just the in-memory mechanism.
func _load_item(id: int) -> ItemData:
	return ItemRegistry.get_item(id)


# ── P01: positive case — Cheek Pouch + a real berry, unchanged behavior ────────
func _test_p01_positive_berry_case() -> void:
	var oran := _load_item(520)  # Oran Berry — HOLD_EFFECT_RESTORE_HP
	_chk("P01.01 fixture check: Oran Berry's pocket == POCKET_BERRIES(3)",
			oran.pocket == ItemManager.POCKET_BERRIES)

	var holder := _make_mon("P01_Holder", TypeChart.TYPE_NORMAL, 300)
	holder.ability = _load_ability(167)  # Cheek Pouch
	holder.held_item = oran
	holder.current_hp = 100  # well below max, so the heal is observable

	var bm := BattleManager.new()
	add_child(bm)
	var triggered := []
	var healed := []
	bm.ability_triggered.connect(func(m, k): triggered.push_back([m, k]))
	bm.ability_healed.connect(func(m, amt): healed.push_back([m, amt]))
	bm._consume_item(holder)

	_chk("P01.02 Cheek Pouch heals maxHP/3 on a real berry consumption " +
			"(unchanged from pre-fix behavior)",
			healed.size() == 1 and healed[0][0] == holder and healed[0][1] == holder.max_hp / 3)
	_chk("P01.03 ability_triggered fires with 'cheek_pouch'",
			triggered.any(func(e): return e[0] == holder and e[1] == "cheek_pouch"))
	_chk("P01.04 the holder's HP actually increased by the heal amount",
			holder.current_hp == 100 + holder.max_hp / 3)
	_chk("P01.05 last_consumed_berry IS set for a real berry (Harvest/Cud Chew " +
			"tracking unaffected for the positive case)",
			holder.last_consumed_berry == oran)
	bm.queue_free()


# ── P02: discriminator — Cheek Pouch + all 3 confirmed non-berry items ─────────
# The actual bug fix: NONE of these should heal, despite reaching the exact same
# `_consume_item` choke point a real berry does.
func _test_p02_discriminator_non_berry() -> void:
	var non_berries := {
		"Focus Sash": 481,
		"Red Card": 498,
		"Eject Button": 501,
	}
	for label: String in non_berries:
		var item: ItemData = _load_item(non_berries[label])
		_chk("P02 fixture check: %s's pocket != POCKET_BERRIES" % label,
				item.pocket != ItemManager.POCKET_BERRIES)

		var holder := _make_mon("P02_Holder_%s" % label, TypeChart.TYPE_NORMAL, 300)
		holder.ability = _load_ability(167)  # Cheek Pouch
		holder.held_item = item
		holder.current_hp = 100

		var bm := BattleManager.new()
		add_child(bm)
		var triggered := []
		var healed := []
		bm.ability_triggered.connect(func(m, k): triggered.push_back([m, k]))
		bm.ability_healed.connect(func(m, amt): healed.push_back([m, amt]))
		bm._consume_item(holder)

		_chk("P02 CORRECTION-confirming: Cheek Pouch does NOT heal on consuming " +
				"%s (a non-berry item)" % label,
				healed.is_empty() and not triggered.any(func(e): return e[1] == "cheek_pouch"))
		_chk("P02 HP unchanged for %s" % label,
				holder.current_hp == 100)
		bm.queue_free()


# ── P03: negative case — no Cheek Pouch, a real berry is consumed, unaffected ──
func _test_p03_negative_no_ability() -> void:
	var oran := _load_item(520)
	var holder := _make_mon("P03_Holder", TypeChart.TYPE_NORMAL, 300)
	holder.held_item = oran
	holder.current_hp = 100

	var bm := BattleManager.new()
	add_child(bm)
	var triggered := []
	var healed := []
	bm.ability_triggered.connect(func(m, k): triggered.push_back([m, k]))
	bm.ability_healed.connect(func(m, amt): healed.push_back([m, amt]))
	bm._consume_item(holder)

	_chk("P03.01 discriminator: no Cheek Pouch ability -> no ability-driven heal, " +
			"no interference from this fix",
			healed.is_empty() and not triggered.any(func(e): return e[1] == "cheek_pouch"))
	_chk("P03.02 the holder's HP is unaffected by _consume_item itself (the " +
			"berry's OWN heal effect, if any, is applied by the caller BEFORE " +
			"_consume_item runs — not this function's job)",
			holder.current_hp == 100)
	_chk("P03.03 last_consumed_berry is STILL correctly set for a real berry, " +
			"regardless of the holder's own ability (Harvest doesn't require " +
			"Cheek Pouch too)",
			holder.last_consumed_berry == oran)
	bm.queue_free()


# ── P04: Harvest/Cud Chew discriminator — the second confirmed instance ────────
# of the identical bug. Both read `last_consumed_berry`, which now only gets set
# for real berries — confirmed at the source (their shared assignment point in
# _consume_item), not by patching each reader independently.
func _test_p04_harvest_cud_chew_discriminator() -> void:
	var harvest := _load_ability(139)
	var cud_chew := _load_ability(291)
	var focus_sash := _load_item(481)
	var oran := _load_item(520)

	# Harvest: consuming a non-berry must NOT arm it (forced_roll=true would
	# otherwise guarantee activation if last_consumed_berry were wrongly set).
	var hv_holder := _make_mon("P04_Harvest", TypeChart.TYPE_NORMAL, 100)
	hv_holder.ability = harvest
	hv_holder.held_item = focus_sash
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._consume_item(hv_holder)
	_chk("P04.01 CORRECTION-confirming: Harvest does NOT activate off a " +
			"non-berry consumption (Focus Sash) -- last_consumed_berry stayed null",
			not AbilityManager.harvest_activates(hv_holder, DamageCalculator.WEATHER_NONE, false, true))
	bm1.queue_free()

	# Discriminator: the SAME setup with a real berry -- Harvest CAN activate.
	var hv_holder2 := _make_mon("P04_Harvest2", TypeChart.TYPE_NORMAL, 100)
	hv_holder2.ability = harvest
	hv_holder2.held_item = oran
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._consume_item(hv_holder2)
	_chk("P04.02 discriminator: Harvest CAN activate after a real berry " +
			"consumption (forced_roll=true)",
			AbilityManager.harvest_activates(hv_holder2, DamageCalculator.WEATHER_NONE, false, true))
	bm2.queue_free()

	# Cud Chew: consuming a non-berry must NOT arm.
	var cc_holder := _make_mon("P04_CudChew", TypeChart.TYPE_NORMAL, 100)
	cc_holder.ability = cud_chew
	cc_holder.held_item = focus_sash
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._consume_item(cc_holder)
	_chk("P04.03 CORRECTION-confirming: Cud Chew does NOT arm off a non-berry " +
			"consumption (Focus Sash)",
			AbilityManager.cud_chew_check(cc_holder) == "")
	bm3.queue_free()

	# Discriminator: the SAME setup with a real berry -- Cud Chew DOES arm.
	var cc_holder2 := _make_mon("P04_CudChew2", TypeChart.TYPE_NORMAL, 100)
	cc_holder2.ability = cud_chew
	cc_holder2.held_item = oran
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4._consume_item(cc_holder2)
	_chk("P04.04 discriminator: Cud Chew DOES arm after a real berry consumption",
			AbilityManager.cud_chew_check(cc_holder2) == "arm")
	bm4.queue_free()
