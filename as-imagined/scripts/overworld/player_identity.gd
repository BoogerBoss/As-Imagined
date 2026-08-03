class_name PlayerIdentity
extends RefCounted

## [M27K K-b] Who the player is. The first thing in this project that answers
## that question at all.
##
## Until now the answer was the literal string "LEAF", hardcoded in THREE
## places that agreed with each other by luck rather than by design:
## `TextBuffers.PLAYER_NAME`, `battle_screen_shared.gd`'s own
## `_PLAYER_BACK_PIC`, and the overworld sprite `[M27D D1]` picked. This is the
## one place that owns it, and the three read from here instead.
##
## ⚠️ **NAMES ARE CAPPED AT 7, WHICH IS SOURCE'S OWN LIMIT** —
## `PLAYER_NAME_LENGTH` (`include/constants/global.h:159`). Not a display
## convenience: source sizes real save-block fields to it, and M27L will want
## the same bound. A longer name is TRUNCATED rather than refused, so a caller
## that skips the naming screen (a test, a debug boot) cannot produce a name
## the save format could not hold.

## Source: `include/constants/global.h:159`.
const NAME_LENGTH := 7

enum Gender { BOY, GIRL }

## FRLG's own preset lists, `sMaleNameChoices`/`sFemaleNameChoices`
## (`src/oak_speech.c:593-650`).
##
## ⚠️ **THE FIRST FEW ENTRIES ARE VERSION-GATED AND THIS PROJECT PICKS ONE.**
## Source's tables open with `#if defined(FIRERED)` — FireRed offers
## RED/FIRE/ASH/KENE/GEKI, LeafGreen offers GREEN/LEAF/GARY/KAZ/TORU. This
## project takes the **LeafGreen** set, because `_PLAYER_BACK_PIC` is already
## Leaf and a project whose sprite is Leaf offering "RED" first would be
## incoherent. Recorded as a choice, not drift.
const MALE_NAMES: PackedStringArray = [
	"GREEN", "LEAF", "GARY", "KAZ", "TORU",
	"JAK", "JANNE", "JONN", "KAMON", "KARL", "TAYLOR", "OSCAR", "HIRO",
	"MAX", "JON", "RALPH", "KAY", "TOSH", "ROAK",
]
const FEMALE_NAMES: PackedStringArray = [
	"GREEN", "LEAF",
	"OMI", "JODI", "AMANDA", "HILLARY", "MAKEY", "MICHI", "PAULA", "JUNE",
	"CASSIE", "REY", "SEDA", "KIKO", "MINA", "NORIE", "SAI", "MOMO", "SUZI",
]

## Source: `sRivalNameChoices` (`src/oak_speech.c`). Deliberately its own list —
## it is NOT the male list, and reusing that would offer the rival a different
## set than source does.
const RIVAL_NAMES: PackedStringArray = [
	"GREEN", "GARY", "KAZ", "TORU", "RED", "ASH", "KENE", "GEKI",
]

## Shown at the head of a name-choice list; picking it opens the keyboard.
## Source: `gOtherText_NewName` (`data/text/new_game_intro_frlg.inc`).
const NEW_NAME := "NEW NAME"

var name: String = ""
var gender: int = Gender.BOY
var rival_name: String = ""


## True once a new game has actually named the player. Everything that reads a
## name needs a sensible answer BEFORE that — a debug boot straight into the
## overworld never runs the speech — so the getters fall back rather than
## returning "".
func is_named() -> bool:
	return name != ""


## ⚠️ TRUNCATES RATHER THAN REFUSING. See the class comment: a caller that
## bypasses the naming screen must not be able to mint a name the save format
## cannot hold. Whitespace-only input is treated as no input at all.
static func sanitize(raw: String) -> String:
	var s := raw.strip_edges()
	if s.length() > NAME_LENGTH:
		s = s.substr(0, NAME_LENGTH)
	return s


func set_name(raw: String) -> void:
	name = sanitize(raw)


func set_rival_name(raw: String) -> void:
	rival_name = sanitize(raw)


## The preset list for the CURRENT gender — source keys the list on the answer
## to "Are you a boy? Or are you a girl?", so the two cannot be chosen out of
## order.
func name_choices() -> PackedStringArray:
	return FEMALE_NAMES if gender == Gender.GIRL else MALE_NAMES


## What `{PLAYER}` expands to. Falls back to the old hardcoded placeholder so a
## boot that skips the speech still reads as a name rather than a blank.
func display_name() -> String:
	return name if name != "" else "LEAF"


## What `{RIVAL}` expands to. Source's own default rival is Blue/Green; the
## fallback keeps a skipped speech readable for the same reason as above.
func display_rival_name() -> String:
	return rival_name if rival_name != "" else "GREEN"


## The back sprite this player uses in battle, replacing the hardcoded constant
## `battle_screen_shared.gd` has carried since `[M26B3-3]`.
##
## ⚠️ Only two back pics exist for a Kanto player — `leaf.png` and `red.png`,
## both pulled at `[M26B3-3]`. Gender picks between them; there is no third.
func back_pic_stem() -> String:
	return "leaf" if gender == Gender.GIRL else "red"
