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
	## [M27F Stage 3] `waitmovement` — one or more entities are walking. Unlike
	## WAIT_BATTLE this carries no result, so a plain resume() is correct for it.
	WAIT_MOVEMENT,
	## [M27K K-c] The naming screen is open on a Pokémon nickname. Carries a
	## result (the typed name) like WAIT_YES_NO does, so `resume()` alone is NOT
	## enough — the caller must go through `answer_naming`.
	WAIT_NAMING,
}

## The one multichoice list Stage 4 implements.
const MULTI_YESNO := "MULTI_YESNO"

## [M27F Stage 4 follow-up] Scripts whose yes/no confirmation is SKIPPED —
## answered YES automatically, with no prompt shown.
##
## ⚠️ **A DELIBERATE DIVERGENCE FROM SOURCE, ROB'S CALL.** Source really does
## ask ("Would you like me to heal your Pokemon?"), and this really does not.
## The reasoning is that talking to the nurse has exactly one purpose, so the
## confirmation is a keypress between the player and the only thing they came
## for. Recorded here rather than left to look like a bug, because a later
## session reading `Std_MsgboxYesNo` WILL find the prompt in source and try to
## "restore" it.
##
## Deliberately keyed on the SCRIPT LABEL rather than a global "auto-confirm"
## setting: every other yes/no in the region — shops, tutors, trades — is a real
## choice with a real cost, and a blanket skip would silently answer all 425 of
## them. Both nurses are listed because the corridor reaches the Kanto one and
## the corpus still holds the Hoenn one.
## [M27F Stage 4 follow-up] Authored replacements for specific text entries.
##
## ⚠️ **CONTENT, NOT MECHANISM — and the FIRST place this project overrides
## reference dialogue.** `[M27]`'s own premise is that geometry and systems are
## imported while content and meaning are authored, so a table like this was
## always going to exist; this is it starting, with one entry.
##
## Keyed on the TEXT SYMBOL rather than the script, so the same line reads the
## same way wherever it is used. The value is the full page list — `\p` in
## source splits pages, and dropping a trailing page is the common case.
const TEXT_OVERRIDES := {
	# The nurse no longer asks (see AUTO_CONFIRM_LABELS), so the question page
	# would be rhetorical — printed and then answered by nobody. Source's own
	# second page is "Would you like me to heal your POKéMON back to perfect
	# health?"; the greeting stays.
	"Text_WelcomeWantToHealPkmn_Frlg": ["Welcome to our POKéMON CENTER!"],
	"gText_WouldYouLikeToRestYourPkmn": ["Hello, and welcome to the POKéMON CENTER."],
}

const AUTO_CONFIRM_LABELS := [
	"EventScript_PkmnCenterNurse_Frlg",       # Kanto — multichoice MULTI_YESNO
	"Common_EventScript_PkmnCenterNurse",     # Hoenn — yesnobox
]

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

## [M27F Stage 3] Movements the script has ASKED for but which the scene has not
## started yet. `applymovement` is asynchronous in source — it kicks a movement
## off and the script keeps running; `waitmovement` is the half that blocks. So
## this is a QUEUE the driver drains, not a pause.
var pending_movements: Array[Dictionary] = []

## Whose movement `waitmovement` is waiting on. "" means "everything".
var pending_wait_target: String = ""

## Which entity this script belongs to, so `faceplayer` and friends have a
## subject. May be null for a map-level script.
var subject: OverworldEntity = null

## [M27I I2] The three script string buffers. Runtime-only, like source's own
## gStringVar1-3 globals — deliberately NOT in FlagStore, which is save state.
var buffers := TextBuffers.new()

## [M27I I3] The player's bag. Injected like `_flags` so a test can hand in a
## fresh one; defaults to a private bag so a VM built without one still runs.
var bag := Bag.new()

## [M27O O1] The respawn point, injected like `bag` so a test can supply one.
var respawn := RespawnPoint.new()

## [M27I I3b] Money and coins, injected like `bag`.
var wallet := Wallet.new()

## [M27K K-a] The player's party, injected like `bag` — `givemon` puts a real
## Pokemon in it. Defaults to an empty party so a VM built without one still
## runs rather than crashing on the first give.
var party := BattleParty.new()

## [M27K K-a] Object events this script removed (`removeobject`), by the name
## the script used. The VM cannot reach the scene tree, so it RECORDS and the
## caller applies — the same split `[M27F Stage 2]` uses for battles.
var removed_objects: PackedStringArray = PackedStringArray()

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
	# ⚠️ .clear(), not `= []` — assigning an untyped array to a typed one
	# fails SILENTLY in GDScript, a gotcha this project has paid for before.
	pending_movements.clear()
	pending_wait_target = ""
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
			Pause.WAIT_BATTLE, Pause.WAIT_MOVEMENT, Pause.WAIT_NAMING]


