class_name ScriptVM
extends RefCounted

## [M27F Stage 1] The field script interpreter.
##
## Runs the scripts the importer already records on every placed entity
## (`OverworldEntity.script_label`) — 218 scripted entities across the corridor,
## 192 distinct labels, 121 distinct commands of source's 237.
##
## [Trainer-battle family + small-opcode batch] Grew from 90 by closing the
## trainer-battle family (`trainerbattle_no_intro`/`_double`/`_rematch`/
## `_rematch_double`, 496 combined corpus uses — `trainerbattle_single` was
## the only variant Stage 2 shipped), plus `checkplayergender`/`random`/
## `setorcopyvar`, the `waitse`/`playmoncry`/`waitmoncry` audio no-ops,
## `bufferboxname` (a real halt, not a no-op — see its own doc comment),
## `fadescreenspeed`/`fadescreenswapbuffers` (the two `fadescreen` siblings
## named but excluded when that opcode shipped), and a symbolic-constant
## table closing `addvar`/`subvar`/`checkmoney`/`addmoney`/`removemoney`'s
## own disclosed Hoenn-only-constant gap. Coverage was NOT re-measured after
## this — the last recorded corpus-completion figure predates it and was
## already stale (see `docs/m27_next_step_recon.md`); no rerunnable
## coverage tool exists to produce a fresh one.
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
	## [Map scripts] `warp` — a script-driven warp (`ScrCmd_warp`,
	## `scrcmd.c`), distinct from the player stepping onto a `Warp` node. Like
	## WAIT_MOVEMENT, carries no result, so a plain resume() is correct once
	## the scene reports the warp finished.
	WAIT_WARP,
	## [M27G G2] `special ChoosePartyMon` — the real party screen is open in
	## browse mode. Carries a result (the chosen slot, or "nothing chosen" on
	## cancel) exactly like WAIT_NAMING/WAIT_BATTLE — `resume()` alone is NOT
	## enough, the caller must go through `answer_party_choice`.
	WAIT_PARTY_CHOICE,
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

## [trainerbattle_earlyrival] `trainerbattle_no_intro`/`trainerbattle_earlyrival`
## both compile to the SAME shared handler, `EventScript_DoNoIntroTrainerBattle`
## (`battle_setup.c`'s `BattleSetup_ConfigureTrainerBattle`/`_ConfigureEarlyRivalBattle`
## dispatch both `TRAINER_BATTLE_SINGLE_NO_INTRO_TEXT` and `TRAINER_BATTLE_EARLY_RIVAL`
## to it) -- and that handler is `dotrainerbattle` / `gotopostbattlescript` with NO
## branch on outcome at all. `gotopostbattlescript` is `BattleSetup_GetScriptAddrAfterBattle`,
## which always resolves to the address right after the calling command -- i.e. an
## ALREADY-BEATEN or a WON battle both fall through to the next opcode in the calling
## script, unconditionally. Only a LOSS stops it (whiteout).
##
## This is a DIFFERENT shape from `trainerbattle_single`/`_double`/`_rematch*`, whose
## shared handler (`EventScript_TryDoNormalTrainerBattle`) genuinely branches:
## already-beaten falls through via `gotopostbattlescript`, but a WIN goes through
## `gotobeatenscript` -- a different resolution (the event_script ARGUMENT, or a
## fallback that ends the script if none was given). `resume_after_battle`'s existing
## "no continuation script means the win ends the script" rule is correct for THAT
## family and wrong for this one, so this flag lets one function serve both.
var pending_battle_always_continues: bool = false

## [M27F Stage 3] Movements the script has ASKED for but which the scene has not
## started yet. `applymovement` is asynchronous in source — it kicks a movement
## off and the script keeps running; `waitmovement` is the half that blocks. So
## this is a QUEUE the driver drains, not a pause.
var pending_movements: Array[Dictionary] = []

## Whose movement `waitmovement` is waiting on. "" means "everything".
var pending_wait_target: String = ""

## [Map scripts] Set by `warp`. `map` is the raw `MAP_*` token — already the
## exact string `Warp.dest_map` stores, so the scene's own MapConstants
## lookup resolves it unchanged. `x`/`y` are the destination CELL, not a
## warp id — source's `ScrCmd_warp` reads them literally.
var pending_warp: Dictionary = {}

## [Map scripts] Immediate object-event mutations the script has requested
## (`setobjectxyperm`/`setobjectmovementtype`/`turnobject`/`addobject`) —
## `{"op":"move"/"movement_type"/"turn"/"add"/"remove", "target":LOCALID, ...}`.
## Queued rather than applied inline for the same reason `pending_movements`
## is: the VM has no business resolving a LOCALID into a scene node, that is
## the caller's job. `removeobject` still ALSO appends to the older
## `removed_objects` below (an existing, separately-tested field) — this is
## the second, functionally-consumed record of the same event, not a
## replacement.
var pending_object_ops: Array[Dictionary] = []

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
	pending_battle_always_continues = false
	# ⚠️ .clear(), not `= []` — assigning an untyped array to a typed one
	# fails SILENTLY in GDScript, a gotcha this project has paid for before.
	pending_movements.clear()
	pending_wait_target = ""
	pending_warp = {}
	pending_object_ops.clear()
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
			Pause.WAIT_BATTLE, Pause.WAIT_MOVEMENT, Pause.WAIT_NAMING, Pause.WAIT_WARP,
			Pause.WAIT_PARTY_CHOICE]


