class_name AnimBehaviorRegistry
extends RefCounted

# [M36B] The behavior registry and the FALLBACK CONTRACT.
#
# The reference's animation scripts are data (M36A extracted them); the thing
# they call into is ~1,010 sprite callbacks and ~264 tasks of C. M36 ports
# those in prioritised batches (M36C onward), which means at any given moment
# some are implemented and most are not.
#
# The contract that makes a partial port shippable:
#
#   Before an animation runs, its script is walked and every behavior it could
#   reach is collected. If ANY is unimplemented, the whole move falls back to
#   the legacy hit-effect. A script never plays half-way.
#
# That is deliberate. A partially-executed script is worse than the generic
# effect it replaces -- sprites that never move, waits that never resolve,
# a target left mid-flinch. All-or-nothing per move keeps every intermediate
# state of the port genuinely shippable, which is the whole basis on which
# the tiered approach was approved (docs/m26_f1_recon.md §5, §6.1).
#
# The walk is static (it follows every branch, not the branch a given battle
# would take), so a move's verdict never changes between battles.

# name -> Callable. Sprite callbacks and task functions share one namespace
# because the scripts reference them the same way: by C symbol name.
var _behaviors: Dictionary = {}

# Opcodes whose FIRST argument names a behavior symbol.
const _SPRITE_OPS := {
	"createsprite": true,
	"createspriteontargets": true,
	"createspriteontargets_onpos": true,
	"createdragondartsprite": true,
}
const _TASK_OPS := {
	"createvisualtask": true,
	"createvisualtaskontargets": true,
}

# `createsoundtask` is deliberately NOT a behavior op. The VM handles it
# itself -- it records the cue for M36-S and moves on -- and upstream those
# tasks report to a SEPARATE counter (gAnimSoundTaskCount) that
# `waitforvisualfinish` does not wait on. Demanding a registered behavior for
# them would block moves on symbols nothing ever calls.

# Opcodes that move the program counter somewhere other than the next command.
const _JUMP_OPS := {"call": 1, "goto": 1, "jumpifcontest": 1}


func register(symbol: String, fn: Callable) -> void:
	_behaviors[symbol] = fn


func register_many(map: Dictionary) -> void:
	for symbol in map:
		_behaviors[str(symbol)] = map[symbol]


func has(symbol: String) -> bool:
	return _behaviors.has(symbol)


func get_behavior(symbol: String) -> Callable:
	return _behaviors.get(symbol, Callable())


func size() -> int:
	return _behaviors.size()


func clear() -> void:
	_behaviors.clear()


# Every behavior symbol reachable from `label`, following call/goto/branch
# targets. Sorted for stable output (tests and the coverage report both
# depend on ordering being deterministic).
func referenced_behaviors(label: String) -> Array[String]:
	var found := {}
	_walk(label, found, {})
	var out: Array[String] = []
	for key in found:
		out.append(str(key))
	out.sort()
	return out


# The fallback verdict: which of a script's behaviors are missing. Empty
# means the VM may run it.
func missing_behaviors(label: String) -> Array[String]:
	var out: Array[String] = []
	for symbol in referenced_behaviors(label):
		if not _behaviors.has(symbol):
			out.append(symbol)
	return out


func can_play(label: String) -> bool:
	return missing_behaviors(label).is_empty()


# Walks the command program from `label`. `visited` is keyed by command index
# so backward `goto`s (the scripts' only loop construct) terminate.
func _walk(label: String, found: Dictionary, visited: Dictionary) -> void:
	var start := AnimData.label_index(label)
	if start < 0:
		# An unresolvable label cannot be played. Recorded as a pseudo-symbol
		# so the caller reports a reason rather than silently passing a script
		# with no body.
		found["<missing label: %s>" % label] = true
		return

	var commands := AnimData.commands()
	var pc := start
	while pc >= 0 and pc < commands.size():
		if visited.has(pc):
			return
		visited[pc] = true

		var cmd: Array = commands[pc]
		var op := str(cmd[0])

		if _SPRITE_OPS.has(op) and cmd.size() > 1:
			# createdragondartsprite builds its template inline (no symbol
			# argument); its callback is fixed upstream.
			if op == "createdragondartsprite":
				found["AnimShadowBall"] = true
			else:
				var tmpl := str(cmd[1])
				var callback: Variant = AnimData.template(tmpl).get("callback")
				if callback == null:
					# A template with no callback is inert but legal (the
					# invisible "controller sprite" idiom uses one).
					pass
				else:
					found[str(callback)] = true
		elif _TASK_OPS.has(op) and cmd.size() > 1:
			found[str(cmd[1])] = true
		elif op == "choosetwoturnanim" and cmd.size() > 2:
			# Both turns are reachable across a battle, so both count.
			_walk_from_label(str(cmd[1]), found, visited)
			_walk_from_label(str(cmd[2]), found, visited)
			return
		elif op == "jumpifmoveturn" and cmd.size() > 2:
			_walk_from_label(str(cmd[2]), found, visited)
		elif op == "jumpargeq" and cmd.size() > 3:
			_walk_from_label(str(cmd[3]), found, visited)
		elif op == "jumpifmovetypeequal" and cmd.size() > 2:
			_walk_from_label(str(cmd[2]), found, visited)
		elif _JUMP_OPS.has(op) and cmd.size() > 1:
			var target := str(cmd[1])
			if op == "goto":
				# Unconditional: control leaves here entirely.
				_walk_from_label(target, found, visited)
				return
			_walk_from_label(target, found, visited)
		elif op == "end" or op == "return":
			# `return` ends this body just as `end` does. Without stopping
			# here the walk runs off the end of a `call` subroutine and into
			# whatever script happens to sit next in the command array --
			# which made moves look blocked on behaviors they never reference
			# (Flamethrower appeared to need SANDSTORM tasks).
			return

		pc += 1


func _walk_from_label(label: String, found: Dictionary,
		visited: Dictionary) -> void:
	var idx := AnimData.label_index(label)
	if idx < 0:
		found["<missing label: %s>" % label] = true
		return
	_walk(label, found, visited)
