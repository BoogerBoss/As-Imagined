@tool
class_name MapResize
extends RefCounted

## [M27M5c Phase 4] Change a map's dimensions after it already exists.
##
## `MapAuthoring.create_map` can make a 20x18 map; nothing until now could make
## it 24x18, and "delete it and start again" is not an answer once a map has
## painted tiles, reviewed collision and placed entities on it.
##
## ## Four edge deltas, not a size and an offset
##
## The caller says how much to add or remove on each EDGE — `+4` north adds four
## rows above, `-2` east trims two columns off the right — and the new size and
## the offset are DERIVED:
##
##     offset = (west, north)                    # where old (0,0) lands
##     size   = (w + west + east, h + north + south)
##
## ⚠️ **THIS IS THE INPUT MODEL ON PURPOSE, AND THE OBVIOUS ONE IS WORSE.**
## Asking for width, height and an offset is three numbers of which two can
## contradict each other — an offset of (3, 0) against a width that only grew by
## 1 is silently a trim on the right, and the author who typed it meant a grow on
## the left. Each edge delta names one edge and means exactly one thing, so no
## combination of them is self-contradictory and nothing has to be validated
## against anything else. A nine-way anchor is a lossy special case of this (it
## cannot express "+3 north AND +5 south" in one action); a free offset is the
## same information in the form where you can get it wrong.
##
## Porymap's own Change Dimensions is a drag-rectangle you reposition the map
## inside, so an arbitrary offset is the REFERENCE behaviour rather than a
## convenience invented here — *"anything outside the rectangle when you finish
## will be deleted"*. A viewport drag can be added later as a second front-end
## onto this same call; it would compute the four deltas and change nothing else.
##
## ## Why the scene is edited in place rather than re-baked
##
## ⚠️ **`map_baker` CANNOT BE THE RESIZE PATH, AND THE REASONS ARE ITS OWN
## GUARDS.** It refuses any map holding AUTHORED cells (`map_baker.gd:90-95`) and
## refuses any scene that diverges from what a re-bake would produce
## (`:123-130`) — which between them describe precisely the maps somebody would
## want to resize. Those guards are correct: a re-bake rebuilds entities from
## `assets/maps/<Map>.json`, which is gitignored regenerable output, so it would
## silently discard every hand-tuned `sight_range`, `movement_type` and
## `script_label` in the scene. So this does surgery on the open scene, the same
## way painting already does, and never regenerates anything.

const MIN_DIM := 1

## ⚠️ **THE REFERENCE'S OWN CEILING, AND IT IS A PRODUCT RATHER THAN A PER-AXIS
## LIMIT.** `fieldmap.c:172-176` builds every loaded map into
## `sBackupMapData[MAX_MAP_DATA_SIZE]` and silently refuses to lay it out at all
## when `(width + MAP_OFFSET_W) * (height + MAP_OFFSET_H) > MAX_MAP_DATA_SIZE` —
## 15, 14 and 10240 (`include/fieldmap.h:15,23-25`).
##
## Measured across all 421 baked Kanto maps: **none exceeds it**, and the largest
## (Diglett's Cave B1F, 85x80) sits at 9,400 of 10,240 — so this is a real,
## close, and load-bearing constraint rather than a formality. A per-axis cap
## would be wrong in both directions: it would refuse the legitimate 24x160
## Route 23 shape and permit an illegal 144x100 one.
const MAP_OFFSET_W := 15
const MAP_OFFSET_H := 14
const MAX_MAP_DATA_SIZE := 10240

## Shared with the overlay and the baker rather than re-listed, so a fourth
## plane could never be added in one place and missed here.
const PLANE_LAYER_NAMES := MapManager.PLANE_LAYER_NAMES

## Every container a placed entity can sit in, from `map_baker.build_map_scene`
## plus the `Triggers` node `_emit_events` adds. Warps/triggers/signs are in a
## flat container and NPCs are split across two elevation strata, so this is
## three names rather than one subtree walk.
const ENTITY_CONTAINERS := ["Entities_P1", "Entities_P2", "Triggers"]


# ------------------------------------------------------------------- [1] plan