func is_finished() -> bool:
	return pause_reason in [Pause.DONE, Pause.UNRESOLVED, Pause.UNKNOWN_OP]


## The caller reports that whatever we were waiting on has happened.
func resume() -> void:
	# ⚠️ WAIT_BATTLE and WAIT_NAMING are deliberately NOT resumable this way. Both
	# carry a RESULT: a battle's win/loss branch, and the typed nickname. Clearing
	# either here would silently drop it and read as "the script just carried on".
	# Use resume_after_battle() / answer_naming().
	if is_waiting() and pause_reason != Pause.WAIT_BATTLE \
			and pause_reason != Pause.WAIT_NAMING:
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
			var text_key := str(args[0]) if args.size() > 0 else ""
			if TEXT_OVERRIDES.has(text_key):
				pending_pages = PackedStringArray(TEXT_OVERRIDES[text_key])
				pending_page_index = 0
				pause_reason = Pause.WAIT_MESSAGE
				return true
			pending_pages = _source.pages_for(text_key)
			pending_page_index = 0
			if pending_pages.is_empty():
				# A message with no text is a data problem worth naming, not a
				# blank box the player has to press through.
				diagnostic = "no text for '%s'" % text_key
				pending_pages = PackedStringArray([""])
			pause_reason = Pause.WAIT_MESSAGE
			return true

		"waitbuttonpress":
			pause_reason = Pause.WAIT_BUTTON
			return true

		"yesnobox":
			if script_label in AUTO_CONFIRM_LABELS:
				_write_yes_no(true)
				return true
			pause_reason = Pause.WAIT_YES_NO
			return true

		"multichoice":
			# [M27F Stage 4] ⚠️ ONLY the yes/no list, and the polarity is the
			# OPPOSITE of `yesnobox`'s — see `answer_yes_no`. Every other list
			# halts: 204 corpus uses, overwhelmingly battle-facility menus that
			# belong to M35, and inventing a picker for them here would be
			# guessing at their contents.
			var list := str(args[2]) if args.size() > 2 else ""
			if list == MULTI_YESNO:
				if script_label in AUTO_CONFIRM_LABELS:
					_write_yes_no(true)
					return true
				pause_reason = Pause.WAIT_YES_NO
				return true
			pause_reason = Pause.UNKNOWN_OP
			diagnostic = "multichoice list '%s' is not implemented" % list
			return false

		# [M27F Stage 4] Presentation-only commands with no system behind them
		# here. `incrementgamestat` is a pure counter; `hidefollower` has no
		# followers to hide; `dofieldeffect`/`waitfieldeffect` are the heal
		# animation and its wait, which this project has no field-effect layer
		# for. Listed explicitly rather than falling through to UNKNOWN_OP, so a
		# real gap stays distinguishable from a known no-op.
		"incrementgamestat", "hidefollower", "dofieldeffect", "waitfieldeffect":
			return true

		# [M27K K-a] ⚠️ AUDIO DOES NOT EXIST ANYWHERE IN THIS PROJECT — not a
		# stub for this scene, a project-wide absence already recorded against
		# M36-S. A fanfare is a real beat in the starter scene (Oak hands you
		# the Pokemon to a jingle) and it is genuinely silent here; listed so
		# that stays a known no-op rather than an UNKNOWN_OP halt.
		"playfanfare", "waitfanfare", "playse", "playbgm", "fadedefaultbgm":
			return true

		# [M27K K-a] The mon picture Oak shows while offering the starter. This
		# project has no picture layer in the field at all — the front sprites
		# are pulled and battle-only. A no-op loses the flourish, not the scene.
		"showmonpic", "hidemonpic":
			return true

		# [M27K K-a] Remove an object event from the map — the Poke Ball you
		# just took. `VAR_LAST_TALKED` is the object you interacted with, which
		# is why this needs the interaction to have recorded it.
		"removeobject":
			if args.size() > 0:
				removed_objects.append(str(args[0]))
			return true

		# [M27K K-a] Put a real Pokemon in the party.
		#
		# ⚠️ BOTH ARGUMENTS GO THROUGH THE VARIABLE STORE. The starter script
		# passes `PLAYER_STARTER_SPECIES`, a VAR holding a species constant —
		# not a literal — so resolving only literals would give every starter
		# choice the same (absent) Pokemon.
		#
		# ⚠️ A FULL PARTY IS REFUSED, NOT SILENTLY DROPPED. Source's own macro
		# asks for `PARTY_SIZE` ("assign to first empty slot") and reports
		# failure in VAR_RESULT; with no PC built (I5-5, deferred past the
		# slice) there is nowhere else for it to go, so refusing and saying so
		# is the honest shape — the same call `[M27H H4]` already made for a
		# full-party catch.
		"givemon":
			if args.size() > 1:
				_give_mon(_resolve_number(str(args[0])),
						_resolve_number(str(args[1])))
			return true

		# [M27K K-c] ⚠️ **A NO-OP, AND THE REASON IS NOT "no fade system exists"
		# — there IS one** (`_fade_to`, used by warps and the battle round trip).
		# It is a no-op because **the fade this opcode starts is NEVER closed by
		# another opcode.** `Common_EventScript_NameReceivedPartyMon` is
		# `fadescreen FADE_TO_BLACK` / `special ChangePokemonNickname` / `return`,
		# and the fade back is done by the naming screen's own return callback
		# (`CB2_ReturnToFieldContinueScriptPlayMapMusic`), which is engine
		# plumbing this project does not have. So a faithful-looking fade here
		# would leave the screen black for good — the no-op is the SAFE reading,
		# not the lazy one.
		#
		# 128 corpus uses, 106 of them `FADE_TO_BLACK`. A future session that
		# implements this properly must pair it with the SCREEN TRANSITION, not
		# with a matching opcode, because in 106 places there is no matching
		# opcode to pair with. `fadescreenspeed` (8 uses) and
		# `fadescreenswapbuffers` (34) are deliberately NOT included — nothing in
		# this milestone reaches them, and the second genuinely swaps buffers
		# rather than just fading.
		"fadescreen":
			return true

		# [M27F Stage 4] A NARROW carve-out — see FieldSpecials for why an
		# unknown one halts rather than degrading to a default.
		"special", "callnative":
			var fn := str(args[0]) if args.size() > 0 else ""
			# [M27K K-c] ⚠️ CHECKED BEFORE `FieldSpecials.run`, because this one
			# cannot be answered synchronously — it opens a screen and waits.
			# `run()` returns a bool in the same frame, which is the right shape
			# for HealPlayerParty and wrong for every special that owns the
			# display. Handled here so the pause lives with the other pauses.
			if fn == FieldSpecials.NICKNAME_SPECIAL:
				return _begin_nickname()
			if FieldSpecials.run(fn):
				return true
			pause_reason = Pause.UNKNOWN_OP
			diagnostic = "special '%s' is not implemented" % fn
			return false

		"specialvar":
			# ⚠️ ARGUMENT ORDER: `specialvar VAR_RESULT, Fn` — the destination
			# var comes FIRST and the function second, the opposite of the way
			# it reads aloud. Getting it backwards resolves the var name as a
			# function and reports every call site as an unimplemented special.
			var dest := str(args[0]) if args.size() > 0 else "VAR_RESULT"
			var vfn := str(args[1]) if args.size() > 1 else ""
			if FieldSpecials.is_known_specialvar(vfn):
				if _flags != null:
					_flags.var_set(dest, FieldSpecials.specialvar_value(vfn))
				return true
			pause_reason = Pause.UNKNOWN_OP
			diagnostic = "specialvar '%s' is not implemented" % vfn
			return false

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

		# [M27K K-c2] ⚠️ **`addvar` AND `subvar` DO NOT RESOLVE THEIR OPERAND THE
		# SAME WAY, AND THE DIFFERENCE IS LIVE.** `ScrCmd_addvar` is
		# `*ptr += ScriptReadHalfword(ctx)` — a RAW immediate — while
		# `ScrCmd_subvar` is `*ptr -= VarGet(ScriptReadHalfword(ctx))`, which
		# resolves a var reference (`scrcmd.c:589, 601`). Implementing both the
		# same way would make `subvar VAR_X, VAR_Y` subtract Y's var-ID instead of
		# Y's value. The corpus really does both: `subvar` has 3 var operands
		# (`VAR_0x8009`, `VAR_ASH_GATHER_COUNT` twice) against 5 literals.
		#
		# ⚠️ DISCLOSED: a SYMBOLIC constant operand resolves to 0. Source's
		# assembler baked those to numbers; this project has no table for them, so
		# `BLACK_FLUTE_PRICE`, `ROULETTE_SPECIAL_RATE` and their 7 siblings read 0.
		# All 9 are shop/roulette scripts belonging to M27G/M35, none in the
		# corridor — a stated gap rather than a silent one.
		"addvar":
			if _flags != null and args.size() > 1:
				_flags.var_set(str(args[0]),
						_flags.var_get(str(args[0])) + _literal(str(args[1])))
			return true

		"subvar":
			if _flags != null and args.size() > 1:
				_flags.var_set(str(args[0]),
						_flags.var_get(str(args[0])) - _resolve_number(str(args[1])))
			return true

		# [M27K K-c2] ⚠️ **THIS IS HOW EVERY GIFT SCRIPT FINDS THE MON IT JUST
		# GAVE YOU.** `Common_EventScript_GetGiftMonPartySlot` is
		# `getpartysize` / `subvar VAR_RESULT, 1` / `copyvar VAR_0x8004, VAR_RESULT`
		# — the LAST slot, which is where `givemon` appended. Only the STARTER
		# script hardcodes slot 0, and it can because a new game's party is empty.
		"getpartysize":
			_set_result_value(party.members.size())
			return true

		# [M27K K-c2] The coins counter, mirroring `showmoneybox` above exactly:
		# display only, and no coins box exists. 32 corpus uses across the three.
		"showcoinsbox", "hidecoinsbox", "updatecoinsbox":
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

		"checkmoney", "addmoney", "removemoney":
			# ⚠️ MONEY ARGS ARE LITERAL, NOT VARIABLES. Source reads a raw
			# `ScriptReadWord` here rather than routing through `VarGet` the way
			# every item argument does, and the corpus agrees — all 54 uses
			# carry a plain number.
			#
			# Honest scope: `_resolve_number` is literal-first, so for the data
			# that actually exists the two readings agree and swapping them
			# breaks nothing today. This stays a literal read for fidelity, and
			# the test asserts the CORPUS FACT that keeps it safe rather than
			# pretending to a behavioural difference it cannot demonstrate.
			#
			# The macro's second `disable` byte defaults to 0 and is never
			# emitted by any corpus call, so a set one is not modelled.
			var raw := str(args[0]) if args.size() > 0 else "0"
			var amount := int(raw) if raw.is_valid_int() else -1
			if amount < 0:
				# ⚠️ FAIL CLOSED, AND THIS DIRECTION IS THE WHOLE POINT.
				# 6 corpus money args are file-scoped assembler constants
				# (`COINS_PRICE_500`) the script compiler does not resolve yet —
				# see the note on `_money_arg_unresolved`. Treating an
				# unresolvable price as 0 would make `checkmoney` report
				# AFFORDABLE and the following `removemoney` charge nothing:
				# free goods. Reporting "cannot afford" refuses the purchase
				# instead, which is the recoverable direction.
				diagnostic = "unresolved money amount '%s'" % raw
				if current_op == "checkmoney":
					_set_result(false)
				return true
			match current_op:
				"checkmoney": _set_result(wallet.can_afford(amount))
				"addmoney": wallet.earn(amount)
				# ⚠️ Clamps to zero rather than refusing — see Wallet.
				_: wallet.spend(amount)
			return true

		"checkcoins":
			# ⚠️ Writes into the NAMED VAR, not VAR_RESULT — the one command in
			# this family that reports somewhere else.
			if _flags != null and args.size() > 0:
				_flags.var_set(str(args[0]), wallet.coins)
			return true

		"addcoins", "removecoins":
			# Coins DO go through the variable store (`VarGet` in source), the
			# opposite of money one branch above.
			var n := _resolve_number(str(args[0])) if args.size() > 0 else 0
			var ok := wallet.add_coins(n) if current_op == "addcoins" \
					else wallet.remove_coins(n)
			# ⚠️ INVERTED. Source sets VAR_RESULT to FALSE on SUCCESS for both
			# of these -- `if (AddCoins(..) == TRUE) gSpecialVar_Result = FALSE`.
			# Reading it the natural way round makes every "did that work"
			# branch in the Game Corner take the wrong path.
			_set_result(not ok)
			return true

		"showmoneybox", "hidemoneybox", "updatemoneybox":
			# Display only, and there is no money box yet. Accepted rather than
			# halting: `hidemoneybox` alone is 42 corpus uses, so treating them
			# as unknown would stop scripts that are otherwise fully runnable.
			return true

		"setrespawn":
			# [M27O O1] Where a whiteout will send the player. Refuses an ID the
			# table does not know rather than storing it: an unresolvable
			# respawn surfaces at the worst possible moment, when the player is
			# already fainted and has nowhere to go.
			if args.size() > 0 and not respawn.set_to(str(args[0])):
				diagnostic = "unknown heal location '%s'" % str(args[0])
			return true

		"additem", "removeitem", "checkitem", "checkitemspace":
			# All four set VAR_RESULT and scripts branch on it immediately.
			# ⚠️ Both arguments run through the variable store: `additem
			# VAR_0x8009` and `checkitemspace VAR_TEMP_0` are real corpus forms.
			var it := _resolve_item(str(args[0])) if args.size() > 0 else 0
			var qty := _resolve_number(str(args[1])) if args.size() > 1 else 1
			var ok := false
			match current_op:
				"additem": ok = bag.add(it, qty)
				"removeitem": ok = bag.remove(it, qty)
				"checkitem": ok = bag.has_item(it, qty)
				_: ok = bag.has_space(it, qty)
			_set_result(ok)
			return true

		"checkitemtype":
			# VAR_RESULT is the POCKET here, not a boolean -- the obtain-item
			# flow switches on it to pick which pocket name to buffer.
			if _flags != null and args.size() > 0:
				_flags.var_set("VAR_RESULT", Bag.pocket_of(_resolve_item(str(args[0]))))
			return true

		"giveitem", "finditem", "giveitem_msg":
			return _obtain_item(args)

		"bufferitemname", "bufferitemnameplural":
			# ⚠️ Both the SLOT and the ITEM can arrive as variables. Every arg
			# in source goes through VarGet, and the corpus really does carry a
			# bare `0` slot and `VAR_0x8009` items — resolving only the named
			# spellings drops those silently.
			if args.size() > 1:
				var slot := TextBuffers.slot_index(str(args[0]))
				var item_id := _resolve_item(str(args[1]))
				var qty := 1
				if current_op == "bufferitemnameplural" and args.size() > 2:
					qty = _resolve_number(str(args[2]))
				buffers.set_slot(slot, _item_name(item_id, qty))
			return true

		"bufferstdstring":
			if args.size() > 1:
				buffers.set_slot(TextBuffers.slot_index(str(args[0])),
						buffers.std_string(str(args[1])))
			return true

		"buffernumberstring":
			if args.size() > 1:
				buffers.set_slot(TextBuffers.slot_index(str(args[0])),
						str(_resolve_number(str(args[1]))))
			return true

		"bufferspeciesname":
			if args.size() > 1:
				buffers.set_slot(TextBuffers.slot_index(str(args[0])),
						_species_name(str(args[1])))
			return true

		"applymovement":
			# ASYNCHRONOUS, like source. `ScrCmd_applymovement` starts the movement
			# and returns; the script carries on until a `waitmovement` blocks it.
			# Queueing rather than pausing is what makes two entities able to walk
			# at once, which most of the corridor's cutscenes do.
			if args.size() > 1:
				pending_movements.append({"target": str(args[0]), "script": str(args[1])})
			return true

		"waitmovement":
			# `waitmovement 0` is the common form and means "everything in flight",
			# not "object 0" -- LOCALID_NONE is 0, so there is no object to name.
			var who := str(args[0]) if args.size() > 0 else ""
			pending_wait_target = "" if who in ["0", "LOCALID_NONE", ""] else who
			pause_reason = Pause.WAIT_MOVEMENT
			return false

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
## Set VAR_RESULT to a boolean outcome. Source writes TRUE/FALSE as 1/0 and
## every `goto_if_eq VAR_RESULT, TRUE` compares against 1.
func _set_result(ok: bool) -> void:
	if _flags != null:
		_flags.var_set("VAR_RESULT", 1 if ok else 0)


