extends Node

# [M26E3-1] Data-integrity smoke test for the Party/Switch screen's real
# Emerald UI Pack asset pull (scripts/gen_party_screen_sprites.py) --
# mirrors battle_background_smoke_test.gd's own directory-scan-plus-fixed-
# expected-set precedent: this pull has a known, fixed target (exactly 30
# files, per the script's own FILES list), so this test checks both "every
# file on disk loads at its real pack dimensions" and "no file is missing/
# extra", not just a raw scan.

var _pass := 0
var _fail := 0

const PARTY_DIR := "res://assets/sprites/battle_ui/party"

# filename -> expected (width, height), from this session's own direct PIL
# inspection of the pack's real source files (see the generator script's
# own doc comment for the Step 0 findings this table encodes).
const EXPECTED_SIZES := {
	"panel_round_base.png": Vector2(156, 98),
	"panel_round_sel.png": Vector2(156, 98),
	"panel_round_faint.png": Vector2(156, 98),
	"panel_round_faint_sel.png": Vector2(156, 98),
	"panel_round_swap.png": Vector2(156, 98),
	"panel_round_swap_sel.png": Vector2(156, 98),
	"panel_round_swap_sel2.png": Vector2(156, 98),
	"panel_rect_base.png": Vector2(288, 48),
	"panel_rect_sel.png": Vector2(288, 48),
	"panel_rect_faint.png": Vector2(288, 48),
	"panel_rect_faint_sel.png": Vector2(288, 48),
	"panel_rect_swap.png": Vector2(288, 48),
	"panel_rect_swap_sel.png": Vector2(288, 48),
	"panel_rect_swap_sel2.png": Vector2(288, 48),
	"panel_blank.png": Vector2(1, 1),
	"party_bg_singles.png": Vector2(512, 384),
	"party_bg_doubles.png": Vector2(512, 384),
	"party_hp_zones.png": Vector2(96, 24),
	"party_hp_trough.png": Vector2(138, 14),
	"party_hp_trough_faint.png": Vector2(138, 14),
	"party_hp_trough_swap.png": Vector2(138, 14),
	"party_lv_icon.png": Vector2(22, 16),
	"party_gender_male.png": Vector2(16, 16),
	"party_gender_female.png": Vector2(16, 16),
	"party_ball_icon.png": Vector2(44, 56),
	"party_ball_icon_sel.png": Vector2(44, 56),
	"party_cancel_icon.png": Vector2(112, 36),
	"party_cancel_icon_sel.png": Vector2(112, 36),
	"party_item_icon.png": Vector2(16, 16),
	"party_mail_icon.png": Vector2(16, 16),
}

# [Step 0] bg.PNG/bg_double.png and overlay_hp.png are genuinely opaque in
# the real pack files (no PNG tRNS chunk) -- confirmed via direct pixel
# inspection, not a gap. Every other file here carries real alpha.
const EXPECTED_OPAQUE := [
	"party_bg_singles.png", "party_bg_doubles.png", "party_hp_zones.png",
]


func _ready() -> void:
	_test_directory_scan()
	_test_expected_files_load_at_real_dimensions()
	_test_transparency_expectations()

	var total := _pass + _fail
	print("party_screen_sprite_smoke_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_directory_scan() -> void:
	var dir := DirAccess.open(PARTY_DIR)
	_chk("%s directory exists and is openable" % PARTY_DIR, dir != null)
	if dir == null:
		return

	var found := {}
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			found[filename] = true
		filename = dir.get_next()
	dir.list_dir_end()

	_chk("exactly %d files on disk (matching the generator's own FILES list)" \
			% EXPECTED_SIZES.size(), found.size() == EXPECTED_SIZES.size())
	for expected_name in EXPECTED_SIZES:
		_chk("%s exists on disk" % expected_name, found.has(expected_name))


func _test_expected_files_load_at_real_dimensions() -> void:
	for filename in EXPECTED_SIZES:
		var tex: Texture2D = load("%s/%s" % [PARTY_DIR, filename])
		var expected: Vector2 = EXPECTED_SIZES[filename]
		_chk("%s loads as a real Texture2D" % filename, tex != null)
		if tex != null:
			_chk("%s is %dx%d (real pack dimensions)" \
					% [filename, expected.x, expected.y],
					tex.get_width() == int(expected.x) and tex.get_height() == int(expected.y))


func _test_transparency_expectations() -> void:
	for filename in EXPECTED_OPAQUE:
		var tex: Texture2D = load("%s/%s" % [PARTY_DIR, filename])
		var img: Image = tex.get_image() if tex != null else null
		_chk("%s loads as a real Image" % filename, img != null)
		if img == null:
			continue
		var fully_opaque := true
		# Sample the 4 corners -- a real background/zone-band file is
		# opaque everywhere, so any corner suffices as a discriminator.
		for corner in [Vector2i(0, 0), Vector2i(img.get_width() - 1, 0),
				Vector2i(0, img.get_height() - 1),
				Vector2i(img.get_width() - 1, img.get_height() - 1)]:
			if img.get_pixelv(corner).a < 1.0:
				fully_opaque = false
		_chk("%s is genuinely opaque (no tRNS chunk in the real pack file)" \
				% filename, fully_opaque)

	# One representative real-alpha file, as a discriminator proving the
	# opaque check above isn't vacuously true for every file.
	var panel_tex: Texture2D = load("%s/panel_round_base.png" % PARTY_DIR)
	var panel_img: Image = panel_tex.get_image() if panel_tex != null else null
	_chk("panel_round_base.png (a real panel) carries real alpha at its own corner",
			panel_img != null and panel_img.get_pixel(0, 0).a < 1.0)
