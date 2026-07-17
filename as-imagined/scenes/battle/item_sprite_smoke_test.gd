extends Node

# [M23.11 Phase 2] Data-integrity smoke test for the item icon pull
# (scripts/gen_item_sprites.py -> assets/sprites/items/) -- mirrors
# pokemon_sprite_smoke_test.gd's directory-scan-based shape (never
# hardcodes the expected file list, since that would duplicate -- and
# risk drifting from -- the copy step's own selection).
#
# Cross-checked directly against data/items/*.tres (the real, authoritative
# scope every real ItemData instance is drawn from -- the same source
# gen_item_sprites.py itself reads) rather than just asserting "every file
# present loads" -- this is what lets the test catch a MISMATCHED or
# INCOMPLETE pull (an item added to data/items/ later with no
# corresponding icon, or an icon file present with no real ItemData behind
# it) rather than only a corrupt-file regression.

var _pass := 0
var _fail := 0

const ITEMS_DATA_DIR := "res://data/items"
const ICON_DIR := "res://assets/sprites/items"


func _ready() -> void:
	_test_icons_match_real_items()

	var total := _pass + _fail
	print("item_sprite_smoke_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _real_item_ids() -> Array[int]:
	var ids: Array[int] = []
	var dir := DirAccess.open(ITEMS_DATA_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".tres"):
			var digits := filename.replace("item_", "").replace(".tres", "")
			if digits.is_valid_int():
				ids.append(int(digits))
		filename = dir.get_next()
	dir.list_dir_end()
	return ids


func _test_icons_match_real_items() -> void:
	var real_ids := _real_item_ids()
	_chk("data/items/ has at least one real ItemData file", real_ids.size() > 0)

	var dir := DirAccess.open(ICON_DIR)
	_chk("icon directory exists and is openable", dir != null)
	if dir == null:
		return

	# icon_id_by_dex : dex(int) -> filename(String), built once from the
	# real on-disk icon set (ID-prefixed, e.g. "0001_poke_ball.png").
	var icon_filename_by_id: Dictionary = {}
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			var id_str := filename.substr(0, 4)
			if id_str.is_valid_int():
				icon_filename_by_id[int(id_str)] = filename
		filename = dir.get_next()
	dir.list_dir_end()

	# Every real item must have a matching icon -- catches an incomplete pull.
	for item_id in real_ids:
		_chk("item %d has a corresponding icon file" % item_id,
				icon_filename_by_id.has(item_id))
		if icon_filename_by_id.has(item_id):
			var full_path := "%s/%s" % [ICON_DIR, icon_filename_by_id[item_id]]
			var res: Resource = load(full_path)
			_chk("item %d icon loads as a valid Texture2D" % item_id,
					res != null and res is Texture2D)
			if res is Texture2D:
				var size: Vector2 = (res as Texture2D).get_size()
				_chk("item %d icon has nonzero dimensions" % item_id,
						size.x > 0 and size.y > 0)

	# Every icon must correspond to a real item -- catches an orphaned pull
	# (an icon copied for an item ID that isn't actually modeled here).
	var real_id_set: Dictionary = {}
	for item_id in real_ids:
		real_id_set[item_id] = true
	for icon_id in icon_filename_by_id.keys():
		_chk("icon-only item %d has a corresponding real ItemData file" % icon_id,
				real_id_set.has(icon_id))

	_chk("icon count matches real item count exactly",
			icon_filename_by_id.size() == real_ids.size())