## Would the real game be able to lay this size out at all?
##
## Public because it is the one rule a UI wants to ask BEFORE the author commits
## — a live "3,412 / 10,240 words" readout is the difference between a ceiling
## you can steer away from and one you hit.
static func fits(size: Vector2i) -> bool:
	return data_words(size) <= MAX_MAP_DATA_SIZE


## How much of the reference's map-data budget a size consumes.
static func data_words(size: Vector2i) -> int:
	return (size.x + MAP_OFFSET_W) * (size.y + MAP_OFFSET_H)

## What a set of edge deltas would do, decided before anything is touched.
##
## Pure — reads `md` and writes nothing. That is deliberate and is the lesson
## `MapAuthoring.would_overlap` records: a guard that lives inside the function
## performing the write cannot be break-tested without the test performing the
## write too, which corrupted two tracked `.tres` files before it was split out.
##
## Returns `{"ok", "reason", "offset", "old_size", "size", "kept", "added",
## "trimmed"}`. `kept` is the old map's surviving footprint IN NEW COORDINATES,
## which is what both the data and the scene pass iterate against.
static func plan(md: MapData, north: int, south: int, west: int,
		east: int) -> Dictionary:
	var res := {
		"ok": false, "reason": "",
		"offset": Vector2i(west, north),
		"old_size": Vector2i.ZERO, "size": Vector2i.ZERO,
		"kept": Rect2i(), "added": 0, "trimmed": 0,
	}
	if md == null:
		res["reason"] = "no MapData"
		return res

	var old_size := Vector2i(md.width, md.height)
	res["old_size"] = old_size
	if old_size.x <= 0 or old_size.y <= 0:
		res["reason"] = "this map has no cells to resize"
		return res
	# ⚠️ Checked rather than assumed. Every pass below indexes the seven arrays
	# by `y * width + x`; a short array would read the wrong row rather than
	# fail, and the map would come out subtly sheared instead of broken.
	if md.metatile.size() != old_size.x * old_size.y:
		res["reason"] = ("this map's cell arrays (%d) do not match its own %dx%d "
				+ "dimensions (%d) — resizing would shear it") % [
				md.metatile.size(), old_size.x, old_size.y,
				old_size.x * old_size.y]
		return res

	if north == 0 and south == 0 and west == 0 and east == 0:
		res["reason"] = "every edge is zero — nothing to do"
		return res

	var size := Vector2i(old_size.x + west + east, old_size.y + north + south)
	res["size"] = size
	if size.x < MIN_DIM or size.y < MIN_DIM:
		res["reason"] = "those deltas ask for %dx%d — a map needs at least %dx%d" \
				% [size.x, size.y, MIN_DIM, MIN_DIM]
		return res
	if not fits(size):
		res["reason"] = ("those deltas ask for %dx%d, which needs %d of the "
				+ "reference's %d map-data words — the game would refuse to lay "
				+ "it out (fieldmap.c:176)") % [size.x, size.y,
				(size.x + MAP_OFFSET_W) * (size.y + MAP_OFFSET_H),
				MAX_MAP_DATA_SIZE]
		return res

	# The old map's footprint in the NEW coordinate space, clipped to it. When
	# the deltas trim, this is smaller than the old map; when they only grow, it
	# is the whole old map shifted by the offset.
	var kept := Rect2i(Vector2i(west, north), old_size).intersection(
			Rect2i(Vector2i.ZERO, size))
	res["kept"] = kept
	if kept.size.x <= 0 or kept.size.y <= 0:
		res["reason"] = "those deltas would trim every existing cell away"
		return res

	var kept_cells := kept.size.x * kept.size.y
	res["added"] = size.x * size.y - kept_cells
	res["trimmed"] = old_size.x * old_size.y - kept_cells
	res["ok"] = true
	return res


# -------------------------------------------------------------- [2] the data

