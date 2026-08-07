class_name MultichoiceLists
extends RefCounted

## [M27G] The named option lists `multichoice` / `multichoicegrid` index.
##
## Source keeps these as `MenuAction` tables in `src/data/script_menu.h`,
## indexed by the `MULTI_*` enum. Only the lists this project can actually
## reach are transcribed — a Kanto-only game never opens the Hoenn ones, and an
## unlisted name halts and says so rather than showing an empty menu.


## ⚠️ **THE ORDER HERE DIVERGES FROM THE REFERENCE, DELIBERATELY, AND THE
## REFERENCE IS THE ONE THAT IS WRONG FOR KANTO.**
##
## `src/data/script_menu.h:69`'s `MultichoiceList_StatusInfo` is
## **PSN, PAR, SLP, BRN, FRZ, EXIT** — and the Hoenn caller agrees with it:
## `RustboroCity_PokemonSchool_EventScript_ChooseBlackboardTopic` maps
## `case 0 -> Poison`, `case 1 -> Paralysis`, `case 2 -> Sleep`.
##
## The FRLG caller does NOT. `ViridianCity_School_EventScript_ChooseBlackboard
## Topic` maps `case 0 -> ReadSleep`, `case 1 -> ReadPoison`,
## `case 2 -> ReadParalysis` — FireRed's own order, **SLP, PSN, PAR**. The
## expansion ported FireRed's script but reused Emerald's single shared list,
## so upstream the Viridian blackboard reads the SLEEP article when you pick
## PSN. Both scripts point at one `MULTI_STATUS_INFO` and only one of them can
## be right.
##
## This project is Kanto-only and Rustboro will never be baked, so the list
## carries FRLG's order and the one reachable call site is correct. ⚠️ **If a
## Hoenn map is ever imported, this needs to become two lists** — the constant
## cannot serve both.
const STATUS_INFO := ["SLP", "PSN", "PAR", "BRN", "FRZ", "EXIT"]

const _LISTS := {
	"MULTI_STATUS_INFO": STATUS_INFO,
}


static func has(list_name: String) -> bool:
	return _LISTS.has(list_name)


## The entries, or empty for a list this project has not transcribed. An empty
## answer is what makes the caller halt and NAME the list rather than opening a
## menu with nothing in it.
static func entries(list_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	for e in _LISTS.get(list_name, []):
		out.append(str(e))
	return out
