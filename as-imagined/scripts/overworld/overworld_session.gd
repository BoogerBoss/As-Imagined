class_name OverworldSession
extends RefCounted

## [M27D D5] The overworld state that must survive a battle.
##
## Starting a battle is a `change_scene_to_file`, which FREES the overworld —
## `MapManager`, every loaded chunk, the player's cell and facing, and (before
## this) the `FlagStore` D4 put on `overworld.gd` as an instance var. So the
## things that define "where you were" have to live outside the scene tree.
##
## Class-level statics, no autoload, matching `BattleSetupContext` — the same
## problem solved the same way, deliberately, rather than inventing a second
## mechanism for it.
##
## WHY A SCENE SWAP AND NOT AN OVERLAY. Keeping the overworld alive underneath
## the battle would avoid rebuilding it, and `[M25h-1.4]` set that precedent for
## the Bag screen. Two things argue the other way here: `battle_screen.tscn` is
## ~6,900 lines written to be a top-level scene, and — measured on Rob's machine
## — a chunk rebuild costs 66-100 ms, which SOURCE ITSELF hides behind a fade
## (`CB2_ReturnToFieldContinueScriptPlayMapMusic` fades in from the battle). So
## the rebuild is both affordable and authentic, and the overlay's cost is not.


## Persistent flags and vars: beaten trainers, hidden entities, trigger gates.
## Created once, never replaced, so a reference taken before a battle is still
## valid after one.
static var flags := FlagStore.new()

## Where to put the player when the overworld next loads, or empty for "use the
## scene's own start_map". Written when a battle starts, consumed on return.
static var pending_return: Dictionary = {}

## The result of the battle just fought, or null. Consumed by the overworld on
## return so the win/loss consequences are applied exactly once.
static var pending_result: BattleOutcome = null

## Which trainer the pending battle is against. Held here rather than widening
## battle_screen_shared's own state: the overworld already knows, and the battle
## screen has no reason to learn.
static var pending_trainer_key: String = ""


## Record where the player is standing, before a battle frees the overworld.
static func save_position(map_name: String, cell: Vector2i, facing: int,
		elevation: int, trainer_key: String = "") -> void:
	pending_trainer_key = trainer_key
	pending_return = {
		"map": map_name,
		"cell": cell,
		"facing": facing,
		"elevation": elevation,
	}


static func has_pending_return() -> bool:
	return not pending_return.is_empty()


## Take the saved position and clear it, so a later boot does not silently
## resume a stale one. Same consume-on-read shape as `BattleSetupContext`.
static func take_return() -> Dictionary:
	var r := pending_return.duplicate()
	pending_return = {}
	return r


static func set_result(r: BattleOutcome) -> void:
	pending_result = r


static func take_result() -> BattleOutcome:
	var r := pending_result
	pending_result = null
	return r


## Tests only. Production never wants this — the flags ARE the save.
static func reset() -> void:
	flags = FlagStore.new()
	pending_return = {}
	pending_result = null
	pending_trainer_key = ""