func is_finished() -> bool:
	return pause_reason in [Pause.DONE, Pause.UNRESOLVED, Pause.UNKNOWN_OP]


## The caller reports that whatever we were waiting on has happened.
func resume() -> void:
	# ⚠️ WAIT_BATTLE, WAIT_NAMING and WAIT_PARTY_CHOICE are deliberately NOT
	# resumable this way. Each carries a RESULT: a battle's win/loss branch,
	# the typed nickname, the chosen party slot. Clearing any of them here
	# would silently drop it and read as "the script just carried on". Use
	# resume_after_battle() / answer_naming() / answer_party_choice().
	if is_waiting() and pause_reason != Pause.WAIT_BATTLE \
			and pause_reason != Pause.WAIT_NAMING \
			and pause_reason != Pause.WAIT_PARTY_CHOICE:
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

		# [Map scripts] Region/Pokédex area-reveal bookkeeping
		# (`FlagSetWorldMapFlag`) — no consumer exists anywhere in this
		# project (no region map, no Pokédex UI), so this is a genuine no-op
		# rather than a deferred mechanic. Listed explicitly, same reasoning
		# as the Stage 1 no-ops above: several OnTransition map scripts open
		# with this, and falling through to UNKNOWN_OP would halt the REST
		# of the script (including the conditional dispatch that matters).
		"setworldmapflag":
			return true

		# [Map scripts] `waitstate` (`scrcmd.c`) — the generic "an async
		# field task is running" wait. It names no task of its own; whatever
		# command started the task (here, only `warp`) is what actually set
		# a Pause reason, so by the time execution reaches this op the real
		# wait already happened. A pure passthrough, not a second wait.
		"waitstate":
			return true

		# [Map scripts] Each entry of an OnFrame/OnWarp table compiles down
		# to this op — the raw form of `MapHeaderCheckScriptTable`'s own
		# `VarGet(v1) == VarGet(v2)` check (`script.c:339`). Reuses
		# `goto_if_eq`'s exact 3-arg semantics — first match wins, a false
		# entry falls through to the next one in program order — rather than
		# a bespoke table-walker, since a sequence of these ops IS the
		# table. `call_if_eq`'s call-stack push is deliberately NOT used:
		# source starts the found script as the new running script, it does
		# not return here afterward.
		"map_script_2":
			if args.size() < 3:
				return true
			var have := _flags.var_get(str(args[0])) if _flags != null else 0
			last_compare = _cmp(have, _literal(str(args[1])))
			if not _compare_holds("eq", last_compare):
				return true
			return _jump(str(args[2]))

		# [Map scripts] `warp` (`ScrCmd_warp`, `scrcmd.c`) — a script-driven
		# warp to an explicit CELL, not a warp id. ASYNCHRONOUS like
		# `applymovement`/`trainerbattle_single`: the scene owns the actual
		# teardown/fade/reload, the VM only records where to and waits.
		# Args are (dest map constant, x, y); the map constant is already
		# the exact string `Warp.dest_map` stores.
		"warp":
			if args.size() < 3:
				pause_reason = Pause.UNKNOWN_OP
				diagnostic = "warp needs 3 args, got %d" % args.size()
				return false
			pending_warp = {
				"map": str(args[0]),
				"x": _resolve_number(str(args[1])),
				"y": _resolve_number(str(args[2])),
			}
			pause_reason = Pause.WAIT_WARP
			return false

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
		#
		# [Corridor op-code scope] `fadeoutbgm` joins the same group — its one
		# corridor use is the Pokémon Center Jigglypuff easter egg fading the
		# lobby music out before its own jingle plays. Same absence, same
		# reasoning; nothing about this opcode is different from its siblings.
		"playfanfare", "waitfanfare", "playse", "playbgm", "fadedefaultbgm", \
		"fadeoutbgm":
			return true

		# [M27K K-a] The mon picture Oak shows while offering the starter. This
		# project has no picture layer in the field at all — the front sprites
		# are pulled and battle-only. A no-op loses the flourish, not the scene.
		"showmonpic", "hidemonpic":
			return true

		# [Corridor op-code scope] `copyobjectxytoperm localId` — source bakes
		# an object event's LIVE position into its own permanent template, so
		# a moved NPC (Pallet Town's Sign Lady, stepping out of the doorway
		# once) doesn't reset to its spawn point on map reload. This project
		# has no template/instance split to begin with — a placed `NPC`
		# node's own `cell` IS the live, sole source of truth, so within one
		# play session the move already sticks with zero code. The real gap
		# this leaves is SAVE persistence (does a reloaded save remember she
		# moved?), which `[M27L]`'s save payload has no concept of for ANY
		# NPC yet — a general save-completeness question, not something to
		# solve one-off for a single sign lady. No-op until that's revisited.
		"copyobjectxytoperm":
			return true

		# [M27K K-a] Remove an object event from the map — the Poke Ball you
		# just took. `VAR_LAST_TALKED` is the object you interacted with, which
		# is why this needs the interaction to have recorded it.
		#
		# [Map scripts] ALSO queued into `pending_object_ops` now — the caller
		# hides the entity by setting its own `visibility_flag` (every entity
		# `addobject`/`removeobject` target in the corpus already carries one,
		# reused rather than invented), which is what makes taking a Pokéball
		# actually make it disappear, and what makes `addobject`'s own
		# counterpart below able to reverse the exact same mechanism.
		"removeobject":
			if args.size() > 0:
				removed_objects.append(str(args[0]))
				pending_object_ops.append({"op": "remove", "target": str(args[0])})
			return true

		# [Map scripts] The reverse of `removeobject` — an object event that
		# starts absent and is spawned in by a script (`ScrCmd_addobject`,
		# `scrcmd.c`). Both toggle the SAME mechanism, `visibility_flag`, so
		# an entity using this idiom needs no second visibility system.
		"addobject":
			if args.size() > 0:
				pending_object_ops.append({"op": "add", "target": str(args[0])})
			return true

		# [Map scripts] `setobjectxyperm` (`ScrCmd_setobjectxyperm`) — a
		# PERMANENT reposition (a data update, not an animated walk), used to
		# snap an entity to its resting spot after a scripted walk-in.
		"setobjectxyperm":
			if args.size() > 2:
				pending_object_ops.append({"op": "move", "target": str(args[0]),
						"x": _resolve_number(str(args[1])),
						"y": _resolve_number(str(args[2]))})
			return true

		# [Map scripts] `setobjectmovementtype` — changes an NPC's own
		# wander/idle behaviour outright (e.g. Oak going from his scripted
		# walk-in to a plain FACE_DOWN once the cutscene parks him).
		"setobjectmovementtype":
			if args.size() > 1:
				pending_object_ops.append({"op": "movement_type", "target": str(args[0]),
						"value": str(args[1])})
			return true

		# [Map scripts] `turnobject` — a static, immediate facing change, no
		# movement. Distinct from `applymovement`'s own FACE_* actions, which
		# are queued and animated through the movement runner.
		"turnobject":
			if args.size() > 1:
				pending_object_ops.append({"op": "turn", "target": str(args[0]),
						"dir": str(args[1])})
			return true

		# [Corridor op-code scope] `setmetatile x, y, metatileId, impassable`
		# (`ScrCmd_setmetatile`, `scrcmd.c:2741`) — replaces one cell's whole
		# metatile at runtime. `x`/`y` are LOCAL to whichever map is running
		# this script; the VM has no scene-tree access to resolve that to a
		# global cell (the same reason `removeobject`/`addobject` above queue
		# rather than act directly), so this queues into `pending_object_ops`
		# for the caller to apply against `MapManager.set_metatile` once it
		# resolves "the current map" the same way it already does for
		# OnFrame/OnLoad dispatch. All four args go through `_resolve_number`
		# — source reads every one of them via `VarGet`, and `metatileId` is
		# a METATILE_* constant in every real corpus use, never a raw int.
		"setmetatile":
			if args.size() < 4:
				pause_reason = Pause.UNKNOWN_OP
				diagnostic = "setmetatile needs 4 args, got %d" % args.size()
				return false
			pending_object_ops.append({"op": "setmetatile",
					"x": _resolve_number(str(args[0])), "y": _resolve_number(str(args[1])),
					"metatile_id": _resolve_number(str(args[2])),
					"impassable": _resolve_number(str(args[3])) != 0})
			return true

		# [Map scripts] Door-tile open/close animation and its own wait.
		# Cosmetic only — nothing in this project models a door's visual
		# open/closed state, and the corridor's own collision rules are not
		# gated on it, so skipping the animation loses nothing functional.
		"opendoor", "closedoor", "waitdooranim":
			return true

		# [Map scripts] Snapshot the current BGM to restore later
		# (`Cmd_savebgm`) — audio does not exist anywhere in this project
		# (see the `playfanfare` group's own doc comment), so this is the
		# same class of no-op.
		"savebgm":
			return true

		# [M27G G1] `signmsg`/`normalmsg` — a message-box display-mode toggle
		# (source's own docs: "used only in FireRed/LeafGreen"). NOT a
		# simplification: `script_cmd_table.inc:227-228` dispatches BOTH to
		# `ScrCmd_nop1` — Emerald never implemented either, and this
		# FRLG-focused expansion doesn't either. A literal port of an
		# already-inert function, found while tracing the Pewter Aide's real
		# Running Shoes script (`docs/m27g_recon.md`).
		"signmsg", "normalmsg":
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
			# [M27G G1] `BufferMonNickname` needs `party`, which `FieldSpecials`
			# deliberately never touches (it is stateless by design — see its
			# own file header). Same reason `ChangePokemonNickname` is
			# intercepted here rather than folded into that registry.
			if fn == "BufferMonNickname":
				return _buffer_mon_nickname()
			# [M27G G2] `ChoosePartyMon` opens the real party screen and waits
			# for a pick — same "owns the display" reasoning as the nickname
			# screen just above, checked before `FieldSpecials.run` for the
			# same reason.
			if fn == "ChoosePartyMon":
				pause_reason = Pause.WAIT_PARTY_CHOICE
				return false
			# [M27G G3a] `CreateInGameTradePokemon` does the actual party
			# mutation — real party context, so it lives here alongside
			# `ChoosePartyMon`/`ScriptGetPartyMonSpecies`, not in the
			# stateless `FieldSpecials` table.
			if fn == "CreateInGameTradePokemon":
				return _create_ingame_trade_pokemon()
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
			# [M27G G1] `ScriptGetPartyMonSpecies` needs `party` too — same
			# reasoning as `BufferMonNickname` just above.
			#
			# [M27G G3a] `GetTradeSpecies` is the SAME lookup under a different
			# name — source's own version additionally checks `MON_DATA_IS_EGG`
			# and returns `SPECIES_NONE` for one, but this project models no
			# eggs at all, so that check is unconditionally false and the two
			# functions are behaviorally identical here. `party_menu.c:4630-
			# 4637` vs. `field_specials.c:1641-1644` — different source files,
			# same real operation: "what did VAR_0x8004 pick."
			if vfn == "ScriptGetPartyMonSpecies" or vfn == "GetTradeSpecies":
				if _flags != null:
					_flags.var_set(dest, _party_mon_species(_flags.var_get("VAR_0x8004")))
				return true
			# [M27G G3a] `GetInGameTradeSpeciesInfo` needs both `party`
			# (indirectly, via the row it looks up) AND `buffers` — writes
			# STR_VAR_1/STR_VAR_2, which `FieldSpecials.specialvar_value`'s
			# single-int-return shape cannot express, matching
			# `bufferitemname`/`bufferspeciesname`'s own reasoning for living
			# here rather than in that stateless table.
			if vfn == "GetInGameTradeSpeciesInfo":
				if _flags != null:
					_flags.var_set(dest, _get_ingame_trade_species_info())
				return true
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
			# ⚠️ `COINS_PRICE_50`/`_500`/`MAGIKARP_PRICE` resolve through
			# `_SYMBOLIC_CONSTANTS` now (see its own doc comment) — this used
			# to fail closed on all three. Anything still unresolved after
			# that check is a genuinely unknown constant, not one of the
			# three named corpus cases.
			var amount := int(raw) if raw.is_valid_int() else \
					int(_SYMBOLIC_CONSTANTS.get(raw, -1))
			if amount < 0:
				# ⚠️ FAIL CLOSED, AND THIS DIRECTION IS THE WHOLE POINT.
				# Treating an unresolvable price as 0 would make `checkmoney`
				# report AFFORDABLE and the following `removemoney` charge
				# nothing: free goods. Reporting "cannot afford" refuses the
				# purchase instead, which is the recoverable direction.
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

		# [Map scripts] `trainerbattle_no_intro trainer, lose_text` — the
		# player never sees a "wants to battle" message. `WAIT_BATTLE`'s own
		# driver already treats an empty `pending_pages` as "skip straight to
		# the battle" (built for exactly this by `[M27F Stage 2]`'s own
		# `_trainer_battle`, unused until now), so no separate no-intro
		# branch was needed on the overworld side.
		#
		# ⚠️ SHARES `EventScript_DoNoIntroTrainerBattle` WITH `trainerbattle_
		# earlyrival` BELOW — `dotrainerbattle` then an unconditional
		# `gotopostbattlescript`, so a WIN falls through to the next opcode
		# in the calling script exactly like the already-beaten skip does,
		# never the `gotobeatenscript`-ends-the-script rule the single/
		# double/rematch family uses. `always_continues=true` carries that.
		"trainerbattle_no_intro":
			if args.size() < 2:
				pause_reason = Pause.UNKNOWN_OP
				diagnostic = "trainerbattle_no_intro needs 2 args, got %d" % args.size()
				return false
			return _start_trainer_battle(str(args[0]), "", str(args[1]), "", false, true)

		# [Map scripts] `trainerbattle_double trainer, intro, lose, not_enough
		# [, event_script[, music]]`.
		#
		# ⚠️ `not_enough_pkmn_text` IS PARSED AND DISCARDED, NOT WIRED. The
		# overworld's own trainer-party builder already flattens every
		# doubles trainer to a singles fight — `OverworldParty.
		# build_trainer_party`'s own comment: "the overworld has no
		# two-active concept yet", a disclosed gap from `[M27D D5]`, not this
		# opcode's to close. Dispatching this like an ordinary single battle
		# is honest about what actually happens; inventing a doubles-aware
		# use for this text would pretend otherwise.
		"trainerbattle_double":
			if args.size() < 4:
				pause_reason = Pause.UNKNOWN_OP
				diagnostic = "trainerbattle_double needs 4+ args, got %d" % args.size()
				return false
			return _start_trainer_battle(str(args[0]), str(args[1]), str(args[2]),
					_script_arg(args, 4), false)

		# [Map scripts] `trainerbattle_rematch trainer, intro, lose` — see
		# `_start_trainer_battle`'s own doc comment for the rematch-tier gap
		# this deliberately does not attempt to close.
		"trainerbattle_rematch":
			if args.size() < 3:
				pause_reason = Pause.UNKNOWN_OP
				diagnostic = "trainerbattle_rematch needs 3 args, got %d" % args.size()
				return false
			return _start_trainer_battle(str(args[0]), str(args[1]), str(args[2]), "", true)

		# [Map scripts] `trainerbattle_rematch_double trainer, intro, lose,
		# not_enough` — both gaps above at once (rematch-tier + doubles),
		# same disclosed reasoning as each.
		"trainerbattle_rematch_double":
			if args.size() < 4:
				pause_reason = Pause.UNKNOWN_OP
				diagnostic = "trainerbattle_rematch_double needs 4 args, got %d" % args.size()
				return false
			return _start_trainer_battle(str(args[0]), str(args[1]), str(args[2]), "", true)

		# [Map scripts] `trainerbattle_earlyrival trainer, flags, lose_text,
		# victory_text` — the Pallet Town starter rival battle. Its underlying
		# macro (`event.inc:831`) passes `intro_text_a=NULL` and
		# `event_script_a=NULL` into the shared `trainerbattle` struct, and
		# `BattleSetup_ConfigureTrainerBattle` dispatches `TRAINER_BATTLE_
		# EARLY_RIVAL` to the exact same `EventScript_DoNoIntroTrainerBattle`
		# handler `trainerbattle_no_intro` uses above — same no-intro-message
		# shape, same unconditional-fallthrough-on-win shape.
		#
		# `flags` (RIVAL_BATTLE_TUTORIAL) and `victory_text` (the rival's own
		# in-battle "won't lose" quote, `GetTrainerWonSpeech`) are both
		# BATTLE-side presentation this project's overworld VM has no seam
		# for and doesn't need one for — the field script's own control flow
		# never branches on either.
		"trainerbattle_earlyrival":
			if args.size() < 3:
				pause_reason = Pause.UNKNOWN_OP
				diagnostic = "trainerbattle_earlyrival needs 3+ args, got %d" % args.size()
				return false
			return _start_trainer_battle(str(args[0]), "", str(args[2]), "", false, true)

		# [Map scripts] `checkplayergender` — writes VAR_RESULT with the
		# player's chosen gender (`ScrCmd_checkplayergender`, `scrcmd.c`).
		# `PlayerIdentity.Gender.BOY`/`GIRL` are 0/1, the same values
		# source's own `gSaveBlock2Ptr->playerGender` stores, so no
		# remapping is needed.
		"checkplayergender":
			_set_result_value(TextBuffers.active_identity().gender)
			return true

		# [Map scripts] `random limit` — VAR_RESULT = a uniform roll in
		# [0, limit) (`ScrCmd_random`, `scrcmd.c`: `Random() % max`). `limit`
		# runs through `_resolve_number` since source resolves it via
		# `VarGet` — the corpus carries both a literal and a var form.
		# ⚠️ limit<=0 is defensive, not source-observed: C's `% 0` is
		# undefined behaviour and no real script passes one.
		"random":
			var _limit := _resolve_number(str(args[0])) if args.size() > 0 else 0
			_set_result_value(randi() % _limit if _limit > 0 else 0)
			return true

		# [Map scripts] `setorcopyvar dest, source` — the same VarGet-
		# resolved copy `copyvar` already does. Source's own `ScrCmd_copyvar`
		# reads the source's RAW storage while `ScrCmd_setorcopyvar` resolves
		# it through `VarGet` — a real distinction in source, but this
		# project's own `FlagStore.var_get` is already the single accessor
		# every var read goes through regardless of opcode, so the two are
		# indistinguishable here. Disclosed rather than silently assumed.
		"setorcopyvar":
			if _flags != null and args.size() > 1:
				_flags.var_set(str(args[0]), _flags.var_get(str(args[1])))
			return true

		# [Map scripts] `waitse`/`playmoncry`/`waitmoncry` — the same
		# audio-does-not-exist no-op class as the `playfanfare` group above.
		"waitse", "playmoncry", "waitmoncry":
			return true

		# [Map scripts] `bufferboxname slot, box` — writes a PC box's name to
		# a string buffer (`GetBoxNamePtr`, `scrcmd.c`). Halts rather than
		# inventing a name, the same call `_begin_nickname`'s own PC branch
		# already makes: there is no PC (I5-5, deferred past the slice), so
		# there is no real box name to buffer.
		"bufferboxname":
			pause_reason = Pause.UNKNOWN_OP
			diagnostic = "bufferboxname: no PC exists (I5-5)"
			return false

		# [Map scripts] The two `fadescreen` siblings named but deliberately
		# excluded when that opcode shipped — see its own doc comment just
		# below. Both are the same no-op for the same reason: the fade this
		# family starts is never closed by a matching opcode in most of the
		# corpus, so a faithful-looking fade here would leave the screen
		# black for good.
		"fadescreenspeed", "fadescreenswapbuffers":
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
	return _start_trainer_battle(str(args[0]), str(args[1]), str(args[2]),
			_script_arg(args, 3), false)


