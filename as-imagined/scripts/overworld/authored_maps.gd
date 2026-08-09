@tool
class_name AuthoredMaps
extends RefCounted

## [M27M5] Maps this project AUTHORED, which the reference has never heard of.
##
## ⚠️ **HAND-OWNED. THIS FILE IS NOT GENERATED AND MUST NEVER BECOME SO.**
## `map_constants.gd` beside it is generated from the reference's own 939
## `map.json` files and is stamped "do not edit by hand" — so an authored map
## added there would be erased by the next `gen_map_import.py` run, silently,
## exactly as `metatile_behavior.gd` lost 60 hand-added lines once already.
## Two files, two owners, and the generated one now falls back to this one.
##
## ## Why a constant at all, rather than just the map name
##
## Because `MapData.connections` and `Warp.dest_map` both store a `MAP_*`
## constant, and every consumer resolves through `MapConstants`. An authored map
## that could not be named that way could not be connected or warped to at
## all — measured before building this: `MapConstants.is_baked()` answers false
## for any name the reference does not define, so `loadable_connections()`
## silently DROPS the edge and the neighbour simply never loads. No error, no
## warning; the map is just never there.
##
## ## The naming rule: `MAP_AUTHORED_<NAME>`
##
## Mirrors the `FLAG_AUTHORED_<MAP>_<THING>` convention Rob settled for flags
## (M27Q Q4), and for the same reason: a prefix makes a collision with the
## reference structurally impossible rather than merely unlikely. Verified —
## **zero of the reference's 939 map constants begin `MAP_AUTHORED_`**, so this
## namespace is clean by measurement, not by hope.
##
## The value is the map name, which is BOTH the baked scene's filename and
## `MapData.map_name` — the same contract `MapConstants.NAME_BY_CONSTANT` has,
## so callers cannot tell the two tables apart and nothing downstream needs to
## know which half a map came from.
const NAME_BY_CONSTANT := {
	"MAP_AUTHORED_XANADU_NURSERY": "XanaduNursery",
}


## Map name for an authored constant, or "" — same shape as
## `MapConstants.map_name_for`, which delegates here on a miss.
static func map_name_for(map_constant: String) -> String:
	return NAME_BY_CONSTANT.get(map_constant, "")


## True when the constant is one of ours. Kept separate from a non-empty
## `map_name_for` so callers can distinguish "authored map, not yet baked" from
## "not an authored map at all" — the same distinction `MapConstants` draws
## between an unknown constant (a pipeline bug) and a known-but-unbaked one (an
## expected gap).
static func has_constant(map_constant: String) -> bool:
	return NAME_BY_CONSTANT.has(map_constant)
