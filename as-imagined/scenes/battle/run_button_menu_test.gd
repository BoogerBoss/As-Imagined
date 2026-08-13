extends Node

# ⚠️ **HARD-LOCK GUARD. THIS SUITE EXISTS BECAUSE A FIX SHIPPED HALF-DONE AND
# BROKE THE GAME WORSE THAN THE BUG IT CLOSED** [Bugfix, live-reported: "hard
# lock after trying to run from rival battle"].
#
# The sequence that produced it is worth keeping, because it is a shape rather
# than an incident. `_on_run_pressed` wrote its refusal line with `_log()` and
# returned, so the line never appeared and Run looked like a dead button. The
# obvious fix — `await _run_message_pacing()` so the line actually plays — is
# correct on its own and catastrophic on its own:
#
#   `_enter_message_mode()` hides BOTH `_top_action_hbox` and
#   `_fight_action_hbox`. `_exit_message_mode()` deliberately does NOT put them
#   back; it restores only the panel skin and the grid containers, because it
#   is documented as handing off to `_refresh_ui()` for whichever menu is
#   needed next. `_layout_action_menu_for()` is the only thing that sets those
#   two visible, and `_refresh_ui()` is the only route to it.
#
# So a drain that hands control BACK to the player leaves a panel that looks
# perfectly normal and holds no buttons, with `_pacing_active` already false so
# input is accepted and there is nothing to accept it with. Measured before the
# fix: `top=false fight=false grid=true`, zero action buttons visible in tree.
#
# ⚠️ **WHY THIS IS A SEPARATE SCENE AND NOT A CASE IN `message_pacing_test`.**
# That suite drives bare `BattleScreenShared.new()` instances, and this defect
# is INVISIBLE off-tree: `_run_message_pacing()` bypasses to a synchronous
# clear when `not is_inside_tree()`, so message mode is never entered and the
# rows are never hidden. Proving it needs a real mounted screen and a real
# settled intro, which costs wall clock the unit suites should not pay.
#
# ⚠️ **AND IT DRIVES `_on_run_pressed()` ITSELF, NOT THE DRAIN.** Asserting on
# `_run_message_pacing()` + `_refresh_ui()` directly would pass while the
# caller forgot the rebuild — the exact "guard on the callee, blind to the call
# site" trap `[M27H H4]` already cost this project once.

const SUITE := "run_button_menu_test"
const EXPECTED_TOTAL := 8

var _passed := 0
var _total := 0


func _chk(label: String, condition: bool) -> void:
	_total += 1
	if condition:
		_passed += 1
	else:
		print("  FAIL: %s" % label)


# Every action button the player could possibly press from the settled TOP
# menu. "Visible in tree" rather than `.visible`, because the defect hides an
# ANCESTOR (`_top_action_hbox`) while each button's own flag stays true.
func _any_action_button_reachable(bs) -> bool:
	for btn in [bs._top_fight_btn, bs._top_item_btn, bs._top_switch_btn, bs._top_run_btn]:
		if btn != null and btn.is_visible_in_tree():
			return true
	return false


# Mounts a real battle screen and waits for its intro to finish. Bounded, and
# the bound is generous rather than tuned: headless frames pass instantly while
# the intro's own beats wait on `create_timer`, so this is wall clock.
func _mount_settled_screen():
	var bs = load("res://scenes/battle/battle_screen_singles.tscn").instantiate()
	add_child(bs)
	for i in range(60):
		await get_tree().create_timer(0.25).timeout
		if not bs._intro_active and not bs._pacing_active and bs._bm != null:
			break
	return bs


func _ready() -> void:
	await _test_run_in_a_trainer_battle_leaves_the_player_a_menu()
	_test_exit_message_mode_does_not_restore_the_action_rows()

	print("%s: %d/%d passed" % [SUITE, _passed, _total])
	# Z.99-style balance check: a test function that aborts partway (a runtime
	# error in GDScript kills the rest of the function silently) drops its
	# remaining assertions, and a bare pass count cannot see that.
	if _total != EXPECTED_TOTAL:
		print("  FAIL: assertion count %d != expected %d" % [_total, EXPECTED_TOTAL])
		print("FAILED")
	elif _passed != _total:
		print("FAILED")
	get_tree().quit()


func _test_run_in_a_trainer_battle_leaves_the_player_a_menu() -> void:
	var bs = await _mount_settled_screen()

	# The fixture has to be able to FAIL before it can prove anything: if the
	# screen never reached a usable TOP menu, every assertion below would pass
	# vacuously on a screen that had no buttons for unrelated reasons.
	_chk("fixture: the intro settled and the battle is live",
			not bs._intro_active and bs._bm != null)
	_chk("fixture: a settled TOP menu offers the player a reachable button",
			_any_action_button_reachable(bs))

	# `overlay_mode` gates the whole overworld path — with it false, Run is the
	# simulator's own scene swap and never reaches the refusal at all.
	# `_bm != null and _bm.is_wild_battle` falling false is what then selects
	# the trainer branch over the flee branch.
	bs.overlay_mode = true
	bs._bm.is_wild_battle = false

	await bs._on_run_pressed()

	# THE GUARD. Without `_refresh_ui()` after the drain this is false and the
	# game is unrecoverable: verified by injection, which reports
	# `top=false fight=false` and no reachable button.
	_chk("after refusing a trainer-battle escape, the player still has a button to press",
			_any_action_button_reachable(bs))
	_chk("...and specifically the TOP action row is back",
			bs._top_action_hbox.visible)
	# The drain must also have ENDED — a screen still in message mode is a
	# different failure that would satisfy the row check once mode exits.
	_chk("the message box has handed the panel back to the menu",
			not bs._message_label.visible and not bs._pacing_active)

	bs.queue_free()


# Pins the seam the bug lives on, so a later session cannot "simplify" it away.
# ⚠️ This is deliberately asserting that `_exit_message_mode()` LEAVES THE ROWS
# HIDDEN. That is not a defect to fix here — every ordinary drain is followed
# by `_refresh_ui()`, which needs to decide TOP vs FIGHT rather than blindly
# restore whichever was up before. Making this function restore them would mask
# the caller-side omission instead of fixing it, and would flash the wrong menu.
func _test_exit_message_mode_does_not_restore_the_action_rows() -> void:
	var bs = load("res://scenes/battle/battle_screen_singles.tscn").instantiate()
	add_child(bs)
	# `@onready` node references bind on tree entry, so this is the earliest
	# point the two rows can be touched at all.
	bs._intro_active = false

	bs._enter_message_mode()
	_chk("entering message mode hides both action rows",
			not bs._top_action_hbox.visible and not bs._fight_action_hbox.visible)

	bs._exit_message_mode()
	_chk("leaving message mode restores the grid containers",
			bs._new_button_grid.visible and bs._new_button_area.visible)
	_chk("but NOT the action rows — only _refresh_ui() decides which menu returns",
			not bs._top_action_hbox.visible and not bs._fight_action_hbox.visible)

	bs.queue_free()
