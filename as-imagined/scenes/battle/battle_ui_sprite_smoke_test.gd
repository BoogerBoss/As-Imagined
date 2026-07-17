extends Node

# [M23.11 Phase 1] Data-integrity smoke test for the battle_interface/,
# types/, and text_window/ asset pulls -- mirrors move_smoke_test.gd's own
# scan-and-load shape (load() every file, assert non-null and the right
# Resource type), and pokemon_sprite_smoke_test.gd's own "scan the real
# directory, don't hardcode a file list" discipline, so this can't
# silently drift from whatever's actually on disk.
#
# Unlike the Pokémon sprite pull (dex-number-prefixed filenames, ID
# coverage checked 1-386) this asset set has no numeric ID scheme at all --
# it's a small, fixed, hand-curated file list (mechanic-excluded and
# "unused"-flagged source files deliberately left out, see
# docs/m23_recon.md's M23.11 Phase 1 entry) -- so this test's job is
# narrower: every file that IS present loads correctly as a valid,
# non-empty Texture2D. It does not assert against a hardcoded expected
# filename list, since that would duplicate the copy step's own file
# selection and risk drifting from it independently.

var _pass := 0
var _fail := 0

const ASSET_DIRS := [
	"res://assets/sprites/battle_ui/interface",
	"res://assets/sprites/battle_ui/types",
	"res://assets/sprites/battle_ui/text_window",
]


func _ready() -> void:
	for dir_path in ASSET_DIRS:
		_test_dir(dir_path)

	var total := _pass + _fail
	print("battle_ui_sprite_smoke_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	_chk("%s directory exists and is openable" % dir_path, dir != null)
	if dir == null:
		return

	var file_count := 0
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			file_count += 1
			var full_path := "%s/%s" % [dir_path, filename]
			var res: Resource = load(full_path)
			_chk("%s: %s loads as a valid Texture2D" % [dir_path, filename],
					res != null and res is Texture2D)
			if res is Texture2D:
				var size: Vector2 = (res as Texture2D).get_size()
				_chk("%s: %s has nonzero dimensions" % [dir_path, filename],
						size.x > 0 and size.y > 0)
		filename = dir.get_next()
	dir.list_dir_end()

	_chk("%s: at least one file found" % dir_path, file_count > 0)
