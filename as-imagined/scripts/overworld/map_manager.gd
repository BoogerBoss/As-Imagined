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

## [M27M Part C] The atlas geometry constant that used to live here is GONE, on
## purpose: `AtlasLayout` owns the id→(source, coords) rule now, and a local
## copy of half of it is exactly how the two paint sites would drift apart.

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
## The three tile planes in SOURCE-ID order, which is not the same thing as
## `PLANE_Z`'s draw order — that one interleaves the two entity strata. Kept
## separate so a change to draw order can never silently re-route a paint.
const PLANE_LAYER_NAMES := ["Ground", "Objects", "Overhangs"]

const PLANE_Z := {
	"Ground": 0,
	"Objects": 1,
	"Entities_P2": 2,
	"Overhangs": 3,
	"Entities_P1": 4,
}


## [M27N] The one shared weather ShaderMaterial, applied to every loaded
## chunk's terrain planes (never Entities_P1/P2 — the player/NPC layer is
## excluded from grading by construction, not by a special case). Owned by
## WeatherManager; MapManager only holds a reference so it can (re)apply it
## at the same moment `apply_plane_z` already runs (a chunk registering) —
## MapManager never reaches into WeatherManager itself, keeping the two
## decoupled.
var _weather_material: ShaderMaterial = null


func set_weather_material(mat: ShaderMaterial) -> void:
	_weather_material = mat
	for map_name in _chunks:
		var root: Node2D = _chunks[map_name]["root"]
		_apply_weather_material(root)


## Same traversal shape as `apply_plane_z`, but only the TERRAIN planes
## (never Entities_P1/P2) — a null material clears the effect.
func _apply_weather_material(root: Node2D) -> void:
	if root == null or not is_instance_valid(root):
		return
	for c in root.get_children():
		if c is CanvasItem and PLANE_Z.has(c.name) and not str(c.name).begins_with("Entities_"):
			(c as CanvasItem).material = _weather_material


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

## map_name -> { local Vector2i : true } for every cell an entity blocks.
##
## [M27D D2] A set rather than a per-step scan of the scene tree: a step already
## costs a resolve, and walking every entity of every live chunk per step is a
## real per-cell cost worth paying once rather than every step. Built
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
		origin: Vector2i) -> bool:
	if data == null or packed == null:
		return false
	var root: Node2D = packed.instantiate() as Node2D
	if root == null:
		return false
	add_child(root)
	register_chunk(map_name, data, root, origin)
	# [M27G G9] Re-apply anything a script permanently changed about this map's
	# object events. ⚠️ HERE, not at bake time and not in the scene: the baked
	# `.tscn` is a reproducible artifact (`check_bake_diff` depends on that) and
	# must keep describing the map as authored, so a runtime override belongs in
	# the save and is layered back on load. Same shape as `entity_visible`
	# reading a FLAG rather than the scene knowing it is hidden.
	_apply_object_event_overrides(map_name, root)
	# ⚠️ **[Bugfix, live-reported: "you can walk right through the sign girl when
	# she is in her alternate position near the north entrance to Pallet"]
	# REBUILT BECAUSE THE LINE ABOVE MOVES ENTITIES AFTER `register_chunk` HAS
	# ALREADY BUILT IT.** Occupancy is derived from the BAKED cells, and then
	# `_apply_object_event_overrides` assigns `e.cell` directly — bypassing
	# `move_entity`, which is the only writer that keeps the set in step — so a
	# repositioned NPC left a phantom block on the tile she used to stand on and
	# none on the one she now occupies. Exactly the symptom the `setobjectxyperm`
	# handler's own doc comment predicts for a direct `e.cell` assignment; it was
	# fixed there and reintroduced here by a different route.
	#
	# A full rebuild rather than an incremental update: this runs once per chunk
	# load, the loop is over one map's entities, and the alternative needs the
	# pre-override cell threaded out of a function whose whole job is to
	# overwrite it. Gated on there being any override at all, so the ordinary
	# load — no script has ever moved anything — pays nothing.
	if ObjectEventState.has_any():
		rebuild_occupancy(map_name)
	# [Bugfix, live-reported: Oak's Lab starter ball / rival never disappear]
	# `removeobject`/`addobject` only ever flipped the FLAG (`entity_visible()`'s
	# own backing store) — nothing ever re-derived a node's `.visible` from it,
	# on load or otherwise, so a hidden entity stayed fully drawn AND fully
	# solid. `rebuild_occupancy` (called by `register_chunk` above) now gates on
	# the same flag for the solid half; this is the render half, applied here so
	# a map loaded AFTER a `removeobject` already fired (leaving the lab and
	# coming back, a loaded save) reflects it immediately rather than only once
	# something else happens to touch the node.
	_apply_entity_visibility(root)
	return true


