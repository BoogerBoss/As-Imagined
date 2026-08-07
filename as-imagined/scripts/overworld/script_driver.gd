class_name ScriptDriver
extends RefCounted

## [M27G G4] The bridge between `ScriptVM` and the scene.
##
## ⚠️ **A PURE EXTRACTION. Nothing here is new behaviour** — every function was
## lifted verbatim out of `overworld.gd`, which had grown to 3,178 lines with
## roughly 400 of them being this. The only edits made in the move were
## mechanical: `_vm` -> `vm`, `_script_source` -> `source`, and every reference
## to a scene-side field now goes through `_ow`.
##
## **The boundary is EXECUTION vs TRIGGERING**, and it is deliberately not the
## boundary `docs/m27g_scope.md` originally sketched:
##
##   * **ScriptDriver owns running a script** — the VM instance, the compiled
##     corpora, the one-op-per-frame pump, the pause dispatch, and the
##     `applymovement` / object-op queue drains.
##   * **Overworld owns deciding a script should run** — `try_interact`,
##     `check_step_trigger`, `check_trainer_sight`, `check_on_frame_map_script`,
##     the warp lifecycle — and owns every scene RESOURCE the driver borrows
##     (the message box, the yes/no box, the naming screen, the party screen).
##
## The scope doc listed the UI nodes as moving too. They deliberately did not:
## `run_new_game`, `_poison_step` and `_on_start_menu_save` all open the same
## message box with no VM running, so moving ownership here would have meant
## rewriting three unrelated call sites in a phase whose whole acceptance
## criterion is "no behaviour changed". They stay where they are and are
## borrowed through `_ow`.
##
## ⚠️ **`_ow` IS DELIBERATELY UNTYPED.** `overworld.gd` carries no `class_name`
## (a long-standing wart this project has already worked around once — see
## `FlagStore.BADGE_FLAGS`, moved there precisely because `overworld.gd` could
## not be seen from another script). Giving it one would let this be
## `var _ow: Overworld`, but `overworld.gd` must then reference `ScriptDriver`
## while `ScriptDriver` references `Overworld` — a cyclic `class_name`
## dependency, which Godot 4 resolves inconsistently. An untyped reference
## costs static checking on ~8 call sites and buys a seam that cannot fail to
## parse. Revisit if `overworld.gd` ever gains a `class_name` for other reasons.
##
## ⚠️ **`RefCounted`, NOT `Node` — and `docs/m27g_scope.md` said Node.** Two
## reasons the scope doc was wrong:
##
##   1. **Convention.** Every other non-visual system in this project is
##      RefCounted — `ScriptVM`, `FlagStore`, `Interaction`, `MovementRunner`,
##      `Bag`, `Wallet`. This drives nothing itself; `Overworld._process` pumps
##      it. It has no reason to be in the tree.
##   2. **It has to exist before `_ready()`.** `m27i_text_buffers_test`
##      instantiates `overworld.tscn` and deliberately never adds it to the
##      tree (`_ready()` would boot the whole region), then assigns `ow._vm`
##      and calls `ow._expanded_pages()`. A Node created in `_setup_scripting`
##      does not exist on that path, so the forwarding property would silently
##      no-op; a Node created at declaration would instead leak, since nothing
##      ever parents or frees it. RefCounted at declaration is the only shape
##      that satisfies both, and it is the one the test was already written
##      against when `_vm` was a plain field.


## The running script, or null. ⚠️ Read/written through `Overworld._vm`, which
## is a forwarding property — `m27i_text_buffers_test` assigns it directly.
var vm: ScriptVM = null

## The compiled corpora, loaded once at boot.
var source: ScriptVM.ScriptSource = null

## [M27G G2] Whether the open party screen belongs to the VM's own
## `WAIT_PARTY_CHOICE` rather than to item-use or a plain browse.
var party_choice_pending := false

## [M27G G5] `native` handlers, owned per-driver. See NativeEventRegistry.
var natives := NativeEventRegistry.new()

## The scene this drives. Untyped — see the class doc comment.
var _ow = null