## Re-lay-out all seven per-cell arrays into the new dimensions.
##
## ⚠️ **A RE-LAYOUT, NOT A `resize()`.** The arrays are row-major over `width`,
## so changing the width moves EVERY row: growing 20x18 to 24x18 by resizing the
## backing array in place would leave row 1 starting four cells into row 0 and
## the whole map diagonally smeared. Each cell is placed by coordinate, into
## fresh arrays, and the old ones are only read.
##
## New cells REPLICATE THE NEAREST EDGE — the clamp below — so extending a map
## into grass or water continues the terrain that was already there rather than
## opening a hole of one arbitrary metatile.
##
## ⚠️ **BUT THE EXPLICIT BITS ARE LEFT CLEAR, WHICH IS THE HALF THAT MATTERS.**
## Collision and elevation are copied from the edge cell as VALUES and marked
## AUTHORED-but-not-explicit, so every new cell reads as `needs_review` in the
## overlay. Measured across all 421 maps, collision varies by placement for
## 52.0% of metatiles and elevation for 52.1% (§1.9), so a replicated attribute
## is a ~87%-right guess, not a decision — and stamping it explicit would have a
## single resize claim hundreds of confirmed decisions nobody made. Same rule,
## same reason, as `MapData.author_cell_with_defaults`.
static func resize_data(md: MapData, p: Dictionary) -> void:
	if md == null or not bool(p.get("ok", false)):
		return
	var old_size: Vector2i = p["old_size"]
	var size: Vector2i = p["size"]
	var off: Vector2i = p["offset"]
	var n := size.x * size.y

	var metatile := PackedInt32Array()
	var collision := PackedInt32Array()
	var elevation := PackedInt32Array()
	var behavior := PackedInt32Array()
	var layer_type := PackedInt32Array()
	var provenance := PackedByteArray()
	var attr_explicit := PackedByteArray()
	metatile.resize(n)
	collision.resize(n)
	elevation.resize(n)
	behavior.resize(n)
	layer_type.resize(n)
	provenance.resize(n)
	attr_explicit.resize(n)

	for ny in range(size.y):
		for nx in range(size.x):
			var i := ny * size.x + nx
			var ox := nx - off.x
			var oy := ny - off.y
			var inside := ox >= 0 and oy >= 0 and ox < old_size.x and oy < old_size.y
			# Clamped rather than skipped: an out-of-range cell reads the nearest
			# EDGE cell, which is what "replicate the edge row/column" means. A
			# corner cell clamps on both axes and therefore copies the corner.
			var si := clampi(oy, 0, old_size.y - 1) * old_size.x \
					+ clampi(ox, 0, old_size.x - 1)

			metatile[i] = _at(md.metatile, si)
			collision[i] = _at(md.collision, si)
			elevation[i] = _at(md.elevation, si, 3)
			behavior[i] = _at(md.behavior, si)
			layer_type[i] = _at(md.layer_type, si)
			if inside:
				# A surviving cell carries its own history over verbatim. An
				# imported cell stays imported: it was not re-decided by being
				# moved, and flipping it AUTHORED would make `map_baker` refuse
				# to re-bake a map nobody hand-edited.
				provenance[i] = _byte_at(md.provenance, si, MapData.Provenance.IMPORTED)
				attr_explicit[i] = _byte_at(md.attr_explicit, si, 0)
			else:
				provenance[i] = MapData.Provenance.AUTHORED
				attr_explicit[i] = 0

	md.width = size.x
	md.height = size.y
	md.metatile = metatile
	md.collision = collision
	md.elevation = elevation
	md.behavior = behavior
	md.layer_type = layer_type
	md.provenance = provenance
	md.attr_explicit = attr_explicit


static func _at(arr: PackedInt32Array, i: int, dflt: int = 0) -> int:
	return arr[i] if i >= 0 and i < arr.size() else dflt


static func _byte_at(arr: PackedByteArray, i: int, dflt: int = 0) -> int:
	return arr[i] if i >= 0 and i < arr.size() else dflt


# ------------------------------------------------------------- [3] the scene

