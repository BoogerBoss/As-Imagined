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


## `movement_type` is a free-text String, and retyping it in the inspector is
## the fastest way to turn a rotating trainer into a fixed-facing one. That
## makes a typo cheap to introduce and, without this, invisible: MapOverlay's
## events mode draws sight lines off this string, so a misspelling silently
## removes the trainer's ray, which looks identical to a trainer who correctly
## has none. Checked against the generated set rather than a hand-kept list.
func _get_configuration_warnings() -> PackedStringArray:
	var out := super()
	if movement_type != "" and not MovementTypes.is_known(movement_type):
		out.append("movement_type '%s' is not a type source defines — typo?"
				% movement_type)
	return out


func sprite_graphics_id() -> String:
	return graphics_id


## MOVEMENT_TYPE_FACE_* names the direction outright; everything else rests
## facing south, matching source's own ANIM_STD_FACE_SOUTH default.
##
## The FACE_x_AND_y and WANDER types start on their first direction and change
## later — that is D3's job, not a starting-facing question.
func initial_facing() -> String:
	for d in ["DOWN", "UP", "LEFT", "RIGHT"]:
		if movement_type.begins_with("MOVEMENT_TYPE_FACE_" + d):
			return {"DOWN": "SOUTH", "UP": "NORTH", "LEFT": "WEST", "RIGHT": "EAST"}[d]
	return "SOUTH"
