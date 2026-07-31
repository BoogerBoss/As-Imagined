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
	## [M27F Stage 2] A trainer battle is running and owns the screen. The ONLY
	## pause that outlives the frame it started in -- appended rather than
	## slotted beside the other WAIT_ values so no existing ordinal shifts.
	WAIT_BATTLE,
}

## Scratch var `switch`/`case` compare through, per event.inc:2115.
const SWITCH_VAR := "VAR_0x8000"

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

## [M27F Stage 2] Set when `trainerbattle_single` pauses on WAIT_BATTLE, so the
## scene can start the battle without the VM knowing what a battle is.
##
## `pending_battle_defeat_text` is the trainer's own speech on LOSING, shown at
## battle end. [M26B3-4] disclosed that gap and declined to pull the text on the
## grounds it was "bound to an overworld this project doesn't have" -- which is
## no longer true, so it is carried here for whoever closes it.
var pending_trainer_key: String = ""
var pending_battle_intro: String = ""
var pending_battle_defeat_text: String = ""
var pending_battle_script: String = ""

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
	pending_trainer_key = ""
	pending_battle_intro = ""
	pending_battle_defeat_text = ""
	pending_battle_script = ""
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
	return pause_reason in [Pause.WAIT_MESSAGE, Pause.WAIT_BUTTON, Pause.WAIT_YES_NO,
			Pause.WAIT_BATTLE]


func is_finished() -> bool:
	return pause_reason in [Pause.DONE, Pause.UNRESOLVED, Pause.UNKNOWN_OP]


## The caller reports that whatever we were waiting on has happened.
func resume() -> void:
	# ⚠️ WAIT_BATTLE is deliberately NOT resumable this way. A battle carries a
	# RESULT the script has to branch on, so clearing it here would silently
	# skip the win/loss branch and read as "the post-battle script just did not
	# run". Use resume_after_battle().
	if is_waiting() and pause_reason != Pause.WAIT_BATTLE:
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
		"waitmessage", "textcolor", "delay", "faceplayer", "famechecker":
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

		"compare":
			# Restored after being wrongly deleted. The compiled corpus emits 33
			# of these and exactly 33 one-argument conditional jumps -- they are
			# the pair. The three-argument form below carries its own comparison;
			# the one-argument form leans on this.
			var cmp_name := str(args[0]) if args.size() > 0 else ""
			var cmp_against := _literal(str(args[1])) if args.size() > 1 else 0
			var cmp_have := _flags.var_get(cmp_name) if _flags != null else 0
			last_compare = 0 if cmp_have == cmp_against else (1 if cmp_have > cmp_against else -1)
			return true

		"goto_if_eq", "goto_if_ne", "goto_if_lt", "goto_if_le", "goto_if_gt", "goto_if_ge", \
		"goto_if_set", "goto_if_unset", "goto_if_defeated", "goto_if_not_defeated", \
		"call_if_eq", "call_if_ne", "call_if_lt", "call_if_le", "call_if_gt", "call_if_ge", \
		"call_if_set", "call_if_unset", "call_if_defeated", "call_if_not_defeated":
			return _conditional(current_op, args)

		"setflag", "clearflag":
			# Pulled forward from Stage 3 deliberately: without them Brock is
			# beatable and NOTHING persists, which reads as a broken alpha.
			if _flags != null and args.size() > 0:
				if current_op == "setflag":
					_flags.flag_set(str(args[0]))
				else:
					_flags.flag_clear(str(args[0]))
			return true

		"setvar":
			if _flags != null and args.size() > 1:
				_flags.var_set(str(args[0]), _literal(str(args[1])))
			return true

		"switch":
			# `switch var` -> `copyvar VAR_0x8000, var` (event.inc:2115). Pure
			# control flow over primitives already here; 503 uses.
			if _flags != null and args.size() > 0:
				_flags.var_set(SWITCH_VAR, _flags.var_get(str(args[0])))
			return true

		"case":
			# `case value, dest` -> `compare VAR_0x8000, value` + `goto_if_eq dest`
			# (event.inc:2119). ⚠️ That is the ONE-ARGUMENT conditional form -- which
			# is exactly why deleting `compare` as "never emitted" was wrong. 2026
			# uses, the largest control-flow family after the conditionals.
			if args.size() < 2:
				return true
			last_compare = _cmp(_flags.var_get(SWITCH_VAR) if _flags != null else 0,
				_literal(str(args[0])))
			if last_compare == 0:
				return _jump(str(args[1]))
			return true

		"copyvar":
			if _flags != null and args.size() > 1:
				_flags.var_set(str(args[0]), _flags.var_get(str(args[1])))
			return true

		"settrainerflag":
			# The same DEFEATED_ key `goto_if_defeated` reads and a won battle
			# writes -- one representation of "beaten", three writers.
			if _flags != null and args.size() > 0:
				_flags.set_trainer_defeated(str(args[0]))
			return true

		"set_gym_trainers_frlg":
			# A compound macro the compiler left unexpanded (event.inc:2940):
			# `setvar VAR_0x8008, gym` + `call Common_EventScript_SetGymTrainers_Frlg`.
			if _flags != null and args.size() > 0:
				_flags.var_set("VAR_0x8008", _literal(str(args[0])))
			_call_stack.push_back({"label": script_label, "pc": pc})
			return _jump("Common_EventScript_SetGymTrainers_Frlg")

		"trainerbattle_single":
			return _trainer_battle(args)

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