## Move the picture and the placed entities to match the new dimensions.
##
## Call AFTER `resize_data`, because the added cells are painted from the
## already-resized `md`.
##
## Returns `{"tiles_moved", "tiles_painted", "unroutable", "entities_moved",
## "removed"}` — `removed` is the Array of entity NODES that fell outside the
## new bounds. ⚠️ **They are detached, NOT freed**, so the caller can hand them
## to `EditorUndoRedoManager.add_undo_reference()` and have Ctrl+Z put them
## back. Freeing them here would make the trim half of a resize permanently
## irreversible while the other half undid cleanly.
static func resize_scene(root: Node2D, md: MapData, p: Dictionary) -> Dictionary:
	var res := {
		"tiles_moved": 0, "tiles_painted": 0, "unroutable": 0,
		"entities_moved": 0, "removed": [],
	}
	if root == null or not is_instance_valid(root) or md == null \
			or not bool(p.get("ok", false)):
		return res

	var size: Vector2i = p["size"]
	var off: Vector2i = p["offset"]
	var bounds := Rect2i(Vector2i.ZERO, size)

	# --- the picture. Captured whole, cleared, then re-stamped at the shifted
	# coordinate. A per-cell move in place would overwrite cells it had not read
	# yet whenever the offset is positive, so the two-pass shape is required
	# rather than tidy.
	for plane_name in PLANE_LAYER_NAMES:
		var layer := root.get_node_or_null(plane_name) as TileMapLayer
		if layer == null:
			continue
		var carried: Array = []
		for cell in layer.get_used_cells():
			carried.append([
				cell + off,
				layer.get_cell_source_id(cell),
				layer.get_cell_atlas_coords(cell),
				layer.get_cell_alternative_tile(cell),
			])
		layer.clear()
		for entry in carried:
			var at: Vector2i = entry[0]
			if not bounds.has_point(at):
				continue
			layer.set_cell(at, entry[1], entry[2], entry[3])
			res["tiles_moved"] = int(res["tiles_moved"]) + 1

	# --- the cells that did not exist before. Painted through
	# `MapManager.paint_metatile` rather than by setting cells directly, because
	# that is the one function that owns §1.6 routing — a metatile paints into
	# one or TWO of the three planes, and a hand-rolled "put it in Ground" here
	# is the exact mistake that has already cost this project twice.
	var kept: Rect2i = p["kept"]
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			if kept.has_point(cell):
				continue
			var mid := md.metatile_at(x, y)
			if mid < 0:
				continue
			if MapManager.paint_metatile(root, cell, mid, md.atlas):
				res["tiles_painted"] = int(res["tiles_painted"]) + 1
			else:
				# The pair has no routing for this id. `paint_metatile` refuses
				# rather than erasing all three planes, so the cell is simply
				# unpainted — reported, because a silently blank strip along a
				# new edge reads as a resize bug rather than a tileset gap.
				res["unroutable"] = int(res["unroutable"]) + 1

	# --- the placed entities.
	var used := _existing_names(root)
	for container_name in ENTITY_CONTAINERS:
		var container := root.get_node_or_null(container_name) as Node2D
		if container == null:
			continue
		# Backwards, so detaching one cannot shift an index still to be visited
		# — the same array-mutation trap `MapAuthoring._drop_connection` records.
		var kids := container.get_children()
		for i in range(kids.size() - 1, -1, -1):
			var ent := kids[i] as OverworldEntity
			if ent == null:
				continue
			var old_cell: Vector2i = ent.cell
			var new_cell := old_cell + off
			if not bounds.has_point(new_cell):
				# ⚠️ Owner cleared BEFORE the detach. A node keeps its `owner`
				# when removed, and re-adding it later — which is exactly what
				# the undo does — then warns "will make owner inconsistent" and
				# leaves the scene in the state that warning describes.
				ent.owner = null
				container.remove_child(ent)
				(res["removed"] as Array).append(ent)
				continue
			ent.cell = new_cell
			# Names are cell-derived (`Warp_6_7`), so an entity that moved and
			# kept its name would advertise a coordinate it is no longer at.
			var renamed := _shift_name(ent.name, old_cell, new_cell, used)
			if renamed != "":
				used.erase(ent.name)
				ent.name = renamed
				used[renamed] = true
			res["entities_moved"] = int(res["entities_moved"]) + 1
	return res


## Every entity node name currently in the map, so a rename cannot collide.
##
## Godot SILENTLY renames a collision to `@Node2D@N` from a process-wide
## counter, which is how a batch bake stopped being byte-reproducible once
## already (`map_baker._unique_name`). A rename that quietly did that would
## break any authored reference to the node.
static func _existing_names(root: Node2D) -> Dictionary:
	var out := {}
	for container_name in ENTITY_CONTAINERS:
		var container := root.get_node_or_null(container_name) as Node2D
		if container == null:
			continue
		for kid in container.get_children():
			out[kid.name] = true
	return out


