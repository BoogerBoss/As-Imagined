class_name RespawnPoint
extends RefCounted

## [M27O O1] Where the player wakes up after a whiteout.
##
## Source stores this as a `WarpData` in the save block (`lastHealLocation`,
## `global.h:1100` — its own comment reads "used by white-out and teleport") and
## `setrespawn` writes it via `SetLastHealLocationWarp`. Here it is the heal
## location's own ID plus a lookup, which is the same information in the form
## this project already moves maps around by.
##
## ⚠️ **THE HEAL POINT AND THE RESPAWN POINT ARE DIFFERENT PLACES.** A heal
## location's `map`/`x`/`y` is the outdoor tile the Pokémon Centre stands on —
## what Teleport and "fly here" use. Its `respawn_map` is INSIDE: the Centre, or
## for Pallet the player's own house. Source keeps two tables for this
## (`sHealLocations` and `sWhiteoutRespawnHealCenterMapIdxs`). Collapsing them
## drops the player outdoors after a whiteout instead of in front of a nurse.

const TABLE_PATH := "res://data/heal_locations.json"

## ⚠️ A STAND-IN FOR A NEW-GAME SCRIPT THAT DOES NOT EXIST YET.
##
## Source sets the first respawn from the opening sequence; M27K owns that. In
## the meantime this resolves from whatever map the overworld is configured to
## start in — so moving `start_map` for a playtest moves the respawn with it
## rather than stranding a Pewter-based session back in Pallet. If the start map
## has no heal location of its own, it falls back to the story's own first one.
const STORY_DEFAULT := "HEAL_LOCATION_PALLET_TOWN"

static var _table: Dictionary = {}

## The heal-location ID currently set, e.g. "HEAL_LOCATION_PEWTER_CITY".
var current: String = ""


static func _load() -> Dictionary:
	if not _table.is_empty():
		return _table
	var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if f == null:
		return _table
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_table = parsed
	return _table


## Every known heal-location ID.
static func ids() -> Array:
	return _load().keys()


## Is this a heal location the table knows?
static func is_known(heal_id: String) -> bool:
	return _load().has(heal_id)


## The record for a heal location, or {} if unknown.
static func entry(heal_id: String) -> Dictionary:
	return _load().get(heal_id, {})


## The heal location whose OUTDOOR point is on this map, or "" if none is.
##
## Used to pick a sensible starting respawn: the map you begin on is the one you
## would have been sent to.
static func for_map(map_name: String) -> String:
	for id in _load():
		if str(_load()[id].get("map", "")) == map_name:
			return id
	return ""


## Set the respawn, refusing an ID the table does not know.
##
## Refusing rather than storing is deliberate: an unknown ID stored now becomes
## an unresolvable warp destination at whiteout time, which is the worst moment
## to discover it — the player is already fainted and has nowhere to go.
func set_to(heal_id: String) -> bool:
	if not is_known(heal_id):
		return false
	current = heal_id
	return true


## Choose a starting respawn for a session that has not had one set.
func default_for(start_map: String) -> void:
	var here := for_map(start_map)
	current = here if here != "" else STORY_DEFAULT


## Where a whiteout should put the player: `{map, cell}`, or {} if unresolvable.
func respawn_warp() -> Dictionary:
	var e := entry(current)
	if e.is_empty():
		return {}
	return {
		"map": str(e.get("respawn_map", "")),
		"cell": Vector2i(int(e.get("respawn_x", 0)), int(e.get("respawn_y", 0))),
	}


## The OUTDOOR heal point, which is a different place — kept for whatever uses
## Teleport or a fly destination later, so nobody re-derives the distinction.
func heal_warp() -> Dictionary:
	var e := entry(current)
	if e.is_empty():
		return {}
	return {
		"map": str(e.get("map", "")),
		"cell": Vector2i(int(e.get("x", 0)), int(e.get("y", 0))),
	}


func to_save() -> Dictionary:
	return {"current": current}


func from_save(data: Dictionary) -> void:
	current = str(data.get("current", ""))
