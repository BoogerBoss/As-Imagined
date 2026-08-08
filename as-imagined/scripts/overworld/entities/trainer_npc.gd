@tool
class_name TrainerNPC
extends NPC

## [M27B/M27D] An NPC who battles on sight.
##
## Identity lives in TrainerRegistry and is referenced by **trainer_key**, never
## by trainer_id: the int is a sorted-alphabetical index assigned at conversion
## time and shifts whenever the roster is regenerated, while the key is source's
## own stable constant (docs/overworld_scope.md §32).
##
## Keys are canonical and origin-suffixed (Rule A): TRAINER_LASS_ROBIN_FRLG,
## not the bare source constant. The suffix is applied at import time by
## scripts/trainer_keys.py, the single owner of that rule.

## Source's own TRAINER_* constant, recovered from the placement's script body
## by the importer's whole-tree label index (the map.json placement itself
## carries only a script label).
@export var trainer_key: String = ""

## How many tiles ahead this trainer notices the player. Source stores it in the
## object event's own `trainer_sight_or_berry_tree_id` field, which is genuinely
## overloaded — it is a sight range here and a berry-tree id on berry-tree
## objects, discriminated by the object's own trainer_type.
@export var sight_range: int = 0

## [M27Q Q2] Open this trainer's own `.tres` in the Inspector.
##
## ⚠️ **THIS IS THE DOOR BETWEEN THE TWO STORAGE CLASSES, WHICH IS WHY A BUTTON
## EARNS ITS PLACE HERE AT ALL.** Everything else the Inspector edits on a
## placed trainer is a node property. The team (`TrainerData.party`, already
## editable through Godot's own array-of-resources UI) and the AI flags
## (`TrainerData.ai_flags`, checkboxes as of Q2) both live in a SEPARATE file
## keyed only by `trainer_key` — so without this the route from "I clicked the
## character on the map" to "I am editing his team" is: read the key, then find
## it by hand among 1,477 files. Four of the six fields this block exists to
## surface were reachable but not discoverable.
##
## ⚠️ **DOES NOT SERIALISE — verified, not assumed.** A tool button reports
## `usage=4100`, which excludes `PROPERTY_USAGE_STORAGE (2)`; packing a node
## carrying one writes no line for it. Baked map scenes and `check_bake_diff`
## are therefore untouched, which matters because the alternative — an
## `@export var trainer_data: TrainerData` — would both serialise into all 32
## baked scenes AND break the deliberate string-keying Rule A protects
## (`trainer_id` is a sorted index that shifts on every roster regen; the key
## is source's own stable constant).
@export_tool_button("Open trainer resource") var _open_trainer := _edit_trainer_resource


## ⚠️ Reached through `Engine.get_singleton`, never by naming `EditorInterface`
## directly: that class does not exist in an exported build, and a bare
## reference would be a runtime error in a shipped game for the sake of an
## editor convenience. The `is_editor_hint()` check is the gate; the singleton
## lookup is the belt.
func _edit_trainer_resource() -> void:
	if not Engine.is_editor_hint():
		return
	# Says WHY rather than doing nothing — a dead button is indistinguishable
	# from a broken one, and both of these are real states a placement can be
	# in (an unkeyed trainer, or a key that outlived a roster regen).
	if trainer_key == "":
		push_warning("TrainerNPC: no trainer_key set — nothing to open.")
		return
	if not has_registry_entry():
		push_warning("TrainerNPC: trainer_key '%s' does not resolve against "
				% trainer_key + "TrainerRegistry — no resource to open.")
		return
	var editor := Engine.get_singleton("EditorInterface")
	if editor == null:
		return
	editor.edit_resource(TrainerRegistry.get_trainer_by_key(trainer_key))


func has_registry_entry() -> bool:
	return trainer_key != "" and TrainerRegistry.has_trainer_key(trainer_key)


func _get_configuration_warnings() -> PackedStringArray:
	var out := super()
	if trainer_key == "":
		out.append("No trainer_key — this trainer cannot start a battle.")
	elif not has_registry_entry():
		out.append("trainer_key '%s' does not resolve against TrainerRegistry."
				% trainer_key)
	if sight_range < 0:
		out.append("sight_range %d is negative." % sight_range)
	return out
