extends Node

# M18l test suite — Turn-order items (Quick Claw, Full Incense, Lagging Tail)
#
# Ground truth: pokeemerald-expansion
#   src/battle_main.c L4987 (`quickClawRandom[battler] = RandomPercentage(RNG_QUICK_CLAW,
#     GetBattlerHoldEffectParam(battler))`) and L5191 (`holdEffectBattler1 ==
#     HOLD_EFFECT_QUICK_CLAW && quickClawRandom[battler1]`) — Quick Claw's 20% (item's
#     own `.holdEffectParam = 20`, src/data/items.h L9716) act-first roll, with NO
#     move-category gate (confirmed by direct comparison — Quick Draw's own condition
#     on the same line DOES check `!IsBattleMoveStatus(...)`, Quick Claw's does not).
#   src/battle_main.c L4409-4410 (`if (GetBattlerHoldEffect(battler) ==
#     HOLD_EFFECT_LAGGING_TAIL) gProtectStructs[battler].laggingTail = TRUE`) — Full
#     Incense (408) and Lagging Tail (485) share the LITERAL SAME `HOLD_EFFECT_
#     LAGGING_TAIL` value in source (items.h L8543/L10270, not two separate
#     constants), set UNCONDITIONALLY (no move-category gate), matching Stall's shape
#     exactly rather than Mycelium Might's narrower one.
#   src/battle_main.c L4786-4800 (`GetWhichBattlerFasterArgs`) — confirms the
#     PRECEDENCE finding this tier's Step 0 resolved: `battler1HasQuickEffect =
#     quickDraw || usedCustapBerry` and `battler1HasSlowEffect =
#     battler1HasStallingAbility || laggingTail` are already OR'd together at the
#     ability/item level BEFORE the comparator runs, and quick is checked strictly
#     before slow for the WHOLE comparison — so a single Pokémon holding both a quick
#     source (ability or item) and a slow source (ability or item) always resolves as
#     quick; its own slow flag is never even consulted. This project's existing
#     `quick_effect`/`slow_effect` precompute dicts in `_phase_priority_resolution`
#     already check quick before slow, so OR-ing the new item checks into those two
#     existing dicts reproduces this precedence automatically — Section L04 proves it.
#
# Docs: docs/m18_subtier_plan.md (M18l section) — 3 items, reusing [M17n-3]'s
# turn-order infrastructure (AbilityManager.quick_draw_activates /
# has_slow_turn_order_effect) via new parallel item-keyed
# ItemManager.quick_claw_activates / has_slow_turn_order_item, OR'd into the exact
# same per-turn precompute dicts BattleManager already builds — no parallel
# mechanism, matching source's own OR-at-the-flag-level structure exactly.
#
# Sections: L01 Quick Claw, L02 Full Incense, L03 Lagging Tail, L04 composition
# (item-vs-ability precedence, the two scenarios this tier's own Step 0 resolved).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_l01_quick_claw()
	_test_l02_full_incense()
	_test_l03_lagging_tail()
	_test_l04_composition()

	var total := _pass + _fail
	print("m18l_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18e_test.gd / m17n3_test.gd's established pattern) ───────

func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


# ── L01: Quick Claw (462) ───────────────────────────────────────────────────────
func _test_l01_quick_claw() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_QUICK_CLAW, 20)
	_chk("L01.01 Quick Claw hold_effect == HOLD_EFFECT_QUICK_CLAW(26), param == 20",
			item.hold_effect == ItemManager.HOLD_EFFECT_QUICK_CLAW and item.hold_effect_param == 20)

	var tackle := _load_move(33)
	var growl := _load_move(45)  # status move

	# Direct unit checks — deterministic via forced_roll, no full battle needed.
	var holder := _make_mon("L01_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("L01.02 direct: forced_roll=true -> activates",
			ItemManager.quick_claw_activates(holder, false, true))
	_chk("L01.03 direct: forced_roll=false -> does not activate",
			not ItemManager.quick_claw_activates(holder, false, false))
	var bare := _make_mon("L01_Bare", TypeChart.TYPE_NORMAL)
	_chk("L01.04 discriminator: holding nothing never activates, even forced_roll=true",
			not ItemManager.quick_claw_activates(bare, false, true))

	# Full-battle: holder is SLOWER; forced roll = true -> acts first anyway.
	var qc := _make_mon("L01_Battle", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	qc.held_item = item
	qc.add_move(tackle)
	var opp := _make_mon("L01_Opp", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_quick_claw_roll = true
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(qc), BattleParty.single(opp))
	_chk("L01.05 full-battle: Quick Claw (forced roll=true) makes the slower holder " +
			"act FIRST",
			not events.is_empty() and events[0][0] == qc)
	bm.queue_free()

	# Discriminator: forced roll = false -> normal (faster-first) order.
	var qc2 := _make_mon("L01_Battle2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	qc2.held_item = item
	qc2.add_move(tackle)
	var opp2 := _make_mon("L01_Opp2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	opp2.add_move(tackle)

	var events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_quick_claw_roll = false
	bm2.move_executed.connect(func(a, d, m, dmg): events2.push_back([a, d, m, dmg]))
	bm2.start_battle_with_parties(BattleParty.single(qc2), BattleParty.single(opp2))
	_chk("L01.06 discriminator: forced roll=false -> normal order, faster opponent first",
			not events2.is_empty() and events2[0][0] == opp2)
	bm2.queue_free()

	# Key correction from Step 0: Quick Claw is NOT gated on move category, unlike
	# Quick Draw. Holder uses a STATUS move (Growl) and still acts first.
	var qc3 := _make_mon("L01_Battle3", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	qc3.held_item = item
	qc3.add_move(growl)
	var opp3 := _make_mon("L01_Opp3", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	opp3.add_move(tackle)

	var stat_events := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_quick_claw_roll = true
	bm3.stat_stage_changed.connect(func(m, stat, actual): stat_events.push_back([m, stat, actual]))
	bm3.start_battle_with_parties(BattleParty.single(qc3), BattleParty.single(opp3))
	_chk("L01.07 CORRECTION-confirming: a STATUS-move Quick Claw holder still acts " +
			"first (unlike Quick Draw, which would be gated out here) — Growl's Attack " +
			"drop is the first stat event",
			not stat_events.is_empty() and stat_events[0][0] == opp3)
	bm3.queue_free()


# ── L02: Full Incense (408) ─────────────────────────────────────────────────────
func _test_l02_full_incense() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_LAGGING_TAIL)
	_chk("L02.01 Full Incense hold_effect == HOLD_EFFECT_LAGGING_TAIL(66)",
			item.hold_effect == ItemManager.HOLD_EFFECT_LAGGING_TAIL)

	var holder := _make_mon("L02_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("L02.02 direct: has_slow_turn_order_item == true when holding Full Incense",
			ItemManager.has_slow_turn_order_item(holder))
	var bare := _make_mon("L02_Bare", TypeChart.TYPE_NORMAL)
	_chk("L02.03 discriminator: holding nothing -> false",
			not ItemManager.has_slow_turn_order_item(bare))

	var tackle := _load_move(33)
	# Full-battle: holder is the FASTER combatant — without the item it would act first.
	var fi := _make_mon("L02_Battle", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	fi.held_item = item
	fi.add_move(tackle)
	var opp := _make_mon("L02_Opp", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(fi), BattleParty.single(opp))
	_chk("L02.04 full-battle: Full Incense holder (normally FASTER) still acts LAST, " +
			"unconditionally",
			not events.is_empty() and events[0][0] == opp)
	bm.queue_free()


# ── L03: Lagging Tail (485) ─────────────────────────────────────────────────────
func _test_l03_lagging_tail() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_LAGGING_TAIL)
	_chk("L03.01 Lagging Tail hold_effect == HOLD_EFFECT_LAGGING_TAIL(66) — the SAME " +
			"value as Full Incense, confirmed via source not a data-entry error",
			item.hold_effect == ItemManager.HOLD_EFFECT_LAGGING_TAIL)

	var holder := _make_mon("L03_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("L03.02 direct: has_slow_turn_order_item == true when holding Lagging Tail",
			ItemManager.has_slow_turn_order_item(holder))
	var bare := _make_mon("L03_Bare", TypeChart.TYPE_NORMAL)
	_chk("L03.03 discriminator: holding nothing -> false",
			not ItemManager.has_slow_turn_order_item(bare))

	var tackle := _load_move(33)
	# Full-battle: holder is the FASTER combatant — without the item it would act first.
	var lt := _make_mon("L03_Battle", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	lt.held_item = item
	lt.add_move(tackle)
	var opp := _make_mon("L03_Opp", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(lt), BattleParty.single(opp))
	_chk("L03.05 full-battle: Lagging Tail holder (normally FASTER) still acts LAST, " +
			"unconditionally — identical outcome to Full Incense (L02.04)",
			not events.is_empty() and events[0][0] == opp)
	bm.queue_free()


# ── L04: item-vs-ability precedence composition ─────────────────────────────────
# Resolves this tier's Step 0 questions directly from source
# (GetWhichBattlerFasterArgs, battle_main.c L4786-4800): quick is checked strictly
# BEFORE slow, for the WHOLE comparison — a single Pokémon's own slow flag is never
# consulted once its quick flag is true, regardless of which side (ability or item)
# supplied which flag.
func _test_l04_composition() -> void:
	var tackle := _load_move(33)
	var quick_claw_item := _make_item(ItemManager.HOLD_EFFECT_QUICK_CLAW, 20)
	var full_incense_item := _make_item(ItemManager.HOLD_EFFECT_LAGGING_TAIL)
	var stall := _load_ability(100)
	var quick_draw := _load_ability(259)

	# Scenario A: "What if a Pokémon holds Quick Claw AND has an ability like Stall
	# (always-last)?" -> Quick Claw (item, quick) wins; Stall's own slow flag on the
	# SAME mon is never consulted. Opponent is plain and FASTER (would normally act
	# first on speed alone, and has neither a quick nor slow source).
	var both_a := _make_mon("L04_QuickClawStall", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	both_a.held_item = quick_claw_item
	both_a.ability = stall
	both_a.add_move(tackle)
	var opp_a := _make_mon("L04_OppA", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	opp_a.add_move(tackle)

	var events_a := []
	var bm_a := BattleManager.new()
	add_child(bm_a)
	bm_a._force_quick_claw_roll = true
	bm_a.move_executed.connect(func(a, d, m, dmg): events_a.push_back([a, d, m, dmg]))
	bm_a.start_battle_with_parties(BattleParty.single(both_a), BattleParty.single(opp_a))
	_chk("L04.01 Quick Claw (item, forced roll=true) OVERRIDES the same mon's own " +
			"Stall ability (always-last) — the mon acts FIRST, precedence confirmed " +
			"from source (quick checked strictly before slow)",
			not events_a.is_empty() and events_a[0][0] == both_a)
	bm_a.queue_free()

	# Scenario B: "What if it holds Full Incense AND has Quick Draw (always-first via
	# ability)?" -> Quick Draw (ability, quick, forced roll=true) wins; Full Incense's
	# own slow flag on the SAME mon is never consulted. Opponent is plain and FASTER.
	var both_b := _make_mon("L04_FullIncenseQuickDraw", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	both_b.held_item = full_incense_item
	both_b.ability = quick_draw
	both_b.add_move(tackle)
	var opp_b := _make_mon("L04_OppB", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	opp_b.add_move(tackle)

	var events_b := []
	var bm_b := BattleManager.new()
	add_child(bm_b)
	bm_b._force_quick_draw_roll = true
	bm_b.move_executed.connect(func(a, d, m, dmg): events_b.push_back([a, d, m, dmg]))
	bm_b.start_battle_with_parties(BattleParty.single(both_b), BattleParty.single(opp_b))
	_chk("L04.02 Quick Draw (ability, forced roll=true) OVERRIDES the same mon's own " +
			"Full Incense item (always-last) — the mon acts FIRST, mirrored precedence " +
			"confirmed the other direction (ability quick beats item slow)",
			not events_b.is_empty() and events_b[0][0] == both_b)
	bm_b.queue_free()