## [M27F Stage 2] `trainerbattle_single trainer, intro, defeat[, script[, music]]`
##
## ⚠️ THE ARITY SELECTS THE BATTLE TYPE (`event.inc:787`). Three arguments is
## `TRAINER_BATTLE_SINGLE`; four or five is `TRAINER_BATTLE_CONTINUE_SCRIPT`,
## which names a post-battle script. 753 of the corpus use the short form and
## 114 the long one, so implementing either alone is wrong for most of Kanto.
##
## Source does NOT do this in the command -- `ScrCmd_trainerbattle` jumps to the
## shared `EventScript_TryDoNormalTrainerBattle`, and the real logic lives there
## as script data. That script is unrunnable here (it needs `applymovement`,
## `special` and `specialvar`, all later stages), so its DECISION STRUCTURE is
## reproduced natively instead. Its other content is presentation this project
## either already does elsewhere (D4 walks the trainer over) or has no equivalent
## for (encounter music). Recorded as a deliberate divergence, not an oversight.
##
## Three outcomes, and they resolve to two DIFFERENT continuation points:
##
##   already beaten -> `gotopostbattlescript` -> `BattleSetup_GetScriptAddrAfterBattle`
##                     = the address AFTER this command, i.e. fall through.
##   won            -> `gotobeatenscript` -> `BattleSetup_GetTrainerPostBattleScript`
##                     = the event_script ARGUMENT, a different target entirely.
##   lost           -> source whites the player out; nothing further runs.
func _trainer_battle(args: Array) -> bool:
	if args.size() < 3:
		pause_reason = Pause.UNKNOWN_OP
		diagnostic = "trainerbattle_single needs 3+ args, got %d" % args.size()
		return false

	pending_trainer_key = str(args[0])
	pending_battle_intro = str(args[1])
	pending_battle_defeat_text = str(args[2])
	pending_battle_script = _script_arg(args, 3)

	# The already-beaten skip. Source checks `GetTrainerFlag` inside the shared
	# script, one level below the command -- which is why Brock's own script has
	# no guard of its own and would otherwise re-challenge forever.
	if _flags != null and _flags.trainer_defeated(pending_trainer_key):
		return true

	# The intro speech. Source shows it before the battle
	# (`EventScript_ShowTrainerIntroMsg`); the box belongs to the driver, so the
	# pages are handed over the same way `message` hands them over.
	pending_pages = _source.pages_for(pending_battle_intro) if _source != null \
			else PackedStringArray()
	pending_page_index = 0
	pause_reason = Pause.WAIT_BATTLE
	return false


## An optional script-pointer argument. Source passes FALSE/NULL for "none", and
## the importer emits `0x0` for an absent pointer, so all three mean absent.
static func _script_arg(args: Array, i: int) -> String:
	if args.size() <= i:
		return ""
	var v := str(args[i])
	if v in ["FALSE", "NULL", "0", "0x0", ""]:
		return ""
	return v


