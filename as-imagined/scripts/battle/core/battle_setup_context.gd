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