## `Warp_6_7` at (6,7) moving to (10,7) becomes `Warp_10_7`. Returns "" to mean
## "leave this name alone".
##
## ⚠️ **ONLY RENAMES A NAME THAT STILL DESCRIBES THE OLD CELL.** A node someone
## renamed by hand, or one whose name never carried coordinates, keeps it — the
## alternative is a tool that quietly discards a human's naming, and a name is
## the only handle an authored script has on a node. The `_2` suffix a stacked
## entity carries is handled by the second branch: 22 cells in Kanto hold two
## events, so `Warp_6_7_2` is real data, not an edge case.
static func _shift_name(name: String, old_cell: Vector2i, new_cell: Vector2i,
		used: Dictionary) -> String:
	var old_tag := "_%d_%d" % [old_cell.x, old_cell.y]
	var new_tag := "_%d_%d" % [new_cell.x, new_cell.y]
	var candidate := ""
	if name.ends_with(old_tag):
		candidate = name.substr(0, name.length() - old_tag.length()) + new_tag
	elif name.contains(old_tag + "_"):
		candidate = name.replace(old_tag + "_", new_tag + "_")
	if candidate == "" or candidate == name:
		return ""
	if not used.has(candidate):
		return candidate
	# A collision here means two entities genuinely landed on one cell, which is
	# legitimate. Suffixed deterministically rather than left to Godot.
	for k in range(2, 100):
		var tried := "%s_%d" % [candidate, k]
		if not used.has(tried):
			return tried
	return ""


# ------------------------------------------------------- [4] undo and redo

## Everything a resize changes, captured as one blob.
##
## ⚠️ **THE OVERLAY'S OWN `snapshot_cells` IS NOT ENOUGH AND WOULD FAIL
## SILENTLY.** It captures the seven arrays and the tile blobs but NOT `width`,
## `height` or the entities — so undoing a resize through it would restore
## 24x18-shaped arrays into a MapData still claiming to be 20x18, which is not a
## broken map so much as a differently sheared one. Resize needs its own pair.
static func snapshot(md: MapData, root: Node2D) -> Dictionary:
	if md == null:
		return {}
	var snap := {
		"width": md.width,
		"height": md.height,
		"metatile": md.metatile.duplicate(),
		"collision": md.collision.duplicate(),
		"elevation": md.elevation.duplicate(),
		"behavior": md.behavior.duplicate(),
		"layer_type": md.layer_type.duplicate(),
		"provenance": md.provenance.duplicate(),
		"attr_explicit": md.attr_explicit.duplicate(),
		"connections": md.connections.duplicate(true),
		"tiles": {},
		"entities": [],
	}
	if root == null or not is_instance_valid(root):
		return snap

	for plane_name in PLANE_LAYER_NAMES:
		var layer := root.get_node_or_null(plane_name) as TileMapLayer
		if layer != null:
			(snap["tiles"] as Dictionary)[plane_name] = layer.tile_map_data.duplicate()

	for container_name in ENTITY_CONTAINERS:
		var container := root.get_node_or_null(container_name) as Node2D
		if container == null:
			continue
		for kid in container.get_children():
			var ent := kid as OverworldEntity
			if ent == null:
				continue
			(snap["entities"] as Array).append({
				"node": ent, "container": container_name,
				"name": String(ent.name), "cell": ent.cell,
			})
	return snap


## Put a map back exactly as `snapshot` found it. Drives BOTH directions of the
## undo action — redo restores the "after" snapshot by the identical path, so
## there is one restore to get right instead of an apply and an inverse.
static func restore(md: MapData, root: Node2D, snap: Dictionary) -> void:
	if md == null or snap.is_empty():
		return
	md.width = int(snap["width"])
	md.height = int(snap["height"])
	md.metatile = snap["metatile"]
	md.collision = snap["collision"]
	md.elevation = snap["elevation"]
	md.behavior = snap["behavior"]
	md.layer_type = snap["layer_type"]
	md.provenance = snap["provenance"]
	md.attr_explicit = snap["attr_explicit"]
	if snap.has("connections"):
		md.connections.assign(snap["connections"])

	if root == null or not is_instance_valid(root):
		return
	for plane_name in (snap.get("tiles", {}) as Dictionary):
		var layer := root.get_node_or_null(str(plane_name)) as TileMapLayer
		if layer != null:
			layer.tile_map_data = (snap["tiles"] as Dictionary)[plane_name]

	_restore_entities(root, snap.get("entities", []) as Array)


