@tool
class_name Trigger
extends OverworldEntity

## [M27B/M27D] A tile that runs a script when stepped on, gated on a variable.
##
## Source's `coord_events`. The gate is a plain equality check against one of
## its own VAR_* slots, which is how a cutscene fires exactly once: the script
## it runs sets the var to a value the trigger no longer matches.

## Source's own VAR_* constant.
@export var var_name: String = ""

## The value `var_name` must equal for this trigger to fire.
@export var var_value: int = 0


func _get_configuration_warnings() -> PackedStringArray:
	var out := super()
	if var_name == "" and script_label != "":
		out.append("Runs a script but has no gating var — it will fire on every step.")
	return out
