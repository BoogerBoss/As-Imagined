@tool
class_name NPC
extends OverworldEntity

## [M27B/M27D] A plain overworld person — talks, wanders, blocks a tile.
##
## This is the residual case of source's `object_events` array: an object event
## that is neither a trainer (trainer_type TRAINER_TYPE_NORMAL) nor an item ball
## (an ITEM_BALL graphics id) lands here.

## Source's own OBJ_EVENT_GFX_* constant. This is PLACEMENT data, not identity
## data — the same character can be placed with different graphics, and a
## trainer's registry entry carries only its battle front pic, never this.
@export var graphics_id: String = "OBJ_EVENT_GFX_NONE"

## Source's own MOVEMENT_TYPE_* constant (LOOK_AROUND, WANDER_UP_AND_DOWN,
## FACE_DOWN, ...). Movement itself is M27D's job; the type is imported now so
## the behaviour does not have to be re-derived per NPC later.
@export var movement_type: String = "MOVEMENT_TYPE_NONE"

## Source's own per-map local id, used by its scripts to address this object
## (applymovement, etc.). Blank when the map declares none.
@export var local_id: String = ""