## Three passes, and the middle one is not optional.
##
## ⚠️ **EVERY NODE IS GIVEN A THROWAWAY NAME BEFORE ANY REAL ONE IS SET.**
## Restoring names in one pass hits transient collisions — node A wants the name
## node B is still holding — and Godot resolves those by silently renaming, so
## the map would come back from an undo with `@Node2D@41` where a script's
## target used to be. Parking every name first makes the final pass collision-free
## by construction.
static func _restore_entities(root: Node2D, manifest: Array) -> void:
	var wanted := {}
	for entry in manifest:
		var ent := (entry as Dictionary)["node"] as OverworldEntity
		if ent != null and is_instance_valid(ent):
			wanted[ent] = true

	# Pass 1: detach anything the snapshot did not have. Detached, never freed —
	# a redo of a trim must leave the node recoverable by the undo after it.
	for container_name in ENTITY_CONTAINERS:
		var container := root.get_node_or_null(container_name) as Node2D
		if container == null:
			continue
		var kids := container.get_children()
		for i in range(kids.size() - 1, -1, -1):
			if kids[i] is OverworldEntity and not wanted.has(kids[i]):
				# Same reason as the detach in `resize_scene` — a stale owner
				# survives the removal and poisons the next re-attach.
				kids[i].owner = null
				container.remove_child(kids[i])

	# Pass 2: reattach and park every name out of the way.
	var parked := 0
	for entry in manifest:
		var e: Dictionary = entry
		var ent := e["node"] as OverworldEntity
		if ent == null or not is_instance_valid(ent):
			continue
		if ent.get_parent() == null:
			var container := root.get_node_or_null(str(e["container"])) as Node2D
			if container == null:
				continue
			container.add_child(ent)
			# Owned by the scene root or `PackedScene.pack()` drops it — the
			# same rule `map_baker._set_owner_recursive` exists for.
			ent.owner = root
		ent.name = "__resize_parked_%d" % parked
		parked += 1

	# Pass 3: the real names and cells.
	for entry in manifest:
		var e: Dictionary = entry
		var ent := e["node"] as OverworldEntity
		if ent == null or not is_instance_valid(ent) or ent.get_parent() == null:
			continue
		ent.name = str(e["name"])
		ent.cell = e["cell"]


# --------------------------------------------------- [5] the neighbour guard

## Which already-placed maps the resized map would land on top of.
##
## ⚠️ **A GROW IS A PLACEMENT CHANGE, WHICH IS WHY THIS EXISTS AT ALL.** Adding
## eight columns to the east pushes nothing — the east neighbour re-derives flush
## against the new edge — but it does put eight columns of this map where empty
## world used to be, and a map two hops away can be sitting there. That is the
## same failure `MapAuthoring.would_overlap` was built for, and it is refused for
## the same reason: `chunk_owning()` is first-match-wins over an UNORDERED
## Dictionary, so two overlapping chunks answer differently run to run.
##
## Runs the real placement BFS with this map's post-resize size and connection
## offsets substituted, rather than re-deriving the geometry here — one rule,
## one implementation.
## ⚠️ **TAKES THE LIVE `MapData` RATHER THAN RE-LOADING IT, AND THE DIFFERENCE
## IS A WRONG ANSWER.** `load()` returns what is on DISK, and the map being
## resized is the one the overlay has been editing in memory — so a second
## resize before a Save Map Data would be checked against the dimensions the
## first one already superseded, and would clear a guard it should have failed.
## Only the OTHER maps are read from disk, which is correct: they have no
## in-memory edits to miss.
static func overlaps_after(map_name: String, md: MapData, p: Dictionary,
		realign: bool) -> Array:
	var out: Array = []
	if md == null or not bool(p.get("ok", false)):
		return out

	var conns: Array = md.connections.duplicate(true)
	if realign:
		conns = realigned_connections(conns, p)
	var rects := MapAuthoring.placed_rects(map_name, {
		map_name: {"size": p["size"], "connections": conns},
	})
	if not rects.has(map_name):
		return out
	var host_rect: Rect2i = rects[map_name]
	for name in rects:
		if name == map_name:
			continue
		if (rects[name] as Rect2i).intersects(host_rect):
			out.append(name)
	return out