## The scene reports how the battle ended. Separate from resume() because a
## battle is the one pause whose RESULT changes where the script goes next.
func resume_after_battle(won: bool) -> void:
	if pause_reason != Pause.WAIT_BATTLE:
		return
	if not won:
		# Whiteout is M27I/M27K's; here the script simply stops, which leaves
		# the trainer undefeated and the encounter repeatable.
		pause_reason = Pause.DONE
		return
	pause_reason = Pause.NONE
	if pending_battle_script != "":
		_jump(pending_battle_script)
		return
	# No post-battle script. Source reaches `EventScript_EndTrainerBattle`, whose
	# `gotobeatenscript` resolves to a fallback rather than falling through, so
	# the calling script does NOT continue. DISCLOSED: this ends the script. If
	# a plain trainer should instead speak their post-battle line immediately
	# after the battle rather than only on the next talk, this is the one line.
	pause_reason = Pause.DONE


## The whole conditional-jump family, in one place.
##
## ⚠️ THE LABEL IS THE LAST ARGUMENT, NEVER THE FIRST. The first cut read
## `args[0]` and sent every gated script jumping to a VAR name. Three shapes,
## all confirmed against `asm/macros/event.inc`:
##
##   * comparison  -- `goto_if_eq a, b, c` -> `trycompare goto_if, 1, a, b, c`
##     (:2023). Compares a to b itself. A ONE-ARGUMENT form also exists and
##     leans on a preceding `compare` instead; the corpus has exactly 33 of
##     each, which is how the pairing was confirmed rather than assumed.
##   * flag       -- `goto_if_set flag, dest` -> `checkflag` + `goto_if TRUE`
##     (:1994). Two arguments.
##   * defeated   -- `goto_if_defeated trainer, dest` -> `checktrainerflag` +
##     `goto_if TRUE` (:2095). Two arguments. Reads the same DEFEATED_ key
##     `FlagStore.set_trainer_defeated` writes, so a beaten trainer's script
##     takes its post-battle branch with nothing extra to wire.
##
## `call_if_*` is the same test with a pushed frame instead of a tail jump.
func _conditional(op_name: String, args: Array) -> bool:
	var is_call := op_name.begins_with("call_if_")
	var kind := op_name.substr(8)
	var taken := false
	var label := ""

	match kind:
		"set", "unset":
			if args.size() < 2:
				return true
			var on := _flags.flag_get(str(args[0])) if _flags != null else false
			taken = on if kind == "set" else not on
			label = str(args[1])
		"defeated", "not_defeated":
			if args.size() < 2:
				return true
			var beaten := _flags.trainer_defeated(str(args[0])) if _flags != null else false
			taken = beaten if kind == "defeated" else not beaten
			label = str(args[1])
		_:
			if args.size() >= 3:
				var have := _flags.var_get(str(args[0])) if _flags != null else 0
				last_compare = _cmp(have, _literal(str(args[1])))
				label = str(args[2])
			elif args.size() == 1:
				label = str(args[0])
			else:
				return true
			taken = _compare_holds(kind, last_compare)

	if not taken:
		return true
	if is_call:
		_call_stack.push_back({"label": script_label, "pc": pc})
	return _jump(label)


static func _cmp(have: int, against: int) -> int:
	return 0 if have == against else (1 if have > against else -1)


## Condition codes are source's own (`goto_if_lt` = 0, `eq` = 1, `ge` = 4,
## `ne` = 5), but the names are what the compiler emits, so match on those.
static func _compare_holds(kind: String, cmp: int) -> bool:
	match kind:
		"eq": return cmp == 0
		"ne": return cmp != 0
		"lt": return cmp < 0
		"le": return cmp <= 0
		"gt": return cmp > 0
		"ge": return cmp >= 0
	return false


## Operands are symbolic as often as numeric (`1`, `TRUE`, `SIGN_LADY_READY`).
## An unknown symbol resolves to 0 rather than erroring: a script comparing
## against a constant this project has not imported should take the false
## branch, not stop dead.
static func _literal(tok: String) -> int:
	if tok.is_valid_int():
		return tok.to_int()
	match tok:
		"TRUE": return 1
		"FALSE": return 0
	return 0


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