func setup(ow) -> void:
	_ow = ow
	# [M27G G5] The project's own `native` handlers, into THIS driver's own
	# registry — see NativeEventRegistry's header for why it is not static.
	FieldNativeEvents.register_all(natives)
	source = ScriptVM.ScriptSource.new()
	source.ops_by_label = _read_json("res://data/map_scripts.json")
	source.texts = _read_json("res://data/map_texts.json")
	# [M27G G6] Authored scripts join the SAME table the imported ones live in,
	# which is what makes `ScriptVM` unable to tell them apart — an authored
	# script can be `goto`'d from an imported one and vice versa.
	#
	# ⚠️ Merged AFTER the corpus loads, never before: `merge_into` refuses a
	# label that already exists and reports it, so the imported script always
	# wins a collision. Merging first would invert that silently.
	AuthoredEvents.register_all()
	EventRegistry.merge_into(source.ops_by_label)
	# ⚠️ Authored DIALOGUE is not merged — it lives in the one corpus with
	# everything else (field_script_source/data/scripts/authored_text.inc), so
	# it is already in `source.texts` by the time we get here. What is checked
	# instead is that every label an authored script NAMES actually resolves:
	# the label is a string naming a row in a separately-compiled corpus, which
	# is the one thing the GDScript front-end cannot type-check.
	var missing := EventRegistry.verify_text(source.texts)
	if not missing.is_empty():
		push_warning("ScriptDriver: authored scripts name %d text label(s) the "
				% missing.size() + "corpus does not define: %s. Did gen_map_texts.py run?"
				% ", ".join(missing))


## [M27F] Both JSONs are read at boot for the same reason the TileSets are: a
## first interaction should not pay an 8.8 MB parse mid-conversation. Measured
## at ~200 ms for the scripts, which is boot cost where a pause is expected.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("overworld: %s missing — scripts will not run" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## [M27G G5] The scene, for `native` handlers. Public because a handler is
## ordinary Godot code living outside this file and legitimately needs the
## tree — `_ow` itself stays private so the handler surface is one named thing
## rather than a field everyone reaches into.
func scene():
	return _ow


func has_script(label: String) -> bool:
	return source != null and source.has_script(label)


## Start a script. Public so a test — and a trigger or a warp — can start one
## without simulating a button press.
func run_script(label: String, p_subject: OverworldEntity = null) -> bool:
	vm = ScriptVM.new(source, _ow.flags)
	# [M27I I3] The session's bag, not the VM's own default — the same reason
	# `flags` reads through OverworldSession. A per-script bag would forget
	# every item the moment the script ended.
	vm.bag = OverworldSession.bag
	vm.respawn = OverworldSession.respawn
	vm.wallet = OverworldSession.wallet
	# [M27K K-a] The session party, for `givemon` — same reason as the bag.
	vm.party = OverworldSession.player_party()
	# [M27G G8] So an unhandled `special` can be routed to a registered handler
	# — and, just as importantly, so the VM can still say by itself when one is
	# NOT registered. See ScriptVM.natives.
	vm.natives = natives
	if not vm.start(label, p_subject):
		# Degrade LOUDLY but without breaking play: the VM named what it could
		# not resolve, so say so and hand control back.
		push_warning("overworld: %s" % vm.diagnostic)
		_ow.script_finished.emit(label, "UNRESOLVED", vm.diagnostic)
		vm = null
		return false
	_ow.script_started.emit(label)
	return true