## [Map scripts] Shared mount, behind all five `trainerbattle_*` variants this
## VM dispatches — extracted once the family grew past the single-battle case
## `[M27F Stage 2]` shipped, so the already-beaten skip / intro-display /
## continuation-routing logic exists in exactly one place.
##
## ⚠️ **REMATCH VARIANTS PASS `skip_already_beaten_check = true`, AND THE
## REASON IS A REAL GAP, NOT A CONVENIENCE.** Source's own dispatch
## (`BattleSetup_GetTrainerBattleScript`, `battle_setup.c:1144`) remaps the
## trainer id through `GetRematchTrainerId` BEFORE the already-beaten check
## is ever reached — a rematch-TIER lookup table this project does not have
## (M35's full rematch/postgame progression system, still deferred). Without
## it there is no stronger roster to remap to, so the disclosed simplification
## is to re-fight the SAME trainer's existing static roster rather than
## invent a tier. This is safe because the CALLING script is what decides
## whether a rematch is even offered in the first place — the standard shape
## upstream of a rematch trigger is a `goto_if_defeated` already gating it —
## so this opcode does not need to re-derive that itself, and skipping its own
## internal check does not open a rematch that shouldn't be reachable.
func _start_trainer_battle(trainer: String, intro_label: String, defeat_label: String,
		continuation_label: String, skip_already_beaten_check: bool,
		always_continues: bool = false) -> bool:
	pending_trainer_key = trainer
	pending_battle_intro = intro_label
	pending_battle_defeat_text = defeat_label
	pending_battle_script = continuation_label
	pending_battle_always_continues = always_continues

	# The already-beaten skip. Source checks `GetTrainerFlag` inside the shared
	# script, one level below the command -- which is why Brock's own script has
	# no guard of its own and would otherwise re-challenge forever.
	if not skip_already_beaten_check and _flags != null \
			and _flags.trainer_defeated(trainer):
		return true

	# The intro speech. Source shows it before the battle
	# (`EventScript_ShowTrainerIntroMsg`); the box belongs to the driver, so the
	# pages are handed over the same way `message` hands them over. Empty for
	# `trainerbattle_no_intro`, whose own driver-side handling of a zero-page
	# `pending_pages` (`WAIT_BATTLE`'s branch in `overworld.gd`) already skips
	# straight to the battle.
	pending_pages = _source.pages_for(intro_label) if _source != null and intro_label != "" \
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
	if pending_battle_always_continues:
		# `trainerbattle_no_intro`/`trainerbattle_earlyrival`'s shared handler
		# (`EventScript_DoNoIntroTrainerBattle`) is `dotrainerbattle` then an
		# UNCONDITIONAL `gotopostbattlescript` -- a win falls through to the
		# next opcode in the calling script exactly like the already-beaten
		# skip above does, not a `gotobeatenscript` resolution. `pc` was
		# already advanced past the trainerbattle op before it paused, so
		# clearing the pause is the whole "continue" -- no jump needed.
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


