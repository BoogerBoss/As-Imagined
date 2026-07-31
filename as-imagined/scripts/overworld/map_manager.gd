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

## Where map_baker writes the shared per-pair TileSets (M27M2).
const TILESET_DIR := "res://assets/map_tilesets/"

## Atlas geometry, matching map_baker.gd — the skirt paints from the same
## atlas the chunk's own Ground layer uses, so a border metatile id converts
## to atlas coords exactly as a map cell does.
const ATLAS_COLS := 32

## How far past a chunk's own bounds the skirt reaches, PER AXIS.
##
## Measured: the canvas is 1024x768 (M26A1) at camera zoom 3, so the visible
## region is 21.3 x 16.0 cells and the half-extent from an edge cell is
## 10.7 x 8.0. Plus one cell for the camera's smoothing lag, measured at 11px
## (~0.7 cells) crossing a seam.
##
## PER AXIS because the screen is wider than it is tall in cells, and a single
## depth sized for the wider one over-covers the vertical by 100%. At a flat 16
## a 24x20 map carried 2432 skirt cells around 480 real ones; 12 x 9 makes that
## 1344, a 45% cut in what is the dominant cost of loading a chunk.
##
## An earlier version of this comment justified 16 partly as headroom for
## "non-native window sizes". That was wrong: stretch mode is `canvas_items`
## with aspect `keep`, so the visible WORLD area is fixed and letterboxing
## preserves it rather than revealing more.
const SKIRT_DEPTH_X := 12
const SKIRT_DEPTH_Y := 9

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

## Neighbours whose resources are being parsed on a background thread.
##
## [M27C C4] Loading a neighbour synchronously cost 41 ms inside ONE _try_step
## — measured crossing into Route 1, which loads VIRIDIAN CITY, not Route 1.
## That is two and a half frames of blocking during a step, and very visible.
## Roughly 28 of those 41 ms is ResourceLoader parsing the scene and data, so
## that part moves off-thread and only instantiate/place/repaint stays.
var _pending: Dictionary = {}

## Skirt repaints owed, one popped per frame.
##
## [M27C C4] Instantiating a chunk and painting its skirt in the same frame
## measured 14.6 ms for a 48x40 map — a single frame right at the 60fps budget.
## They are independent, and a freshly loaded neighbour is a whole map away
## from the player, so its skirt can wait a frame. The SYNC path still paints
## immediately: startup and the tests want a chunk fully formed on return.
## Chunk NAMES waiting for a skirt repaint, at most one paid per frame.
##
## [M27D perf] Was a queue of RECTS, and one rect could repaint several chunks
## in a single call — measured at 4.8 ms for one, and a chunk's skirt is 4-7k
## `set_cell` calls (2256 cells x 3 planes for Viridian City). Splitting per
## chunk turns one spike into several cheap frames.
var _skirt_queue: Array[String] = []

## map_name -> { local Vector2i : true } for every cell an entity blocks.
##
## [M27D D2] A set rather than a per-step scan of the scene tree: a step already
## costs a resolve, and walking every entity of every live chunk per step is the
## same per-cell cost that made C4's skirt repaint 4000 dictionary walks. Built
## once at install, and rebuildable — which is the shape D3 needs when NPCs
## start moving.
var _occupancy: Dictionary = {}

## Where the player is standing, in GLOBAL cells, or a sentinel when unset.
##
## [M27D D3 follow-up] The player is not a placed entity — it is spawned by the
## overworld controller, not baked into a map — so it was absent from the
## occupancy set entirely and NPCs walked straight through it. Measured: the
## player's own cell reported `entity_at` false and a step into it resolved to
## NONE.
##
## Kept as one cell rather than by registering a node, because the manager
## should not need to know what a player IS to know a square is taken. D4 wants
## the same fact for trainer sight.
var _player_cell := Vector2i(-2147483648, -2147483648)


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
	return _install_chunk(map_name, load(data_path) as MapData,
			load(scene_path) as PackedScene, origin)


