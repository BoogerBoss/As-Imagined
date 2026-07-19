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


static func set_pending(p_player_party: BattleParty, p_opp_party: BattleParty,
		p_is_doubles: bool = false, p_background_id: String = "") -> void:
	player_party = p_player_party
	opp_party = p_opp_party
	is_doubles = p_is_doubles
	background_id = p_background_id


static func has_pending() -> bool:
	return player_party != null and opp_party != null


static func clear() -> void:
	player_party = null
	opp_party = null
	is_doubles = false
	background_id = ""