## [M27G G2] `PARTY_NOTHING_CHOSEN` (`include/constants/party_menu.h:5`) — the
## sentinel `BufferMonSelection`/`CB2_ChooseMonForMoveRelearner` both write on
## a cancel or an out-of-range pick. Deliberately DISTINCT from `PC_MON_CHOSEN`
## above (0xFE vs 0xFF, both real source sentinels for two different things —
## "the PC was chosen instead" vs "nothing was chosen at all").
const PARTY_NOTHING_CHOSEN := 0xFF


## [M27G G2] The caller reports what the real party screen (browse mode)
## produced. Mirrors `answer_naming`'s own shape: `WAIT_PARTY_CHOICE` carries a
## result, so a plain `resume()` cannot clear it (see `resume()`'s own guard).
##
## `index` is whatever `FieldPartyScreen.confirm()`/`.close()` already report —
## a real 0-5 slot, or -1 on cancel (the screen's own "invalid" sentinel,
## `[M27I I5-2]`'s `confirm()`). Both -1 AND an out-of-range index write
## `PARTY_NOTHING_CHOSEN`, matching source's own `>= PARTY_SIZE` check
## (`BufferMonSelection`, `party_menu.c:8046-8052`) rather than assuming the
## screen's own -1 convention is the only "nothing chosen" shape a caller
## could ever hand in.
func answer_party_choice(index: int) -> void:
	if pause_reason != Pause.WAIT_PARTY_CHOICE:
		return
	if _flags != null:
		_flags.var_set("VAR_0x8004",
				index if index >= 0 and index < party.members.size() else PARTY_NOTHING_CHOSEN)
	pause_reason = Pause.NONE


