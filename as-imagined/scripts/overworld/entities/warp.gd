@tool
class_name Warp
extends OverworldEntity

## [M27B/M27C] A tile that moves the player to another map.
##
## Destinations are stored as source's own MAP_* constant plus the destination
## map's own warp index — resolving that pair into a live scene is M27C's job,
## alongside stitching and connections.

## This warp's OWN index in its map's warp list — what other maps address.
##
## [M27C C5] A `dest_warp_id` is positional, so arriving anywhere correct
## depends on every consumer agreeing on the ordering. Storing the index makes
## that agreement data instead of an assumption: without it the baker emitting
## nodes in array order is load-bearing and unasserted, and any reorder sends
## every arrival in the region to the wrong tile while looking like a content
## bug rather than a pipeline one.
##
## DEFAULTS -1, meaning "not addressable as a destination". A hand-placed warp
## is a valid exit immediately but is not something another map can name until
## it is given a real index — so a lookup that finds nothing fails loudly
## rather than landing the player on whichever warp happened to be first.
@export var warp_id: int = -1

## Source's own MAP_* constant (e.g. MAP_VIRIDIAN_CITY_POKEMON_CENTER_1F).
@export var dest_map: String = ""

## Index of the warp on the DESTINATION map that the player emerges from.
##
## A real index into that map's warp list, NOT derivable from position: a
## multi-tile doorway has several warps sharing one arrival slot. Oak's Lab
## exits from three tiles, all arriving at Pallet Town's warp 2.
@export var dest_warp_id: int = 0

## If this warp is an ARROW warp, the direction you must press while standing
## on it. -1 when it is not one.
##
## [M27C C5-4] A third trigger geometry, and the one that gets you out of nearly
## every building: `TryArrowWarp` reads the player's OWN tile on a held
## direction, BEFORE any step is attempted, so it fires whether or not the
## target cell is walkable — which is the point, since an interior exit faces
## the map's bottom wall.
##
## Stamped rather than derived. "The one blocked neighbour is the exit" was
## measured against all 421 maps and does not hold: 64 of 345 arrow warps have
## zero or several blocked neighbours, so the guess would fire the wrong way on
## nearly a fifth of them.
##
## Values are StepResolver.Dir (SOUTH 0, NORTH 1, WEST 2, EAST 3).
@export var arrow_dir: int = -1

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
