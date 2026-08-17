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
const TILESET_DIR := "res://assets/map_tilesets/"
const AUTHORED_MAPS_PATH := "res://scripts/overworld/authored_maps.gd"
const CONSTANT_PREFIX := "MAP_AUTHORED_"


# ------------------------------------------------------------------ [C1] create

## The tileset pairs a new map can actually use.
##
## ⚠️ **A PAIR IS USABLE ONLY IF A MAP ON IT HAS BEEN BAKED**, because that is
## what writes the shared `TileSet`. Measured 2026-08-09: 60 pairs exist
## region-wide, 22 have rendered atlases, and **16 have a TileSet — exactly the
## set the 35 baked maps use.** That is the vertical slice, not a defect, but it
## is the first wall anyone hits, so the caller must be able to say which 16.
static func usable_pairs() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(TILESET_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".tres"):
			out.append(f.get_basename())
	out.sort()
	return out


## Every baked map, as a name — the candidates a connection can name.
##
## ⚠️ **BAKED, NOT DEFINED.** `MapConstants` knows 939 map constants; only the
## ~35 with a real `<Map>.tscn` can be stitched to, and `loadable_connections()`
## drops the rest at runtime anyway. Listing anything else would offer an author
## a choice that silently does nothing.
##
## Keyed off the SCENE rather than the `_data.tres` because the scene is what
## `MapManager.load_chunk` requires and what `is_baked()` already tests — a
## `_data.tres` with no scene beside it is a half-baked artifact, not a
## destination.
##
## `exclude` drops the host: a map cannot connect to itself, and offering it is
## how you get a seam that resolves to its own origin.
static func baked_maps(exclude: String = "") -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(OUT_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".tscn"):
			continue
		var n := f.get_basename()
		if n != exclude:
			out.append(n)
	out.sort()
	return out


## A sensible fill metatile for a pair, derived rather than asked for.
##
## The most common metatile that is walkable, plain (`MB_NORMAL`) and at
## elevation 3 across a baked map using this pair. Measured to resolve for all
## 16 usable pairs, which is what lets a map be created without knowing a single
## metatile id — the gap M27M6's picker will otherwise leave open.
##
## ⚠️ Reads BAKED `_data.tres`, deliberately, not `assets/maps/*.json`. That
## directory is gitignored regenerable output and may be absent in a fresh
## checkout; the baked data is tracked. It is also guaranteed to exist here —
## a pair is only usable BECAUSE a map on it was baked (see `usable_pairs`), so
## there is always something to measure.
static func default_fill_for(pair: String) -> int:
	var counts := {}
	var d := DirAccess.open(OUT_DIR)
	if d == null:
		return -1
	for f in d.get_files():
		if not f.ends_with("_data.tres"):
			continue
		var md := load(OUT_DIR + f) as MapData
		if md == null or md.atlas != pair:
			continue
		for i in range(md.metatile.size()):
			if i < md.collision.size() and md.collision[i] == 0 \
					and i < md.behavior.size() and md.behavior[i] == 0 \
					and i < md.elevation.size() and md.elevation[i] == 3:
				var m: int = md.metatile[i]
				counts[m] = int(counts.get(m, 0)) + 1
	# ⚠️ EVERY map on the pair, not the first one found. An earlier draft broke
	# out after one and produced 371 for `general_frlg__viridian_city_frlg`
	# where the whole-corpus measurement says 8 — a different but individually
	# valid tile, chosen by directory order. A default that changes depending on
	# which file `DirAccess` happens to list first is not a default.
	var best := -1
	var best_n := 0
	for m in counts:
		if int(counts[m]) > best_n:
			best_n = int(counts[m])
			best = int(m)
	return best


