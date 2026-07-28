@tool
class_name Sign
extends OverworldEntity

## [M27B/M27D] Something you read by facing it and pressing A.
##
## Source's `bg_events` — a family wider than the name suggests: plain signposts,
## but also hidden items, and secret-base entrances. `bg_type` is what tells them
## apart, so it is imported rather than assumed to be a signpost every time.

## Normalised kind: "sign", "hidden_item", or "secret_base".
@export var bg_type: String = "sign"

## Which way the player must face to interact, from source's own
## BG_EVENT_PLAYER_FACING_* constants. ANY means it reads from any direction.
@export var facing: String = "BG_EVENT_PLAYER_FACING_ANY"

## Hidden items only — source's own ITEM_* constant. Empty for a plain sign.
@export var item: String = ""


func _get_configuration_warnings() -> PackedStringArray:
	var out := super()
	if bg_type == "sign" and script_label == "":
		out.append("A sign with no script has nothing to say.")
	if bg_type == "hidden_item" and item == "":
		out.append("A hidden item with no item constant yields nothing.")
	return out
