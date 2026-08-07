class_name PalletTownEvents
extends RefCounted

## [M27G G6] Authored Pallet Town content — the first script this project wrote
## in GDScript rather than compiling out of `field_script_source/`.
##
## ⚠️ **THIS IS A WORKED EXAMPLE, AND IT IS ALSO REAL.** It exists to prove the
## front-end end to end — a flag gate, a checkpoint, dialogue, and a `native`
## beat the opcode language cannot express — and it is written to be kept and
## extended rather than deleted once the tests are green.
##
## ⚠️ **NOT YET REACHED BY ANY PLACED ENTITY.** Attaching it means setting an
## NPC's `script_label` in a baked map scene, which is map DATA and a content
## decision, not a mechanism one. G6 ships the ability to write scripts; which
## NPC says what is Rob's call. Until then it is reachable by label — which is
## how the tests and the live drive run it, and how a trigger would.
##
## ⚠️ **THE DIALOGUE LIVES IN THE CORPUS, NOT HERE.** These constants name
## labels defined in `field_script_source/data/scripts/authored_text.inc` —
## the same place every imported line lives, per
## `docs/field_script_authoring.md`'s standing "no separate text-source tree"
## decision. G6 briefly registered pages in GDScript instead; that was undone
## the same day. Change a line by editing that `.inc` and running
## `python3 scripts/gen_map_texts.py`.


## ⚠️ Prefixed with the map, ending in a name the reference would never emit —
## the convention `AuthoredEvents` describes for staying clear of the imported
## corpus. `EventRegistry.merge_into` is what actually enforces it.
const LABEL_SIGN_POST := "PalletTown_Authored_SeaBreeze"

## The progress var this cutscene advances. `VAR_TEMP_*` deliberately: a temp
## var is cleared on map change, which is right for a one-conversation beat and
## wrong for anything the save should remember.
const VAR_SCENE := "VAR_TEMP_1"


const LABEL_SIGN_POST_AGAIN := LABEL_SIGN_POST + "_Again"
const TEXT_SEA_BREEZE := "PalletTown_Authored_Text_SeaBreeze"
const TEXT_SEA_BREEZE_SHORT := "PalletTown_Authored_Text_SeaBreezeShort"


static func register_all() -> void:
	EventRegistry.register(LABEL_SIGN_POST, sea_breeze())
	EventRegistry.register(LABEL_SIGN_POST_AGAIN, sea_breeze_again())


## A signpost by the water. First read is the full beat; afterwards it is one
## line, because a script that repeats itself verbatim reads as broken.
##
## Demonstrates, in order: a flag gate that branches, a `native` presentation
## beat (a real screen fade — something no opcode in this project could reach
## before G5), a checkpoint recording progress in world state rather than in a
## program counter, and a terminator.
static func sea_breeze() -> Array:
	return EventScript.new() \
		.lock() \
		.face_player() \
		.goto_if_set("FLAG_AUTHORED_SEA_BREEZE_READ", LABEL_SIGN_POST_AGAIN) \
		.msgbox(TEXT_SEA_BREEZE) \
		.native("Wait", ["20"]) \
		.set_flag("FLAG_AUTHORED_SEA_BREEZE_READ") \
		.checkpoint(VAR_SCENE, 1) \
		.release() \
		.end()


## The short version, reached by the gate above. Registered as its own label
## because that is how the VM's `goto` resolves — one label, one op list.
static func sea_breeze_again() -> Array:
	return EventScript.new() \
		.msgbox(TEXT_SEA_BREEZE_SHORT) \
		.release() \
		.end()
