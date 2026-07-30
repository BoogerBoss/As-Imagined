@tool
class_name ItemBall
extends OverworldEntity

## [M27B/M27D] A pickup lying on the ground.
##
## Discriminated out of source's `object_events` array by its graphics id
## (OBJ_EVENT_GFX_ITEM_BALL). The item itself is named inside the script body
## rather than the placement, so `visibility_flag` — which source sets once the
## ball is taken — is what actually makes a pickup one-shot.

@export var graphics_id: String = "OBJ_EVENT_GFX_ITEM_BALL"

@export var local_id: String = ""


func sprite_graphics_id() -> String:
	return graphics_id
