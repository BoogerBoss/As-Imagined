class_name TrainerPicRegistry
extends RefCounted

# [M24a] Convention-based trainer-portrait loader — mirrors MoveRegistry/
# ItemRegistry/TrainerRegistry exactly.
#
# Deliberately a SEPARATE registry from TrainerRegistry, not a convenience
# method on it — see docs/m24_recon.md section 1.4: 854 real trainers share
# only 93 distinct Pic values (e.g. "Swimmer M" alone covers dozens of
# trainers), so trainer identity and portrait identity are two genuinely
# different id spaces, not one conflated with the other.
#
# Files live at: res://data/trainer_pics/trainer_pic_NNNN.tres
# where NNNN is pic_id zero-padded to 4 digits (sorted-alphabetical index of
# the distinct "Pic:" source string, assigned by gen_trainer_data.py).


static func get_trainer_pic(id: int) -> TrainerPicData:
	var path := "res://data/trainer_pics/trainer_pic_%04d.tres" % id
	if not ResourceLoader.exists(path):
		push_warning("TrainerPicRegistry: no file for trainer_pic id %d (%s)" % [id, path])
		return null
	return ResourceLoader.load(path) as TrainerPicData


# [M23.11 Phase 3] Portrait-art lookup, mirroring SpriteRegistry's own
# lazy-directory-scan-and-cache convention exactly (see sprite_registry.gd's
# doc comment) rather than a pure "%04d.png" path template — every filename
# here also embeds the source's own front_pic slug (e.g.
# "0006_aroma_lady.png") for on-disk browsability, so the leading 4-digit
# numeric prefix is what's actually keyed on, not the full name.
#
# Returns null for an unresolvable id (matching get_trainer_pic()'s own
# "return null, let the caller decide the fallback" convention) — this is a
# pure lookup, not a fallback-substitution policy-maker.
const PORTRAIT_DIR := "res://assets/sprites/trainers/portraits"

static var _portrait_path_by_id: Dictionary = {}
static var _portrait_scanned := false


static func get_portrait_texture(pic_id: int) -> Texture2D:
	if not _portrait_scanned:
		_scan_portrait_dir()
		_portrait_scanned = true
	var path: String = _portrait_path_by_id.get(pic_id, "")
	if path.is_empty():
		return null
	return load(path) as Texture2D


static func _scan_portrait_dir() -> void:
	var dir := DirAccess.open(PORTRAIT_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			var id_str := filename.substr(0, 4)
			if id_str.is_valid_int():
				_portrait_path_by_id[int(id_str)] = "%s/%s" % [PORTRAIT_DIR, filename]
		filename = dir.get_next()
	dir.list_dir_end()