## The main-thread half of loading: instantiate, place, repaint. Split out so
## the threaded path can share it, and deliberately small — this is all that
## still blocks once resource parsing happens off-thread.
func _install_chunk(map_name: String, data: MapData, packed: PackedScene,
		origin: Vector2i, defer_skirt: bool = false) -> bool:
	if data == null or packed == null:
		return false
	var root: Node2D = packed.instantiate() as Node2D
	if root == null:
		return false
	add_child(root)
	register_chunk(map_name, data, root, origin)
	# Not just this chunk's skirt: a newly loaded neighbour takes ownership of
	# cells an existing chunk was skirting over, so the seam only closes if the
	# OTHER side repaints too. Scoped to chunks that reach these cells.
	if defer_skirt:
		# The new chunk first: its own tiles are the ones a neighbour's stale
		# skirt is currently painted over, so repainting it first is what
		# shortens the visible seam rather than merely spreading the cost.
		_enqueue_skirt(map_name)
		for other in _chunks_reaching(chunk_rect(map_name)):
			_enqueue_skirt(other)
	else:
		refresh_skirts_near(chunk_rect(map_name))
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
	rebuild_occupancy(map_name)


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


## The cells a chunk covers, and the wider box its skirt can reach into.
func chunk_rect(map_name: String) -> Rect2i:
	if not _chunks.has(map_name):
		return Rect2i()
	var d: MapData = _chunks[map_name]["data"]
	if d == null:
		return Rect2i()
	return Rect2i(_chunks[map_name]["origin"], Vector2i(d.width, d.height))


## Repaint only the chunks a change at `rect` could actually have altered.
##
## [M27C C4] The full sweep is O(chunks) per load and became the dominant cost
## once shared TileSets removed the resource-load stall — 23.8 ms to repaint
## four chunks when only one or two could possibly have changed. A chunk's
## skirt only differs if its own skirt REGION — its bounds grown by the skirt
## depth — reaches into the cells that changed hands.
func refresh_skirts_near(rect: Rect2i) -> void:
	for map_name in _chunks_reaching(rect):
		_paint_skirt(map_name)


## Which live chunks' skirt regions reach into `rect`.
func _chunks_reaching(rect: Rect2i) -> Array[String]:
	var grow := Vector2i(SKIRT_DEPTH_X, SKIRT_DEPTH_Y)
	var out: Array[String] = []
	for map_name in _chunks:
		var r := chunk_rect(map_name)
		if r.size == Vector2i.ZERO:
			continue
		if Rect2i(r.position - grow, r.size + grow * 2).intersects(rect):
			out.append(map_name)
	return out


## Queue a chunk's skirt for a later frame, without queuing it twice.
func _enqueue_skirt(map_name: String) -> void:
	if not _skirt_queue.has(map_name):
		_skirt_queue.append(map_name)


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

	# Ownership as RECTS in this chunk's own local space, resolved once.
	#
	# [M27C C4] This inner loop runs ~4000 times per repaint, and calling
	# chunk_owning() per cell meant a Dictionary walk, a Vector2i allocation and
	# a String return every time — measured at ~13 ms for one 48x40 chunk, which
	# was the whole remaining hitch after resource loading went off-thread.
	# Rect2i.has_point against a two-entry array is the same answer without any
	# of that.
	var own := Rect2i(Vector2i.ZERO, Vector2i(d.width, d.height))
	var others: Array[Rect2i] = []
	for other_name in _chunks:
		if other_name == map_name:
			continue
		var r := chunk_rect(other_name)
		if r.size != Vector2i.ZERO:
			others.append(Rect2i(r.position - origin, r.size))

	for y in range(-SKIRT_DEPTH_Y, d.height + SKIRT_DEPTH_Y):
		for x in range(-SKIRT_DEPTH_X, d.width + SKIRT_DEPTH_X):
			var local := Vector2i(x, y)
			# Skip anything a chunk owns — this chunk's own cells, and a
			# neighbour's, which is what makes a seam close up.
			if own.has_point(local):
				continue
			var taken := false
			for r in others:
				if r.has_point(local):
					taken = true
					break
			if taken:
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
	_occupancy.erase(map_name)
	var root: Node2D = _chunks[map_name]["root"]
	if root != null and is_instance_valid(root):
		root.queue_free()
	# Captured BEFORE the erase: the rect is what the repaint scopes to, and it
	# stops existing the moment the chunk does.
	var vacated := chunk_rect(map_name)
	_chunks.erase(map_name)
	# [M27C C4] Repaint what is left. Cells this chunk owned are now unowned, so
	# whichever neighbour was skirting up to that seam has to extend over them
	# again — otherwise unloading leaves a hole exactly where the map used to be.
	# Flagged as debt when the skirt landed in C3, unreachable until now because
	# only one chunk was ever live.
	refresh_skirts_near(vacated)


