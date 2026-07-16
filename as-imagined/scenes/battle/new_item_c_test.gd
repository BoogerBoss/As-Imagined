extends Node

# [NEW ITEM C] TARGET_FOES_AND_ALLY full-roster ally-hit sweep — fix + tests.
# Closes NEW ITEM C from docs/m21_recon.md's "Full-Roster Spread/Status-
# Target Audit" section (and the original item 4 follow-up from M21's own
# bundle-safe session): 20 real source moves carry TARGET_FOES_AND_ALLY
# (hits both opponents AND the user's own ally in doubles). Self-
# Destruct(120)/Explosion(153) were already fixed by M21's own bundle-safe
# session; Teeter Dance(298) already got BOTH `is_spread` and
# `target_includes_ally` from the same-arc NEW ITEM B session. This session
# closes the remaining 13: Magnitude(222), Discharge(435), Lava
# Plume(436), Sludge Wave(482), Bulldoze(523), Searing Shot(545),
# Parabolic Charge(570), Petal Blizzard(572), Boomburst(586), Sparkling
# Aria(627), Brutal Swing(656) (already `is_spread=True`, just needed
# `target_includes_ally`), plus Surf(57)/Earthquake(89) (fixed by NEW ITEM A
# this same arc, which deliberately left `target_includes_ally` unset for
# THIS session to close with its own test-audit-first pass).
#
# Step 0 (see docs/decisions.md's own entry for this session) re-confirmed
# fresh, not copied from prior sessions:
#   - The full 20-move TARGET_FOES_AND_ALLY list, re-derived via a fresh
#     `moves_info.h` grep, cross-checked against current `gen_moves.py`
#     state — confirming the corrected 13-move worklist above (not 11, not
#     18 — Surf/Earthquake needed the flag too, Teeter Dance needed
#     nothing).
#   - `GetTargetDamageModifier` (battle_util.c L7220-7229): the flat
#     `UQ_4_12(0.75)` applies identically whether `GetMoveTargetCount`
#     returns 2 (opponents only) or >=3 (opponents + ally) — re-confirmed
#     fresh, not just re-cited from the Self-Destruct/Explosion finding.
#   - `GetMoveTargetCount`'s own `TARGET_FOES_AND_ALLY` case
#     (battle_util.c L5993-5996) sums THREE terms — both opponents plus
#     `BATTLE_PARTNER(battlerAtk)` (the user's own ally) — re-confirmed.
#   - Magnitude's own `is_magnitude` power-roll and Sparkling Aria's own
#     `is_sparkling_aria` burn-cure both confirmed to compose correctly
#     with the ally as an additional target: Magnitude's roll happens once
#     via `_dmg_power_override` before the spread/single split (same shape
#     already proven for Eruption in NEW ITEM A); Sparkling Aria's cure
#     reads the per-target `target` parameter inside `_do_damaging_hit`
#     (called once per target, including the ally once
#     `target_includes_ally` is set), so it correctly cures the ally's own
#     burn too if hit.
#   - **A real, specifically-checked interaction, not assumed safe**:
#     `AbilityManager.pressure_pp_cost`'s own spread-move branch
#     (`ability_manager.gd:1803-1812`) loops ONLY over the opposing side's
#     combatants (`opp_start = (1 - attacker_side) * active_per_side`) —
#     it never reads `target_includes_ally` and structurally cannot count
#     the ally, regardless of this session's own changes. Re-confirmed
#     against source (`CancelerPPDeduction`'s own comment, already cited
#     in that function's doc) that Pressure's PP surcharge is opponent-only
#     by design, even for a TARGET_FOES_AND_ALLY move that also hits the
#     ally — this session's fix does NOT touch or risk that mechanism.
#   - Parabolic Charge(570)'s drain re-confirmed to need NO change: the
#     drain (`damage * move.drain_percent / 100`) is computed inside
#     `_do_damaging_hit`, called once per target in the spread loop — the
#     ally is simply one more target in that SAME existing loop, healing
#     the attacker off the ally's own hit independently, exactly matching
#     source's real per-hit (not accumulate-then-heal-once) drain
#     behavior. This is explicitly NOT the Shell-Bell-style accumulation
#     pattern and must never become one.
#
# Test-audit-first pass (per this project's own discipline): checked every
# existing reference to these 13 moves across the test suite before
# writing this file. Found ONE genuine doubles-context test —
# `m17n10_test.gd`'s S6.03 (Magnitude vs two Pressure holders) — confirmed
# UNAFFECTED: its own ally fixture doesn't hold Pressure, and
# `pressure_pp_cost` structurally can't count the ally anyway (see above).
# Also found and fixed 4 now-stale assertions in this arc's OWN
# `new_item_a_test.gd` (A.10/A.11/H.03/I.03), which had explicitly asserted
# Surf/Earthquake's OLD "ally not yet hit" boundary — updated in place to
# assert the new, fully-correct behavior.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_discharge_hits_both_opponents_and_ally()
	_test_spread_reduction_applies_in_three_target_case()
	_test_parabolic_charge_drains_per_hit_including_ally()
	_test_sparkling_aria_cures_ally_burn_too()
	_test_pressure_pp_cost_unaffected_by_ally_target()
	_test_negative_control_rock_slide_still_excludes_ally()
	_test_negative_control_singles_unaffected()

	var total := _pass + _fail
	print("new_item_c_test: %d/%d passed" % [_pass, total])
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
# new_item_a_test.gd's own `_dispatch_doubles_damage` — resolves exactly ONE
# `_phase_move_execution()` call for A0 (idx 0), bypassing the full
# multi-turn battle loop entirely.
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
	var magnitude := _load_move(222)
	var discharge := _load_move(435)
	var lava_plume := _load_move(436)
	var sludge_wave := _load_move(482)
	var bulldoze := _load_move(523)
	var searing_shot := _load_move(545)
	var parabolic_charge := _load_move(570)
	var petal_blizzard := _load_move(572)
	var boomburst := _load_move(586)
	var sparkling_aria := _load_move(627)
	var brutal_swing := _load_move(656)
	var surf := _load_move(57)
	var earthquake := _load_move(89)

	_chk("A.01 Magnitude target_includes_ally=true (was missing)", magnitude.target_includes_ally)
	_chk("A.02 Discharge target_includes_ally=true (was missing)", discharge.target_includes_ally)
	_chk("A.03 Lava Plume target_includes_ally=true (was missing)", lava_plume.target_includes_ally)
	_chk("A.04 Sludge Wave target_includes_ally=true (was missing)", sludge_wave.target_includes_ally)
	_chk("A.05 Bulldoze target_includes_ally=true (was missing)", bulldoze.target_includes_ally)
	_chk("A.06 Searing Shot target_includes_ally=true (was missing)", searing_shot.target_includes_ally)
	_chk("A.07 Parabolic Charge target_includes_ally=true (was missing)",
			parabolic_charge.target_includes_ally)
	_chk("A.08 Petal Blizzard target_includes_ally=true (was missing)",
			petal_blizzard.target_includes_ally)
	_chk("A.09 Boomburst target_includes_ally=true (was missing)", boomburst.target_includes_ally)
	_chk("A.10 Sparkling Aria target_includes_ally=true (was missing)",
			sparkling_aria.target_includes_ally)
	_chk("A.11 Brutal Swing target_includes_ally=true (was missing)", brutal_swing.target_includes_ally)
	_chk("A.12 Surf target_includes_ally=true (closed this session, deferred by NEW ITEM A)",
			surf.target_includes_ally)
	_chk("A.13 Earthquake target_includes_ally=true (closed this session, deferred by " +
			"NEW ITEM A)", earthquake.target_includes_ally)

	# Already-done confirmations (no change expected/needed).
	var self_destruct := _load_move(120)
	var explosion := _load_move(153)
	var teeter_dance := _load_move(298)
	_chk("A.14 Self-Destruct already correct (M21's own bundle-safe session)",
			self_destruct.target_includes_ally)
	_chk("A.15 Explosion already correct (M21's own bundle-safe session)",
			explosion.target_includes_ally)
	_chk("A.16 Teeter Dance already correct (NEW ITEM B this same arc) — " +
			"confirmed NO changes needed for it in this session",
			teeter_dance.target_includes_ally and teeter_dance.is_spread)


