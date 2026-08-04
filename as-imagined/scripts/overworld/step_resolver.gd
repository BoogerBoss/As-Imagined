@tool
# @tool because MapOverlay is an editor surface and Godot instantiates a
# NON-@tool script as a PLACEHOLDER in the editor -- calling into one throws
# "Attempt to call a method on a placeholder instance". The whole read chain
# behind the overlay must therefore be @tool. Safe: nothing here mutates
# state or touches the scene tree.
class_name StepResolver
extends RefCounted

## [M27A] Logic-based grid step resolution.
##
## Ported from source's GetVanillaCollision / IsMetatileDirectionallyImpassable
## / IsElevationMismatchAt. Per docs/overworld_scope.md §1.8 the SEMANTICS are
## ported faithfully while the expression is Godot-idiomatic: source's C
## function-pointer tables (gDirectionBlockedMetatileFuncs) become a const
## Dictionary here, exactly as the battle engine turned sMoveSuccessOrderCancelers
## into StatusManager.pre_move_check rather than reproducing the table.
##
## A step is a REQUEST returning an OUTCOME, never a bool — §1.7. Physics
## layers are deliberately not used (§0): source stores collision as bits in
## the map data and tests it per tile.

enum Dir { SOUTH, NORTH, WEST, EAST }

## Subset of source's 15-value enum covering the mechanics currently scoped.
## Deliberately left open: adding PUSHED_BOULDER (Strength, M27E) or the rail
## variants must not change this resolver's signature.
enum Outcome {
	NONE,                ## step allowed
	OUTSIDE_RANGE,       ## off the map / no connection
	IMPASSABLE,          ## collision bit, or a directional rule
	ELEVATION_MISMATCH,  ## strata disagree and neither is a wildcard
	LEDGE_JUMP,          ## redirect: two-tile hop, not a block
	OBJECT_EVENT,        ## an NPC, trainer or item ball is standing there
}

const STEP: Dictionary = {
	Dir.SOUTH: Vector2i(0, 1),
	Dir.NORTH: Vector2i(0, -1),
	Dir.WEST: Vector2i(-1, 0),
	Dir.EAST: Vector2i(1, 0),
}

## §1.7 — the two-sided rule. Moving SOUTH means leaving the current tile by
## its south edge and entering the target by its north edge, so the two tables
## are mirror images. Implementing only the entry side looks correct across
## most of the world and fails exactly where a one-way tile was placed.
const EXIT_BLOCKED: Dictionary = {
	Dir.SOUTH: MetatileBehavior.BLOCKED_SOUTH,
	Dir.NORTH: MetatileBehavior.BLOCKED_NORTH,
	Dir.WEST: MetatileBehavior.BLOCKED_WEST,
	Dir.EAST: MetatileBehavior.BLOCKED_EAST,
}
const ENTRY_BLOCKED: Dictionary = {
	Dir.SOUTH: MetatileBehavior.BLOCKED_NORTH,
	Dir.NORTH: MetatileBehavior.BLOCKED_SOUTH,
	Dir.WEST: MetatileBehavior.BLOCKED_EAST,
	Dir.EAST: MetatileBehavior.BLOCKED_WEST,
}

## A ledge is only jumpable in its own direction — you never hop UP one.
## Measured: MB_JUMP_NORTH never appears anywhere in Kanto (§1.7).
const LEDGE_FOR: Dictionary = {
	Dir.SOUTH: MetatileBehavior.LEDGE_SOUTH,
	Dir.NORTH: MetatileBehavior.LEDGE_NORTH,
	Dir.WEST: MetatileBehavior.LEDGE_WEST,
	Dir.EAST: MetatileBehavior.LEDGE_EAST,
}

## Wildcards: both short-circuit an elevation comparison to "compatible".
## ELEVATION_TRANSITION is 56% of Kanto — it means "unconstrained here",
## not "this is a staircase" (§1.4).
const ELEVATION_TRANSITION := 0
const ELEVATION_MULTI_LEVEL := 15

