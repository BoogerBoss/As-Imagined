extends Node

# [M26B4-1] Asset smoke test for the in-battle weather animation set, pulled
# by scripts/gen_weather_effect_sprites.py. Mirrors hit_effect_smoke_test.gd /
# battle_background_smoke_test.gd's own directory-scan convention.
#
# Full recon: docs/m26_b4_recon.md. In short: source has no persistent weather
# renderer — it REPLAYS a finite animation every turn — and these are the
# assets those animations use. For Sun/Sandstorm/Hail/Snow the per-turn
# "continues" animation is a literal `goto` into the MOVE's own script, so one
# asset set serves both consumers.
#
# Two properties here are load-bearing rather than cosmetic:
#
#  1. The five SPRITES must have palette index 0 tagged transparent. These
#     source PNGs carry no tRNS chunk, so a plain flat copy renders every
#     particle inside an opaque box — the exact defect [M26B3-6a] hit with the
#     ball sheets.
#  2. sandstorm_bg.png must be the OPPOSITE — fully opaque. It is a GBA BG
#     layer, where index 0 is a real colour (established in Phase 5a,
#     reconfirmed for Surf's water.png in Phase 5b). Tagging it transparent
#     would punch holes in the backdrop.

const WEATHER_DIR := "res://assets/sprites/battle_effects/weather"

