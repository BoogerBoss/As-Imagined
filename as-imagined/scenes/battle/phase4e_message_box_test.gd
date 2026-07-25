extends Node

# [M23.11 Phase 4e, narrowed by M26b] Test suite for the reusable color-
# keying utility (`_color_keyed_texture`/`_is_message_box_key_color`) that
# originally backed the Dialogue-Manager-balloon-based message box built in
# this phase. [M26b] retired that message box outright (VBox/LogLabel and
# `_setup_message_box()` no longer exist — see battle_screen.gd's own
# former `_log_label` doc comment) as part of merging the always-visible
# log into the F3-only debug/log panel, so this file's old Section D
# (`_setup_message_box()` itself) and Section E (DialogueLabel's own
# generic append behavior, unrelated to anything this project's UI still
# uses) were removed rather than left asserting dead functionality. The
# color-keying functions themselves are NOT dead — ItemSelectScreen/
# SwitchSelectScreen both still call `_color_keyed_texture` directly for
# their own real window art (see m25h1_bottom_region_test.gd's own
# `_test_color_keyed_texture_generalizes_to_a_custom_key_color` for a
# second, independent regression guard on the same function) — so Sections
# A-C, which only ever exercised those reusable pieces, are kept unchanged.
#
# [Deliberately NOT tested here] Instantiating battle_screen.tscn — same
# established precedent as phase4d_doubles_visual_test.gd/
# phase4f_targeting_test.gd (count_assertions.sh's own unconditional
# --autoplay flag, battle_screen.gd's own process-wide autoplay check).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_key_color_detection()
	_test_color_keyed_texture_synthetic()
	_test_color_keyed_texture_real_asset()

	var total := _pass + _fail
	print("phase4e_message_box_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── A. Key-color detection (pure function) ──────────────────────────────

func _test_key_color_detection() -> void:
	_chk("A.01 exact key color matches",
			BattleScreenShared._is_message_box_key_color(Color8(115, 205, 164, 255)))
	# [Correction during test-writing] Color.is_equal_approx's default
	# epsilon is far tighter than a single 8-bit channel step (~0.0039 in
	# normalized float space) — a real palette-indexed PNG's key color is
	# always byte-exact across every pixel anyway (confirmed by C.02 below
	# against the real asset), so exact matching is the correct, sufficient
	# behavior; this case confirms a genuinely different nearby color is
	# NOT swept up by too-loose a match.
	_chk("A.02 a visibly-different nearby green does not match",
			not BattleScreenShared._is_message_box_key_color(Color8(115, 205, 174, 255)))
	_chk("A.03 white does not match", not BattleScreenShared._is_message_box_key_color(Color.WHITE))
	_chk("A.04 the border's own dark gray does not match",
			not BattleScreenShared._is_message_box_key_color(Color8(98, 115, 123, 255)))
	_chk("A.05 fully transparent black does not match",
			not BattleScreenShared._is_message_box_key_color(Color(0, 0, 0, 0)))


# ── B. _color_keyed_texture on a small synthetic image (no disk I/O) ────

func _test_color_keyed_texture_synthetic() -> void:
	var img := Image.create(4, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color8(115, 205, 164, 255))  # key color -> should become transparent
	img.set_pixel(1, 0, Color.WHITE)                  # untouched
	img.set_pixel(2, 0, Color.BLACK)                  # untouched
	img.set_pixel(3, 0, Color8(115, 205, 164, 255))   # key color -> should become transparent

	var tex: ImageTexture = BattleScreenShared._color_keyed_texture(img)
	var result: Image = tex.get_image()

	_chk("B.01 key-colored pixel 0 becomes fully transparent", result.get_pixel(0, 0).a == 0.0)
	_chk("B.02 white pixel 1 is untouched", result.get_pixel(1, 0).is_equal_approx(Color.WHITE))
	_chk("B.03 black pixel 2 is untouched", result.get_pixel(2, 0).is_equal_approx(Color(0, 0, 0, 1)))
	_chk("B.04 key-colored pixel 3 becomes fully transparent", result.get_pixel(3, 0).a == 0.0)
	_chk("B.05 source image itself is not mutated (duplicated, not aliased)",
			img.get_pixel(0, 0).a == 1.0)


# ── C. Real std.png asset, run through the real color-keying function ──

func _test_color_keyed_texture_real_asset() -> void:
	var raw: Image = load("res://assets/sprites/battle_ui/text_window/std.png").get_image()
	_chk("C.01 real std.png loads and is 24x24", raw.get_width() == 24 and raw.get_height() == 24)

	var tex: ImageTexture = BattleScreenShared._color_keyed_texture(raw)
	var result: Image = tex.get_image()

	var any_opaque_key_pixel_remains := false
	var any_transparent_pixel_found := false
	for y in range(result.get_height()):
		for x in range(result.get_width()):
			var px: Color = result.get_pixel(x, y)
			if px.a == 0.0:
				any_transparent_pixel_found = true
			elif BattleScreenShared._is_message_box_key_color(px) and px.a > 0.0:
				any_opaque_key_pixel_remains = true

	_chk("C.02 no opaque key-colored pixel remains anywhere in the real asset",
			not any_opaque_key_pixel_remains)
	_chk("C.03 at least one pixel became transparent (the corners)", any_transparent_pixel_found)

	# The known-white interior (see battle_screen.gd's own pixel-scanline
	# citation) must still be fully opaque white, confirming the keying only
	# touched the background-key color, not the real border/interior art.
	_chk("C.04 the known white interior pixel stays opaque white",
			result.get_pixel(12, 12).is_equal_approx(Color(1, 1, 1, 1)))

# [M26b] Sections D (_setup_message_box() itself) and E (DialogueLabel's own
# generic append behavior) were removed here — see this file's own top doc
# comment for why.
