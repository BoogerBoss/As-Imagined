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

var _map: MapData
var no_collision: bool = false  ## §20 debug toggle; mirrors OW_FLAG_NO_COLLISION


func _init(map: MapData) -> void:
	_map = map


## Resolve one step. Returns { outcome, to, ledge_to }.
## `to` is the cell actually landed on; for a ledge that is TWO tiles away.
func resolve(from: Vector2i, dir: int, elevation: int) -> Dictionary:
	var delta: Vector2i = STEP[dir]
	var to: Vector2i = from + delta

	if no_collision:
		return _r(Outcome.NONE, to)

	if not _map.in_bounds(to.x, to.y):
		return _r(Outcome.OUTSIDE_RANGE, from)

	# Ledge is checked BEFORE impassability: a ledge tile is solid to walk
	# onto but jumpable in its own direction, so it must not be rejected by
	# the collision bit first.
	if _map.behavior_at(to.x, to.y) == LEDGE_FOR[dir]:
		var land: Vector2i = to + delta
		if _map.in_bounds(land.x, land.y):
			return _r(Outcome.LEDGE_JUMP, land)
		return _r(Outcome.IMPASSABLE, from)

	# Order matches GetVanillaCollision: solidity (bit OR directional) before
	# elevation, so a mismatch is only ever reported for an otherwise-enterable
	# cell (§1.7).
	if _map.collision_at(to.x, to.y) != 0:
		return _r(Outcome.IMPASSABLE, from)
	if _directionally_impassable(from, to, dir):
		return _r(Outcome.IMPASSABLE, from)
	if _elevation_mismatch(elevation, to):
		return _r(Outcome.ELEVATION_MISMATCH, from)

	return _r(Outcome.NONE, to)


func _directionally_impassable(from: Vector2i, to: Vector2i, dir: int) -> bool:
	var here: int = _map.behavior_at(from.x, from.y)
	var there: int = _map.behavior_at(to.x, to.y)
	return (here in EXIT_BLOCKED[dir]) or (there in ENTRY_BLOCKED[dir])


## Ported from IsElevationMismatchAt: either side being a wildcard means
## compatible, otherwise they must be equal.
func _elevation_mismatch(from_elev: int, to: Vector2i) -> bool:
	if from_elev == ELEVATION_TRANSITION:
		return false
	var e: int = _map.elevation_at(to.x, to.y)
	if e == ELEVATION_TRANSITION or e == ELEVATION_MULTI_LEVEL:
		return false
	return e != from_elev


static func _r(outcome: int, to: Vector2i) -> Dictionary:
	return {"outcome": outcome, "to": to}
