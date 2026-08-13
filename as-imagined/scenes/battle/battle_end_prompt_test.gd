extends Node

# ⚠️ **THE ACTION PROMPT MUST NOT REAPPEAR WHILE END-OF-BATTLE TEXT IS STILL
# PLAYING** [Bugfix, live-reported: "Choose move for bulbasaur shows quickly at
# end of battle" and "box asking what will xxx do shows in between transition
# from battle text to post-battle text from trainers"].
#
# Two reports, ONE cause. `_on_battle_ended` plays its text in more than one
# drain — the result ("You win!"), then the trainer's own post-battle line —
# and `_exit_message_mode()` ran between them. Its `_status_label.visible =
# true` put the LAST ACTION PROMPT back on screen, traced verbatim as:
#
#     TRACE >>> _on_battle_ended ENTER
#     TRACE >>> exit_message_mode -> status shown: 'Choose a move for Blaze.'
#     TRACE >>> end-drain DONE. status_vis=true text='You win!'
#
# Which of the two prompts a player sees is just whichever menu they were last
# in — FIGHT gives #4's wording, TOP gives #5's.
#
# ⚠️ **NOTHING OVERWRITES THE STALE TEXT, which is why it is visible rather
# than a single frame.** Mid-battle `_refresh_ui()` follows immediately and
# rewrites the prompt; at BATTLE_END its prompt block is gated on
# MOVE_SELECTION and never runs, so the dead prompt stands until the next drain
# happens to cover it.
#
# ⚠️ **SAMPLED DURING THE SEQUENCE, NOT AFTER IT.** The end state was always
# correct — this defect exists only in between, so a suite that ran
# `_on_battle_ended` to completion and then asserted would pass while the flash
# happened. `[M36]`'s own rule 16 (a restore-based harness cannot see a mid-run
# defect) in a new dress.
#
# ⚠️ **AND THE SAMPLING GUARD IS STILL NOT THE DISCRIMINATING ONE — read its
# own note before trusting it.** A simulator battle has no trainer data, so the
# end sequence plays a single drain and finishes synchronously; the flash needs
# the second drain a real trainer battle plays. The rule is pinned
# deterministically by the mechanism test at the bottom of this file instead.

const SUITE := "battle_end_prompt_test"
const EXPECTED_TOTAL := 9

var _passed := 0
var _total := 0


func _chk(label: String, condition: bool) -> void:
	_total += 1
	if condition:
		_passed += 1
	else:
		print("  FAIL: %s" % label)


func _mount_settled_screen():
	var bs = load("res://scenes/battle/battle_screen_singles.tscn").instantiate()
	add_child(bs)
	for i in range(60):
		await get_tree().create_timer(0.25).timeout
		if not bs._intro_active and not bs._pacing_active and bs._bm != null:
			break
	# The settle loop can win the race against the intro's final beat, leaving
	# the screen still in message mode with the status label hidden. Leaving it
	# explicitly is what `_ready()` itself does once the intro ends.
	bs._exit_message_mode()
	return bs


func _ready() -> void:
	await _test_no_action_prompt_flashes_during_the_end_sequence()
	await _test_exit_message_mode_is_suppressed_while_battle_end_runs()

	print("%s: %d/%d passed" % [SUITE, _passed, _total])
	if _total != EXPECTED_TOTAL:
		print("  FAIL: assertion count %d != expected %d" % [_total, EXPECTED_TOTAL])
		print("FAILED")
	elif _passed != _total:
		print("FAILED")
	get_tree().quit()


