@tool
# @tool because MapOverlay is an editor surface and Godot instantiates a
# NON-@tool script as a PLACEHOLDER in the editor -- calling into one throws
# "Attempt to call a method on a placeholder instance". The whole read chain
# behind the overlay must therefore be @tool. Safe: nothing here mutates
# state or touches the scene tree.
class_name MapData
extends Resource

## [M27A] One imported map's per-cell data.
##
## Produced by scripts/gen_map_import.py. Collision and elevation are stored
## PER CELL rather than on the TileSet, because they are properties of the
## position, not of the metatile — 52.1% of Kanto metatiles appear at more
## than one elevation (docs/overworld_scope.md §1.4). Behaviour IS per-metatile
## and is carried here per-cell only as a pre-resolved convenience.

## [M27B Change 1] MapData is a Resource so a baked map ships as a .tres
## beside its .tscn — the scene is the artifact, JSON is a build input.
@export var map_name: String = ""
@export var layout: String = ""
## Shared per tileset PAIR, not per map — 421 Kanto maps use 60 pairs.
@export var atlas: String = ""
@export var width: int = 0
@export var height: int = 0

## [M27N] Ordinals match include/constants/weather.h EXACTLY (gaps included —
## 4/9/10 are confirmed dead in the reference game itself, 15/20-23 are
## Hoenn-plot/route-specific with no Kanto equivalent), so a future opcode/
## save-data reference can cite the same numbers as source.
enum Weather {
	NONE = 0, SUNNY_CLOUDS = 1, SUNNY = 2, RAIN = 3, RAIN_THUNDERSTORM = 5,
	FOG_HORIZONTAL = 6, VOLCANIC_ASH = 7, SANDSTORM = 8, SHADE = 11,
	DROUGHT = 12, DOWNPOUR = 13, UNDERWATER_BUBBLES = 14,
}
@export var weather: int = Weather.NONE

@export var metatile: PackedInt32Array = PackedInt32Array()
@export var collision: PackedInt32Array = PackedInt32Array()
@export var elevation: PackedInt32Array = PackedInt32Array()
@export var behavior: PackedInt32Array = PackedInt32Array()
@export var layer_type: PackedInt32Array = PackedInt32Array()

## [M27B Change 3] Per-cell provenance: IMPORTED cells may be refreshed by a
## re-import, AUTHORED cells may not. The importer refuses to overwrite a map
## containing any AUTHORED cell unless --force. Must exist in the format from
## the start — it cannot be retrofitted onto data that stores only final
## values (docs/overworld_scope.md §1.9).
enum Provenance { IMPORTED, AUTHORED }
@export var provenance: PackedByteArray = PackedByteArray()


## [M27B Change 3] Which per-cell attributes a HUMAN actually decided.
##
## Collision and elevation cannot be inferred from a painted tile: measured
## across all 421 maps, collision varies by placement for 52.0% of metatiles and
## elevation for 52.1%, and a per-metatile collision default would mis-set
## 29,827 cells (12.93%). So a newly painted cell gets a *guess* — inherited
## from the cell painted over — which is right roughly 87% of the time. The
## remaining 13% is exactly what has to stay visible.
##
## Recorded per ATTRIBUTE rather than per cell, because the two are set
## independently: an author may pin elevation on a bridge tile while leaving its
## collision inherited. Folding this into Provenance would lose that.
##
## An IMPORTED cell counts as explicit on both — its values came from source and
## are authoritative, not a guess. A newly AUTHORED cell starts with neither bit
## until someone sets it, so "needs review" is precisely
## `AUTHORED and not explicit`.
##
## Bitflags rather than two arrays so behaviour can join later without another
## format change.
enum AttrFlag {
	COLLISION_EXPLICIT = 1,
	ELEVATION_EXPLICIT = 2,
}
const ATTR_ALL_EXPLICIT := AttrFlag.COLLISION_EXPLICIT | AttrFlag.ELEVATION_EXPLICIT

@export var attr_explicit: PackedByteArray = PackedByteArray()