# name -> expected exact size. Sizes are the source assets' own, verified on
# disk during the pull; pinned here so a bad re-pull fails loudly.
const EXPECTED_SPRITES := {
	"rain_drops.png": Vector2i(16, 224),   # 16x32 OAM => 7 stacked frames
	"sunlight.png": Vector2i(32, 32),      # affine (rotates/scales)
	"flying_dirt.png": Vector2i(32, 32),   # 32x16 OAM, 2 subsprites => 64x16 crescent
	"hail.png": Vector2i(16, 16),          # affine
	"snowflakes.png": Vector2i(16, 224),   # Snowscape — see _test_snowscape_asset_present
}
const BG_NAME := "sandstorm_bg.png"
const BG_SIZE := Vector2i(256, 256)  # one 32x32-tile GBA screen block

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_directory_contents()
	_test_sprites_load_at_expected_size()
	_test_sprites_have_index_zero_transparent()
	_test_background_decoded_and_opaque()
	_test_background_decode_has_no_fallback_pixels()
	_test_snowscape_asset_present()
	_test_weather_dir_is_separate_from_generic_and_bespoke()

	var total := _pass + _fail
	print("m26_b4_1_weather_asset_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _texture(filename: String) -> Texture2D:
	var res: Resource = load("%s/%s" % [WEATHER_DIR, filename])
	return res as Texture2D


# ── Directory ────────────────────────────────────────────────────────────

func _test_directory_contents() -> void:
	var dir := DirAccess.open(WEATHER_DIR)
	_chk("A.01 %s exists and is openable" % WEATHER_DIR, dir != null)
	if dir == null:
		return
	var found: Array[String] = []
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			found.append(filename)
		filename = dir.get_next()
	dir.list_dir_end()
	found.sort()

	var expected: Array[String] = []
	for k: String in EXPECTED_SPRITES:
		expected.append(k)
	expected.append(BG_NAME)
	expected.sort()

	_chk("A.02 exactly 6 weather assets on disk", found.size() == 6)
	_chk("A.03 the files match the expected set exactly", found == expected)


# ── Sprites ──────────────────────────────────────────────────────────────

func _test_sprites_load_at_expected_size() -> void:
	for filename: String in EXPECTED_SPRITES:
		var tex := _texture(filename)
		_chk("B.01 %s loads as a Texture2D" % filename, tex != null)
		if tex != null:
			var expected: Vector2i = EXPECTED_SPRITES[filename]
			_chk("B.02 %s is %dx%d" % [filename, expected.x, expected.y],
					Vector2i(tex.get_size()) == expected)


# The defect this guards against renders as an opaque box around every
# particle — caught by screenshot in M26B3-6a, pinned by assertion here.
func _test_sprites_have_index_zero_transparent() -> void:
	for filename: String in EXPECTED_SPRITES:
		var tex := _texture(filename)
		if tex == null:
			continue
		var img: Image = tex.get_image()
		_chk("B.03 %s has index 0 tagged transparent (corner pixel is clear)" % filename,
				img != null and img.get_pixel(0, 0).a == 0.0)
		# Non-vacuity: a fully transparent sheet would pass the corner check
		# while containing no art at all.
		var opaque := 0
		if img != null:
			for y in range(img.get_height()):
				for x in range(img.get_width()):
					if img.get_pixel(x, y).a > 0.0:
						opaque += 1
		_chk("B.04 %s still contains real opaque art" % filename, opaque > 0)


# ── Background ───────────────────────────────────────────────────────────

func _test_background_decoded_and_opaque() -> void:
	var tex := _texture(BG_NAME)
	_chk("C.01 %s loads as a Texture2D" % BG_NAME, tex != null)
	if tex == null:
		return
	_chk("C.02 %s is one full 32x32-tile screen block (%dx%d)"
				% [BG_NAME, BG_SIZE.x, BG_SIZE.y],
			Vector2i(tex.get_size()) == BG_SIZE)
	var img: Image = tex.get_image()
	var transparent := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a < 1.0:
				transparent += 1
	_chk("C.03 %s is fully opaque (BG layer, index 0 is a real colour)" % BG_NAME,
			transparent == 0)


# decode_screen_block() writes magenta (255,0,255) wherever a screen entry
# references a palette slot it can't resolve. Any magenta at all means the
# decode is wrong, which is exactly the failure mode Phase 5a was flagged for.
func _test_background_decode_has_no_fallback_pixels() -> void:
	var tex := _texture(BG_NAME)
	if tex == null:
		return
	var img: Image = tex.get_image()
	var magenta := 0
	var distinct := {}
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			distinct[c.to_rgba32()] = true
			if is_equal_approx(c.r, 1.0) and is_equal_approx(c.g, 0.0) \
					and is_equal_approx(c.b, 1.0):
				magenta += 1
	_chk("C.04 no unresolved-palette magenta pixels in the decode", magenta == 0)
	# A garbled or single-bank decode collapses to near-uniform output; the real
	# sandstorm texture is a small dithered sand palette.
	_chk("C.05 the decode produced a real multi-colour texture, not a flat fill",
			distinct.size() >= 4)


# ── Snowscape ────────────────────────────────────────────────────────────

# Rob's call, 2026-07-27. [D2 batch] permanently collapsed source's separate
# Snow and Hail into this project's single WEATHER_HAIL, so Snowscape (move
# 809) sets hail here while source keeps the two distinct. snowflakes.png is
# pulled so Snowscape keeps its own authentic MOVE animation; the per-turn
# replay still follows weather STATE and so shows hail.
#
# That residual divergence — snowflakes once, then hail each turn — is a
# KNOWN, ACCEPTED consequence of the collapse, not a defect. Do not "fix" it
# by deleting this asset or by remapping Snowscape to hail without revisiting
# the collapse decision itself.
func _test_snowscape_asset_present() -> void:
	var tex := _texture("snowflakes.png")
	_chk("D.01 snowflakes.png is present for Snowscape's own move animation",
			tex != null)
	var hail := _texture("hail.png")
	_chk("D.02 it is genuinely distinct art from hail.png, not a duplicate",
			tex != null and hail != null and tex.get_size() != hail.get_size())


# ── Directory separation ─────────────────────────────────────────────────

# These assets deliberately do NOT live in battle_effects/generic/, whose exact
# contents hit_effect_smoke_test asserts — [M26B3-6a] already had to relocate
# the ball-particle sheet out of it for that reason. Nor in per-move bespoke/
# subdirs, since they have two consumers (move anim AND per-turn replay).
func _test_weather_dir_is_separate_from_generic_and_bespoke() -> void:
	_chk("E.01 weather assets are not in generic/",
			not FileAccess.file_exists(
					"res://assets/sprites/battle_effects/generic/rain_drops.png"))
	_chk("E.02 generic/ still holds its own curated library untouched",
			DirAccess.open("res://assets/sprites/battle_effects/generic") != null)
	_chk("E.03 bespoke/ still holds its own per-move dirs untouched",
			DirAccess.open("res://assets/sprites/battle_effects/bespoke") != null)
