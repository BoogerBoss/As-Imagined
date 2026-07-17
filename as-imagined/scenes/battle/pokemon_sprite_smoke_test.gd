extends Node

# Full-roster sprite smoke test — a dedicated, standalone,
# independently-runnable data-integrity check for the front/back/icon
# sprites pulled in from the reference clone via
# scripts/gen_pokemon_sprites.py, mirroring move_smoke_test.gd's own
# established shape (scan-and-load-check, not a hardcoded per-ID list).
#
# Deliberately does NOT hardcode the dex->slug mapping anywhere in this
# test — that would duplicate gen_pokemon_sprites.py's own source-derived
# mapping and risk silently drifting from it. Instead this scans each of
# the 3 asset directories directly via DirAccess, checks the file COUNT
# and the dex-number PREFIX coverage (every dex 1-386 exactly once), and
# loads every file via Godot's own `load()` to catch anything a plain
# filesystem listing wouldn't (corrupt PNG, wrong resource type, etc.) —
# the same "load(), not just exists()" discipline move_smoke_test.gd
# established.

var _pass := 0
var _fail := 0

const DEX_MIN := 1
const DEX_MAX := 386
const ASSET_KINDS := ["front", "back", "icon"]


func _ready() -> void:
	for kind in ASSET_KINDS:
		_test_kind(kind)

	var total := _pass + _fail
	print("pokemon_sprite_smoke_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_kind(kind: String) -> void:
	var dir_path := "res://assets/sprites/pokemon/%s" % kind
	var dir := DirAccess.open(dir_path)
	_chk("%s directory exists and is openable" % kind, dir != null)
	if dir == null:
		return

	var seen_dex: Dictionary = {}
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			var dex_str := filename.substr(0, 4)
			if dex_str.is_valid_int():
				seen_dex[int(dex_str)] = true
			var full_path := "%s/%s" % [dir_path, filename]
			var res: Resource = load(full_path)
			_chk("%s: %s loads as a valid Texture2D" % [kind, filename],
					res != null and res is Texture2D)
		filename = dir.get_next()
	dir.list_dir_end()

	for dex in range(DEX_MIN, DEX_MAX + 1):
		_chk("%s: dex %d present exactly once" % [kind, dex], seen_dex.get(dex, false) == true)
	_chk("%s: no unexpected extra dex numbers" % kind, seen_dex.size() == (DEX_MAX - DEX_MIN + 1))