## [M27G G9] Layer saved script-driven changes back onto a freshly loaded
## chunk. Silent and cheap when nothing was ever changed, which is the norm.
func _apply_object_event_overrides(map_name: String, root: Node2D) -> void:
	if root == null or not ObjectEventState.has_any():
		return
	for e in _entities_under(root):
		if not ("local_id" in e) or str(e.local_id) == "":
			continue
		var ov := ObjectEventState.overrides_for(map_name, str(e.local_id))
		if ov.is_empty():
			continue
		if ov.has("cell"):
			e.cell = ov["cell"]
		if ov.has("movement_type") and e is NPC:
			(e as NPC).movement_type = str(ov["movement_type"])
		# ⚠️ Facing LAST: `set_facing` rebuilds the sprite frame, and doing it
		# before a cell change would leave the sprite correct and the node in
		# the wrong place for a frame.
		if ov.has("facing") and e is NPC:
			(e as NPC).set_facing(int(ov["facing"]))


## [Bugfix companion to `_install_chunk`'s own note] Bulk apply at load time —
## every entity's `.visible` matches `entity_visible()` before the player ever
## sees the map, rather than only the entities a script happens to touch again.
func _apply_entity_visibility(root: Node2D) -> void:
	for e in _entities_under(root):
		e.visible = OverworldSession.flags.entity_visible(e)


## [Bugfix] The LIVE half: called the instant a script flips an entity's
## visibility flag (`addobject`/`removeobject`), so the node vanishes (or
## reappears) in front of the player on the same frame the flag changes,
## rather than only on the map's next load. Mirrors `move_entity`'s own
## incremental-occupancy-update shape rather than paying a full
## `rebuild_occupancy` for one entity.
func apply_entity_visibility(e: OverworldEntity) -> void:
	if e == null or not is_instance_valid(e):
		return
	var now_visible := OverworldSession.flags.entity_visible(e)
	e.visible = now_visible
	if not (e is NPC or e is ItemBall):
		return
	var map_name := map_name_of(e)
	if map_name == "":
		return
	var occ: Dictionary = _occupancy.get(map_name, {})
	if now_visible:
		occ[e.cell] = true
	else:
		occ.erase(e.cell)
	_occupancy[map_name] = occ


## [Bugfix] The broad counterpart to `apply_entity_visibility()` — queued by a
## plain `setflag`/`clearflag` rather than `addobject`/`removeobject`, since a
## generic flag write has no single entity to target. Refreshes every entity's
## `.visible` and rebuilds occupancy across every currently loaded chunk.
func refresh_all_entity_visibility() -> void:
	for map_name in _chunks.keys():
		var root: Node2D = _chunks[map_name]["root"]
		if root != null and is_instance_valid(root):
			_apply_entity_visibility(root)
		rebuild_occupancy(map_name)


func _entities_under(root: Node2D) -> Array[OverworldEntity]:
	var out: Array[OverworldEntity] = []
	for stratum in root.get_children():
		if not (stratum is Node2D):
			continue
		for c in stratum.get_children():
			if c is OverworldEntity:
				out.append(c)
	return out


## The registry half, split from the loading half so it can be driven with
## synthetic MapData and a bare Node2D. The coordinate maths is the part worth
## testing and it has nothing to do with disk.
func register_chunk(map_name: String, data: MapData, root: Node2D,
		origin: Vector2i = Vector2i.ZERO) -> void:
	_chunks[map_name] = {"data": data, "root": root, "origin": origin}
	if root != null:
		root.position = Vector2(origin) * CELL
		apply_plane_z(root)
		_apply_weather_material(root)
	rebuild_occupancy(map_name)


