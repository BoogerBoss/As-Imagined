extends Node

# [M25h-1.2] Regression suite for the real GBA bitmap fonts pulled and
# wired in this sub-phase — see scripts/gen_battle_fonts.py's own doc
# comment for the full Step 0 source citations (glyph grid, per-context
# TextColor sourcing) this suite doesn't re-derive.
#
# [Deliberately NOT tested here] The full _setup_health_ui()/
# _setup_message_box()/_setup_action_region_panel() -> real .tscn node ->
# on-screen pixel pipeline needs a live instantiated scene (real NodePath
# `$BattleStage/...` lookups _setup_health_ui() alone makes ~20 of) --
# matches every prior M25h/Phase-4x suite's own established precedent of
# scoping automated coverage to pure logic + bare-instance direct calls,
# and leaving the real end-to-end visual proof to this session's own
# mandatory real screenshot pass (singles TOP/FIGHT/log-with-real-move-
# text, doubles TOP) rather than fighting to reconstruct that whole tree
# by hand in a unit test.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_all_three_atlas_and_fnt_files_exist()
	_test_all_three_fonts_load_without_error()
	_test_each_font_has_the_full_needed_character_set()
	_test_fonts_are_genuinely_proportional_not_monospaced()
	_test_load_battle_fonts_populates_all_three_fields()
	_test_style_menu_button_applies_menu_font_and_neutral_color()
	_test_style_menu_button_sets_a_visibly_different_disabled_color()

	var total := _pass + _fail
	print("m25h1_2_font_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % label)


# ── A. The 3 generated (font, context) atlas+.fnt pairs exist on disk ──────

func _test_all_three_atlas_and_fnt_files_exist() -> void:
	var contexts := ["latin_normal_message", "latin_normal_menu", "latin_small_healthbox"]
	for ctx in contexts:
		_chk("%s.png exists" % ctx, FileAccess.file_exists("res://assets/fonts/%s.png" % ctx))
		_chk("%s.fnt exists" % ctx, FileAccess.file_exists("res://assets/fonts/%s.fnt" % ctx))


# ── B. Each loads cleanly as a real Godot FontFile via load_bitmap_font() ──

func _test_all_three_fonts_load_without_error() -> void:
	var contexts := ["latin_normal_message", "latin_normal_menu", "latin_small_healthbox"]
	for ctx in contexts:
		var font := FontFile.new()
		var err := font.load_bitmap_font("res://assets/fonts/%s.fnt" % ctx)
		_chk("%s.fnt loads with OK" % ctx, err == OK)


# ── C. Full needed character set (uppercase/lowercase/digits/punctuation
# this project's M25c move-announcement/damage/effectiveness text and
# Pokemon/move/item names actually use) is present in every font ──────────

func _test_each_font_has_the_full_needed_character_set() -> void:
	var sample := " !?.-,'()%:/&+0123456789ABCXYZabcxyz"
	var contexts := ["latin_normal_message", "latin_normal_menu", "latin_small_healthbox"]
	for ctx in contexts:
		var font := FontFile.new()
		font.load_bitmap_font("res://assets/fonts/%s.fnt" % ctx)
		var all_present := true
		for i in range(sample.length()):
			if not font.has_char(sample.unicode_at(i)):
				all_present = false
				print("  missing char '%s' in %s" % [sample[i], ctx])
		_chk("%s has every character in the sample set" % ctx, all_present)


# ── D. Genuinely proportional -- narrow glyphs (I, !, space) measurably
# narrower than wide ones (M, W), confirming the real per-glyph width
# table was actually used, not a fixed cell width ─────────────────────────

func _test_fonts_are_genuinely_proportional_not_monospaced() -> void:
	var font := FontFile.new()
	font.load_bitmap_font("res://assets/fonts/latin_normal_message.fnt")
	var size := BattleScreen._FONT_NORMAL_SIZE

	# [Real Step-0 finding, not an assumption] gFontNormalLatinGlyphWidths
	# turns out to be near-monospace for the capital-letter/digit block
	# (uniformly 6px -- confirmed directly, most capitals/digits/most
	# lowercase share this exact value) with proportional variation
	# concentrated in punctuation and a handful of narrow lowercase glyphs
	# instead. '&' (7px) is this project's own curated set's single WIDEST
	# glyph; 'A' (6px, the uniform capital-letter width) sits in the
	# middle; 'i' (4px) and '.' (3px) are genuinely narrower -- a real,
	# sourced monotonic chain, not the "M wider than I" assumption a
	# generic proportional font might suggest (this specific font's 'M'
	# and 'I' are BOTH 6px, confirmed via direct .fnt inspection).
	var width_amp: float = font.get_string_size("&", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var width_a: float = font.get_string_size("A", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var width_i: float = font.get_string_size("i", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var width_period: float = font.get_string_size(".", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

	_chk("'&' is measurably wider than 'A' (not fixed-width)", width_amp > width_a)
	_chk("'A' is measurably wider than 'i' (not fixed-width)", width_a > width_i)
	_chk("'i' is measurably wider than '.' (not fixed-width)", width_i > width_period)

	# A real regression guard on the exact source-cited width table values
	# (gFontNormalLatinGlyphWidths, re-confirmed directly against the
	# generated .fnt file during this sub-phase's own Step 0).
	_chk("'&' 's own real source width is exactly 7px", is_equal_approx(width_amp, 7.0))
	_chk("'A' 's own real source width is exactly 6px", is_equal_approx(width_a, 6.0))
	_chk("'.' 's own real source width is exactly 3px", is_equal_approx(width_period, 3.0))


# ── E. _load_battle_fonts() populates all three member fields on a bare
# instance (no scene tree needed -- pure disk load + field assignment) ────

func _test_load_battle_fonts_populates_all_three_fields() -> void:
	var bs := BattleScreen.new()
	bs._load_battle_fonts()

	_chk("_font_message is a real loaded FontFile", bs._font_message != null and bs._font_message is FontFile)
	_chk("_font_menu is a real loaded FontFile", bs._font_menu != null and bs._font_menu is FontFile)
	_chk("_font_healthbox is a real loaded FontFile", bs._font_healthbox != null and bs._font_healthbox is FontFile)
	_chk("_font_message and _font_menu are genuinely distinct resources (different baked colors)",
			bs._font_message != bs._font_menu)


# ── F. _style_menu_button() applies the real menu font + a neutral
# (non-tinting) color set, on a bare Button with no scene tree needed ─────

func _test_style_menu_button_applies_menu_font_and_neutral_color() -> void:
	var bs := BattleScreen.new()
	bs._load_battle_fonts()
	var btn := Button.new()

	bs._style_menu_button(btn)

	_chk("Button has the real menu-context bitmap font applied",
			btn.get_theme_font("font") == bs._font_menu)
	_chk("Button font_size matches the font's own native pixel size (no soft rescaling)",
			btn.get_theme_font_size("font_size") == BattleScreen._FONT_NORMAL_SIZE)
	_chk("Button font_color is neutral white (the baked-in dark-grey/light-grey pixels show through unmodified)",
			btn.get_theme_color("font_color").is_equal_approx(Color(1, 1, 1, 1)))
	_chk("Button font_hover_color is also neutral",
			btn.get_theme_color("font_hover_color").is_equal_approx(Color(1, 1, 1, 1)))


func _test_style_menu_button_sets_a_visibly_different_disabled_color() -> void:
	var bs := BattleScreen.new()
	bs._load_battle_fonts()
	var btn := Button.new()

	bs._style_menu_button(btn)

	var disabled_color: Color = btn.get_theme_color("font_disabled_color")
	_chk("font_disabled_color keeps the same RGB (still recognizably the baked font) but fades alpha",
			disabled_color.r == 1.0 and disabled_color.g == 1.0 and disabled_color.b == 1.0 and disabled_color.a < 1.0)