## Advance the running script. Called once per frame while `vm` is live.
##
## THIS is what the VM's external state is for. The driver reads `pause_reason`
## and decides what the scene should do about it — the VM never awaits, never
## touches the message box, and never knows what a button is.
func drive() -> void:
	if vm == null:
		return

	# Run until the VM needs something from us.
	var guard := 0
	while vm.step() and guard < 500:
		guard += 1

	# [M27F Stage 3] `applymovement` is ASYNCHRONOUS: it queues rather than
	# pausing, so the script keeps running and a cutscene can start two
	# entities walking at once. Drained here, after stepping, so everything
	# queued this frame starts together.
	start_pending_movements()
	# [Map scripts] setobjectxyperm/setobjectmovementtype/turnobject/
	# addobject/removeobject — same drain shape as movements, immediately
	# after them so a script that repositions an entity THEN walks it (or
	# vice versa) sees its own ops applied in the order it issued them.
	apply_pending_object_ops()

	match vm.pause_reason:
		ScriptVM.Pause.WAIT_MESSAGE:
			# `message` only OPENS the box. The compiled msgbox chain is
			# message -> waitmessage -> waitbuttonpress, so the waiting belongs
			# to WAIT_BUTTON below; resuming here is what lets the VM reach it.
			if not _ow._box.is_open:
				_ow._box.open(expanded_pages())
			vm.resume()

		ScriptVM.Pause.WAIT_BUTTON:
			if _ow._box.is_open:
				if Input.is_action_just_pressed("ui_accept"):
					if not _ow._box.advance():
						vm.resume()
			else:
				vm.resume()

		ScriptVM.Pause.WAIT_YES_NO:
			# [M27F Stage 4] A REAL prompt. Stage 1 answered NO unconditionally
			# as a disclosed stopgap, which made every one of the corpus's 425
			# yes/no call sites unreachable past the question.
			#
			# ⚠️ YES = 1, NO = 0 (`Task_HandleYesNoInput` writes
			# `gSpecialVar_Result` 1 for row 0 and 0 for row 1 or B). The two are
			# not interchangeable: `goto_if_eq VAR_RESULT, YES` is what every
			# call site branches on.
			if not _ow._yes_no.is_open:
				_ow._yes_no.open()
			elif _ow._yes_no.accepts_input:
				if Input.is_action_just_pressed("ui_up"):
					_ow._yes_no.move(-1)
				elif Input.is_action_just_pressed("ui_down"):
					_ow._yes_no.move(1)
				elif Input.is_action_just_pressed("ui_cancel"):
					_ow._yes_no.cancel()
					vm.cancel_yes_no()
				elif Input.is_action_just_pressed("ui_accept"):
					# ⚠️ The VM writes VAR_RESULT, not this — `yesnobox` and
					# `multichoice MULTI_YESNO` use OPPOSITE polarity and only
					# the VM knows which opcode paused.
					vm.answer_yes_no(_ow._yes_no.confirm())

		ScriptVM.Pause.WAIT_BATTLE:
			# The trainer's intro speech runs first, then the battle. Source does
			# the same (`EventScript_ShowTrainerIntroMsg` precedes `dotrainerbattle`).
			if vm.pending_pages.size() > 0:
				if not _ow._box.is_open:
					_ow._box.open(expanded_pages())
				elif Input.is_action_just_pressed("ui_accept") and not _ow._box.advance():
					_ow._box.close()
					vm.pending_pages = PackedStringArray()
				return
			if not _ow.start_script_battle(vm.pending_trainer_key):
				# Cannot start (no resolvable party, no scene). End the script
				# rather than retrying this branch every frame forever.
				push_warning("overworld: battle vs '%s' could not start"
					% vm.pending_trainer_key)
				vm.resume_after_battle(false)
				finish()

		ScriptVM.Pause.WAIT_MOVEMENT:
			# The blocking half. A plain `resume()` is right here because there
			# is no RESULT to branch on — unlike WAIT_BATTLE, which must never
			# be resumed this way or the win/loss branch is silently skipped.
			if not movement_pending():
				vm.resume()

		ScriptVM.Pause.WAIT_NAMING:
			# [M27K K-c] The keyboard, on a party member the script picked.
			#
			# ⚠️ `open_keyboard`, NOT `open` — a nickname has no preset list in
			# source (`sMonNamingScreenTemplate` is a bare keyboard), and it
			# accepts an empty entry, which is how you back out once the keyboard
			# is up. `_drive_naming` handles the keys; this branch only opens it
			# and waits, because `answer_naming` is what actually resumes the VM.
			if not _ow._naming.is_open and vm.naming_slot >= 0:
				if not _ow._naming.name_chosen.is_connected(on_name_chosen):
					_ow._naming.name_chosen.connect(on_name_chosen)
				_ow._naming.open_keyboard(vm.naming_prompt())

		# [Map scripts] `warp`. Guarded on `_warping` rather than a local
		# flag — `_do_scripted_warp` sets it at its own very start, the same
		# way `_do_warp` already does, so this can't be re-triggered every
		# frame while the fade/teardown/reload is in flight.
		ScriptVM.Pause.WAIT_WARP:
			if not _ow._warping:
				_ow._do_scripted_warp(vm.pending_warp)

		# [M27G G2] `special ChoosePartyMon` — the real party screen, in
		# BROWSE mode (no item name), reusing the exact node the bag's own
		# item-use flow already shares. Guarded on `party_choice_pending`
		# rather than `_party_screen.is_open` so a re-entrant frame (the
		# screen takes a frame to actually open) cannot double-open it.
		ScriptVM.Pause.WAIT_PARTY_CHOICE:
			if not party_choice_pending:
				party_choice_pending = true
				_ow._pending_use_item = -1
				_ow._party_screen.open(vm.party)

		# [M27G G5] `native` — registered Godot code owns the screen until it
		# reports back. Guarded on `_native_running` rather than on the pause
		# itself, because the pause STAYS WAIT_NATIVE for the whole handler
		# (that is what makes it observable) and this branch runs every frame.
		ScriptVM.Pause.WAIT_NATIVE:
			if not _native_running:
				_native_running = true
				_run_native(vm.pending_native, vm.pending_native_args)

		ScriptVM.Pause.DONE, ScriptVM.Pause.UNRESOLVED, ScriptVM.Pause.UNKNOWN_OP:
			finish()


