class_name AnimData
extends RefCounted

# [M36B] Loader/cache for the four JSON products of M36A's extraction, plus
# the sheet textures they point at. Scope of record: docs/m26_f1_recon.md.
#
# Everything is static and lazily loaded once per run: the program is ~1.3 MB
# of JSON and is read exactly once, not per animation. Accessors return the
# raw extracted structures rather than wrapper objects -- the VM reads them
# directly, and keeping them as Dictionaries means the on-disk shape and the
# runtime shape can never drift apart.
#
# Nothing here interprets an animation; that is AnimScriptVM's job. This class
# only answers "what does the data say".

const DATA_DIR := "res://data/battle_anims"
const SHEET_DIR := "res://assets/sprites/battle_anims"
const BG_DIR := "res://assets/sprites/battle_anims/backgrounds"

static var _scripts: Dictionary = {}
static var _tags: Dictionary = {}
static var _templates: Dictionary = {}
static var _frames: Dictionary = {}
static var _sheet_index: Dictionary = {}
static var _sheet_cache: Dictionary = {}
static var _bg_index: Dictionary = {}
static var _bg_cache: Dictionary = {}
static var _bg_by_id: Dictionary = {}
static var _loaded := false
static var _load_error := ""


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


# Idempotent. Returns false (and records why) if any product is missing, so
# callers can degrade to the legacy hit-effect path instead of erroring --
# the same "absent data must not crash the battle" posture every other
# registry in this project takes.
static func ensure_loaded() -> bool:
	if _loaded:
		return _load_error == ""
	_loaded = true

	var scripts := _read_json(DATA_DIR + "/scripts.json")
	var tags := _read_json(DATA_DIR + "/tags.json")
	var templates := _read_json(DATA_DIR + "/templates.json")
	var frames := _read_json(DATA_DIR + "/frames.json")
	var index := _read_json(SHEET_DIR + "/index.json")
	var bg_index := _read_json(BG_DIR + "/index.json")

	for pair in [["scripts.json", scripts], ["tags.json", tags],
			["templates.json", templates], ["frames.json", frames],
			["index.json", index]]:
		if (pair[1] as Dictionary).is_empty():
			_load_error = "battle-anim data missing or unparseable: %s" % pair[0]
			push_warning(_load_error)
			return false

	_scripts = scripts
	_tags = tags.get("tags", {})
	_templates = templates.get("templates", {})
	_frames = frames
	_sheet_index = index.get("sprites", {})
	# Backgrounds are optional: M36E1 added them, and an older checkout that
	# has not run the generator should degrade to "no background" rather than
	# refusing to load the whole animation system.
	_bg_index = bg_index.get("backgrounds", {})
	# BG_* ids arrive in the command stream as the INTEGER the assembler
	# emitted, so the reverse map is built from the same constant table the
	# extractor recorded -- no second source of truth.
	for name in _scripts.get("constants", {}):
		var key := str(name)
		if key.begins_with("BG_"):
			_bg_by_id[int(_scripts["constants"][key])] = key
	return true


static func load_error() -> String:
	return _load_error


# ── The command program ───────────────────────────────────────────────────

static func commands() -> Array:
	return _scripts.get("commands", [])


static func labels() -> Dictionary:
	return _scripts.get("labels", {})


static func label_index(label: String) -> int:
	# -1 rather than an error: an unknown label is a fallback trigger, not a
	# crash, and the M36A suite already guarantees no *extracted* reference
	# dangles -- this guards hand-passed labels only.
	return int(_scripts.get("labels", {}).get(label, -1))


static func opcode_signatures() -> Dictionary:
	return _scripts.get("meta", {}).get("opcode_signatures", {})


# ── Dispatch tables ───────────────────────────────────────────────────────

static func script_for_move(move_id: int) -> String:
	return str(_scripts.get("moves", {}).get(str(move_id), ""))


static func script_for_general(name: String) -> String:
	var row: Dictionary = _scripts.get("general", {}).get(name, {})
	return str(row.get("label", ""))


static func script_for_status(name: String) -> String:
	var row: Dictionary = _scripts.get("status", {}).get(name, {})
	return str(row.get("label", ""))