func _test_discharge_hits_both_opponents_and_ally() -> void:
	var discharge := _load_move(435)
	var a0 := _make_mon_stats("DcA0", TypeChart.TYPE_ELECTRIC, 60, 60)
	var a1 := _make_mon_stats("DcA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("DcB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("DcB1", TypeChart.TYPE_NORMAL, 60, 60)

	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, discharge, per_target_dmg)
	_chk("B.01 REQUIRED: Discharge deals damage to B0 (opponent)", per_target_dmg.get(b0, 0) > 0)
	_chk("B.02 REQUIRED: Discharge ALSO deals damage to B1 (opponent)",
			per_target_dmg.get(b1, 0) > 0)
	_chk("B.03 REQUIRED (the core fix): Discharge ALSO deals damage to A1 " +
			"(the user's own ally, TARGET_FOES_AND_ALLY)", per_target_dmg.get(a1, 0) > 0)
	bm.queue_free()


func _test_spread_reduction_applies_in_three_target_case() -> void:
	# 3-live-target damage (2 opponents + ally) should be LESS than a
	# 1-live-target comparison, confirming the 0.75x reduction still
	# applies correctly once the ally becomes a genuine third target.
	var discharge := _load_move(435)
	var a0 := _make_mon_stats("SrA0", TypeChart.TYPE_ELECTRIC, 60, 60)
	var a1 := _make_mon_stats("SrA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("SrB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("SrB1", TypeChart.TYPE_NORMAL, 60, 60)
	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, discharge, per_target_dmg)
	var three_target_dmg: int = per_target_dmg.get(b0, 0)
	bm.queue_free()

	# 1-live-target comparison: ally and B1 both fainted before resolution.
	var a0_s := _make_mon_stats("SrA0S", TypeChart.TYPE_ELECTRIC, 60, 60)
	var a1_s := _make_mon_stats("SrA1S", TypeChart.TYPE_NORMAL, 60, 60)
	a1_s.current_hp = 0
	a1_s.fainted = true
	var b0_s := _make_mon_stats("SrB0S", TypeChart.TYPE_NORMAL, 60, 60)
	var b1_s := _make_mon_stats("SrB1S", TypeChart.TYPE_NORMAL, 60, 60)
	b1_s.current_hp = 0
	b1_s.fainted = true
	var per_target_dmg_s := {}
	var bm2 := _dispatch_doubles_damage(a0_s, a1_s, b0_s, b1_s, discharge, per_target_dmg_s)
	var single_target_dmg: int = per_target_dmg_s.get(b0_s, 0)
	bm2.queue_free()

	_chk("C.01 REQUIRED: the 0.75x spread-reduction still applies correctly in the " +
			"3-target (2 opponents + ally) case — damage (%d) is strictly less " % [three_target_dmg] +
			"than the 1-target comparison (%d)" % [single_target_dmg],
			three_target_dmg > 0 and single_target_dmg > 0 and three_target_dmg < single_target_dmg)


