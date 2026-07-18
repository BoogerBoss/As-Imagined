extends Node

# [NEW ITEM D] Shared accuracy-roll architecture gap — implementation + tests.
#
# Closes NEW ITEM D from docs/m21_recon.md's own "NEW ITEM D" section. Source
# resolves accuracy AND the semi-invulnerable bypass independently PER TARGET
# for a spread move (CancelerAccuracyCheck, battle_move_resolution.c
# L2174-2260, its own per-battler loop calling DoesMoveMissTarget
# independently; a separate per-target canceler for semi-invulnerability,
# L1960-2010). This project previously checked accuracy exactly ONCE, against
# the single default `defender`, before the spread/single split — a miss
# aborted the WHOLE move for every target; a hit sent every live target
# through unconditionally with no further per-target check at all. Affects
# 59 currently-implemented spread damage moves.
#
# Step 0 findings (see docs/decisions.md's own entry for the full trail):
#   - crashes_on_miss (Jump Kick/High Jump Kick/Axe Kick/Supercell Slam) never
#     co-occurs with is_spread (all 4 are .target=TARGET_SELECTED in source)
#     — confirmed via direct moves_info.h read, not assumed. Non-issue.
#   - recoil_percent/drain_percent/is_rage/is_recharge are ALL already gated
#     on `damage > 0` INSIDE `_do_damaging_hit`, which is called once per
#     target in the spread loop — automatically correct per-target once a
#     missed target is simply never passed to it. No changes needed to any
#     of these.
#   - is_rollout/is_fury_cutter/is_steel_beam/is_rampage/is_uproar also never
#     co-occur with is_spread (confirmed via gen_moves.py grep) — the
#     existing shared miss-handling block (Rollout reset, Fury Cutter reset,
#     Steel Beam recoil, rampage/uproar continuation) is simply skipped for
#     spread moves, losing none of that bookkeeping (structurally
#     unreachable for them either way).
#   - New `move_missed_target(attacker, target, reason)` signal fires once
#     per individual missed target within a spread use; the existing
#     `move_missed(attacker, reason)` signal stays single-shot, firing only
#     when EVERY live target in the spread use missed (preserving
#     `_current_action_failed`'s "did my whole move fail" semantics for
#     Stomping Tantrum et al. — a partial hit is NOT treated as an overall
#     failure, matching source, which has no single "the move missed" flag
#     for a spread move with mixed outcomes).
#   - Blunder Policy: a disclosed simplification, not silently dropped —
#     fires only when a spread move's accuracy roll misses EVERY live target
#     (same "whole move failed" threshold as `move_missed`), via a new
#     shared `_apply_blunder_policy_on_miss` helper (also used by the
#     pre-existing single-target miss path, a pure extraction, no behavior
#     change there).
#   - StatusManager.check_accuracy and _can_hit_semi_invulnerable needed ZERO
#     logic changes — both were already stateless and per-target-capable;
#     this is a pure call-site scoping fix (called once per target inside
#     the spread loop instead of once before it).
#   - Dragon Darts' smart-target mechanism is NOT touched — it dispatches
#     through the separate `multi_hit`/`strike_count` branch, confirmed
#     mutually exclusive from `is_spread` (see that branch's own comment).
#
# Test-audit-first pass (per this project's own discipline): grepped every
# test file referencing is_spread/doubles dispatch for one NOT using
# `_force_hit` or a deterministic accuracy==100/no-stat-change scenario.
# Found exactly 3: doubles_test.gd (uses `_make_spread` with accuracy=100,
# which is unconditionally `randi() % 100 < 100` — always true regardless of
# how many times it's independently rolled — safe), m19_weather_accuracy_test
# .gd's Bleakwind Storm full-battle test (singles only, `_active_per_side`
# never exceeds 1, so the spread branch/this fix is never reached at all —
# safe), and m21_test.gd (all its spread-move helpers hardcode
# `accuracy = 100` too — safe). Zero existing assertions needed fixing.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_semi_invulnerable_plus_grounded_independence()
	_test_partial_miss_does_not_fire_whole_move_missed()
	_test_full_miss_fires_whole_move_missed_once_and_blunder_policy()
	_test_blunder_policy_not_fired_on_partial_miss()
	_test_evasion_divergence_statistical()
	_test_shell_bell_accumulation_excludes_missed_target()
	_test_negative_control_singles_unaffected()

	var total := _pass + _fail
	print("new_item_d_test: %d/%d passed" % [_pass, total])
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


