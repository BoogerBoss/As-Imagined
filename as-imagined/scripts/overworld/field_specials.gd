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
##
## [M27G G1] `DisableMsgBoxWalkaway`/`SetWalkingIntoSignVars` — NOT a
## simplification either: source's own bodies (`script.c:685-692`) are each a
## single COMMENTED-OUT line. The reference ships these two already inert; a
## no-op here is a port of the real function, not a stand-in for one.
## `OpenMuseumFossilPic`/`CloseMuseumFossilPic` — the same "no field picture
## layer" no-op class `[M27K K-a]` already established for `showmonpic`/
## `hidemonpic`; a no-op loses the flourish (Pewter Museum's fossil-pic
## viewer), not the scene. Found via `docs/m27g_recon.md`'s own corridor
## reachability walk.
## [M27G G3a] `DoInGameTradeScene` — deliberately a no-op here, NOT a
## simplification of a small function. `CreateInGameTradePokemon` (dispatched
## directly in `ScriptVM`, since it needs `party`) already does the real
## work — this one is PURE presentation in source, and what it actually
## presents is the full link-trade cinematic engine (`Task_InGameTrade` ->
## `CB2_InitInGameTrade` -> `CB2_InGameTrade`, `src/trade.c:4862-4867,
## 2958-3054`), reused verbatim with `isLinkTrade = FALSE` — ball-bounce,
## GBA screen zoom/flash, cable-end sprites, a mon-crossing animation. G3b
## (deferred, Rob's call) reuses `[M26B3]`'s already-built ball recall/
## send-out primitives for a real visual beat instead of porting that
## cable-trade spectacle faithfully — see `docs/m27g_recon.md`'s own G3
## Step 0 section for the reasoning.
## ⚠️ **[Bugfix, live-reported: "I can deliver Oak's parcel and trigger the
## Pokédex speech indefinitely" / "didn't get given Poké Balls" / "the parcel
## delivery flag never lands"] `SetUnlockedPokedexFlags` IS NOT A POKÉDEX
## FUNCTION, DESPITE ITS NAME — and `docs/m27_corridor_opcode_scope.md` §33-34
## filing it under "M33 (Pokédex)" alongside `GetFrlgPokedexCount` and
## `HasAllMons` is the mistake this entry corrects.** Its whole body
## (`save_location.c:125-143`) sets three bits of `gSaveBlock2Ptr->gcnLinkFlags`
## and nothing else, and `global.h:610` annotates that field "Read by Pokémon
## Colosseum/XD". Greppped the entire reference: the field is written in exactly
## three places (here, `SetPostgameFlags`, `new_game.c`'s zeroing) and READ in
## exactly one — `rom_header_gf.c`, which only publishes its byte offset so a
## GameCube game can find it in the save. **No GBA code path ever reads it.**
## GCN linking sits inside the same permanent link/Union-Room exclusion
## `BufferUnionRoomPlayerName` below is already justified by, so this is a
## genuine no-op in the `DisableMsgBoxWalkaway` sense — a port of a function
## with no local effect, not a stand-in for one.
##
## It mattered far out of proportion to that. It sits mid-way through
## `PalletTown_ProfessorOaksLab_EventScript_ReceiveDexScene`, so halting on it
## stranded the script at pc=73 with `FLAG_SYS_POKEDEX_GET` already set but
## every consequence still ahead of it: the five Poké Balls (the ONLY Poké Ball
## gift in the Kanto corpus), and the five `setvar`s that advance
## `VAR_MAP_SCENE_PALLET_TOWN_PROFESSOR_OAKS_LAB` to 6 and open the Viridian
## mart, the old man, the rival's house and Route 22. With none of those
## landing, `EventScript_ProfOak`'s `goto_if_ge VAR_MAP_SCENE_VIRIDIAN_CITY_MART,
## 1` stayed satisfied and the whole scene replayed on every talk, forever.
## One unimplemented no-op, four reported symptoms, and a soft-locked corridor.
const NOOP_SPECIALS := [
	"UpdateFollowingPokemon",
	"DrawWholeMapView",
	"DisableMsgBoxWalkaway",
	"SetWalkingIntoSignVars",
	"OpenMuseumFossilPic",
	"CloseMuseumFossilPic",
	"DoInGameTradeScene",
	"SetUnlockedPokedexFlags",
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
## ⚠️ **THE ADMISSION RULE, RESTATED 2026-08-13 — AND THE OLD WORDING WAS
## ALREADY DESCRIBING ITSELF WRONGLY.** It read: "Every entry is a **1-2 use**
## function region-wide — a short tail being closed, not a policy." Use count
## was never the real criterion, and three of the original five entries fail it
## on their own stated reasoning: `IsPokerusInParty` ("Pokerus is not
## modelled"), `BufferUnionRoomPlayerName` ("link ... is a confirmed permanent
## exclusion") and `CountPlayerTrainerStars` ("no trainer card exists here") are
## admitted because their answer is INVARIANT under a documented project
## exclusion, not because they are rare.
##
## The honest rule, which is what this table has actually been enforcing:
##
##   1. the value is the function's REAL return in this project, derived by
##      reading its body — never a convenient one that happens to work; and
##   2. it is a CONSTANT here, because either the system it interrogates is
##      permanently excluded, or the geography/state it tests cannot occur.
##
## Anything needing live state belongs in `ScriptVM` beside
## `ScriptGetPartyMonSpecies` (which is where `CalculatePlayerPartyCount` and
## `GetLeadMonFriendship` went), and anything needing a system this project
## intends to build stays halting so the gap keeps reporting itself.
##
## ⚠️ Under the old wording `ShouldTryRematchBattle` would have been refused for
## being too common — it is the second opcode of essentially every trainer
## script in Kanto. That would have been exactly backwards: it is the single
## most load-bearing entry here, and admitting it fixes a live bug (see its own
## note). Rarity was a proxy for "small enough not to matter"; invariance is the
## property that was actually doing the work.
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
	# ⚠️ **[Bugfix, live-reported class: every already-beaten trainer in the
	# corridor is MUTE.] THIS ONE IS NOT A TIDY-UP — IT IS THE HIGHEST-TRAFFIC
	# HALT IN THE FIELD ENGINE.** `specialvar VAR_RESULT,
	# ShouldTryRematchBattle` is the opcode IMMEDIATELY AFTER
	# `trainerbattle_single` in the standard trainer script shape — all 8 of
	# Route 3's trainers, Lass Robin included, and essentially every trainer in
	# Kanto. `_trainer_battle`'s own contract is that an ALREADY-BEATEN trainer
	# falls through to the next opcode, so re-talking to any trainer you have
	# already defeated halted the script here and their post-battle line
	# (`message Route3_Text_RobinPostBattle`, two opcodes later) had never once
	# printed.
	#
	# 0 is source's own answer here, not a stand-in. `ShouldTryRematchBattle` ->
	# `ShouldTryRematchBattleForTrainerId` -> `IsFirstTrainerIdReadyForRematch(
	# gRematchTable, id) || WasSecondRematchWon(gRematchTable, id)`
	# (`battle_setup.c:2060-2071`). Both read MUTABLE rematch state, and
	# `TrainerData`'s own header records that as an explicit project exclusion:
	# "any MUTABLE 'has this trainer been beaten / rematch state' field —
	# rematch_group_id/rematch_tier below are static source data only". Nothing
	# can ever register a rematch, so FALSE is not merely true today, it is
	# structurally guaranteed — the same shape as the two entries above.
	"ShouldTryRematchBattle": [0, "rematch state is an explicit TrainerData exclusion, so no rematch can ever be registered"],
	# `CheckPartyMonHasHeldItem(ITEM_ENIGMA_BERRY_E_READER)`
	# (`script_pokemon_util.c:108`). The e-Reader Enigma Berry is not in this
	# project's implemented item set — `items.json` lists it, no `.tres` backs
	# it, and per the two-layer data rule the file's absence IS the answer — so
	# no party member can ever hold one.
	"DoesPartyHaveEnigmaBerry": [0, "the e-Reader Enigma Berry has no .tres, so it is unobtainable and unholdable here"],
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