func loaded_chunks() -> Array:
	return _chunks.keys()


## Drop every live chunk. Used by a warp, which is a HARD boundary.
##
## [M27C C5] A connection is continuous — the player walks across it, so it has
## to stream. A warp is not: the player takes a door and expects a cut, so the
## whole registry is cleared and the destination is loaded on its own. That is
## also closer to source than the streaming is, since `LoadMapFromCameraTransition`
## keeps ONE map live and swaps it wholesale.
##
## The payoff is that the destination can always go at (0, 0): with nothing else
## live there is nothing to collide with, so free-origin allocation and the
## overlap constraint on `chunk_owning()` — first match over an UNORDERED
## Dictionary, and so nondeterministic if two chunks ever overlapped — both stop
## being problems rather than being solved.
##
## ANYTHING PARENTED INTO A CHUNK IS FREED WITH IT. The player lives inside one
## for draw order, so a caller must move it out first; the camera already lives
## outside for exactly this reason (see overworld.gd).
func unload_all() -> void:
	# Copied: unload_chunk erases from the dictionary being iterated.
	for map_name in loaded_chunks().duplicate():
		unload_chunk(map_name)


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

	func entity_at(x: int, y: int) -> bool:
		return _mm.entity_at(Vector2i(x, y))


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
## Start background loads for a chunk's baked neighbours. Non-blocking.
##
## Returns how many requests were started. The origin cannot be computed yet —
## north/west placement needs the NEIGHBOUR's own dimensions — so the host
## frame is recorded and the origin derived at completion, when its MapData has
## actually arrived.
func request_neighbours(map_name: String) -> int:
	if not _chunks.has(map_name):
		return 0
	var host: MapData = _chunks[map_name]["data"]
	var host_origin: Vector2i = _chunks[map_name]["origin"]
	if host == null:
		return 0
	var started := 0
	for c in host.loadable_connections():
		var nb := MapConstants.map_name_for(str(c.get("map", "")))
		if nb == "" or _chunks.has(nb) or _pending.has(nb):
			continue
		var sp := "res://scenes/maps/%s.tscn" % nb
		var dp := "res://scenes/maps/%s_data.tres" % nb
		if not (ResourceLoader.exists(sp) and ResourceLoader.exists(dp)):
			continue
		ResourceLoader.load_threaded_request(sp)
		ResourceLoader.load_threaded_request(dp)
		_pending[nb] = {"scene": sp, "data": dp, "host": host,
				"host_origin": host_origin, "conn": c}
		started += 1
	return started


func _process(_delta: float) -> void:
	# Skirts first, and only when nothing installed this frame — the two are the
	# frame's two expensive jobs and doing both at once is what this avoids.
	if not _skirt_queue.is_empty():
		_paint_skirt(_skirt_queue.pop_front())
		return
	_poll_pending()


## Install at most ONE finished chunk per frame.
##
## Deliberately one: two neighbours arriving together would otherwise stack
## their instantiate-and-repaint cost into a single frame, which is the hitch
## this exists to remove.
func _poll_pending() -> void:
	for nb in _pending.keys():
		var p: Dictionary = _pending[nb]
		var s_scene := ResourceLoader.load_threaded_get_status(p["scene"])
		var s_data := ResourceLoader.load_threaded_get_status(p["data"])
		if (s_scene == ResourceLoader.THREAD_LOAD_IN_PROGRESS
				or s_data == ResourceLoader.THREAD_LOAD_IN_PROGRESS):
			continue
		_pending.erase(nb)
		if (s_scene != ResourceLoader.THREAD_LOAD_LOADED
				or s_data != ResourceLoader.THREAD_LOAD_LOADED):
			continue
		var data: MapData = ResourceLoader.load_threaded_get(p["data"]) as MapData
		var packed: PackedScene = ResourceLoader.load_threaded_get(p["scene"]) as PackedScene
		if data != null and packed != null:
			_install_chunk(nb, data, packed,
					neighbour_origin(p["host_origin"], p["host"], p["conn"], data), true)
		return


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