## [M27C C1] Which maps sit against which edge, and how they line up.
##
## Ordinals match the reference's own `enum Connection`
## (include/constants/global.h) so the two can be read side by side. Note the
## crossover map.json forces: its "up" is NORTH, its "down" is SOUTH.
##
## DIVE/EMERGE are carried because the data has them (7 of each across the
## reference), but §1 settles that they WARP rather than stitching geometry —
## a chunk loader must not treat them as adjacency.
enum Connection { NONE, SOUTH, NORTH, WEST, EAST, DIVE, EMERGE }

## One entry per connected edge: `{direction: int, map: String, offset: int}`.
##
## `map` is the raw `MAP_*` constant, matching what `Warp.dest_map` already
## stores, so both kinds of link resolve through the one `MapConstants` table —
## and so "source does not define this destination" (a bug) stays
## distinguishable from "defined but not baked yet" (the expected M27C gap).
##
## `offset` shifts the neighbour along the shared edge and is genuinely
## load-bearing: 104 of 266 connections in the reference carry a nonzero one.
@export var connections: Array[Dictionary] = []

## The block painted outside the map on any edge with NO loadable neighbour,
## row-major over `border_width` x `border_height`. Metatile ids only — a skirt
## cell's impassability is a rule the loader applies, not a value read here.
##
## Defaults are 2x2 because that is the reference's own: 441 of 785 layouts
## omit the dimensions entirely and every one of those ships a 4-entry
## border.bin. Seven declare 3x2, which is why these are fields rather than
## constants.
@export var border: PackedInt32Array = PackedInt32Array()

## Per-border-metatile layer type, parallel to `border`. Needed because a
## metatile routes to one or two of the three draw planes (§1.6) and a skirt
## painted into the ground plane alone shows half of each block.
@export var border_layer_type: PackedInt32Array = PackedInt32Array()
@export var border_width: int = 2
@export var border_height: int = 2


## The connected edges a chunk loader can actually act on.
##
## Excludes DIVE/EMERGE (warps, not adjacency) and anything whose destination
## does not resolve to a baked scene. Deliberately one place rather than each
## caller re-deriving it: the corridor has 15 connections of which 3 dangle,
## so "has a connection" and "has a neighbour to load" are genuinely different
## questions, and an edge that fails this test is one that needs a border skirt.
func loadable_connections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in connections:
		var dir: int = int(c.get("direction", Connection.NONE))
		if dir == Connection.DIVE or dir == Connection.EMERGE:
			continue
		if MapConstants.is_baked(str(c.get("map", ""))):
			out.append(c)
	return out


## True if any cell has been hand-authored — the re-import guard.
func has_authored_cells() -> bool:
	for p in provenance:
		if p == Provenance.AUTHORED:
			return true
	return false


func _flags_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	var i := _idx(x, y)
	return attr_explicit[i] if i < attr_explicit.size() else 0


func collision_is_explicit(x: int, y: int) -> bool:
	return (_flags_at(x, y) & AttrFlag.COLLISION_EXPLICIT) != 0


func elevation_is_explicit(x: int, y: int) -> bool:
	return (_flags_at(x, y) & AttrFlag.ELEVATION_EXPLICIT) != 0


