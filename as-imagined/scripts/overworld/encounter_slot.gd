@tool
class_name EncounterSlot
extends Resource

## [M27T piece 5] One row of a wild-encounter table: a species and its level band.
##
## ⚠️ **A RESOURCE RATHER THAN THREE PARALLEL ARRAYS, AND THAT IS THE WHOLE
## REASON THE LAYER EXISTS.** Godot hands out undo, dirty-tracking and
## per-property interception only for `Resource` properties — an
## `EditorInspectorPlugin` can intercept `dex` on a sub-resource and swap in a
## species picker, and cannot do anything at all with `slots_dex[7]`. Piece 6 is
## that picker; this is the shape that makes it possible.
##
## ⚠️ **`@tool` IS LOAD-BEARING AND ITS ABSENCE FAILS SILENTLY — reported from
## the editor, 2026-08-13: every slot read `EncounterSlot` instead of its
## species.** A script without `@tool` gets a PLACEHOLDER instance in the editor:
## properties are stored raw and `_init`, the setters and `_validate_property`
## never run. So `_refresh_name()` never fired, `resource_name` stayed empty, and
## the Inspector fell back to the class name. **A headless suite cannot see this
## at all** — at runtime the real instance runs and every assertion passes, which
## is exactly why it shipped green. The same applies to `EncounterTable`, whose
## `incomplete_reason()` the panel calls on a loaded instance.
##
## ⚠️ **DEX NUMBER, NOT A SPECIES KEY, DELIBERATELY.** This project's own pattern
## is that species NAMES resolve to dex at GENERATION time and the runtime is
## numeric all the way down — `gen_wild_encounters.py` resolves through
## `gen_trainer_data.load_species_map()`, and `land_encounters.json` stores
## `dex`. Storing a key here would add a second resolution path, a second
## spelling to keep aligned, and a dangling-key failure class that
## `[M27B Step 4]`'s Nidoran collision already showed the cost of. The number is
## unreadable in a raw Inspector, which is a real objection — and it is what
## piece 6's picker exists to answer, rather than a reason to change the storage.


## National dex number. **0 means UNSET**, which is not the same as invalid — a
## freshly created table is all-zero by construction, and `EncounterTable`'s own
## completeness check is what stops such a table from ever reaching the roll.
@export var dex: int = 0:
	set(value):
		dex = maxi(0, value)
		_refresh_name()
		emit_changed()

## ⚠️ **THE PAIR CLAMPS EACH OTHER, IN BOTH DIRECTIONS, AND IT LIVES HERE RATHER
## THAN IN THE UI.** A setter holds for a script edit, a converter and a test
## fixture; a spinbox guard holds only for the one person dragging it. Pushing
## `min` above `max` carries `max` up, and pulling `max` below `min` carries
## `min` down.
##
## Each direction bounces exactly once and then terminates — the second setter's
## own comparison is already satisfied by the assignment that woke it — so this
## needs no re-entry flag. Both directions are tested independently, per the
## standing pair-symmetry convention, because a symmetric-LOOKING pair where only
## one side works is the shape that passes a one-directional test.
@export_range(1, 100) var min_level: int = 1:
	set(value):
		min_level = clampi(value, 1, 100)
		if max_level < min_level:
			max_level = min_level
		_refresh_name()
		emit_changed()

@export_range(1, 100) var max_level: int = 1:
	set(value):
		max_level = clampi(value, 1, 100)
		if min_level > max_level:
			min_level = max_level
		_refresh_name()
		emit_changed()


## ⚠️ **A `.tres` LOAD FIRES THESE SETTERS IN FILE PROPERTY ORDER, so a
## hand-edited inverted band is silently repaired rather than reported.** That is
## acceptable as a runtime BACKSTOP and is explicitly not the detection: the
## converter asserts on inverted source bands and refuses to build, and the suite
## sweeps the shipped corpus. Detection belongs where it can name the file; this
## only has to leave the object in a state the roll cannot trip over.
func is_valid() -> bool:
	return dex > 0 and min_level >= 1 and min_level <= max_level and max_level <= 100


## The generated table's own row shape, so both layers meet the runtime as one
## thing. See `EncounterTable.to_runtime()`.
func to_runtime() -> Dictionary:
	return {"dex": dex, "min": min_level, "max": max_level}


## ⚠️ **THE INSPECTOR SHOWS A RESOURCE'S `resource_name` IN PLACE OF ITS CLASS
## NAME**, so keeping it current is what turns fifteen rows reading
## `EncounterSlot` into a readable table. Rob's ask, 2026-08-13.
##
## ⚠️ **THE LEVEL BAND IS PART OF THE LABEL BECAUSE THE SPECIES ALONE IS NOT
## UNIQUE — measured, not assumed.** Xanadu Nursery carries dex 19 in FOUR slots,
## at levels 3, 4, 2 and 5; without the band those four rows are indistinguishable
## and the label would be prettier while still not telling you which slot you are
## editing. Same for its other three species, which appear 4, 3 and 4 times.
func _refresh_name() -> void:
	resource_name = slot_label()


func _init() -> void:
	# A default-constructed slot has no `dex` line in a `.tres`, so its setter
	# never fires on load and the name would stay blank. Seeded here instead.
	_refresh_name()


## ⚠️ **NEVER WRITTEN TO DISK.** `resource_name` is an ordinary stored property,
## so without this every slot would persist a species name that goes stale the
## moment `pokemon.json` is edited — a derived value kept beside its own source,
## which is the shape this project already refuses for per-slot percentages. The
## setters above recompute it on load, so the live value is always current and
## the `.tres` stays exactly as it is today.
func _validate_property(property: Dictionary) -> void:
	if property.name == "resource_name":
		property.usage = int(property.usage) & ~PROPERTY_USAGE_STORAGE


## `"Rattata Lv3"`, or `"Rattata Lv3-5"` across a band. The array-element label.
func slot_label() -> String:
	if dex <= 0:
		return "(empty)"
	var name := TrainerData.species_name_for(dex)
	if name == "":
		return "#%d (unresolved)" % dex
	if min_level == max_level:
		return "%s Lv%d" % [name, min_level]
	return "%s Lv%d-%d" % [name, min_level, max_level]


## `"019 Rattata"` — dex-first, for the digest panel and the picker button, where
## the number sorts and identifies. `EncounterPreview.species_label` delegates
## here rather than restating it.
##
## ⚠️ **STATIC AND ON THIS CLASS DELIBERATELY.** The natural home looks like
## `EncounterPreview`, but `EncounterSlot` -> `EncounterPreview` ->
## `EncounterTable` -> `EncounterSlot` is a `class_name` CYCLE, which Godot 4
## resolves badly and intermittently — the same reason `EncounterTable.is_complete`
## takes its slot count as a parameter instead of reading it back.
static func species_label(species_dex: int) -> String:
	if species_dex <= 0:
		return "(empty)"
	var name := TrainerData.species_name_for(species_dex)
	if name == "":
		return "#%d (unresolved)" % species_dex
	return "%03d %s" % [species_dex, name]