## The triggering warp standing on a global cell, or null.
##
## [M27C C5] Scoped to the OWNING chunk rather than every live one, because a
## warp only exists in its own map's coordinate space and the seam between two
## chunks is exactly where a whole-registry scan would answer for the wrong one.
##
## `triggers == false` reads as absent, not as a disabled warp: those cells are
## the flanking tiles of multi-tile doorways, where exactly one tile fires.
## Treating them as present would silently widen every doorway in the region.
func warp_at(gcell: Vector2i) -> Warp:
	var map_name := chunk_owning(gcell)
	if map_name == "":
		return null
	var root: Node2D = _chunks[map_name]["root"]
	if root == null or not is_instance_valid(root):
		return null
	var local := gcell - Vector2i(_chunks[map_name]["origin"])
	for n in root.find_children("*", "Warp", true, false):
		var w := n as Warp
		if w != null and w.triggers and w.cell == local:
			return w
	return null


## Where arriving at `warp_id` on `map_name` puts the player, in GLOBAL cells.
##
## [M27C C5] Source lands the player ON the destination warp's own tile —
## `SetPlayerCoordsFromWarp` (overworld.c:685-687) assigns `warps[warpId].x/y`
## directly, with no adjacent-tile or facing offset. So entering Oak's Lab
## leaves you standing on the lab's own door.
##
## That does not re-trigger, and needs no guard, because warps fire from
## `TryStartStepBasedScript` under `input->tookStep` — arriving is not a step.
## The guard is free ONLY while the check lives in the step path; a per-frame
## "am I on a warp" poll would bounce the player between two doors forever.
##
## The chunk must already be loaded — resolution reads the destination's own
## live Warp nodes rather than a copy in MapData, so there is one source of
## truth for a warp's position and no second place to keep in step.
##
## Returns {} rather than a sentinel cell when the chunk is absent or carries
## no such index, so an unresolvable warp fails loudly instead of teleporting
## the player somewhere arbitrary.
func warp_arrival(map_name: String, warp_id: int) -> Dictionary:
	if warp_id < 0 or not _chunks.has(map_name):
		return {}
	var root: Node2D = _chunks[map_name]["root"]
	if root == null or not is_instance_valid(root):
		return {}
	for n in root.find_children("*", "Warp", true, false):
		var w := n as Warp
		if w != null and w.warp_id == warp_id:
			return {"cell": w.cell + Vector2i(_chunks[map_name]["origin"]), "warp": w}
	return {}


## Recompute which cells of a chunk are blocked by a placed entity.
##
## [M27D D2] Only `npc`, `trainer` and `item_ball` block, and that is source's
## rule rather than a choice: `DoesObjectCollideWithObjectAt` consults the
## `object_events` array and nothing else, so warps, triggers and signs occupy
## no collision slot — which is why a trainer sees straight over a doormat and
## why you can stand on one.
##
## Falls out of this: the region's 210 HM obstacles (97 breakable rocks, 55
## cuttable trees, 58 pushable boulders) are object events, so every one becomes
## solid here with no obstacle-specific code.
##
## NOT yet gated on `visibility_flag`. Source hides a flagged-away object event
## and stops it colliding; nothing reads flags until the store lands in D4, so
## every placed entity currently blocks. Recorded rather than silently assumed.
func rebuild_occupancy(map_name: String) -> void:
	var out := {}
	if _chunks.has(map_name):
		var root: Node2D = _chunks[map_name]["root"]
		if root != null and is_instance_valid(root):
			for n in root.find_children("*", "OverworldEntity", true, false):
				var e := n as OverworldEntity
				if e != null and (e is NPC or e is ItemBall):
					out[e.cell] = true
	_occupancy[map_name] = out


## Is a placed entity standing on this GLOBAL cell?
func set_player_cell(gcell: Vector2i) -> void:
	_player_cell = gcell


