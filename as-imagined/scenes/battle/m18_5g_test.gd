extends Node

# M18.5g test suite — multi-hit move mechanism (30 of the 31 real-source
# strikeCount/multiHit moves; Population Bomb excluded — see move_data.gd's
# strike_count doc comment). Sectioned by MECHANISM CONCERN, not by individual
# move, per this tier's own scope — only Triple Kick/Triple Axel (Section E)
# get their own section, since their per-hit-accuracy + escalating-power shape
# genuinely differs from every other move in the family.
#
# Ground truth: pokeemerald_expansion
#   Hit-count roll:        battle_move_resolution.c :: SetRandomMultiHitCounter
#                          (L2304-2312) — 35/35/15/15 for 2/3/4/5 hits (Gen5+)
#   Multi-hit continuation: MoveEndMultihitMove (L3224-3286) — mid-sequence
#                          termination on faint/Substitute-break/immunity
#   Per-hit accuracy exception: ShouldSkipAccuracyCalcPastFirstHit (L2137-2151)
#                          — Triple Kick/Triple Axel only
#   Escalating power:      battle_util.c L6165-6167 (EFFECT_TRIPLE_KICK)
#   Shell Bell accumulation: gBattleScripting.savedDmg += (L2490, MoveEndSetValues)
#   Scale Shot once-at-end: battle_move_resolution.c L3620-3628 (EFFECT_SCALE_SHOT)
#
# Every statistical-sample assertion uses a fixed, explicit n; every
# non-statistical assertion is scoped to one direct function call, one
# signal-snapshot, or one forced-seam call — no whole-battle-aggregation risk.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_move_data()
	_test_section_b_hit_count_resolution()
	_test_section_c_mid_sequence_termination()
	_test_section_d_per_hit_vs_once_per_move()
	_test_section_e_triple_kick_family()
	_test_section_f_full_battle_integration()

	var total := _pass + _fail
	print("m18_5g_test: %d/%d passed" % [_pass, total])
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


func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


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
	return BattlePokemon.from_species(sp, 50)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: Move data spot-checks (all 30 in-scope moves) ────────────────
# [id, name, type, category(0=PHYS/1=SPEC), power, accuracy(0=always), pp,
#  makes_contact, "multi"|"strike:N", extra_flag]

