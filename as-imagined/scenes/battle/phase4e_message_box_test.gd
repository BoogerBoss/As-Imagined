extends Node

# [M23.11 Phase 4e] Test suite for the Dialogue-Manager-balloon-based
# message box — the runtime color-keying of text_window/std.png's
# background-key green, the resulting StyleBoxTexture's margins, and
# confirmation that _setup_message_box() doesn't disturb the existing
# accumulating-scroll log behavior (DialogueLabel IS-A RichTextLabel; see
# battle_screen.gd's own doc comments for the full reasoning).
#
# [Deliberately NOT tested here] Instantiating battle_screen.tscn — same
# established precedent as phase4d_doubles_visual_test.gd/
# phase4f_targeting_test.gd (count_assertions.sh's own unconditional
# --autoplay flag, battle_screen.gd's own process-wide autoplay check).
# Every function this suite exercises is called directly on a bare
# `BattleScreen.new()` instance never added to the scene tree, plus a
# manually-constructed DialogueLabel node standing in for the real
# scene's onready `_log_label` — the genuine end-to-end proof (real art,
# real singles/doubles battles, no overlap with Phase 4d's visual layer)
# is the mandated real screenshot verification instead.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_key_color_detection()
	_test_color_keyed_texture_synthetic()
	_test_color_keyed_texture_real_asset()
	_test_setup_message_box_applies_stylebox()
	_test_log_label_still_plain_richtextlabel_append()

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
			BattleScreen._is_message_box_key_color(Color8(115, 205, 164, 255)))
	# [Correction during test-writing] Color.is_equal_approx's default
	# epsilon is far tighter than a single 8-bit channel step (~0.0039 in
	# normalized float space) — a real palette-indexed PNG's key color is
	# always byte-exact across every pixel anyway (confirmed by C.02 below
	# against the real asset), so exact matching is the correct, sufficient
	# behavior; this case confirms a genuinely different nearby color is
	# NOT swept up by too-loose a match.
	_chk("A.02 a visibly-different nearby green does not match",
			not BattleScreen._is_message_box_key_color(Color8(115, 205, 174, 255)))
	_chk("A.03 white does not match", not BattleScreen._is_message_box_key_color(Color.WHITE))
	_chk("A.04 the border's own dark gray does not match",
			not BattleScreen._is_message_box_key_color(Color8(98, 115, 123, 255)))
	_chk("A.05 fully transparent black does not match",
			not BattleScreen._is_message_box_key_color(Color(0, 0, 0, 0)))


# ── B. _color_keyed_texture on a small synthetic image (no disk I/O) ────

func _test_color_keyed_texture_synthetic() -> void:
	var img := Image.create(4, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color8(115, 205, 164, 255))  # key color -> should become transparent
	img.set_pixel(1, 0, Color.WHITE)                  # untouched
	img.set_pixel(2, 0, Color.BLACK)                  # untouched
	img.set_pixel(3, 0, Color8(115, 205, 164, 255))   # key color -> should become transparent

	var tex: ImageTexture = BattleScreen._color_keyed_texture(img)
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

	var tex: ImageTexture = BattleScreen._color_keyed_texture(raw)
	var result: Image = tex.get_image()

	var any_opaque_key_pixel_remains := false
	var any_transparent_pixel_found := false
	for y in range(result.get_height()):
		for x in range(result.get_width()):
			var px: Color = result.get_pixel(x, y)
			if px.a == 0.0:
				any_transparent_pixel_found = true
			elif BattleScreen._is_message_box_key_color(px) and px.a > 0.0:
				any_opaque_key_pixel_remains = true

	_chk("C.02 no opaque key-colored pixel remains anywhere in the real asset",
			not any_opaque_key_pixel_remains)
	_chk("C.03 at least one pixel became transparent (the corners)", any_transparent_pixel_found)

	# The known-white interior (see battle_screen.gd's own pixel-scanline
	# citation) must still be fully opaque white, confirming the keying only
	# touched the background-key color, not the real border/interior art.
	_chk("C.04 the known white interior pixel stays opaque white",
			result.get_pixel(12, 12).is_equal_approx(Color(1, 1, 1, 1)))


# ── D. _setup_message_box() applies a real StyleBoxTexture with the
# expected margins, called directly on a bare instance with a manually-
# constructed stand-in node for the onready _log_label. ──────────────────

func _test_setup_message_box_applies_stylebox() -> void:
	var bs := BattleScreen.new()
	var fake_log_label := DialogueLabel.new()
	bs._log_label = fake_log_label
	# [M25h-1.2] _setup_message_box() now also applies the real message-
	# context bitmap font to _log_label -- a null font here (this
	# function's own production caller, _ready(), always loads one first
	# via _load_battle_fonts()) makes add_theme_font_override log a real
	# engine error rather than silently no-op.
	bs._font_message = FontFile.new()
	bs._font_message.load_bitmap_font("res://assets/fonts/latin_normal_message.fnt")

	bs._setup_message_box()

	var applied: StyleBox = fake_log_label.get_theme_stylebox("normal")
	_chk("D.01 a StyleBoxTexture was applied to the log label",
			applied != null and applied is StyleBoxTexture)
	if applied is StyleBoxTexture:
		var st: StyleBoxTexture = applied
		_chk("D.02 texture_margin_left matches the measured 5px corner",
				st.texture_margin_left == BattleScreen._MESSAGE_BOX_MARGIN)
		_chk("D.03 texture_margin_top matches the measured 5px corner",
				st.texture_margin_top == BattleScreen._MESSAGE_BOX_MARGIN)
		_chk("D.04 texture_margin_right matches the measured 5px corner",
				st.texture_margin_right == BattleScreen._MESSAGE_BOX_MARGIN)
		_chk("D.05 texture_margin_bottom matches the measured 5px corner",
				st.texture_margin_bottom == BattleScreen._MESSAGE_BOX_MARGIN)
		_chk("D.06 the stylebox's own texture is set", st.texture != null)


# ── E. Confirm DialogueLabel's own dialogue_line/type_out API being
# untouched means plain `.text +=` still behaves exactly like a normal
# RichTextLabel — the key claim behind not regressing queuing/sequencing.

func _test_log_label_still_plain_richtextlabel_append() -> void:
	var label := DialogueLabel.new()
	label.text = ""
	label.text += "line one\n"
	label.text += "line two\n"
	_chk("E.01 plain .text += accumulates normally, untouched by DialogueLabel's own API",
			label.text == "line one\nline two\n")
	_chk("E.02 dialogue_line was never set (no typewriter side effect triggered)",
			label.dialogue_line == null)
	_chk("E.03 is_typing stays false since type_out() was never called", not label.is_typing)
