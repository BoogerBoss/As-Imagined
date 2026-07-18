extends Node

# [NEW ITEM A] 9 damage-category moves missing `is_spread` entirely — fix +
# tests. Closes the item from docs/m21_recon.md's "Full-Roster Spread/
# Status-Target Audit" section: Razor Wind(13), Surf(57), Earthquake(89),
# Swift(129), Rock Slide(157), Eruption(284), Water Spout(323),
# Shell Trap(658), Dragon Energy(748) all carry real source target types
# (TARGET_BOTH or TARGET_FOES_AND_ALLY) requiring spread dispatch in
# doubles, but none had `is_spread` set — each behaved as single-target
# only. Fix: `is_spread = True` added to all 9 in gen_moves.py.
#
# [UPDATED by NEW ITEM C, same day]: this session originally left
# Surf/Earthquake WITHOUT `target_includes_ally` (deferred to NEW ITEM C's
# own test-audit-first sweep). NEW ITEM C has since landed and added
# `target_includes_ally=True` to both — the assertions below (A.10/A.11,
# H.03/I.03) were updated in place to assert the new, fully-correct
# behavior (ally IS hit) rather than the old intermediate boundary. This is
# the exact "a genuine correctness fix legitimately invalidates a stale
# test assumption" pattern this project's own testing conventions document
# — not a bug in this file's own original design.
#
# Step 0 (see docs/decisions.md's own entry for this session) confirmed all
# 9 moves are simple flag-only fixes:
#   - Shell Trap: once armed, falls through to the ordinary accuracy+hit
#     dispatch exactly like a normal move — the spread branch is the
#     correct, unmodified integration point.
#   - Eruption/Water Spout/Dragon Energy: `_dmg_power_override` (which
#     `power_scales_with_user_hp` feeds) is computed ONCE, before the
#     spread/single split, from the attacker's own current_hp/max_hp —
#     unaffected by target count, applied identically to every target.
#   - Razor Wind: the two-turn charge is target-agnostic on the charge
#     turn (no targeting resolution happens then); the release turn falls
#     through the ordinary spread dispatch cleanly.
#   - Swift/Rock Slide: a REAL, but PRE-EXISTING and NOT newly-introduced,
#     finding — this project's entire architecture checks accuracy (and the
#     semi-invulnerable bypass Surf/Earthquake's own flags feed into) ONCE,
#     against the single default target, BEFORE the spread/single split,
#     for EVERY damaging move already shipped (not just these 9). This is a
#     real divergence from source (where each spread target gets its own
#     independent accuracy roll), but it applies identically to all ~37
#     already-shipped spread damage moves too — not something this
#     session's flag-flip worsens or is asked to fix. Flagged for a future
#     dedicated architecture session, not touched here. SECONDARY effects
#     (Rock Slide's flinch included) ARE correctly rolled independently
#     per-target, inside `_do_damaging_hit`, confirmed via direct code read.
#
# Test-audit-first pass (per this project's own discipline): checked every
# existing reference to these 9 moves across the test suite before writing
# this file — every usage was a plain singles battle or a direct
# `DamageCalculator.calculate()` unit test. Zero existing assertions needed
# fixing.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_swift_hits_both_opponents_in_doubles()
	_test_rock_slide_hits_both_opponents_in_doubles()
	_test_eruption_power_computed_once_identical_across_targets()
	_test_shell_trap_arms_and_deals_spread_damage_in_doubles()
	_test_razor_wind_two_turn_charge_hits_both_opponents()
	_test_spread_damage_reduction_applies()
	_test_surf_hits_both_opponents()
	_test_earthquake_hits_both_opponents()
	_test_negative_control_singles_unaffected()

	var total := _pass + _fail
	print("new_item_a_test: %d/%d passed" % [_pass, total])
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