## [M27G G1] `ScriptGetPartyMonSpecies` — party-ONLY, unlike `BufferMonNickname`
## just below. Source: `GetMonData(&gParties[B_TRAINER_PLAYER][
## gSpecialVar_0x8004], MON_DATA_SPECIES_OR_EGG, NULL)` (`field_specials.c:
## 1641-1644`) — no PC fallback exists in that function at all, so unlike
## `_begin_nickname`'s own `PC_MON_CHOSEN` guard, there is no second branch to
## refuse here; an out-of-range slot degrades to 0 (no species), the same
## "unknown constant" shape `_literal` already uses elsewhere.
func _party_mon_species(slot: int) -> int:
	if slot < 0 or slot >= party.members.size():
		return 0
	var mon: BattlePokemon = party.members[slot]
	if mon == null or mon.species == null:
		return 0
	return mon.species.national_dex_num


## [M27G G1] `BufferMonNickname` — writes the chosen party member's nickname
## into buffer slot 0 (`gStringVar1`). ⚠️ Source's own `GetSelectedBoxMonFromPcOrParty`
## DOES support a PC fallback (`PC_MON_CHOSEN`, the same sentinel
## `_begin_nickname` already guards) — this project has no PC (I5-5, still
## deferred), so the PC branch halts rather than guessing, the identical
## precedent `_begin_nickname`'s own PC branch already established.
func _buffer_mon_nickname() -> bool:
	var slot := 0
	if _flags != null:
		slot = _flags.var_get("VAR_0x8004")
	if slot == PC_MON_CHOSEN:
		pause_reason = Pause.UNKNOWN_OP
		diagnostic = "BufferMonNickname: the PC path needs a PC (I5-5)"
		return false
	if slot < 0 or slot >= party.members.size():
		pause_reason = Pause.UNKNOWN_OP
		diagnostic = ("BufferMonNickname: VAR_0x8004 is %d, and the party "
				+ "holds %d") % [slot, party.members.size()]
		return false
	var mon: BattlePokemon = party.members[slot]
	buffers.set_slot(0, mon.display_name() if mon != null else "")
	return true


