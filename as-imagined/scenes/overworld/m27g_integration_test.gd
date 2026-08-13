extends Node

## [M27G] Trigger -> text -> battle -> resume, end to end through the real scene.
##
## ⚠️ **NOTHING ELSE IN THE 22 SUITES COVERS THIS SEAM.** Each piece is tested
## in isolation — `m27a` walks and steps, `m27f` drives a bare VM, `m27d` proved
## the trainer round trip — but the FULL chain from a coord_event firing to the
## script resuming after a battle and running its post-battle branch has only
## ever been verified by hand. That is exactly the shape of thing that breaks
## silently, because every part still passes its own test.
##
## The subject is Route 22's early rival, chosen because it exercises every seam
## M27G touched in one script:
##
##   step onto (33,5)            check_step_trigger + FlagStore.trigger_armed
##   lockall/setvar/goto         control flow
##   addobject                   entity spawn via visibility_flag
##   call_if_eq x3               real branching
##   applymovement/waitmovement  async queue + the blocking half
##   message + waitbuttonpress   TEXT, advanced by REAL KEY PRESSES
##   call_if_eq VAR_STARTER_MON  branches on which starter was chosen
##     trainerbattle_earlyrival  the BATTLE
##   message PostBattle          the script RESUMED
##   removeobject / setvar       state written on the way out
##
## ⚠️ **`trainerbattle_earlyrival` IS THE VARIANT MOST LIKELY TO BE SILENTLY
## WRONG.** Its shared handler (`EventScript_DoNoIntroTrainerBattle`) is
## `dotrainerbattle` then an UNCONDITIONAL `gotopostbattlescript`, so a WIN falls
## through to the next opcode in the CALLING script — never the
## `gotobeatenscript`-ends-the-script rule the single/double/rematch family uses.
## `ScriptVM.pending_battle_always_continues` carries that distinction, and D.06
## below is the only assertion anywhere that it holds end to end.
##
## ⚠️ **TWO THINGS ARE FAKED, AND THEY ARE STATED RATHER THAN HIDDEN.**
##   * The party. `_mount_battle` refuses an empty one (it would black-screen),
##     so a debug team is seeded. The battle's own correctness is 22 other
##     suites' job.
##   * The battle round trip. ⚠️ **THE REAL SCREEN IS DELIBERATELY NOT MOUNTED,
##     AND THE REASON IS A TRAP WORTH KNOWING**: `run_overworld_tests.sh` passes
##     `--autoplay`, and `battle_screen_shared` reads that flag and SELF-PLAYS,
##     printing its own `battle_screen_autoplay: 1/1 passed` and calling
##     `get_tree().quit()`. Mounting it here ends the whole run mid-suite — the
##     summary line the runner greps is then the battle screen's, not this
##     suite's, so the run reports PASS having never finished. Found the hard
##     way. Instead the round trip is simulated with the same two calls the real
##     return path makes (`_in_battle` as the re-entrancy guard, then
##     `resume_after_battle`), which is the seam under test. The overlay mount
##     itself is `[M27D D5]`'s.

const EXPECTED_TOTAL := 21

## Route 22's early-rival trigger, in the map's own LOCAL cells.
const TRIGGER_CELL := Vector2i(33, 5)

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


