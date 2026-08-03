class_name FieldSpecials
extends RefCounted

## [M27F Stage 4] `special` / `specialvar` / `callnative` — a NARROW carve-out.
##
## ⚠️ **THIS IS DELIBERATELY NOT M27G.** That block owns the real scoping pass,
## and the surface is genuinely large: measured across the compiled corpus,
## **1,390 `special` + 719 `specialvar` = 2,109 uses across 569 distinct C
## functions**, plus 62 `callnative` across 28 more. (Worth recording: M27's own
## roadmap row estimates "a few hundred" distinct functions — the real figure is
## 569, so M27G is bigger than currently written down.)
##
## What this file does instead is unblock ONE thing — healing — and stop there.
## The same carve-out shape `[M26B4-0]` used for `weather_continues`: take the
## one entry a blocked feature needs, leave the block itself intact.
##
## ⚠️ **AN UNKNOWN SPECIAL STILL HALTS THE VM, AND THAT IS ON PURPOSE.** The
## tempting shortcut is "unknown `specialvar` writes 0 to VAR_RESULT" — which
## would, as it happens, carry the nurse script through unaided, because every
## branch it takes tests against 0. It is rejected anyway for two reasons: it
## invents a behaviour source has no equivalent for (every special exists
## there, so there is no "unimplemented" case to be faithful to), and it would
## silently take a branch in the other 2,100 call sites rather than reporting a
## gap. Halting keeps `[M27F]`'s corpus-coverage figures honest, which is the
## one measurement telling us how far the script engine actually reaches.


## Specials that DO something.
const HEAL_PLAYER_PARTY := "HealPlayerParty"

## [M27K K-c] ⚠️ **NAMED HERE BUT DELIBERATELY NOT RUN HERE.** `run()` answers in
## the same frame and returns a bool, which fits `HealPlayerParty` and fits
## nothing that owns the display: this one opens the keyboard and the script has
## to wait for it. `ScriptVM` intercepts the name before calling `run()` and
## raises `Pause.WAIT_NAMING` instead.
##
## The constant still lives here so this file stays the single answer to "which
## specials does the project implement" — the alternative was a bare string
## literal in the VM and a silent gap in this list. `is_known_special` reports it
## as known for the same reason; `run()` refuses it, so a caller that ignores the
## VM's interception gets a halt rather than a script that skips the rename.
const NICKNAME_SPECIAL := "ChangePokemonNickname"


## Specials deliberately treated as no-ops, each because the system it touches
## does not exist here — NOT because it was inconvenient.
##
## `UpdateFollowingPokemon` / `hidefollower`: no follower Pokémon (ruled out
## project-wide, `docs/overworld_scope.md`). `DrawWholeMapView`: this project
## repaints continuously rather than on demand.
const NOOP_SPECIALS := [
	"UpdateFollowingPokemon",
	"DrawWholeMapView",
]


## `specialvar` functions this carve-out can answer, each with its TRUE value
## here and the reason that value is honest rather than merely convenient.
##
## ⚠️ **THE VALUE IS PER ENTRY, AND TWO OF THE FIVE ARE 1.** A first cut made
## this a blanket "answer 0", which carried the nurse through and was WRONG on
## exactly the negated predicates: `PlayerNotAtTrainerHillEntrance` and
## `IsPlayerNotInTrainerTowerLobby` both `return TRUE` unless you are standing
## in that specific facility (`field_specials.c:2143, 5408`) — so in a Pokecentre
## the true answer is 1. Both scripts happen to reach the same place either way,
## which is precisely why a convenient-but-false value would have survived
## testing and then been wrong somewhere else. Read the function, do not guess
## from the branch that follows it.
##
## ⚠️ Every entry is a **1-2 use** function region-wide — a short tail being
## closed, not a policy. A future session adds entries here one at a time with
## the same justification; the moment this list grows by category it has become
## M27G and belongs there.
const SPECIALVAR_VALUES := {
	# 0 stars on a new save: no Hall of Fame, no complete dex, no contest
	# paintings, no Frontier symbols (`trainer_card.c:664`). Genuinely 0, and
	# also 0 because no trainer card exists here (M27I).
	"CountPlayerTrainerStars": [0, "a new save genuinely has 0 stars"],
	# Pokerus is not modelled at all, and source's own function returns FALSE
	# when the config is off (`pokerus.c:73`).
	"IsPokerusInParty": [0, "Pokerus is not modelled; FALSE is genuinely correct"],
	# ⚠️ NEGATED PREDICATE. TRUE everywhere except the Trainer Hill entrance.
	"PlayerNotAtTrainerHillEntrance": [1, "TRUE anywhere but Trainer Hill, which the corridor has none of"],
	# ⚠️ NEGATED PREDICATE. TRUE everywhere except the Trainer Tower lobby.
	"IsPlayerNotInTrainerTowerLobby": [1, "TRUE anywhere but the Trainer Tower lobby, which is out of scope"],
	# FALSE with no link players connected (`union_room.c:3382`); link is a
	# confirmed permanent exclusion, so there can never be one.
	"BufferUnionRoomPlayerName": [0, "link/Union Room is permanently excluded, so there is never a name"],
}


static func is_known_special(name: String) -> bool:
	return (name == HEAL_PLAYER_PARTY or name == NICKNAME_SPECIAL
			or name in NOOP_SPECIALS)


static func is_known_specialvar(name: String) -> bool:
	return SPECIALVAR_VALUES.has(name)


## The value an allowlisted `specialvar` answers with. See the table's own note:
## this is the function's REAL return here, not a uniform default.
static func specialvar_value(name: String) -> int:
	var entry: Array = SPECIALVAR_VALUES.get(name, [0, ""])
	return int(entry[0])


## Run a `special`. Returns false if it is not one this carve-out covers, so the
## VM can halt and report the name rather than continuing past a gap.
static func run(name: String) -> bool:
	match name:
		HEAL_PLAYER_PARTY:
			# Source: `HealPlayerParty` (`script_pokemon_util.c:38`) loops the
			# party through `HealPokemon` — max HP, status cleared, PP restored
			# — which is exactly what `heal_party` already does for the whiteout.
			# Its two other branches are both moot here: `HealPlayerBoxes` needs
			# a PC (M27I I5) and the Tera Orb recharge is excluded project-wide.
			OverworldSession.heal_party()
			return true
		_:
			return name in NOOP_SPECIALS