## [M27G G3a] Friendship a traded-in Pokémon always starts at, regardless of
## the row — a CONSTANT in source, not per-entry data (`TradeMons`,
## `src/trade.c:3104`: `friendship = 70;`, unconditional except for eggs,
## which this project does not model).
const TRADE_FRIENDSHIP := 70


## [M27G G3a] `GetInGameTradeSpeciesInfo` (`src/trade.c:4545-4551`) — indexes
## `data/ingame_trades.json` by `VAR_0x8005` (see `_INGAME_TRADE_IDS`'s own
## doc comment for how that got set), buffers the REQUESTED species' name
## into slot 0 (`STR_VAR_1`) and the GIVEN-AWAY species' name into slot 1
## (`STR_VAR_2`) — source's own argument order, not alphabetical or by table
## field order — and returns the requested species' dex as the specialvar
## result. An out-of-range row degrades to empty buffers and 0, the same
## shape `_party_mon_species`'s own out-of-range case already uses.
func _get_ingame_trade_species_info() -> int:
	var row := IngameTradeRegistry.entry(_flags.var_get("VAR_0x8005") if _flags != null else -1)
	if row.is_empty():
		buffers.set_slot(0, "")
		buffers.set_slot(1, "")
		return 0
	buffers.set_slot(0, _species_name(str(int(row.get("requested_species", 0)))))
	buffers.set_slot(1, _species_name(str(int(row.get("species", 0)))))
	return int(row.get("requested_species", 0))