## [M27K K-c2] VAR_RESULT as a COUNT rather than a flag. `getpartysize` writes a
## real number there, which the boolean `_set_result` cannot express — a party of
## 3 would land as 1 and every gift script would rename the second slot.
func _set_result_value(value: int) -> void:
	if _flags != null:
		_flags.var_set("VAR_RESULT", value)


## [M27I I3] `giveitem` / `finditem` / `giveitem_msg`.
##
## ⚠️ NONE OF THESE IS A PRIMITIVE IN SOURCE. `giveitem` is a macro over
## `setorcopyvar` x2 + `callstd STD_OBTAIN_ITEM`, and that standard script does
## the real work: additem -> buffer the pluralised name -> `checkitemtype` ->
## buffer the POCKET name -> branch on success -> "obtained" + "put away", or
## "the BAG is full". This project's compiler kept the macro unexpanded, so what
## is reproduced here is that script's DECISION STRUCTURE — the same approach
## [M27F Stage 2] took for `trainerbattle_single`, and for the same reason: the
## real script needs commands (`playfanfare`, `showitemdescription`) this
## project has no equivalent for, while its branching is exactly the behaviour.
##
## The TEXT is not invented — every page is source's own string, already in
## `map_texts.json` from Stage 1's extraction.
## [M27K K-a] Put a real Pokemon in the party, reporting success in VAR_RESULT.
##
## ⚠️ A KNOWN CONSTANT CAN STILL NAME A SPECIES THIS PROJECT DOES NOT HAVE —
## `species_id_of` covers all 1672 reference constants while the roster is 386.
## Both are refused, but they are different failures and the diagnostic says
## which, so a Gen 4+ script reads as out-of-roster rather than as a bad parse.
## [M27K K-c2] ⚠️ **VAR_RESULT HERE IS A THREE-WAY CODE, NOT A BOOLEAN, AND THIS
## USED TO WRITE THE BOOLEAN.** Source: `MON_GIVEN_TO_PARTY 0` /
## `MON_GIVEN_TO_PC 1` / `MON_CANT_GIVE 2` (`constants/pokemon.h:167-169`).
## `_set_result(true)` wrote **1**, which reads as "sent to the PC" — so
## `EventScript_GiveAerodactyl`, whose next two lines are
## `goto_if_eq VAR_RESULT, 0 -> NicknameMonParty` and
## `goto_if_eq VAR_RESULT, 1 -> NicknameMonPC`, took the PC branch on a
## successful gift to the PARTY. Success and failure were BOTH wrong: a full
## party wrote 0, which reads as "given to the party".
const MON_GIVEN_TO_PARTY := 0
const MON_GIVEN_TO_PC := 1
const MON_CANT_GIVE := 2


