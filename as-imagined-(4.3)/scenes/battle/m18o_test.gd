extends Node

# M18o test suite — Survive-lethal-hit items (Focus Sash, Focus Band)
#
# Ground truth: pokeemerald-expansion
#   include/constants/items.h -- ITEM_FOCUS_SASH=481, ITEM_FOCUS_BAND=469.
#   src/battle_util.c :: GetAdjustedDamage (L7954-8003) -- the SAME shared
#     endure-check function this project's existing Sturdy already lives in
#     ([M17n-5], battle_manager.gd). Confirmed a strict `else if` CHAIN, first
#     match wins: Endure -> False Swipe -> Sturdy -> Focus Band -> Focus Sash
#     -> affection (only Sturdy/Focus Band/Focus Sash reachable in this
#     project). A Pokemon with BOTH Sturdy and a held Focus Sash never even
#     reaches the Focus Sash branch -- it is not consumed, not "wasted,"
#     simply untouched by that hit.
#   Focus Band: holdEffectParam=10 (10%), PROBABILISTIC, NO HP gate at all --
#     can trigger from any starting HP. NOT consumed -- repeatable every hit.
#   Focus Sash: NO holdEffectParam/roll in source at all -- purely
#     IsBattlerAtMaxHp (the SAME gate Sturdy uses), unconditional given full
#     HP. SINGLE-USE -- corroborated by
#     docs/changelogs/1.8.x/1.8.4.md's own "Focus Sash but not consuming the
#     item" bugfix entry (no Focus Band equivalent exists, since it's simply
#     never consumed).
#   Timing-bug check (per CLAUDE.md's current_hp-vs-.fainted convention):
#     confirmed no analogous bug -- this whole chain reads target.current_hp
#     BEFORE it's reduced by the hit, a pre-application lethality prediction
#     on the target's own still-current HP, not a post-hit aliveness check on
#     a different Pokemon.
#
# Docs: docs/m18_subtier_plan.md (M18o section) -- 2 items, no cross-tier
# dependencies. Extends the existing Sturdy elif chain in _do_damaging_hit
# directly (battle_manager.gd) rather than a parallel mechanism. New
# ItemManager.focus_band_activates()/holds_focus_sash(); new
# _force_focus_band_roll seam; new generic item_effect_triggered signal
# (Focus Band isn't consumed, so item_consumed doesn't fit).
#
# Sections: O01 Focus Sash (incl. the not-at-full-HP discriminator and the
# Sturdy-precedence/non-consumption proof), O02 Focus Band (incl. a
# statistical rate sample, since this item's core mechanic is genuinely
# probabilistic -- multi-rerun required for this suite specifically).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_o01_focus_sash()
	_test_o02_focus_band()

	var total := _pass + _fail
	print("m18o_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18n_test.gd's established pattern) ───────────────────────

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
	return BattlePokemon.from_species(sp, 50)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


# ── O01: Focus Sash (481) ────────────────────────────────────────────────────────
func _test_o01_focus_sash() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_FOCUS_SASH)
	_chk("O01.01 Focus Sash hold_effect == HOLD_EFFECT_FOCUS_SASH(67)",
			item.hold_effect == ItemManager.HOLD_EFFECT_FOCUS_SASH)

	var holder := _make_mon("O01_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("O01.02 direct: holds_focus_sash == true when holding Focus Sash",
			ItemManager.holds_focus_sash(holder))
	var bare := _make_mon("O01_Bare", TypeChart.TYPE_NORMAL)
	_chk("O01.03 discriminator: holding nothing -> false",
			not ItemManager.holds_focus_sash(bare))

	var double_edge := _load_move(38)

	# Full-battle: holder at FULL HP (tiny base_hp so a normal hit is clearly
	# lethal) survives an otherwise-lethal hit at exactly 1 HP, and the item is
	# consumed.
	var atk1 := _make_mon("O01_Atk1", TypeChart.TYPE_NORMAL, 100, 255, 60, 60, 60, 100)
	atk1.add_move(double_edge)
	var fs_holder1 := _make_mon("O01_Holder1", TypeChart.TYPE_NORMAL, 1, 60, 60, 60, 60, 40)
	fs_holder1.held_item = item
	fs_holder1.add_move(double_edge)

	var triggered1 := []
	var consumed1 := []
	var hp_after_hit1 := []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_roll = 100
	bm1._force_crit = false
	# Snapshot HP via move_executed, not post-battle state (per CLAUDE.md's
	# whole-battle-aggregation convention): the battle continues past turn 1 —
	# fs_holder1 survives at 1 HP but then attacks back on its own turn, and
	# faints from ITS OWN Double-Edge recoil moments later (Focus Sash doesn't
	# protect against self-recoil). Reading fs_holder1.current_hp/.fainted
	# after the whole battle would see that later state, not the turn-1
	# survival this test is actually about. item_effect_triggered itself fires
	# BEFORE target.current_hp is actually reduced (it only caps the local
	# `damage` variable that hasn't been applied yet) — move_executed fires
	# right after the real HP write, so it's the correct signal to snapshot
	# from, not item_effect_triggered.
	bm1.item_effect_triggered.connect(func(m, k): triggered1.push_back([m, k]))
	bm1.item_consumed.connect(func(m, it): consumed1.push_back(m))
	bm1.move_executed.connect(func(a, d, m, dmg): hp_after_hit1.push_back(d.current_hp))
	bm1.start_battle_with_parties(BattleParty.single(atk1), BattleParty.single(fs_holder1))
	_chk("O01.04 full-battle: Focus Sash holder at full HP survives an " +
			"otherwise-lethal hit at exactly 1 HP",
			not hp_after_hit1.is_empty() and hp_after_hit1[0] == 1)
	_chk("O01.05 item_effect_triggered fires with 'focus_sash'",
			triggered1.any(func(e): return e[0] == fs_holder1 and e[1] == "focus_sash"))
	_chk("O01.06 the item is CONSUMED (single-use)",
			consumed1.has(fs_holder1) and fs_holder1.held_item == null)
	bm1.queue_free()

	# Discriminator: the holder is NOT at full HP when hit -> does NOT trigger,
	# faints normally.
	var atk2 := _make_mon("O01_Atk2", TypeChart.TYPE_NORMAL, 100, 255, 60, 60, 60, 100)
	atk2.add_move(double_edge)
	var fs_holder2 := _make_mon("O01_Holder2", TypeChart.TYPE_NORMAL, 1, 60, 60, 60, 60, 40)
	fs_holder2.held_item = item
	fs_holder2.add_move(double_edge)
	fs_holder2.current_hp = fs_holder2.max_hp - 1  # already off full HP

	var triggered2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.item_effect_triggered.connect(func(m, k): triggered2.push_back([m, k]))
	bm2.start_battle_with_parties(BattleParty.single(atk2), BattleParty.single(fs_holder2))
	_chk("O01.07 discriminator: not at full HP -> Focus Sash does NOT trigger, " +
			"the holder faints normally",
			fs_holder2.fainted and not triggered2.any(func(e): return e[0] == fs_holder2))
	bm2.queue_free()

	# Sturdy-precedence: a holder with BOTH Sturdy and Focus Sash -> Sturdy
	# fires FIRST (the elif chain never reaches Focus Sash), so the item is
	# NOT consumed and NOT triggered -- confirmed untouched, not "wasted."
	var sturdy := _load_ability(5)
	var atk3 := _make_mon("O01_Atk3", TypeChart.TYPE_NORMAL, 100, 255, 60, 60, 60, 100)
	atk3.add_move(double_edge)
	var both_holder3 := _make_mon("O01_Holder3", TypeChart.TYPE_NORMAL, 1, 60, 60, 60, 60, 40)
	both_holder3.ability = sturdy
	both_holder3.held_item = item
	both_holder3.add_move(double_edge)

	var triggered3 := []
	var ability_triggered3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.item_effect_triggered.connect(func(m, k): triggered3.push_back([m, k]))
	bm3.ability_triggered.connect(func(m, k): ability_triggered3.push_back([m, k]))
	bm3.start_battle_with_parties(BattleParty.single(atk3), BattleParty.single(both_holder3))
	_chk("O01.08 CORRECTION-confirming: Sturdy fires (not Focus Sash) when a " +
			"Pokemon has both",
			ability_triggered3.any(func(e): return e[0] == both_holder3 and e[1] == "sturdy"))
	_chk("O01.09 CORRECTION-confirming: Focus Sash is NOT triggered when " +
			"Sturdy already fired -- the elif chain never reaches it",
			not triggered3.any(func(e): return e[0] == both_holder3 and e[1] == "focus_sash"))
	_chk("O01.10 CORRECTION-confirming: Focus Sash is NOT consumed -- untouched, " +
			"not 'wasted', still held after the hit",
			both_holder3.held_item == item)
	bm3.queue_free()


