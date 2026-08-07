class_name ObjectEventState
extends RefCounted

## [M27G G9] Script-driven changes to placed entities, persisted.
##
## ⚠️ **THE GAP THIS CLOSES: `setobjectxyperm` / `setobjectmovementtype` /
## `turnobject` MUTATED NODES THAT ARE FREED ON EVERY WARP.** A cutscene that
## parks an NPC somewhere new — which is the whole purpose of `setobjectxyperm`,
## the "perm" being permanent — worked until the player left the room and came
## back, at which point the baked scene supplied the original position again.
## Nothing was saved and nothing was even remembered within a session.
##
## Source keeps a mutable copy of every map's object-event templates in the
## save block (`gSaveBlock1Ptr->objectEventTemplates`) for exactly this. This is
## that, keyed by this project's own identifiers.
##
## ⚠️ **KEYED BY MAP + `local_id`, NOT BY NODE.** The node is the thing that
## dies; `local_id` is what the script named in the first place and what
## `find_entity_by_local_id` already resolves. A per-node key would be a second
## identity that cannot survive the teardown it exists to survive.
##
## ⚠️ **VISIBILITY IS DELIBERATELY NOT HERE.** `addobject`/`removeobject` toggle
## the entity's own `visibility_flag`, which is a FLAG and therefore already in
## the save. Recording it twice would be two sources of truth for one fact —
## the duplication `ScriptVM.removed_objects` already flirts with.


## "map|local_id" -> {"cell": Vector2i, "facing": int, "movement_type": String}
## Only the fields a script actually changed are present.
static var _overrides: Dictionary = {}


static func _key(map_name: String, local_id: String) -> String:
	return "%s|%s" % [map_name, local_id]


static func record(map_name: String, local_id: String, field: String, value: Variant) -> void:
	if map_name == "" or local_id == "":
		return
	var k := _key(map_name, local_id)
	if not _overrides.has(k):
		_overrides[k] = {}
	(_overrides[k] as Dictionary)[field] = value


## Everything recorded for one entity, or empty. Applied by the map loader.
static func overrides_for(map_name: String, local_id: String) -> Dictionary:
	return _overrides.get(_key(map_name, local_id), {})


static func has_any() -> bool:
	return not _overrides.is_empty()


## ⚠️ Vector2i does not survive JSON — the same reason `SaveManager` stores the
## player's cell as two ints rather than a stringified "(45, 21)".
static func to_save() -> Dictionary:
	var out := {}
	for k in _overrides:
		var row: Dictionary = _overrides[k]
		var flat := {}
		for f in row:
			if f == "cell":
				var c: Vector2i = row[f]
				flat["x"] = c.x
				flat["y"] = c.y
			else:
				flat[f] = row[f]
		out[k] = flat
	return out


## ⚠️ COERCES rather than trusting, like `FlagStore.from_save` — a save file can
## be hand-edited, and an override holding a String cell would surface as a
## crash the next time the player walked into that room.
static func from_save(data: Dictionary) -> void:
	_overrides = {}
	for k in data:
		var row = data[k]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var out := {}
		if row.has("x") and row.has("y"):
			out["cell"] = Vector2i(int(row["x"]), int(row["y"]))
		if row.has("facing"):
			out["facing"] = int(row["facing"])
		if row.has("movement_type"):
			out["movement_type"] = str(row["movement_type"])
		if not out.is_empty():
			_overrides[str(k)] = out


static func clear() -> void:
	_overrides.clear()
