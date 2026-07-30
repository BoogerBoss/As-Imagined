class_name MapManager
extends Node2D

## [M27C C2] Owns which maps are loaded and where they sit relative to each
## other. The thing that replaces "the current map is the scene you are in".
##
## THE POINT IS THE COORDINATE SPACE, not the loading. Every cell coordinate
## crossing this boundary is GLOBAL — a position in one tile grid shared by
## every loaded chunk — and each chunk knows the offset from that grid to its
## own local cells. Today exactly one chunk is ever live and its origin is
## (0,0), so global and local happen to be equal; C4 makes several live at once
## and the equality stops holding.
##
## Introducing the distinction NOW, while it is a no-op, is deliberate. The
## alternative is a player controller written against map-local cells that has
## to be re-plumbed once neighbours load — and the failure mode of getting that
## wrong later is silent, because everything still works perfectly on the one
## map you happen to be testing. That is why `_test_map_manager` registers
## chunks at NONZERO origins even though nothing does at runtime yet: an origin
## of (0,0) cannot tell a correct conversion from a missing one.
##
## What this deliberately does NOT do yet: derive a neighbour's origin from a
## connection's direction and offset, load neighbours, or unload with
## hysteresis. That is C4. C1 landed the data those need; this holds the shape
## they plug into.

const CELL := 16

## Atlas geometry, matching map_baker.gd — the skirt paints from the same
## atlas the chunk's own Ground layer uses, so a border metatile id converts
## to atlas coords exactly as a map cell does.
const ATLAS_COLS := 32

## How far past a chunk's own bounds the skirt reaches, in cells.
##
## MEASURED, not picked: the canvas is 1024x768 (M26A1) and the overworld
## camera runs at zoom 3, so the visible region is 341x256 world px = 21.3 x 16
## cells, i.e. a ~11 x 8 half-extent when the player stands on an edge cell.
## 16 covers the wider axis with headroom for the camera's own position
## smoothing overshooting the player, and for the non-native window sizes
## M26G3 flags as a real case. Cost is bounded: a 24x20 map skirted at 16 is
## 56x52 cells of TileMapLayer, which is nothing.
const SKIRT_DEPTH := 16

## The layers MapManager paints the skirt into, one per draw plane.
##
## Created at load time and NEVER baked. The baked scene is a reproducible
## artifact (map_baker's own guard depends on that), and which edges need a
## skirt is not a property of the map anyway — it changes at runtime as C4
## loads and unloads neighbours.
##
## THREE of them, not one, and that is not symmetry for its own sake: a
## metatile routes to one or two of the three planes by §1.6, so a skirt
## painted into the ground plane alone renders half of each block. Pallet
## Town's own border is the worked example — ids 28/29 are COVERED
## (ground+objects) but 20/21 are NORMAL (objects+overhangs, nothing on ground
## at all), so a ground-only skirt left every other row blank. The cell COUNT
## was already correct; only a screenshot could see it.
const SKIRT_LAYERS := ["BorderSkirt_Ground", "BorderSkirt_Objects",
		"BorderSkirt_Overhangs"]

## §1.6 routing, matching map_baker.gd's own table: layer_type -> the planes a
## metatile paints into. Both halves use the same atlas coords; the per-plane
## atlas already holds the right half.
const ROUTING := {
	0: [1, 2],  # NORMAL  : objects + overhangs
	1: [0, 1],  # COVERED : ground  + objects
	2: [0, 2],  # SPLIT   : ground  + overhangs
}

## §1.6's plane order, expressed as z_index so it is GLOBAL across chunks.
##
## [M27C C4] Without this, draw order is pure scene-tree order, which is
## CHUNK-major: every layer of the chunk loaded first draws beneath every layer
## of the next. Reparenting the player into the lower chunk mid-step then puts
## it behind the other chunk's ground while it is still visually overlapping it
## — seen crossing Route 1 back into Pallet Town as the character snapping
## behind the grass for a frame. Only in that direction, because Pallet Town
## happened to load first.
##
## Chunk roots stay at z 0 and `z_as_relative` is on, so a layer's effective z
## is its own — a plane therefore sorts identically no matter which chunk owns
## it, which is what docs/overworld_scope.md means by sorting being "global
## across stitched maps so sorting never breaks at seams".
##
## Entities sit at 2 and 4, straddling Overhangs at 3, preserving the whole
## point of the two strata: elevation-4 entities draw above the overhang plane
## and everything else below it.
const PLANE_Z := {
	"BorderSkirt_Ground": 0, "Ground": 0,
	"BorderSkirt_Objects": 1, "Objects": 1,
	"Entities_P2": 2,
	"BorderSkirt_Overhangs": 3, "Overhangs": 3,
	"Entities_P1": 4,
}