static func script_for_special(name: String) -> String:
	var row: Dictionary = _scripts.get("special", {}).get(name, {})
	return str(row.get("label", ""))


# ── Templates, tags, sheets, frames ───────────────────────────────────────

static func template(name: String) -> Dictionary:
	return _templates.get(name, {})


static func has_template(name: String) -> bool:
	return _templates.has(name)


static func tag_row(tag_name: String) -> Dictionary:
	return _tags.get(tag_name, {})


# The sheet for an ANIM_TAG, loaded once and cached. Returns null for the two
# legitimately-empty NULL rows and for any tag whose sheet was not pulled
# (e.g. a template using a non-ANIM_TAG tile tag).
static func sheet_for_tag(tag_name: String) -> Texture2D:
	if _sheet_cache.has(tag_name):
		return _sheet_cache[tag_name]
	var row: Dictionary = _sheet_index.get(tag_name, {})
	if row.is_empty():
		_sheet_cache[tag_name] = null
		return null
	var tex := load("%s/%s" % [SHEET_DIR, row.get("file", "")]) as Texture2D
	_sheet_cache[tag_name] = tex
	return tex


# ── Backgrounds (M36E) ────────────────────────────────────────────────────

# The BG_* name for the integer a `fadetobg` carries, or "" if unknown.
static func bg_name_for_id(bg_id: int) -> String:
	return str(_bg_by_id.get(bg_id, ""))


static func has_background(bg_name: String) -> bool:
	return _bg_index.has(bg_name)


static func background_texture(bg_name: String) -> Texture2D:
	if _bg_cache.has(bg_name):
		return _bg_cache[bg_name]
	var row: Dictionary = _bg_index.get(bg_name, {})
	if row.is_empty():
		_bg_cache[bg_name] = null
		return null
	var tex := load("%s/%s" % [BG_DIR, row.get("file", "")]) as Texture2D
	_bg_cache[bg_name] = tex
	return tex


static func background_count() -> int:
	return _bg_index.size()


# The 16 colours, IN PALETTE ORDER, that the extraction applied to this
# background. Needed only by the palette-cycling behaviors: a composited RGBA
# image records which colour each pixel ended up as, not which palette SLOT it
# came from, so the rotation cannot be derived from the texture alone.
static func background_palette(bg_name: String) -> PackedColorArray:
	var out := PackedColorArray()
	var row: Dictionary = _bg_index.get(bg_name, {})
	for entry in row.get("palette_colors", []):
		var rgb: Array = entry
		if rgb.size() < 3:
			continue
		out.append(Color8(int(rgb[0]), int(rgb[1]), int(rgb[2])))
	return out


static func sheet_row(tag_name: String) -> Dictionary:
	return _sheet_index.get(tag_name, {})


# A template's frame sequences, already resolved through its (file-qualified)
# table key and its offset -- see M36A's note on templates that deliberately
# point part-way into a shared table. Returns an Array of sequences, each a
# list of {tile, duration, ...} steps.
static func anim_sequences_for(template_name: String) -> Array:
	var t: Dictionary = template(template_name)
	var key: Variant = t.get("anims_key")
	if key == null:
		return []
	var table: Array = _frames.get("anim_tables", {}).get(str(key), [])
	var offset: int = int(t.get("anims_offset", 0))
	var out: Array = []
	for i in range(offset, table.size()):
		out.append(_frames.get("anims", {}).get(str(table[i]), []))
	return out


static func affine_sequences_for(template_name: String) -> Array:
	var t: Dictionary = template(template_name)
	var key: Variant = t.get("affine_anims_key")
	if key == null:
		return []
	var table: Array = _frames.get("affine_tables", {}).get(str(key), [])
	var offset: int = int(t.get("affine_anims_offset", 0))
	var out: Array = []
	for i in range(offset, table.size()):
		out.append(_frames.get("affine", {}).get(str(table[i]), []))
	return out


# Test/tooling seam: forget everything so a suite can reload from disk.
static func _reset_for_tests() -> void:
	_scripts = {}
	_tags = {}
	_templates = {}
	_frames = {}
	_sheet_index = {}
	_sheet_cache = {}
	_bg_index = {}
	_bg_cache = {}
	_bg_by_id = {}
	_loaded = false
	_load_error = ""
