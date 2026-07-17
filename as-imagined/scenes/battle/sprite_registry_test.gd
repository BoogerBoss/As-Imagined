extends Node

# [M23.11 Phase 4a] Data-integrity test for SpriteRegistry's own
# RESOLUTION LOGIC -- distinct from pokemon_sprite_smoke_test.gd, which
# checks the raw asset files themselves (existence, loads as Texture2D).
# This test instead exercises the registry's lookup/caching/slicing
# behavior: does get_front()/get_back() resolve the right file per dex,
# does the front-frame slice come out the right size, does the dex-0
# "unknown" fallback resolve correctly, and does an out-of-range dex
# gracefully return null rather than crash.

var _pass := 0
var _fail := 0

const DEX_MIN := 1
const DEX_MAX := 386
const UNKNOWN_DEX := 0
const INVALID_DEX := 9999
const EXPECTED_FRAME_SIZE := Vector2(64, 64)


func _ready() -> void:
	_test_real_species_range()
	_test_unknown_fallback()
	_test_invalid_dex()

	var total := _pass + _fail
	print("sprite_registry_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_real_species_range() -> void:
	for dex in range(DEX_MIN, DEX_MAX + 1):
		var front: Texture2D = SpriteRegistry.get_front(dex)
		_chk("dex %d: get_front resolves to a non-null Texture2D" % dex, front != null)
		if front != null:
			_chk("dex %d: get_front's sliced frame is exactly 64x64" % dex,
					front.get_size() == EXPECTED_FRAME_SIZE)

		var back: Texture2D = SpriteRegistry.get_back(dex)
		_chk("dex %d: get_back resolves to a non-null Texture2D" % dex, back != null)
		if back != null:
			_chk("dex %d: get_back's texture is exactly 64x64" % dex,
					back.get_size() == EXPECTED_FRAME_SIZE)


func _test_unknown_fallback() -> void:
	var front: Texture2D = SpriteRegistry.get_front(UNKNOWN_DEX)
	_chk("dex 0 (unknown fallback): get_front resolves to a non-null Texture2D", front != null)
	if front != null:
		_chk("dex 0: get_front's sliced frame is exactly 64x64", front.get_size() == EXPECTED_FRAME_SIZE)

	var back: Texture2D = SpriteRegistry.get_back(UNKNOWN_DEX)
	_chk("dex 0 (unknown fallback): get_back resolves to a non-null Texture2D", back != null)
	if back != null:
		_chk("dex 0: get_back's texture is exactly 64x64", back.get_size() == EXPECTED_FRAME_SIZE)


func _test_invalid_dex() -> void:
	_chk("invalid dex %d: get_front returns null, not a crash" % INVALID_DEX,
			SpriteRegistry.get_front(INVALID_DEX) == null)
	_chk("invalid dex %d: get_back returns null, not a crash" % INVALID_DEX,
			SpriteRegistry.get_back(INVALID_DEX) == null)