func _give_mon(dex: int, level: int) -> bool:
	if level <= 0:
		level = 5
	if dex <= 0 or PokemonRegistry.get_species(dex).is_empty():
		_set_result_value(MON_CANT_GIVE)
		diagnostic = "givemon: no species %d in this project's roster" % dex
		return true
	if party.members.size() >= BattleParty.PARTY_SIZE:
		# No PC exists (I5-5, deferred past the slice), so there is nowhere
		# else to put it — refuse and say so, as `[M27H H4]` does for a catch.
		#
		# ⚠️ `MON_CANT_GIVE`, deliberately NOT `MON_GIVEN_TO_PC`. Source would
		# box it and answer 1; with no PC the honest answer is "cannot", and the
		# scripts branch on it — `Common_EventScript_NoMoreRoomForPokemon` is
		# exactly where a 2 sends them.
		_set_result_value(MON_CANT_GIVE)
		diagnostic = "givemon: party is full and no PC exists"
		return true
	party.members.append(PokemonFactory.create_battle_pokemon(dex, level))
	if party.active_indices.is_empty():
		party.active_indices = [0]
	_set_result_value(MON_GIVEN_TO_PARTY)
	return true


## [M27K K-c] `special ChangePokemonNickname` — open the keyboard on a party
## member and pause until `answer_naming` reports what was typed.
##
## ⚠️ **THE SLOT IS `VAR_0x8004`, AND IT IS A SLOT INDEX, NOT A FLAG.**
## `GetSelectedBoxMonFromPcOrParty` (`pokemon.c:6846`) indexes
## `gParties[B_TRAINER_PLAYER][gSpecialVar_0x8004]` directly, with the single
## reserved value `PC_MON_CHOSEN` (0xFE, `party_menu.h:4`) diverting to the box
## instead. So `setvar VAR_0x8004, 0` in `EventScript_GiveNicknameToStarter`
## means "party slot 0" and nothing more.
##
## The PC path HALTS rather than falling back to the party. There is no PC (I5-5,
## deferred past the slice), and silently renaming a party member when the script
## asked for a boxed one is the kind of near-miss that reads as working.
const PC_MON_CHOSEN := 0xFE


