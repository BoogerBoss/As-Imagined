@tool
extends Node

## [M27M5 C1/C2] Make a map, and link it to an existing one.
##
## ⚠️ **THIS IS THE TEST SURFACE, NOT THE USER SURFACE.** The rules live on
## `MapAuthoring` and the editor dialog presses the same functions — this driver
## exists so they can be asserted headlessly and so a batch of maps stays
## scriptable, the same split `map_baker` and `check_bake_diff` already use.
##
## Run:
##   godot --headless --path <project> scenes/overworld/map_creator.tscn -- \
##       --name XanaduNursery --pair general_frlg__viridian_city_frlg \
##       --size 20x18 [--fill 8] \
##       [--connect Route2_Frlg:WEST:0] [--force]
##
##   ...or with no arguments at all, which lists what a map can be built on.

const DIRS := {
	"NORTH": MapData.Connection.NORTH, "SOUTH": MapData.Connection.SOUTH,
	"WEST": MapData.Connection.WEST, "EAST": MapData.Connection.EAST,
}


func _ready() -> void:
	var a := _args()
	if a.is_empty() or not a.has("name"):
		_usage()
		get_tree().quit()
		return

	var map_name: String = a["name"]
	var pair: String = a.get("pair", "")
	var usable := MapAuthoring.usable_pairs()

	# ⚠️ The first wall anyone hits, so it is answered precisely rather than
	# refused vaguely: a pair is usable only once a map on it has been BAKED,
	# because that is what writes the shared TileSet.
	if pair == "" or pair not in usable:
		print("map_creator: --pair must be one of the %d built tilesets%s"
				% [usable.size(), "" if pair == "" else " (got '%s')" % pair])
		for p in usable:
			print("    ", p)
		print("\nTo use another pair: render its atlas with")
		print("    python3 scripts/gen_map_import.py <a map on that pair>")
		print("then run a Godot --import pass and bake that map.")
		get_tree().quit(1)
		return

	if MapAuthoring.map_exists(map_name):
		print("map_creator: %s already exists — refusing to overwrite." % map_name)
		get_tree().quit(1)
		return

	var size: Vector2i = _size(a.get("size", "20x18"))
	if size.x <= 0 or size.y <= 0:
		print("map_creator: --size must be WxH, e.g. 20x18")
		get_tree().quit(1)
		return

	var fill := int(a["fill"]) if a.has("fill") else MapAuthoring.default_fill_for(pair)
	if fill < 0:
		print("map_creator: no fill metatile could be derived for %s; pass --fill" % pair)
		get_tree().quit(1)
		return

	var md := MapAuthoring.create_map(map_name, size.x, size.y, pair, fill)
	var err := MapAuthoring.save_map(md)
	if err != OK:
		print("map_creator: save failed — %s" % error_string(err))
		get_tree().quit(1)
		return
	var reg := MapAuthoring.register_constant(map_name)
	print("map_creator: created %s %dx%d on %s (fill %d)"
			% [map_name, size.x, size.y, pair, fill])
	print("map_creator: constant %s%s" % [MapAuthoring.constant_for(map_name),
			"" if reg == "" else "  ⚠ NOT registered: " + reg])

	if a.has("connect"):
		var parts: PackedStringArray = a["connect"].split(":")
		if parts.size() != 3 or not DIRS.has(parts[1].to_upper()):
			print("map_creator: --connect wants HostMap:DIRECTION:offset")
			get_tree().quit(1)
			return
		# ⚠️ The direction is FROM the host TO the new map, and the reciprocal
		# is derived — never given — so the two can never disagree.
		var r := MapAuthoring.connect_maps(parts[0], DIRS[parts[1].to_upper()],
				map_name, int(parts[2]), a.has("force"))
		if bool(r["ok"]):
			print("map_creator: linked %s %s -> %s (offset %s)"
					% [parts[0], parts[1].to_upper(), map_name, parts[2]])
		else:
			print("map_creator: NOT linked — %s" % r["reason"])
			if not (r["overlaps"] as Array).is_empty():
				print("    pass --force only if you know why that is safe;")
				print("    chunk_owning() answers overlapping chunks nondeterministically.")
	print("\nNext: open res://scenes/maps/%s.tscn, press Overlay, and paint."
			% map_name)
	get_tree().quit()


func _usage() -> void:
	print("""map_creator — make an authored map

  --name <MapName>           required
  --pair <tileset_pair>      required; one of the built TileSets
  --size WxH                 default 20x18
  --fill <metatile id>       default: derived from a baked map on that pair
  --connect Host:DIR:offset  DIR is NORTH/SOUTH/WEST/EAST, from Host to the new map
  --force                    link even if it overlaps something

Built tilesets a map can use right now:""")
	for p in MapAuthoring.usable_pairs():
		print("    ", p)


func _args() -> Dictionary:
	var out := {}
	var argv := OS.get_cmdline_user_args()
	var i := 0
	while i < argv.size():
		var t: String = argv[i]
		if t.begins_with("--"):
			var key := t.substr(2)
			if i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				out[key] = argv[i + 1]
				i += 1
			else:
				out[key] = "1"
		i += 1
	return out


func _size(s: String) -> Vector2i:
	var p := s.to_lower().split("x")
	return Vector2i(int(p[0]), int(p[1])) if p.size() == 2 else Vector2i.ZERO
