@tool
class_name NPC
extends OverworldEntity

## [M27B/M27D] A plain overworld person — talks, wanders, blocks a tile.
##
## This is the residual case of source's `object_events` array: an object event
## that is neither a trainer (trainer_type TRAINER_TYPE_NORMAL) nor an item ball
## (an ITEM_BALL graphics id) lands here.

## Source's own OBJ_EVENT_GFX_* constant. This is PLACEMENT data, not identity
## data — the same character can be placed with different graphics, and a
## trainer's registry entry carries only its battle front pic, never this.
@export var graphics_id: String = "OBJ_EVENT_GFX_NONE"

## Source's own MOVEMENT_TYPE_* constant (LOOK_AROUND, WANDER_UP_AND_DOWN,
## FACE_DOWN, ...). Movement itself is M27D's job; the type is imported now so
## the behaviour does not have to be re-derived per NPC later.
@export var movement_type: String = "MOVEMENT_TYPE_NONE"

## Source's own per-map local id, used by its scripts to address this object
## (applymovement, etc.). Blank when the map declares none.
@export var local_id: String = ""

## Wander bounds: a HALF-EXTENT from the spawn cell, per axis.
##
## [M27D D3] 0 means UNCONSTRAINED on that axis, not "cannot move" — source's
## `IsCoordOutsideObjectEventMovementRange` skips the check entirely for a zero
## range. Reading it as a zero-size box would pin every such NPC in place.
@export var range_x: int = 0
@export var range_y: int = 0

## Which directions this movement type may choose from, and whether choosing
## one also STEPS.
##
## Source spreads the four behaviours across separate function tables, but they
## are one state machine with two parameters — `MovementType_LookAround_Step4`
## and `MovementType_FaceDownAndUp_Step4` differ only in the direction table
## they memcpy, and `MovementType_WanderAround_Step4` differs only in going on
## to walk. Reproducing that as four behaviours would be reproducing the
## table layout rather than the mechanic.
const _ALL := [StepResolver.Dir.SOUTH, StepResolver.Dir.NORTH,
		StepResolver.Dir.WEST, StepResolver.Dir.EAST]
const _UP_DOWN := [StepResolver.Dir.SOUTH, StepResolver.Dir.NORTH]
const _LEFT_RIGHT := [StepResolver.Dir.WEST, StepResolver.Dir.EAST]

## sMovementDelaysMedium, in SECONDS rather than frames.
##
## Source is 60fps-locked so {32, 64, 96, 128} frames is fixed wall-clock time;
## this project is not, and [M26G4] measured frame-tied stepping running ~10%
## slow at 144Hz and half speed at 30Hz. Same conversion the ball-particle
## stagger already needed.
const _DELAYS := [32.0 / 60.0, 64.0 / 60.0, 96.0 / 60.0, 128.0 / 60.0]

var _spawn_cell := Vector2i.ZERO
var _facing := StepResolver.Dir.SOUTH
var _delay := 0.0
var _spawned := false


## The directions this NPC may turn to, or [] if it never turns.
func direction_choices() -> Array:
	if movement_type.begins_with("MOVEMENT_TYPE_FACE_DOWN_AND_UP") \
			or movement_type == "MOVEMENT_TYPE_WANDER_UP_AND_DOWN":
		return _UP_DOWN
	if movement_type.begins_with("MOVEMENT_TYPE_FACE_LEFT_AND_RIGHT") \
			or movement_type == "MOVEMENT_TYPE_WANDER_LEFT_AND_RIGHT":
		return _LEFT_RIGHT
	if movement_type == "MOVEMENT_TYPE_LOOK_AROUND" \
			or movement_type == "MOVEMENT_TYPE_WANDER_AROUND":
		return _ALL
	return []


## Does choosing a direction also take a step?
func wanders() -> bool:
	return movement_type.begins_with("MOVEMENT_TYPE_WANDER")


