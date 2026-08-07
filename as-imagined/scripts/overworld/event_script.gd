class_name EventScript
extends RefCounted

## [M27G G6] Author a field script in GDScript instead of GBA assembler.
##
## ⚠️ **A WRITER, NOT A RUNTIME.** This produces the exact same op list
## `gen_map_scripts.py` emits — `[{"op": ..., "args": [...]}, ...]` — and
## `ScriptVM` cannot tell which one typed it. Nothing downstream changes: same
## VM, same driver, same `describe()`, same save format, same tests. If this
## file were deleted tomorrow, every imported script would still run.
##
## **Two authoring paths, one runtime:**
##
##     field_script_source/**/*.inc ──gen_map_scripts.py──┐
##                                                        ├──► ops_by_label ──► ScriptVM
##     scripts/events/*.gd (this)   ──────────────────────┘
##
## Why it exists: the 17,137 imported labels give this project Kanto's geometry
## and systems, but its **story is all new scripts**, and writing one meant GBA
## assembler plus a Python regenerate step — no autocomplete, no type checking,
## and an unimplemented opcode surfacing as a runtime `UNKNOWN_OP` mid-
## conversation rather than an error at author time.
##
## ⚠️ **THIS PROJECT HAS PAID TWICE FOR THE FAILURE MODE A TYPED FRONT-END
## REMOVES**, both silent and both wrong at every call site at once: `YES`/`NO`
## resolving to 0 (inverting every yes/no branch in the region) and `PARTY_SIZE`
## resolving to 0 (making every "nothing chosen" check take the Decline branch).
## Both were found by live-driving, not by any test.
##
## Usage — chain, then terminate with `end()` or `ret()`, which return the
## built Array:
##
##     static func seto_intro() -> Array:
##         return EventScript.new() \
##             .lock() \
##             .face_player() \
##             .msgbox_npc("SetoIntro_Greeting") \
##             .native("FadeToBlack") \
##             .set_flag("FLAG_SETO_MET") \
##             .end()
##
## ⚠️ **EVERY ARGUMENT IS STRINGIFIED**, because the compiler's own output is
## strings throughout (`{"args": ["VAR_X", "2", "T"]}` — even the numbers). A
## builder that emitted real ints would produce an op list that *looks* right,
## runs correctly today because `_resolve_number` calls `str()` on everything
## anyway, and silently diverges the moment anything compares the two forms.
## The round-trip test in `m27f_script_vm_test` section R exists to hold this.
##
## ⚠️ **`build()` RETURNS A PLAIN `Array`, NOT `Array[Dictionary]`.** Assigning
## an untyped Array to a typed one fails SILENTLY in GDScript — a gotcha this
## project has already paid for (see `ScriptVM.start`'s own `.clear()` comment)
## — and `ScriptSource.ops_by_label` holds plain Arrays parsed from JSON, so a
## typed return here would be a conversion waiting to go wrong.


## Every op name this builder can emit.
##
## ⚠️ **NOT DECORATION — `m27f_script_vm_test` R.02 iterates it and drives a
## one-op VM for each**, asserting none halts with `UNKNOWN_OP`. That is the
## mechanical guard `docs/m27g_scope.md` §7 requires: it makes it impossible to
## add a builder method for an opcode the VM does not implement, which would
## otherwise compile cleanly and halt at runtime — the exact failure this whole
## front-end exists to remove. Add a method, add its op here, or the test fails.
const OPS := [
	"lock", "lockall", "release", "releaseall", "faceplayer", "closemessage",
	"message", "waitmessage", "waitbuttonpress", "yesnobox",
	"setflag", "clearflag", "setvar", "copyvar", "addvar", "subvar",
	"compare", "goto", "call", "return", "end",
	"goto_if_eq", "goto_if_ne", "goto_if_lt", "goto_if_le", "goto_if_gt",
	"goto_if_ge", "goto_if_set", "goto_if_unset",
	"goto_if_defeated", "goto_if_not_defeated",
	"call_if_eq", "call_if_set", "call_if_unset",
	"applymovement", "waitmovement", "turnobject", "setobjectxyperm",
	"addobject", "removeobject", "setobjectmovementtype",
	"additem", "removeitem", "checkitem", "giveitem", "givemon",
	"warp", "setrespawn", "special", "specialvar",
	"trainerbattle_single", "trainerbattle_no_intro",
	"native",
]

var _ops: Array = []


func _emit(op_name: String, args: Array = []) -> EventScript:
	var out: Array = []
	for a in args:
		out.append(str(a))
	_ops.append({"op": op_name, "args": out})
	return self


# --- terminators ---------------------------------------------------------