## map name -> {"data": MapData, "root": Node2D, "origin": Vector2i}
##
## Keyed by the map's own directory name (`Route1_Frlg`), which is what
## `MapConstants` resolves a `MAP_*` constant to and what the baked scene is
## called — so a connection's destination and a loaded chunk are the same
## string with no third naming scheme in between.
var _chunks: Dictionary = {}


## Instantiate a baked map and place it at `origin` in the global grid.
##
## Returns false rather than pushing an error for an unbaked map: the corridor
## has 3 dangling connections and 20 unbaked warp destinations by design, so
## "not baked" is an expected answer a caller acts on, not a fault.
func load_chunk(map_name: String, origin: Vector2i = Vector2i.ZERO) -> bool:
	if _chunks.has(map_name):
		return true
	var scene_path := "res://scenes/maps/%s.tscn" % map_name
	var data_path := "res://scenes/maps/%s_data.tres" % map_name
	if not (ResourceLoader.exists(scene_path) and ResourceLoader.exists(data_path)):
		return false
	var data: MapData = load(data_path) as MapData
	var packed: PackedScene = load(scene_path) as PackedScene
	if data == null or packed == null:
		return false
	var root: Node2D = packed.instantiate() as Node2D
	if root == null:
		return false
	add_child(root)
	register_chunk(map_name, data, root, origin)
	# Every chunk's skirt, not just this one's: a newly loaded neighbour takes
	# ownership of cells an existing chunk was skirting over, so the seam only
	# closes if the OTHER side repaints too.
	refresh_skirts()
	return true


## The registry half, split from the loading half so it can be driven with
## synthetic MapData and a bare Node2D. The coordinate maths is the part worth
## testing and it has nothing to do with disk.
func register_chunk(map_name: String, data: MapData, root: Node2D,
		origin: Vector2i = Vector2i.ZERO) -> void:
	_chunks[map_name] = {"data": data, "root": root, "origin": origin}
	if root != null:
		root.position = Vector2(origin) * CELL
		apply_plane_z(root)


## Which border metatile falls at a given LOCAL cell, including negative ones.
##
## Ported from `GetBorderBlockAt` (src/fieldmap.c:53-70): the block tiles by
## modulo on the map's own local coordinates, so the pattern's parity runs
## continuously outward rather than restarting at the map edge.
##
## Source biases by `8 * borderWidth` before taking the modulo, because C's `%`
## keeps the sign of the dividend and a negative index would read out of the
## array. GDScript's `%` has exactly the same behaviour, so the guard is
## needed here too — written as a general positive modulo rather than a copied
## magic bias, which also drops source's implicit assumption that no
## coordinate is more than 8 blocks outside the map.
static func border_metatile_at(d: MapData, local: Vector2i) -> int:
	if d == null or d.border.is_empty():
		return -1
	var bw: int = maxi(1, d.border_width)
	var bh: int = maxi(1, d.border_height)
	var xp := ((local.x % bw) + bw) % bw
	var yp := ((local.y % bh) + bh) % bh
	var i := xp + yp * bw
	return d.border[i] if i < d.border.size() else -1


## The layer type of the border metatile at a local cell, tiled identically to
## `border_metatile_at` so the two never disagree about which entry they mean.
static func border_layer_type_at(d: MapData, local: Vector2i) -> int:
	if d == null or d.border_layer_type.is_empty():
		return -1
	var bw: int = maxi(1, d.border_width)
	var bh: int = maxi(1, d.border_height)
	var xp := ((local.x % bw) + bw) % bw
	var yp := ((local.y % bh) + bh) % bh
	var i := xp + yp * bw
	return d.border_layer_type[i] if i < d.border_layer_type.size() else -1


