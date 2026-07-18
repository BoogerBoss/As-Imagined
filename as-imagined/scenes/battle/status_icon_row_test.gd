extends Node

# [M23.11 Phase 4b] Unit test for BattleScreen._status_icon_row() -- the
# pure mapping from BattlePokemon.STATUS_* to a status-icon-sheet row (or
# -1 for "no icon"). Static function, called directly with no scene
# instantiation needed, matching this project's established convention
# for testing a screen's own static helpers (see e.g. ai_test.gd's use of
# BattleScreen.build_fixture_player_party()).
#
# Covers: every real status value maps to its own distinct row, POISON and
# TOXIC deliberately share one row (confirmed intentional, not a bug --
# the source sprite sheet has no separate "badly poisoned" badge), NONE
# maps to -1 (hidden), and a direct transition check (status changing from
# one real condition to NONE and back) to confirm the mapping has no
# hidden state/memory between calls -- it's a pure function of its input.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_each_status_maps_to_its_own_row()
	_test_toxic_shares_poison_row()
	_test_none_maps_to_hidden()
	_test_transition_has_no_hidden_state()

	var total := _pass + _fail
	print("status_icon_row_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_each_status_maps_to_its_own_row() -> void:
	var expected := {
		BattlePokemon.STATUS_POISON: 0,
		BattlePokemon.STATUS_PARALYSIS: 1,
		BattlePokemon.STATUS_SLEEP: 2,
		BattlePokemon.STATUS_FREEZE: 3,
		BattlePokemon.STATUS_BURN: 4,
	}
	for status in expected:
		_chk("status %d maps to row %d" % [status, expected[status]],
				BattleScreen._status_icon_row(status) == expected[status])

	# Every expected row is distinct from every other (no accidental
	# collision between two different real statuses).
	var seen: Dictionary = {}
	for status in expected:
		var row: int = expected[status]
		_chk("row %d for status %d is not reused by a different status" % [row, status],
				not seen.has(row))
		seen[row] = true


func _test_toxic_shares_poison_row() -> void:
	var poison_row := BattleScreen._status_icon_row(BattlePokemon.STATUS_POISON)
	var toxic_row := BattleScreen._status_icon_row(BattlePokemon.STATUS_TOXIC)
	_chk("TOXIC deliberately shares POISON's own row (no separate badge exists)",
			poison_row == toxic_row and poison_row == 0)


func _test_none_maps_to_hidden() -> void:
	_chk("STATUS_NONE maps to -1 (icon hidden)",
			BattleScreen._status_icon_row(BattlePokemon.STATUS_NONE) == -1)


func _test_transition_has_no_hidden_state() -> void:
	# Pure function -- calling it repeatedly with different inputs in
	# sequence must never leak state between calls.
	var first := BattleScreen._status_icon_row(BattlePokemon.STATUS_BURN)
	var mid := BattleScreen._status_icon_row(BattlePokemon.STATUS_NONE)
	var last := BattleScreen._status_icon_row(BattlePokemon.STATUS_BURN)
	_chk("BURN -> NONE -> BURN transition is stateless (same result both times)",
			first == last and first == 4)
	_chk("the NONE call in between correctly reported hidden", mid == -1)