## [M27G G3a] `CreateInGameTradePokemon` (`src/trade.c:4562-4610, 4639-4642`)
## — builds the incoming Pokémon from the row `GetInGameTradeSpeciesInfo`
## already indexed (`VAR_0x8005`, persisted across the whole script) and
## swaps it into the SAME party slot the player's offered mon occupies
## (`VAR_0x8004`, from `ChoosePartyMon`). A direct in-place replace, matching
## source's own `SWAP(*playerMon, *partnerMon, sTradeAnim->tempMon)`
## (`TradeMons`, `:3100`) — NOT a remove-then-append, which would move the
## traded-in mon to a different slot than the one it actually landed in.
##
## Level is the OFFERED mon's own level (source: `CreateInGameTradePokemonInternal`
## reads it off `playerMon` before building the new one), not a fixed value
## from the row. Ability slot and all 6 IVs are forced from the row directly
## — `PokemonFactory.create_battle_pokemon`'s own `forced_ivs`/`ability_slot`
## params exist for exactly this (built ahead of need for M24's trainer
## data, per that function's own doc comment).
##
## ⚠️ Degrades safely (a no-op, script continues) on an out-of-range slot or
## an unresolved row — both mean an EARLIER opcode in the calling script
## already misfired (a bad `ChoosePartyMon` answer, an unresolved
## `INGAME_TRADE_*`), and this is not the place to surface that.
func _create_ingame_trade_pokemon() -> bool:
	if _flags == null or party == null:
		return true
	var slot := _flags.var_get("VAR_0x8004")
	if slot < 0 or slot >= party.members.size():
		return true
	var row := IngameTradeRegistry.entry(_flags.var_get("VAR_0x8005"))
	if row.is_empty():
		return true
	var offered: BattlePokemon = party.members[slot]
	if offered == null:
		return true
	var raw_ivs: Array = row.get("ivs", [])
	var ivs: Array[int] = []
	for v in raw_ivs:
		ivs.append(int(v))
	var incoming := PokemonFactory.create_battle_pokemon(
			int(row.get("species", 0)), offered.level, [], null,
			ivs if ivs.size() == 6 else null, TRADE_FRIENDSHIP, null,
			int(row.get("ability_num", 0)))
	if incoming == null:
		return true
	incoming.nickname = str(row.get("nickname", ""))
	incoming.held_item = _resolve_trade_held_item(int(row.get("held_item", 0)))
	party.members[slot] = incoming
	return true


## Only the items this project actually has a real `.tres` for resolve —
## everything else (mail, Tiny Mushroom, Stardust — none of which have any
## held-item mechanic in this project regardless) degrades to no item held,
## rather than a noisy `ItemRegistry.get_item` warning on every such trade.
func _resolve_trade_held_item(item_id: int) -> ItemData:
	if item_id <= 0:
		return null
	if not ResourceLoader.exists("res://data/items/item_%04d.tres" % item_id):
		return null
	return ItemRegistry.get_item(item_id)


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
				# [M27G G3a] ⚠️ `args[1]` MUST GO THROUGH `_resolve_number`, NOT
				# `_literal` DIRECTLY — a real, general bug found by driving the
				# real corpus, not specific to trade scripts. `goto_if_ne
				# VAR_RESULT, VAR_0x8009, ...` (Reyley's own "did the player
				# offer the right species" check, and the IDENTICAL shape on
				# 6 of the other 7 in-game trade NPCs) compares two VARIABLES
				# — source's own `VarGet` resolves EVERY operand uniformly
				# (raw var vs. literal constant), but this branch always ran
				# `_literal("VAR_0x8009")`, which has no case for it and falls
				# through to 0. VAR_RESULT (63) != 0 read as "wrong species",
				# so every one of these NPCs took the WRONG branch on a
				# CORRECT trade. `_resolve_number` already implements the
				# real var-then-literal duality (`setvar`'s own value arg
				# still goes through plain `_literal`, since a `setvar` target
				# is always a literal in source — `copyvar` is the
				# var-to-var op — so that call site is deliberately untouched).
				last_compare = _cmp(have, _resolve_number(str(args[1])))
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