## The cell source. Deliberately untyped rather than `MapData`.
##
## [M27C C4] `resolve()` and its two helpers touch exactly FOUR methods —
## `in_bounds`, `behavior_at`, `collision_at`, `elevation_at` — all of them
## `(x, y) -> value`. Anything providing those four can drive the step rules,
## which is what lets a `MapManager` supply them in GLOBAL coordinates and
## makes a step across a chunk seam use the same code as one inside a map.
##
## That matters because of §1.7's TWO-SIDED directional rule: the exit rule
## applies to the tile being left and the entry rule to the tile being entered,
## and at a seam those two tiles live in different `MapData`s. A second
## implementation of that rule for the cross-seam case would be two hand-kept
## copies of one rule set — the exact shape that produced this milestone's
## `check_bake_diff` false positive — so there is one implementation and the
## source of cells varies instead.
##
## `cell_info()` below is NOT part of that seam. It is the overlay's per-map
## read surface and needs `MapData` specifically (provenance, explicit bits,
## the metatile). The overlay always edits one map, so that is not a limitation.
var _cells

var no_collision: bool = false  ## §20 debug toggle; mirrors OW_FLAG_NO_COLLISION

## [M27E E1] Is the player on the water right now?
##
## ⚠️ **THIS INVERTS THE COLLISION RULE RATHER THAN RELAXING IT.** On foot, water
## is impassable because its collision bit is set. Surfing does NOT simply ignore
## collision — that would let the player ride the blob through walls. It makes
## SURFABLE tiles passable *despite* the bit, and leaves everything else exactly
## as strict as it was, so the only non-water tile you can reach from the water
## is one that was already walkable: the shore. Dismounting therefore needs no
## rule of its own, which is why there isn't one.
var surfing: bool = false


func _init(cells) -> void:
	_cells = cells


## Resolve one step. Returns { outcome, to, ledge_to }.
## `to` is the cell actually landed on; for a ledge that is TWO tiles away.
func resolve(from: Vector2i, dir: int, elevation: int) -> Dictionary:
	var delta: Vector2i = STEP[dir]
	var to: Vector2i = from + delta

	if no_collision:
		return _r(Outcome.NONE, to)

	if not _cells.in_bounds(to.x, to.y):
		return _r(Outcome.OUTSIDE_RANGE, from)

	# Ledge is checked BEFORE impassability: a ledge tile is solid to walk
	# onto but jumpable in its own direction, so it must not be rejected by
	# the collision bit first.
	if _cells.behavior_at(to.x, to.y) == LEDGE_FOR[dir]:
		var land: Vector2i = to + delta
		if _cells.in_bounds(land.x, land.y):
			return _r(Outcome.LEDGE_JUMP, land)
		return _r(Outcome.IMPASSABLE, from)

	# Order matches GetVanillaCollision: solidity (bit OR directional) before
	# elevation, so a mismatch is only ever reported for an otherwise-enterable
	# cell (§1.7).
	# [M27E E1] Water first, and only while surfing. A surfable tile carries a
	# collision bit exactly so it stops you on foot, so the bit has to be
	# overridden here rather than tested and then forgiven below.
	var to_surfable := MetatileBehavior.is_surfable(_cells.behavior_at(to.x, to.y))
	if surfing and to_surfable:
		if _elevation_mismatch(elevation, to):
			return _r(Outcome.ELEVATION_MISMATCH, from)
		if _cells.entity_at(to.x, to.y):
			return _r(Outcome.OBJECT_EVENT, from)
		return _r(Outcome.NONE, to)
	if _cells.collision_at(to.x, to.y) != 0:
		return _r(Outcome.IMPASSABLE, from)
	if _directionally_impassable(from, to, dir):
		return _r(Outcome.IMPASSABLE, from)
	if _elevation_mismatch(elevation, to):
		return _r(Outcome.ELEVATION_MISMATCH, from)
	# [M27D D2] LAST, matching GetVanillaCollision's own precedence: range,
	# then terrain and directional, then elevation, THEN object events. The
	# order is visible rather than cosmetic — walking at an NPC standing on a
	# different stratum reports ELEVATION_MISMATCH, not OBJECT_EVENT, because
	# the elevation rule rejects the tile before anyone is asked who is on it.
	if _cells.entity_at(to.x, to.y):
		return _r(Outcome.OBJECT_EVENT, from)

	return _r(Outcome.NONE, to)


func _directionally_impassable(from: Vector2i, to: Vector2i, dir: int) -> bool:
	var here: int = _cells.behavior_at(from.x, from.y)
	var there: int = _cells.behavior_at(to.x, to.y)
	return (here in EXIT_BLOCKED[dir]) or (there in ENTRY_BLOCKED[dir])


