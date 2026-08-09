@tool
class_name MartStock
extends RefCounted

## [M27I I6a] What a shop sells.
##
## A mart's stock is DATA under an ordinary script label — `.2byte ITEM_*` runs
## terminated by `ITEM_NONE` — and `gen_map_scripts.py` used to drop every one
## of them, because they start with `.` like any other assembler directive.
##
## ⚠️ **THE FAILURE THAT MADE THIS TIER FIRST: THE LABEL STILL RESOLVED.** It
## compiled to the leftover `[release, end]` that follows the data in FRLG's own
## asm, so a consumer asking "does this list exist?" got yes, and only asking
## "what is in it?" revealed the loss. A shop built against that would have
## opened onto an empty shelf and read as a design decision.
##
## Two guards now stand in front of that, both at BUILD time, so this class can
## stay simple: every `pokemart` argument must name a non-empty list, and every
## item in a stocked list must resolve to a real id.

const PATH := "res://data/map_data_lists.json"

static var _lists: Dictionary = {}
static var _loaded := false


static func _load() -> Dictionary:
	if _loaded:
		return _lists
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("MartStock: %s is missing — run gen_map_scripts.py" % PATH)
		return _lists
	var j := JSON.new()
	var err := j.parse(f.get_as_text())
	f.close()
	if err != OK or typeof(j.data) != TYPE_DICTIONARY:
		push_error("MartStock: %s is malformed (line %d)" % [PATH, j.get_error_line()])
		return _lists
	_lists = j.data
	return _lists


## True when the label names a real, NON-EMPTY list.
##
## ⚠️ Empty and absent are deliberately the same answer. A shop with nothing in
## it is not a shop, and the distinction only matters to the build guard that
## already refuses it.
static func has_stock(label: String) -> bool:
	var l: Array = _load().get(label, [])
	return not l.is_empty()


## The stock as item ids, in shelf order.
##
## Names are resolved here rather than baked into the JSON so the sidecar stays
## greppable against source, matching how every other argument in
## `map_scripts.json` is stored. An unresolvable name is dropped and reported —
## it cannot normally happen, because the generator fails the build on one.
static func stock_for(label: String) -> Array[int]:
	var out: Array[int] = []
	for name in _load().get(label, []):
		var id := PokemonRegistry.item_id_of(str(name))
		if id > 0:
			out.append(id)
		else:
			push_warning("MartStock: %s stocks unknown item %s" % [label, name])
	return out


## Every label carrying a data list. Not a hot path — for the roster guard.
static func labels() -> Array:
	return _load().keys()


## The raw, UNRESOLVED entries for a label.
##
## ⚠️ Exists because `stock_for` cannot see a terminator that leaked into the
## data: `ITEM_NONE` resolves to id 0 and is dropped by the `id > 0` filter, so
## an assertion written against resolved ids passes whether or not the generator
## excluded it. Defence in depth is good; a guard that cannot fail is not.
static func raw_for(label: String) -> Array:
	return _load().get(label, [])