## [M27G G3a] `enum InGameTradeID` (`include/constants/trade.h:8-24`) —
## the ROW `VAR_0x8005` indexes into `data/ingame_trades.json`'s own array
## (`GetInGameTradeSpeciesInfo`/`CreateInGameTradePokemon`). Every real trade
## NPC sets it via `setvar VAR_0x8008, INGAME_TRADE_MR_MIME` /
## `copyvar VAR_0x8005, VAR_0x8008` — unresolved, this falls through to 0
## (`INGAME_TRADE_SEEDOT`, the FIRST row) for every single one, the same
## silent-wrong-branch shape G2's own `PARTY_SIZE` gap had. GENERAL, not
## Hoenn-only, unlike `_SYMBOLIC_CONSTANTS` below — kept as its own dict for
## that reason, and because these are ROW INDICES (0-12), not price/rate
## values.
const _INGAME_TRADE_IDS := {
	"INGAME_TRADE_SEEDOT": 0, "INGAME_TRADE_PLUSLE": 1,
	"INGAME_TRADE_HORSEA": 2, "INGAME_TRADE_MEOWTH": 3,
	"INGAME_TRADE_MR_MIME": 4, "INGAME_TRADE_JYNX": 5,
	"INGAME_TRADE_NIDORAN": 6, "INGAME_TRADE_FARFETCHD": 7,
	"INGAME_TRADE_NIDORINOA": 8, "INGAME_TRADE_LICKITUNG": 9,
	"INGAME_TRADE_ELECTRODE": 10, "INGAME_TRADE_TANGELA": 11,
	"INGAME_TRADE_SEEL": 12,
}


## [Map scripts] File-scoped assembler constants (`.set`/`#define`) that the
## script compiler leaves unresolved because they are not `VAR_`/`FLAG_`/
## `SPECIES_`-style names it has a table for — real corpus values for
## `addvar`/`subvar`/`checkmoney`/`addmoney`/`removemoney`.
##
## ⚠️ EVERY ONE OF THESE IS CONFIRMED, BY DIRECT SOURCE CITATION, HOENN-ONLY
## CONTENT — Route 113's Glass Workshop, Mauville's Game Corner, the Route 4
## Pokémon Center's Magikarp salesman — not merely content outside the
## current corridor, content this Kanto project will never author a map for
## at all. Kept anyway: the values are cheap and sourced, and "resolves to a
## real number" is strictly safer than the fail-closed 0 it replaces, on the
## chance a future session ever imports the Hoenn geography wholesale.
const _SYMBOLIC_CONSTANTS := {
	"ROULETTE_SPECIAL_RATE": 1 << 7,  # include/constants/roulette.h:5
	"BLUE_FLUTE_PRICE": 250,          # data/maps/Route113_GlassWorkshop/scripts.inc:5
	"YELLOW_FLUTE_PRICE": 500,        # :6
	"RED_FLUTE_PRICE": 500,           # :7
	"WHITE_FLUTE_PRICE": 1000,        # :8
	"BLACK_FLUTE_PRICE": 1000,        # :9
	"PRETTY_CHAIR_PRICE": 6000,       # :10
	"PRETTY_DESK_PRICE": 8000,        # :11
	"MAGIKARP_PRICE": 500,            # data/maps/Route4_PokemonCenter_1F_Frlg/scripts.inc:1
	"COINS_PRICE_50": 1000,           # data/maps/MauvilleCity_GameCorner/scripts.inc:12
	"COINS_PRICE_500": 10000,         # :13
}


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
		# [M27G G2] A GENERAL constant, not Hoenn-only — 57 region-wide corpus
		# uses, most in the exact `goto_if_ge VAR_0x8004, PARTY_SIZE, Decline*`
		# shape `ChoosePartyMon`'s own callers use to detect "nothing chosen"
		# (PARTY_NOTHING_CHOSEN=0xFF >= PARTY_SIZE). Unresolved, every one of
		# those checks always took the Decline branch, regardless of what was
		# actually picked — found while driving `PalletTown_RivalsHouse_
		# EventScript_GroomMon`, whose own very next opcode after `ChoosePartyMon`
		# is exactly this check (`include/constants/global.h:82`).
		"PARTY_SIZE": return BattleParty.PARTY_SIZE
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
	# [Corridor op-code scope] `setmetatile`'s own metatileId argument is a
	# METATILE_<Tileset>_<Name> constant, never a raw int in the corpus —
	# same shape as SPECIES_ above, resolved through the generated
	# `MetatileLabels` table rather than a hand-picked pair.
	if tok.begins_with("METATILE_"):
		return MetatileLabels.id_of(tok)
	# [M27G G3a] Checked here, alongside SPECIES_ above — see
	# `_INGAME_TRADE_IDS`'s own doc comment.
	if _INGAME_TRADE_IDS.has(tok):
		return _INGAME_TRADE_IDS[tok]
	# [Map scripts] The Hoenn-only shop/roulette constants `addvar`/`subvar`
	# already route through here — see `_SYMBOLIC_CONSTANTS`'s own doc
	# comment for why they are worth carrying despite never being reachable
	# from a Kanto map.
	if _SYMBOLIC_CONSTANTS.has(tok):
		return _SYMBOLIC_CONSTANTS[tok]
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
