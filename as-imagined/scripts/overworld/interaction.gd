class_name Interaction
extends RefCounted

## [M27F Stage 1] What a press of A targets.
##
## Ported from `GetInteractionScript` (`field_control_avatar.c:308`), which tries
## four sources in strict order and takes the first non-null:
##
##     1. object event   (npc / trainer / item ball)
##     2. background event (signs)
##     3. metatile        (behaviour-driven: PC, bookshelf, TV, ...)
##     4. water           (surf prompts)
##
## Stage 1 implements 1 and 2. Sources 3 and 4 are later stages; that they sit
## BEHIND object and background events is why the 31 `readable` metatile
## behaviours only ever fire on a tile nothing else claims.
##
## ⚠️ THE COUNTER HOP. `ProcessPlayerFieldInput` computes the FACED tile, then:
##
##     if (!MetatileBehavior_IsCounter(behaviorAt(position)))
##         objectEventId = GetObjectEventIdByPosition(position.x, position.y, elev);
##     else
##         objectEventId = GetObjectEventIdByPosition(position.x + dir.x,
##                                                    position.y + dir.y, elev);
##
## If the faced tile is MB_COUNTER, the search moves ONE TILE FURTHER — that is
## how you talk to a shopkeeper across a counter. MB_COUNTER is 729 cells across
## 89 corridor maps, so without this every Poké Mart clerk, Pokécentre nurse and
## gym receptionist is unreachable. A naive "check the faced tile" reads as
## correct everywhere outdoors and fails in every shop.
##
## Returns a Dictionary rather than a script label so the caller knows WHAT it
## hit, not just what to run — the message box needs the entity to face, and the
## debug overlay needs to say which source claimed the tile.


const NONE := ""
const SOURCE_OBJECT := "object_event"
const SOURCE_BACKGROUND := "background_event"


## Resolve a press of A.
##
## `cells` supplies terrain (`behavior_at`); `entity_at_cell` returns the entity
## occupying a global cell, or null. Both are injected so this is testable
## without a MapManager or a scene.
##
## Returns:
##   {"source": ..., "entity": OverworldEntity, "script": String, "cell": Vector2i}
## or an empty Dictionary when nothing is there.
static func resolve(from: Vector2i, dir: int, behavior_at: Callable,
		entity_at_cell: Callable) -> Dictionary:
	if not StepResolver.STEP.has(dir):
		return {}
	var step: Vector2i = StepResolver.STEP[dir]
	var target: Vector2i = from + step

	# The counter hop, before anything else looks at the tile.
	if int(behavior_at.call(target)) == MetatileBehavior.MB_COUNTER:
		target += step

	# 1. object events first — an NPC standing on a sign tile answers, not the sign.
	var e = entity_at_cell.call(target)
	if e != null and (e is NPC or e is ItemBall):
		return {
			"source": SOURCE_OBJECT,
			"entity": e,
			"script": (e as OverworldEntity).script_label,
			"cell": target,
		}

	# 2. background events. A sign may require being approached from one side.
	if e != null and e is Sign:
		var sign := e as Sign
		if not _facing_satisfies(sign.facing, dir):
			return {}
		return {
			"source": SOURCE_BACKGROUND,
			"entity": sign,
			"script": sign.script_label,
			"cell": target,
		}

	return {}


## Source's `BgEvent.kind` gate. The player's direction is the way they are
## WALKING; a sign that requires FACING_NORTH means the player must be pressing
## north into it, which is the same direction the step would have taken.
static func _facing_satisfies(required: String, dir: int) -> bool:
	match required:
		"BG_EVENT_PLAYER_FACING_NORTH":
			return dir == StepResolver.Dir.NORTH
		"BG_EVENT_PLAYER_FACING_SOUTH":
			return dir == StepResolver.Dir.SOUTH
		"BG_EVENT_PLAYER_FACING_EAST":
			return dir == StepResolver.Dir.EAST
		"BG_EVENT_PLAYER_FACING_WEST":
			return dir == StepResolver.Dir.WEST
	# BG_EVENT_PLAYER_FACING_ANY, and anything unrecognised. Source's own switch
	# defaults to returning the script, so an unknown kind is permissive rather
	# than silently unreachable.
	return true