## Append `end` and hand back the built ops. `end` at depth 0 stops the script.
func end() -> Array:
	_emit("end")
	return _ops


## Append `return` and hand back the built ops — for a script reached by `call`.
func ret() -> Array:
	_emit("return")
	return _ops


## The ops so far, unterminated. For a script that falls through deliberately,
## or for a fragment being assembled by other code.
func build() -> Array:
	return _ops


# --- player control ------------------------------------------------------

func lock() -> EventScript: return _emit("lock")
func lock_all() -> EventScript: return _emit("lockall")
func release() -> EventScript: return _emit("release")
func release_all() -> EventScript: return _emit("releaseall")
func face_player() -> EventScript: return _emit("faceplayer")
func close_message() -> EventScript: return _emit("closemessage")


# --- text ----------------------------------------------------------------

## The raw primitive — opens the box and returns immediately.
func message(text_label: String) -> EventScript: return _emit("message", [text_label])
func wait_message() -> EventScript: return _emit("waitmessage")
func wait_button() -> EventScript: return _emit("waitbuttonpress")
func yes_no() -> EventScript: return _emit("yesnobox")


## `msgbox X, MSGBOX_NPC` — lock, turn to face the player, say it, wait, release.
##
## ⚠️ **EXPANDED HERE, exactly as `gen_map_scripts.py` expands it at compile
## time** (`STD_EXPANSIONS`, transcribed from `data/scripts/std_msgbox.inc`).
## The VM deliberately has no `callstd` and no std-script table, so this must
## emit the same six primitives the compiler does or the two front-ends diverge
## on the single most common script shape in the corpus.
func msgbox_npc(text_label: String) -> EventScript:
	return lock().face_player().message(text_label).wait_message() \
			.wait_button().release()


## `msgbox X, MSGBOX_SIGN` — no facing; a sign does not turn to look at you.
func msgbox_sign(text_label: String) -> EventScript:
	return lock_all().message(text_label).wait_message().wait_button().release_all()


## `msgbox X, MSGBOX_DEFAULT` — just the three text primitives, no lock/release.
func msgbox(text_label: String) -> EventScript:
	return message(text_label).wait_message().wait_button()


## `msgbox X, MSGBOX_YESNO` — asks, and leaves the answer in VAR_RESULT.
## ⚠️ YES is 1 here (`yesnobox` polarity), NOT the list-index polarity
## `multichoice MULTI_YESNO` uses. The VM owns that distinction; see
## `ScriptVM._write_yes_no`.
func msgbox_yes_no(text_label: String) -> EventScript:
	return message(text_label).wait_message().yes_no()


# --- flags, vars, progress ----------------------------------------------

func set_flag(flag_name: String) -> EventScript: return _emit("setflag", [flag_name])
func clear_flag(flag_name: String) -> EventScript: return _emit("clearflag", [flag_name])
func set_var(var_name: String, value) -> EventScript: return _emit("setvar", [var_name, value])
func copy_var(dest: String, src: String) -> EventScript: return _emit("copyvar", [dest, src])
func add_var(var_name: String, value) -> EventScript: return _emit("addvar", [var_name, value])
func sub_var(var_name: String, value) -> EventScript: return _emit("subvar", [var_name, value])
func compare(var_name: String, value) -> EventScript: return _emit("compare", [var_name, value])


## [M27G G6] Record how far a cutscene has got.
##
## ⚠️ **SUGAR FOR `setvar`, AND THE CONVENTION IT ENCODES IS THE WHOLE SAVE
## STORY.** Events are re-entrant from world state, never resumed from
## execution state — there is no `scriptPtr` in the save and there must not be
## (`docs/m27g_scope.md` §7). A long cutscene therefore advances a
## `VAR_MAP_SCENE_*` at each act boundary, and the map's own OnFrame/
## OnTransition table dispatches on it, so a quit or a crash loses at most one
## act. Named rather than left as a bare `set_var` so the intent is legible at
## the call site and greppable across authored content.
func checkpoint(var_name: String, act: int) -> EventScript:
	return set_var(var_name, act)


# --- control flow --------------------------------------------------------

func goto(label: String) -> EventScript: return _emit("goto", [label])
func call_script(label: String) -> EventScript: return _emit("call", [label])

## ⚠️ THE LABEL IS THE LAST ARGUMENT in every conditional, never the first —
## the shape `ScriptVM._conditional` reads and the one an early cut of that
## function got backwards, sending every gated script jumping to a VAR name.
func goto_if_eq(var_name: String, value, label: String) -> EventScript:
	return _emit("goto_if_eq", [var_name, value, label])
func goto_if_ne(var_name: String, value, label: String) -> EventScript:
	return _emit("goto_if_ne", [var_name, value, label])