## Bounded wait. Generous enough that it can only fire on a genuine stall.
func _until(cond: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return false


## ⚠️ **THE DRIVER IS PUMPED BY HAND, NOT BY `_process`, AND THE REASON IS A
## RACE THAT CANNOT BE WON FROM A POLLING LOOP.** `_drive_script` runs
## `while vm.step()` and THEN matches the pause, so in ONE call the VM can go
## from resuming to `WAIT_BATTLE` **and mount the battle screen**. There is no
## frame in which `WAIT_BATTLE` exists un-mounted for a test to notice.
##
## And the mount is fatal here: `run_overworld_tests.sh` passes `--autoplay`,
## `battle_screen_shared` reads that flag in `_ready`, self-plays, prints its
## own `battle_screen_autoplay: 1/1 passed` and calls `get_tree().quit()`. The
## run ends mid-suite, and the summary line the runner greps is the battle
## screen's — so it reports PASS having never finished. Found the hard way.
##
## Turning `_process` off and calling `_drive_script()` per step is what makes
## the WAIT_BATTLE moment observable. The driver's own logic is unchanged and
## fully exercised; only the thing calling it moves. Keys are still real —
## pressed, then pumped in the same frame, which is exactly what `_process`
## does.
## ⚠️ **TICKS MOVEMENT TOO, AND FORGETTING THAT STALLED THE FIRST CUT DEAD.**
## Turning `_process` off stops more than the driver: it also stops
## `manager.tick_movement()`, which is what `waitmovement` blocks on. The rival
## walks up before the intro line, so the script parked on WAIT_MOVEMENT
## forever and every assertion from C onward failed. Pumping the driver by hand
## means pumping what the driver WAITS ON by hand as well.
const _FRAME := 1.0 / 60.0


func _pump(ow) -> void:
	ow.manager.tick_movement(_FRAME)
	ow._drive_script()
	await get_tree().process_frame


## Press A and pump, the way a player does one page.
func _advance_page(ow) -> void:
	# ⚠️ **DRIVE IMMEDIATELY AFTER THE PRESS, BEFORE AWAITING A FRAME.**
	# `Input.is_action_just_pressed` is true from the moment `action_press`
	# lands until the next input flush — so awaiting first and pumping after
	# means the driver's WAIT_BUTTON branch sees a press that has already gone
	# stale, and the box never advances. The first cut did exactly that and
	# parked forever on page 0 of 5.
	Input.action_press("ui_accept")
	ow.manager.tick_movement(_FRAME)
	ow._drive_script()
	await get_tree().process_frame
	Input.action_release("ui_accept")
	ow.manager.tick_movement(_FRAME)
	ow._drive_script()
	await get_tree().process_frame


## Drain the box and STOP THE INSTANT IT CLOSES.
##
## ⚠️ **IT MUST NOT PUMP ONCE MORE AFTER THE LAST PAGE**, and the first cut did.
## Closing the final page calls `vm.resume()`, leaving the VM at `NONE`; one
## further `_drive_script()` then steps straight into `trainerbattle` and mounts
## the battle screen — the very thing this suite has to observe un-mounted. The
## `break` before the trailing frame is the whole difference.
func _drain_box(ow) -> void:
	var guard := 0
	while ow._box != null and ow._box.is_open and guard < 80:
		Input.action_press("ui_accept")
		ow.manager.tick_movement(_FRAME)
		ow._drive_script()
		Input.action_release("ui_accept")
		if ow._box == null or not ow._box.is_open:
			return
		await get_tree().process_frame
		guard += 1


## Pump until `cond` holds or we give up. Returns whether it held.
func _pump_until(ow, cond: Callable, steps: int = 400) -> bool:
	for _i in range(steps):
		if cond.call():
			return true
		if ow._box != null and ow._box.is_open:
			await _advance_page(ow)
		else:
			await _pump(ow)
	return cond.call()


func _ready() -> void:
	await _test_trigger_to_battle_and_back()
	await _test_yes_no_waits_for_question_to_finish_typing()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27g_integration_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


func _test_trigger_to_battle_and_back() -> void:
	OverworldSession.reset()
	# ⚠️ Seeded BEFORE the scene boots. `_mount_battle` refuses to start with no
	# usable party — an unrecoverable black screen, guarded since [M27E].
	OverworldSession.party = OverworldParty.build_debug_player_party()

	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	ow.start_map = "Route22_Frlg"
	ow.start_cell = Vector2i(-1, -1)
	add_child(ow)
	await get_tree().process_frame
	await get_tree().process_frame

	var man: MapManager = ow.manager
	var origin: Vector2i = man.origin_of("Route22_Frlg")
	var target: Vector2i = origin + TRIGGER_CELL

	# --- A. the gate ---------------------------------------------------------
	# ⚠️ The trigger is GATED on VAR_MAP_SCENE_ROUTE22 == 1. Standing on the cell
	# with the var unset must do NOTHING — if it fired regardless, the gate would
	# be decorative and every later-scene trigger in the region would misfire.
	ow._cell = target
	ow.flags.var_set("VAR_MAP_SCENE_ROUTE22", 0)
	_chk("A.01 an unarmed trigger does not fire", not ow.check_step_trigger())
	_chk("A.02 and no script is running", ow._vm == null)

	ow.flags.var_set("VAR_MAP_SCENE_ROUTE22", 1)
	# The rival's own starter branch — 2 is Squirtle, the Charmander-player case.
	ow.flags.var_set("VAR_STARTER_MON", 2)
	var started: bool = ow.check_step_trigger()
	_chk("A.03 an ARMED trigger on the same cell fires", started)
	_chk("A.04 and a script is now running", ow._vm != null)

	# ⚠️ From here the driver is pumped BY HAND — see `_pump`'s own header for
	# why `_process` cannot be used past the point the script reaches a battle.
	ow.set_process(false)

	# --- B. the rival appears and walks over ---------------------------------
	var rival_seen := await _pump_until(ow, func():
		var e := man.find_entity_by_local_id("LOCALID_ROUTE22_RIVAL")
		return e != null and ow.flags.entity_visible(e))
	_chk("B.01 addobject makes the rival present", rival_seen)
	# ⚠️ (33,5) is the TOP trigger, and the three set DIFFERENT values —
	# Top 0 / Mid 1 / Bottom 2 — which is what selects the rival's approach
	# path. An earlier cut of this assertion expected 1 and failed, correctly:
	# guessing which of three same-shaped triggers a cell carries is exactly
	# what an integration test is for.
	_chk("B.02 the TOP trigger's own branch var was written (0, not Mid's 1)",
			ow.flags.var_get("VAR_TEMP_1") == 0)

	# --- C. text, advanced by REAL key presses -------------------------------
	var box_open := await _pump_until(ow, func():
		return ow._box != null and ow._box.is_open)
	_chk("C.01 the intro message reaches the box", box_open)
	# ⚠️ Read through the VM's own expansion path, not the raw corpus — this is
	# what a player actually sees.
	var pages: PackedStringArray = ow._expanded_pages()
	_chk("C.02 with real text in it, not a blank box",
			pages.size() > 0 and str(pages[0]).strip_edges() != "")

	# --- D. the battle -------------------------------------------------------
	#
	# ⚠️ **THE VM IS STEPPED DIRECTLY ACROSS THIS ONE TRANSITION, AND ONLY THIS
	# ONE.** `_drive_script` runs `while vm.step()` at the top and matches the
	# pause at the bottom, so the call that steps into `trainerbattle` also
	# MOUNTS the battle — there is no instant in between for a test to observe,
	# no matter how finely it pumps. And the mount is fatal under `--autoplay`
	# (see `_pump`'s header). Stepping the VM by hand here reaches WAIT_BATTLE
	# without the driver's match block running, which is the only way to assert
	# on the parked state at all. The driver takes over again immediately after.
	await _drain_box(ow)
	var guard := 0
	while ow._vm != null and ow._vm.step() and guard < 500:
		guard += 1
	var at_battle: bool = ow._vm != null \
			and ow._vm.pause_reason == ScriptVM.Pause.WAIT_BATTLE
	_chk("D.01 the script reaches a battle", at_battle)
	var key: String = ow._vm.pending_trainer_key if ow._vm != null else ""
	_chk("D.02 against the rival the starter branch selected",
			key.contains("RIVAL_ROUTE22_EARLY"))
	# ⚠️ `trainerbattle_earlyrival` passes NO intro text — its shared handler is
	# the no-intro one — so the pages are empty here. A non-empty list would mean
	# the wrong trainerbattle variant was dispatched.
	_chk("D.03 with no intro speech, as the earlyrival variant specifies",
			ow._vm != null and ow._vm.pending_pages.is_empty())

	# The round trip, using the same call the real return path makes.
	if ow._vm != null:
		ow.flags.set_trainer_defeated(key)
		ow._vm.resume_after_battle(true)
	_chk("D.04 the trainer is recorded as beaten", ow.flags.trainer_defeated(key))

	# ⚠️ THE ASSERTION THIS WHOLE SUITE EXISTS FOR. `trainerbattle_earlyrival`
	# falls through to the NEXT OPCODE on a win, unlike the single/double/rematch
	# family, which ends the script unless given a continuation label. If
	# `pending_battle_always_continues` were wrong the script would simply stop
	# here — silently, with the player locked and the rival still on the map.
	var resumed := await _pump_until(ow, func():
		return ow._box != null and ow._box.is_open)
	_chk("D.05 the script RESUMES after the battle and keeps running", resumed)

	# --- E. the tail: post-battle text, cleanup, state ------------------------
	var finished := await _pump_until(ow, func(): return ow._vm == null)
	_chk("E.01 the script runs to completion", finished)
	_chk("E.02 removeobject takes the rival back off the map",
			not ow.flags.entity_visible(man.find_entity_by_local_id("LOCALID_ROUTE22_RIVAL")))
	# ⚠️ The scene var advancing to 2 is what DISARMS the trigger. Without it the
	# same cutscene fires again on the next step — the self-disarming shape every
	# coord_event in the region relies on.
	_chk("E.03 the scene var advances, disarming the trigger",
			ow.flags.var_get("VAR_MAP_SCENE_ROUTE22") == 2)
	_chk("E.04 and standing on the cell again does nothing",
			not ow.check_step_trigger())
	_chk("E.05 the player is released, not left locked", ow._vm == null)

	ow._abandon_script()
	for _i in range(45):
		await get_tree().process_frame
	ow.queue_free()


## --- F. the yes/no cursor must not beat its own question onto screen -----
##
## [Bugfix, live-reported: "the dialog prompt isn't shown, it skips right to
## yes/no"] `Std_MsgboxYesNo` compiles to `message` / `waitmessage` /
## `yesnobox` -- no `waitbuttonpress` -- so nothing else in that chain ever
## blocked the yes/no cursor from opening before the question's own text had
## even started typing (see `ScriptDriver`'s `WAIT_YES_NO` branch for the
## fix, and its own doc comment for the full mechanism). Every OTHER yes/no
## suite in this project drives a bare `ScriptVM` and treats `WAIT_MESSAGE`
## as instantly resumable with no real `MessageBox`/`YesNoBox` behind it --
## which is exactly the shape that let this ship unnoticed. Only a REAL
## driven pair, which only this file's own real-scene machinery provides,
## can see it.
func _test_yes_no_waits_for_question_to_finish_typing() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	ow.start_map = "Route22_Frlg"
	ow.start_cell = Vector2i(-1, -1)
	add_child(ow)
	await get_tree().process_frame
	await get_tree().process_frame
	ow.set_process(false)

	# A real, long-enough question -- at TextTyper's own 0.02s/char, ~1s to
	# type fully, giving many frames in which a premature cursor would show.
	var question := "Do you want to give a nickname to this Pokemon?"
	var source := ScriptVM.ScriptSource.new()
	source.ops_by_label = {"F_Q": [
		{"op": "message", "args": ["F_QuestionText"]},
		{"op": "waitmessage", "args": []},
		{"op": "yesnobox", "args": []},
		{"op": "end", "args": []},
	]}
	source.texts = {"F_QuestionText": [question]}
	var vm := ScriptVM.new(source, ow.flags)
	vm.start("F_Q")
	ow._vm = vm

	var saw_yes_no_open := false
	var saw_yes_no_while_typing := false
	var guard := 0
	while ow._vm != null and guard < 300:
		ow._drive_script()
		if ow._yes_no != null and ow._yes_no.is_open:
			saw_yes_no_open = true
			if ow._box != null and ow._box.is_typing:
				saw_yes_no_while_typing = true
			break
		await get_tree().process_frame
		guard += 1

	_chk("F.01 the yes/no cursor does eventually open", saw_yes_no_open)
	_chk("F.02 -- and NEVER while the question is still typing (the reported bug)",
			not saw_yes_no_while_typing)
	_chk("F.03 the question's real text reached the box before the cursor did",
			ow._box != null and ow._box.page_count > 0
			and ow._expanded_pages()[0] == question)

	# Let it finish cleanly rather than leaving a parked VM behind.
	if ow._vm != null and ow._vm.pause_reason == ScriptVM.Pause.WAIT_YES_NO:
		ow._vm.answer_yes_no(true)
		var drain := 0
		while ow._vm != null and drain < 50:
			ow._drive_script()
			await get_tree().process_frame
			drain += 1

	ow._abandon_script()
	for _i in range(10):
		await get_tree().process_frame
	ow.queue_free()