func entity_at(gcell: Vector2i) -> bool:
	if gcell == _player_cell:
		return true
	var map_name := chunk_owning(gcell)
	if map_name == "":
		return false
	var occ: Dictionary = _occupancy.get(map_name, {})
	if occ.is_empty():
		return false
	return occ.has(gcell - Vector2i(_chunks[map_name]["origin"]))


## Every trainer whose sight line currently reaches the player.
##
## [M27D D4] Ported from `GetTrainerApproachDistance` + `CheckPathBetweenTrainerAndPlayer`
## (`trainer_see.c:636,708`). Returns one entry per seeing trainer:
##   {"trainer": TrainerNPC, "map": String, "dir": int, "distance": int}
## ordered by `local_id`, which is source's own ordering — `CheckForTrainersWantingBattle`
## sorts its candidate array by `localId` before walking it, so which of two
## simultaneous trainers gets the battle is data, not scene-tree order.
##
## GEOMETRY ONLY. Whether a seeing trainer should actually battle — already
## beaten, hidden by a flag — is the caller's question, because this node has no
## game state and giving it one to answer that would be the wrong seam.
##
## THE FACING IS THE LIVE ONE, not the template's. Source reads
## `trainerObj->facingDirection`, so a rotating trainer genuinely sees whichever
## way it happens to be turned. `MapOverlay.trainer_sight_cells` draws rays only
## for FIXED-facing trainers, which is right for a static editor view and wrong
## here — that restriction would blind the 97 rotating and 74 walking trainers
## in Kanto (39.6% of the roster) at runtime.
func trainers_seeing_player() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _player_cell.x == -2147483648:
		return out
	for map_name in _chunks:
		var root: Node2D = _chunks[map_name]["root"]
		if root == null or not is_instance_valid(root):
			continue
		var origin: Vector2i = _chunks[map_name]["origin"]
		for n in root.find_children("*", "TrainerNPC", true, false):
			var t := n as TrainerNPC
			if t == null or t.sight_range <= 0:
				continue
			var hit := sight_reaches_player(t.cell + origin, t.facing(),
					t.sight_range, t.elevation)
			if hit <= 0:
				continue
			out.append({"trainer": t, "map": map_name, "dir": t.facing(),
					"distance": hit})
	out.sort_custom(func(a, b): return _local_id_of(a) < _local_id_of(b))
	return out


static func _local_id_of(entry: Dictionary) -> String:
	var t := entry["trainer"] as TrainerNPC
	return t.local_id if t != null else ""


## How far ahead the player is along `dir` from `from`, or 0 for no sight.
##
## Source splits this across five functions; the four directional ones
## (`GetTrainerApproachDistanceSouth` and siblings) all reduce to the same test —
## the player is on the shared axis, strictly beyond the trainer, and within
## `range` — so they collapse into one here rather than being transcribed four
## times with the comparison operators permuted.
##
## The returned value is a DISTANCE, 1-based: 1 means the player is directly in
## front. Source relies on that offset (`InitTrainerApproachTask` is handed
## `approachDistance - 1`, so the trainer walks up to be ADJACENT to the player
## rather than onto them).
func sight_reaches_player(from: Vector2i, dir: int, sight_range: int,
		elevation: int) -> int:
	if sight_range <= 0 or not StepResolver.STEP.has(dir):
		return 0
	var step: Vector2i = StepResolver.STEP[dir]
	var delta := _player_cell - from
	# Must be on the ray's own axis, and strictly ahead of it.
	var distance := delta.x * step.x + delta.y * step.y
	if distance <= 0 or distance > sight_range:
		return 0
	if delta != step * distance:
		return 0

	# Cells strictly BETWEEN trainer and player must be clear. Source walks
	# `approachDistance - 1` intermediate cells and stops on any collision but
	# COLLISION_OUTSIDE_RANGE — i.e. directional impassability, an elevation
	# mismatch and another object event each break the line, not just terrain.
	# Routing through the resolver is what makes that true here without
	# restating any of it: a sight line can never disagree with the movement
	# rules it describes.
	var r := global_resolver()
	if r == null:
		return 0
	var c := from
	for _i in range(distance - 1):
		var res: Dictionary = r.resolve(c, dir, elevation)
		if int(res["outcome"]) != StepResolver.Outcome.NONE:
			return 0
		c += step
		if entity_at(c):
			return 0
	# Source's final check is that the last cell collides with an OBJECT EVENT —
	# that is how it confirms the player is really standing there. Here the ray
	# was derived from the player's own cell, so it holds by construction.
	return distance