## Paint every chunk's skirt over ground nobody owns.
##
## Deliberately "wherever no chunk owns the cell" rather than "on edges with no
## connection". The two differ in ways that matter: the corridor has 3 dangling
## connections whose neighbours are real in source but unbaked, and those edges
## need a skirt exactly like an edge with no connection at all. It also means
## C4 needs no new edge logic — when a neighbour loads, its cells acquire an
## owner and re-running this clears the skirt that covered them.
func refresh_skirts() -> void:
	for map_name in _chunks:
		_paint_skirt(map_name)


func _paint_skirt(map_name: String) -> void:
	var c: Dictionary = _chunks[map_name]
	var d: MapData = c["data"]
	var root: Node2D = c["root"]
	if d == null or root == null or not is_instance_valid(root) or d.border.is_empty():
		return
	var ground: TileMapLayer = root.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return

	# One layer per plane. All three share the chunk's single TileSet — the
	# baker gives every baked layer the same one, with the three atlases as
	# sources 0/1/2 — so the plane index doubles as the source id, exactly as
	# in map_baker's own set_cell call.
	var skirts: Array[TileMapLayer] = []
	for plane in range(SKIRT_LAYERS.size()):
		var nm: String = SKIRT_LAYERS[plane]
		var layer: TileMapLayer = root.get_node_or_null(nm) as TileMapLayer
		if layer == null:
			layer = TileMapLayer.new()
			layer.name = nm
			layer.tile_set = ground.tile_set
			root.add_child(layer)
			# Below every baked layer, in plane order among themselves. Skirt
			# cells never overlap map cells, so skirt-vs-map order is free;
			# skirt-vs-skirt order is not, or an overhang would draw under its
			# own ground. add_child appends, so each has to be moved.
			root.move_child(layer, plane)
		layer.clear()
		skirts.append(layer)
	apply_plane_z(root)

	var origin: Vector2i = c["origin"]
	var has_types := d.border_layer_type.size() == d.border.size()
	for y in range(-SKIRT_DEPTH, d.height + SKIRT_DEPTH):
		for x in range(-SKIRT_DEPTH, d.width + SKIRT_DEPTH):
			var local := Vector2i(x, y)
			# Skip anything a chunk owns — this chunk's own cells, and (once C4
			# lands) a neighbour's, which is what makes a seam close up.
			if chunk_owning(origin + local) != "":
				continue
			var mid := border_metatile_at(d, local)
			if mid < 0:
				continue
			var coords := Vector2i(mid % ATLAS_COLS, int(mid / ATLAS_COLS))
			# A map imported before border_layer_type existed has none; fall
			# back to the ground plane rather than painting nothing, so an old
			# artifact degrades to the previous behaviour instead of a void.
			var lt: int = border_layer_type_at(d, local) if has_types else 1
			for plane in ROUTING.get(lt, [0]):
				skirts[plane].set_cell(local, plane, coords)


## Give a chunk's layers their plane z. Idempotent, and silent about children
## it does not recognise — a synthetic chunk in a test has none of these, and a
## baked one gains its skirt layers later.
static func apply_plane_z(root: Node2D) -> void:
	if root == null or not is_instance_valid(root):
		return
	for c in root.get_children():
		if c is CanvasItem and PLANE_Z.has(c.name):
			(c as CanvasItem).z_index = PLANE_Z[c.name]


func unload_chunk(map_name: String) -> void:
	if not _chunks.has(map_name):
		return
	var root: Node2D = _chunks[map_name]["root"]
	if root != null and is_instance_valid(root):
		root.queue_free()
	_chunks.erase(map_name)
	# [M27C C4] Repaint what is left. Cells this chunk owned are now unowned, so
	# whichever neighbour was skirting up to that seam has to extend over them
	# again — otherwise unloading leaves a hole exactly where the map used to be.
	# Flagged as debt when the skirt landed in C3, unreachable until now because
	# only one chunk was ever live.
	refresh_skirts()


func loaded_chunks() -> Array:
	return _chunks.keys()


