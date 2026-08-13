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
		emit_changed()

@export_range(1, 100) var max_level: int = 1:
	set(value):
		max_level = clampi(value, 1, 100)
		if min_level > max_level:
			min_level = max_level
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