## Ported from IsElevationMismatchAt: either side being a wildcard means
## compatible, otherwise they must be equal.
func _elevation_mismatch(from_elev: int, to: Vector2i) -> bool:
	if from_elev == ELEVATION_TRANSITION:
		return false
	var e: int = _cells.elevation_at(to.x, to.y)
	if e == ELEVATION_TRANSITION or e == ELEVATION_MULTI_LEVEL:
		return false
	return e != from_elev


static func _r(outcome: int, to: Vector2i) -> Dictionary:
	return {"outcome": outcome, "to": to}


# --- cell_info: the overlay's read seam (M27B Change 2) ----------------------
#
# §20 requires the overlay to read "the real cell_info() resolver". This is it,
# and it lives on StepResolver deliberately: the overlay holds a resolver and
# asks it, so there is one implementation of what a cell MEANS rather than a
# renderer that re-derives movement rules from raw arrays and drifts.
#
# Nothing here resolves anything new. Per-cell values are delegated to MapData;
# the movement semantics come from the SAME EXIT_BLOCKED / ENTRY_BLOCKED /
# LEDGE_FOR tables resolve() itself consumes. If those tables change, the
# overlay changes with them for free — which is the entire point.

## A behaviour value with no MB_* name. Measured: **zero** of the 83 behaviours
## present across all 421 imported maps are unnamed, so this can only ever flag
## a hand-painted cell whose behaviour was never set — which is exactly what
## §20's "bright magenta for untagged tiles" is for. Magenta on imported data
## means the importer or the constants table regressed.
static func is_untagged_behavior(beh: int) -> bool:
	return not MetatileBehavior.NAME_BY_ID.has(beh)


## Everything the overlay needs to draw one cell, in one call.
##
## Returns a Dictionary rather than a typed object to match this project's own
## convention for multi-value returns (resolve() above, BattleManager's result
## dicts). `in_bounds` is always present; every other key is only meaningful
## when it is true.
func cell_info(cell: Vector2i) -> Dictionary:
	# MapData specifically -- see `_cells`. A resolver built on a MapManager
	# steps fine but cannot answer this, and says so rather than half-answering.
	var _map: MapData = _cells as MapData
	if _map == null:
		return {"cell": cell, "in_bounds": false, "no_map_data": true}
	if not _map.in_bounds(cell.x, cell.y):
		return {"cell": cell, "in_bounds": false}

	var beh: int = _map.behavior_at(cell.x, cell.y)
	var elev: int = _map.elevation_at(cell.x, cell.y)

	# Derived from the resolver's own tables, not from a second opinion about
	# which behaviours block which way.
	var exits_blocked: Array[int] = []
	var entries_blocked: Array[int] = []
	for dir in [Dir.SOUTH, Dir.NORTH, Dir.WEST, Dir.EAST]:
		if beh in EXIT_BLOCKED[dir]:
			exits_blocked.append(dir)
		if beh in ENTRY_BLOCKED[dir]:
			entries_blocked.append(dir)

	var ledge_dir := -1
	for dir in LEDGE_FOR:
		if beh == LEDGE_FOR[dir]:
			ledge_dir = dir
			break

	var i := cell.y * _map.width + cell.x
	return {
		"cell": cell,
		"in_bounds": true,
		"metatile": _map.metatile_at(cell.x, cell.y),
		"behavior": beh,
		"behavior_name": MetatileBehavior.NAME_BY_ID.get(beh, ""),
		"untagged": is_untagged_behavior(beh),
		"collision": _map.collision_at(cell.x, cell.y),
		"elevation": elev,
		# 0 and 15 short-circuit every elevation comparison; 0 alone is 56% of
		# Kanto and means "unconstrained here", not "staircase" (§1.4).
		"elevation_wildcard": elev == ELEVATION_TRANSITION or elev == ELEVATION_MULTI_LEVEL,
		"layer_type": _map.layer_type_at(cell.x, cell.y),
		"priority": _map.priority_at(cell.x, cell.y),
		"exits_blocked": exits_blocked,
		"entries_blocked": entries_blocked,
		"ledge_dir": ledge_dir,
		"provenance": _map.provenance[i] if i < _map.provenance.size() else 0,
		"collision_explicit": _map.collision_is_explicit(cell.x, cell.y),
		"elevation_explicit": _map.elevation_is_explicit(cell.x, cell.y),
		"needs_review": _map.needs_review(cell.x, cell.y),
	}
