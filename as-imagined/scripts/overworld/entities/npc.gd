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

## [M27F Stage 3b] This NPC's own walk-cycle clock. Per-instance and free-running
## across steps — see WalkAnim's header for why sharing or resetting it would
## make every walker lead with the same foot.
var _anim := WalkAnim.new()


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


## Point the sprite a new way, at rest. Cheap: the sheet is one texture and
## only the region and the mirror change.
##
## [M27F Stage 3b] Routed through the same [WalkAnim] the walk cycle uses, so
## "standing still facing west" and "mid-stride facing west" cannot drift into
## two different ideas of which frame that is.
func set_facing(dir: int) -> void:
	_facing = dir
	var spr := get_node_or_null("Sprite") as Sprite2D
	if spr == null:
		return
	_anim.setup(graphics_id)
	_anim.rest(spr, WalkAnim.facing_name(dir))


## One tick of this NPC's walk cycle, driven by [MovementRunner].
##
## Separate from [method set_facing] because they mean different things: this
## ADVANCES the cycle, that one parks it. The runner calls this every frame a
## walking action is in flight and calls `set_facing` once when the whole
## movement script ends.
func step_anim(dir: int, ticks: int, delta: float) -> void:
	_facing = dir
	var spr := get_node_or_null("Sprite") as Sprite2D
	if spr == null:
		return
	_anim.setup(graphics_id)
	_anim.step(spr, WalkAnim.facing_name(dir), ticks, delta)


## [M27R Step 1] Show one RAW sheet frame, for a bespoke animation the
## facing/walk-cycle vocabulary cannot express — today only the nurse's bow.
##
## ⚠️ **RAW, not a pic-table index.** `ANIM_NURSE_BOW` quotes frame 9 of
## `sPicTable_Nurse`, which is a ten-entry table over a FOUR-frame sheet, and
## entry 9 resolves to raw frame 3. The caller does that translation (see
## `MovementRunner`'s own table); this takes the answer.
func show_frame(raw_index: int) -> void:
	var spr := get_node_or_null("Sprite") as Sprite2D
	if spr == null:
		return
	_anim.setup(graphics_id)
	_anim.show_raw(spr, raw_index)


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
		_facing = facing_from_movement_type()
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


## [Bugfix, live-reported: Oak stays facing north through his starter speech]
## PUBLIC because `setobjectmovementtype` needs it too — source's own retype
## lands its facing when the object next spawns from its template, and this is
## the equivalent. It used to be private and called from exactly one place
## (`tick`'s first-run branch), which is why a mid-cutscene retype changed the
## string and nothing else.
func facing_from_movement_type() -> int:
	match initial_facing():
		"NORTH": return StepResolver.Dir.NORTH
		"WEST": return StepResolver.Dir.WEST
		"EAST": return StepResolver.Dir.EAST
	return StepResolver.Dir.SOUTH


## [M27Q Q2] Make `movement_type` a DROPDOWN instead of a text field.
##
## ⚠️ **THIS MAKES THE TYPO THE WARNING BELOW CATCHES UNREPRESENTABLE.** The
## warning stays — it still fires for a value typed before this landed, or set
## from code, or arriving from an older baked scene — but the Inspector can no
## longer produce one.
##
## The hint is built from `MovementTypes.ALL`, which is GENERATED from
## `include/constants/event_object_movement.h` (89 types), so the list cannot
## drift from source: regenerating the constants regenerates the dropdown. Same
## single-table discipline as `TrainerAI.FLAG_TABLE`.
##
## ⚠️ The property stays a `String` and stores the constant NAME, not an index.
## An index would be a second encoding of a value the whole project passes
## around as text (`MovementTypes.FIXED_FACING` is keyed by it, `map_baker`
## writes it, `begins_with("MOVEMENT_TYPE_WANDER")` reads it), and it would
## silently reinterpret every baked scene the moment the generated order
## changed.
func _validate_property(property: Dictionary) -> void:
	if property.name == "movement_type":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(MovementTypes.ALL)


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
