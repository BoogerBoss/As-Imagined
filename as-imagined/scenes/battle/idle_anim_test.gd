extends Node

# [M23.11 Phase 4c] Unit test for BattleScreen._next_anim_frame() -- the
# pure frame-toggle logic driving idle-bob animation. Static, called
# directly with no scene/Timer instantiation needed, matching this
# project's established convention for testing a screen's own static
# helpers (see status_icon_row_test.gd's own precedent from Phase 4b).
#
# Covers: alternation direction (0->1, 1->0), a multi-tick sequence
# (asserting on frame INDEX after simulated time advance, not visual
# appearance -- per this phase's own explicit instruction), and the
# fainted-freezes-the-current-frame behavior from both starting frames.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_basic_alternation()
	_test_multi_tick_sequence()
	_test_fainted_freezes_current_frame()

	var total := _pass + _fail
	print("idle_anim_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_basic_alternation() -> void:
	_chk("frame 0, not fainted -> advances to frame 1",
			BattleScreen._next_anim_frame(0, false) == 1)
	_chk("frame 1, not fainted -> advances back to frame 0",
			BattleScreen._next_anim_frame(1, false) == 0)


func _test_multi_tick_sequence() -> void:
	# Simulates 5 real timer ticks in sequence -- asserts on the resulting
	# frame INDEX at each step, not on any rendered/visual output.
	var frame := 0
	var expected := [1, 0, 1, 0, 1]
	for i in range(expected.size()):
		frame = BattleScreen._next_anim_frame(frame, false)
		_chk("tick %d: frame is %d" % [i + 1, expected[i]], frame == expected[i])


func _test_fainted_freezes_current_frame() -> void:
	_chk("frame 0, fainted -> stays on frame 0 (does not advance)",
			BattleScreen._next_anim_frame(0, true) == 0)
	_chk("frame 1, fainted -> stays on frame 1 (does not advance)",
			BattleScreen._next_anim_frame(1, true) == 1)

	# A fainted mon that was mid-bob when it fainted should freeze exactly
	# where it was, not reset or continue -- confirmed via a short
	# sequence: alternate twice while alive, then faint and confirm no
	# further movement across several more simulated ticks.
	var frame := 0
	frame = BattleScreen._next_anim_frame(frame, false)  # -> 1
	frame = BattleScreen._next_anim_frame(frame, false)  # -> 0
	var frame_at_faint := frame
	for i in range(3):
		frame = BattleScreen._next_anim_frame(frame, true)
	_chk("frozen frame after fainting mid-sequence matches the frame at the moment of fainting",
			frame == frame_at_faint)