# Direct single-dispatch helper for a 4-combatant doubles scenario, mirroring
# m21_test.gd's own `_dispatch_doubles_spread_with_signals` /
# new_item_b_test.gd's `_dispatch_doubles_status` — resolves exactly ONE
# `_phase_move_execution()` call for A0 (idx 0) using `move`, bypassing the
# full multi-turn battle loop (whole-battle-aggregation pitfall by
# construction).
func _dispatch_doubles_damage(a0: BattlePokemon, a1: BattlePokemon,
		b0: BattlePokemon, b1: BattlePokemon, move: MoveData,
		per_target_dmg: Dictionary) -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(atk, d, mv, dmg):
		if atk == a0 and mv == move and not per_target_dmg.has(d):
			per_target_dmg[d] = dmg
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


func _test_data_integrity() -> void:
	var razor_wind := _load_move(13)
	var surf := _load_move(57)
	var earthquake := _load_move(89)
	var swift := _load_move(129)
	var rock_slide := _load_move(157)
	var eruption := _load_move(284)
	var water_spout := _load_move(323)
	var shell_trap := _load_move(658)
	var dragon_energy := _load_move(748)

	_chk("A.01 Razor Wind is_spread=true (was missing)", razor_wind.is_spread)
	_chk("A.02 Surf is_spread=true (was missing)", surf.is_spread)
	_chk("A.03 Earthquake is_spread=true (was missing)", earthquake.is_spread)
	_chk("A.04 Swift is_spread=true (was missing)", swift.is_spread)
	_chk("A.05 Rock Slide is_spread=true (was missing)", rock_slide.is_spread)
	_chk("A.06 Eruption is_spread=true (was missing)", eruption.is_spread)
	_chk("A.07 Water Spout is_spread=true (was missing)", water_spout.is_spread)
	_chk("A.08 Shell Trap is_spread=true (was missing)", shell_trap.is_spread)
	_chk("A.09 Dragon Energy is_spread=true (was missing)", dragon_energy.is_spread)
	_chk("A.10 UPDATED by NEW ITEM C: Surf now carries target_includes_ally=true " +
			"(the ally-hit half, closed by that session)", surf.target_includes_ally)
	_chk("A.11 UPDATED by NEW ITEM C: Earthquake now carries " +
			"target_includes_ally=true too", earthquake.target_includes_ally)


