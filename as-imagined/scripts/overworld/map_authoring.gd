@tool
class_name MapAuthoring
extends RefCounted

## [M27M5] Making a map this project invents, rather than imports.
##
## Everything before this tier edited maps that already existed. A new map has
## no `map.json`, no entry in `assets/maps/`, and no `MAP_*` constant — so this
## is the one place that has to answer "where does a map come from when the
## reference has never heard of it".
##
## ⚠️ **NO IMPORTER, NO JSON, DELIBERATELY.** `assets/maps/` is gitignored as
## regenerable output (`docs/overworld_scope.md` §1.9), so authored input
## cannot live there — a `gen_map_import.py` run would not recreate it and a
## fresh checkout would not have it. An authored map's `.tscn` and `_data.tres`
## in `scenes/maps/` ARE the source, which is the same "the scene becomes the
## source of truth" decision M27M already made for tiles.

const CELL := 16
const OUT_DIR := "res://scenes/maps/"


## A new map, filled with one metatile.
##
## ⚠️ Every cell is `AUTHORED` and, unlike an imported one, is left NOT
## explicit on collision or elevation — so a fresh map reads as entirely
## "needs review", which is honest: nobody has decided anything about it yet.
## The alternative, stamping it explicit because the fill was deliberate, would
## make a 360-cell map claim 360 confirmed decisions from a single call.
static func create_map(map_name: String, width: int, height: int, atlas: String,
		fill_metatile: int) -> MapData:
	var md := MapData.new()
	md.map_name = map_name
	md.layout = ""
	md.atlas = atlas
	md.width = width
	md.height = height
	var n := width * height
	md.metatile.resize(n)
	md.collision.resize(n)
	md.elevation.resize(n)
	md.behavior.resize(n)
	md.layer_type.resize(n)
	md.provenance.resize(n)
	md.attr_explicit.resize(n)
	for i in range(n):
		md.provenance[i] = MapData.Provenance.AUTHORED
		md.attr_explicit[i] = 0
	# Borders are imported data with no live consumer (see MapData.border), and
	# an authored map has none to import. Left empty rather than invented.
	md.border = PackedInt32Array()
	md.border_layer_type = PackedInt32Array()
	fill_rect(md, Rect2i(0, 0, width, height), fill_metatile, 0, 3)
	return md


## Paint a rectangle: the metatile, the behaviour that follows from it, the
## layer type it routes by, and a collision/elevation the author is asserting.
##
## Collision and elevation ARE marked explicit here, unlike `create_map`'s own
## base fill — a caller naming a rectangle and a value is making a decision,
## which is exactly what the explicit bits record.
static func fill_rect(md: MapData, rect: Rect2i, metatile_id: int,
		collision: int, elevation: int, explicit: bool = false) -> void:
	var beh := MapManager.behavior_for(md.atlas, metatile_id)
	var lt := MapManager._layer_type_for(md.atlas, metatile_id)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if not md.in_bounds(x, y):
				continue
			var i := y * md.width + x
			md.metatile[i] = metatile_id
			md.behavior[i] = maxi(beh, 0)
			md.layer_type[i] = lt
			md.collision[i] = collision
			md.elevation[i] = elevation
			md.provenance[i] = MapData.Provenance.AUTHORED
			md.attr_explicit[i] = MapData.ATTR_ALL_EXPLICIT if explicit else 0


## Paint a 2x2-tiled block, which is how the reference's tree walls are drawn:
## `quad` is [top-left, top-right, bottom-left, bottom-right] and the pattern
## repeats on the map's own parity, so a wall lines up with its neighbours.
static func fill_rect_quad(md: MapData, rect: Rect2i, quad: Array,
		collision: int, elevation: int) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if not md.in_bounds(x, y):
				continue
			var mid: int = quad[(y % 2) * 2 + (x % 2)]
			fill_rect(md, Rect2i(x, y, 1, 1), mid, collision, elevation)


## Add one edge link. Does NOT add the reciprocal — the two maps are separate
## resources and the caller saves both, so doing it silently here would write a
## file the caller did not know it was changing.
##
## ⚠️ The reciprocal offset is the NEGATIVE of this one for both axes, and the
## reciprocal DIRECTION is the opposite. Getting either wrong stitches the two
## maps at a slant that looks plausible until you walk it.
static func add_connection(md: MapData, direction: int, map_constant: String,
		offset: int) -> void:
	for c in md.connections:
		if int(c.get("direction", 0)) == direction \
				and str(c.get("map", "")) == map_constant:
			c["offset"] = offset
			return
	md.connections.append({
		"direction": direction, "map": map_constant, "offset": offset,
	})


## Write both artifacts. The scene is built through `map_baker.build_map_scene`
## so an authored map is structurally identical to a baked one — same five
## nodes, same names, same z-order — because `MapManager` finds planes by name
## and nothing downstream is told which kind of map it is looking at.
static func save_map(md: MapData) -> Error:
	var baker = load("res://scenes/overworld/map_baker.gd").new()
	var ts: TileSet = baker._get_or_build_tileset(md.atlas)
	if ts == null:
		push_error("MapAuthoring: no TileSet for atlas %s" % md.atlas)
		return ERR_CANT_CREATE
	var root: Node2D = baker.build_map_scene(md, ts, md.map_name)
	for c in root.get_children():
		c.owner = root
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return ERR_CANT_CREATE
	var scene_path := OUT_DIR + md.map_name + ".tscn"
	var data_path := OUT_DIR + md.map_name + "_data.tres"
	var err := ResourceSaver.save(packed, scene_path)
	if err == OK:
		err = ResourceSaver.save(md, data_path)
	root.free()
	# ⚠️ A SCENE WITH NO `uid=` IS INVISIBLE TO THE EDITOR'S RESOURCE PICKERS,
	# and `ResourceSaver` does not write one. `map_baker` already mints one for
	# exactly this reason (`_preserve_or_mint_uid`), and `check_bake_diff --all`
	# reports a missing uid as a defect — so an authored map that skipped this
	# would be flagged by the project's own acceptance tool the moment it was
	# created. Reuses the baker's own helper rather than re-deriving the format.
	if err == OK:
		baker._preserve_or_mint_uid(scene_path, "")
		baker._preserve_or_mint_uid(data_path, "")
	return err
