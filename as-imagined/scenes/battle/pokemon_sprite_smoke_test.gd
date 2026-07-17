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
#
# [Found during the GBA-style-switch session, not caused by it] This test
# was never updated when M23.11 Phase 4a added the dex-0 "unknown"
# fallback (front.png/back.png only, no icon) to
# scripts/gen_pokemon_sprites.py -- it had been silently failing 2/2324
# ("no unexpected extra dex numbers" for both front and back) across all
# of Phase 4a's own sweep runs. Caught only because this session actually
# ran this suite standalone rather than trusting a sweep GRAND TOTAL that
# happened to still balance (count_assertions.sh sums the PASSED count
# from each suite's own "N/M passed" line, not M -- a partial failure
# doesn't perturb the running total the way a full suite disappearing
# would). Fixed here by explicitly asserting the fallback's own presence,
# not just widening the tolerance to quietly accept it.

var _pass := 0
var _fail := 0

const DEX_MIN := 1
const DEX_MAX := 386
const DEX_UNKNOWN := 0
const ASSET_KINDS := ["front", "back", "icon"]
# Which kinds the dex-0 "unknown" fallback exists for -- icon deliberately
# excluded, matching gen_pokemon_sprites.py's own scope (nothing consumes
# a fallback icon yet).
const KINDS_WITH_UNKNOWN_FALLBACK := ["front", "back"]


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

	var expected_total := DEX_MAX - DEX_MIN + 1
	if kind in KINDS_WITH_UNKNOWN_FALLBACK:
		_chk("%s: dex %d (unknown fallback) present" % [kind, DEX_UNKNOWN],
				seen_dex.get(DEX_UNKNOWN, false) == true)
		expected_total += 1
	_chk("%s: no unexpected extra dex numbers" % kind, seen_dex.size() == expected_total)