func origin_of(map_name: String) -> Vector2i:
	if not _chunks.has(map_name):
		return Vector2i.ZERO
	return _chunks[map_name]["origin"]


## Which chunk's bounds contain this global cell, or "" for the gap between and
## around them. That gap is real and expected: it is where the border skirt
## goes (C3), and a caller must treat it as impassable rather than assuming
## every coordinate belongs to somebody.
func chunk_owning(gcell: Vector2i) -> String:
	for map_name in _chunks:
		var c: Dictionary = _chunks[map_name]
		var d: MapData = c["data"]
		var o: Vector2i = c["origin"]
		if d == null:
			continue
		var l := gcell - o
		if l.x >= 0 and l.y >= 0 and l.x < d.width and l.y < d.height:
			return map_name
	return ""


## Global cell -> the owning chunk's own local cell. Meaningless without an
## owner, so callers check `chunk_owning()` first; the unowned answer is the
## input unchanged rather than a sentinel, because there is no correct local
## coordinate for a cell nobody owns.
func local_of(gcell: Vector2i) -> Vector2i:
	var map_name := chunk_owning(gcell)
	if map_name == "":
		return gcell
	return gcell - Vector2i(_chunks[map_name]["origin"])


## Where a node PARENTED INTO a chunk must sit to appear at `gcell`.
##
## [M27C C4] Chunk roots are positioned at `origin * CELL`, so a child's
## `position` is already relative to that — assigning a GLOBAL cell's pixels
## there displaces the node by the whole origin. That is not hypothetical: the
## player teleported to the top of Route 1 on the first real seam crossing,
## exactly `Route1.height` cells off, because the step tween targeted
## `Vector2(global_cell) * CELL` while the node had just been reparented into a
## chunk whose root is at y = -640.
##
## Invisible until C4 for the same reason everything else in this class was: at
## origin (0,0) local and global pixels are equal, so the wrong version and the
## right one are indistinguishable on a single map.
func local_pixel_of(gcell: Vector2i) -> Vector2:
	return Vector2(local_of(gcell)) * CELL


func data_at(gcell: Vector2i) -> MapData:
	var map_name := chunk_owning(gcell)
	return _chunks[map_name]["data"] if map_name != "" else null


## --- the per-cell queries, routed to whichever chunk owns the cell ---
##
## Unowned cells report as solid ground at elevation 0. That is the
## conservative answer in both directions: a step into nowhere is refused, and
## nothing falls through the world while C3's skirt does not exist yet.
func collision_at(gcell: Vector2i) -> int:
	var d := data_at(gcell)
	if d == null:
		return 1
	var l := local_of(gcell)
	return d.collision_at(l.x, l.y)


func elevation_at(gcell: Vector2i) -> int:
	var d := data_at(gcell)
	if d == null:
		return 0
	var l := local_of(gcell)
	return d.elevation_at(l.x, l.y)


func priority_at(gcell: Vector2i) -> int:
	var d := data_at(gcell)
	if d == null:
		return 2
	var l := local_of(gcell)
	return d.priority_at(l.x, l.y)


func in_bounds(gcell: Vector2i) -> bool:
	return chunk_owning(gcell) != ""


## --- the StepResolver cell-source seam, in GLOBAL cells -----------------------
##
## [M27C C4] Four methods, `(x, y) -> value`, matching MapData's own signatures
## so a StepResolver built on this manager runs the identical step rules across
## a chunk seam that it runs inside one map. See StepResolver's `_cells`.
##
## `behavior_at` is what makes ledges and §1.7's directional rules work at a
## seam; C2 routed collision, elevation and priority but not this, because
## nothing had yet needed to resolve a step through the manager.
func behavior_at(gcell: Vector2i) -> int:
	var d := data_at(gcell)
	if d == null:
		return -1
	var l := local_of(gcell)
	return d.behavior_at(l.x, l.y)