func _load_item(id: int) -> ItemData:
	return ItemRegistry.get_item(id)


func _make_mon_stats(mon_name: String, mon_type: int,
		base_atk: int = 60, base_def: int = 60, base_hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = base_hp
	sp.base_attack = base_atk
	sp.base_defense = base_def
	sp.base_sp_attack = base_atk
	sp.base_sp_defense = base_def
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


# Direct single-dispatch helper for a 4-combatant doubles scenario, matching
# new_item_a/b/c_test.gd's own convention — resolves exactly ONE
# `_phase_move_execution()` call for A0 (idx 0), bypassing the full
# multi-turn battle loop. Deliberately does NOT set `_force_hit` (null,
# meaning "use real RNG per StatusManager.check_accuracy's own per-target
# logic") — callers control determinism via move.accuracy/stat stages/
# semi-invulnerable state instead, which is the whole point of these tests.
func _dispatch(a0: BattlePokemon, a1: BattlePokemon, b0: BattlePokemon, b1: BattlePokemon,
		move: MoveData, per_target_dmg: Dictionary, missed_targets: Array,
		whole_move_missed: Array, blunder_events: Array) -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(atk, d, mv, dmg):
		if atk == a0 and mv == move and not per_target_dmg.has(d):
			per_target_dmg[d] = dmg
	)
	bm.move_missed_target.connect(func(atk, t, _reason):
		if atk == a0:
			missed_targets.append(t)
	)
	bm.move_missed.connect(func(atk, _reason):
		if atk == a0:
			whole_move_missed.append(true)
	)
	bm.stat_stage_changed.connect(func(mon, stat_idx, actual):
		if mon == a0 and stat_idx == BattlePokemon.STAGE_SPEED:
			blunder_events.append(actual)
	)
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [move, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 3, 0, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()
	return bm


# ── Section A: semi-invulnerable + grounded independence (fully deterministic,
# no RNG needed at all — the exact "target A semi-invulnerable, target B
# grounded, in the SAME spread use" scenario NEW ITEM D's own recon flagged) ──

func _test_semi_invulnerable_plus_grounded_independence() -> void:
	var earthquake := _load_move(89)   # damages_underground = true, target_includes_ally = true
	# Rock Slide: is_spread=true, no damages_underground, no target_includes_ally
	# (confirmed via NEW ITEM C's own negative control) — a clean 2-opponent-
	# only spread move for the "does NOT bypass semi-invulnerability" half.
	# Accuracy overridden to 100 on this in-memory copy for full determinism
	# (real Rock Slide is 90%) — discarded when the test ends, never written
	# back to the .tres file.
	var rock_slide := _load_move(157)
	rock_slide.accuracy = 100

	# A.01: Earthquake (damages_underground) hits BOTH a grounded target AND
	# one that's mid-Dig (semi_invulnerable = SEMI_INV_UNDERGROUND) in the
	# SAME spread use — the bypass applies independently per target.
	var a0 := _make_mon_stats("EqA0", TypeChart.TYPE_GROUND, 60, 60)
	var a1 := _make_mon_stats("EqA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("EqB0", TypeChart.TYPE_NORMAL, 60, 60)  # grounded
	var b1 := _make_mon_stats("EqB1", TypeChart.TYPE_NORMAL, 60, 60)  # mid-Dig
	b1.semi_invulnerable = MoveData.SEMI_INV_UNDERGROUND
	var per_target_dmg := {}
	var missed := []
	var whole_missed := []
	var blunder := []
	var bm := _dispatch(a0, a1, b0, b1, earthquake, per_target_dmg, missed, whole_missed, blunder)
	_chk("A.01 REQUIRED: Earthquake (damages_underground) hits the grounded target B0",
			per_target_dmg.get(b0, 0) > 0)
	_chk("A.02 REQUIRED: Earthquake ALSO hits the semi-invulnerable-underground " +
			"target B1, independently of B0's own outcome", per_target_dmg.get(b1, 0) > 0)
	_chk("A.03 no per-target miss reported for either (both connect)", missed.is_empty())
	bm.queue_free()

	# A.04-A.06: Rock Slide (no damages_underground flag) hits ONLY the
	# grounded target; the semi-invulnerable one is independently skipped —
	# the core per-target-independence proof: one target's own state blocks
	# it while the OTHER target in the same use is completely unaffected.
	var c0 := _make_mon_stats("RsA0", TypeChart.TYPE_ROCK, 60, 60)
	var c1 := _make_mon_stats("RsA1", TypeChart.TYPE_NORMAL, 60, 60)
	var d0 := _make_mon_stats("RsB0", TypeChart.TYPE_NORMAL, 60, 60)  # grounded
	var d1 := _make_mon_stats("RsB1", TypeChart.TYPE_NORMAL, 60, 60)  # mid-Dig
	d1.semi_invulnerable = MoveData.SEMI_INV_UNDERGROUND
	var per_target_dmg2 := {}
	var missed2 := []
	var whole_missed2 := []
	var blunder2 := []
	var bm2 := _dispatch(c0, c1, d0, d1, rock_slide, per_target_dmg2, missed2, whole_missed2, blunder2)
	_chk("A.04 REQUIRED: Rock Slide (no underground bypass) still hits the " +
			"grounded target D0", per_target_dmg2.get(d0, 0) > 0)
	_chk("A.05 REQUIRED (the core fix): Rock Slide does NOT hit the " +
			"semi-invulnerable-underground target D1, even though D0 in the " +
			"SAME use connected normally", not per_target_dmg2.has(d1))
	_chk("A.06 REQUIRED: exactly one per-target miss reported (D1), and the " +
			"whole-move move_missed signal did NOT fire (D0 still connected)",
			missed2 == [d1] and whole_missed2.is_empty())
	bm2.queue_free()


# ── Section B: partial miss must not be treated as a whole-move failure ──────

func _test_partial_miss_does_not_fire_whole_move_missed() -> void:
	# Reuses Section A's D1-misses/D0-hits scenario as the canonical
	# "partial miss" case — already proven above that move_missed (whole-
	# move) does not fire when only one of several targets misses. This
	# test isolates that specific assertion with its own fresh fixtures for
	# clarity and to guard against Section A's own test changing shape later.
	var rock_slide := _load_move(157)
	rock_slide.accuracy = 100
	var a0 := _make_mon_stats("PmA0", TypeChart.TYPE_ROCK, 60, 60)
	var a1 := _make_mon_stats("PmA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("PmB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("PmB1", TypeChart.TYPE_NORMAL, 60, 60)
	b1.semi_invulnerable = MoveData.SEMI_INV_UNDERGROUND
	var per_target_dmg := {}
	var missed := []
	var whole_missed := []
	var blunder := []
	var bm := _dispatch(a0, a1, b0, b1, rock_slide, per_target_dmg, missed, whole_missed, blunder)
	_chk("B.01 REQUIRED: a partial miss (1 of 2 opponents) does NOT fire the " +
			"whole-move move_missed signal", whole_missed.is_empty())
	_chk("B.02 the one missed target's own move_missed_target DID fire", missed == [b1])
	bm.queue_free()


# ── Section C: a full miss (every live target) fires move_missed exactly
# once, plus Blunder Policy ────────────────────────────────────────────────

func _test_full_miss_fires_whole_move_missed_once_and_blunder_policy() -> void:
	# Rock Slide (no target_includes_ally) — keeps this a clean 2-opponent
	# scenario so "both individual per-target misses" means exactly 2, not 3.
	var rock_slide := _load_move(157)
	var a0 := _make_mon_stats("FmA0", TypeChart.TYPE_ROCK, 60, 60)
	a0.held_item = _load_item(511)  # Blunder Policy
	var a1 := _make_mon_stats("FmA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("FmB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("FmB1", TypeChart.TYPE_NORMAL, 60, 60)

	var per_target_dmg := {}
	var missed := []
	var whole_missed := []
	var blunder := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = false  # every per-target check_accuracy call returns false
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(atk, d, mv, dmg):
		if atk == a0 and mv == rock_slide and not per_target_dmg.has(d):
			per_target_dmg[d] = dmg
	)
	bm.move_missed_target.connect(func(atk, t, _reason):
		if atk == a0:
			missed.append(t)
	)
	bm.move_missed.connect(func(atk, _reason):
		if atk == a0:
			whole_missed.append(true)
	)
	bm.stat_stage_changed.connect(func(mon, stat_idx, actual):
		if mon == a0 and stat_idx == BattlePokemon.STAGE_SPEED:
			blunder.append(actual)
	)
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [rock_slide, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 3, 0, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()

	_chk("C.01 REQUIRED: no target takes damage when every live target " +
			"misses", per_target_dmg.is_empty())
	_chk("C.02 REQUIRED: both individual per-target misses reported " +
			"(B0 and B1)", missed.size() == 2)
	_chk("C.03 REQUIRED: the whole-move move_missed signal fires EXACTLY " +
			"ONCE (not once per target) when every target misses",
			whole_missed.size() == 1)
	_chk("C.04 REQUIRED: Blunder Policy fires on a full spread-move miss " +
			"(+2 Speed)", blunder.size() == 1 and blunder[0] == 2)
	bm.queue_free()


func _test_blunder_policy_not_fired_on_partial_miss() -> void:
	# Same D1-misses/D0-hits scenario as Section A/B, but the attacker now
	# holds Blunder Policy — confirms it does NOT fire on a partial miss,
	# only on a full one (Section C above).
	var rock_slide := _load_move(157)
	rock_slide.accuracy = 100
	var a0 := _make_mon_stats("BpA0", TypeChart.TYPE_ROCK, 60, 60)
	a0.held_item = _load_item(511)  # Blunder Policy
	var a1 := _make_mon_stats("BpA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("BpB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("BpB1", TypeChart.TYPE_NORMAL, 60, 60)
	b1.semi_invulnerable = MoveData.SEMI_INV_UNDERGROUND
	var per_target_dmg := {}
	var missed := []
	var whole_missed := []
	var blunder := []
	var bm := _dispatch(a0, a1, b0, b1, rock_slide, per_target_dmg, missed, whole_missed, blunder)
	_chk("D.01 REQUIRED: Blunder Policy does NOT fire on a partial miss " +
			"(one target still connected)", blunder.is_empty())
	bm.queue_free()


# ── Section E: statistical evasion-divergence proof — two targets with
# different evasion resolve independently over many trials ─────────────────

func _test_evasion_divergence_statistical() -> void:
	# Target B0: neutral evasion, move accuracy=100 → calc=100 → deterministic
	# 100% hit every trial (randi() % 100 < 100 is always true).
	# Target B1: +6 evasion → calc = 100 * 33/100 = 33 → genuinely
	# probabilistic (~33% hit rate), independent of B0's own guaranteed hit.
	var rock_slide := _load_move(157)
	rock_slide.accuracy = 100
	var hits_b0 := 0
	var hits_b1 := 0
	var trials := 60
	for i in range(trials):
		var a0 := _make_mon_stats("EvA0_%d" % i, TypeChart.TYPE_ROCK, 60, 60)
		var a1 := _make_mon_stats("EvA1_%d" % i, TypeChart.TYPE_NORMAL, 60, 60)
		var b0 := _make_mon_stats("EvB0_%d" % i, TypeChart.TYPE_NORMAL, 60, 60)
		var b1 := _make_mon_stats("EvB1_%d" % i, TypeChart.TYPE_NORMAL, 60, 60)
		b1.stat_stages[BattlePokemon.STAGE_EVASION] = 6
		var per_target_dmg := {}
		var missed := []
		var whole_missed := []
		var blunder := []
		var bm := _dispatch(a0, a1, b0, b1, rock_slide, per_target_dmg, missed, whole_missed, blunder)
		if per_target_dmg.get(b0, 0) > 0:
			hits_b0 += 1
		if per_target_dmg.get(b1, 0) > 0:
			hits_b1 += 1
		bm.queue_free()

	_chk("E.01 REQUIRED: the 0-evasion target (B0) hits in EVERY trial " +
			"(%d/%d), unaffected by the other target's own evasion" % [hits_b0, trials],
			hits_b0 == trials)
	_chk("E.02 REQUIRED: the +6-evasion target (B1) hits in a genuinely " +
			"reduced fraction of trials (%d/%d, expected ~33%%), proving its " % [hits_b1, trials] +
			"own accuracy is rolled independently rather than sharing B0's " +
			"guaranteed-hit outcome", hits_b1 > 0 and hits_b1 < trials)


# ── Section F: Shell Bell/Life Orb accumulation composes correctly with a
# partially-missed spread use (only landed hits contribute) ────────────────

func _test_shell_bell_accumulation_excludes_missed_target() -> void:
	var rock_slide := _load_move(157)
	rock_slide.accuracy = 100
	var a0 := _make_mon_stats("SbA0", TypeChart.TYPE_ROCK, 60, 60)
	a0.held_item = _load_item(473)  # Shell Bell
	a0.current_hp = a0.max_hp / 2
	var a1 := _make_mon_stats("SbA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("SbB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("SbB1", TypeChart.TYPE_NORMAL, 60, 60)
	b1.semi_invulnerable = MoveData.SEMI_INV_UNDERGROUND

	var per_target_dmg := {}
	var healed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	# Deliberately NOT force_hit — that would bypass the semi-invulnerable
	# gate too, defeating the point of this test. accuracy=100 above makes
	# B0's own real roll deterministic without needing to force anything.
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(atk, d, mv, dmg):
		if atk == a0 and mv == rock_slide and not per_target_dmg.has(d):
			per_target_dmg[d] = dmg
	)
	bm.item_healed.connect(func(p, amt):
		if p == a0:
			healed_events.append(amt))
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [rock_slide, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 3, 0, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()

	_chk("F.01 REQUIRED: B0 was hit, B1 (semi-invulnerable) was not",
			per_target_dmg.get(b0, 0) > 0 and not per_target_dmg.has(b1))
	_chk("F.02 REQUIRED: Shell Bell heals off ONLY the landed hit's damage " +
			"(B0's), not a phantom contribution from the missed target",
			healed_events.size() == 1 and healed_events[0] == max(1, per_target_dmg.get(b0, 0) / 8))
	bm.queue_free()


# ── Section G: negative control — a singles battle's shared accuracy check
# is completely unaffected (non-spread path untouched) ──────────────────────

func _test_negative_control_singles_unaffected() -> void:
	var tackle := _load_move(33)
	var atk := _make_mon_stats("SglAtk", TypeChart.TYPE_NORMAL, 60, 60)
	atk.add_move(tackle)
	var def := _make_mon_stats("SglDef", TypeChart.TYPE_NORMAL, 60, 60)
	def.add_move(tackle)
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var hit := [false]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and not hit[0]:
			hit[0] = true)
	bm.start_battle(atk, def)
	_chk("G.01 singles battle still resolves normally (unaffected by the " +
			"spread-only per-target change)", hit[0] == true)
	bm.queue_free()
