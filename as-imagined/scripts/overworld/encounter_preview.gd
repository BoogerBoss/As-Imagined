class_name EncounterPreview
extends RefCounted

## [M27T piece 6] Everything the encounter Inspector panel DECIDES.
##
## ⚠️ **THIS EXISTS SO `encounter_inspector.gd` CAN CONTAIN NO RULES**, which is
## this addon's own standing split, written at the top of `plugin.gd` and
## restated in `entity_inspector.gd`: the editor surface is the one place in
## this project with no automated coverage and has already shipped three
## defects, so anything with a decision in it lives on this side, where
## `m27h_wild_encounters_test` drives it directly. The panel only turns these
## Dictionaries into Controls.
##
## ⚠️ **THE SPECIES TABLE COMES FROM `TrainerData.species_names()`, NOT FROM
## `PokemonRegistry`, AND THAT IS A TRAP THIS PROJECT ALREADY PAID FOR.**
## `PokemonRegistry` is an autoload whose script is not `@tool`, so it does not
## execute in the editor at all and every species would render as a bare number
## — the exact defect `trainer_data.gd`'s own comment records hitting on its
## first cut. Reading the shared JSON-backed table works identically in the
## editor and at runtime, which is the property a panel needs.


## Where a table for this map and field belongs, by convention.
static func table_path(map_name: String, field: int = EncounterTable.Field.LAND) -> String:
	return "%s%s_%s.tres" % [WildEncounters.AUTHORED_DIR, map_name,
			EncounterTable.FIELD_SUFFIX.get(field, "land")]


## ⚠️ **THE MAP NAME COMES FROM THE SCENE FILENAME, NOT THROUGH `MapConstants`
## — a deliberate departure from this block's own scoping, which leaned the
## other way.** That lean was right for a caller starting from a `MAP_*`
## constant, where the table can distinguish "the importer emitted a
## destination source does not define" from "defined but not baked". This panel
## starts from an OPEN SCENE, and `scenes/maps/<Map>.tscn` -> `<Map>` IS the key
## `land_encounters.json` is written with, so routing through a constant table
## would add an indirection that can only introduce a mismatch, never detect
## one. Same convention `plugin._on_overlay_toggled` already uses to find a
## map's `_data.tres`.
static func map_name_of(scene_path: String) -> String:
	if not scene_path.begins_with("res://scenes/maps/"):
		return ""
	return scene_path.get_file().trim_suffix(".tscn")


## What this map spawns, ready to render.
##
## `source` is `"authored"` / `"generated"` / `"none"` — and the three are
## genuinely different states rather than a presence flag: an authored table is
## editable here, a generated one has to be taken ownership of first, and
## neither is the same as a map that simply has no encounters.
static func digest_for(map_name: String) -> Dictionary:
	var out := {
		"map_name": map_name,
		"source": "none",
		"encounter_rate": 0,
		"slots": [],
	}
	if map_name == "" or not WildEncounters.has_table(map_name):
		return out
	out["source"] = "authored" if map_name in WildEncounters.authored_map_names() \
			else "generated"
	var t: Dictionary = WildEncounters.table_for(map_name)
	out["encounter_rate"] = int(t.get("encounter_rate", 0))
	var rates := WildEncounters.slot_rates()
	var rows: Array = []
	var i := 0
	for s in t.get("slots", []):
		var slot: Dictionary = s
		var dex := int(slot.get("dex", 0))
		rows.append({
			"index": i,
			"dex": dex,
			"name": species_label(dex),
			"min": int(slot.get("min", 0)),
			"max": int(slot.get("max", 0)),
			# Read from the field's own rate table rather than stored — a
			# derived number kept alongside the data is a number that goes
			# stale the first time the curve is retuned.
			"percent": int(rates[i]) if i < rates.size() else 0,
		})
		i += 1
	out["slots"] = rows
	return out


## ⚠️ **AT FIRE RED'S 1600 DENOMINATOR THE RATE IS LITERALLY THE PERCENTAGE PER
## STEP** — `rate * 16 / 1600 == rate / 100` — so the number an author drags is
## directly the thing they are choosing. That was not true before `[M27T piece
## 1]`, when the same value meant `rate / 1.8` and told you nothing without
## arithmetic. Computed rather than hardcoded so it stays honest if the
## denominator is ever revisited.
static func rate_percent_per_step(encounter_rate: int) -> float:
	if WildEncounters.MAX_ENCOUNTER_RATE <= 0:
		return 0.0
	return 100.0 * float(encounter_rate * WildEncounters.RATE_SCALE) \
			/ float(WildEncounters.MAX_ENCOUNTER_RATE)


