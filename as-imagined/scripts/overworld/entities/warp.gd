@tool
class_name Warp
extends OverworldEntity

## [M27B/M27C] A tile that moves the player to another map.
##
## Destinations are stored as source's own MAP_* constant plus the destination
## map's own warp index — resolving that pair into a live scene is M27C's job,
## alongside stitching and connections.

## Source's own MAP_* constant (e.g. MAP_VIRIDIAN_CITY_POKEMON_CENTER_1F).
@export var dest_map: String = ""

## Index of the warp on the DESTINATION map that the player emerges from.
@export var dest_warp_id: int = 0


func _get_configuration_warnings() -> PackedStringArray:
	var out := super()
	if dest_map == "":
		out.append("No dest_map — this warp leads nowhere.")
	return out