func goto_if_lt(var_name: String, value, label: String) -> EventScript:
	return _emit("goto_if_lt", [var_name, value, label])
func goto_if_le(var_name: String, value, label: String) -> EventScript:
	return _emit("goto_if_le", [var_name, value, label])
func goto_if_gt(var_name: String, value, label: String) -> EventScript:
	return _emit("goto_if_gt", [var_name, value, label])
func goto_if_ge(var_name: String, value, label: String) -> EventScript:
	return _emit("goto_if_ge", [var_name, value, label])
func goto_if_set(flag_name: String, label: String) -> EventScript:
	return _emit("goto_if_set", [flag_name, label])
func goto_if_unset(flag_name: String, label: String) -> EventScript:
	return _emit("goto_if_unset", [flag_name, label])
func goto_if_defeated(trainer_key: String, label: String) -> EventScript:
	return _emit("goto_if_defeated", [trainer_key, label])
func goto_if_not_defeated(trainer_key: String, label: String) -> EventScript:
	return _emit("goto_if_not_defeated", [trainer_key, label])
func call_if_eq(var_name: String, value, label: String) -> EventScript:
	return _emit("call_if_eq", [var_name, value, label])
func call_if_set(flag_name: String, label: String) -> EventScript:
	return _emit("call_if_set", [flag_name, label])
func call_if_unset(flag_name: String, label: String) -> EventScript:
	return _emit("call_if_unset", [flag_name, label])


# --- entities ------------------------------------------------------------

## ⚠️ ASYNCHRONOUS, like source. This queues and the script keeps running;
## `wait_movement()` is the half that blocks. That is what lets two entities
## walk at once, which most cutscenes do.
func apply_movement(target: String, movement_label: String) -> EventScript:
	return _emit("applymovement", [target, movement_label])

## `0` / `LOCALID_NONE` / omitted means "everything in flight", not "object 0".
func wait_movement(target: String = "0") -> EventScript:
	return _emit("waitmovement", [target])

func turn_object(target: String, dir_token: String) -> EventScript:
	return _emit("turnobject", [target, dir_token])
func set_object_xy_perm(target: String, x: int, y: int) -> EventScript:
	return _emit("setobjectxyperm", [target, x, y])
func set_object_movement_type(target: String, movement_type: String) -> EventScript:
	return _emit("setobjectmovementtype", [target, movement_type])
func add_object(target: String) -> EventScript: return _emit("addobject", [target])
func remove_object(target: String) -> EventScript: return _emit("removeobject", [target])


# --- items, party, world -------------------------------------------------

func add_item(item: String, qty: int = 1) -> EventScript: return _emit("additem", [item, qty])
func remove_item(item: String, qty: int = 1) -> EventScript: return _emit("removeitem", [item, qty])
func check_item(item: String, qty: int = 1) -> EventScript: return _emit("checkitem", [item, qty])
func give_item(item: String, qty: int = 1) -> EventScript: return _emit("giveitem", [item, qty])
func give_mon(species: String, level: int) -> EventScript: return _emit("givemon", [species, level])
func set_respawn(heal_location: String) -> EventScript: return _emit("setrespawn", [heal_location])

## ⚠️ x/y are a destination CELL, not a warp id — `ScrCmd_warp` reads them
## literally.
func warp(map_constant: String, x: int, y: int) -> EventScript:
	return _emit("warp", [map_constant, x, y])

func special(fn: String) -> EventScript: return _emit("special", [fn])
## ⚠️ DESTINATION VAR FIRST, function second — the opposite of how it reads
## aloud, and the order `ScriptVM` expects.
func special_var(dest_var: String, fn: String) -> EventScript:
	return _emit("specialvar", [dest_var, fn])

func trainer_battle(trainer_key: String, intro_label: String, defeat_label: String,
		continuation_label: String = "") -> EventScript:
	if continuation_label == "":
		return _emit("trainerbattle_single", [trainer_key, intro_label, defeat_label])
	return _emit("trainerbattle_single",
			[trainer_key, intro_label, defeat_label, continuation_label])

func trainer_battle_no_intro(trainer_key: String, defeat_label: String) -> EventScript:
	return _emit("trainerbattle_no_intro", [trainer_key, defeat_label])


# --- the escape hatch ----------------------------------------------------

## [M27G G5] Hand control to registered Godot code, then carry on.
##
## ⚠️ **PRESENTATION AND ENGINE CAPABILITY ONLY — never control flow, never
## state.** See `NativeEventRegistry`'s header for why that rule is what keeps
## the op stream the whole story.
func native(handler_name: String, args: Array = []) -> EventScript:
	var all: Array = [handler_name]
	all.append_array(args)
	return _emit("native", all)
