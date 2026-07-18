extends Node

# [NEW ITEM B] Status-move spread-targeting dispatch (structural gap) — fix +
# tests. Closes the gap found in docs/m21_recon.md's "Full-Roster Spread/
# Status-Target Audit" section: 9 already-implemented status/status-adjacent
# moves (Tail Whip(39)/Leer(43)/Growl(45)/String Shot(81)/Cotton Spore(178)/
# Poison Gas(139)/Sweet Scent(230)/Venom Drench(599), all TARGET_BOTH, plus
# Teeter Dance(298), TARGET_FOES_AND_ALLY) had NO functioning spread dispatch
# in doubles — `is_spread` was structurally never even read for a status-
# category move, since this project's only spread-dispatch loop sat strictly
# inside the damaging-move branch (power > 0).
#
# Fix: new `BattleManager._apply_status_move_to_target()` (the per-target
# gate stack — Magic Bounce/Coat, Substitute, type-immunity, Prankster-vs-
# Dark, then the actual effect — this project's existing single-target
# status dispatch already ran once), called once per live opposing
# combatant (+ally if `target_includes_ally`) in a new early branch of
# `_phase_move_execution`, gated on `foe_targeting and move.is_spread and
# _active_per_side > 1`. Growl/Leer/Tail Whip gained `is_spread=True` (were
# missing it entirely); Teeter Dance gained `target_includes_ally=True`
# (already had `is_spread=True`, but it was inert). NEW ITEM A (the 9
# separate damage-move is_spread gaps) and NEW ITEM C (the
# TARGET_FOES_AND_ALLY ally-hit sweep) are explicitly NOT touched here, per
# the recon doc's own sequencing.
#
# Source citations for the per-target gate-stack design (StatChangeSubstitute's
# own per-battler loop; MoveEndBouncedMove's per-battler bounce bitmask
# confirming each target's bounce is independent) live in docs/m21_recon.md's
# audit section and in `_apply_status_move_to_target`'s own doc comment —
# not repeated here.
#
# Test-audit-first pass (per this project's own established discipline):
# every existing reference to these 9 moves across the whole test suite was
# checked before writing this file. All are either plain singles battles, or
# direct unit tests bypassing full battle dispatch, or (one case,
# d4_bundle8_test.gd's Round test C.03) a genuine doubles battle where the
# move's own targeting is irrelevant to what that test asserts (only Round's
# own damage is checked). Zero existing assertions needed fixing.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_growl_hits_both_opponents_in_doubles()
	_test_venom_drench_per_target_independent_condition()
	_test_teeter_dance_confuses_both_opponents_and_ally()
	_test_substitute_blocks_per_target_independently()
	_test_magic_bounce_reflects_per_target_without_breaking_other_target()
	_test_negative_control_singles_unaffected()
	_test_negative_control_single_target_move_in_doubles_unaffected()

	var total := _pass + _fail
	print("new_item_b_test: %d/%d passed" % [_pass, total])
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
		base_atk: int = 60, base_def: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = 100
	sp.base_attack = base_atk
	sp.base_defense = base_def
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


# Direct single-dispatch helper for a 4-combatant doubles scenario — resolves
# exactly ONE `_phase_move_execution()` call for A0 (idx 0) using `move`,
# bypassing the full multi-turn battle loop entirely. Every one of these 9
# moves is a guaranteed-hit, zero-power status move that would otherwise
# legitimately re-cast every turn in a real multi-turn battle (this
# project's own documented whole-battle-aggregation pitfall) — sidesteps it
# by construction, matching the established direct-dispatch convention (see
# e.g. m21_test.gd's own `_dispatch_doubles_spread_with_signals`).
func _dispatch_doubles_status(a0: BattlePokemon, a1: BattlePokemon,
		b0: BattlePokemon, b1: BattlePokemon, move: MoveData) -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
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
	var tail_whip := _load_move(39)
	var leer := _load_move(43)
	var growl := _load_move(45)
	var string_shot := _load_move(81)
	var poison_gas := _load_move(139)
	var cotton_spore := _load_move(178)
	var sweet_scent := _load_move(230)
	var teeter_dance := _load_move(298)
	var venom_drench := _load_move(599)

	_chk("A.01 Tail Whip is_spread=true (was missing entirely)", tail_whip.is_spread)
	_chk("A.02 Leer is_spread=true (was missing entirely)", leer.is_spread)
	_chk("A.03 Growl is_spread=true (was missing entirely)", growl.is_spread)
	_chk("A.04 String Shot is_spread=true (was already set, previously inert)",
			string_shot.is_spread)
	_chk("A.05 Poison Gas is_spread=true (was already set, previously inert)",
			poison_gas.is_spread)
	_chk("A.06 Cotton Spore is_spread=true (was already set, previously inert)",
			cotton_spore.is_spread)
	_chk("A.07 Sweet Scent is_spread=true (was already set, previously inert)",
			sweet_scent.is_spread)
	_chk("A.08 Venom Drench is_spread=true (was already set, previously inert)",
			venom_drench.is_spread)
	_chk("A.09 Teeter Dance is_spread=true", teeter_dance.is_spread)
	_chk("A.10 Teeter Dance target_includes_ally=true (was missing)",
			teeter_dance.target_includes_ally)
	_chk("A.11 Growl/Leer/Tail Whip do NOT carry target_includes_ally (TARGET_BOTH, not " +
			"TARGET_FOES_AND_ALLY)",
			not tail_whip.target_includes_ally and not leer.target_includes_ally
					and not growl.target_includes_ally)


