class_name BattleBackgroundRegistry
extends RefCounted

# [M23.11 Phase 5a] Battle-background texture lookup — mirrors
# TrainerPicRegistry's own lazy-directory-scan-and-cache convention exactly
# (see trainer_pic_registry.gd's doc comment): rather than a numeric-ID
# path template, this scans res://assets/sprites/battle_backgrounds/ once
# and caches path-by-id, where id is each file's own name stem (e.g.
# "rock", "tall_grass") — this naming was originally established by Phase
# 5a's own gen_battle_backgrounds.py (since deleted, M25e — see this file's
# own asset-directory doc history in CLAUDE.md) and preserved unchanged
# when M25e replaced 9 of the 11 PNGs with a direct CFRU pull (no numeric
# battle-environment-ID concept exists anywhere else in this project yet,
# so a name-keyed lookup is the honest shape rather than inventing one).
#
# [M26 polish batch, item 1] Each id now resolves to THREE separate files
# (<id>_bg.png/<id>_base0.png/<id>_base1.png) instead of one flattened
# composite — see gen_battle_backgrounds_emerald.py's own doc comment for
# why (the two base layers are now real, independently-positioned scene
# nodes, not baked into the backdrop at generation time). The scan derives
# each unique id by stripping whichever of the three known suffixes a
# filename carries, so "<id>_bg.png"/"<id>_base0.png"/"<id>_base1.png" all
# collapse to the same id rather than being treated as 3 separate ids.
#
# Returns null for an unresolvable id/layer (matching every other
# Registry's own "return null, let the caller decide" convention in this
# project).

const BACKGROUND_DIR := "res://assets/sprites/battle_backgrounds"

# id -> {"bg": path, "base0": path, "base1": path}. A layer key is only
# ever present if that exact file exists on disk — a partially-populated
# id (e.g. a bg with no matching base0/base1 yet) degrades gracefully
# rather than crashing, matching get_background_texture()'s own existing
# null-on-missing contract.
static var _paths_by_id: Dictionary = {}
static var _scanned := false


static func get_background_texture(id: String) -> Texture2D:
	return _get_layer_texture(id, "bg")


static func get_player_base_texture(id: String) -> Texture2D:
	return _get_layer_texture(id, "base0")


static func get_enemy_base_texture(id: String) -> Texture2D:
	return _get_layer_texture(id, "base1")


static func _get_layer_texture(id: String, layer: String) -> Texture2D:
	_ensure_scanned()
	var layers: Dictionary = _paths_by_id.get(id, {})
	var path: String = layers.get(layer, "")
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
	for id in _paths_by_id.keys():
		ids.append(id)
	ids.sort()
	return ids


# "tall_grass" -> "Tall Grass" (String.capitalize() already does the
# snake_case-to-Title-Case conversion this project needs, no custom
# transform required).
static func display_name(id: String) -> String:
	return id.capitalize()


const _LAYER_SUFFIXES: Array[String] = ["_bg", "_base0", "_base1"]


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
			var stem := filename.get_basename()
			for suffix: String in _LAYER_SUFFIXES:
				if stem.ends_with(suffix):
					var id := stem.substr(0, stem.length() - suffix.length())
					var layer: String = suffix.substr(1)  # "_bg" -> "bg", etc.
					if not _paths_by_id.has(id):
						_paths_by_id[id] = {}
					_paths_by_id[id][layer] = "%s/%s" % [BACKGROUND_DIR, filename]
					break
		filename = dir.get_next()
	dir.list_dir_end()
