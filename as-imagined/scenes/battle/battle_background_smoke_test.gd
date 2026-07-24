extends Node

# [M23.11 Phase 5a] Data-integrity smoke test for the battle-background
# asset pull -- mirrors battle_ui_sprite_smoke_test.gd's own directory-
# scan-style precedent (scan the real directory, don't hardcode a file
# list that could drift from what's actually on disk) plus a direct
# exercise of BattleBackgroundRegistry's own API (list/get/display_name),
# not just a raw DirAccess scan.
#
# Unlike battle_ui_sprite_smoke_test.gd's asset set (no fixed expected
# count), this pull DOES have a known, fixed target -- exactly the 11 real
# base tilesets gen_battle_backgrounds.py's own TILESET_IDS enumerates
# (see docs/m23_11_phase5_recon.md Section 0 item 4 -- palette recolors
# are deferred to 5d, not part of this pull at all) -- so this test also
# checks the count and the specific expected ids, not just "every present
# file loads."

var _pass := 0
var _fail := 0

const BACKGROUND_DIR := "res://assets/sprites/battle_backgrounds"

const EXPECTED_IDS := [
	"building", "cave", "long_grass", "pond_water", "rock", "sand", "sky",
	"stadium", "tall_grass", "underwater", "water",
]


func _ready() -> void:
	_test_directory_scan()
	_test_registry_list()
	_test_registry_get_and_display_name()
	_test_registry_unresolvable_id()

	var total := _pass + _fail
	print("battle_background_smoke_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Raw directory scan (mirrors battle_ui_sprite_smoke_test.gd exactly) ──

func _test_directory_scan() -> void:
	var dir := DirAccess.open(BACKGROUND_DIR)
	_chk("%s directory exists and is openable" % BACKGROUND_DIR, dir != null)
	if dir == null:
		return

	var found_ids: Array[String] = []
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			found_ids.append(filename.get_basename())
			var full_path := "%s/%s" % [BACKGROUND_DIR, filename]
			var res: Resource = load(full_path)
			_chk("%s: %s loads as a valid Texture2D" % [BACKGROUND_DIR, filename],
					res != null and res is Texture2D)
			if res is Texture2D:
				var size: Vector2 = (res as Texture2D).get_size()
				# [M26c battle-UI polish] All 11 ids now source from the vendored
				# Emerald UI Pack (see gen_battle_backgrounds_emerald.py's own
				# mapping doc comment) — every `*_bg.png` in that pack is a
				# single, already-composited, uniform 512×288 image, superseding
				# both M25e's mixed 240×160 (unreplaced Phase 5a reconstruction)/
				# 256×112 (CFRU pull) shapes documented here previously.
				_chk("%s: %s is 512x288 (Emerald UI Pack battleback)" % [BACKGROUND_DIR, filename],
						size.x == 512 and size.y == 288)
		filename = dir.get_next()
	dir.list_dir_end()

	_chk("exactly 11 background files found on disk", found_ids.size() == 11)
	found_ids.sort()
	var expected_sorted := EXPECTED_IDS.duplicate()
	expected_sorted.sort()
	_chk("the 11 files match the expected 11 base-tileset ids exactly",
			found_ids == expected_sorted)


# ── BattleBackgroundRegistry API ─────────────────────────────────────────

func _test_registry_list() -> void:
	var ids := BattleBackgroundRegistry.list_background_ids()
	_chk("BattleBackgroundRegistry.list_background_ids() returns 11 ids",
			ids.size() == 11)
	var expected_sorted := EXPECTED_IDS.duplicate()
	expected_sorted.sort()
	_chk("list_background_ids() is sorted and matches the expected 11 exactly",
			ids == expected_sorted)


func _test_registry_get_and_display_name() -> void:
	for id in EXPECTED_IDS:
		var tex := BattleBackgroundRegistry.get_background_texture(id)
		_chk("get_background_texture(%s) resolves to a real Texture2D" % id,
				tex != null)

	_chk("display_name('tall_grass') == 'Tall Grass'",
			BattleBackgroundRegistry.display_name("tall_grass") == "Tall Grass")
	_chk("display_name('rock') == 'Rock'",
			BattleBackgroundRegistry.display_name("rock") == "Rock")


func _test_registry_unresolvable_id() -> void:
	var tex := BattleBackgroundRegistry.get_background_texture("not_a_real_background")
	_chk("get_background_texture() returns null for an unresolvable id (not a crash)",
			tex == null)
