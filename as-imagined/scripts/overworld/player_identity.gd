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
## ⚠️ **THE CAP IS 12, AND IT IS DELIBERATELY *NOT* SOURCE'S 7.** Rob's call,
## 2026-08-03, after asking whether 7 was necessary or merely inherited. It was
## inherited: source's `PLAYER_NAME_LENGTH` (`include/constants/global.h:159`)
## exists because the GBA sizes a fixed save-block field to it, and **this
## project shares none of that** — checked before changing it:
##
##   * no fixed-width slot displays the player's name anywhere; the only
##     consumers are `{PLAYER}` substitutions inside message text;
##   * this project saves structured data as JSON (`team_storage.gd`), which
##     has no field width, and M27L will follow that precedent;
##   * nothing reserves glyphs for it in the message box.
##
## [An earlier draft of this comment claimed "M27L will want the same bound".
## That was wrong and is corrected here rather than left to justify a number
## nothing requires.]
##
## 12 matches `POKEMON_NAME_LENGTH` (`global.h:156`), which nicknames will want
## anyway, so the project carries ONE name bound rather than two. A cap remains
## because the value reaches a save file and authored dialogue is hand-wrapped
## around short names — unbounded input belongs in neither.
##
## A longer name is TRUNCATED rather than refused, so a caller that skips the
## naming screen (a test, a debug boot) cannot produce an unstorable name.
const NAME_LENGTH := 12

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

## [Summary-screen INFO-page OT ID] Source generates this once at new-game
## creation and keeps it for the life of a save (`gSaveBlock2Ptr`'s own
## trainer-ID field). This project has no such generation moment wired into
## the new-game flow yet -- lazily generated on first read instead
## (`ensure_trainer_id()`), then held for the life of this identity object.
## 0 is the untouched sentinel, never a real ID.
var trainer_id: int = 0


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


## Real (non-zero) trainer ID, generating one on first call. Kept for the
## life of this identity object rather than regenerated per read.
func ensure_trainer_id() -> int:
	if trainer_id == 0:
		trainer_id = randi() % 100000
	return trainer_id


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


## [M27L L1] Who the player is, for a save slot.
func to_save() -> Dictionary:
	return {"name": name, "gender": gender, "rival": rival_name, "trainer_id": trainer_id}


## ⚠️ Goes through `set_name`/`set_rival_name` rather than assigning, so a
## hand-edited save cannot smuggle in a name longer than the cap that every
## other path enforces.
func from_save(data: Dictionary) -> void:
	set_name(str(data.get("name", "")))
	set_rival_name(str(data.get("rival", "")))
	gender = Gender.GIRL if int(data.get("gender", Gender.BOY)) == Gender.GIRL \
			else Gender.BOY
	trainer_id = int(data.get("trainer_id", 0))