## `XanaduNursery` -> `MAP_AUTHORED_XANADU_NURSERY`.
static func constant_for(map_name: String) -> String:
	var out := ""
	for i in range(map_name.length()):
		var c := map_name[i]
		if c == "_":
			out += "_"
			continue
		if i > 0 and c == c.to_upper() and c != c.to_lower() \
				and map_name[i - 1] != "_" \
				and not (map_name[i - 1] == map_name[i - 1].to_upper()
						and map_name[i - 1] != map_name[i - 1].to_lower()):
			out += "_"
		out += c.to_upper()
	return CONSTANT_PREFIX + out


static func map_exists(map_name: String) -> bool:
	return ResourceLoader.exists(OUT_DIR + map_name + ".tscn")


## Add the map to the hand-owned `AuthoredMaps` table.
##
## ⚠️ **APPEND-ONLY AND GUARDED — Rob's call, 2026-08-09, and the guard is the
## load-bearing half.** That file exists precisely because `map_constants.gd` is
## GENERATED and would erase authored entries; a tool that rewrote it would
## reintroduce the same erasure by a different hand. So this inserts exactly one
## line before the closing brace, refuses if the constant is already present,
## and never reorders or rewrites an existing line.
##
## Returns "" on success, or a reason.
static func register_constant(map_name: String) -> String:
	var konst := constant_for(map_name)
	var f := FileAccess.open(AUTHORED_MAPS_PATH, FileAccess.READ)
	if f == null:
		return "cannot read %s" % AUTHORED_MAPS_PATH
	var text := f.get_as_text()
	f.close()
	if text.contains('"%s"' % konst):
		return "%s is already registered" % konst
	var entry := '\t"%s": "%s",\n' % [konst, map_name]
	var marker := "}\n"
	var at := text.find(marker, text.find("const NAME_BY_CONSTANT := {"))
	if at < 0:
		return "could not find the end of NAME_BY_CONSTANT"
	text = text.substr(0, at) + entry + text.substr(at)
	var w := FileAccess.open(AUTHORED_MAPS_PATH, FileAccess.WRITE)
	if w == null:
		return "cannot write %s" % AUTHORED_MAPS_PATH
	w.store_string(text)
	w.close()
	return ""


# ----------------------------------------------------------------- [C2] connect

## Which direction answers a given one, so a reciprocal cannot be guessed wrong.
const OPPOSITE := {
	MapData.Connection.NORTH: MapData.Connection.SOUTH,
	MapData.Connection.SOUTH: MapData.Connection.NORTH,
	MapData.Connection.WEST: MapData.Connection.EAST,
	MapData.Connection.EAST: MapData.Connection.WEST,
}

## Human-readable edge names, for labelling only — never round-tripped back
## into an enum. `_existing_keys` in the connect dialog records why: a label is
## for a human, and parsing one back is how a display change becomes a wrong
## edit.
const DIRECTION_NAMES := {
	MapData.Connection.NONE: "NONE",
	MapData.Connection.SOUTH: "SOUTH",
	MapData.Connection.NORTH: "NORTH",
	MapData.Connection.WEST: "WEST",
	MapData.Connection.EAST: "EAST",
	MapData.Connection.DIVE: "DIVE",
	MapData.Connection.EMERGE: "EMERGE",
}


static func direction_name(direction: int) -> String:
	return str(DIRECTION_NAMES.get(direction, "DIR_%d" % direction))


