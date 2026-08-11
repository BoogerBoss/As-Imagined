class_name BattleSetupContext
extends RefCounted

# [M23.6] The hand-off point between battle_setup_screen.gd and
# battle_screen.gd. GDScript class-level `static var`s persist for the
# whole process regardless of scene tree (the same mechanism MoveNameMap's
# own lazy-loaded cache already relies on, `[M23.4]`) — no autoload/Node
# registration needed, so this stays a plain RefCounted utility class
# matching PokemonFactory/MovepoolResolver/TeamStorage's own established
# shape, rather than adding a new project.godot [autoload] entry for a
# single one-shot hand-off.
#
# Usage: battle_setup_screen.gd calls `set_pending(player, opp)` then
# `get_tree().change_scene_to_file("res://scenes/battle/battle_screen
# .tscn")`. The freshly-instantiated battle_screen.gd's own `_ready()`
# checks `has_pending()` first thing, consumes (and clears) the two
# parties if present, and only falls back to its own hardcoded
# Blaze/Torrent-vs-Leaf/Volt fixture teams when nothing is pending — the
# exact case for every pre-existing direct launch of battle_screen.tscn
# (the --autoplay sweep test included).

static var player_party: BattleParty = null
static var opp_party: BattleParty = null

# [M23.11 Phase 4f] Doubles flag — added so battle_screen.gd's _ready() can
# call BattleManager.start_battle_doubles() instead of the singles-only
# start_battle_with_parties() when the hand-off parties are doubles-shaped
# (active_indices = [0, 1]). Optional, defaults false — every pre-existing
# caller (battle_setup_screen.gd's own singles-only Launch button, which
# stays that way this session; see docs/m23_recon.md's Phase 4f entry for
# why the Doubles toggle itself is NOT re-enabled here) is unaffected.
static var is_doubles: bool = false

## [M27H H4] Catch inputs the battle engine cannot know on its own — badge count
## lives in the overworld's flag store, party room is an overworld question.
static var badge_count: int = 0
static var party_has_room: bool = true

# [M23.11 Phase 5a] The manually-picked battle background id (a
# BattleBackgroundRegistry key, e.g. "rock" — see battle_background
# _registry.gd), or "" for unset. Optional, defaults to "" so every
# pre-existing caller (this file's own prior callers, plus every direct/
# --autoplay launch of battle_screen.tscn that never goes through
# battle_setup_screen.gd at all) is unaffected — battle_screen.gd's own
# _ready() falls back to a fixed default background when this is empty,
# matching how it already falls back to its own hardcoded fixture teams
# when has_pending() is false.
static var background_id: String = ""

# [M26l] Optional opponent TrainerData id (TrainerRegistry space, not
# TrainerPicRegistry's), or ""
# for unset. Optional, defaults -1 so every pre-existing caller (which never
# picks a trainer identity today — battle_setup_screen.gd has no trainer
# concept at all) is unaffected and battle_screen.gd's _ready() skips the
# intro-banner entirely, matching how it already skips when has_pending()
# is false.
static var opp_trainer_key: String = ""

## [M27H H5 fix] Is this battle being run FROM THE OVERWORLD?
##
## ⚠️ **THE CONTEXT IS THE ONLY THING RELIABLY SET BEFORE THE SCREEN'S `_ready`,
## WHICH IS WHY THIS LIVES HERE.** `overlay_mode` is assigned by the overworld
## AFTER `add_child()` — and `add_child` is what fires `_ready` — so reading it
## during setup answers false for every battle. `OverworldSession
## .has_pending_return()` was used instead and is false too, for a different
## reason: the overlay design deliberately saves no position ("the overworld
## STAYS ALIVE underneath"). Two plausible-looking signals, both wrong at the
## one moment they were being read.
static var is_overworld_battle: bool = false

## [M36 bench] Make the opponent pick moves at random rather than by score.
## ⚠️ Set ONLY by the setup screen's own checkbox. An overworld trainer must
## never get this — `set_pending`'s overworld caller does not touch it, and it
## is reset alongside everything else so a bench battle cannot leak into the
## next real one.
static var ai_random_moves: bool = false

