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
#
# [M26 polish batch, item 1] Each id now resolves to 3 SEPARATE files
# (<id>_bg.png/<id>_base0.png/<id>_base1.png, 33 files total) instead of 1
# flattened composite -- see gen_battle_backgrounds_emerald.py's own doc
# comment and BattleBackgroundRegistry's own updated doc comment for why.

var _pass := 0
var _fail := 0

const BACKGROUND_DIR := "res://assets/sprites/battle_backgrounds"

const EXPECTED_IDS := [
	"building", "cave", "long_grass", "pond_water", "rock", "sand", "sky",
	"stadium", "tall_grass", "underwater", "water",
]

# suffix -> expected (width, height), per this session's own direct PIL
# inspection of the Emerald UI Pack's own source files (uniform across all
# 11 mapped names, confirmed before writing gen_battle_backgrounds_emerald
# .py's own copy-only, no-resize implementation).
const EXPECTED_LAYER_SIZES := {
	"bg": Vector2(512, 288),
	"base0": Vector2(512, 64),
	"base1": Vector2(256, 128),
}


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

	var found_ids := {}
	var file_count := 0
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".png"):
			file_count += 1
			var stem := filename.get_basename()
			var full_path := "%s/%s" % [BACKGROUND_DIR, filename]
			var res: Resource = load(full_path)
			_chk("%s: %s loads as a valid Texture2D" % [BACKGROUND_DIR, filename],
					res != null and res is Texture2D)
			var matched_layer := ""
			for layer_suffix in EXPECTED_LAYER_SIZES.keys():
				if stem.ends_with("_" + layer_suffix):
					matched_layer = layer_suffix
					found_ids[stem.substr(0, stem.length() - layer_suffix.length() - 1)] = true
					break
			_chk("%s: filename matches a known <id>_{bg,base0,base1} layer suffix" % filename,
					not matched_layer.is_empty())
			if res is Texture2D and not matched_layer.is_empty():
				var size: Vector2 = (res as Texture2D).get_size()
				var expected: Vector2 = EXPECTED_LAYER_SIZES[matched_layer]
				_chk("%s: %s is the expected %s size for the '%s' layer" %
						[BACKGROUND_DIR, filename, expected, matched_layer],
						size == expected)
		filename = dir.get_next()
	dir.list_dir_end()

	_chk("exactly 33 background files found on disk (11 ids x 3 layers)", file_count == 33)
	var found_ids_sorted: Array[String] = []
	for id in found_ids.keys():
		found_ids_sorted.append(id)
	found_ids_sorted.sort()
	var expected_sorted := EXPECTED_IDS.duplicate()
	expected_sorted.sort()
	_chk("the 11 unique ids derived from the 33 files match the expected 11 base-tileset ids",
			found_ids_sorted == expected_sorted)


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
		var bg_tex := BattleBackgroundRegistry.get_background_texture(id)
		_chk("get_background_texture(%s) resolves to a real Texture2D" % id,
				bg_tex != null)
		var player_tex := BattleBackgroundRegistry.get_player_base_texture(id)
		_chk("get_player_base_texture(%s) resolves to a real Texture2D" % id,
				player_tex != null)
		var enemy_tex := BattleBackgroundRegistry.get_enemy_base_texture(id)
		_chk("get_enemy_base_texture(%s) resolves to a real Texture2D" % id,
				enemy_tex != null)
		_chk("%s's bg/base0/base1 textures are three genuinely distinct resources" % id,
				bg_tex != player_tex and bg_tex != enemy_tex and player_tex != enemy_tex)

	_chk("display_name('tall_grass') == 'Tall Grass'",
			BattleBackgroundRegistry.display_name("tall_grass") == "Tall Grass")
	_chk("display_name('rock') == 'Rock'",
			BattleBackgroundRegistry.display_name("rock") == "Rock")


func _test_registry_unresolvable_id() -> void:
	var tex := BattleBackgroundRegistry.get_background_texture("not_a_real_background")
	_chk("get_background_texture() returns null for an unresolvable id (not a crash)",
			tex == null)
	var player_tex := BattleBackgroundRegistry.get_player_base_texture("not_a_real_background")
	_chk("get_player_base_texture() returns null for an unresolvable id (not a crash)",
			player_tex == null)
	var enemy_tex := BattleBackgroundRegistry.get_enemy_base_texture("not_a_real_background")
	_chk("get_enemy_base_texture() returns null for an unresolvable id (not a crash)",
			enemy_tex == null)
