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


## A cell a human painted but never decided the movement rules for. This is the
## overlay's whole reason to exist — these are invisible in the rendered map and
## wrong ~13% of the time.
func needs_review(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var i := _idx(x, y)
	if i >= provenance.size() or provenance[i] != Provenance.AUTHORED:
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