## Has a human touched this cell at all?
##
## Deliberately WIDER than `needs_review`, which is the narrower "touched but
## not yet decided" case — a fully confirmed cell is still authored. That width
## is the point: the baker's re-import guard keys on this, not on review state,
## so a cell can be entirely unremarkable to look at and still be the reason a
## map refuses to re-bake.
func is_authored(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var i := _idx(x, y)
	return i < provenance.size() and provenance[i] == Provenance.AUTHORED


## A cell a human painted but never decided the movement rules for. This is the
## overlay's whole reason to exist — these are invisible in the rendered map and
## wrong ~13% of the time.
func needs_review(x: int, y: int) -> bool:
	if not is_authored(x, y):
		return false
	return _flags_at(x, y) != ATTR_ALL_EXPLICIT


func review_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			if needs_review(x, y):
				out.append(Vector2i(x, y))
	return out


func set_attr_explicit(x: int, y: int, flag: int, value: bool = true) -> void:
	if not in_bounds(x, y):
		return
	var i := _idx(x, y)
	if attr_explicit.size() != metatile.size():
		_resize_attr_explicit()
	attr_explicit[i] = (attr_explicit[i] | flag) if value else (attr_explicit[i] & ~flag)


## [M27B Change 2 — write half] Set a cell's collision and record that a HUMAN
## decided it. Always paired: a value written without the explicit bit is
## indistinguishable from a guess, which is the whole thing §1.9 exists to
## prevent. Marks the cell AUTHORED, because a cell someone has decided about
## is by definition no longer purely imported.
func set_collision(x: int, y: int, value: int) -> void:
	if not in_bounds(x, y):
		return
	collision[_idx(x, y)] = value
	set_attr_explicit(x, y, AttrFlag.COLLISION_EXPLICIT, true)
	_mark_authored(x, y)


func set_elevation(x: int, y: int, value: int) -> void:
	if not in_bounds(x, y):
		return
	elevation[_idx(x, y)] = value
	set_attr_explicit(x, y, AttrFlag.ELEVATION_EXPLICIT, true)
	_mark_authored(x, y)


## Mark a cell hand-authored and give it INHERITED defaults, explicitly NOT
## marked explicit.
##
## This is the case §1.9 is really about. Collision and elevation cannot be
## inferred from a painted tile — measured across all 421 maps, collision
## varies by placement for 52.0% of metatiles and elevation for 52.1%, and a
## per-metatile default would mis-set 29,827 cells (12.93%). So a newly painted
## cell gets a GUESS, inherited from a neighbour, right roughly 87% of the
## time. The remaining 13% is what has to stay visible, which is exactly what
## leaving the explicit bits clear does: the cell reads as `needs_review` until
## a human confirms each attribute.
##
## Returns false if there was no in-bounds neighbour to inherit from.
func author_cell_with_defaults(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var src := _nearest_neighbour(x, y)
	if src == Vector2i(-1, -1):
		return false
	var i := _idx(x, y)
	collision[i] = collision_at(src.x, src.y)
	elevation[i] = elevation_at(src.x, src.y)
	_mark_authored(x, y)
	# Deliberately CLEARED, not set: these are guesses until confirmed.
	set_attr_explicit(x, y, ATTR_ALL_EXPLICIT, false)
	return true


## Nearest orthogonal neighbour, in a fixed order so authoring is reproducible.
func _nearest_neighbour(x: int, y: int) -> Vector2i:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if in_bounds(x + d.x, y + d.y):
			return Vector2i(x + d.x, y + d.y)
	return Vector2i(-1, -1)


func _mark_authored(x: int, y: int) -> void:
	if provenance.size() != metatile.size():
		provenance.resize(metatile.size())
	provenance[_idx(x, y)] = Provenance.AUTHORED


func _resize_attr_explicit() -> void:
	var old := attr_explicit
	attr_explicit = PackedByteArray()
	attr_explicit.resize(metatile.size())
	for i in range(metatile.size()):
		# A cell with no recorded flags is only trustworthy if it came from the
		# importer; anything else defaults to "not yet decided".
		if i < old.size():
			attr_explicit[i] = old[i]
		elif i < provenance.size() and provenance[i] == Provenance.IMPORTED:
			attr_explicit[i] = ATTR_ALL_EXPLICIT
		else:
			attr_explicit[i] = 0


## Entity draw priority for a cell, from source's own sElevationToPriority.
## Lower draws on top. 4 -> 1 (above the overhang plane), but 5 -> 2, back to
## ground level; this is why the container split cannot be "upper vs lower".
func priority_at(x: int, y: int) -> int:
	var e := elevation_at(x, y)
	if e < 0 or e > 15:
		return 2
	return MetatileBehavior.ELEVATION_TO_PRIORITY[e]


static func load_from(path: String) -> MapData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MapData: cannot open %s" % path)
		return null
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("MapData: %s is not a JSON object" % path)
		return null

	var d: Dictionary = raw
	var m := MapData.new()
	m.map_name = str(d.get("name", ""))
	m.layout = str(d.get("layout", ""))
	m.atlas = str(d.get("atlas", ""))
	m.width = int(d.get("width", 0))
	m.height = int(d.get("height", 0))
	m.weather = int(d.get("weather", 0))
	m.metatile = _to_ints(d.get("metatile", []))
	m.collision = _to_ints(d.get("collision", []))
	m.elevation = _to_ints(d.get("elevation", []))
	m.behavior = _to_ints(d.get("behavior", []))
	m.layer_type = _to_ints(d.get("layer_type", []))
	m.provenance = _to_bytes(d.get("provenance", []))
	# A map with no provenance array predates the format; treat every cell as
	# IMPORTED rather than guessing, so the re-import guard fails safe open.
	if m.provenance.size() != m.metatile.size():
		m.provenance = _to_bytes([])
		m.provenance.resize(m.metatile.size())
		m.provenance.fill(Provenance.IMPORTED)

	# [Change 3] Read back explicitly, with the same fail-safe shape provenance
	# uses: a missing/short array on an IMPORTED map means "source said so",
	# which is explicit, not a guess.
	#
	# Read-back is called out because Change 1 nearly shipped provenance
	# write-only — declared and written to JSON but never read here, so it
	# persisted empty and the re-import guard could not have fired. That was
	# caught and fixed inside Change 1 by its own test; provenance round-trips
	# correctly today, verified against a real baked .tres. The lesson kept is
	# that a field which round-trips only halfway is worse than no field,
	# because it looks present.
	m.attr_explicit = _to_bytes(d.get("attr_explicit", []))
	if m.attr_explicit.size() != m.metatile.size():
		m._resize_attr_explicit()

	# [M27C C1] Read back EXPLICITLY, and tested for it — this is the exact
	# shape Change 1 nearly shipped broken, where provenance was declared and
	# written to JSON but never read here, so it round-tripped as an empty
	# array and the guard depending on it could never fire. A field that
	# round-trips halfway is worse than no field, because it looks present.
	m.border = _to_ints(d.get("border", []))
	m.border_layer_type = _to_ints(d.get("border_layer_type", []))
	m.border_width = int(d.get("border_width", 2))
	m.border_height = int(d.get("border_height", 2))

	# JSON gives untyped Dictionaries; assigning the parsed array straight to a
	# typed Array[Dictionary] export silently fails (this project's own
	# documented GDScript gotcha), so it is rebuilt entry by entry — and the
	# numeric fields need int() because JSON.parse_string returns every number
	# as a float.
	m.connections = []
	for raw_c in d.get("connections", []):
		if typeof(raw_c) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = raw_c
		m.connections.append({
			"direction": int(c.get("direction", Connection.NONE)),
			"map": str(c.get("map", "")),
			"offset": int(c.get("offset", 0)),
		})
	return m


static func _to_bytes(v: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	if typeof(v) != TYPE_ARRAY:
		return out
	for x in (v as Array):
		out.append(int(x))
	return out


## JSON numbers arrive as floats — cast explicitly. This project has been
## bitten by that before (see CLAUDE.md's GDScript gotchas).
static func _to_ints(v: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if typeof(v) != TYPE_ARRAY:
		return out
	for x in (v as Array):
		out.append(int(x))
	return out


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func _idx(x: int, y: int) -> int:
	return y * width + x


func metatile_at(x: int, y: int) -> int:
	return metatile[_idx(x, y)] if in_bounds(x, y) else -1


func collision_at(x: int, y: int) -> int:
	return collision[_idx(x, y)] if in_bounds(x, y) else 1


func elevation_at(x: int, y: int) -> int:
	return elevation[_idx(x, y)] if in_bounds(x, y) else -1


func behavior_at(x: int, y: int) -> int:
	return behavior[_idx(x, y)] if in_bounds(x, y) else -1


func layer_type_at(x: int, y: int) -> int:
	return layer_type[_idx(x, y)] if in_bounds(x, y) else -1


## Is a placed entity standing on this cell?
##
## [M27D D2] Always false, and that is correct rather than a stub: entities are
## NODES in the baked scene, while MapData is the per-cell terrain resource. A
## MapData on its own — which is what the editor overlay resolves against —
## genuinely has no one standing on it. The runtime path answers for real
## through MapManager, which can see the scene.
func entity_at(_x: int, _y: int) -> bool:
	return false