## Advance every live NPC's own movement by one frame.
##
## [M27D D3] Driven from here rather than each NPC's own `_process` because
## moving one is not a private act: the destination has to clear terrain, the
## wander box AND every other entity, and the occupancy set has to stay true
## afterwards. An NPC cannot answer any of that alone, and giving each a
## back-reference to the manager would be the same coupling with more copies.
##
## `reserved` is belt-and-braces, NOT the thing preventing double-occupancy.
## An earlier note here claimed two NPCs ticking in one frame could both take a
## cell because occupancy updated late — that was wrong, and measuring killed
## it: `move_entity` runs synchronously inside this loop, so a later NPC in the
## same tick already sees the cell taken. The set only guards the case of two
## NPCs wanting a cell neither currently occupies.
func tick_entities(delta: float, rng: RandomNumberGenerator) -> void:
	var reserved := {}
	for map_name in _chunks:
		var root: Node2D = _chunks[map_name]["root"]
		if root == null or not is_instance_valid(root):
			continue
		var origin: Vector2i = _chunks[map_name]["origin"]
		for n in root.find_children("*", "NPC", true, false):
			var npc := n as NPC
			if npc == null:
				continue
			var want: Vector2i = npc.tick(delta, rng)
			if want == npc.cell:
				continue
			if not npc.within_range(want):
				continue
			var g: Vector2i = origin + want
			if reserved.has(g):
				continue
			# Full step rules, not just the collision bit: a wandering NPC obeys
			# ledges, directional tiles and elevation exactly as the player does,
			# because it walks through the same resolver.
			var r := _resolver_for(map_name).resolve(
					origin + npc.cell, _dir_towards(npc.cell, want), npc.elevation)
			if int(r["outcome"]) != StepResolver.Outcome.NONE:
				continue
			reserved[g] = true
			move_entity(map_name, npc, want)


static func _dir_towards(from: Vector2i, to: Vector2i) -> int:
	var d := to - from
	if d.y > 0:
		return StepResolver.Dir.SOUTH
	if d.y < 0:
		return StepResolver.Dir.NORTH
	if d.x < 0:
		return StepResolver.Dir.WEST
	return StepResolver.Dir.EAST


var _resolver_cache: Dictionary = {}


func _resolver_for(_map_name: String) -> StepResolver:
	# One global resolver, not one per chunk: a wandering NPC near a seam has to
	# see the neighbouring map's terrain, and a per-chunk resolver would report
	# its own edge as out of bounds.
	if not _resolver_cache.has("global"):
		_resolver_cache["global"] = global_resolver()
	return _resolver_cache["global"]


## Move a placed entity to a new LOCAL cell, keeping occupancy true.
##
## Incremental rather than a rebuild: `rebuild_occupancy` walks every entity of
## the chunk, and doing that per NPC per step is the per-cell cost C4 already
## paid for once with the skirt repaint.
func move_entity(map_name: String, e: OverworldEntity, to: Vector2i) -> void:
	if not _chunks.has(map_name):
		return
	var occ: Dictionary = _occupancy.get(map_name, {})
	occ.erase(e.cell)
	e.cell = to
	occ[to] = true
	_occupancy[map_name] = occ


## Every pair TileSet, loaded once at boot and HELD for the process lifetime.
##
## Static deliberately. A `MapManager` is a scene node and dies with its scene —
## a battle, a title screen, any `change_scene_to_file` — and the whole point is
## residence across all of that. This project already uses class-level statics
## for exactly this (`BattleSetupContext`), and they need no autoload
## registration, so this is the established shape rather than a new one.
##
## HOLDING THE REFERENCE IS THE MECHANISM. `ResourceLoader`'s own cache is not a
## guarantee — an entry with no live reference can be evicted, and then the next
## first visit pays the full cost again with nothing to show why. The dictionary
## is what makes "loaded once" true.
static var _preloaded: Dictionary = {}


