class_name NewGameEvents
extends RefCounted

## [M27G G7] Oak's speech, as a script rather than a coroutine.
##
## ⚠️ **THIS REPLACES `overworld.gd::run_new_game()`, AND THE POINT IS NOT
## TIDINESS.** That coroutine was this project's one `await`-based cutscene, and
## it produced a real, shipped defect: because it bypassed the VM, its yes/no
## prompt had **no input driver at all**, so `[M27K K-b]`'s gender question
## could never be answered from the keyboard. A second driver had to be added
## to `_process`, gated on `_vm == null`, with load-bearing ordering against the
## message box. One cutscene, one permanently forked input path.
##
## It passed its own test, because that test called `confirm()` directly. The
## lesson is recorded in this project's own words:
##
## > **A driver that reaches past the input layer cannot test the input layer.**
##
## Running through the VM means the ordinary driver handles the keys, and G7
## deletes the fork.
##
## ⚠️ **THE TWO RETRY LOOPS ARE REAL CONTROL FLOW, NOT A SIMPLIFICATION.**
## Source lets the player say NO and retype — `Task_OakSpeech_HandleConfirmName
## Input`'s NO branch loops back into naming with no extra text. A `while true`
## in GDScript becomes what it always was underneath: a label and a conditional
## jump back to it. That the op stream can express this is exactly why it did
## not need a coroutine.
##
## ⚠️ **`msgbox_yes_no` LEAVES THE BOX OPEN under the prompt** — the shape the
## old coroutine used deliberately (`_box.open` + `_yes_no.open`, not `_say`),
## because `_say` would force an extra dismiss press before the choice could be
## answered. `message`/`waitmessage`/`yesnobox` reproduces that exactly: no
## `waitbuttonpress` between the text and the question.


const LABEL := "NewGame_Authored_OakSpeech"
const LABEL_ASK_NAME := "NewGame_Authored_AskName"
## ⚠️ **THE LOOP TARGETS ARE SEPARATE LABELS, AND THAT IS NOT TIDINESS.** The
## retry must re-run NAMING ONLY — the old coroutine's `while true` wrapped
## `_ask_name` + confirm and nothing else. Jumping back to `LABEL_ASK_NAME`
## instead would re-show "Let's begin with your name. What is it?" on every
## retry, an extra page and an extra button press per attempt that source
## never asks for (`Task_OakSpeech_HandleConfirmNameInput`'s NO branch loops
## back into naming with NO extra text). Caught by H.03 timing out.
const LABEL_NAME_LOOP := "NewGame_Authored_NameLoop"
const LABEL_ASK_RIVAL := "NewGame_Authored_AskRival"
const LABEL_RIVAL_LOOP := "NewGame_Authored_RivalLoop"
const LABEL_FINISH := "NewGame_Authored_Finish"

const TEXT_WELCOME := "NewGame_Text_Welcome"
const TEXT_INHABITED := "NewGame_Text_Inhabited"
const TEXT_ASK_GENDER := "NewGame_Text_AskGender"
const TEXT_YOUR_NAME := "NewGame_Text_YourName"
const TEXT_SO_YOUR_NAME := "NewGame_Text_SoYourName"
const TEXT_RIVAL_INTRO := "NewGame_Text_RivalIntro"
const TEXT_CONFIRM_RIVAL := "NewGame_Text_ConfirmRivalName"
const TEXT_REMEMBER_RIVAL := "NewGame_Text_RememberRival"
const TEXT_LETS_GO := "NewGame_Text_LetsGo"


static func register_all() -> void:
	EventRegistry.register(LABEL, opening())
	EventRegistry.register(LABEL_ASK_NAME, ask_name())
	EventRegistry.register(LABEL_NAME_LOOP, name_loop())
	EventRegistry.register(LABEL_ASK_RIVAL, ask_rival())
	EventRegistry.register(LABEL_RIVAL_LOOP, rival_loop())
	EventRegistry.register(LABEL_FINISH, finish())


## Fade in, greet, release a Pokémon, ask the gender, then fall into naming.
##
## ⚠️ `lock_all`, not `lock`: there is no NPC being talked to. It is also
## belt-and-braces — the field is not running yet when this fires.
static func opening() -> Array:
	return EventScript.new() \
		.lock_all() \
		.native("OakPortrait", ["oak"]) \
		.native("OakFadeIn") \
		.msgbox(TEXT_WELCOME) \
		.native("OakBallRelease") \
		.msgbox(TEXT_INHABITED) \
		.msgbox(TEXT_ASK_GENDER) \
		.native("OakPickGender") \
		.native("OakPortraitPlayer") \
		.goto(LABEL_ASK_NAME) \
		.build()


## ⚠️ **THE RETRY LOOP.** `goto_if_eq VAR_RESULT, NO` jumps back to this label's
## own start, which is what "say no and retype" is. NO is 0 and YES is 1 —
## `yesnobox` polarity, NOT `multichoice MULTI_YESNO`'s list-index polarity,
## and the VM is what knows the difference (`ScriptVM._write_yes_no`).
static func ask_name() -> Array:
	return EventScript.new() \
		.msgbox(TEXT_YOUR_NAME) \
		.goto(LABEL_NAME_LOOP) \
		.build()


## The retry itself: type a name, confirm it, jump back HERE on NO — past the
## prompt, so a retry costs exactly one naming screen and one question.
static func name_loop() -> Array:
	return EventScript.new() \
		.native("OakAskPlayerName") \
		.msgbox_yes_no(TEXT_SO_YOUR_NAME) \
		.goto_if_eq("VAR_RESULT", "NO", LABEL_NAME_LOOP) \
		.goto(LABEL_ASK_RIVAL) \
		.build()


## The same shape for the rival. Source's own
## `gOakSpeech_Text_ConfirmRivalName` is the confirmation prompt here, exactly
## as `SoYourName` is for the player.
static func ask_rival() -> Array:
	return EventScript.new() \
		.native("OakPortrait", ["rival"]) \
		.msgbox(TEXT_RIVAL_INTRO) \
		.goto(LABEL_RIVAL_LOOP) \
		.build()


## Same split as `name_loop`, same reason.
static func rival_loop() -> Array:
	return EventScript.new() \
		.native("OakAskRivalName") \
		.msgbox_yes_no(TEXT_CONFIRM_RIVAL) \
		.goto_if_eq("VAR_RESULT", "NO", LABEL_RIVAL_LOOP) \
		.goto(LABEL_FINISH) \
		.build()


## ⚠️ The closing line is addressed to `{PLAYER}`, so it shows the PLAYER's own
## portrait, not Oak's — source's `Task_OakSpeech_ReshowPlayersPic`. Showing
## Oak here was a real bug `[M27K K-b]` fixed, and re-showing him would
## reintroduce it.
static func finish() -> Array:
	return EventScript.new() \
		.msgbox(TEXT_REMEMBER_RIVAL) \
		.native("OakPortraitPlayer") \
		.msgbox(TEXT_LETS_GO) \
		.native("OakFadeOut") \
		.release_all() \
		.end()