# ------------------------------------------------ [6] keeping neighbours lined up

## The map's own connection offsets, corrected so existing content stays lined
## up with the maps it borders.
##
## ⚠️ **WITHOUT THIS, GROWING A MAP SILENTLY SLIDES EVERY SEAM.** A connection's
## `offset` shifts the neighbour along the shared edge, measured from this map's
## own origin — and adding rows to the NORTH moves all existing content down by
## that many rows while the origin stays put. So the tile that used to line up
## with the neighbour's row 0 is now `north` rows lower, and the seam is wrong by
## exactly the amount you grew. 104 of the reference's 266 connections carry a
## nonzero offset, so this is the common case, not the corner.
##
## Which delta applies is decided by which AXIS the edge runs along, not by which
## edge it is: a NORTH or SOUTH neighbour slides horizontally, so it takes the
## west delta; a WEST or EAST neighbour slides vertically, so it takes the north
## delta. Growing south or east moves no existing content and therefore corrects
## nothing — the neighbour simply re-derives flush against the longer edge.
static func realigned_connections(connections: Array, p: Dictionary) -> Array:
	var off: Vector2i = p["offset"]
	var out: Array = []
	for c in connections:
		var entry: Dictionary = (c as Dictionary).duplicate()
		var dir := int(entry.get("direction", MapData.Connection.NONE))
		match dir:
			MapData.Connection.NORTH, MapData.Connection.SOUTH:
				entry["offset"] = int(entry.get("offset", 0)) + off.x
			MapData.Connection.WEST, MapData.Connection.EAST:
				entry["offset"] = int(entry.get("offset", 0)) + off.y
			_:
				# DIVE/EMERGE warp rather than stitching geometry (§1), so they
				# have no shared edge to slide along and no offset to correct.
				pass
		out.append(entry)
	return out


## Write the matching correction onto every neighbour's own reciprocal edge.
##
## ⚠️ **THIS TOUCHES OTHER MAPS' FILES ON DISK AND IS NOT UNDOABLE**, which is
## why the caller makes it an explicit opt-in and names every file written. The
## host's own side is corrected in memory and rides along with Save Map Data;
## the guests have no open scene to hold an edit, exactly as `connect_maps`
## already found when it chose to save both sides itself.
##
## The reciprocal offset is the NEGATIVE of this map's, so a `+4` here is a `-4`
## there — deriving it rather than recomputing it is what stops the two sides
## drifting into a seam that looks plausible until you walk it.
##
## Matched on (direction, map) rather than direction alone: 3 maps in the
## reference carry more than one connection on a single edge, so "the WEST one"
## is ambiguous where it matters most.
##
## Returns `{"ok", "reason", "written": Array, "missing": Array}`.
## Reads the host's edges from the LIVE `md` for the same reason
## `overlaps_after` does — a seam added in this session but not yet saved is
## still a seam this map has.
static func realign_neighbours(map_name: String, md: MapData,
		p: Dictionary) -> Dictionary:
	var res := {"ok": false, "reason": "", "written": [], "missing": []}
	if md == null:
		res["reason"] = "no MapData for %s" % map_name
		return res
	var off: Vector2i = p["offset"]

	for c in md.connections:
		var dir := int(c.get("direction", MapData.Connection.NONE))
		if not MapAuthoring.OPPOSITE.has(dir):
			continue
		var delta := off.x if dir in [MapData.Connection.NORTH,
				MapData.Connection.SOUTH] else off.y
		if delta == 0:
			continue
		var guest := MapConstants.map_name_for(str(c.get("map", "")))
		if guest == "":
			continue
		var gd := _load_data(guest)
		if gd == null:
			(res["missing"] as Array).append(guest)
			continue
		var back := int(MapAuthoring.OPPOSITE[dir])
		var found := false
		for gc in gd.connections:
			if int(gc.get("direction", -1)) != back:
				continue
			if MapConstants.map_name_for(str(gc.get("map", ""))) != map_name:
				continue
			gc["offset"] = int(gc.get("offset", 0)) - delta
			found = true
		if not found:
			# Reported, not fatal — the two sides had already drifted, and
			# `disconnect_maps` records the same judgement for the same case.
			(res["missing"] as Array).append(guest)
			continue
		var err := ResourceSaver.save(gd, MapAuthoring.OUT_DIR + guest + "_data.tres")
		if err != OK:
			res["reason"] = "could not write %s (%s)" % [guest, error_string(err)]
			return res
		(res["written"] as Array).append(guest)
	res["ok"] = true
	return res