## `GlobalCells(manager)` is what you hand to StepResolver.
##
## This manager speaks Vector2i throughout; StepResolver's seam speaks (x, y),
## matching MapData's own signatures. Rather than rely on the two happening to
## agree — which would make the seam an accident of naming, and would break
## silently the first time either side changed a signature — the adaptation is
## an explicit object whose whole job is the conversion.
class GlobalCells extends RefCounted:
	var _mm: MapManager

	func _init(mm: MapManager) -> void:
		_mm = mm

	func in_bounds(x: int, y: int) -> bool:
		return _mm.in_bounds(Vector2i(x, y))

	func collision_at(x: int, y: int) -> int:
		return _mm.collision_at(Vector2i(x, y))

	func elevation_at(x: int, y: int) -> int:
		return _mm.elevation_at(Vector2i(x, y))

	func behavior_at(x: int, y: int) -> int:
		return _mm.behavior_at(Vector2i(x, y))


## A resolver that steps in GLOBAL cells, across seams, using the same rules.
func global_resolver() -> StepResolver:
	return StepResolver.new(GlobalCells.new(self))


## Where a neighbour's own (0,0) sits, given a connection on `host`.
##
## Ported from FillSouthConnection / FillNorthConnection / FillWestConnection /
## FillEastConnection (src/fieldmap.c). Source expresses these as fills into a
## padded backup grid; dropping MAP_OFFSET (7), which is only that padding,
## leaves the relation between two maps' origins.
##
## THE ASYMMETRY IS REAL AND LOAD-BEARING. `offset` always shifts along the
## SHARED EDGE — x for north/south, y for west/east. But the perpendicular term
## uses the HOST's dimension going south/east (push the neighbour past this map)
## and the NEIGHBOUR's going north/west (pull it back by its own extent).
## Written uniformly it would look tidy and stitch the region inside out.
##
## Validated by walking the corridor's connection graph from Pallet Town: 12
## edges, ZERO reciprocal conflicts, and the resulting layout is real Kanto
## geography — Viridian City lands at x = -12 precisely because it is 48 wide
## against Route 1's 24.
static func neighbour_origin(host_origin: Vector2i, host: MapData,
		conn: Dictionary, neighbour: MapData) -> Vector2i:
	var off: int = int(conn.get("offset", 0))
	match int(conn.get("direction", MapData.Connection.NONE)):
		MapData.Connection.NORTH:
			return host_origin + Vector2i(off, -neighbour.height)
		MapData.Connection.SOUTH:
			return host_origin + Vector2i(off, host.height)
		MapData.Connection.WEST:
			return host_origin + Vector2i(-neighbour.width, off)
		MapData.Connection.EAST:
			return host_origin + Vector2i(host.width, off)
	# DIVE/EMERGE warp rather than stitching, and loadable_connections() already
	# drops them — reaching here means a caller bypassed it.
	return host_origin


## Load every baked neighbour of an already-loaded chunk.
##
## Returns the names loaded. Uses `loadable_connections()`, so DIVE/EMERGE and
## unbaked destinations are excluded by the same rule the skirt keys on: an
## edge that yields nothing here is an edge that stays skirted.
func load_neighbours(map_name: String) -> Array[String]:
	var added: Array[String] = []
	if not _chunks.has(map_name):
		return added
	var host: MapData = _chunks[map_name]["data"]
	var host_origin: Vector2i = _chunks[map_name]["origin"]
	if host == null:
		return added
	for c in host.loadable_connections():
		var nb := MapConstants.map_name_for(str(c.get("map", "")))
		if nb == "" or _chunks.has(nb):
			continue
		var nb_data: MapData = load("res://scenes/maps/%s_data.tres" % nb) as MapData
		if nb_data == null:
			continue
		if load_chunk(nb, neighbour_origin(host_origin, host, c, nb_data)):
			added.append(nb)
	return added


## The two entity containers of whichever chunk owns this cell, keyed by draw
## priority. An entity crossing a seam changes which chunk's containers it
## belongs to, not just which container — which is why this is looked up per
## cell rather than cached once at spawn.
func strata_at(gcell: Vector2i) -> Dictionary:
	var map_name := chunk_owning(gcell)
	if map_name == "":
		return {}
	var root: Node2D = _chunks[map_name]["root"]
	if root == null or not is_instance_valid(root):
		return {}
	return {
		2: root.get_node_or_null("Entities_P2"),
		1: root.get_node_or_null("Entities_P1"),
	}