func _begin_nickname() -> bool:
	var slot := 0
	if _flags != null:
		slot = _flags.var_get("VAR_0x8004")
	if slot == PC_MON_CHOSEN:
		pause_reason = Pause.UNKNOWN_OP
		diagnostic = "ChangePokemonNickname: the PC path needs a PC (I5-5)"
		return false
	if slot < 0 or slot >= party.members.size():
		pause_reason = Pause.UNKNOWN_OP
		diagnostic = ("ChangePokemonNickname: VAR_0x8004 is %d, and the party "
				+ "holds %d") % [slot, party.members.size()]
		return false
	naming_slot = slot
	pause_reason = Pause.WAIT_NAMING
	return true


## Which party slot the open naming screen is renaming. Meaningful only while
## `pause_reason == WAIT_NAMING`.
var naming_slot := -1


## The prompt the naming screen should show.
##
## ⚠️ Source builds this in `DrawMonTextEntryBox` (`naming_screen.c:1778`) by
## prepending `GetSpeciesName(monSpecies)` to `sMonNamingScreenTemplate.title`,
## which is `"{STR_VAR_1}'s nickname?"` — so the template carries a placeholder
## AND the draw function substitutes the species itself. I could not resolve from
## reading alone whether the expansion double-renders there; what is unambiguous
## is that the species name appears once, followed by "'s nickname?", so that is
## what this builds. Recorded rather than presented as a clean port.
##
## Reads the SPECIES, not `display_name()` — you are being asked about the thing
## you caught, and after a rename the old nickname is not what identifies it.
func naming_prompt() -> String:
	if naming_slot < 0 or naming_slot >= party.members.size():
		return "Nickname?"
	var mon: BattlePokemon = party.members[naming_slot]
	if mon == null or mon.species == null:
		return "Nickname?"
	return "%s's nickname?" % mon.species.species_name


