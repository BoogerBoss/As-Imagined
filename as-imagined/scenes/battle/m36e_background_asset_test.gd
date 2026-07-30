extends Node

# [M36E1] Data-integrity suite for the battle-anim BACKGROUND pull.
#
# Backgrounds are composited, not copied: each is a tilemap over a tile sheet
# with per-cell flip flags, so a decode bug produces a plausible-looking image
# rather than an obvious failure. These assertions therefore check the
# properties a correct decode must have, not merely that files exist.

var _pass := 0
var _fail := 0

const DIR := "res://assets/sprites/battle_anims/backgrounds"

# The reference's own table length. If a reference update changes it, this
# should fail loudly rather than let the recon's figures go stale.
const EXPECTED_TABLE_ENTRIES := 84
const TILEMAP_WIDTH_PX := 256  # 32 cells x 8 px, always


func _ready() -> void:
	var index := _read_json(DIR + "/index.json")
	if index.is_empty():
		print("m36e_background_asset_test: index.json missing or unparseable")
		print("FAILED")
		get_tree().quit(1)
		return

	var bgs: Dictionary = index.get("backgrounds", {})
	var meta: Dictionary = index.get("meta", {})

	_chk("the reference table still has %d entries (got %d)"
			% [EXPECTED_TABLE_ENTRIES, int(meta.get("table_entries", -1))],
			int(meta.get("table_entries", -1)) == EXPECTED_TABLE_ENTRIES)
	_chk("a substantial set of backgrounds was pulled (%d)" % bgs.size(),
			bgs.size() >= 85)

	# Every indexed background must load, be tile-aligned, be exactly the
	# tilemap width, and match its recorded geometry.
	var bad_load := ""
	var bad_width := ""
	var bad_align := ""
	var bad_geom := ""
	var checked := 0
	for name in bgs:
		var e: Dictionary = bgs[name]
		var tex := load("%s/%s" % [DIR, e.get("file", "")]) as Texture2D
		if tex == null:
			bad_load = str(name)
			break
		var size := tex.get_size()
		if int(size.x) != TILEMAP_WIDTH_PX:
			bad_width = "%s (%d px)" % [name, int(size.x)]
			break
		if int(size.y) % 8 != 0 or size.y <= 0:
			bad_align = str(name)
			break
		if int(size.x) != int(e.get("width", -1)) \
				or int(size.y) != int(e.get("height", -1)):
			bad_geom = str(name)
			break
		checked += 1
	_chk("every background loads as a Texture2D (bad: '%s')" % bad_load,
			bad_load == "")
	_chk("every background is exactly the 32-cell tilemap width (bad: '%s')"
			% bad_width, bad_width == "")
	_chk("every background is 8px tile-aligned vertically (bad: '%s')"
			% bad_align, bad_align == "")
	_chk("every background matches its indexed geometry (bad: '%s')"
			% bad_geom, bad_geom == "")
	_chk("all %d backgrounds were geometry-checked" % checked,
			checked == bgs.size())

	# The headline consumers M36E exists to unblock must be present.
	for required in ["BG_PSYCHIC", "BG_THUNDER", "SURF_PLAYER",
			"SURF_OPPONENT", "BG_HYPER_BEAM", "BG_DARK", "BG_GHOST"]:
		_chk("required background present: %s" % required, bgs.has(required))

	# A composited background must carry REAL imagery, not one flat colour --
	# the failure mode a broken tile lookup would produce.
	for name in ["BG_PSYCHIC", "SURF_PLAYER"]:
		if not bgs.has(name):
			continue
		var tex := load("%s/%s" % [DIR, (bgs[name] as Dictionary).get("file",
				"")]) as Texture2D
		var img := tex.get_image()
		var seen := {}
		for y in range(0, img.get_height(), 8):
			for x in range(0, img.get_width(), 8):
				var c := img.get_pixel(x, y)
				if c.a > 0.0:
					seen[c.to_rgba32()] = true
		_chk("%s decoded to real imagery, not a flat fill (%d colours)"
				% [name, seen.size()], seen.size() >= 4)

	# Palette-only variants share tiles AND tilemap upstream, so if they came
	# out identical the palette step silently did nothing.
	if bgs.has("BG_HYPER_BEAM") and bgs.has("BG_HYDRO_CANNON"):
		var a: Dictionary = bgs["BG_HYPER_BEAM"]
		var b: Dictionary = bgs["BG_HYDRO_CANNON"]
		_chk("Hyper Beam and Hydro Cannon share tiles upstream",
				str(a.get("tiles", "")) == str(b.get("tiles", "")))
		_chk("...and share a tilemap",
				str(a.get("tilemap", "")) == str(b.get("tilemap", "")))
		_chk("...but differ in palette (so the recolor really applied)",
				str(a.get("palette", "")) != str(b.get("palette", "")))
		var ia := (load("%s/%s" % [DIR, a.get("file", "")]) as Texture2D) \
				.get_image()
		var ib := (load("%s/%s" % [DIR, b.get("file", "")]) as Texture2D) \
				.get_image()
		var differs := false
		for y in range(0, mini(ia.get_height(), ib.get_height()), 16):
			for x in range(0, ia.get_width(), 16):
				if ia.get_pixel(x, y) != ib.get_pixel(x, y):
					differs = true
					break
			if differs:
				break
		_chk("...and the rendered pixels actually differ", differs)

	var total := _pass + _fail
	print("m36e_background_asset_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
