class_name ScriptVM
extends RefCounted

## [M27F Stage 1] The field script interpreter.
##
## Runs the scripts the importer already records on every placed entity
## (`OverworldEntity.script_label`) — 218 scripted entities across the corridor,
## 192 distinct labels, 90 distinct commands of source's 237.
##
## ⚠️ STATE IS EXTERNAL, DELIBERATELY. `pc`, `current_op` and `pause_reason` are
## plain readable properties, never information that exists only inside a
## suspended call frame. Three things depend on that and would each be
## impossible otherwise:
##
##   * the resolve-or-degrade path has to report WHERE it degraded, not just that
##     it did — a missing label or an out-of-stage opcode has to name itself;
##   * the F-key debug overlay convention this project uses everywhere;
##   * tests that freeze the VM mid-script and assert from outside, the way
##     TextTyper's own test reads `is_typing`/`visible_characters` rather than
##     reaching into a coroutine.
##
## So `step()` advances exactly one opcode and RETURNS — it never awaits. The
## caller drives it and owns the waiting. A coroutine would have been shorter and
## would have buried every one of the three above.
##
## Opcode coverage is Stage 1's set (~55% of all corridor command uses). An
## unknown opcode is a first-class outcome (`PAUSE_UNKNOWN_OP`), not a crash and
## not a silent skip — the tail is 53 more commands and they arrive by stages.


## Why the VM is not currently advancing.
enum Pause {
	NONE,            ## running; step() will do work
	WAIT_MESSAGE,    ## a page is typing; caller clears when the typer finishes
	WAIT_BUTTON,     ## page shown, waiting for the player to press on
	WAIT_YES_NO,     ## a yes/no box is open; caller writes VAR_RESULT
	DONE,            ## `end` or `return` at depth 0
	UNRESOLVED,      ## the script label does not exist (reported, not thrown)
	UNKNOWN_OP,      ## an opcode outside Stage 1's set
}

## Where execution is. Index into `_ops`.
var pc: int = 0

## The opcode about to run (or the one that caused the current pause).
var current_op: String = ""

## Why we are stopped. Never NONE while the caller should be waiting.
var pause_reason: Pause = Pause.DONE

## The label currently executing — for the overlay and for degrade reports.
var script_label: String = ""

## Set alongside UNRESOLVED / UNKNOWN_OP. Human-readable, names the thing.
var diagnostic: String = ""

## Text the caller should be showing, as pages. Set when a message starts.
var pending_pages: PackedStringArray = PackedStringArray()
var pending_page_index: int = 0

## Which entity this script belongs to, so `faceplayer` and friends have a
## subject. May be null for a map-level script.
var subject: OverworldEntity = null

## Result of the last `compare`: 0 equal, 1 greater, -1 less. Source keeps the
## same single-slot comparison result. OBSERVABLE because it decides whether
## `goto_if_eq` branches — without it in describe(), a test that froze the VM
## mid-script could see WHICH way a branch went but never WHY.
var last_compare: int = 0

var _ops: Array[Dictionary] = []

## ⚠️ Frames are {label, pc}, NOT bare PCs. `_jump` swaps the whole op array, so
## a stack of plain integers restores the right NUMBER into the WRONG SCRIPT —
## `call` then `return` landed past the end of the callee and reported DONE,
## skipping the caller's own `release`/`end` and leaving the player locked with
## the box open. Found by tracing call/return while writing this up, not by a
## test; `call` is 36 uses in the corridor, so it was reachable, not theoretical.
var _call_stack: Array[Dictionary] = []
var _flags: FlagStore = null
var _source: ScriptSource = null


## Where compiled scripts and text come from. Injected so a test can supply
## either without touching disk.
class ScriptSource:
	extends RefCounted

	var ops_by_label: Dictionary = {}     ## label -> Array[Dictionary]
	var texts: Dictionary = {}            ## label -> Array[String] (pages)

	func has_script(label: String) -> bool:
		return ops_by_label.has(label)

	func ops_for(label: String) -> Array:
		return ops_by_label.get(label, [])

	func pages_for(label: String) -> PackedStringArray:
		var out := PackedStringArray()
		for p in texts.get(label, []):
			out.append(str(p))
		return out


func _init(source: ScriptSource, flags: FlagStore) -> void:
	_source = source
	_flags = flags