## ⚠️ **[Bugfix, live-reported: "if Gary wins he doesn't say his alternate
## dialogue"] THE TRAINER'S OWN POST-BATTLE SPEECH, BOTH DIRECTIONS.**
## `defeat_pages` is what the trainer says when the PLAYER WINS
## (`GetTrainerLoseText`); `victory_pages` is what they say when the player
## loses (`GetTrainerWonSpeech`). Named after whose defeat/victory it is, which
## is source's own naming and reads backwards until you know that.
##
## ⚠️ **ALREADY EXPANDED.** `{RIVAL}`/`{PLAYER}` resolve against the running
## script's own text buffers, and the battle screen has none — so the overworld
## substitutes before handing over rather than passing labels the screen could
## not resolve. Empty for every wild, fixture and simulator battle, which is
## what keeps those paths silent exactly as before.
static var script_defeat_pages: PackedStringArray = PackedStringArray()
static var script_victory_pages: PackedStringArray = PackedStringArray()

## ⚠️ `BATTLE_TYPE_FIRST_BATTLE` — Oak narrates this one. Set only by an
## `trainerbattle_earlyrival` carrying `RIVAL_BATTLE_TUTORIAL`, which in the
## whole corridor is the three Oak's-Lab rival battles and nothing else.
static var first_battle_tutorial: bool = false

## Will losing this battle actually white the player out?
##
## ⚠️ **NOT THE SAME QUESTION AS "DID THE PLAYER LOSE", AND SOURCE ASKS IT
## SEPARATELY.** `BattleScript_LocalBattleLost` reaches its whiteout block
## through `jumpifnowhiteout` (`data/battle_scripts_1.s:2912`), so a rival fight
## you are MEANT to lose prints none of those lines — it heals you and the
## script carries on. This project already models that as
## `ScriptVM.pending_battle_heal_after`, consulted by the overworld on the
## battle-RETURN path; the battle screen needs the same answer BEFORE then, to
## decide whether to narrate a whiteout at all, and it cannot reach the VM.
##
## Defaults TRUE so every ordinary battle — wild, trainer, simulator — narrates
## normally, and only a caller that deliberately sets it false opts out.
static var whiteout_on_loss: bool = true

## The player's highest party level at battle entry, for the whiteout payout
## line the screen prints.
##
## ⚠️ CAPTURED AT ENTRY, NOT DERIVED AT PRINT TIME, and deliberately the SAME
## number the overworld will later charge against. `overworld._mount_battle`
## already snapshots this into `_battle_party_level` and hands it to
## `BattleOutcome` on the way back out; passing that same snapshot in means the
## line the player reads and the money they actually lose cannot disagree, which
## is the entire point of routing both through
## `OverworldSession.whiteout_payout`.
static var party_level: int = 1


static func set_pending(p_player_party: BattleParty, p_opp_party: BattleParty,
		p_is_doubles: bool = false, p_background_id: String = "",
		p_opp_trainer_key: String = "",
		p_is_overworld_battle: bool = false) -> void:
	player_party = p_player_party
	opp_party = p_opp_party
	is_doubles = p_is_doubles
	background_id = p_background_id
	opp_trainer_key = p_opp_trainer_key
	is_overworld_battle = p_is_overworld_battle


static func has_pending() -> bool:
	return player_party != null and opp_party != null


static func clear() -> void:
	player_party = null
	opp_party = null
	is_doubles = false
	background_id = ""
	opp_trainer_key = ""
	is_overworld_battle = false
	ai_random_moves = false
	# ⚠️ Cleared like everything else, so one rival's speech cannot surface at
	# the end of an unrelated later battle — the same leak `pending_battle_
	# heal_after` already guards against one layer up.
	script_defeat_pages = PackedStringArray()
	script_victory_pages = PackedStringArray()
	first_battle_tutorial = false
	whiteout_on_loss = true
	party_level = 1