## The cells a chunk covers, in global coordinates.
func chunk_rect(map_name: String) -> Rect2i:
	if not _chunks.has(map_name):
		return Rect2i()
	var d: MapData = _chunks[map_name]["data"]
	if d == null:
		return Rect2i()
	return Rect2i(_chunks[map_name]["origin"], Vector2i(d.width, d.height))


## Give a chunk's layers their plane z. Idempotent, and silent about children
## it does not recognise — a synthetic chunk in a test has none of these.
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
	_chunks.erase(map_name)


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


## [M27N] The destination's own real weather (MapData.Weather ordinal),
## or NONE for an unloaded/unknown map — same fail-safe shape as origin_of.
func weather_of(map_name: String) -> int:
	if not _chunks.has(map_name):
		return MapData.Weather.NONE
	var d: MapData = _chunks[map_name]["data"]
	return d.weather


## Which chunk's bounds contain this global cell, or "" for the gap between and
## around them. That gap is real and expected, and a caller must treat it as
## impassable rather than assuming every coordinate belongs to somebody.
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
## nothing falls through the world.
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
## unbaked destinations are excluded: an edge that yields nothing here is an
## edge with no neighbour to walk onto.
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
					neighbour_origin(p["host_origin"], p["host"], p["conn"], data))
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
## [Bugfix, closes the gap this comment used to record] Now gated on
## `visibility_flag` via `FlagStore.entity_visible()` — source hides a
## flagged-away object event and stops it colliding, and an entity a script
## has removed (`removeobject`) or never revealed (`FLAG_HIDE_*` still set)
## must not go on blocking a tile the player can now see is empty.
func rebuild_occupancy(map_name: String) -> void:
	var out := {}
	if _chunks.has(map_name):
		var root: Node2D = _chunks[map_name]["root"]
		if root != null and is_instance_valid(root):
			for n in root.find_children("*", "OverworldEntity", true, false):
				var e := n as OverworldEntity
				if e != null and (e is NPC or e is ItemBall) \
						and OverworldSession.flags.entity_visible(e):
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


## The entity standing on this GLOBAL cell, or null.
##
## [M27F] Distinct from `entity_at`, which answers the COLLISION question and so
## only counts npc/trainer/item — the three kinds source's own
## `DoesObjectCollideWithObjectAt` consults. Interaction needs SIGNS too, and it
## needs the node rather than a bool, so this is a separate lookup rather than a
## widened one: conflating them would make a sign solid.
##
## Scans rather than indexes. Interaction happens on a button press, not per
## step, so a per-cell cost that would matter in a hot loop does not apply here.
func entity_node_at(gcell: Vector2i) -> OverworldEntity:
	var found := entities_at(gcell)
	return found[0] if not found.is_empty() else null


## Every entity standing on this GLOBAL cell, in scene-tree order.
##
## [Map scripts + coord_event trigger dispatch] Several idioms legitimately
## stack more than one entity on one cell — most commonly gated triggers,
## where two `Trigger` nodes share a cell and are gated on the same var at
## different values so exactly one is ever armed. `entity_node_at` used to
## answer with whichever entity `find_children` happened to return first,
## with no regard for whether ITS OWN gate condition was satisfied — so a
## trigger declared earlier in the scene permanently shadowed one declared
## later on the same cell, even once the shadowed one's var condition became
## true. Source's own `GetCoordEventScriptAtPosition` (`field_control_avatar.c`)
## walks every coord_event at a position and returns the first one whose
## condition actually passes; this is the seam that lets callers reproduce
## that instead of trusting scene-tree order alone.
##
## ⚠️ **[Bugfix, live-reported: "clicking anywhere on the table in Oak's lab
## reads 'that's Oak's last POKéMON' even if there is no longer a Poké Ball
## there"] HIDDEN ENTITIES ARE SKIPPED, AND THEY USED NOT TO BE.** A
## `removeobject` (and every `FLAG_HIDE_*`) only flips `.visible` and drops the
## cell from the occupancy set — the node stays in the tree, which is what lets
## `addobject` reverse it. This function answered with it anyway, so an
## invisible Poké Ball still ran `EventScript_BulbasaurBall`, which by then
## resolves to the `VAR_MAP_SCENE >= 3` arm: "That's PROF. OAK's last POKéMON."
## Three balls become three ghosts on an empty table.
##
## Source cannot reach one: `GetObjectEventIdByPosition` searches only ACTIVE
## object events, and a removed one is inactive. Keyed on `.visible` rather than
## re-reading `FlagStore` because `apply_entity_visibility` already writes it
## from exactly that flag, and a second derivation is a second thing to keep in
## step.
##
## ⚠️ Warps, triggers and signs are unaffected: they carry no `visibility_flag`
## (source's own `warp_events`/`coord_events`/`bg_events` arrays have no such
## field), so `FlagStore.entity_visible` answers true and `.visible` stays true.
## Disclosed edge: an NPC hidden mid-cutscene by `applymovement`'s own
## `set_invisible` also stops answering here, where source's would still be
## found — unreachable in practice, since a running script owns input and
## nothing can press A at it.
func entities_at(gcell: Vector2i) -> Array[OverworldEntity]:
	var out: Array[OverworldEntity] = []
	var map_name := chunk_owning(gcell)
	if map_name == "" or not _chunks.has(map_name):
		return out
	var root: Node2D = _chunks[map_name]["root"]
	if root == null or not is_instance_valid(root):
		return out
	var local: Vector2i = gcell - Vector2i(_chunks[map_name]["origin"])
	for n in root.find_children("*", "OverworldEntity", true, false):
		var e := n as OverworldEntity
		if e != null and e.cell == local and e.visible:
			out.append(e)
	return out


