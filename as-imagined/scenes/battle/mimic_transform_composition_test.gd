extends Node

# [M19.5 Task 2] Transform + Mimic composition bug — confirmed real and
# reachable during the M19.5 recon, fixed here. If the attacker has an
# ACTIVE Mimic overlay (used Mimic earlier this same stint, hasn't switched
# out since) at the moment it casts Transform, the pre-fix code snapshotted
# `pre_transform_moves` BEFORE restoring the overlaid slot back to Mimic —
# permanently losing the "revert to Mimic on switch-out" information. Fix:
# BattleManager's Transform dispatch now calls _reset_mon_mimicked_move(
# attacker) FIRST, if mimicked_slot >= 0, before snapshotting.
#
# Ground truth for the fix's correctness model: source's own dual-layer
# struct (temp battle struct + untouched party record) means Mimic and
# Transform are both ephemeral mutations discarded wholesale via a fresh
# party-record re-derivation on switch-in — this project's own per-mechanic
# snapshot/restore fields need this explicit ordering to reproduce that.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_mimic_then_transform_reverts_to_mimic()

	var total := _pass + _fail
	print("mimic_transform_composition_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = 100
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# Direct single-dispatch helper, matching the convention established across
# the M19/M19.5 test suites.
func _dispatch_move(combatants: Array[BattlePokemon], attacker_idx: int, move: MoveData) -> BattleManager:
	var bm := _make_bm()
	bm._combatants = combatants
	bm._active_per_side = combatants.size() / 2
	var actor_indices := {}
	for i in range(combatants.size()):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	var chosen_moves: Array = []
	for i in range(combatants.size()):
		chosen_moves.append(move if i == attacker_idx else null)
	bm._chosen_moves = chosen_moves
	var chosen_switch_slots: Array[int] = []
	for i in range(combatants.size()):
		chosen_switch_slots.append(-1)
	bm._chosen_switch_slots = chosen_switch_slots
	var other_idx: int = 1 if attacker_idx == 0 else 0
	var chosen_targets: Array[int] = []
	for i in range(combatants.size()):
		chosen_targets.append(other_idx if i == attacker_idx else attacker_idx)
	bm._chosen_targets = chosen_targets
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = attacker_idx
	bm._phase_move_execution()
	return bm


func _test_mimic_then_transform_reverts_to_mimic() -> void:
	var mimic := _load_move(102)
	var tackle := _load_move(33)
	var ember := _load_move(52)

	var attacker := _make_mon("MTAtk")
	attacker.add_move(mimic)
	attacker.add_move(tackle)

	# Step 1: attacker successfully Mimics Ember (Mimic occupies slot 0's
	# overlay — mimicked_slot=0, mimicked_original_move=Mimic).
	var mimic_target := _make_mon("MTMimicTarget")
	mimic_target.last_move_used = ember
	var bm1 := _dispatch_move([attacker, mimic_target], 0, mimic)
	_chk("01 Mimic succeeded: attacker's slot 0 now holds Ember",
			attacker.moves[0] == ember)
	_chk("02 mimicked_slot correctly tracks slot 0", attacker.mimicked_slot == 0)
	_chk("03 mimicked_original_move correctly records Mimic itself",
			attacker.mimicked_original_move == mimic)
	bm1.queue_free()

	# Step 2: SAME attacker, same stint (no switch-out in between), now
	# Transforms into a different target. Attacker's slot 0 currently holds
	# Ember (the active Mimic overlay) — this is exactly the composition
	# scenario Step 0 flagged.
	var xform_target := _make_mon("MTXformTarget", TypeChart.TYPE_WATER)
	var xform_target_move := _load_move(56)  # Hydro Pump — a real, distinct move
	xform_target.add_move(xform_target_move)
	# xform is not itself in attacker.moves, but the direct-dispatch helper
	# doesn't require that (matches every other test in this arc).
	var xform := _load_move(144)
	var bm2 := _dispatch_move([attacker, xform_target], 0, xform)
	_chk("04 Transform succeeded", attacker.transformed == true)
	_chk("05 attacker's moves now reflect the Transform target's moveset " +
			"(slot 0 is Hydro Pump, not Ember)",
			attacker.moves[0] == xform_target_move)
	_chk("06 pre_transform_moves captured MIMIC ITSELF in slot 0 — NOT Ember " +
			"(the temporarily-mimicked move) — this is the actual fix under test",
			attacker.pre_transform_moves[0] == mimic)
	_chk("07 mimicked_slot correctly cleared by the pre-snapshot restore",
			attacker.mimicked_slot == -1)
	bm2.queue_free()

	# Step 3: switch the attacker out, then back in — confirm the moveset
	# reverts to the ORIGINAL Mimic move slot (Mimic itself), NOT the
	# Transform target's copied moveset, and NOT whatever Mimic had
	# temporarily copied (Ember).
	var bench := _make_mon("MTBench")
	var party := BattleParty.new()
	party.members = [attacker, bench]

	var bm3 := _make_bm()
	bm3._active_per_side = 1
	bm3._parties = [party]
	bm3._combatants = [attacker]
	bm3._do_voluntary_switch(0, 1)  # switch attacker OUT to bench
	_chk("08 immediately after switching OUT, attacker is STILL Transformed " +
			"(reset runs on the INCOMING mon, not the outgoing one)",
			attacker.transformed == true)

	bm3._do_voluntary_switch(0, 0)  # switch BACK to attacker
	_chk("09 moveset correctly reverted to Mimic itself in slot 0 " +
			"(NOT Ember, NOT Hydro Pump)", attacker.moves[0] == mimic)
	_chk("10 slot 1 correctly reverted to Tackle (attacker's other real move)",
			attacker.moves[1] == tackle)
	_chk("11 transformed flag cleared", attacker.transformed == false)
	_chk("12 mimicked_slot remains cleared (nothing left to restore twice)",
			attacker.mimicked_slot == -1)
	bm3.queue_free()
