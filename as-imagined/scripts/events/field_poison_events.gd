class_name FieldPoisonEvents
extends RefCounted

## [M27G G7 follow-up] The field-poison notice, as a script.
##
## ⚠️ **THIS IS WHAT DELETED THE LAST FREE-STANDING MESSAGE-BOX DRIVER.** The
## notice builds its pages at RUNTIME — one per Pokémon left sitting at 1 HP,
## each with that Pokémon's own name buffered — and `message` names a STATIC
## label in the text corpus. There is no opcode for "show these N pages I just
## computed", which is why `_poison_step` used to open the box directly and
## needed its own input driver in `_process`.
##
## The loop below is the answer, and it needs no new opcode and no driver
## change: a `native` buffers the next name and answers 1, or answers 0 when
## the queue is drained; `message` shows the one static line; `goto` comes
## back. Every page stays inside the op stream, so `describe()` still tells the
## truth about a running poison notice and a frozen test can still read it.
##
## ⚠️ The handler writes only `TextBuffers` — runtime-only, like source's own
## `gStringVar1`, and explicitly not a flag, a var, or a branch. The rule holds.
##
## Source runs this as a real script too (`EventScript_FieldPoison`, opening
## with `lockall`), which this project could not do when the notice was built
## because there was no VM to park it on.


const LABEL := "FieldPoison_Authored_Notice"
const LABEL_LOOP := "FieldPoison_Authored_NoticeLoop"
const TEXT_SURVIVED := "FieldPoison_Text_Survived"


static func register_all() -> void:
	EventRegistry.register(LABEL, notice())
	EventRegistry.register(LABEL_LOOP, notice_loop())
	EventRegistry.register(LABEL + "_Done", done())


static func notice() -> Array:
	return EventScript.new() \
		.lock_all() \
		.goto(LABEL_LOOP) \
		.build()


## ⚠️ The guard is the HANDLER's answer, not a counter the script keeps. A
## script-side counter would be a second source of truth for "how many are
## left" and could drift from the queue it is draining.
static func notice_loop() -> Array:
	return EventScript.new() \
		.native("BufferNextPoisonSurvivor") \
		.goto_if_eq("VAR_RESULT", "0", LABEL + "_Done") \
		.msgbox(TEXT_SURVIVED) \
		.goto(LABEL_LOOP) \
		.build()


static func done() -> Array:
	return EventScript.new().release_all().end()