func _test_parabolic_charge_drains_per_hit_including_ally() -> void:
	# REQUIRED guardrail: the heal amount must be tied to the TOTAL damage
	# dealt across all 3 targets (each hit's own drain applied independently
	# and summed via separate current_hp increments), NOT a single combined
	# "heal once" the Shell-Bell way. Since drain is applied via 3 SEPARATE
	# current_hp additions inside 3 separate _do_damaging_hit calls, the
	# attacker's total HP GAIN should equal 50% of the SUM of the 3 targets'
	# own individual damage taken — confirming per-hit computation, not a
	# combined-then-halved total (which would coincidentally look similar
	# for damage but is architecturally different — checked via item_healed
	# firing 3 times, once per hit, not once for the whole move).
	var parabolic_charge := _load_move(570)
	var a0 := _make_mon_stats("PcA0", TypeChart.TYPE_ELECTRIC, 60, 60)
	a0.current_hp = a0.max_hp / 2
	var a1 := _make_mon_stats("PcA1", TypeChart.TYPE_NORMAL, 60, 60, 300)
	var b0 := _make_mon_stats("PcB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("PcB1", TypeChart.TYPE_NORMAL, 60, 100)

	var per_target_dmg := {}
	var heal_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(atk, d, mv, dmg):
		if atk == a0 and mv == parabolic_charge and not per_target_dmg.has(d):
			per_target_dmg[d] = dmg
	)
	bm.drain_heal.connect(func(mon, amount):
		if mon == a0:
			heal_events.append(amount))
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [parabolic_charge, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 3, 0, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()

	_chk("D.01 REQUIRED: Parabolic Charge hits all 3 targets (B0, B1, and the " +
			"ally A1)", per_target_dmg.has(b0) and per_target_dmg.has(b1) and per_target_dmg.has(a1))
	_chk("D.02 REQUIRED guardrail: exactly 3 SEPARATE drain_heal events fire " +
			"(one per hit, confirming per-hit drain, not accumulate-then-heal-once " +
			"the Shell-Bell way)", heal_events.size() == 3)
	var expected_total_heal: int = 0
	for d in [per_target_dmg.get(b0, 0), per_target_dmg.get(b1, 0), per_target_dmg.get(a1, 0)]:
		expected_total_heal += d * 50 / 100
	var actual_total_heal: int = 0
	for h in heal_events:
		actual_total_heal += h
	_chk("D.03 REQUIRED: total healing (%d) equals the SUM of each individual " % [actual_total_heal] +
			"hit's own 50%% drain (%d), confirming per-hit computation including " % [expected_total_heal] +
			"the ally's own hit", actual_total_heal == expected_total_heal)
	bm.queue_free()


func _test_sparkling_aria_cures_ally_burn_too() -> void:
	var sparkling_aria := _load_move(627)
	var a0 := _make_mon_stats("SaA0", TypeChart.TYPE_WATER, 60, 60)
	var a1 := _make_mon_stats("SaA1", TypeChart.TYPE_NORMAL, 60, 60)
	a1.status = BattlePokemon.STATUS_BURN
	var b0 := _make_mon_stats("SaB0", TypeChart.TYPE_NORMAL, 60, 60)
	b0.status = BattlePokemon.STATUS_BURN
	var b1 := _make_mon_stats("SaB1", TypeChart.TYPE_NORMAL, 60, 60)

	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, sparkling_aria, per_target_dmg)
	_chk("E.01 Sparkling Aria cures the opponent's (B0) own burn", b0.status == BattlePokemon.STATUS_NONE)
	_chk("E.02 REQUIRED: Sparkling Aria ALSO cures the user's own ally's (A1) " +
			"burn, confirming the per-target cure composes correctly with the new " +
			"ally target", a1.status == BattlePokemon.STATUS_NONE)
	bm.queue_free()