static func _load_data(map_name: String) -> MapData:
	var path := MapAuthoring.OUT_DIR + map_name + "_data.tres"
	return load(path) as MapData if ResourceLoader.exists(path) else null


# ------------------------------------------- [7] the two-artifact mismatch

## The cell rectangle the SCENE actually paints into, across all three planes.
##
## `Rect2i()` when nothing is painted or the planes are missing.
static func painted_extent(root: Node2D) -> Rect2i:
	if root == null or not is_instance_valid(root):
		return Rect2i()
	var out := Rect2i()
	var seen := false
	for plane_name in PLANE_LAYER_NAMES:
		var layer := root.get_node_or_null(plane_name) as TileMapLayer
		if layer == null:
			continue
		var r := layer.get_used_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		out = r if not seen else out.merge(r)
		seen = true
	return out


## ⚠️ **DOES THE PICTURE AGREE WITH THE CELL DATA ABOUT HOW BIG THIS MAP IS?**
##
## This exists because of a real defect, found by Rob on the first real drive of
## the resize tool: the resize changes BOTH artifacts, but they are saved by two
## different gestures — the scene by Ctrl+S, the `_data.tres` by Save Map Data —
## and doing only the first persists shifted tiles and entities against
## unshifted collision. The map then loads, looks right, and has its movement
## rules four rows out of register. Nothing anywhere said so.
##
## The resize no longer leaves that state (it writes the `.tres` itself), but
## this stays for the two cases that fix cannot reach: **maps already saved that
## way before the fix**, and any other cause of the same divergence.
##
## ⚠️ **KEYED ON PAINT OUTSIDE THE BOUNDS, NOT ON A SIZE COMPARISON.** A painted
## extent SMALLER than the data is completely normal — plenty of maps have
## unpainted cells at an edge, and 421 of them would light this up. A tile drawn
## where the data says there is no cell cannot be anything but wrong.
##
## Returns `{"mismatch": bool, "painted": Rect2i, "data": Vector2i,
## "overhang": Vector2i}` — `overhang` is how far past the data bounds the paint
## reaches, which is the number an author needs to recognise their own resize.
static func size_mismatch(md: MapData, root: Node2D) -> Dictionary:
	var res := {
		"mismatch": false, "painted": Rect2i(), "data": Vector2i.ZERO,
		"overhang": Vector2i.ZERO,
	}
	if md == null:
		return res
	res["data"] = Vector2i(md.width, md.height)
	var painted := painted_extent(root)
	res["painted"] = painted
	if painted.size.x <= 0 or painted.size.y <= 0:
		return res
	var over := Vector2i(
			maxi(painted.end.x - md.width, 0),
			maxi(painted.end.y - md.height, 0))
	res["overhang"] = over
	res["mismatch"] = over.x > 0 or over.y > 0
	return res


# ---------------------------------------------------------- [8] what it did

## The one-line summaries a caller reports, built here so the dialog and any
## headless driver say the same thing about the same numbers.
static func describe(p: Dictionary, scene_report: Dictionary) -> String:
	var old_size: Vector2i = p["old_size"]
	var size: Vector2i = p["size"]
	var off: Vector2i = p["offset"]
	var out := "%dx%d -> %dx%d, content offset by (%d, %d)" \
			% [old_size.x, old_size.y, size.x, size.y, off.x, off.y]
	out += "\n%d cell(s) added, %d trimmed" % [int(p["added"]), int(p["trimmed"])]
	if not scene_report.is_empty():
		out += "\n%d tile(s) moved, %d painted, %d entit(ies) moved" % [
			int(scene_report.get("tiles_moved", 0)),
			int(scene_report.get("tiles_painted", 0)),
			int(scene_report.get("entities_moved", 0)),
		]
	return out