## The caller reports what the naming screen produced, and the VM resumes.
##
## ⚠️ **AN EMPTY STRING MEANS "KEEP WHAT IT HAD" — IT IS NOT A FAILURE.**
## `SaveInputText` (`naming_screen.c:1921`) writes the typed buffer into the
## destination only if some character is neither space nor EOS, and the
## destination was pre-seeded with the current nickname
## (`ChangePokemonNicknameWithCallback`, `pokemon.c:6892`). So OK-with-nothing-
## typed leaves the mon named after its species, and that is source's own way of
## backing out once the keyboard is already open. Refusing here instead would
## strand the script with no way forward.
func answer_naming(value: String) -> void:
	if pause_reason != Pause.WAIT_NAMING:
		return
	var trimmed := value.strip_edges()
	if trimmed != "" and naming_slot >= 0 and naming_slot < party.members.size():
		var mon: BattlePokemon = party.members[naming_slot]
		if mon != null:
			mon.nickname = PlayerIdentity.sanitize(trimmed)
	naming_slot = -1
	pause_reason = Pause.NONE


func _obtain_item(args: Array) -> bool:
	# giveitem_msg's first argument is its own message label; the other two
	# forms lead with the item.
	var msg_label := ""
	var idx := 0
	if current_op == "giveitem_msg" and args.size() > 0:
		msg_label = str(args[0])
		idx = 1
	var item_id := _resolve_item(str(args[idx])) if args.size() > idx else 0
	var qty := _resolve_number(str(args[idx + 1])) if args.size() > idx + 1 else 1
	if qty <= 0:
		qty = 1

	var ok := bag.add(item_id, qty)
	_set_result(ok)

	# STR_VAR_2 is the item, STR_VAR_1 the count, STR_VAR_3 the pocket — the
	# slots source's own strings read.
	buffers.set_slot(1, _item_name(item_id, qty))
	buffers.set_slot(0, str(qty))
	buffers.set_slot(2, buffers.std_string(_POCKET_STDSTRING.get(
			Bag.pocket_of(item_id), "STDSTRING_ITEMS")))

	var pages := PackedStringArray()
	if msg_label != "":
		# giveitem_msg supplies its own line and skips the standard pair.
		pages.append_array(_source.pages_for(msg_label))
	elif not ok:
		pages.append_array(_source.pages_for("gText_TooBadBagIsFull"
				if current_op == "finditem" else "gText_TheBagIsFull"))
	elif current_op == "finditem":
		pages.append_array(_source.pages_for(
				"gText_PlayerFoundOneItem" if qty == 1 else "gText_PlayerFoundItems"))
		pages.append_array(_source.pages_for("gText_PlayerPutItemInBag"))
	else:
		pages.append_array(_source.pages_for(
				"gText_ObtainedTheItem" if qty == 1 else "gText_ObtainedTheItems"))
		pages.append_array(_source.pages_for("gText_PutItemInPocket"))

	if pages.is_empty():
		# No text is a data problem worth naming, not a silent success.
		diagnostic = "no obtain-item text for item %d" % item_id
		return true
	pending_pages = pages
	pending_page_index = 0
	pause_reason = Pause.WAIT_MESSAGE
	return true


