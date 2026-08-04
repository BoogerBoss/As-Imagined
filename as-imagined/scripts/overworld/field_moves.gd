class_name FieldMoves
extends RefCounted

## [M27E E0] Who may reshape the world, and on what authority.
##
## ⚠️ **THE BADGE IS THE WHOLE GATE. NO PARTY MEMBER NEEDS TO KNOW THE MOVE.**
## Rob's design call, 2026-08-03, and it is a **deliberate, large divergence from
## source**: hold the Cascade Badge, face a cuttable tree, press A, and the tree
## comes down whether or not anything you own has ever heard of Cut.
##
## What this deletes from source, listed so a later session reading
## `party_menu.c` does not "restore" it as missing work: `SetUpFieldMove_Cut` and
## its siblings, the party-menu entry point, the "Which POKéMON?" selection, the
## per-Pokémon usability scan, and the `{STR_VAR_1} used CUT!` message that names
## the user. **None of that is unfinished — it is designed out.**
##
## ⚠️ **THE OVERWORLD BEHAVIOURS ARE UNTOUCHED.** Rob's framing was "keep the
## overworld behaviours, separate them from the actual moves". The world still
## carries every one of them, measured across all 421 imported Kanto maps:
## 55 cuttable trees / 24 maps, 97 breakable rocks / 15, 58 pushable boulders /
## 16, ~32,900 water cells / ~70, 80 waterfall cells / 4, 15 strength buttons / 8.
## Only the PERMISSION QUESTION changed, from "does someone know the move" to
## "do you hold the badge".
##
## ⚠️ **THE MAPPING BELOW IS SERIES CANON, AUTHORED HERE — IT IS NOT PORTED, AND
## I COULD NOT PORT IT.** Checked directly: the reference has **no badge→HM field
## gating anywhere in C**. `FLAG_BADGE0*_GET` appears only in `event_data.c`'s
## `gBadgeFlags` table and in `battle_util.c`'s obedience ladder; the Route 22/23
## `BoulderBadgeGuard` scripts are map CHECKPOINTS, not field-move gates. So this
## table is written from the games' own canon rather than lifted from source, and
## that distinction matters if it is ever audited against the reference and found
## to have no counterpart there. **Rob expects to edit it** (2026-08-03), which is
## why it is one flat dictionary and nothing reads the pairs any other way.
##
## The badge ORDER is ported and verified — each Kanto gym's own script sets it:
## Pewter 01 · Cerulean 02 · Vermilion 03 · Celadon 04 · Fuchsia 05 · Saffron 06
## · Cinnabar 07 · Viridian 08.

enum Ability { CUT, FLY, SURF, STRENGTH, FLASH, ROCK_SMASH, WATERFALL, DIVE }

const ABILITY_NAME := {
	Ability.CUT: "CUT",
	Ability.FLY: "FLY",
	Ability.SURF: "SURF",
	Ability.STRENGTH: "STRENGTH",
	Ability.FLASH: "FLASH",
	Ability.ROCK_SMASH: "ROCK SMASH",
	Ability.WATERFALL: "WATERFALL",
	Ability.DIVE: "DIVE",
}

## Ability -> the badge flag that grants it.
##
## ⚠️ **DIVE'S ENTRY IS AN INVENTION AND IS THE ONLY ONE.** FRLG has no Dive at
## all — it is Hoenn's HM08 — and **M27E's own scoping measured ZERO Dive cells
## on ZERO of the 421 Kanto maps**: `MB_DEEP_WATER`, `MB_NO_SURFACING`,
## `MB_SEAWEED_NO_SURFACING` and `MB_INTERIOR_DEEP_WATER` are all absent from the
## region. I recommended cutting it; **Rob's call was to keep it in scope**
## (2026-08-03), so it takes the Earth Badge, which canon leaves free because the
## eighth badge governs obedience rather than a field move. Recorded as an
## invention rather than presented as canon, and it currently has nowhere in
## Kanto to be used.
const BADGE_FOR := {
	Ability.FLASH: "FLAG_BADGE01_GET",       # Boulder  — Pewter
	Ability.CUT: "FLAG_BADGE02_GET",         # Cascade  — Cerulean
	Ability.FLY: "FLAG_BADGE03_GET",         # Thunder  — Vermilion
	Ability.STRENGTH: "FLAG_BADGE04_GET",    # Rainbow  — Celadon
	Ability.SURF: "FLAG_BADGE05_GET",        # Soul     — Fuchsia
	Ability.ROCK_SMASH: "FLAG_BADGE06_GET",  # Marsh    — Saffron
	Ability.WATERFALL: "FLAG_BADGE07_GET",   # Volcano  — Cinnabar
	Ability.DIVE: "FLAG_BADGE08_GET",        # Earth    — Viridian (INVENTED)
}


## The only question this class exists to answer.
##
## ⚠️ Takes a `FlagStore` rather than reading `OverworldSession` directly, so a
## test can ask it about a hypothetical badge set without standing up a session —
## and so the field screens and the script VM can both call it with whichever
## store they already hold.
static func can_use(flags: FlagStore, ability: int) -> bool:
	if flags == null or not BADGE_FOR.has(ability):
		return false
	return flags.flag_get(str(BADGE_FOR[ability]))


static func ability_name(ability: int) -> String:
	return str(ABILITY_NAME.get(ability, "?"))


## What the world says when you use one.
##
## ⚠️ **`{PLAYER}` USED IT, NOT A POKéMON — Rob's call, 2026-08-03.** Source
## prints `{STR_VAR_1} used CUT!`, naming the Pokémon that did it. Under this
## project's badge-only gate there IS no such Pokémon, so the subject moves to
## the only actor left: the player. That reads better than the first draft's
## subjectless "Used CUT!" and it costs nothing — `{PLAYER}` is already a real
## placeholder `[M27I I2]` expands, backed by `[M27K K-b]`'s identity.
##
## ⚠️ Returned UNEXPANDED. Every other message in this project reaches the box as
## a template and is expanded at print time, which is what lets a rename take
## effect immediately; expanding here would bake the name in at call time.
## `field_move_streaks`, pulled by `[M27D D1]`, still plays over it.
static func used_message(ability: int) -> String:
	return "{PLAYER} used %s!" % ability_name(ability)


## What it says when you cannot.
##
## ⚠️ Deliberately does NOT name the badge or the gym. Telling the player *which*
## badge unlocks a tree is a hint source never gives and would flatten the
## region's own progression; "not yet" is the whole message.
static func blocked_message(ability: int) -> String:
	return "This needs %s, and you cannot use it yet." % ability_name(ability)