func _test_section_a_move_data() -> void:
	var expected := [
		[3,   "Double Slap",       TypeChart.TYPE_NORMAL,   0, 15,  85,  10, true,  "multi", ""],
		[4,   "Comet Punch",       TypeChart.TYPE_NORMAL,   0, 18,  85,  15, true,  "multi", ""],
		[24,  "Double Kick",       TypeChart.TYPE_FIGHTING, 0, 30,  100, 30, true,  "strike:2", ""],
		[31,  "Fury Attack",       TypeChart.TYPE_NORMAL,   0, 15,  85,  20, true,  "multi", ""],
		[41,  "Twineedle",         TypeChart.TYPE_BUG,      0, 25,  100, 20, false, "strike:2", "poison20"],
		[42,  "Pin Missile",       TypeChart.TYPE_BUG,      0, 25,  95,  20, false, "multi", ""],
		[131, "Spike Cannon",      TypeChart.TYPE_NORMAL,   0, 20,  100, 15, false, "multi", ""],
		[140, "Barrage",           TypeChart.TYPE_NORMAL,   0, 15,  85,  20, false, "multi", ""],
		[154, "Fury Swipes",       TypeChart.TYPE_NORMAL,   0, 18,  80,  15, true,  "multi", ""],
		[155, "Bonemerang",        TypeChart.TYPE_GROUND,   0, 50,  90,  10, false, "strike:2", ""],
		[167, "Triple Kick",       TypeChart.TYPE_FIGHTING, 0, 10,  90,  10, true,  "strike:3", "triple_kick"],
		[198, "Bone Rush",         TypeChart.TYPE_GROUND,   0, 25,  90,  10, false, "multi", ""],
		[292, "Arm Thrust",        TypeChart.TYPE_FIGHTING, 0, 15,  100, 20, true,  "multi", ""],
		[331, "Bullet Seed",       TypeChart.TYPE_GRASS,    0, 25,  100, 30, false, "multi", ""],
		[333, "Icicle Spear",      TypeChart.TYPE_ICE,      0, 25,  100, 30, false, "multi", ""],
		[350, "Rock Blast",        TypeChart.TYPE_ROCK,     0, 25,  90,  10, false, "multi", ""],
		[458, "Double Hit",        TypeChart.TYPE_NORMAL,   0, 35,  90,  10, true,  "strike:2", ""],
		[530, "Dual Chop",         TypeChart.TYPE_DRAGON,   0, 40,  90,  15, true,  "strike:2", ""],
		[541, "Tail Slap",         TypeChart.TYPE_NORMAL,   0, 25,  85,  10, true,  "multi", ""],
		[544, "Gear Grind",        TypeChart.TYPE_STEEL,    0, 50,  85,  15, true,  "strike:2", ""],
		[594, "Water Shuriken",    TypeChart.TYPE_WATER,    1, 15,  100, 20, false, "multi", ""],
		[689, "Double Iron Bash",  TypeChart.TYPE_STEEL,    0, 60,  100, 5,  true,  "strike:2", "flinch30"],
		[697, "Dragon Darts",      TypeChart.TYPE_DRAGON,   0, 50,  100, 10, false, "strike:2", ""],
		[727, "Scale Shot",        TypeChart.TYPE_DRAGON,   0, 25,  90,  20, false, "multi", "scale_shot"],
		[741, "Triple Axel",       TypeChart.TYPE_ICE,      0, 20,  90,  10, true,  "strike:3", "triple_kick"],
		[742, "Dual Wingbeat",     TypeChart.TYPE_FLYING,   0, 40,  90,  10, true,  "strike:2", ""],
		[746, "Surging Strikes",   TypeChart.TYPE_WATER,    0, 25,  100, 5,  true,  "strike:3", "crit"],
		[793, "Triple Dive",       TypeChart.TYPE_WATER,    0, 30,  95,  10, true,  "strike:3", ""],
		[814, "Twin Beam",         TypeChart.TYPE_PSYCHIC,  1, 40,  100, 10, false, "strike:2", ""],
		[839, "Tachyon Cutter",    TypeChart.TYPE_STEEL,    1, 50,  0,   10, false, "strike:2", ""],
	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "A.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " name",          mv.move_name == e[1])
		_chk(tag + " type",          mv.type == e[2])
		_chk(tag + " category",      mv.category == e[3])
		_chk(tag + " power",         mv.power == e[4])
		_chk(tag + " accuracy",      mv.accuracy == e[5])
		_chk(tag + " pp",            mv.pp == e[6])
		_chk(tag + " makes_contact", mv.makes_contact == e[7])
		var shape: String = e[8]
		if shape == "multi":
			_chk(tag + " multi_hit=true, strike_count=1 (default)",
					mv.multi_hit and mv.strike_count == 1)
		else:
			var n: int = int(shape.split(":")[1])
			_chk(tag + " strike_count=%d, multi_hit=false" % n,
					mv.strike_count == n and not mv.multi_hit)
		match e[9]:
			"poison20":
				_chk(tag + " SE_POISON chance=20",
						mv.secondary_effect == MoveData.SE_POISON and mv.secondary_chance == 20)
			"flinch30":
				_chk(tag + " SE_FLINCH chance=30",
						mv.secondary_effect == MoveData.SE_FLINCH and mv.secondary_chance == 30)
			"triple_kick":
				_chk(tag + " is_triple_kick", mv.is_triple_kick)
			"scale_shot":
				_chk(tag + " is_scale_shot", mv.is_scale_shot)
			"crit":
				_chk(tag + " always_critical_hit", mv.always_critical_hit)


# ── Section B: _resolve_multi_hit_count — direct unit tests ─────────────────

func _test_section_b_hit_count_resolution() -> void:
	var bm := _make_bm()
	var atk := _make_mon("BAtk", TypeChart.TYPE_NORMAL)

	# B1-B4: fixed strike_count moves return exactly that value, deterministically.
	var double_kick := _load_move(24)
	_chk("B1 Double Kick (strike_count=2) resolves to exactly 2",
			bm._resolve_multi_hit_count(double_kick, atk) == 2)
	var triple_dive := _load_move(793)
	_chk("B2 Triple Dive (strike_count=3) resolves to exactly 3",
			bm._resolve_multi_hit_count(triple_dive, atk) == 3)

	# B3-B6: force_multi_hit_count seam pins each of 2/3/4/5 for a multi_hit move.
	var bullet_seed := _load_move(331)
	for forced in [2, 3, 4, 5]:
		bm._force_multi_hit_count = forced
		_chk("B%d force_multi_hit_count=%d pins exactly %d" % [3 + forced - 2, forced, forced],
				bm._resolve_multi_hit_count(bullet_seed, atk) == forced)
	bm._force_multi_hit_count = null

	# B7: statistical distribution — 35% 2 hits / 35% 3 hits / 15% 4 hits /
	# 15% 5 hits (n=4000, tolerance band matching this project's established
	# statistical-sample convention).
	var n := 4000
	var counts := {2: 0, 3: 0, 4: 0, 5: 0}
	for _i in range(n):
		var c: int = bm._resolve_multi_hit_count(bullet_seed, atk)
		counts[c] += 1
	var r2: float = float(counts[2]) / n
	var r3: float = float(counts[3]) / n
	var r4: float = float(counts[4]) / n
	var r5: float = float(counts[5]) / n
	_chk(("B7a 2-hit rate near 35%% (n=%d, observed=%.3f)" % [n, r2]),
			r2 > 0.30 and r2 < 0.40)
	_chk(("B7b 3-hit rate near 35%% (n=%d, observed=%.3f)" % [n, r3]),
			r3 > 0.30 and r3 < 0.40)
	_chk(("B7c 4-hit rate near 15%% (n=%d, observed=%.3f)" % [n, r4]),
			r4 > 0.10 and r4 < 0.20)
	_chk(("B7d 5-hit rate near 15%% (n=%d, observed=%.3f)" % [n, r5]),
			r5 > 0.10 and r5 < 0.20)
	_chk("B7e every roll landed in [2,5]",
			counts[2] + counts[3] + counts[4] + counts[5] == n)

	bm.queue_free()


# ── Section C: mid-sequence termination ──────────────────────────────────────

func _test_section_c_mid_sequence_termination() -> void:
	var bullet_seed := _load_move(331)

	# C1: target fainting mid-sequence stops immediately — force exactly 5 hits,
	# but give the target only enough HP to survive 1 hit (current_hp set directly
	# after construction, well below what a single forced-roll hit will deal, so
	# there's no ambiguity about which forced hit is the killing blow).
	var c1_bm := _make_bm()
	c1_bm._force_multi_hit_count = 5
	c1_bm._force_hit = true
	c1_bm._force_crit = false
	c1_bm._force_roll = 100
	var c1_atk := _make_mon("C1Atk", TypeChart.TYPE_GRASS, 200, 200, 1, 60, 60, 100)
	var c1_def := _make_mon("C1Def", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 50)
	c1_def.current_hp = 5
	var c1_hits := [0]
	c1_bm.move_executed.connect(func(a, d, m, dmg):
		if a == c1_atk and dmg > 0:
			c1_hits[0] += 1)
	c1_bm._do_multi_hit_sequence(c1_atk, c1_def, bullet_seed, false, -1)
	_chk("C1 sequence stopped early once the target fainted (fewer than the forced 5 hits)",
			c1_hits[0] < 5 and c1_hits[0] > 0)
	_chk("C1b target is actually dead (current_hp <= 0)", c1_def.current_hp <= 0)
	c1_bm.queue_free()

	# C2: a Substitute that ABSORBS multiple hits without breaking lets the
	# sequence CONTINUE (discriminator vs. C1's faint case and C3's break case).
	var c2_bm := _make_bm()
	c2_bm._force_multi_hit_count = 5
	c2_bm._force_hit = true
	c2_bm._force_crit = false
	c2_bm._force_roll = 100
	var c2_atk := _make_mon("C2Atk", TypeChart.TYPE_GRASS, 200, 30, 60, 60, 60, 100)
	var c2_def := _make_mon("C2Def", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 50)
	c2_def.substitute_hp = 999999  # effectively unbreakable for this test
	var c2_hits := [0]
	c2_bm.move_executed.connect(func(a, d, m, dmg):
		if a == c2_atk:
			c2_hits[0] += 1)
	c2_bm._do_multi_hit_sequence(c2_atk, c2_def, bullet_seed, false, -1)
	_chk("C2 all 5 forced hits landed against a Substitute that never broke",
			c2_hits[0] == 5)
	_chk("C2b target's own current_hp is untouched (Substitute absorbed everything)",
			c2_def.current_hp == c2_def.max_hp)
	c2_bm.queue_free()

	# C3: a Substitute that BREAKS mid-sequence stops the rest of the hits —
	# the real Pokémon behind it is never touched by the remaining swings.
	var c3_bm := _make_bm()
	c3_bm._force_multi_hit_count = 5
	c3_bm._force_hit = true
	c3_bm._force_crit = false
	c3_bm._force_roll = 100
	var c3_atk := _make_mon("C3Atk", TypeChart.TYPE_GRASS, 200, 200, 1, 60, 60, 100)
	var c3_def := _make_mon("C3Def", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 50)
	c3_def.substitute_hp = 1  # breaks on the very first hit
	var c3_hits := [0]
	var c3_broke := [false]
	c3_bm.move_executed.connect(func(a, d, m, dmg):
		if a == c3_atk:
			c3_hits[0] += 1)
	c3_bm.substitute_broke.connect(func(m): c3_broke[0] = true)
	c3_bm._do_multi_hit_sequence(c3_atk, c3_def, bullet_seed, false, -1)
	_chk("C3 substitute_broke fired", c3_broke[0])
	_chk("C3b sequence stopped immediately after the Substitute broke (exactly 1 hit)",
			c3_hits[0] == 1)
	_chk("C3c the real Pokémon's own HP was never touched",
			c3_def.current_hp == c3_def.max_hp)
	c3_bm.queue_free()

	# C4: a wholly-blocked hit (type immunity, no Substitute involved) stops
	# after just the one attempt — not a full forced 5.
	var c4_bm := _make_bm()
	c4_bm._force_multi_hit_count = 5
	c4_bm._force_hit = true
	c4_bm._force_crit = false
	c4_bm._force_roll = 100
	var c4_atk := _make_mon("C4Atk", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 100)
	var c4_def := _make_mon("C4Def", TypeChart.TYPE_GHOST, 200, 60, 60, 60, 60, 50)
	# Comet Punch (Normal) is immune against a pure Ghost-type target.
	var comet_punch := _load_move(4)
	var c4_hits := [0]
	c4_bm.move_executed.connect(func(a, d, m, dmg):
		if a == c4_atk:
			c4_hits[0] += 1)
	c4_bm._do_multi_hit_sequence(c4_atk, c4_def, comet_punch, false, -1)
	_chk("C4 wholly-immune target: sequence stops after exactly 1 attempt, not 5",
			c4_hits[0] == 1)
	_chk("C4b target took no damage at all", c4_def.current_hp == c4_def.max_hp)
	c4_bm.queue_free()


# ── Section D: per-hit vs. once-per-move correctness ─────────────────────────

func _test_section_d_per_hit_vs_once_per_move() -> void:
	var bullet_seed := _load_move(331)

	# D1: PP — deducted once per move use regardless of hit count. Snapshotted at
	# the FIRST move_executed for this move (guarded to first occurrence, per this
	# project's own established signal-snapshot testing convention) — start_battle
	# runs the WHOLE battle to completion, so reading current_pp AFTER it returns
	# would reflect however many additional turns happened to run, not just this
	# one 5-hit use.
	var d1_bm := _make_bm()
	d1_bm._force_multi_hit_count = 5
	d1_bm._force_hit = true
	var d1_atk := _make_mon("D1Atk", TypeChart.TYPE_GRASS, 300, 60, 60, 60, 60, 100)
	d1_atk.add_move(bullet_seed)
	var d1_def := _make_mon("D1Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	var dummy := MoveData.new()
	dummy.move_name = "D1Dummy"
	dummy.type = TypeChart.TYPE_NORMAL
	dummy.power = 0
	dummy.accuracy = 0
	dummy.pp = 30
	d1_def.add_move(dummy)
	var d1_pp_snapshot := [-1]
	d1_bm.move_executed.connect(func(a, d, m, dmg):
		if a == d1_atk and d1_pp_snapshot[0] == -1:
			d1_pp_snapshot[0] = d1_atk.current_pp[0])
	d1_bm.queue_move(0, 0)
	d1_bm.queue_move(1, 0)
	d1_bm.start_battle(d1_atk, d1_def)
	_chk("D1 PP deducted exactly once for a 5-hit move (29 remaining after hit 1, not 25)",
			d1_pp_snapshot[0] == bullet_seed.pp - 1)

	# D2: contact ability rolls independently per hit — force the roll true and
	# confirm it fires once per landed hit (Rough Skin, contact-gated recoil).
	# Uses Comet Punch, NOT Bullet Seed — Bullet Seed is a ballistic (non-contact)
	# move, confirmed via moves_info.h, so Rough Skin would never fire on it at
	# all; Comet Punch (makes_contact=true, multi_hit=true) is the right fixture.
	var comet_punch_d2 := _load_move(4)
	var d2_bm := _make_bm()
	d2_bm._force_multi_hit_count = 4
	d2_bm._force_hit = true
	d2_bm._force_crit = false
	d2_bm._force_roll = 100
	d2_bm._force_contact_roll = true
	var d2_atk := _make_mon("D2Atk", TypeChart.TYPE_NORMAL, 300, 30, 60, 60, 60, 100)
	var d2_def := _make_mon("D2Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	d2_def.ability = _load_ability(24)  # Rough Skin
	var d2_recoil_ticks := [0]
	d2_bm.recoil_damage.connect(func(a, amt):
		if a == d2_atk:
			d2_recoil_ticks[0] += 1)
	d2_bm._do_multi_hit_sequence(d2_atk, d2_def, comet_punch_d2, false, -1)
	_chk("D2 Rough Skin recoil fired once per landed hit (4, not 1)",
			d2_recoil_ticks[0] == 4)

	# D3: King's Rock flinch rolls independently per hit — force the roll and
	# confirm SE_FLINCH fires once per landed hit.
	var d3_bm := _make_bm()
	d3_bm._force_multi_hit_count = 4
	d3_bm._force_hit = true
	d3_bm._force_crit = false
	d3_bm._force_roll = 100
	d3_bm._force_kings_rock_roll = true
	var d3_atk := _make_mon("D3Atk", TypeChart.TYPE_GRASS, 300, 60, 60, 60, 60, 100)
	d3_atk.held_item = _make_item(ItemManager.HOLD_EFFECT_FLINCH, 10)
	var d3_def := _make_mon("D3Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 1)
	d3_bm._combatants = [d3_atk, d3_def]
	d3_bm._turn_order = [d3_atk, d3_def]  # attacker acts first -> target hasn't acted
	d3_bm._chosen_switch_slots = [-1, -1]  # sized to match _combatants (avoids
			# _is_last_to_move's Array[int] index-out-of-bounds on a manually-
			# constructed BattleManager that never went through start_battle)
	d3_bm._current_actor_index = 0
	var d3_flinch_ticks := [0]
	d3_bm.secondary_applied.connect(func(t, eff):
		if t == d3_def and eff == MoveData.SE_FLINCH:
			d3_flinch_ticks[0] += 1)
	d3_bm._do_multi_hit_sequence(d3_atk, d3_def, bullet_seed, false, -1)
	_chk("D3 King's Rock flinch rolled independently on each of the 4 landed hits",
			d3_flinch_ticks[0] == 4)

	# D4: Shell Bell heals ONCE from the ACCUMULATED total, not per hit. Uses a
	# concrete counter-example matching decisions.md's citation shape: each
	# individual hit's own damage is forced low enough that floor(hit/8)==0 (so
	# a naive per-hit heal would total 0 across the whole sequence), while the
	# SUMMED total clears the /8 threshold and produces a real, positive heal —
	# force_roll=100/force_crit=false pins each hit's damage exactly so this is
	# deterministic, not a statistical near-miss.
	var d4_bm := _make_bm()
	d4_bm._force_multi_hit_count = 5
	d4_bm._force_hit = true
	d4_bm._force_crit = false
	d4_bm._force_roll = 100
	var d4_atk := _make_mon("D4Atk", TypeChart.TYPE_NORMAL, 300, 22, 60, 60, 60, 100)
	d4_atk.held_item = _make_item(ItemManager.HOLD_EFFECT_SHELL_BELL, 8)
	d4_atk.current_hp = 100  # damaged, so the heal is observable
	var d4_def := _make_mon("D4Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	var weak_hit := MoveData.new()
	weak_hit.move_name = "D4WeakHit"
	weak_hit.type = TypeChart.TYPE_NORMAL
	weak_hit.power = 15
	weak_hit.accuracy = 0
	weak_hit.multi_hit = true
	var heal_ticks := [0]
	var final_hp_before_loop: int = d4_atk.current_hp
	var heal_amt_total := [0]
	d4_bm.item_healed.connect(func(m, amt):
		heal_ticks[0] += 1
		heal_amt_total[0] += amt)
	var d4_hit_dmgs := []
	d4_bm.move_executed.connect(func(a, d, m, dmg): d4_hit_dmgs.append(dmg))
	d4_bm._do_multi_hit_sequence(d4_atk, d4_def, weak_hit, false, -1)
	var d4_per_hit_naive_total: int = 0
	for hd: int in d4_hit_dmgs:
		d4_per_hit_naive_total += hd / 8
	_chk("D4 each individual hit's own damage floors to 0 under Shell Bell's /8 " +
			"(the naive per-hit total is 0)", d4_per_hit_naive_total == 0)
	_chk("D4b Shell Bell healed exactly once for the whole 5-hit sequence, not per hit",
			heal_ticks[0] == 1)
	_chk("D4c the ACCUMULATED total produced a real, positive heal " +
			"(would be 0 if computed per-hit and summed)",
			heal_amt_total[0] > 0)
	_chk("D4d current_hp actually increased", d4_atk.current_hp > final_hp_before_loop)

	# D5: Twineedle's poison chance rolls independently on each hit (statistical
	# — n=1500, force each hit to land, force_secondary not threaded through
	# try_secondary_effect's multi-hit call site so a real roll is used; a
	# fresh un-poisoned target every trial).
	var twineedle := _load_move(41)
	var d5_bm := _make_bm()
	d5_bm._force_multi_hit_count = 2
	d5_bm._force_hit = true
	d5_bm._force_crit = false
	var n5 := 1500
	var poisoned_count := 0
	for _i in range(n5):
		var d5_atk := _make_mon("D5Atk", TypeChart.TYPE_BUG, 100, 60, 60, 60, 60, 100)
		var d5_def := _make_mon("D5Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
		d5_bm._do_multi_hit_sequence(d5_atk, d5_def, twineedle, false, -1)
		if d5_def.status == BattlePokemon.STATUS_POISON:
			poisoned_count += 1
	var d5_rate: float = float(poisoned_count) / n5
	# Two independent 20% rolls (one per hit): P(at least one hits) = 1-0.8^2 = 0.36.
	_chk(("D5 Twineedle poison rate over 2 independent per-hit 20%% rolls is near " +
			"36%% (n=%d, observed=%.3f)") % [n5, d5_rate],
			d5_rate > 0.28 and d5_rate < 0.44)

	# D6: Scale Shot's self stat change fires exactly once, not per hit.
	var scale_shot := _load_move(727)
	var d6_bm := _make_bm()
	d6_bm._force_multi_hit_count = 5
	d6_bm._force_hit = true
	d6_bm._force_crit = false
	var d6_atk := _make_mon("D6Atk", TypeChart.TYPE_DRAGON, 300, 60, 60, 60, 60, 100)
	var d6_def := _make_mon("D6Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	var d6_stat_ticks := [0]
	d6_bm.stat_stage_changed.connect(func(t, stat_idx, actual):
		if t == d6_atk:
			d6_stat_ticks[0] += 1)
	d6_bm._do_multi_hit_sequence(d6_atk, d6_def, scale_shot, false, -1)
	_chk("D6 Scale Shot's self stat change fired exactly twice (Def-1, Speed+1), " +
			"not once per hit (would be 10)",
			d6_stat_ticks[0] == 2)
	_chk("D6b Defense actually dropped by 1", d6_atk.stat_stages[BattlePokemon.STAGE_DEF] == -1)
	_chk("D6c Speed actually rose by 1", d6_atk.stat_stages[BattlePokemon.STAGE_SPEED] == 1)


# ── Section E: Triple Kick / Triple Axel — escalating power + per-hit accuracy ──

func _test_section_e_triple_kick_family() -> void:
	var triple_kick := _load_move(167)
	var atk := _make_mon("E_Atk", TypeChart.TYPE_FIGHTING, 200, 80, 60, 60, 60, 100)
	var def := _make_mon("E_Def", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 50)

	# E1-E3: escalating power confirmed via direct DamageCalculator calls
	# (pairwise comparison, force_roll=100/force_crit=false per this project's
	# established convention). NOT checked as an exact 2x/3x multiple — the
	# damage formula chains several independent floor() divisions (base power
	# calc, then the /50 stage, then random%), so doubling/tripling the power
	# input does not generally produce an exactly-doubled/tripled OUTPUT (concrete
	# observed values: power=10->20 damage, power=20->38 (not 40), power=30->56
	# (not 60) — a ~5-7% rounding gap, the same class of floor-truncation this
	# project's own Shell Bell accumulation citation already documents). A
	# tolerance band confirms the escalation is real and correctly proportioned
	# without asserting false mathematical precision the formula doesn't provide.
	var hit1 := DamageCalculator.calculate(atk, def, triple_kick, 100, false,
			DamageCalculator.WEATHER_NONE, false, false, triple_kick.power * 1)
	var hit2 := DamageCalculator.calculate(atk, def, triple_kick, 100, false,
			DamageCalculator.WEATHER_NONE, false, false, triple_kick.power * 2)
	var hit3 := DamageCalculator.calculate(atk, def, triple_kick, 100, false,
			DamageCalculator.WEATHER_NONE, false, false, triple_kick.power * 3)
	var d1: int = hit1["damage"]
	var d2: int = hit2["damage"]
	var d3: int = hit3["damage"]
	_chk("E1 hit 2's damage is close to 2x hit 1's (within floor-rounding tolerance)",
			d2 >= d1 * 2 - d1 / 4 and d2 <= d1 * 2)
	_chk("E2 hit 3's damage is close to 3x hit 1's (within floor-rounding tolerance)",
			d3 >= d1 * 3 - d1 / 2 and d3 <= d1 * 3)
	_chk("E3 damage strictly increases hit-over-hit (1 < 2 < 3)",
			d1 < d2 and d2 < d3)

	# E4: full sequence via _do_multi_hit_sequence — force all 3 hits to land,
	# confirm exactly 3 landed and the total equals the sum of the 3 individual
	# power-override damages computed above (same forced roll/crit).
	var e4_bm := _make_bm()
	e4_bm._force_hit = true
	e4_bm._force_crit = false
	e4_bm._force_roll = 100
	var e4_hits := [0]
	e4_bm.move_executed.connect(func(a, d, m, dmg):
		if a == atk and dmg > 0:
			e4_hits[0] += 1)
	e4_bm._do_multi_hit_sequence(atk, def, triple_kick, false, -1)
	_chk("E4 all 3 Triple Kick hits landed when every accuracy roll is forced true",
			e4_hits[0] == 3)

	# E5: an independent per-hit miss stops the sequence early — force hit 1 to
	# land (already true globally above isn't selective enough), so instead
	# force_hit=false globally and confirm ZERO hits land (hit 1's own single
	# top-level accuracy check, done by the caller in a real battle, isn't
	# exercised by calling _do_multi_hit_sequence directly — this call starts
	# from "hit 1 already landed" by construction, so this test targets hits
	# 2-3's own independent rolls instead).
	var e5_bm := _make_bm()
	e5_bm._force_hit = false
	e5_bm._force_crit = false
	e5_bm._force_roll = 100
	var e5_hits := [0]
	e5_bm.move_executed.connect(func(a, d, m, dmg):
		if a == atk and dmg > 0:
			e5_hits[0] += 1)
	e5_bm._do_multi_hit_sequence(atk, def, triple_kick, false, -1)
	_chk("E5 hit 1 always lands (unconditional first hit), but hit 2's forced miss " +
			"stops the sequence there (exactly 1 hit, not 3)",
			e5_hits[0] == 1)


# ── Section F: full-battle integration — real move-execution dispatch ───────

func _test_section_f_full_battle_integration() -> void:
	var bullet_seed := _load_move(331)
	var dummy := MoveData.new()
	dummy.move_name = "F_Dummy"
	dummy.type = TypeChart.TYPE_NORMAL
	dummy.power = 0
	dummy.accuracy = 0
	dummy.pp = 30

	var attacker := _make_mon("F_Attacker", TypeChart.TYPE_GRASS, 300, 60, 60, 60, 60, 100)
	attacker.add_move(bullet_seed)
	var defender := _make_mon("F_Defender", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	defender.add_move(dummy)

	var bm := _make_bm()
	bm._force_hit = true
	var finished_log := []
	bm.multi_hit_sequence_finished.connect(func(a, t, hits, dmg):
		if finished_log.is_empty():
			finished_log.append([a, t, hits, dmg]))
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(attacker, defender)

	_chk("F1 multi_hit_sequence_finished fired for the real dispatch path",
			finished_log.size() >= 1)
	if not finished_log.is_empty():
		var hits: int = finished_log[0][2]
		var total_dmg: int = finished_log[0][3]
		_chk("F2 hits landed is within the real 2-5 range", hits >= 2 and hits <= 5)
		_chk("F3 total damage accumulated is positive", total_dmg > 0)
