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


static func set_pending(p_player_party: BattleParty, p_opp_party: BattleParty) -> void:
	player_party = p_player_party
	opp_party = p_opp_party


static func has_pending() -> bool:
	return player_party != null and opp_party != null


static func clear() -> void:
	player_party = null
	opp_party = null