## Begin a script. Returns false (and sets UNRESOLVED + diagnostic) if the label
## does not exist.
##
## MEASURED: all 192 corridor labels compile, so this path is defensive rather
## than expected. An earlier Step 0 claimed three were permanently unresolvable
## (the excluded link-cable rooms) — that was an artifact of an indexer globbing
## only `.inc`; the compiler reads `.s` as well and finds every one.
func start(label: String, p_subject: OverworldEntity = null) -> bool:
	script_label = label
	subject = p_subject
	pc = 0
	current_op = ""
	diagnostic = ""
	_call_stack.clear()
	last_compare = 0
	pending_pages = PackedStringArray()
	pending_page_index = 0
	if _source == null or not _source.has_script(label):
		pause_reason = Pause.UNRESOLVED
		diagnostic = "no script named '%s'" % label
		return false
	_ops.assign(_source.ops_for(label))
	pause_reason = Pause.NONE
	return true


func is_running() -> bool:
	return pause_reason == Pause.NONE


func is_waiting() -> bool:
	return pause_reason in [Pause.WAIT_MESSAGE, Pause.WAIT_BUTTON, Pause.WAIT_YES_NO]


func is_finished() -> bool:
	return pause_reason in [Pause.DONE, Pause.UNRESOLVED, Pause.UNKNOWN_OP]


## The caller reports that whatever we were waiting on has happened.
func resume() -> void:
	if is_waiting():
		pause_reason = Pause.NONE


## Advance one opcode. Returns true if it did work, false if paused or finished.
##
## One opcode per call, never a loop and never an await: that is what keeps `pc`
## and `pause_reason` meaningful to an outside observer at every instant.
func step() -> bool:
	if pause_reason != Pause.NONE:
		return false
	if pc < 0 or pc >= _ops.size():
		# Running off the end is an implicit end, matching source's own scripts
		# which are not all explicitly terminated.
		pause_reason = Pause.DONE
		return false

	var op: Dictionary = _ops[pc]
	current_op = str(op.get("op", ""))
	var args: Array = op.get("args", [])
	pc += 1

	match current_op:
		"lock", "lockall", "release", "releaseall", "closemessage", \
		"waitmessage", "textcolor", "delay", "faceplayer":
			# Stage 1 no-ops at the VM level: the CALLER owns locking input,
			# facing the player and clearing the box, because those are scene
			# concerns. Listed explicitly rather than falling through to
			# UNKNOWN_OP so a real gap stays distinguishable from a known no-op.
			return true

		"message":
			pending_pages = _source.pages_for(str(args[0]) if args.size() > 0 else "")
			pending_page_index = 0
			if pending_pages.is_empty():
				# A message with no text is a data problem worth naming, not a
				# blank box the player has to press through.
				diagnostic = "no text for '%s'" % (str(args[0]) if args.size() > 0 else "")
				pending_pages = PackedStringArray([""])
			pause_reason = Pause.WAIT_MESSAGE
			return true

		"waitbuttonpress":
			pause_reason = Pause.WAIT_BUTTON
			return true

		"yesnobox":
			pause_reason = Pause.WAIT_YES_NO
			return true

		"call":
			_call_stack.push_back({"label": script_label, "pc": pc})
			return _jump(str(args[0]) if args.size() > 0 else "")

		"goto":
			return _jump(str(args[0]) if args.size() > 0 else "")

		"goto_if_eq":
			# Stage 1 carries exactly the comparison yes/no needs. The general
			# flag/var flow is Stage 3.
			if last_compare == 0:
				return _jump(str(args[0]) if args.size() > 0 else "")
			return true

		"compare":
			var name := str(args[0]) if args.size() > 0 else ""
			var against := int(args[1]) if args.size() > 1 else 0
			var have := _flags.var_get(name) if _flags != null else 0
			last_compare = 0 if have == against else (1 if have > against else -1)
			return true

		"return":
			if _call_stack.is_empty():
				pause_reason = Pause.DONE
				return false
			var frame: Dictionary = _call_stack.pop_back()
			# Restore the op ARRAY as well as the counter.
			_ops.assign(_source.ops_for(str(frame["label"])))
			script_label = str(frame["label"])
			pc = int(frame["pc"])
			return true

		"end":
			pause_reason = Pause.DONE
			return false

	pause_reason = Pause.UNKNOWN_OP
	diagnostic = "opcode '%s' is outside Stage 1's set" % current_op
	return false


func _jump(label: String) -> bool:
	if _source == null or not _source.has_script(label):
		pause_reason = Pause.UNRESOLVED
		diagnostic = "jump target '%s' does not exist" % label
		return false
	_ops.assign(_source.ops_for(label))
	script_label = label
	pc = 0
	return true


## Everything an observer needs, in one call — the overlay's own read.
func describe() -> Dictionary:
	return {
		"label": script_label,
		"pc": pc,
		"op": current_op,
		"pause": Pause.keys()[pause_reason],
		"diagnostic": diagnostic,
		"page": pending_page_index,
		"pages": pending_pages.size(),
		"depth": _call_stack.size(),
		"last_compare": last_compare,
	}