## [M27G G5] Whether a `native` handler is in flight. Not on the VM: the VM's
## job is to record that it is waiting, not to track who is answering.
var _native_running := false


## [M27G G5] ⚠️ **THE ONLY `await` IN THE ENTIRE SCRIPT PIPELINE.**
##
## Everything else — the VM, the pause dispatch, the queue drains — is
## frame-driven and inspectable precisely because nothing suspends. Confining
## the one genuine suspension to this function means there is exactly ONE place
## that has to handle "the world may have changed while we were gone", instead
## of one per cutscene (which is what `run_new_game` costs today, and what G7
## exists to retire).
##
## ⚠️ An unregistered handler HALTS and NAMES ITSELF rather than being skipped —
## the same discipline an unknown `special` already uses, and for the same
## reason: a silent skip makes coverage figures lie.
func _run_native(handler_name: String, handler_args: Array) -> void:
	var handler := natives.get_handler(handler_name)
	if not handler.is_valid():
		_native_running = false
		if vm != null:
			vm.pause_reason = ScriptVM.Pause.UNKNOWN_OP
			vm.diagnostic = "native handler '%s' is not registered" % handler_name
		return
	var result: Variant = await handler.call(self, handler_args)
	_native_running = false
	# ⚠️ GUARDED, AND THIS IS THE WHOLE REASON THE await IS PENNED IN HERE. A
	# whiteout, a warp or `abandon()` can all land while a handler is suspended;
	# `resume_after_native` would then resume a VM that no longer exists, or —
	# worse — a DIFFERENT script that started in the meantime. Checking the
	# pause as well as the instance covers both.
	if vm != null and vm.pause_reason == ScriptVM.Pause.WAIT_NATIVE:
		vm.resume_after_native(result)


## [M27K K-c] The naming screen reported a name for a script-driven rename.
## The VM owns the write — it knows the slot, and it knows that "" means keep.
func on_name_chosen(value: String) -> void:
	if vm != null:
		vm.answer_naming(value)


## [M27G G2] The party screen reported a pick (or a cancel, as -1) while the VM
## was waiting on one. Returns true if the VM claimed it, so the scene's own
## item-use and browse paths know to stand down.
func claim_party_choice(index: int) -> bool:
	if not party_choice_pending:
		return false
	party_choice_pending = false
	if vm != null:
		vm.answer_party_choice(index)
	return true


func expanded_pages() -> PackedStringArray:
	if vm == null:
		return PackedStringArray()
	var out := PackedStringArray()
	for page in vm.pending_pages:
		out.append(vm.buffers.expand(str(page)))
	return out