func _test_no_action_prompt_flashes_during_the_end_sequence() -> void:
	var bs = await _mount_settled_screen()
	_chk("fixture: the intro settled and the battle is live",
			not bs._intro_active and bs._bm != null)

	# Put the screen in the state a player is actually in when they land the
	# finishing blow: the FIGHT menu, whose prompt is #4's reported wording.
	bs._menu = bs.Menu.FIGHT
	bs._refresh_ui()
	var stale_prompt: String = bs._status_label.text

	# ⚠️ **AND THIS IS THE SHARP EDGE OF THE WHOLE BUG.** FIGHT SETS that text
	# and then deliberately HIDES it — `_layout_action_menu_for` does
	# `_status_label.visible = not is_fight`, because the two-box move grid
	# replaces the prompt rather than sitting under it. So "Choose a move for X"
	# is a string that is never supposed to be on screen at all.
	#
	# `_exit_message_mode()` restores visibility UNCONDITIONALLY, so it does not
	# merely leave a stale prompt up — it reveals one that no menu state ever
	# displays. That is why the flash reads as an unrelated box appearing out of
	# nowhere rather than as the previous menu lingering.
	_chk("fixture: FIGHT has set the move prompt AND is keeping it hidden",
			stale_prompt.begins_with("Choose a move for") and not bs._status_label.visible)

	# ⚠️ **DRIVEN AS A REAL BATTLE END, NOT BY CALLING `_on_battle_ended`
	# DIRECTLY — and the first draft of this test did the latter and was
	# VACUOUS.** With no trainer data the fixture plays only ONE drain, and the
	# window between that drain ending and the flag clearing contains no await
	# at all, so a sampler can never land in it. Injection is what exposed that:
	# removing the fix failed the mechanism test below and left THIS one green.
	#
	# The reported flash needs two things this path supplies and a direct call
	# does not — a second drain to flash in front of, and `_dispatch_move`'s own
	# trailing `_refresh_ui()` resuming inside the sequence.
	for m in bs._opp_party.members:
		m.current_hp = 1

	var flashed := false
	var saw_end_text := false
	var reached_end := false

	for turn in range(12):
		if bs._winner_side != -1:
			reached_end = true
			break
		bs._top_fight_btn.pressed.emit()
		await get_tree().create_timer(0.05).timeout
		var pressed := false
		for btn in bs._move_buttons:
			if btn.visible and not btn.disabled:
				btn.pressed.emit()
				pressed = true
				break
		if not pressed:
			break
		# Sample continuously across the whole paced sequence. "Choose a move
		# for X" is never legitimately visible in ANY menu state — FIGHT hides
		# it and every other state overwrites it — so a single sighting is the
		# defect.
		for i in range(400):
			await get_tree().create_timer(0.05).timeout
			if bs._status_label.visible and bs._status_label.text == stale_prompt:
				flashed = true
			if bs._message_label.visible and bs._message_label.text != "":
				saw_end_text = true
			if not bs._pacing_active and not bs._battle_end_active:
				break

	# The sampler has to be able to observe SOMETHING, or "never flashed" is
	# just "never looked" — the vacuity that the first draft of this test had.
	_chk("sampler: real battle text played during the run", saw_end_text)
	_chk("sampler: the battle actually reached its end", reached_end)

	# ⚠️ **THIS ASSERTION CANNOT EXPRESS ITS OWN NEGATION IN THIS FIXTURE, AND
	# SAYS SO RATHER THAN PRETENDING OTHERWISE.** Injection confirmed it stays
	# GREEN with the fix removed. The reason is the fixture, not the rule: a
	# simulator battle carries no trainer data, so `_show_trainer_battle_end`
	# returns early and only ONE drain plays. Every remaining step then runs
	# synchronously — exit, refresh, blank — so no sampler can land between
	# them. The reported flash needs the SECOND drain a real trainer battle
	# plays, which is also exactly why both reports came from the RPG side.
	#
	# Kept because it is a real invariant and would catch a future regression on
	# a fixture that does have a trainer; the DISCRIMINATING guard for this fix
	# is `_test_exit_message_mode_is_suppressed_while_battle_end_runs` below,
	# which injection does fail. See `[M36]` rule 15.
	_chk("the hidden FIGHT prompt is never revealed during the end sequence",
			not flashed)

	_chk("once the sequence is over, message mode has been left for real",
			not bs._message_label.visible)
	_chk("...and the dead action prompt is blanked rather than left standing",
			bs._status_label.text == "")

	bs.queue_free()


# The mechanism on its own, deterministic and instant — the test above needs a
# real battle and real wall clock, so this pins the rule directly.
func _test_exit_message_mode_is_suppressed_while_battle_end_runs() -> void:
	var bs = load("res://scenes/battle/battle_screen_singles.tscn").instantiate()
	add_child(bs)
	bs._intro_active = false

	bs._enter_message_mode()
	bs._battle_end_active = true
	bs._exit_message_mode()
	_chk("_exit_message_mode is a no-op while the end sequence owns the screen",
			bs._message_label.visible and not bs._status_label.visible)

	# The discriminator: the same call with the flag down must genuinely exit,
	# or the assertion above would pass against a function that never works.
	bs._battle_end_active = false
	bs._exit_message_mode()
	_chk("...and exits normally once the flag is down",
			not bs._message_label.visible and bs._status_label.visible)

	bs.queue_free()