## The maps this one borders, in its own connection order, ready to navigate to.
##
## ⚠️ **NAVIGATION, NOT LOADING — so this deliberately does NOT reuse
## `MapData.loadable_connections()`.** That one answers the question a chunk
## loader asks and drops DIVE/EMERGE (real links that warp rather than stitch)
## along with anything unbaked. An author wants to open the map on the other
## side of an edge whatever kind of edge it is, and wants to be TOLD when the
## other side has no scene rather than have the row silently vanish — a missing
## neighbour is a thing to go and bake, not a thing to hide.
##
## `openable` is the flag a caller gates its button on; `map` is "" when the
## destination constant resolves to nothing at all, which is a pipeline bug
## rather than an unbaked map and reads differently in a list.
static func neighbours_of(map_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var md := _load_data(map_name)
	if md == null:
		return out
	for i in range(md.connections.size()):
		var c: Dictionary = md.connections[i]
		var constant := str(c.get("map", ""))
		var nb := MapConstants.map_name_for(constant)
		var path := OUT_DIR + nb + ".tscn"
		out.append({
			"index": i,
			"direction": int(c.get("direction", MapData.Connection.NONE)),
			"offset": int(c.get("offset", 0)),
			"constant": constant,
			"map": nb,
			"scene_path": path,
			"openable": nb != "" and ResourceLoader.exists(path),
		})
	return out


## Every map reachable from `origin_map` by connections, and the rect it
## occupies, with `origin_map` itself at (0, 0).
##
## ⚠️ This is what makes an overlap check possible at all. Placement is not a
## property of one edge — a map two hops away can land on top of you, which is
## exactly what nearly happened to Xanadu Nursery and Pewter City (Pewter sits
## at (-12,-40) from Route 2, two hops from nothing obvious).
## [M27M5c Phase 4] `overrides` answers "where would everything sit IF this map
## were a different shape" without writing that shape to disk first.
##
## Keyed by map name, each entry `{"size": Vector2i, "connections": Array}` with
## both optional. ⚠️ **THE POINT IS THAT THE RESIZE GUARD RUNS THIS BFS RATHER
## THAN A SECOND COPY OF IT.** Placement is not a property of one edge — a map
## two hops away can land on top of you — so a guard that re-derived the geometry
## would be a second implementation of the one rule that has to agree with
## `MapManager` exactly. Empty by default, so every existing caller is unchanged.
static func placed_rects(origin_map: String, overrides: Dictionary = {}) -> Dictionary:
	var out := {}
	var md := _load_data_as(origin_map, overrides)
	if md == null:
		return out
	out[origin_map] = Rect2i(Vector2i.ZERO, Vector2i(md.width, md.height))
	var queue: Array = [origin_map]
	while not queue.is_empty():
		var host: String = queue.pop_front()
		var hd := _load_data_as(host, overrides)
		if hd == null:
			continue
		var horigin: Vector2i = (out[host] as Rect2i).position
		for c in hd.connections:
			var nb := MapConstants.map_name_for(str(c.get("map", "")))
			if nb == "" or out.has(nb):
				continue
			var nd := _load_data_as(nb, overrides)
			if nd == null:
				continue
			var o := MapManager.neighbour_origin(horigin, hd, c, nd)
			out[nb] = Rect2i(o, Vector2i(nd.width, nd.height))
			queue.append(nb)
	return out


## A map's data with any override applied, on a COPY.
##
## ⚠️ **THE `duplicate()` IS LOAD-BEARING.** `load()` hands back the cached
## resource — the very instance the open scene's overlay is painting into — so
## writing a hypothetical width onto it would silently resize the live map to
## answer a what-if question. Shallow is correct and deliberate: only `width`,
## `height` and the `connections` REFERENCE are replaced, and the seven per-cell
## arrays are never touched, so sharing them costs nothing.
static func _load_data_as(map_name: String, overrides: Dictionary) -> MapData:
	var md := _load_data(map_name)
	if md == null or not overrides.has(map_name):
		return md
	var o: Dictionary = overrides[map_name]
	var copy: MapData = md.duplicate()
	if o.has("size"):
		var size: Vector2i = o["size"]
		copy.width = size.x
		copy.height = size.y
	if o.has("connections"):
		copy.connections.assign(o["connections"])
	return copy


## Which already-placed maps a proposed link would land on top of.
##
## ⚠️ **PURE, AND EXTRACTED FROM `connect_maps` FOR A REASON THE TESTS FOUND THE
## HARD WAY.** Break-testing a refusal guard is self-defeating when the guard
## lives inside the function that performs the write: with the check disabled
## the call no longer refuses, so it goes ahead and writes — a read-only test
## silently becomes a writing one, and it corrupted two tracked `.tres` files
## before this was split out. The decision is now assertable without the act.
##
## The guest is deliberately excluded from its own check: re-linking an
## existing edge is a legitimate offset UPDATE, not a self-collision.
static func would_overlap(host: String, direction: int, guest: String,
		offset: int) -> Array:
	var out: Array = []
	var hd := _load_data(host)
	var gd := _load_data(guest)
	if hd == null or gd == null:
		return out
	var rects := placed_rects(host)
	if not rects.has(host):
		return out
	var conn := {"direction": direction, "map": _constant_of(guest), "offset": offset}
	var origin := MapManager.neighbour_origin(
			(rects[host] as Rect2i).position, hd, conn, gd)
	var guest_rect := Rect2i(origin, Vector2i(gd.width, gd.height))
	for name in rects:
		if name == guest:
			continue
		if (rects[name] as Rect2i).intersects(guest_rect):
			out.append(name)
	return out


## Link two maps, both ways, refusing an overlap.
##
## `direction` is FROM `host` TO `guest`. The reciprocal direction and offset
## are DERIVED — ⚠️ a hand-written reciprocal is how two maps end up stitched at
## a slant that looks plausible until you walk it.
##
## Returns `{"ok": bool, "reason": String, "overlaps": Array}`.
static func connect_maps(host: String, direction: int, guest: String,
		offset: int, force: bool = false) -> Dictionary:
	var res := {"ok": false, "reason": "", "overlaps": []}
	if not OPPOSITE.has(direction):
		res["reason"] = "direction must be NORTH/SOUTH/WEST/EAST"
		return res
	var hd := _load_data(host)
	var gd := _load_data(guest)
	if hd == null or gd == null:
		res["reason"] = "no MapData for %s" % (host if hd == null else guest)
		return res

	if _constant_of(guest) == "":
		res["reason"] = "%s has no MAP_* constant — register it first" % guest
		return res
	res["overlaps"] = would_overlap(host, direction, guest, offset)
	# ⚠️ REFUSED, not warned. `chunk_owning()` is first-match-wins over an
	# UNORDERED Dictionary, so two overlapping chunks answer differently run to
	# run — a bug that reproduces intermittently and points nowhere near itself.
	if not res["overlaps"].is_empty() and not force:
		res["reason"] = "would overlap %s" % ", ".join(res["overlaps"])
		return res

	add_connection(hd, direction, _constant_of(guest), offset)
	add_connection(gd, OPPOSITE[direction], _constant_of(host), -offset)
	var e1 := ResourceSaver.save(hd, OUT_DIR + host + "_data.tres")
	var e2 := ResourceSaver.save(gd, OUT_DIR + guest + "_data.tres")
	if e1 != OK or e2 != OK:
		res["reason"] = "save failed (%d / %d)" % [e1, e2]
		return res
	res["ok"] = true
	return res


## [M27M5c Phase 3] Unlink two maps, both ways. The inverse of `connect_maps`.
##
## ⚠️ **KEYED ON (direction, guest), AND DIRECTION ALONE WOULD BE WRONG.**
## Measured across all 939 reference `map.json` files: **3 maps carry more than
## one connection on a single edge** — `SixIsland_WaterPath_Frlg` has THREE on
## its left — so "remove this map's WEST connection" is ambiguous there and
## would drop whichever happened to be first. The same sweep found **zero**
## `(direction, map)` pairs repeated on one map, so the pair is unique
## everywhere the data exists. Do not "simplify" this to a direction.
##
## ⚠️ **A MISSING RECIPROCAL IS REPORTED, NOT FATAL.** If the guest has no
## matching entry the two sides had already drifted — removing only the host's
## side is still strictly an improvement, and refusing would leave an author
## unable to clear a half-seam through any tool. The count is returned so the
## caller can say which happened rather than claiming a clean unlink.
##
## Returns `{"ok": bool, "reason": String, "removed_host": int,
## "removed_guest": int}`.
static func disconnect_maps(host: String, direction: int,
		guest: String) -> Dictionary:
	var res := {"ok": false, "reason": "", "removed_host": 0, "removed_guest": 0}
	if not OPPOSITE.has(direction):
		res["reason"] = "direction must be NORTH/SOUTH/WEST/EAST"
		return res
	var hd := _load_data(host)
	var gd := _load_data(guest)
	if hd == null or gd == null:
		res["reason"] = "no MapData for %s" % (host if hd == null else guest)
		return res

	# Matched by RESOLVED NAME rather than raw constant. An authored map and an
	# imported one answer from different tables (`AuthoredMaps` vs the generated
	# `MapConstants`), and comparing constants directly would silently fail to
	# match a seam written before a map was renamed or re-registered.
	res["removed_host"] = _drop_connection(hd, direction, guest)
	res["removed_guest"] = _drop_connection(gd, OPPOSITE[direction], host)

	if int(res["removed_host"]) == 0 and int(res["removed_guest"]) == 0:
		res["reason"] = "no such connection on %s" % host
		return res

	var e1 := ResourceSaver.save(hd, OUT_DIR + host + "_data.tres")
	var e2 := ResourceSaver.save(gd, OUT_DIR + guest + "_data.tres")
	if e1 != OK or e2 != OK:
		res["reason"] = "save failed (%d / %d)" % [e1, e2]
		return res
	if int(res["removed_guest"]) == 0:
		res["reason"] = ("%s had no reciprocal edge — the two sides had already "
				+ "drifted; %s's side is gone.") % [guest, host]
	res["ok"] = true
	return res


## Remove every connection on `md` matching (direction, other map). Returns how
## many went. Walks BACKWARDS so a removal cannot shift an index still to be
## visited — the ordinary array-mutation trap, and the 3 multi-seam edges above
## are exactly where it would bite.
static func _drop_connection(md: MapData, direction: int, other: String) -> int:
	var removed := 0
	for i in range(md.connections.size() - 1, -1, -1):
		var c: Dictionary = md.connections[i]
		if int(c.get("direction", -1)) != direction:
			continue
		if MapConstants.map_name_for(str(c.get("map", ""))) != other:
			continue
		md.connections.remove_at(i)
		removed += 1
	return removed


static func _load_data(map_name: String) -> MapData:
	var p := OUT_DIR + map_name + "_data.tres"
	return load(p) as MapData if ResourceLoader.exists(p) else null


## The MAP_* constant naming a map, from either table. "" when nothing does.
##
## ⚠️ **THE THIRD LOOKUP IS NOT BELT-AND-BRACES — WITHOUT IT, CREATING AND
## CONNECTING A MAP IN ONE RUN IS IMPOSSIBLE.** `AuthoredMaps.NAME_BY_CONSTANT`
## is a `const`, compiled into the running process, so a line `register_constant`
## has just WRITTEN TO DISK is invisible to it until the editor rescans. The
## creator does exactly that sequence, and the symptom was a flat refusal to
## link a map it had just registered a line earlier.
##
## Reading the file back is the authoritative answer to "is this registered",
## and it is deliberately a text match on the real entry rather than trusting
## `constant_for()` — deriving the name would happily invent a constant for a
## map nobody registered, and the connection would then point at something that
## resolves to "" forever.
static func _constant_of(map_name: String) -> String:
	for k in AuthoredMaps.NAME_BY_CONSTANT:
		if str(AuthoredMaps.NAME_BY_CONSTANT[k]) == map_name:
			return str(k)
	for k in MapConstants.NAME_BY_CONSTANT:
		if str(MapConstants.NAME_BY_CONSTANT[k]) == map_name:
			return str(k)
	var f := FileAccess.open(AUTHORED_MAPS_PATH, FileAccess.READ)
	if f != null:
		var text := f.get_as_text()
		f.close()
		var konst := constant_for(map_name)
		if text.contains('"%s": "%s",' % [konst, map_name]):
			return konst
	return ""


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