## Start every movement the script has asked for since the last drain.
##
## Targets are LOCALIDs, not node paths — map data, resolved here rather than in
## the VM, which has no business knowing what a chunk is.
func start_pending_movements() -> void:
	if vm == null or vm.pending_movements.is_empty():
		return
	var queued := vm.pending_movements.duplicate()
	vm.pending_movements.clear()
	for m in queued:
		var target := str(m.get("target", ""))
		# Movement scripts are ordinary labels — the compiler indexes every
		# label uniformly, so `Common_Movement_WalkDown` resolves through the
		# exact same table `goto` uses. No second pipeline.
		var ops: Array = source.ops_for(str(m.get("script", "")))
		if ops.is_empty():
			push_warning("overworld: movement script '%s' is empty or unresolved"
					% str(m.get("script", "")))
			continue
		if is_player_target(target):
			_ow._start_player_movement(target, ops)
			continue
		var e := resolve_movement_entity(target)
		if e == null or not _ow.manager.start_movement_for_entity(e, ops):
			push_warning("overworld: applymovement target '%s' did not resolve" % target)


## [Map scripts] Direction token -> StepResolver.Dir, for `turnobject` — the
## one place a raw `DIR_*` string needs converting; applymovement's own
## FACE_* actions go through WalkAnim.facing_name instead, a separate table.
const DIR_TOKEN := {
	"DIR_SOUTH": StepResolver.Dir.SOUTH,
	"DIR_NORTH": StepResolver.Dir.NORTH,
	"DIR_WEST": StepResolver.Dir.WEST,
	"DIR_EAST": StepResolver.Dir.EAST,
}


## [Map scripts] setobjectxyperm/setobjectmovementtype/turnobject/addobject/
## removeobject — same drain-and-resolve shape as `start_pending_movements`,
## for the same reason: the VM has no business resolving a LOCALID into a
## scene node.
##
## `add`/`remove` both toggle the entity's own `visibility_flag` — every
## corpus entity reached via `addobject`/`removeobject` already carries one
## (the importer wires it uniformly), so this reuses the SAME mechanism
## `entity_visible()` already reads everywhere else rather than adding a
## second, Godot-native show/hide path that nothing else would check.
func apply_pending_object_ops() -> void:
	if vm == null or vm.pending_object_ops.is_empty():
		return
	var queued := vm.pending_object_ops.duplicate()
	vm.pending_object_ops.clear()
	for op: Dictionary in queued:
		var target := str(op.get("target", ""))
		match str(op.get("op", "")):
			"move":
				var e := resolve_movement_entity(target)
				if e != null:
					e.cell = Vector2i(int(op.get("x", 0)), int(op.get("y", 0)))
					# [M27G G9] `setobjectxyperm` — the "perm" is the point, and
					# it was not permanent: the node is freed on the next warp
					# and the baked scene supplies the original cell again.
					_record_override(e, "cell", e.cell)
			"movement_type":
				var e2 := resolve_movement_entity(target) as NPC
				if e2 != null:
					e2.movement_type = str(op.get("value", ""))
					_record_override(e2, "movement_type", e2.movement_type)
			"turn":
				if not DIR_TOKEN.has(str(op.get("dir", ""))):
					continue
				var dir: int = DIR_TOKEN[str(op.get("dir", ""))]
				if is_player_target(target):
					_ow._face_player(dir)
				else:
					var e3 := resolve_movement_entity(target) as NPC
					if e3 != null:
						e3.set_facing(dir)
						_record_override(e3, "facing", dir)
			"add":
				var e4 := resolve_movement_entity(target)
				if e4 != null and e4.visibility_flag != "":
					_ow.flags.flag_clear(e4.visibility_flag)
			"remove":
				var e5 := resolve_movement_entity(target)
				if e5 != null and e5.visibility_flag != "":
					_ow.flags.flag_set(e5.visibility_flag)
			"setmetatile":
				# `x`/`y` are LOCAL to whichever map the running script belongs
				# to. Every corridor caller of a map script is scoped to the
				# player's own CURRENT map by construction (OnLoad/OnTransition
				# fire for the map just entered; a trigger/NPC script runs from
				# the tile the player is standing on) — the same assumption
				# `_map_script_prefix` dispatch already relies on, applied here
				# rather than threading a map name through the VM itself.
				# ⚠️ EXPLICIT TYPES, NOT `:=`. `_ow` is untyped (see the class
				# doc comment), so nothing reached through it carries a return
				# type and inference fails outright — "Cannot infer the type of
				# 'here'". This is the one real cost of the untyped back-
				# reference, and it is a compile error rather than a silent
				# one, which is why it is acceptable.
				var here: String = _ow.manager.chunk_owning(_ow._cell)
				if here == "":
					continue
				var gcell: Vector2i = _ow.manager.origin_of(here) \
						+ Vector2i(int(op.get("x", 0)), int(op.get("y", 0)))
				_ow.manager.set_metatile(gcell, int(op.get("metatile_id", 0)),
						bool(op.get("impassable", false)))


