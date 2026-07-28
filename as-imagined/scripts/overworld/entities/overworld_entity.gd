@tool
class_name OverworldEntity
extends Node2D

## [M27B/M27D] Base class for every placed map event.
##
## The four `map.json` event arrays become six node types over this base
## (docs/overworld_scope.md §32): object_events split three ways by their own
## fields into NPC / TrainerNPC / ItemBall, warp_events into Warp, coord_events
## into Trigger, bg_events into Sign.
##
## The PLACED INSTANCE is the source of truth for spawn data — position,
## elevation, which flag hides it, which script it runs. Identity that outlives
## a placement (a trainer's party, class, name) stays in its own registry and is
## referenced by key.

const CELL := 16

## Tile coordinate, not pixels. `position` is derived from it so a hand-placed
## entity in the editor still snaps to the grid the step resolver walks.
@export var cell: Vector2i = Vector2i.ZERO:
	set(value):
		cell = value
		position = Vector2(value) * CELL
		update_configuration_warnings()

## Per-CELL elevation, same 0–15 space as MapData. Drives draw priority via
## MetatileBehavior.ELEVATION_TO_PRIORITY, which is why entities live in two
## containers rather than one Y-sorted pile (§1.6).
@export var elevation: int = 3

## Visibility flag from the source event (e.g. FLAG_HIDE_VIRIDIAN_CITY_POTION).
## Empty means always present. Nothing consumes this until the flag store lands
## in M27G — carried now because it is placement data and would otherwise have
## to be re-imported later.
@export var visibility_flag: String = ""

## Label of the script this event runs, indexed out of the reference's own
## data/**/*.inc tree at import time. Routing it is M27G's job; until then it is
## a recorded pointer, not a live call.
@export var script_label: String = ""


## Entity draw priority for this entity's own elevation. Lower draws on top.
func priority() -> int:
	if elevation < 0 or elevation > 15:
		return 2
	return MetatileBehavior.ELEVATION_TO_PRIORITY[elevation]


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	if elevation < 0 or elevation > 15:
		out.append("elevation %d is outside the 0-15 range the source uses." % elevation)
	return out