## Is `cell` inside this NPC's wander box?
func within_range(c: Vector2i) -> bool:
	if range_x != 0 and absi(c.x - _spawn_cell.x) > range_x:
		return false
	if range_y != 0 and absi(c.y - _spawn_cell.y) > range_y:
		return false
	return true


func spawn_cell() -> Vector2i:
	return _spawn_cell


func facing() -> int:
	return _facing


## Point the sprite a new way. Cheap: the sheet is one texture and only the
## region and the mirror change.
func set_facing(dir: int) -> void:
	_facing = dir
	var spr := get_node_or_null("Sprite") as Sprite2D
	if spr == null:
		return
	var name_by_dir := {
		StepResolver.Dir.SOUTH: "SOUTH", StepResolver.Dir.NORTH: "NORTH",
		StepResolver.Dir.WEST: "WEST", StepResolver.Dir.EAST: "EAST",
	}
	var facing_name: String = name_by_dir.get(dir, "SOUTH")
	var frame: int = int(ObjectEventGraphics.FACE_FRAME.get(facing_name, 0))
	spr.region_rect = Rect2(frame * spr.region_rect.size.x, 0,
			spr.region_rect.size.x, spr.region_rect.size.y)
	spr.flip_h = facing_name == "EAST" and ObjectEventGraphics.EAST_IS_MIRRORED_WEST


## One frame of this NPC's own movement. Returns the cell it wants to move to,
## or its current cell to stay put.
##
## Ported from the shared Wander/LookAround step chain: face, wait a random
## delay, choose a direction, then either just turn (LookAround, Face*And*) or
## also walk (Wander*). A blocked wander turns without moving, which is source's
## own `if (GetCollisionInDirection(...)) sTypeFuncId = 1`.
func tick(delta: float, rng: RandomNumberGenerator) -> Vector2i:
	if not _spawned:
		_spawned = true
		_spawn_cell = cell
		_facing = _facing_from_movement_type()
	var choices := direction_choices()
	if choices.is_empty():
		return cell
	_delay -= delta
	if _delay > 0.0:
		return cell
	_delay = _DELAYS[rng.randi() % _DELAYS.size()]
	var dir: int = choices[rng.randi() % choices.size()]
	set_facing(dir)
	if not wanders():
		return cell
	return cell + StepResolver.STEP[dir]


func _facing_from_movement_type() -> int:
	match initial_facing():
		"NORTH": return StepResolver.Dir.NORTH
		"WEST": return StepResolver.Dir.WEST
		"EAST": return StepResolver.Dir.EAST
	return StepResolver.Dir.SOUTH


## `movement_type` is a free-text String, and retyping it in the inspector is
## the fastest way to turn a rotating trainer into a fixed-facing one. That
## makes a typo cheap to introduce and, without this, invisible: MapOverlay's
## events mode draws sight lines off this string, so a misspelling silently
## removes the trainer's ray, which looks identical to a trainer who correctly
## has none. Checked against the generated set rather than a hand-kept list.
func _get_configuration_warnings() -> PackedStringArray:
	var out := super()
	if movement_type != "" and not MovementTypes.is_known(movement_type):
		out.append("movement_type '%s' is not a type source defines — typo?"
				% movement_type)
	return out


func sprite_graphics_id() -> String:
	return graphics_id


## MOVEMENT_TYPE_FACE_* names the direction outright; everything else rests
## facing south, matching source's own ANIM_STD_FACE_SOUTH default.
##
## The FACE_x_AND_y and WANDER types start on their first direction and change
## later — that is D3's job, not a starting-facing question.
func initial_facing() -> String:
	for d in ["DOWN", "UP", "LEFT", "RIGHT"]:
		if movement_type.begins_with("MOVEMENT_TYPE_FACE_" + d):
			return {"DOWN": "SOUTH", "UP": "NORTH", "LEFT": "WEST", "RIGHT": "EAST"}[d]
	return "SOUTH"
