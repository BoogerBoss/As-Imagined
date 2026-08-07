class_name StartMenuEvents
extends RefCounted

## [M27G G7] Saving, as a script.
##
## ⚠️ **THIS CALLER WAS NOT IN G7's SCOPE LIST — it was found by deleting the
## free-standing yes/no driver and asking what else used it.** The scope doc
## named `run_new_game` and `_poison_step`; `_on_start_menu_save` opened a
## yes/no outside the VM too, so deleting that driver would have left SAVING
## unanswerable from the keyboard — the identical bug `[M27K K-b]`'s gender
## question shipped with, reintroduced by the very phase fixing it.
##
## ⚠️ **THE BOX STAYS OPEN UNDER THE PROMPT.** `msgbox_yes_no` is
## `message`/`waitmessage`/`yesnobox` with no `waitbuttonpress` between them,
## which is what the old coroutine did deliberately (`_box.open` + `_yes_no
## .open`, not `_say`) so the question is still on screen while it is answered.


const LABEL := "StartMenu_Authored_Save"
const LABEL_FAILED := "StartMenu_Authored_SaveFailed"

const TEXT_CONFIRM := "StartMenu_Text_SaveConfirm"
const TEXT_SAVING := "StartMenu_Text_Saving"
const TEXT_DONE := "StartMenu_Text_SaveDone"
const TEXT_FAILED := "StartMenu_Text_SaveFailed"


static func register_all() -> void:
	EventRegistry.register(LABEL, save())
	EventRegistry.register(LABEL_FAILED, failed())
	EventRegistry.register(LABEL_FAILED + "_Abort", abort())


## ⚠️ `SaveGame` is the one handler here that writes nothing the script can
## see — it returns 1/0 and the script branches on it, which is a handler
## ANSWERING a question rather than owning the decision. That is the shape the
## refined `native` rule permits without qualification.
static func save() -> Array:
	return EventScript.new() \
		.lock_all() \
		.msgbox_yes_no(TEXT_CONFIRM) \
		.goto_if_eq("VAR_RESULT", "NO", LABEL_FAILED + "_Abort") \
		.msgbox(TEXT_SAVING) \
		.native("SaveGame") \
		.goto_if_eq("VAR_RESULT", "0", LABEL_FAILED) \
		.msgbox(TEXT_DONE) \
		.release_all() \
		.end()


static func failed() -> Array:
	return EventScript.new() \
		.msgbox(TEXT_FAILED) \
		.release_all() \
		.end()


## The NO branch: nothing said, nothing written. Registered as its own label
## because a `goto` needs one.
static func abort() -> Array:
	return EventScript.new().release_all().end()