# ── O02: Focus Band (469) ─────────────────────────────────────────────────────────
func _test_o02_focus_band() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_FOCUS_BAND, 10)
	_chk("O02.01 Focus Band hold_effect == HOLD_EFFECT_FOCUS_BAND(38), param == 10",
			item.hold_effect == ItemManager.HOLD_EFFECT_FOCUS_BAND and item.hold_effect_param == 10)

	var holder := _make_mon("O02_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("O02.02 direct: forced_roll=true -> activates",
			ItemManager.focus_band_activates(holder, false, true))
	_chk("O02.03 direct: forced_roll=false -> does not activate",
			not ItemManager.focus_band_activates(holder, false, false))
	var bare := _make_mon("O02_Bare", TypeChart.TYPE_NORMAL)
	_chk("O02.04 discriminator: holding nothing never activates, even forced_roll=true",
			not ItemManager.focus_band_activates(bare, false, true))

	var double_edge := _load_move(38)

	# Full-battle: forced_roll=true, holder deliberately NOT at full HP (proves
	# there is no HP gate, unlike Focus Sash) -> survives at exactly 1 HP, item
	# is NOT consumed.
	var atk1 := _make_mon("O02_Atk1", TypeChart.TYPE_NORMAL, 100, 255, 60, 60, 60, 100)
	atk1.add_move(double_edge)
	var fb_holder1 := _make_mon("O02_Holder1", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	fb_holder1.held_item = item
	fb_holder1.add_move(double_edge)
	fb_holder1.current_hp = 5  # far from full HP -- Focus Sash would never trigger here

	var triggered1 := []
	var consumed1 := []
	var hp_after_hit1 := []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1._force_focus_band_roll = true
	# Snapshot HP via move_executed, not item_effect_triggered or post-battle
	# state — same reasoning as O01.04: item_effect_triggered fires BEFORE
	# target.current_hp is actually reduced (it only caps the local `damage`
	# variable), and post-battle state would reflect later turns (the seam
	# stays forced true, but fb_holder1 faints from its OWN Double-Edge recoil
	# once it counters, ending the battle) rather than this turn-1 survival.
	bm1.item_effect_triggered.connect(func(m, k): triggered1.push_back([m, k]))
	bm1.item_consumed.connect(func(m, it): consumed1.push_back(m))
	bm1.move_executed.connect(func(a, d, m, dmg): hp_after_hit1.push_back(d.current_hp))
	bm1.start_battle_with_parties(BattleParty.single(atk1), BattleParty.single(fb_holder1))
	_chk("O02.05 full-battle: Focus Band (forced roll=true) survives an " +
			"otherwise-lethal hit at exactly 1 HP, despite NOT being at full HP",
			not hp_after_hit1.is_empty() and hp_after_hit1[0] == 1)
	_chk("O02.06 item_effect_triggered fires with 'focus_band'",
			triggered1.any(func(e): return e[0] == fb_holder1 and e[1] == "focus_band"))
	_chk("O02.07 CORRECTION-confirming: the item is NOT consumed, unlike Focus " +
			"Sash -- still held after the hit",
			not consumed1.has(fb_holder1) and fb_holder1.held_item == item)
	bm1.queue_free()

	# Discriminator: forced_roll=false -> faints normally.
	var atk2 := _make_mon("O02_Atk2", TypeChart.TYPE_NORMAL, 100, 255, 60, 60, 60, 100)
	atk2.add_move(double_edge)
	var fb_holder2 := _make_mon("O02_Holder2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	fb_holder2.held_item = item
	fb_holder2.add_move(double_edge)
	fb_holder2.current_hp = 5

	var triggered2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2._force_focus_band_roll = false
	bm2.item_effect_triggered.connect(func(m, k): triggered2.push_back([m, k]))
	bm2.start_battle_with_parties(BattleParty.single(atk2), BattleParty.single(fb_holder2))
	_chk("O02.08 discriminator: forced roll=false -> the holder faints normally",
			fb_holder2.fainted and not triggered2.any(func(e): return e[0] == fb_holder2))
	bm2.queue_free()

	# Statistical: unforced roll, observed rate near the confirmed 10% (n=3000,
	# per [M17n-5]/[M18e]/[M18k]'s established tolerance-band pattern) --
	# Focus Band's core mechanic is genuinely probabilistic, so this suite
	# requires multi-rerun stability, unlike M18o's other deterministic checks.
	var n := 3000
	var fires := 0
	for _i in range(n):
		if ItemManager.focus_band_activates(holder, false, null):
			fires += 1
	var rate: float = float(fires) / n
	_chk("O02.09 unforced observed trigger rate is near the expected 10%% " +
			"(n=%d, observed=%.3f)" % [n, rate],
			rate > 0.06 and rate < 0.14)