## Pocket ordinal -> the std string naming it, from
## `EventScript_BufferPocketNameAndTryFanfare`'s own switch.
const _POCKET_STDSTRING := {
	ItemManager.POCKET_ITEMS: "STDSTRING_ITEMS",
	ItemManager.POCKET_KEY_ITEMS: "STDSTRING_KEYITEMS",
	ItemManager.POCKET_POKE_BALLS: "STDSTRING_POKEBALLS",
	ItemManager.POCKET_TM_HM: "STDSTRING_TMHMS",
	ItemManager.POCKET_BERRIES: "STDSTRING_BERRIES",
}


## [M27I I2] An argument that may be an ITEM_* constant OR a variable holding
## an item id. Source runs every one through `VarGet`; 64 corpus args really
## are variables, concentrated in the give-and-branch chains.
func _resolve_item(arg: String) -> int:
	if arg.begins_with("ITEM_"):
		return PokemonRegistry.item_id_of(arg)
	return _resolve_number(arg)


## A numeric argument, whether written as a literal or held in a variable.
## An argument as a number: an integer, a VAR reference, or a symbolic constant.
##
## ⚠️ **[M27K K-c2] THE CONSTANT FALLBACK WAS MISSING, AND IT SILENTLY BROKE 19
## OF THE 23 `givemon` CALL SITES.** This used to be integer-or-var only, so
## `givemon SPECIES_AERODACTYL, 5` resolved the species through `var_get`, found
## no such var, and handed `_give_mon` a 0 — which refuses and gives nothing. The
## corpus splits 19 direct `SPECIES_*` constants against 4 var references, and
## the starter script is one of the 4, which is exactly why `[M27K K-a]` shipped
## without noticing: the one script it drove took the working path.
##
## Order matters and mirrors source. `VarGet` treats its argument as a var when
## it is at or above `VARS_START` and as an immediate otherwise, so a var
## reference wins over a constant of the same name — hence `has_var` first. An
## unset var still reads 0, the same answer as before, so nothing regresses.
func _resolve_number(arg: String) -> int:
	if arg.is_valid_int():
		return int(arg)
	if _flags != null and _flags.has_var(arg):
		return _flags.var_get(arg)
	return _literal(arg)


