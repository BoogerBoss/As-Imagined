class_name AnimDispatcher
extends RefCounted

# [M36B] The decision point between the ported animation engine and the
# legacy hit-effect. Scope of record: docs/m26_f1_recon.md §5.2.
#
# One question, asked per move: can the engine play this faithfully right now?
# If yes, the VM runs the real script. If anything it needs is unported, the
# move plays the M23.11 hit-effect it plays today. Nothing in between.
#
# The point of routing every move through here from the START of M36 -- while
# the registry is still empty and therefore EVERY move falls back -- is that
# the seam is exercised and tested long before it changes any pixels. When
# M36C registers its first batch, those moves light up and the rest keep
# working unchanged.

# Why a move fell back, for the coverage report M36D builds on.
enum Reason { PLAYABLE, DATA_MISSING, NO_SCRIPT, MISSING_BEHAVIORS, EMPTY_SCRIPT }

var registry: AnimBehaviorRegistry
var _verdict_cache: Dictionary = {}


func _init(behavior_registry: AnimBehaviorRegistry = null) -> void:
	registry = behavior_registry if behavior_registry != null \
			else AnimBehaviorRegistry.new()


# Verdict for a move id: {reason, label, missing}. Cached per move id --
# the answer depends only on the data and the registry contents, both fixed
# for a run, so it is stable and worth memoising across a battle.
func verdict_for_move(move_id: int) -> Dictionary:
	if _verdict_cache.has(move_id):
		return _verdict_cache[move_id]

	var out := {"reason": Reason.PLAYABLE, "label": "", "missing": []}
	if not AnimData.ensure_loaded():
		out = {"reason": Reason.DATA_MISSING, "label": "",
				"missing": [AnimData.load_error()]}
	else:
		var label := AnimData.script_for_move(move_id)
		if label == "":
			out = {"reason": Reason.NO_SCRIPT, "label": "", "missing": []}
		elif registry.referenced_behaviors(label).is_empty():
			# A script that reaches `end` without creating a single sprite or
			# task draws nothing. Upstream that is legitimate for exactly one
			# move -- Secret Power's body IS just `end`, because
			# LaunchBattleAnimation REMAPS it at launch to whichever script
			# the current terrain calls for, so the placeholder is never
			# actually executed. We do not model that remap (Secret Power is
			# permanently excluded from this project anyway), and "play a
			# script that renders nothing" would be a silent regression from
			# the generic hit-effect. So an empty script falls back too.
			out = {"reason": Reason.EMPTY_SCRIPT, "label": label,
					"missing": []}
		else:
			var missing := registry.missing_behaviors(label)
			out = {
				"reason": Reason.PLAYABLE if missing.is_empty()
						else Reason.MISSING_BEHAVIORS,
				"label": label,
				"missing": missing,
			}
	_verdict_cache[move_id] = out
	return out


func can_play_move(move_id: int) -> bool:
	return int(verdict_for_move(move_id).get("reason", Reason.NO_SCRIPT)) \
			== Reason.PLAYABLE


# Builds a VM primed for this move, or null if it must fall back. The caller
# owns pumping it (the battle screen does so from its own frame clock, inside
# the existing "anim" beat, so the reference's damage -> anim -> flicker ->
# HP-drain ordering is untouched).
func make_vm(move_id: int, stage, move_turn: int = 0) -> AnimScriptVM:
	var verdict := verdict_for_move(move_id)
	if int(verdict.get("reason", Reason.NO_SCRIPT)) != Reason.PLAYABLE:
		return null
	var vm := AnimScriptVM.new()
	vm.registry = registry
	vm.stage = stage
	vm.move_turn = move_turn
	if not vm.start(str(verdict.get("label", ""))):
		return null
	return vm


# Coverage across every move this project implements: how many can play, and
# which behaviors are blocking the rest (most-blocking first). This is the
# report M36D sequences its batches from -- decision 5's ordering picks the
# moves, this says what porting them costs.
func coverage(move_ids: Array) -> Dictionary:
	var playable := 0
	var no_script := 0
	var blocked := 0
	var blocker_counts := {}
	for id in move_ids:
		var v := verdict_for_move(int(id))
		match int(v.get("reason", Reason.NO_SCRIPT)):
			Reason.PLAYABLE:
				playable += 1
			Reason.NO_SCRIPT, Reason.EMPTY_SCRIPT:
				no_script += 1
			_:
				blocked += 1
				for symbol in (v.get("missing", []) as Array):
					blocker_counts[symbol] = int(
							blocker_counts.get(symbol, 0)) + 1
	var ranked: Array = []
	for symbol in blocker_counts:
		ranked.append({"symbol": symbol, "moves": int(blocker_counts[symbol])})
	ranked.sort_custom(func(a, b): return int(a["moves"]) > int(b["moves"]))
	return {
		"total": move_ids.size(),
		"playable": playable,
		"blocked": blocked,
		"no_script": no_script,
		"top_blockers": ranked,
	}


func invalidate_cache() -> void:
	_verdict_cache.clear()
