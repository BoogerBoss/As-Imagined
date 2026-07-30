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
##
## A real index into that map's warp list, NOT derivable from position: a
## multi-tile doorway has several warps sharing one arrival slot. Oak's Lab
## exits from three tiles, all arriving at Pallet Town's warp 2.
@export var dest_warp_id: int = 0

## Does stepping here actually warp you?
##
## [M27C C5] This project DECOUPLES "a warp is here" from "this tile is a door".
## The reference gates on the tile's metatile behaviour, which means a warp
## placed on an ordinary tile silently never fires — the same invisible-failure
## shape §1.9 exists to prevent for collision, and a real trap once maps are
## hand-authored.
##
## So presence decides, and this flag carries imported fidelity instead:
## measured, 267 of 1294 warps in Kanto sit on tiles the reference fires nothing
## from. They are not arrival points either — they are the flanking tiles of
## multi-tile doorways, where exactly one tile carries the behaviour that
## triggers. Importing them as live would silently widen every doorway in the
## region.
##
## DEFAULTS TRUE, so a warp you place yourself works immediately. The importer
## is the only thing that ever sets it false, and it is a visible, editable
## property rather than a hidden coupling to a tile you might repaint later.
@export var triggers: bool = true


func _get_configuration_warnings() -> PackedStringArray:
	var out := super()
	if dest_map == "":
		out.append("No dest_map — this warp leads nowhere.")
	return out
