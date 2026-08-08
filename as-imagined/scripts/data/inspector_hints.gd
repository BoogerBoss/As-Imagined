@tool
class_name InspectorHints
extends RefCounted

## [M27Q Q2 follow-up] `Name:value` hint strings, so id fields show names.
##
## ⚠️ **ITS OWN CLASS SO `TrainerData` AND `TrainerPartyMon` CAN SHARE ONE
## BUILDER.** Both need the item list — `battle_items` on the trainer,
## `held_item_id` on each party mon — and the alternative was either a
## `TrainerPartyMon -> TrainerData` reference (a cycle, on top of the
## `TrainerData -> TrainerPartyMon` one the typed `party` array already
## creates) or a second copy of the scan. A second copy is the drift shape that
## cost 80 trainers their CHECK_VIABILITY; the cycle is avoidable for free.
##
## ⚠️ **THE VALUE AFTER THE COLON IS THE STORED INT, NEVER A DROPDOWN INDEX.**
## A positional enum would store 0,1,2… and silently reinterpret every existing
## `.tres` the moment an entry was inserted in the middle.
##
## ⚠️ **CACHED FOR THE SESSION, AND THE CACHE MUST BE CLEARED WHEN FILES
## CHANGE.** The Inspector re-queries a property list often and these strings
## run to kilobytes, so rebuilding per call is the sort of thing that became a
## five-second stall once already. `clear_caches()` is wired to
## `EditorFileSystem.filesystem_changed` by the plugin — without that, a
## trainer class or item added mid-session would not appear until Godot
## restarted.

static var _item_cache := ""
static var _class_cache := ""
static var _nature_cache := ""


## Called on `filesystem_changed`. Cheap: the next query rebuilds lazily.
static func clear_caches() -> void:
	_item_cache = ""
	_class_cache = ""
	_nature_cache = ""


## ⚠️ **EVERY CLASS IS LISTED, INCLUDING UNNAMED ONES, AND THAT PREVENTS DATA
## LOSS RATHER THAN BEING TIDY.** Measured across all 1,477 trainers: 11 of the
## 117 converted classes carry no `class_name_text` at all (ids 0, 1, 4, 50,
## 52, 65, 106, 107, 110, 111, 116 — the `.tres` holds only an id), and 7 of
## those are in real use. A dropdown offering no entry for a trainer's current
## value renders BLANK, and the first click overwrites a real class id with an
## unrelated one. `Class N (unnamed)` keeps the value selectable and makes the
## gap visible. The missing names are a data gap in `gen_trainer_data.py`'s
## class table — flagged, not fixed here.
static func class_hint() -> String:
	if _class_cache != "":
		return _class_cache
	var rows := {}
	var dir := DirAccess.open("res://data/trainer_classes")
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var c: TrainerClassData = ResourceLoader.load(
					"res://data/trainer_classes/" + f)
			if c == null:
				continue
			rows[c.trainer_class_id] = c.class_name_text if c.class_name_text != "" \
					else "Class %d (unnamed)" % c.trainer_class_id
	_class_cache = rows_to_hint(rows)
	return _class_cache


## ⚠️ `0` IS "NO ITEM" HERE, AND THAT IS NOT UNIVERSAL — see `ability_id`,
## where 0 is a real `ability_0000.tres` named "None" that actually means "use
## the species default". Item ids start at 1 and there is no `item_0000.tres`,
## so "None" is literally correct for this field and misleading for that one.
static func item_hint() -> String:
	if _item_cache != "":
		return _item_cache
	var rows := {0: "None"}
	var dir := DirAccess.open("res://data/items")
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var it: ItemData = ResourceLoader.load("res://data/items/" + f)
			if it != null and it.item_name != "":
				rows[f.trim_prefix("item_").trim_suffix(".tres").to_int()] = it.item_name
	_item_cache = rows_to_hint(rows)
	return _item_cache


## Driven off `BattlePokemon.NATURE_NAMES`, which already exists and is already
## the single source for nature naming — not a second table beside it.
static func nature_hint() -> String:
	if _nature_cache != "":
		return _nature_cache
	var rows := {}
	for i in BattlePokemon.NATURE_NAMES.size():
		rows[i] = BattlePokemon.NATURE_NAMES[i]
	_nature_cache = rows_to_hint(rows)
	return _nature_cache


## ⚠️ **TWO GENDER HINTS, BECAUSE -1 MEANS DIFFERENT THINGS ON THE TWO
## RESOURCES.** On a party mon it means "roll from the species' own
## gender_ratio"; on the trainer themself it means "unspecified / not
## applicable". Same number, different behaviour, so one shared label would be
## wrong on one of them — and `-1` is the single most opaque value in either
## resource when shown as a bare int.
static func mon_gender_hint() -> String:
	return "Roll from species ratio:-1,Male:%d,Female:%d,Genderless:%d" % [
		BattlePokemon.GENDER_MALE, BattlePokemon.GENDER_FEMALE,
		BattlePokemon.GENDER_GENDERLESS]


static func trainer_gender_hint() -> String:
	return "Unspecified:-1,Male:%d,Female:%d" % [
		BattlePokemon.GENDER_MALE, BattlePokemon.GENDER_FEMALE]


## ⚠️ A comma or colon inside a name would split the hint and silently shift
## every entry after it. No current name contains either; the guard is for the
## one that eventually does.
static func rows_to_hint(rows: Dictionary) -> String:
	var ids := rows.keys()
	ids.sort()
	var parts := PackedStringArray()
	for i in ids:
		parts.append("%s:%d" % [str(rows[i]).replace(",", " ").replace(":", " "), i])
	return ",".join(parts)