## Load every pair TileSet under `dir` and hold it. Returns pairs loaded.
##
## [M27D perf / preload] MEASURED before writing this: a single pair costs
## **16.4 ms** cold in a fresh process, and **23.6 ms** when the OS file cache is
## cold too. That is paid on the first visit to any map whose pair has not been
## built yet — exactly the "hitch transitioning to a map for the first time"
## Rob reported. 14 pairs back the 32-map corridor, 60 the region.
##
## Work is RELOCATED, not reduced: this is not the M27M trim. No tile definition
## changes, no atlas or `.tres` content changes. The same milliseconds are spent,
## once, at boot where a pause is expected, instead of mid-step where it is not.
##
## SYNCHRONOUS, replacing the threaded `warm_tilesets` this supersedes. That one
## fired `load_threaded_request` and kept no reference, so it neither guaranteed
## residence nor reported whether it had worked; keeping both would be two
## mechanisms for one job, which is the duplication shape that has bitten this
## project before (`check_bake_diff` vs `map_baker._normalise_text`).
##
## `dir` is a parameter so a test can point the scan somewhere empty and prove
## the guard below actually fires.
## `strict` is a TESTING SEAM, not a severity dial. The guard's whole point is
## to be loud, but `run_overworld_tests.sh` fails a run on any engine ERROR
## line — correctly, since a stray error means a test function aborted silently.
## A test that must PROVE the guard fires therefore cannot let it push_error.
## With `strict = false` the guard records its message in `last_diagnostic`
## instead, so the test asserts on the text rather than on the absence of a
## crash. Production never passes false. Same shape as `_force_hit`/`_force_roll`.
static var last_diagnostic: String = ""


static func preload_tilesets(dir_path: String = TILESET_DIR, verbose: bool = true,
		strict: bool = true) -> int:
	last_diagnostic = ""
	var t_start := Time.get_ticks_usec()
	var dir := DirAccess.open(dir_path)
	var files: Array[String] = []
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".tres"):
				files.append(f)
	files.sort()

	var loaded := 0
	var slowest_ms := 0.0
	var slowest_name := ""
	for f in files:
		var t0 := Time.get_ticks_usec()
		var ts := ResourceLoader.load(dir_path + f) as TileSet
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if ts == null:
			push_error("preload_tilesets: %s failed to load as a TileSet" % f)
			continue
		_preloaded[f.trim_suffix(".tres")] = ts
		loaded += 1
		if ms > slowest_ms:
			slowest_ms = ms
			slowest_name = f.trim_suffix(".tres")

	var total_ms := (Time.get_ticks_usec() - t_start) / 1000.0

	# Arithmetic guard, Z.99-style. A boot that warms nothing must FAIL, not
	# print a green nothing — the failure this is defending against is a
	# renamed/moved directory silently restoring the per-visit hitch while the
	# summary line still looks healthy.
	if files.is_empty():
		last_diagnostic = ("preload_tilesets: found 0 .tres files under %s — expected at "
				% dir_path + "least one; every first map visit will now pay the full build cost")
		if strict:
			push_error(last_diagnostic)
		return 0
	if loaded != files.size():
		last_diagnostic = ("preload_tilesets: loaded %d of %d files found under %s — %d failed"
				% [loaded, files.size(), dir_path, files.size() - loaded])
		if strict:
			push_error(last_diagnostic)

	if verbose:
		print("preload_tilesets: %d pair(s), %.1f ms total, slowest %s at %.1f ms"
				% [loaded, total_ms, slowest_name, slowest_ms])
	return loaded


## The held TileSet for a pair, or null if it was not preloaded.
static func preloaded_tileset(pair: String) -> TileSet:
	return _preloaded.get(pair, null) as TileSet


static func preloaded_count() -> int:
	return _preloaded.size()


## Drop every held reference. Tests only — production never wants this, since
## releasing the refs is precisely what reintroduces the hitch.
static func clear_preloaded() -> void:
	_preloaded.clear()