## Where the corridor op-code scope's per-pair layer-type tables live,
## alongside `map_baker.gd`'s own `ATLAS_DIR` for the atlas PNGs they were
## generated from.
const ATLAS_JSON_DIR := "res://assets/map_atlases/"

## Cache of `<pair>_layer_types.json`, keyed by pair name (`MapData.atlas`,
## the same string `preload_tilesets()` uses to key its own TileSet cache).
## Loaded lazily rather than up front: only `set_metatile` ever needs one,
## and today that is a single tileset pair across the whole corridor.
static var _layer_types: Dictionary = {}

## [M27M1] The same, for `<pair>_behaviors.json`. Separate cache rather than one
## dictionary of dictionaries: the two are read by different callers at
## different times (`set_metatile` needs routing, authoring needs meaning) and
## neither should pay for the other's file.
static var _behaviors: Dictionary = {}


## The layer_type (0 NORMAL / 1 COVERED / 2 SPLIT) of `metatile_id` within
## `pair`'s own atlas, or -1 if the pair's table hasn't been generated (an
## unregenerated checkout) or the id is out of range.
static func _layer_type_for(pair: String, metatile_id: int) -> int:
	return _table_lookup(_layer_types, "_layer_types.json", pair, metatile_id)


## [M27M1] The metatile BEHAVIOUR (an `MB_*` id — see `MetatileBehavior`) of
## `metatile_id` within `pair`'s own atlas, or **-1** when the table has not been
## generated or the id is out of range.
##
## ⚠️ **THIS IS THE DEFAULT A PAINTED TILE BRINGS WITH IT, and it is per-TILE
## rather than per-CELL on purpose.** Behaviour has **0% placement variance**
## (measured across all 421 maps: 11,031 distinct (atlas, metatile) pairs, zero
## conflicts), unlike collision and elevation which vary by placement 52.0% and
## 52.1% of the time and so genuinely belong to the square rather than the tile.
##
## That difference is why `author_cell_with_defaults` seeds collision/elevation
## from the NEAREST NEIGHBOUR and must seed behaviour from HERE instead —
## inheriting a neighbour's behaviour would give a newly painted grass tile the
## `MB_NORMAL` of the path beside it, which is wrong in exactly the case
## authoring cares about.
##
## ⚠️ **-1 IS "UNKNOWN", NEVER "MB_NORMAL".** `MB_NORMAL` is 0 and is 62.3% of
## the region, so collapsing the two would make a missing table look like a
## perfectly ordinary map — the silent-failure shape this project keeps paying
## for. A caller that cannot get an answer must be able to tell.
static func behavior_for(pair: String, metatile_id: int) -> int:
	return _table_lookup(_behaviors, "_behaviors.json", pair, metatile_id)