func _test_pressure_pp_cost_unaffected_by_ally_target() -> void:
	# Re-verifies the specific interaction checked in Step 0: Magnitude vs
	# two Pressure holders in doubles still costs exactly 3 PP (1 base + 1
	# per opposing Pressure holder), NOT 4, even now that the user's own
	# ally is also a target of the move — pressure_pp_cost structurally
	# only ever loops the opposing side.
	var pressure := _load_ability(46)
	var magnitude := _load_move(222)
	var atk := _make_mon_stats("PpAtk", TypeChart.TYPE_NORMAL, 60, 60)
	atk.add_move(magnitude)
	var ally := _make_mon_stats("PpAlly", TypeChart.TYPE_NORMAL, 60, 60)
	ally.ability = pressure
	var opp0 := _make_mon_stats("PpOpp0", TypeChart.TYPE_NORMAL, 60, 60)
	opp0.ability = pressure
	var opp1 := _make_mon_stats("PpOpp1", TypeChart.TYPE_NORMAL, 60, 60)
	opp1.ability = pressure

	var combatants: Array[BattlePokemon] = [atk, ally, opp0, opp1]
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	var cost: int = AbilityManager.pressure_pp_cost(magnitude, atk, opp0, 0, combatants, 2, false)
	_chk("F.01 REQUIRED: Magnitude's PP cost vs 2 opposing Pressure holders is still " +
			"3 (1 base + 2 opponents), NOT 4, even though the user's own ally ALSO " +
			"holds Pressure and is now a real target of the move (%d)" % [cost],
			cost == 3)


func _test_negative_control_rock_slide_still_excludes_ally() -> void:
	var rock_slide := _load_move(157)
	_chk("G.00 sanity: Rock Slide does NOT carry target_includes_ally (TARGET_BOTH, " +
			"not TARGET_FOES_AND_ALLY — unaffected by this session)",
			not rock_slide.target_includes_ally)

	var a0 := _make_mon_stats("RsA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("RsA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("RsB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("RsB1", TypeChart.TYPE_NORMAL, 60, 60)

	var per_target_dmg := {}
	var bm := _dispatch_doubles_damage(a0, a1, b0, b1, rock_slide, per_target_dmg)
	_chk("G.01 negative control: Rock Slide still hits both opponents",
			per_target_dmg.get(b0, 0) > 0 and per_target_dmg.get(b1, 0) > 0)
	_chk("G.02 REQUIRED negative control: Rock Slide still correctly excludes the " +
			"user's own ally (A1) — a move without target_includes_ally must NOT " +
			"be affected by this session's changes to other moves",
			not per_target_dmg.has(a1))
	bm.queue_free()


func _test_negative_control_singles_unaffected() -> void:
	var discharge := _load_move(435)
	var atk := _make_mon_stats("SinglesAtk", TypeChart.TYPE_ELECTRIC, 60, 60)
	atk.add_move(discharge)
	var def := _make_mon_stats("SinglesDef", TypeChart.TYPE_NORMAL, 60, 60)

	var first_dmg := [-1]
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(a, _d, m, dmg):
		if a == atk and m == discharge and first_dmg[0] == -1:
			first_dmg[0] = dmg)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("H.01 negative control: Discharge in a plain singles battle still deals " +
			"ordinary single-target damage (no ally exists, no crash)",
			first_dmg[0] > 0)