## The two-way disagreement between a map's TILES and its TABLE, as a line to
## show, or `""` when they agree.
##
## ⚠️ **BOTH DIRECTIONS ARE REPORTED AND NEITHER IS AN ERROR.** A map with
## encounter tiles and no table is source's own normal way of saying "nothing
## spawns here" — measured at **38 real Kanto maps** — so this is a notice at
## the point of authoring, not a defect. It earns its place because the
## authoring order is paint the tiles, THEN create the table, and the halfway
## state is invisible otherwise: a table with no tiles never fires, and a
## painted patch with no table looks finished.
static func mismatch_for(map_name: String, md: MapData) -> String:
	if md == null or map_name == "":
		return ""
	var cells := 0
	for y in range(md.height):
		for x in range(md.width):
			if WildEncounters.resolve_encounter_type(md, x, y) \
					== MapManager.EncounterType.LAND:
				cells += 1
	var has := WildEncounters.has_table(map_name)
	if cells > 0 and not has:
		return "%d cell(s) here can host a land encounter, but this map has no table — nothing will spawn." % cells
	if cells == 0 and has:
		return "This map has a land table, but no cell can host a land encounter — it will never fire."
	return ""


## `"025 Pikachu"`, or a visibly unresolved label rather than a silent blank.
##
## ⚠️ **AN UNKNOWN DEX MUST READ AS UNRESOLVED, NOT AS EMPTY.** A blank cell in
## a species column looks like a slot nobody has filled in yet, which is a
## completely different problem from a slot pointing at a species this roster
## does not have — and the second one is the one that would ship broken.
static func species_label(dex: int) -> String:
	if dex <= 0:
		return "(empty)"
	var name := TrainerData.species_name_for(dex)
	if name == "":
		return "#%d (unresolved)" % dex
	return "%03d %s" % [dex, name]


## Species matching `query`, for the picker. Empty query returns everything.
##
## Matches on NAME and on DEX NUMBER both, because an author who knows a species
## by number should not have to remember its spelling to reach it — and typing
## `25` is faster than `pika` when you do know it.
static func species_matches(query: String, limit: int = 0) -> Array:
	var q := query.strip_edges().to_lower()
	var out: Array = []
	var names: Dictionary = TrainerData.species_names()
	var dexes: Array = names.keys()
	dexes.sort()
	for dex in dexes:
		if int(dex) <= 0:
			continue
		var name := str(names[dex])
		if q != "" and not name.to_lower().contains(q) \
				and not str(dex).begins_with(q):
			continue
		out.append({"dex": int(dex), "name": name})
		if limit > 0 and out.size() >= limit:
			break
	return out


## A table to start editing, seeded from the generated one when there is one.
##
## ⚠️ **SEEDING IS WHAT MAKES "TAKE OWNERSHIP" DIFFERENT FROM "START OVER".**
## For an imported Kanto map the generated table is the thing you want to tweak,
## so retyping 15 slots to change one would make the button useless. A map with
## no generated table gets a blank at the field's own slot count — which is the
## from-scratch case, and it is the ordinary path rather than a special one.
static func seed_table(map_name: String,
		field: int = EncounterTable.Field.LAND) -> EncounterTable:
	var t := EncounterTable.new()
	t.map_name = map_name
	t.field = field
	var slot_count := WildEncounters.slot_rates().size()
	var src: Dictionary = WildEncounters.table_for(map_name)
	if not src.is_empty():
		t.encounter_rate = int(src.get("encounter_rate", 0))
		for s in src.get("slots", []):
			var row: Dictionary = s
			var slot := EncounterSlot.new()
			# max before min: the pair clamps each other and min defaults to 1,
			# so this is the order that never fights its own guard.
			slot.max_level = int(row.get("max", 1))
			slot.min_level = int(row.get("min", 1))
			slot.dex = int(row.get("dex", 0))
			t.slots.append(slot)
	while t.slots.size() < slot_count:
		t.slots.append(EncounterSlot.new())
	return t