## Shared body for both per-pair sidecar tables. Extracted rather than copied:
## `[M27M-T]` §5.4 already records that this project has TWO hand-kept copies of
## the routing rule and should not grow a third of anything — the same argument
## applies to the lookup itself.
##
## Loaded lazily and cached per pair, including the EMPTY result: a missing file
## is a stable answer, not something to retry on every cell of a paint stroke.
static func _table_lookup(cache: Dictionary, suffix: String, pair: String,
		metatile_id: int) -> int:
	if not cache.has(pair):
		var arr: Array = []
		var f := FileAccess.open(ATLAS_JSON_DIR + pair + suffix, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Array:
				arr = parsed
		cache[pair] = arr
	var table: Array = cache[pair]
	if metatile_id < 0 or metatile_id >= table.size():
		return -1
	return int(table[metatile_id])


## [Corridor op-code scope] `setmetatile x, y, metatileId, impassable`
## (`ScrCmd_setmetatile`, `scrcmd.c:2741-2757`) — replaces one cell's whole
## metatile at runtime, source's own mechanism for a prop that toggles once
## (Viridian Mart's counter, hiding the questionnaire once
## `FLAG_SYS_POKEDEX_GET` is set). `x`/`y` are LOCAL to whichever map the
## calling script is running on, matching source's own
## `MapGridSetMetatileIdAt(x + MAP_OFFSET, y + MAP_OFFSET, ...)` — `gcell`
## here is already the resolved GLOBAL cell, converted by the caller the
## same way every other local-to-global op in this project is.
##
## Repaints all three planes from the per-pair layer-type table via `ROUTING`,
## exactly as `map_baker` does at bake time — and getting the routing wrong
## here is the identical "painted a
## NORMAL metatile into Ground alone, half the block never renders" trap
## `[M27C C3]`/`[M27M]` already paid for twice. Confirmed non-trivial on the
## corridor's own two real uses: `METATILE_Mart_CounterMid_Top` (id 703) is
## NORMAL (objects+overhangs) while `_Bottom` (id 704) is COVERED
## (ground+objects) — the two halves of one prop route differently.
##
## Collision has no "the metatile's own default" to fall back to when
## `impassable` is false — source's own `MapGridSetMetatileIdAt` either ORs
## in `MAPGRID_IMPASSABLE` or doesn't, and the fresh grid value it
## constructs otherwise carries zero collision bits regardless of what the
## new metatile "naturally" is. So `impassable` is a flat force-solid /
## force-walkable, not a per-metatile lookup — there is nothing to look up.
func set_metatile(gcell: Vector2i, metatile_id: int, impassable: bool) -> bool:
	var map_name := chunk_owning(gcell)
	if map_name == "" or not _chunks.has(map_name):
		return false
	var c: Dictionary = _chunks[map_name]
	var d: MapData = c["data"]
	var root: Node2D = c["root"]
	if d == null or root == null or not is_instance_valid(root):
		return false
	var local: Vector2i = gcell - Vector2i(c["origin"])
	var idx := local.y * d.width + local.x
	if local.x < 0 or local.y < 0 or local.x >= d.width or local.y >= d.height \
			or idx < 0 or idx >= d.collision.size():
		return false

	d.collision[idx] = 1 if impassable else 0
	return paint_metatile(root, local, metatile_id, d.atlas)


## Draw one metatile into a map root's three plane layers. Returns false when
## the pair does not describe the id, having changed nothing.
##
## ⚠️ **SHARED WITH THE EDITOR BRUSH ON PURPOSE (M27M3).** The runtime
## `setmetatile` opcode and a human with a brush are the same act, and this
## project has already paid once for one rule kept by hand in two places —
## `check_bake_diff`'s normalisation drifted from `map_baker`'s and produced a
## permanent false positive. A brush that routed differently from the opcode
## would be that again, in a place where the symptom is a map that looks right.
##
## ⚠️ **AN UNKNOWN LAYER TYPE REFUSES RATHER THAN ERASING.** `_layer_type_for`
## answers -1 for a pair it has no table for, and the old inline version fed
## that straight into `ROUTING.get(lt, [])` — an empty route, which erases all
## three planes. Silent, and it deletes art. Refusing is the only honest
## answer: nothing here can know where an unroutable metatile belongs.
static func paint_metatile(root: Node2D, local: Vector2i, metatile_id: int,
		pair: String) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	var lt := _layer_type_for(pair, metatile_id)
	if not ROUTING.has(lt):
		return false
	var routed: Array = ROUTING[lt]
	# [M27M Part C] The source is no longer just the plane — a secondary id
	# lives in a different TileSet source and at a re-based coord. Both come
	# from `AtlasLayout` so the baker and the manager cannot drift apart.
	var coords := AtlasLayout.coords(metatile_id)
	for plane in range(PLANE_LAYER_NAMES.size()):
		var layer := root.get_node_or_null(PLANE_LAYER_NAMES[plane]) as TileMapLayer
		if layer == null:
			continue
		if plane in routed:
			layer.set_cell(local, AtlasLayout.source_id(plane, metatile_id), coords)
		else:
			layer.set_cell(local)  # not routed to this plane -- erase, don't leave stale art
	return true


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
			# Mid-walk NPCs are not asked for a new decision. Without this the
			# wander timer would re-fire against a cell the sprite has not
			# visually reached yet.
			if _runner.is_busy(npc):
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
			# [M27F Stage 3] Hand the already-approved destination to the runner
			# instead of committing it outright. Occupancy still updates
			# synchronously (the runner commits at action start), so D3's
			# "two NPCs cannot claim one tile in a frame" invariant is intact —
			# what changes is that the sprite now WALKS there instead of
			# teleporting, which it has done since D3 shipped.
			start_entity_movement(map_name, npc,
					walk_ops(_dir_towards(npc.cell, want)))


## A movement script of `count` normal walks in one direction.
##
## Shared so the two callers that build one — wandering, and the trainer
## approach — cannot drift into two spellings of the same thing. Normal speed
## is what source uses for both: the approach hands its object
## `GetWalkNormalMovementAction` (`trainer_see.c`), not a fast variant.
func walk_ops(dir: int, count: int = 1) -> Array:
	var suffix: String = _ACTION_SUFFIX.get(dir, "down")
	var ops: Array = []
	for _i in range(maxi(0, count)):
		ops.append({"op": "walk_" + suffix})
	ops.append({"op": "step_end"})
	return ops


## Direction -> the suffix source's own movement actions use.
const _ACTION_SUFFIX := {
	StepResolver.Dir.NORTH: "up",
	StepResolver.Dir.SOUTH: "down",
	StepResolver.Dir.WEST: "left",
	StepResolver.Dir.EAST: "right",
}


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


## [M27F Stage 3] The one entity-motion system. Lives here because this node
## already owns entities and occupancy; the player is driven through the same
## runner by the overworld, which owns that node instead.
var _runner := MovementRunner.new()


func movement() -> MovementRunner:
	return _runner


## Advance in-flight motion. Called every frame INCLUDING while a script runs —
## a scripted `applymovement` has to keep moving while the rest of the world is
## frozen, which is exactly what a cutscene is.
func tick_movement(delta: float) -> void:
	_runner.tick(delta)


## Walk a placed entity through a movement script (a list of `{"op": ...}`).
##
## ⚠️ No collision check, deliberately — see MovementRunner's own header. The
## wandering caller resolves BEFORE calling this; a scripted caller does not,
## because source does not.
func start_entity_movement(map_name: String, e: OverworldEntity, ops: Array) -> void:
	if e == null or not is_instance_valid(e):
		return
	var commit := func(dir: int) -> void:
		move_entity(map_name, e, e.cell + StepResolver.STEP[dir])
	var face := Callable()
	var anim := Callable()
	var rest := Callable()
	if e is NPC:
		face = func(dir: int) -> void: (e as NPC).set_facing(dir)
		# [M27F Stage 3b] The walk cycle. `anim` advances it every tick a
		# walking action is in flight; `rest` settles onto the standing frame
		# once the whole script ends, so nobody is left with one leg out.
		anim = func(dir: int, ticks: int, delta: float) -> void:
			(e as NPC).step_anim(dir, ticks, delta)
		rest = func(dir: int) -> void: (e as NPC).set_facing(dir)
	# [M27R Step 1] Runtime-resolved facing, for `face_player` /
	# `face_original_direction`. Supplied here rather than baked into the
	# runner's table because both answers depend on live state the runner has
	# no business reaching for — where the player is, and what this entity's
	# movement type is.
	var resolve := func(source: String) -> int:
		if source == "player":
			return _dir_toward_player(e)
		if source == "movement_type" and e is NPC:
			return _dir_of_step(MovementTypes.initial_facing(
					(e as NPC).movement_type))
		return -1
	var emote := func(name: String) -> void: spawn_emote(e, name)
	var show_frame := Callable()
	if e is NPC:
		show_frame = func(idx: int) -> void: (e as NPC).show_frame(idx)
	_runner.start(e, e, ops, commit, face, anim, rest, resolve, emote, show_frame)


## [M27R Step 1] Pop an emote bubble above an entity. Parented to the entity's
## own PARENT rather than to the entity, matching source: the icon is an
## independent field-effect sprite that merely follows, which is what lets it
## outlive both the movement action and (harmlessly) a reparent for elevation.
func spawn_emote(e: OverworldEntity, kind: String) -> void:
	if e == null or not is_instance_valid(e):
		return
	var parent := e.get_parent()
	if parent == null:
		return
	EmoteIcon.spawn(parent, e, kind)


## The direction from `e` toward the player, or -1 with no player known.
##
## ⚠️ Source's `GetDirectionToFace` picks the axis with the GREATER separation
## and breaks a tie toward the horizontal — it is not a diagonal and it is not
## "whichever axis differs". Reproduced rather than approximated, because a
## tie is the common case for an NPC standing directly beside the player.
func _dir_toward_player(e: OverworldEntity) -> int:
	if _player_cell.x == -2147483648 or e == null or not is_instance_valid(e):
		return -1
	# `e.cell` is LOCAL to its own chunk; `_player_cell` is GLOBAL. Comparing
	# them directly is the coordinate-space mistake [M27C C2] introduced the
	# global space to make impossible, and it reads correct at origin (0, 0).
	var here: Vector2i = e.cell + origin_of(map_name_of(e))
	var d: Vector2i = _player_cell - here
	if absi(d.x) >= absi(d.y):
		if d.x != 0:
			return StepResolver.Dir.EAST if d.x > 0 else StepResolver.Dir.WEST
		return StepResolver.Dir.SOUTH if d.y > 0 else StepResolver.Dir.NORTH
	return StepResolver.Dir.SOUTH if d.y > 0 else StepResolver.Dir.NORTH


static func _dir_of_step(step: Vector2i) -> int:
	if step == Vector2i(0, -1):
		return StepResolver.Dir.NORTH
	if step == Vector2i(0, 1):
		return StepResolver.Dir.SOUTH
	if step == Vector2i(-1, 0):
		return StepResolver.Dir.WEST
	if step == Vector2i(1, 0):
		return StepResolver.Dir.EAST
	return -1


## Find a placed entity by its own `local_id`, across every live chunk.
##
## `applymovement` addresses its target by LOCALID, which is map data rather
## than a node path, so this is the one lookup that has to exist. Scans rather
## than indexes for the same reason `entity_node_at` does: a script command is
## not a per-frame cost.
func find_entity_by_local_id(local_id: String) -> OverworldEntity:
	if local_id == "":
		return null
	for map_name in _chunks:
		var root: Node2D = _chunks[map_name]["root"]
		if root == null or not is_instance_valid(root):
			continue
		for n in root.find_children("*", "OverworldEntity", true, false):
			if _entity_local_id(n) == local_id:
				return n as OverworldEntity
	return null


## `local_id` lives on the concrete kinds, not on OverworldEntity — only the
## three that occupy an object-event slot carry one.
static func _entity_local_id(n: Node) -> String:
	if n is NPC:
		return (n as NPC).local_id
	if n is ItemBall:
		return (n as ItemBall).local_id
	return ""


## Which live chunk owns this entity. Needed because occupancy is per-chunk and
## a mover has to update the right one.
func map_name_of(e: OverworldEntity) -> String:
	if e == null or not is_instance_valid(e):
		return ""
	for map_name in _chunks:
		var root: Node2D = _chunks[map_name]["root"]
		if root != null and is_instance_valid(root) and root.is_ancestor_of(e):
			return map_name
	return ""


## Start a movement on an entity whose owning chunk is not already known.
## False when the entity does not belong to any live chunk.
func start_movement_for_entity(e: OverworldEntity, ops: Array) -> bool:
	var map_name := map_name_of(e)
	if map_name == "":
		return false
	start_entity_movement(map_name, e, ops)
	return true


func is_entity_moving(e: OverworldEntity) -> bool:
	return _runner.is_busy(e)


## Move a placed entity to a new LOCAL cell, keeping occupancy true.
##
## Incremental rather than a rebuild: `rebuild_occupancy` walks every entity of
## the chunk, and doing that per NPC per step is a cost worth avoiding.
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


## True once `warm_tilemap_draws` has actually paid its cost, so a second boot
## in the same process (a battle return, any `change_scene_to_file`) does not
## pay it again for nothing.
static var _first_draw_warmed := false


## [Map-edge hitch] Force whatever Godot pays on a tileset's FIRST
## `TileMapLayer` draw to happen HERE, off-screen at boot, instead of live at
## the first real chunk a player's camera actually reaches.
##
## ⚠️ **THIS IS A DIFFERENT COST FROM `preload_tilesets`, AND CONFUSING THE TWO
## IS WHAT LEFT IT UNFIXED.** `preload_tilesets` warms the CPU-side `TileSet`
## *Resource* — parsing the `.tres`, decoding the atlas `Image`s. This warms
## the RENDER-side cost of the first `TileMapLayer` *draw* — measured directly
## (`RenderingServer` timing around `await process_frame` × 2, `--headless`, so
## no GPU rasterization is even involved — confirming this is Godot's own
## CPU-side bookkeeping, not shader/driver compilation) at ~37 ms for whichever
## map happens to be the first one a fresh process ever draws, and near-zero
## for every map after it, REGARDLESS OF TILESET — proven by warming with one
## throwaway cell from an unrelated pair and watching every real corridor map
## probed afterward (480 to 3726 cells, 5 different tilesets) drop to the same
## few milliseconds a bare 2-frame wait costs in this environment anyway.
##
## ⚠️ **THAT "PROCESS-GLOBAL, NOT PER-TILESET" CONCLUSION IS NOT SAFE, AND THIS
## NOW WARMS ALL OF THEM.** It was measured `--headless`, where there is no GPU
## and therefore no texture upload and no pipeline state to create — exactly the
## per-atlas costs it was claiming to have ruled out. Rob ships on Windows under
## `d3d12` (`project.godot`), and the map that reveals this is the crossing into
## Route 1: Pallet Town and Route 1 SHARE the `general_frlg__pallet_town_frlg`
## pair, while the neighbour that loads on that step, Viridian City, is the
## first chunk in the corridor drawn from a DIFFERENT atlas. Warming one
## arbitrary pair — `_preloaded.values()[0]` — cannot cover that by
## construction, which is consistent with the hitch surviving the original fix.
##
## Every source of every pair, because a pair's three sources are three separate
## plane atlases and so three separate textures. 14 pairs x 3 is 42 throwaway
## cells and two frame waits TOTAL, so if the original process-global reading
## was right this costs nothing extra, and if it was wrong this is the fix.
##
## Needs a real node to hang the throwaway layers and the frame waits off —
## static, matching `preload_tilesets`, but callers pass whatever's on hand at
## boot (`self` from `overworld.gd`'s own `_ready`).
static func warm_tilemap_draws(host: Node) -> void:
	if _first_draw_warmed or host == null or not is_instance_valid(host) \
			or _preloaded.is_empty():
		return
	_first_draw_warmed = true
	var layers: Array[TileMapLayer] = []
	for pair in _preloaded:
		var ts: TileSet = _preloaded[pair] as TileSet
		if ts == null or ts.get_source_count() == 0:
			continue
		var layer := TileMapLayer.new()
		layer.tile_set = ts
		# Off in world space rather than merely `visible = false` — the cost
		# this warms is paid by a real draw, and an invisible CanvasItem is
		# exactly the kind of thing a renderer is entitled to skip.
		layer.position = Vector2(-1000000, -1000000)
		host.add_child(layer)
		for i in range(ts.get_source_count()):
			layer.set_cell(Vector2i(i, 0), ts.get_source_id(i), Vector2i.ZERO)
		layers.append(layer)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	for layer in layers:
		layer.queue_free()