func _test_growl_hits_both_opponents_in_doubles() -> void:
	var growl := _load_move(45)
	var a0 := _make_mon_stats("GA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("GA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("GB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("GB1", TypeChart.TYPE_NORMAL, 60, 60)

	var bm := _dispatch_doubles_status(a0, a1, b0, b1, growl)
	_chk("B.01 REQUIRED: Growl lowers B0's Attack by 1 stage",
			b0.stat_stages[BattlePokemon.STAGE_ATK] == -1)
	_chk("B.02 REQUIRED: Growl ALSO lowers B1's Attack by 1 stage (the real fix)",
			b1.stat_stages[BattlePokemon.STAGE_ATK] == -1)
	_chk("B.03 the attacker's own Attack is untouched (foe-targeting, not self)",
			a0.stat_stages[BattlePokemon.STAGE_ATK] == 0)
	bm.queue_free()


func _test_venom_drench_per_target_independent_condition() -> void:
	var venom_drench := _load_move(599)
	var a0 := _make_mon_stats("VdA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("VdA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("VdB0", TypeChart.TYPE_NORMAL, 60, 60)
	b0.status = BattlePokemon.STATUS_POISON
	var b1 := _make_mon_stats("VdB1", TypeChart.TYPE_NORMAL, 60, 60)
	# b1 deliberately NOT poisoned — confirms each target's own poison
	# condition is evaluated independently, not shared/computed once.

	var stat_events := {}
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.stat_stage_changed.connect(func(mon, stat, _amt):
		if not stat_events.has(mon):
			stat_events[mon] = []
		stat_events[mon].append(stat))
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [venom_drench, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 3, 0, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()

	_chk("C.01 REQUIRED: the poisoned target (B0) gets all 3 stat drops",
			stat_events.has(b0) and stat_events[b0].size() == 3)
	_chk("C.02 REQUIRED: the non-poisoned target (B1) gets NO stat drop at all " +
			"(each target's own condition evaluated independently)",
			not stat_events.has(b1))
	bm.queue_free()


func _test_teeter_dance_confuses_both_opponents_and_ally() -> void:
	var teeter_dance := _load_move(298)
	var a0 := _make_mon_stats("TdA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("TdA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("TdB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("TdB1", TypeChart.TYPE_NORMAL, 60, 60)

	var bm := _dispatch_doubles_status(a0, a1, b0, b1, teeter_dance)
	_chk("D.01 REQUIRED: Teeter Dance confuses B0 (opponent)", b0.confusion_turns > 0)
	_chk("D.02 REQUIRED: Teeter Dance confuses B1 (opponent)", b1.confusion_turns > 0)
	_chk("D.03 REQUIRED: Teeter Dance ALSO confuses A1 (the user's own ally, " +
			"TARGET_FOES_AND_ALLY)", a1.confusion_turns > 0)
	_chk("D.04 the user itself (A0) is not confused by its own Teeter Dance",
			a0.confusion_turns == 0)
	bm.queue_free()


func _test_substitute_blocks_per_target_independently() -> void:
	var tail_whip := _load_move(39)
	var a0 := _make_mon_stats("SubA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("SubA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("SubB0", TypeChart.TYPE_NORMAL, 60, 60)
	b0.substitute_hp = 50
	var b1 := _make_mon_stats("SubB1", TypeChart.TYPE_NORMAL, 60, 60)
	# b1 deliberately has NO Substitute.

	var bm := _dispatch_doubles_status(a0, a1, b0, b1, tail_whip)
	_chk("E.01 REQUIRED: a Substitute-protected target (B0) is NOT affected",
			b0.stat_stages[BattlePokemon.STAGE_DEF] == 0)
	_chk("E.02 REQUIRED: the OTHER, non-Substitute target (B1) is still hit normally " +
			"in the SAME spread use",
			b1.stat_stages[BattlePokemon.STAGE_DEF] == -1)
	bm.queue_free()


func _test_magic_bounce_reflects_per_target_without_breaking_other_target() -> void:
	var growl := _load_move(45)
	var a0 := _make_mon_stats("MbA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("MbA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("MbB0", TypeChart.TYPE_NORMAL, 60, 60)
	var magic_bounce := AbilityData.new()
	magic_bounce.ability_id = AbilityManager.ABILITY_MAGIC_BOUNCE
	b0.ability = magic_bounce
	var b1 := _make_mon_stats("MbB1", TypeChart.TYPE_NORMAL, 60, 60)
	# b1 deliberately has no Magic Bounce.

	var bounced := [false]
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.move_bounced.connect(func(holder, _origin): if holder == b0: bounced[0] = true)
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [growl, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 3, 0, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()

	_chk("F.01 REQUIRED: B0 (Magic Bounce) reflects Growl instead of taking the drop",
			bounced[0] == true and b0.stat_stages[BattlePokemon.STAGE_ATK] == 0)
	_chk("F.02 REQUIRED: the reflected Growl lowers the ORIGINAL ATTACKER's (A0) own " +
			"Attack instead",
			a0.stat_stages[BattlePokemon.STAGE_ATK] == -1)
	_chk("F.03 REQUIRED: the OTHER target (B1, no Magic Bounce) is STILL hit normally " +
			"by the original move, in the SAME spread use — a bounce by one target " +
			"does not cancel resolution against the other",
			b1.stat_stages[BattlePokemon.STAGE_ATK] == -1)
	bm.queue_free()


func _test_negative_control_singles_unaffected() -> void:
	# start_battle runs a full multi-turn battle to completion; Growl has no
	# other move to fall back to, so it keeps re-casting every turn (this
	# project's own documented whole-battle-aggregation pitfall — a post-
	# battle read of stat_stages would see well past -1 by the time the
	# battle ends). Snapshotted via the FIRST stat_stage_changed event
	# instead, matching CLAUDE.md's own established convention.
	var growl := _load_move(45)
	var atk := _make_mon_stats("SinglesAtk", TypeChart.TYPE_NORMAL, 60, 60)
	atk.add_move(growl)
	var def := _make_mon_stats("SinglesDef", TypeChart.TYPE_NORMAL, 60, 60)

	var first_stage := [999]
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.stat_stage_changed.connect(func(mon, stat, _amt):
		if mon == def and stat == BattlePokemon.STAGE_ATK and first_stage[0] == 999:
			first_stage[0] = def.stat_stages[BattlePokemon.STAGE_ATK])
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("G.01 negative control: Growl in a plain singles battle still lowers the " +
			"single defender's Attack (new spread branch never fires when " +
			"_active_per_side == 1)",
			first_stage[0] == -1)


func _test_negative_control_single_target_move_in_doubles_unaffected() -> void:
	# Scary Face(184): TARGET_SELECTED, -2 Speed, single-target — is_spread
	# must be false, and must never accidentally hit the second opponent.
	var scary_face := _load_move(184)
	_chk("H.00 sanity: Scary Face is NOT flagged is_spread (ordinary single-target " +
			"move, unaffected by this session's changes)", not scary_face.is_spread)

	var a0 := _make_mon_stats("SfA0", TypeChart.TYPE_NORMAL, 60, 60)
	var a1 := _make_mon_stats("SfA1", TypeChart.TYPE_NORMAL, 60, 60)
	var b0 := _make_mon_stats("SfB0", TypeChart.TYPE_NORMAL, 60, 60)
	var b1 := _make_mon_stats("SfB1", TypeChart.TYPE_NORMAL, 60, 60)

	var bm := _dispatch_doubles_status(a0, a1, b0, b1, scary_face)
	_chk("H.01 negative control: an ordinary single-target status move in doubles " +
			"still only hits the one selected target (B0)",
			b0.stat_stages[BattlePokemon.STAGE_SPEED] == -2)
	_chk("H.02 negative control: the OTHER opponent (B1) is untouched",
			b1.stat_stages[BattlePokemon.STAGE_SPEED] == 0)
	bm.queue_free()
