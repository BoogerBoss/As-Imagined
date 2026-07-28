extends Node

# [M26B6-1] Asset smoke test for the ability-activation popup panel.
#
# The panel was already present before M26B6 (M23.11 Phase 1's chrome pull) and
# is pixel-identical to the reference, but that pass was a plain filtered copy
# and left palette index 0 UNTAGGED while index 0 is the transparency key --
# all four corners, 1202/4096 pixels, colour (1,177,91) green. Rendered as-is
# the popup sits inside an opaque green box: the same defect [M26B3-6a] hit
# with the ball sheets.
#
# B.01 is the assertion that matters. B.02 is its non-vacuity partner: a fully
# transparent panel would pass a corner check while containing no art.

const POPUP := "res://assets/sprites/battle_ui/interface/ability_pop_up.png"
const EXPECTED_SIZE := Vector2i(128, 32)

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_loads_at_expected_size()
	_test_index_zero_is_transparent()
	_test_real_art_survives()

	var total := _pass + _fail
	print("m26_b6_1_popup_asset_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _tex() -> Texture2D:
	return load(POPUP) as Texture2D


func _test_loads_at_expected_size() -> void:
	var t := _tex()
	_chk("A.01 the popup panel loads as a Texture2D", t != null)
	if t == null:
		return
	# 128x32 is two 64x32 OAM halves in source; reproduced as one node here.
	_chk("A.02 it is %dx%d" % [EXPECTED_SIZE.x, EXPECTED_SIZE.y],
			Vector2i(t.get_size()) == EXPECTED_SIZE)


func _test_index_zero_is_transparent() -> void:
	var t := _tex()
	if t == null:
		return
	var img: Image = t.get_image()
	var w := img.get_width()
	var h := img.get_height()
	var corners := [
		img.get_pixel(0, 0), img.get_pixel(w - 1, 0),
		img.get_pixel(0, h - 1), img.get_pixel(w - 1, h - 1),
	]
	var all_clear := true
	for c: Color in corners:
		if c.a != 0.0:
			all_clear = false
	_chk("B.01 index 0 is tagged transparent (all four corners are clear)",
			all_clear)


func _test_real_art_survives() -> void:
	var t := _tex()
	if t == null:
		return
	var img: Image = t.get_image()
	var opaque := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.0:
				opaque += 1
	# ~70% of the panel is real art; a fully-keyed image would pass B.01 while
	# containing nothing to draw.
	_chk("B.02 the panel still contains real opaque art (%d px)" % opaque,
			opaque > 2000)
