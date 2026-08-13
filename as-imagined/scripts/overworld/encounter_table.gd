@tool
class_name EncounterTable
extends Resource

## [M27T piece 5] One map's wild-encounter table for one field, authored by hand.
##
## ⚠️ **THIS IS THE AUTHORED LAYER, AND THE GENERATED CORPUS IS NOT IN IT.**
## `data/land_encounters.json` stays generated and is never hand-edited, so
## re-running `gen_wild_encounters.py` is always safe — which is why the
## converter needs no `--force` guard at all. A table here OVERRIDES the
## generated one for its map, or supplies the only one where the reference has
## none (Xanadu Nursery; or Saffron City, which has encounter tiles and no table
## in Fire Red).
##
## ⚠️ **THE COST OF TAKING OWNERSHIP IS THAT THE MAP STOPS RECEIVING CONVERTER
## FIXES**, deliberately and visibly — the override is a file you created. Same
## trade `field_script_source/` makes.
##
## ⚠️ **`.tres` HERE REOPENS D4b (`docs/m27m5_map_creator_scope.md:226-245`),
## WHICH CHOSE JSON — Rob, 2026-08-09.** Reopened by Rob, 2026-08-12, on new
## information that decision did not have: in-Godot editing is now a
## requirement, and Godot gives free undo, dirty-tracking and property
## interception only for Resources. The generated corpus stays JSON, so the
## project's two-layer rule (full dataset in JSON, the authored subset in `.tres`)
## is honoured rather than reversed.
##
## Scope of record: `docs/m27t_encounter_authoring_scope.md` §4.


## Which encounter kind this table feeds. Land is the only one with a runtime
## consumer; water and fishing are M27E.
##
## ⚠️ Stored on the resource as well as encoded in the filename so a renamed or
## copied file still says what it is, and so the suite can check the two agree —
## a file whose name and contents disagree is worse than either being wrong.
enum Field { LAND, WATER, ROCK_SMASH, FISHING }

const FIELD_SUFFIX := {
	Field.LAND: "land",
	Field.WATER: "water",
	Field.ROCK_SMASH: "rock_smash",
	Field.FISHING: "fishing",
}

## ⚠️ **THE MAP THIS BELONGS TO, BY NAME, AND THE RENAME HAZARD IS REAL.** An
## authored map is exactly the kind that gets renamed, and a name-keyed table
## detaches SILENTLY when it does — the grass simply stops working with nothing
## pointing at the cause. `WildEncounters.unresolved_authored_maps()` is the
## guard that turns that into a named failure, and it is why this is stored
## rather than inferred from the filename alone.
@export var map_name: String = "":
	set(value):
		map_name = value
		emit_changed()

@export var field: Field = Field.LAND:
	set(value):
		field = value
		emit_changed()

## The table's own odds of firing, before the ×16 and the ability modifiers.
## Source's own values run 1–25; the roll clamps anyway, so this only has to
## refuse the nonsense.
@export_range(0, 100) var encounter_rate: int = 0:
	set(value):
		encounter_rate = clampi(value, 0, 100)
		emit_changed()

@export var slots: Array[EncounterSlot] = []:
	set(value):
		slots = value
		emit_changed()


## ⚠️ **`expected_slots` IS A PARAMETER RATHER THAN READ FROM `WildEncounters`,
## AND THAT IS DELIBERATE.** `WildEncounters` has to reference this class to load
## the layer at all; having this one reference back would make a `class_name`
## cycle, which Godot 4 resolves badly and intermittently. The caller already
## knows the count — it is `slot_rates().size()` — so passing it costs nothing
## and keeps the dependency one-way.
func is_complete(expected_slots: int) -> bool:
	if map_name == "" or encounter_rate <= 0:
		return false
	if slots.size() != expected_slots:
		return false
	for s in slots:
		if s == null or not s.is_valid():
			return false
	return true


## Why this table is not usable yet, for a human. Empty when it is fine.
##
## Separate from `is_complete` because the two have different jobs: the boolean
## gates the roll, and this explains the gate at the point of authoring. A table
## that silently does nothing is the failure this whole layer is meant to avoid.
func incomplete_reason(expected_slots: int) -> String:
	if map_name == "":
		return "no map assigned"
	if encounter_rate <= 0:
		return "encounter rate is 0 — nothing would ever spawn"
	if slots.size() != expected_slots:
		return "%d slots, needs %d" % [slots.size(), expected_slots]
	var unset := 0
	var bad := 0
	for s in slots:
		if s == null or s.dex <= 0:
			unset += 1
		elif not s.is_valid():
			bad += 1
	if unset > 0:
		return "%d slot(s) have no species yet" % unset
	if bad > 0:
		return "%d slot(s) have an impossible level band" % bad
	return ""


## ⚠️ **THE SEAM THAT KEPT PIECE 5 FROM TOUCHING ANYTHING DOWNSTREAM.** The
## generated layer is a `Dictionary` of `{encounter_rate, slots:[{dex,min,max}]}`
## and every consumer — `should_encounter`, `build_wild_party`, the tests — reads
## that shape. Meeting it here means the storage change is invisible past
## `table_for()`, rather than rippling into the roll.
func to_runtime() -> Dictionary:
	var out: Array = []
	for s in slots:
		out.append(s.to_runtime())
	return {"encounter_rate": encounter_rate, "slots": out}


## The filename this table belongs in, by convention: `<Map>_<field>.tres`.
func expected_basename() -> String:
	return "%s_%s" % [map_name, FIELD_SUFFIX.get(field, "land")]
