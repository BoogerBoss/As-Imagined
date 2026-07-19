class_name BattleBackgroundRegistry
extends RefCounted

# [M23.11 Phase 5a] Battle-background texture lookup — mirrors
# TrainerPicRegistry's own lazy-directory-scan-and-cache convention exactly
# (see trainer_pic_registry.gd's doc comment): rather than a numeric-ID
# path template, this scans res://assets/sprites/battle_backgrounds/ once
# and caches path-by-id, where id is each file's own name stem (e.g.
# "rock", "tall_grass") — matching gen_battle_backgrounds.py's own output
# naming (no numeric battle-environment-ID concept exists anywhere else in
# this project yet, so a name-keyed lookup is the honest shape rather than
# inventing one).
#
# Returns null for an unresolvable id (matching every other Registry's own
# "return null, let the caller decide" convention in this project).

const BACKGROUND_DIR := "res://assets/sprites/battle_backgrounds"

static var _path_by_id: Dictionary = {}
static var _scanned := false


static func get_background_texture(id: String) -> Texture2D:
	_ensure_scanned()
	var path: String = _path_by_id.get(id, "")
	if path.is_empty():
		return null
	return load(path) as Texture2D


# Sorted list of every real background id currently on disk — the manual
# picker (battle_setup_screen.gd) populates its dropdown directly from
# this rather than a hardcoded 11-name list, so a future background added
# to the asset directory shows up automatically.
static func list_background_ids() -> Array[String]:
	_ensure_scanned()
	var ids: Array[String] = []
	for id in _path_by_id.keys():
		ids.append(id)
	ids.sort()
	return ids


# "tall_grass" -> "Tall Grass" (String.capitalize() already does the
# snake_case-to-Title-Case conversion this project needs, no custom
# transform required).
static func display_name(id: String) -> String:
	return id.capitalize()


static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	var dir := DirAccess.open(BACKGROUND_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			var id := filename.get_basename()
			_path_by_id[id] = "%s/%s" % [BACKGROUND_DIR, filename]
		filename = dir.get_next()
	dir.list_dir_end()
