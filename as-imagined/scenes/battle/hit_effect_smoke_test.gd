extends Node

# [M23.11 Phase 5b] Data-integrity smoke test for the hit-effect asset
# pull -- mirrors battle_background_smoke_test.gd's own directory-scan
# precedent (a known, fixed target set, not just "every present file
# loads"), extended to cover both halves of the locked hybrid model:
# Part A (the 21-sprite generic library, flat) and Part B (the 3 bespoke
# moves, each its own move-ID-keyed subdirectory).

var _pass := 0
var _fail := 0

const GENERIC_DIR := "res://assets/sprites/battle_effects/generic"
const BESPOKE_DIR := "res://assets/sprites/battle_effects/bespoke"

const EXPECTED_GENERIC_IDS := [
	"fire", "water", "electric", "grass", "ice", "rock", "ground", "psychic",
	"ghost", "dark", "poison", "dragon", "fighting", "flying", "bug", "steel",
	"fairy", "normal", "physical_impact", "status_puff", "stat_shimmer",
]

# Bespoke subdir -> the exact files gen_hit_effect_sprites.py writes there.
# Surf's two files are BG-layer reconstructions (opaque, like Phase 5a's
# backgrounds) -- deliberately NOT expected to carry transparency, unlike
# every sprite-shaped file here, which is why they're tracked separately
# below rather than folded into one uniform "every file must be
# transparent" loop.
const EXPECTED_BESPOKE := {
	"0053_flamethrower": ["small_ember.png"],
	"0087_thunder": ["lightning.png", "lightning_2.png"],
	"0057_surf": ["water_opponent.png", "water_player.png"],
}
const SURF_SUBDIR := "0057_surf"


func _ready() -> void:
	_test_generic_directory()
	_test_bespoke_directories()

	var total := _pass + _fail
	print("hit_effect_smoke_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Part A: generic library ───────────────────────────────────────────────

func _test_generic_directory() -> void:
	var dir := DirAccess.open(GENERIC_DIR)
	_chk("%s directory exists and is openable" % GENERIC_DIR, dir != null)
	if dir == null:
		return

	var found_ids: Array[String] = []
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			found_ids.append(filename.get_basename())
			var full_path := "%s/%s" % [GENERIC_DIR, filename]
			var res: Resource = load(full_path)
			_chk("generic/%s loads as a valid Texture2D" % filename,
					res != null and res is Texture2D)
			if res is Texture2D:
				var size: Vector2 = (res as Texture2D).get_size()
				_chk("generic/%s has nonzero dimensions" % filename,
						size.x > 0 and size.y > 0)
				var img: Image = (res as Texture2D).get_image()
				_chk("generic/%s uses palette index 0 as transparent (a corner pixel is transparent)" % filename,
						img != null and img.get_pixel(0, 0).a == 0.0)
		filename = dir.get_next()
	dir.list_dir_end()

	_chk("exactly 21 generic files found on disk", found_ids.size() == 21)
	found_ids.sort()
	var expected_sorted := EXPECTED_GENERIC_IDS.duplicate()
	expected_sorted.sort()
	_chk("the 21 generic files match the curated list exactly",
			found_ids == expected_sorted)


# ── Part B: bespoke moves ─────────────────────────────────────────────────

func _test_bespoke_directories() -> void:
	for subdir in EXPECTED_BESPOKE.keys():
		var dir_path := "%s/%s" % [BESPOKE_DIR, subdir]
		var dir := DirAccess.open(dir_path)
		_chk("%s directory exists and is openable" % dir_path, dir != null)
		if dir == null:
			continue

		var expected_files: Array = EXPECTED_BESPOKE[subdir]
		for expected_filename in expected_files:
			var full_path := "%s/%s" % [dir_path, expected_filename]
			_chk("%s exists" % full_path, FileAccess.file_exists(full_path))
			var res: Resource = load(full_path)
			_chk("%s loads as a valid Texture2D" % full_path,
					res != null and res is Texture2D)
			if res is Texture2D:
				var size: Vector2 = (res as Texture2D).get_size()
				_chk("%s has nonzero dimensions" % full_path, size.x > 0 and size.y > 0)

				var img: Image = (res as Texture2D).get_image()
				if subdir == SURF_SUBDIR:
					# BG-layer reconstruction, opaque by design (matches
					# Phase 5a's own battle-background convention) --
					# confirm it's the full uncropped 512x256 canvas, not
					# a single-screen 240x160 crop.
					_chk("%s is the full uncropped 512x256 canvas" % full_path,
							size.x == 512 and size.y == 256)
					_chk("%s is fully opaque (a BG layer, not a sprite)" % full_path,
							img != null and img.get_pixel(0, 0).a == 1.0)
				else:
					_chk("%s uses palette index 0 as transparent" % full_path,
							img != null and img.get_pixel(0, 0).a == 0.0)