## [M27G G9] Remember a script-driven change so it survives the chunk teardown
## that a warp performs. Keyed by MAP + `local_id`, because the node is exactly
## the thing that dies — see `ObjectEventState`.
func _record_override(e: OverworldEntity, field: String, value: Variant) -> void:
	if e == null or not ("local_id" in e):
		return
	ObjectEventState.record(_ow._owning_map_of(e), str(e.local_id), field, value)


static func is_player_target(target: String) -> bool:
	return target == "LOCALID_PLAYER" or target == "255"


## The non-player half. `VAR_LAST_TALKED` is the entity you are talking to,
## which the VM already carries as `subject` — 15 corridor call sites use it,
## and resolving it any other way would be a second source of truth.
func resolve_movement_entity(target: String) -> OverworldEntity:
	if target == "VAR_LAST_TALKED":
		if vm == null:
			return null
		# ⚠️ [M27G G9] RE-RESOLVE BY NAME IF THE NODE IS GONE. A scripted warp
		# frees the outgoing chunk and everything in it, so a long script that
		# warps and then applies a movement to `VAR_LAST_TALKED` was reaching
		# into a dead instance. Every other target already resolved by
		# `local_id` each time it was used; this one uniquely held a reference.
		if is_instance_valid(vm.subject):
			return vm.subject
		if vm.subject_local_id == "":
			return null
		return _ow.manager.find_entity_by_local_id(vm.subject_local_id)
	return _ow.manager.find_entity_by_local_id(target)


func movement_pending() -> bool:
	if vm == null:
		return false
	var who := vm.pending_wait_target
	if who == "":
		return _ow.manager.movement().is_busy()
	if is_player_target(who):
		return _ow.manager.movement().is_busy(who)
	var e := resolve_movement_entity(who)
	return e != null and _ow.manager.is_entity_moving(e)


func finish() -> void:
	if vm == null:
		return
	var d := vm.describe()
	if vm.pause_reason == ScriptVM.Pause.UNKNOWN_OP:
		# Not an error — 53 opcodes arrive in later stages. Reported so a script
		# that stops early is visibly a coverage gap rather than a silent no-op.
		print("overworld: script '%s' stopped at pc=%d — %s"
				% [d["label"], d["pc"], vm.diagnostic])
	_ow._box.close()
	# [M27G] ⚠️ **THE OTHER HALF OF `fadescreen`, AND WITHOUT IT THAT OPCODE
	# MUST STAY A NO-OP.** In 106 of its 128 corpus uses the fade is never
	# closed by another opcode — source closes it from
	# `CB2_ReturnToFieldContinueScriptPlayMapMusic`, which this project has no
	# equivalent of — so a script can and does end with the screen black.
	# Pairing the fade with the SCRIPT'S OWN LIFETIME rather than with a
	# matching opcode is what makes it safe, and is what that opcode's own
	# comment asked a later session to do.
	#
	# ⚠️ Deliberately not awaited: `finish()` is called from the frame-driven
	# `drive()`, and suspending here would leave the VM half torn down for the
	# length of a fade. The restore is fire-and-forget because nothing after it
	# depends on the screen being back.
	if _ow._fade != null and _ow._fade.color.a > 0.0 and not _ow._warping:
		_ow._fade_to(0.0)
	_ow.script_finished.emit(str(d["label"]), str(d["pause"]), str(vm.diagnostic))
	vm = null
	# [M27G G5] A script can end while a handler is still suspended (an
	# unregistered-handler halt does exactly that). Leaving this set would stop
	# the NEXT script's first `native` from ever starting.
	_native_running = false


func abandon() -> void:
	if vm == null:
		return
	if _ow._box != null:
		_ow._box.close()
	vm = null
	_native_running = false
