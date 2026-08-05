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
# [M26E3-2] get_icon() -- the 386 already-pulled party icon sheets' first
# real consumer (SwitchSelectScreen). Mirrors get_front()'s exact frame-
# slicing shape: a 32x64 2-frame vertical sheet, frame 0/1 selected the
# same way get_front() already does for its own 2-frame idle-bob.
#
# Two explicit resolution functions rather than one generic
# field-name-driven helper -- GDScript's Object.get()/set() reflection on
# STATIC (not instance) variables from within a static func is untested,
# unusual territory; two small, obviously-correct functions are safer than
# one clever one here.

const FRONT_DIR := "res://assets/sprites/pokemon/front"
const BACK_DIR := "res://assets/sprites/pokemon/back"
const ICON_DIR := "res://assets/sprites/pokemon/icon"
const ICON_FRAME_SIZE := Vector2(32, 32)

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

# [M26c battle-UI polish] Real per-species `frontPicYOffset` data (see
# gen_sprite_y_offsets.py's own doc comment for the full source citation) --
# "the number of pixels between the drawn pixel area and the bottom edge" of
# the 64x64 front-sprite canvas, the real mechanism pokeemerald_expansion
# itself uses so every species' front sprite appears to stand at a
# consistent height despite wildly varying transparent padding within that
# uniform canvas. Lazily loaded once, matching _scan_dir's own established
# lazy-cache convention. Returns 0 (no padding assumed) for an unresolvable
# dex, the safe default matching get_front()'s own "unknown dex" handling.
const Y_OFFSET_PATH := "res://data/sprite_y_offsets.json"

static var _front_path_by_dex: Dictionary = {}
static var _back_path_by_dex: Dictionary = {}
static var _icon_path_by_dex: Dictionary = {}
static var _front_scanned := false
static var _back_scanned := false
static var _icon_scanned := false
static var _y_offset_by_dex: Dictionary = {}
static var _y_offset_loaded := false


static func get_front_y_offset(dex: int) -> int:
	if not _y_offset_loaded:
		_load_y_offsets()
		_y_offset_loaded = true
	return _y_offset_by_dex.get(dex, 0)


static func _load_y_offsets() -> void:
	var f := FileAccess.open(Y_OFFSET_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null or not (parsed is Dictionary):
		return
	# JSON object keys are always Strings; JSON numeric values decode as
	# float -- both cast explicitly here (the same float-key/float-value
	# gotcha this project's own CLAUDE.md gdscript-gotchas memory documents).
	for key: String in (parsed as Dictionary).keys():
		_y_offset_by_dex[int(key)] = int((parsed as Dictionary)[key])


# [M23.11 Phase 4c] `frame` selects which of the (up to) 2 idle-animation
# frames to slice -- confirmed via direct source inspection
# (species_info's own `.frontAnimFrames = ANIM_FRAMES(ANIMCMD_FRAME(0,
# 30), ANIMCMD_FRAME(1, 30), ANIMCMD_FRAME(0, 1))`, e.g. Bulbasaur) that
# frame 0/frame 1 genuinely are the two real idle-bob frames the reference
# engine itself alternates between, not a guessed convention. Defaults to
# 0 so every pre-Phase-4c call site's behavior is unchanged.
#
# Single-frame species (Unown, Castform under GBA style) have a 64x64
# source with no real second frame to slice -- gracefully falls back to
# frame 0 rather than requesting an out-of-bounds AtlasTexture region,
# giving a correctly-static (non-crashing, non-blank) result.
static func get_front(dex: int, frame: int = 0) -> Texture2D:
	if not _front_scanned:
		_scan_dir(FRONT_DIR, _front_path_by_dex)
		_front_scanned = true
	var path: String = _front_path_by_dex.get(dex, "")
	if path.is_empty():
		return null
	var full_sheet: Texture2D = load(path)
	if full_sheet == null:
		return null
	var has_second_frame: bool = full_sheet.get_height() >= FRAME_SIZE.y * 2
	var actual_frame: int = frame if has_second_frame else 0
	var atlas := AtlasTexture.new()
	atlas.atlas = full_sheet
	atlas.region = Rect2(0, actual_frame * FRAME_SIZE.y, FRAME_SIZE.x, FRAME_SIZE.y)
	return atlas


static func get_icon(dex: int, frame: int = 0) -> Texture2D:
	if not _icon_scanned:
		_scan_dir(ICON_DIR, _icon_path_by_dex)
		_icon_scanned = true
	var path: String = _icon_path_by_dex.get(dex, "")
	if path.is_empty():
		return null
	var full_sheet: Texture2D = load(path)
	if full_sheet == null:
		return null
	var has_second_frame: bool = full_sheet.get_height() >= ICON_FRAME_SIZE.y * 2
	var actual_frame: int = frame if has_second_frame else 0
	var atlas := AtlasTexture.new()
	atlas.atlas = full_sheet
	atlas.region = Rect2(0, actual_frame * ICON_FRAME_SIZE.y, ICON_FRAME_SIZE.x, ICON_FRAME_SIZE.y)
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
	#
	# [M23.11 Phase 4c] Deliberately NOT given a `frame` parameter like
	# get_front() gained -- confirmed via direct source inspection
	# (include/pokemon.h's SpeciesInfo struct has a single `backAnimId`
	# byte and NO accompanying `backAnimFrames` array field at all, unlike
	# `.frontAnimFrames`) that back sprites don't use frame-swap idle
	# animation in the real engine -- `backAnimId` drives a single
	# positional effect (e.g. Bulbasaur's `BACK_ANIM_DIP_RIGHT_SIDE`)
	# applied to ONE static frame, not a 2-frame alternation. Deoxys's own
	# second back frame is therefore NOT idle-bob content and is
	# deliberately left unanimated/unused here -- adding a `frame` param
	# here would invite a caller to wire up an idle-bob loop using content
	# that was never meant for that purpose.
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