## An item's display name, pluralised the way source does.
##
## ⚠️ The plural rule is not "add S to everything": `CopyItemNameHandlePlural`
## uses a real per-item plural name when the item has one and only falls back to
## a suffix otherwise. This project has no plural-name column, so the suffix is
## the whole rule here — a disclosed simplification, visible only on the eight
## corpus `bufferitemnameplural` uses, none of which are in the corridor.
func _item_name(item_id: int, quantity: int) -> String:
	var info := PokemonRegistry.get_item_identity(item_id)
	if info.is_empty():
		return ""
	var n := str(info.get("name", ""))
	return n if quantity == 1 or n == "" else n + "s"


## A species name from a SPECIES_* constant or a variable holding a dex number.
func _species_name(arg: String) -> String:
	# [M27K K-a] The SPECIES_* map now exists, so `_resolve_number` resolves a
	# constant through `_literal` and a variable through the store, uniformly.
	# [This helper used to return "" for any constant, disclosed as closed when
	# M27 needed it. It does now — the starter script buffers its own name.]
	var dex := _resolve_number(arg)
	var sp := PokemonRegistry.get_species(dex)
	return str(sp.get("name", "")) if not sp.is_empty() else ""


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
		# [M27F Stage 4] ⚠️ 753 corpus args are one of these three, and every
		# one of them resolved to 0 before this. `goto_if_eq VAR_RESULT, YES`
		# compared against 0, so answering NO took the YES branch — inverted at
		# every yes/no call site in the region, silently.
		"YES": return 1          # asm/macros/event.inc:2133
		"NO": return 0
		"MULTI_B_PRESSED": return 127  # include/constants/script_menu.h:8
	# ⚠️ [M27K K-a] A SPECIES CONSTANT IS A REAL VALUE, AND 295 CORPUS ARGS ARE
	# ONE. Before this they all resolved to 0 through the fallthrough below —
	# `setvar PLAYER_STARTER_SPECIES, SPECIES_BULBASAUR` stored nothing, so the
	# starter script could not have named its own Pokemon. Exactly the shape of
	# the YES/NO inversion above: silent, and wrong at every call site at once.
	# Resolved HERE rather than in `givemon` so setvar/compare/copyvar/switch
	# all agree, which is what source does — every arg goes through VarGet and
	# a species constant is just a number by the time it gets there.
	if tok.begins_with("SPECIES_"):
		var dex := PokemonRegistry.species_id_of(tok)
		return dex if dex > 0 else 0
	return 0


## [M27F Stage 4] Answer a yes/no prompt and resume.
##
## ⚠️ **THE TWO OPCODES HAVE OPPOSITE POLARITY, AND THIS IS WHY THE CALLER MUST
## NOT WRITE VAR_RESULT ITSELF.** `yesnobox` writes **1 for YES**
## (`Task_HandleYesNoInput` sets `gSpecialVar_Result = 1` for row 0), while
## `multichoice MULTI_YESNO` writes the **LIST INDEX**, and
## `MultichoiceList_YesNo` is `{Yes, NO}` — so **0 is YES** there.
##
## Kanto's own Pokecentre nurse uses the multichoice form
## (`EventScript_PkmnCenterNurse_Frlg`), Hoenn's uses `yesnobox`, and the two
## sit behind one identical-looking prompt. A caller that picked one convention
## would heal on NO in half the region. Keeping the decision here means the
## opcode that paused is what decides.
func answer_yes_no(yes: bool) -> void:
	if pause_reason != Pause.WAIT_YES_NO:
		return
	_write_yes_no(yes)
	resume()


## The polarity, in ONE place. `yesnobox` writes 1 for YES; `multichoice
## MULTI_YESNO` writes the list index, where 0 is YES. Shared by the real
## prompt and by the auto-confirm path so the two can never drift.
func _write_yes_no(yes: bool) -> void:
	if _flags == null:
		return
	if current_op == "multichoice":
		_flags.var_set("VAR_RESULT", 0 if yes else 1)
	else:
		_flags.var_set("VAR_RESULT", 1 if yes else 0)


## B / Escape. `yesnobox` folds this onto NO; `multichoice` has a distinct
## MULTI_B_PRESSED (127) that scripts really do branch on separately.
func cancel_yes_no() -> void:
	if pause_reason != Pause.WAIT_YES_NO:
		return
	if current_op == "multichoice":
		if _flags != null:
			_flags.var_set("VAR_RESULT", 127)
		resume()
	else:
		answer_yes_no(false)


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