func _test_swift_hits_both_opponents_in_doubles() -> void:
	var swift := _load_move(129)
	var a0 := _make_mon_stats("SwA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("SwA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("SwB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("SwB1", TypeChart.TYPE_NORMAL, 60, 60)

	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, swift, per_target_dmg)
	_chk("B.01 REQUIRED: Swift deals damage to B0", per_target_dmg.get(b0, 0) > 0)
	_chk("B.02 REQUIRED: Swift ALSO deals damage to B1 (the real fix)",
			per_target_dmg.get(b1, 0) > 0)
	_chk("B.03 the attacker's own ally (A1) is untouched (opponents only, " +
			"no target_includes_ally on Swift)", not per_target_dmg.has(a1))
	bm.queue_free()


func _test_rock_slide_hits_both_opponents_in_doubles() -> void:
	var rock_slide := _load_move(157)
	var a0 := _make_mon_stats("RsA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("RsA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("RsB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("RsB1", TypeChart.TYPE_NORMAL, 60, 60)

	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, rock_slide, per_target_dmg)
	_chk("C.01 REQUIRED: Rock Slide deals damage to B0", per_target_dmg.get(b0, 0) > 0)
	_chk("C.02 REQUIRED: Rock Slide ALSO deals damage to B1", per_target_dmg.get(b1, 0) > 0)
	bm.queue_free()


func _test_eruption_power_computed_once_identical_across_targets() -> void:
	var eruption := _load_move(284)
	# Two structurally identical opposing targets — if power were somehow
	# recomputed per-target (it shouldn't be, per Step 0), any divergence
	# would show up as unequal damage despite identical Defense/HP.
	var a0 := _make_mon_stats("ErA0", TypeChart.TYPE_FIRE, 60, 60)
	var a1 := _make_mon_stats("ErA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("ErB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("ErB1", TypeChart.TYPE_NORMAL, 60, 60)
	a0.current_hp = a0.max_hp / 2  # half HP -> ~half of Eruption's base power

	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, eruption, per_target_dmg)
	_chk("D.01 REQUIRED: both structurally-identical targets take IDENTICAL damage " +
			"(power computed once, not per-target)",
			per_target_dmg.get(b0, -1) > 0 and per_target_dmg[b0] == per_target_dmg[b1])
	bm.queue_free()

	# Discriminator: a FULL-HP attacker deals strictly MORE damage than the
	# half-HP one above, proving the HP-scaling itself is genuinely applied
	# (not just coincidentally equal for an unrelated reason).
	var a0_full := _make_mon_stats("ErA0Full", TypeChart.TYPE_FIRE, 60, 60)
	var a1_full := _make_mon_stats("ErA1Full", TypeChart.TYPE_NORMAL, 60, 60)
	var b0_full := _make_mon_stats("ErB0Full", TypeChart.TYPE_NORMAL, 60, 60)
	var b1_full := _make_mon_stats("ErB1Full", TypeChart.TYPE_NORMAL, 60, 60)
	var per_target_dmg_full := {}
	var bm2 := _dispatch_doubles_damage(a0_full, a1_full, b0_full, b1_full, eruption,
			per_target_dmg_full)
	_chk("D.02 discriminator: a full-HP attacker's Eruption deals strictly more " +
			"damage than the half-HP attacker's, proving power scaling is real",
			per_target_dmg_full.get(b0_full, 0) > per_target_dmg.get(b0, 0))
	bm2.queue_free()


func _test_shell_trap_arms_and_deals_spread_damage_in_doubles() -> void:
	var shell_trap := _load_move(658)
	var a0 := _make_mon_stats("StA0", TypeChart.TYPE_FIRE, 60, 60)
	a0.shell_trap_armed = true
	var a1 := _make_mon_stats("StA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("StB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("StB1", TypeChart.TYPE_NORMAL, 60, 60)

	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, shell_trap, per_target_dmg)
	_chk("E.01 REQUIRED: an armed Shell Trap deals damage to B0", per_target_dmg.get(b0, 0) > 0)
	_chk("E.02 REQUIRED: an armed Shell Trap ALSO deals damage to B1 (spread, once " +
			"triggered, uses the SAME dispatch as an ordinary move)",
			per_target_dmg.get(b1, 0) > 0)
	bm.queue_free()


func _test_razor_wind_two_turn_charge_hits_both_opponents() -> void:
	var razor_wind := _load_move(13)
	var a0 := _make_mon_stats("RwA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("RwA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("RwB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("RwB1", TypeChart.TYPE_NORMAL, 60, 60)

	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var per_target_dmg := {}
	bm.move_executed.connect(func(atk, d, mv, dmg):
		if atk == a0 and mv == razor_wind and dmg > 0 and not per_target_dmg.has(d):
			per_target_dmg[d] = dmg
	)
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [razor_wind, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 3, 0, 0]
	bm._turn_order = combatants.duplicate()

	# Turn 1: charge (no damage, sets charging_move).
	bm._current_actor_index = 0
	bm._phase_move_execution()
	_chk("F.01 charge turn sets charging_move, deals no damage yet",
			a0.charging_move == razor_wind and per_target_dmg.is_empty())

	# Turn 2: release — falls through the ordinary spread dispatch.
	bm._current_actor_index = 0
	bm._phase_move_execution()
	_chk("F.02 REQUIRED: the release turn deals damage to B0", per_target_dmg.get(b0, 0) > 0)
	_chk("F.03 REQUIRED: the release turn ALSO deals damage to B1",
			per_target_dmg.get(b1, 0) > 0)
	bm.queue_free()


func _test_spread_damage_reduction_applies() -> void:
	# Confirms the existing 0.75x live-target-count-based reduction still
	# composes correctly with these newly-flagged moves — a 2-live-target
	# spread hit should deal LESS damage per target than a hypothetical
	# single-target hit of the same move, all else equal.
	var swift := _load_move(129)
	var a0 := _make_mon_stats("SrA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("SrA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("SrB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("SrB1", TypeChart.TYPE_NORMAL, 60, 60)
	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, swift, per_target_dmg)
	var spread_dmg: int = per_target_dmg.get(b0, 0)
	bm.queue_free()

	# Single-target comparison: only ONE live opponent (B1 fainted before
	# the move resolves) — no spread reduction should apply.
	var a0_s := _make_mon_stats("SrA0S", TypeChart.TYPE_NORMAL, 60, 60)
	var a1_s := _make_mon_stats("SrA1S", TypeChart.TYPE_NORMAL, 60, 60)
	var b0_s := _make_mon_stats("SrB0S", TypeChart.TYPE_NORMAL, 60, 60)
	var b1_s := _make_mon_stats("SrB1S", TypeChart.TYPE_NORMAL, 60, 60)
	b1_s.current_hp = 0
	b1_s.fainted = true
	var per_target_dmg_s := {}
	var bm2 := _dispatch_doubles_damage(a0_s, a1_s, b0_s, b1_s, swift, per_target_dmg_s)
	var single_dmg: int = per_target_dmg_s.get(b0_s, 0)
	bm2.queue_free()

	_chk("G.01 REQUIRED: the 0.75x spread-reduction still applies to a newly-flagged " +
			"move — 2-live-target damage (%d) is strictly less than the " % [spread_dmg] +
			"1-live-target damage (%d)" % [single_dmg],
			spread_dmg > 0 and single_dmg > 0 and spread_dmg < single_dmg)


func _test_surf_hits_both_opponents() -> void:
	# [UPDATED by NEW ITEM C]: originally named
	# "_test_surf_hits_both_opponents_but_not_ally" and asserted the ally was
	# NOT hit (the intermediate, deliberately-deferred state this session
	# shipped with). NEW ITEM C has since added target_includes_ally=True to
	# Surf — renamed and updated to assert the ally IS now hit too.
	var surf := _load_move(57)
	var a0 := _make_mon_stats("SfA0", TypeChart.TYPE_WATER, 60, 60)
	var a1 := _make_mon_stats("SfA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("SfB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("SfB1", TypeChart.TYPE_NORMAL, 60, 60)

	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, surf, per_target_dmg)
	_chk("H.01 REQUIRED: Surf deals damage to B0", per_target_dmg.get(b0, 0) > 0)
	_chk("H.02 REQUIRED: Surf ALSO deals damage to B1", per_target_dmg.get(b1, 0) > 0)
	_chk("H.03 UPDATED by NEW ITEM C: Surf now ALSO hits the user's own ally " +
			"(A1) — target_includes_ally was closed by that session",
			per_target_dmg.get(a1, 0) > 0)
	bm.queue_free()


func _test_earthquake_hits_both_opponents() -> void:
	# [UPDATED by NEW ITEM C]: same rename/update as Surf above.
	var earthquake := _load_move(89)
	var a0 := _make_mon_stats("EqA0", TypeChart.TYPE_GROUND, 60, 60)
	var a1 := _make_mon_stats("EqA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("EqB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("EqB1", TypeChart.TYPE_NORMAL, 60, 60)

	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, earthquake, per_target_dmg)
	_chk("I.01 REQUIRED: Earthquake deals damage to B0", per_target_dmg.get(b0, 0) > 0)
	_chk("I.02 REQUIRED: Earthquake ALSO deals damage to B1", per_target_dmg.get(b1, 0) > 0)
	_chk("I.03 UPDATED by NEW ITEM C: Earthquake now ALSO hits the user's own " +
			"ally (A1) — target_includes_ally was closed by that session",
			per_target_dmg.get(a1, 0) > 0)
	bm.queue_free()


func _test_negative_control_singles_unaffected() -> void:
	var swift := _load_move(129)
	var atk := _make_mon_stats("SinglesAtk", TypeChart.TYPE_NORMAL, 60, 60)
	atk.add_move(swift)
	var def := _make_mon_stats("SinglesDef", TypeChart.TYPE_NORMAL, 60, 60)

	var first_dmg := [-1]
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(a, _d, m, dmg):
		if a == atk and m == swift and first_dmg[0] == -1:
			first_dmg[0] = dmg)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("J.01 negative control: Swift in a plain singles battle still deals " +
			"ordinary single-target damage (new spread branch never fires when " +
			"_active_per_side == 1)",
			first_dmg[0] > 0)
