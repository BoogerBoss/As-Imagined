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
