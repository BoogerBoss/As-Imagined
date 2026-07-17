class_name SpriteRegistry
extends RefCounted

# [M23.11 Phase 4a] Dex-keyed sprite loader for assets/sprites/pokemon/,
# mirroring MoveRegistry/ItemRegistry's static-loader convention -- but
# unlike those two, this CANNOT use a pure "%04d.png" string template,
# since every filename here also embeds the species slug
# (e.g. "0001_bulbasaur.png") for on-disk browsability. Instead: a
# lazily-built static cache (one directory scan per kind, on first call
# only), giving O(1) lookups after that with zero new manifest/data file
# to keep in sync with what's actually on disk.
#
# get_front()/get_back() return null for an unresolvable dex (matching
# MoveRegistry.get_move()'s own "return null" convention for an
# unimplemented ID) -- callers decide what to substitute (see
# battle_screen.gd's own dex-0 "unknown" fallback handling). This registry
# is a pure lookup, not a fallback-substitution policy-maker.
#
# get_icon() deliberately NOT built -- nothing in this project's UI
# consumes party icons yet (the switch menu is still text buttons); adding
# it now would be unused, untested surface.
#
# Two explicit resolution functions rather than one generic
# field-name-driven helper -- GDScript's Object.get()/set() reflection on
# STATIC (not instance) variables from within a static func is untested,
# unusual territory; two small, obviously-correct functions are safer than
# one clever one here.

const FRONT_DIR := "res://assets/sprites/pokemon/front"
const BACK_DIR := "res://assets/sprites/pokemon/back"

# Every front/back sprite sheet has a fixed 64x64-per-frame canvas
# (confirmed via direct pixel inspection, uniform across every species
# regardless of the Pokémon's own visual size). Front sheets are always
# 64x128 (2 frames, idle-bob animation). Back sheets are single-frame
# 64x64 for 385 of 386 species, EXCEPT Deoxys (#386), whose GBA-style back
# sheet is genuinely animated (64x128, 2 frames) -- found via
# sprite_registry_test.gd catching a real size-check failure, not assumed.
# Both get_front() and get_back() always slice to the top frame via this
# same FRAME_SIZE region, which is a safe no-op for every single-frame
# source (slicing a 64x64 region out of an already-64x64 image just
# returns the whole image unchanged).
const FRAME_SIZE := Vector2(64, 64)

static var _front_path_by_dex: Dictionary = {}
static var _back_path_by_dex: Dictionary = {}
static var _front_scanned := false
static var _back_scanned := false


static func get_front(dex: int) -> Texture2D:
	if not _front_scanned:
		_scan_dir(FRONT_DIR, _front_path_by_dex)
		_front_scanned = true
	var path: String = _front_path_by_dex.get(dex, "")
	if path.is_empty():
		return null
	var full_sheet: Texture2D = load(path)
	if full_sheet == null:
		return null
	# Slice to the top (first) frame only -- no animation in Phase 4a.
	var atlas := AtlasTexture.new()
	atlas.atlas = full_sheet
	atlas.region = Rect2(Vector2.ZERO, FRAME_SIZE)
	return atlas


static func get_back(dex: int) -> Texture2D:
	if not _back_scanned:
		_scan_dir(BACK_DIR, _back_path_by_dex)
		_back_scanned = true
	var path: String = _back_path_by_dex.get(dex, "")
	if path.is_empty():
		return null
	var full_sheet: Texture2D = load(path)
	if full_sheet == null:
		return null
	# [Found via sprite_registry_test.gd, GBA-style switch session] Back
	# sprites are single-frame 64x64 for 385 of 386 species, but Deoxys
	# (#386) has a genuinely animated 2-frame 64x128 back sheet under GBA
	# style. Always slicing to the top frame (rather than special-casing
	# just Deoxys) is both simpler and defensively correct -- a no-op for
	# every other species, since slicing a 64x64 region out of an
	# already-64x64 source just returns the whole image unchanged
	# (confirmed with Castform's single-frame front_gba.png earlier in
	# this same session).
	var atlas := AtlasTexture.new()
	atlas.atlas = full_sheet
	atlas.region = Rect2(Vector2.ZERO, FRAME_SIZE)
	return atlas


static func _scan_dir(dir_path: String, cache: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			var id_str := filename.substr(0, 4)
			if id_str.is_valid_int():
				cache[int(id_str)] = "%s/%s" % [dir_path, filename]
		filename = dir.get_next()
	dir.list_dir_end()
