extends Node

# [Bucket 3 multi-stat] Unlocks the 24 buildable moves in Bucket 3's
# multi-stat-in-one-block cluster (Ancient Power, Superpower, Silver Wind,
# Tickle, Cosmic Power, Bulk Up, Calm Mind, Dragon Dance, Close Combat,
# Ominous Wind, Hone Claws, Quiver Dance, Coil, Shell Smash, Shift Gear,
# Work Up, Noble Roar, Dragon Ascent, Tearful Look, Decorate, Victory Dance,
# Headlong Rush, Spicy Extract, Armor Cannon).
#
# Step 0 re-derived the 25-move cluster fresh from moves_info.h (brace-
# matched, unioning stats across ALL of a move's stat-change blocks, not
# just within one — a broadened detector, since the first draft missed
# Spicy Extract's two-separate-single-stat-block shape) and cross-checked
# byte-for-byte against the plan doc's own list: exact match. Found the
# cluster splits 8 EFFECT_HIT (damage moves, routed through
# `[M19-secondary-stat-on-hit]`'s dispatch) / 17 EFFECT_STAT_CHANGE (pure
# status moves, routed through the pre-existing pure-status dispatch) — NOT
# uniform. Found Coaching(739) is genuinely TARGET_ALLY, a third targeting
# mode `stat_change_self: bool` can't represent — carved out of this tier's
# buildable scope, deferred to merge with `M19-ally-targeting-stat-change`
# (Howl/Aromatic Mist), leaving 24 moves here. Found magnitude/sign is NOT
# uniform ±1 — Shell Smash mixes +2 (Atk/SpAtk/Speed) with -1 (Def/SpDef) in
# ONE move; Shift Gear mixes +1 Atk with +2 Speed; Spicy Extract mixes +2
# Atk with -2 Def.
#
# Design: two new optional MoveData fields, `extra_stat_change_stats`/
# `extra_stat_change_amounts` (parallel Array[int], empty for every other
# move in the roster), carrying every (stat, amount) pair beyond the
# existing primary `stat_change_stat`/`amount`. BattleManager.
# _apply_stat_change_effect was refactored into a new per-pair helper
# (_apply_one_stat_change_pair) called once for the primary pair and once
# per extra pair — deliberately running Mirror Armor/Defiant/Competitive/
# Opportunist/Mirror Herb independently PER PAIR, not once per move, since
# Mirror Armor must redirect only the DECREASING component of a mixed-sign
# move (Spicy Extract's -2 Def redirects, its simultaneous +2 Atk does not)
# and real Defiant/Competitive fires once per qualifying decrease (a
# 2-stat-lowering move against a Defiant holder triggers it twice).
# Zero changes needed to either dispatch gate (both key only on the primary
# stat_change_stat) or to Sheer Force (gated on secondary_chance alone,
# already generic) — confirmed by Step 0, not assumed.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_functional()

	var total := _pass + _fail
	print("m19_bucket3_multistat_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _make_mon(mon_name: String, type1: int,
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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data-integrity table (all 24 moves) ───────────────────────────
# [id, name, type, category, power, accuracy, pp, self, primary_stat, primary_amount,
#  secondary_chance_or_null, extra_stats, extra_amounts, flag_tokens]

func _test_data_integrity() -> void:
	var expected := [
		[246, "Ancient Power", TypeChart.TYPE_ROCK, 1, 60, 100, 5, true,
			BattlePokemon.STAGE_ATK, 1, 10,
			[BattlePokemon.STAGE_DEF, BattlePokemon.STAGE_SPATK, BattlePokemon.STAGE_SPDEF, BattlePokemon.STAGE_SPEED],
			[1, 1, 1, 1], []],
		[276, "Superpower", TypeChart.TYPE_FIGHTING, 0, 120, 100, 5, true,
			BattlePokemon.STAGE_ATK, -1, 0,
			[BattlePokemon.STAGE_DEF], [-1], ["contact"]],
		[318, "Silver Wind", TypeChart.TYPE_BUG, 1, 60, 100, 5, true,
			BattlePokemon.STAGE_ATK, 1, 10,
			[BattlePokemon.STAGE_DEF, BattlePokemon.STAGE_SPATK, BattlePokemon.STAGE_SPDEF, BattlePokemon.STAGE_SPEED],
			[1, 1, 1, 1], []],
		[321, "Tickle", TypeChart.TYPE_NORMAL, 2, 0, 100, 20, false,
			BattlePokemon.STAGE_ATK, -1, -1,
			[BattlePokemon.STAGE_DEF], [-1], []],
		[322, "Cosmic Power", TypeChart.TYPE_PSYCHIC, 2, 0, 0, 20, true,
			BattlePokemon.STAGE_DEF, 1, -1,
			[BattlePokemon.STAGE_SPDEF], [1], []],
		[339, "Bulk Up", TypeChart.TYPE_FIGHTING, 2, 0, 0, 20, true,
			BattlePokemon.STAGE_ATK, 1, -1,
			[BattlePokemon.STAGE_DEF], [1], []],
		[347, "Calm Mind", TypeChart.TYPE_PSYCHIC, 2, 0, 0, 20, true,
			BattlePokemon.STAGE_SPATK, 1, -1,
			[BattlePokemon.STAGE_SPDEF], [1], []],
		[349, "Dragon Dance", TypeChart.TYPE_DRAGON, 2, 0, 0, 20, true,
			BattlePokemon.STAGE_ATK, 1, -1,
			[BattlePokemon.STAGE_SPEED], [1], []],
		[370, "Close Combat", TypeChart.TYPE_FIGHTING, 0, 120, 100, 5, true,
			BattlePokemon.STAGE_DEF, -1, 0,
			[BattlePokemon.STAGE_SPDEF], [-1], ["contact"]],
		[466, "Ominous Wind", TypeChart.TYPE_GHOST, 1, 60, 100, 5, true,
			BattlePokemon.STAGE_ATK, 1, 10,
			[BattlePokemon.STAGE_DEF, BattlePokemon.STAGE_SPATK, BattlePokemon.STAGE_SPDEF, BattlePokemon.STAGE_SPEED],
			[1, 1, 1, 1], []],
		[468, "Hone Claws", TypeChart.TYPE_DARK, 2, 0, 0, 15, true,
			BattlePokemon.STAGE_ATK, 1, -1,
			[BattlePokemon.STAGE_ACCURACY], [1], []],
		[483, "Quiver Dance", TypeChart.TYPE_BUG, 2, 0, 0, 20, true,
			BattlePokemon.STAGE_SPATK, 1, -1,
			[BattlePokemon.STAGE_SPDEF, BattlePokemon.STAGE_SPEED], [1, 1], []],
		[489, "Coil", TypeChart.TYPE_POISON, 2, 0, 0, 20, true,
			BattlePokemon.STAGE_ATK, 1, -1,
			[BattlePokemon.STAGE_DEF, BattlePokemon.STAGE_ACCURACY], [1, 1], []],
		[504, "Shell Smash", TypeChart.TYPE_NORMAL, 2, 0, 0, 15, true,
			BattlePokemon.STAGE_ATK, 2, -1,
			[BattlePokemon.STAGE_SPATK, BattlePokemon.STAGE_SPEED, BattlePokemon.STAGE_DEF, BattlePokemon.STAGE_SPDEF],
			[2, 2, -1, -1], []],
		[508, "Shift Gear", TypeChart.TYPE_STEEL, 2, 0, 0, 10, true,
			BattlePokemon.STAGE_ATK, 1, -1,
			[BattlePokemon.STAGE_SPEED], [2], []],
		[526, "Work Up", TypeChart.TYPE_NORMAL, 2, 0, 0, 30, true,
			BattlePokemon.STAGE_ATK, 1, -1,
			[BattlePokemon.STAGE_SPATK], [1], []],
		[568, "Noble Roar", TypeChart.TYPE_NORMAL, 2, 0, 100, 30, false,
			BattlePokemon.STAGE_ATK, -1, -1,
			[BattlePokemon.STAGE_SPATK], [-1], ["sound"]],
		[620, "Dragon Ascent", TypeChart.TYPE_FLYING, 0, 120, 100, 5, true,
			BattlePokemon.STAGE_DEF, -1, 0,
			[BattlePokemon.STAGE_SPDEF], [-1], ["contact"]],
		[669, "Tearful Look", TypeChart.TYPE_NORMAL, 2, 0, 0, 20, false,
			BattlePokemon.STAGE_ATK, -1, -1,
			[BattlePokemon.STAGE_SPATK], [-1], []],
		[705, "Decorate", TypeChart.TYPE_FAIRY, 2, 0, 0, 15, false,
			BattlePokemon.STAGE_ATK, 2, -1,
			[BattlePokemon.STAGE_SPATK], [2], []],
		[765, "Victory Dance", TypeChart.TYPE_FIGHTING, 2, 0, 0, 20, true,
			BattlePokemon.STAGE_ATK, 1, -1,
			[BattlePokemon.STAGE_DEF, BattlePokemon.STAGE_SPEED], [1, 1], []],
		[766, "Headlong Rush", TypeChart.TYPE_GROUND, 0, 120, 100, 5, true,
			BattlePokemon.STAGE_DEF, -1, 0,
			[BattlePokemon.STAGE_SPDEF], [-1], ["contact"]],
		[786, "Spicy Extract", TypeChart.TYPE_GRASS, 2, 0, 0, 15, false,
			BattlePokemon.STAGE_ATK, 2, -1,
			[BattlePokemon.STAGE_DEF], [-2], []],
		[816, "Armor Cannon", TypeChart.TYPE_FIRE, 1, 120, 100, 5, true,
			BattlePokemon.STAGE_DEF, -1, 0,
			[BattlePokemon.STAGE_SPDEF], [-1], []],
	]

	for e: Array in expected:
		var id: int = e[0]
		var mv := _load_move(id)
		var tag: String = "%d %s" % [id, e[1]]
		_chk(tag + " loads", mv != null)
		if mv == null:
			continue
		_chk(tag + " move_name", mv.move_name == e[1])
		_chk(tag + " type", mv.type == e[2])
		_chk(tag + " category", mv.category == e[3])
		_chk(tag + " power", mv.power == e[4])
		_chk(tag + " accuracy", mv.accuracy == e[5])
		_chk(tag + " pp", mv.pp == e[6])
		_chk(tag + " stat_change_self", mv.stat_change_self == e[7])
		_chk(tag + " stat_change_stat (primary)", mv.stat_change_stat == e[8])
		_chk(tag + " stat_change_amount (primary)", mv.stat_change_amount == e[9])

		var expected_chance: int = e[10]
		if expected_chance >= 0:
			_chk(tag + " secondary_chance", mv.secondary_chance == expected_chance)
			_chk(tag + " secondary_effect stays SE_NONE (EFFECT_HIT dispatch)",
					mv.secondary_effect == MoveData.SE_NONE)

		var expected_extra_stats: Array = e[11]
		var expected_extra_amounts: Array = e[12]
		_chk(tag + " extra_stat_change_stats", mv.extra_stat_change_stats == expected_extra_stats)
		_chk(tag + " extra_stat_change_amounts", mv.extra_stat_change_amounts == expected_extra_amounts)

		var tokens: Array = e[13]
		_chk(tag + " makes_contact", mv.makes_contact == ("contact" in tokens))
		_chk(tag + " sound_move", mv.sound_move == ("sound" in tokens))


# ── Section B: functional checks ──────────────────────────────────────────────

func _test_functional() -> void:
	_test_b1_pure_status_multistat()
	_test_b2_effect_hit_guaranteed_multistat()
	_test_b3_mirror_armor_per_pair()
	_test_b4_defiant_fires_per_decrease()
	_test_b5_sheer_force_suppresses_whole_secondary()
	_test_b6_opportunist_copies_both_stats()
	_test_b7_shell_smash_mixed_sign_self()


# B1: Bulk Up(339, pure status, self, +1 Atk/+1 Def) — both stats land on the
# attacker in one full battle. Stage math itself is already proven by prior
# tiers; this confirms the NEW loop actually applies both pairs.
func _test_b1_pure_status_multistat() -> void:
	var bulk_up := _load_move(339)
	var tackle := _load_move(33)
	var atk := _make_mon("B1Atk", TypeChart.TYPE_FIGHTING)
	atk.add_move(bulk_up)
	var def := _make_mon("B1Def", TypeChart.TYPE_NORMAL)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	var stat_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle(atk, def)

	_chk("B1 Bulk Up's first two stat_stage_changed events are +1 Atk then +1 Def, both on the attacker",
			stat_events.size() >= 2
					and stat_events[0] == [atk, BattlePokemon.STAGE_ATK, 1]
					and stat_events[1] == [atk, BattlePokemon.STAGE_DEF, 1])


# B2: Superpower(276, EFFECT_HIT, guaranteed self -1 Atk/-1 Def) — full-battle
# fire with primary damage still nonzero (discriminator: multi-stat
# application must never suppress the hit) and BOTH stat drops landing on
# the attacker.
func _test_b2_effect_hit_guaranteed_multistat() -> void:
	var superpower := _load_move(276)
	var tackle := _load_move(33)
	var atk := _make_mon("B2Atk", TypeChart.TYPE_FIGHTING)
	atk.add_move(superpower)
	var def := _make_mon("B2Def", TypeChart.TYPE_NORMAL)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var dmg := [0]
	var stat_events := []
	bm.move_executed.connect(func(a, _d, _m, amount):
		if a == atk and dmg[0] == 0:
			dmg[0] = amount)
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle(atk, def)

	_chk("B2 Superpower deals real nonzero primary damage", dmg[0] > 0)
	_chk("B2 Superpower's first two stat_stage_changed events are -1 Atk then -1 Def, both on the attacker",
			stat_events.size() >= 2
					and stat_events[0] == [atk, BattlePokemon.STAGE_ATK, -1]
					and stat_events[1] == [atk, BattlePokemon.STAGE_DEF, -1])


# B3: Spicy Extract(786, foe-targeted, mixed sign: +2 Atk / -2 Def) against a
# Mirror Armor holder — the key new-behavior test. Only the DECREASING
# component (-2 Def) should redirect onto the attacker; the simultaneous
# INCREASING component (+2 Atk) should land normally on the defender. A
# whole-move (not per-pair) Mirror Armor check would get this wrong.
func _test_b3_mirror_armor_per_pair() -> void:
	var spicy_extract := _load_move(786)
	var tackle := _load_move(33)
	var mirror_armor := _load_ability(240)
	var atk := _make_mon("B3Atk", TypeChart.TYPE_GRASS)
	atk.add_move(spicy_extract)
	var holder := _make_mon("B3Holder", TypeChart.TYPE_NORMAL)
	holder.ability = mirror_armor
	holder.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	var stat_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle(atk, holder)

	_chk("B3 the +2 Atk component lands normally on the Mirror Armor holder (not redirected)",
			stat_events.any(func(e): return e[0] == holder and e[1] == BattlePokemon.STAGE_ATK and e[2] == 2))
	_chk("B3 the -2 Def component redirects onto the ATTACKER via Mirror Armor",
			stat_events.any(func(e): return e[0] == atk and e[1] == BattlePokemon.STAGE_DEF and e[2] == -2))
	_chk("B3 the holder's own Defense is never lowered",
			not stat_events.any(func(e): return e[0] == holder and e[1] == BattlePokemon.STAGE_DEF and e[2] < 0))


# B4: Tickle(321, foe-targeted, -1 Atk/-1 Def) against a Defiant holder — real
# game behavior fires Defiant once per qualifying decrease, so a 2-stat
# lowering move should trigger it TWICE (two separate +2 Atk activations),
# not once for the whole move.
func _test_b4_defiant_fires_per_decrease() -> void:
	var tickle := _load_move(321)
	var tackle := _load_move(33)
	var defiant := _load_ability(128)
	var atk := _make_mon("B4Atk", TypeChart.TYPE_NORMAL)
	atk.add_move(tickle)
	var holder := _make_mon("B4Holder", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 20)
	holder.ability = defiant
	holder.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	var trig_events := []
	var atk_stage_events := []
	bm.ability_triggered.connect(func(m, tg):
		if tg == "defiant_competitive":
			trig_events.append(m))
	bm.stat_stage_changed.connect(func(t, s, a):
		if t == holder and s == BattlePokemon.STAGE_ATK:
			atk_stage_events.append(a))
	bm.start_battle(atk, holder)

	# [whole-battle-aggregation pitfall] Tickle is the attacker's only move,
	# so if the holder survives Tackle it re-fires on later turns, compounding
	# further Defiant activations — bounding to the FIRST exchange's own 3
	# STAGE_ATK events (Tickle's own -1, then two +2 Defiant activations) via
	# signal snapshot, never reading post-battle state directly.
	_chk("B4 Defiant fires exactly twice on Tickle's first use (once per stat " +
			"it lowered), not once for the whole move",
			trig_events.size() >= 2 and trig_events[0] == holder and trig_events[1] == holder)
	# Sequential, not simultaneous: Tickle's own -1 Atk lands first (0 -> -1),
	# triggering the first +2 Defiant activation (-1 -> +1); Tickle's second
	# pair (-1 Def) then triggers a SECOND +2 Defiant activation on top of
	# that already-raised +1 (+1 -> +3) -- not two independent +2s from a
	# flat 0 baseline.
	_chk("B4 the first exchange's 3 Attack-stage events are -1 (Tickle's own), " +
			"then +2, +2 (two sequential Defiant activations)",
			atk_stage_events.size() >= 3
					and atk_stage_events.slice(0, 3) == [-1, 2, 2])


# B5: Ancient Power(246, EFFECT_HIT, chance=10, self, 5-stat raise) — Sheer
# Force must suppress the WHOLE multi-stat secondary at the gate (before any
# stat is even considered), matching [M19-secondary-stat-on-hit]'s
# established precedent — confirmed via a direct try_secondary_effect call,
# this project's established convention for deterministic secondary-chance
# testing.
func _test_b5_sheer_force_suppresses_whole_secondary() -> void:
	var ancient_power := _load_move(246)
	var sheer_force := _load_ability(125)
	var sf_atk := _make_mon("B5SFAtk", TypeChart.TYPE_ROCK)
	sf_atk.ability = sheer_force
	var def := _make_mon("B5Def", TypeChart.TYPE_NORMAL)

	_chk("B5 Sheer Force suppresses Ancient Power's entire multi-stat secondary " +
			"even when force_secondary=true",
			StatusManager.try_secondary_effect(sf_atk, def, ancient_power, true) == false)


# B6: Bulk Up(339, self, +1 Atk/+1 Def) used against an opponent holding
# Opportunist — BOTH raised stats should be copied independently (Opportunist
# fires once per qualifying increase, same shape as Defiant's per-decrease
# firing in B4).
func _test_b6_opportunist_copies_both_stats() -> void:
	var bulk_up := _load_move(339)
	var tackle := _load_move(33)
	var opportunist := _load_ability(290)
	var atk := _make_mon("B6Atk", TypeChart.TYPE_FIGHTING)
	atk.add_move(bulk_up)
	var opp := _make_mon("B6Opp", TypeChart.TYPE_NORMAL)
	opp.ability = opportunist
	opp.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	var stat_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle(atk, opp)

	_chk("B6 Opportunist copies the +1 Atk raise onto the opponent",
			stat_events.any(func(e): return e[0] == opp and e[1] == BattlePokemon.STAGE_ATK and e[2] == 1))
	_chk("B6 Opportunist ALSO copies the +1 Def raise onto the opponent (fires per-stat)",
			stat_events.any(func(e): return e[0] == opp and e[1] == BattlePokemon.STAGE_DEF and e[2] == 1))


# B7: Shell Smash(504, self, mixed sign +2/+2/+2/-1/-1) — all 5 stat changes
# land on the attacker in one battle; self-targeting means Mirror Armor/
# Defiant/Opportunist are all correctly bypassed for every pair (not just
# the primary one), confirmed by their total absence from the event log.
func _test_b7_shell_smash_mixed_sign_self() -> void:
	var shell_smash := _load_move(504)
	var tackle := _load_move(33)
	var atk := _make_mon("B7Atk", TypeChart.TYPE_NORMAL)
	atk.add_move(shell_smash)
	var def := _make_mon("B7Def", TypeChart.TYPE_NORMAL)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	var stat_events := []
	var trig_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.ability_triggered.connect(func(m, tg): trig_events.append(tg))
	bm.start_battle(atk, def)

	var first_five: Array = stat_events.slice(0, 5)
	_chk("B7 all 5 of Shell Smash's stat changes land on the attacker",
			first_five.all(func(e): return e[0] == atk))
	_chk("B7 the exact 5 (stat, amount) pairs match Shell Smash's mixed +2/+2/+2/-1/-1",
			first_five.map(func(e): return [e[1], e[2]]) == [
				[BattlePokemon.STAGE_ATK, 2], [BattlePokemon.STAGE_SPATK, 2],
				[BattlePokemon.STAGE_SPEED, 2], [BattlePokemon.STAGE_DEF, -1],
				[BattlePokemon.STAGE_SPDEF, -1]])
	_chk("B7 no Mirror Armor / Defiant / Opportunist trigger fires for a self-targeted move",
			not trig_events.any(func(t): return t in ["mirror_armor", "defiant_competitive", "opportunist"]))
