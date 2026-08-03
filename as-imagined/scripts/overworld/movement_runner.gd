class_name MovementRunner
extends RefCounted

## [M27F Stage 3] THE ONE ENTITY-MOTION SYSTEM.
##
## Two consumers, deliberately sharing one runner rather than growing a second
## path beside the first:
##
##   * `applymovement` — scripted, authored, timed movement.
##   * NPC wandering — which until now TELEPORTED. `OverworldEntity.cell` is a
##     setter that snaps `position` (`overworld_entity.gd:21`), so D3's
##     `move_entity()` moved the sprite in one frame. Measured on a real
##     wandering NPC: 6 moves, every per-frame delta exactly 16.0 px = one CELL,
##     zero intermediate values. D3 built the movement LOGIC correctly and the
##     visual half was simply never built — no test could have caught it,
##     because every assertion there is on cells, not pixels.
##
## ⚠️ **SCRIPTED MOVEMENT IGNORES COLLISION.** `MovementAction_WalkNormalDown_Step0`
## calls `InitMovementNormal` with no check of any kind
## (`event_object_movement.c:7346`). Authored movement is authored — routing it
## through `StepResolver` the way a player step and NPC wandering both do would
## be wrong, and would silently strand cutscenes on terrain the author meant to
## walk over. The WANDERING consumer still resolves first; it just hands the
## already-approved destination here to be animated.
##
## ⚠️ **THE `cell` SETTER FIGHTS ANY TWEEN.** Assigning `cell` snaps `position`
## to the destination, so a mover cannot set the cell and then animate from
## where it used to be. The order here is: capture the old pixel, commit the
## cell (occupancy updates synchronously, which is D3's invariant and worth
## keeping — two NPCs must never claim one tile in a frame), read the new pixel
## the setter just wrote, then REWIND `position` and interpolate it ourselves.
##
## Motion is interpolated against WALL CLOCK, not `process_frame`. [M26G4]
## measured frame-tied stepping running ~10% slow at 144 Hz and half speed at
## 30 Hz, and every discrete stepper in this project has had to learn that once.


const FRAME := 1.0 / 60.0

## Per-tile frame counts, read straight off source's own step tables
## (`event_object_movement.c:10728`): `sStepTimes[speed] = ARRAY_COUNT(sStepNFuncs)`,
## and those arrays are 16 / 8 / 6 / 4 / 2 entries long.
##
## ⚠️ FAST_2 is SIX frames, not 16/3. Its table is `{2,3,3,2,3,3}` — a
## non-uniform pixel walk that sums to 16. Nothing in this project uses that
## speed yet; the number is recorded so a future "16 divided by the speed"
## shortcut is visibly wrong rather than plausibly wrong.
## SLOW is 32, not a fraction of NORMAL: `UpdateWalkSlowAnim` moves one pixel
## only on EVEN frames (`if (!(sprite->sTimer & 1))`) and finishes after 16
## such steps, so the walk costs exactly twice a normal one.
const FRAMES_SLOW := 32
const FRAMES_NORMAL := 16
const FRAMES_FAST := 8
const FRAMES_FAST_2 := 6
const FRAMES_FASTER := 4
const FRAMES_FASTEST := 2

const _DIRS := {
	"up": StepResolver.Dir.NORTH,
	"down": StepResolver.Dir.SOUTH,
	"left": StepResolver.Dir.WEST,
	"right": StepResolver.Dir.EAST,
}

static var _actions: Dictionary = {}


## One in-flight movement. `key` is whatever the caller identifies a mover by —
## the entity node for a placed entity, the string "player" for the player.
class Active extends RefCounted:
	var node: Node2D
	var ops: Array = []
	var index := 0
	var elapsed := 0.0
	var duration := 0.0
	var from_px := Vector2.ZERO
	var to_px := Vector2.ZERO
	var commit: Callable      ## commit(dir) -> void: do the logical move, leaving node.position AT the destination
	var face: Callable        ## face(dir) -> void
	var unknown := ""         ## the action name that stopped this mover, if any
	var facing_locked := false
	var anim: Callable        ## anim(facing_dir, ticks, delta) -> void, while walking
	var rest: Callable        ## rest(facing_dir) -> void, once the whole script ends
	var anim_ticks := 0       ## cycle-entry length of the CURRENT action, 0 = not animating
	var anim_dir := -1        ## direction the current action animates in


var _active: Dictionary = {}
var _last_unknown := ""


## The action table, built once. Generated rather than hand-written: the four
## direction suffixes cross three speeds across three families, and forty
## hand-typed rows is forty chances to transpose one.
static func _build() -> void:
	var t := {}
	for suffix in _DIRS:
		var dir: int = _DIRS[suffix]
		# Real steps.
		var n := ObjectEventGraphics.ANIM_TICKS_NORMAL
		var f := ObjectEventGraphics.ANIM_TICKS_FAST
		var r := ObjectEventGraphics.ANIM_TICKS_FASTER
		t["walk_" + suffix] = {"dir": dir, "frames": FRAMES_NORMAL, "moves": true, "anim": n}
		t["walk_fast_" + suffix] = {"dir": dir, "frames": FRAMES_FAST, "moves": true, "anim": f}
		t["walk_faster_" + suffix] = {"dir": dir, "frames": FRAMES_FASTER, "moves": true, "anim": r}
		t["walk_fastest_" + suffix] = {"dir": dir, "frames": FRAMES_FASTEST, "moves": true, "anim": r}
		# Stationary: the same durations, turned on the spot. Used for "look
		# around" beats and to burn time without displacing anyone.
		# Walking in place ANIMATES — that is the entire point of it, and source
		# routes it through the same GO anims a real walk uses. Gating the
		# animation on `moves` instead would leave every "look busy" cutscene
		# beat standing perfectly still.
		t["walk_in_place_" + suffix] = {"dir": dir, "frames": FRAMES_NORMAL, "moves": false, "anim": n}
		t["walk_in_place_fast_" + suffix] = {"dir": dir, "frames": FRAMES_FAST, "moves": false, "anim": f}
		t["walk_slow_" + suffix] = {"dir": dir, "frames": FRAMES_SLOW, "moves": true, "anim": n}
		t["walk_in_place_faster_" + suffix] = {"dir": dir, "frames": FRAMES_FASTER, "moves": false, "anim": r}
		t["walk_in_place_slow_" + suffix] = {"dir": dir, "frames": FRAMES_SLOW, "moves": false, "anim": n}
		# A turn is immediate.
		t["face_" + suffix] = {"dir": dir, "frames": 1, "moves": false}
	for n in [1, 2, 4, 8, 16, 32]:
		t["delay_%d" % n] = {"dir": -1, "frames": n, "moves": false}
	## Source keeps this as one bit on the object event
	## (`facingDirectionLocked`): a walk still MOVES while locked, it just does
	## not turn the sprite. Modelled the same way rather than skipped, because
	## skipping would silently turn a sprite a cutscene meant to hold still.
	t["lock_facing_direction"] = {"facing_locked": true}
	t["unlock_facing_direction"] = {"facing_locked": false}
	t["set_invisible"] = {"visible": false}
	t["set_visible"] = {"visible": true}
	_actions = t


## The spec for one movement action, or {} if this project does not implement it.
static func action(name: String) -> Dictionary:
	if _actions.is_empty():
		_build()
	return _actions.get(name, {})


## Begin a movement. Replaces anything already running for `key` — source's own
## `ScriptMovement_StartObjectMovementScript` likewise overwrites rather than
## queueing, so a second applymovement at the same target supersedes the first.
func start(key: Variant, node: Node2D, ops: Array, commit: Callable,
		face: Callable = Callable(), anim: Callable = Callable(),
		rest: Callable = Callable()) -> void:
	if node == null or not is_instance_valid(node):
		return
	var a := Active.new()
	a.node = node
	a.ops = ops
	a.commit = commit
	a.face = face
	a.anim = anim
	a.rest = rest
	if _begin(a):
		_active[key] = a
	else:
		# An unknown action in the FIRST slot never reaches `tick`, so without
		# this it would be dropped silently — the one shape that reports as a
		# cutscene that simply did nothing rather than as a coverage gap.
		if a.unknown != "":
			_last_unknown = a.unknown
		if a.anim_dir >= 0 and a.rest.is_valid():
			a.rest.call(a.anim_dir)
		_active.erase(key)


## True if anything is moving (no key), or if this particular mover is.
func is_busy(key: Variant = null) -> bool:
	if key == null:
		return not _active.is_empty()
	return _active.has(key)


## The action that stopped a mover early, "" if it finished cleanly. Read by the
## driver so an unimplemented action reports as a named coverage gap rather than
## as a cutscene that quietly stopped halfway.
func last_unknown() -> String:
	return _last_unknown


func clear(key: Variant) -> void:
	_active.erase(key)


func clear_all() -> void:
	_active.clear()


## Advance every mover by real elapsed time.
func tick(delta: float) -> void:
	# Snapshot the keys: finishing a mover erases from the dictionary being walked.
	for key in _active.keys():
		if not _active.has(key):
			continue
		var a: Active = _active[key]
		if a.node == null or not is_instance_valid(a.node):
			_active.erase(key)
			continue
		a.elapsed += delta
		# The frame cycle advances on the SAME delta the position does, so a
		# sprite can never be sliding while its feet are stopped.
		if a.anim_ticks > 0 and a.anim_dir >= 0 and a.anim.is_valid():
			a.anim.call(a.anim_dir, a.anim_ticks, delta)
		var t := 1.0 if a.duration <= 0.0 else clampf(a.elapsed / a.duration, 0.0, 1.0)
		a.node.position = a.from_px.lerp(a.to_px, t)
		if t < 1.0:
			continue
		a.node.position = a.to_px
		if not _begin(a):
			if a.unknown != "":
				_last_unknown = a.unknown
			# Settle onto the resting frame. Without this a walker keeps
			# whatever mid-stride frame it stopped on — one leg out, forever.
			if a.anim_dir >= 0 and a.rest.is_valid():
				a.rest.call(a.anim_dir)
			_active.erase(key)


## Start the next action. False when the script is finished or has hit something
## this project does not implement.
func _begin(a: Active) -> bool:
	while a.index < a.ops.size():
		var name := str((a.ops[a.index] as Dictionary).get("op", ""))
		a.index += 1
		if name == "step_end":
			return false
		var spec := action(name)
		if spec.is_empty():
			a.unknown = name
			return false
		# Visibility is instantaneous — apply it and take the next action in the
		# same tick rather than burning a frame on it.
		if spec.has("facing_locked"):
			a.facing_locked = bool(spec["facing_locked"])
			continue
		if spec.has("visible"):
			a.node.visible = bool(spec["visible"])
			continue
		a.duration = float(int(spec["frames"])) * FRAME
		a.elapsed = 0.0
		var dir := int(spec["dir"])
		# A face_* or delay_* action carries no "anim" key, so it parks the
		# cycle rather than advancing it — turning on the spot is not a step.
		a.anim_ticks = int(spec.get("anim", 0))
		# A locked facing blocks the TURN, not the walk — source's own
		# `facingDirectionLocked` leaves the current GO anim running. So hold the
		# cycle on the direction already established instead of repointing it,
		# and keep animating: a locked walker still moves its feet.
		if dir >= 0 and not a.facing_locked:
			a.anim_dir = dir
		# ⚠️ A WALKING action does not call `face` WHEN an `anim` callable is
		# wired, and that exception is load-bearing. `face` means "turn and
		# stand", so it parks the walk cycle; calling it at the head of every
		# walk would restart the cycle each tile and the walker would lead with
		# the same foot every step — a hop, not a walk. Source draws the same
		# line: a walk issues StartSpriteAnimIfDifferent(GO_*) and never touches
		# the FACE_* anim.
		#
		# A caller that supplies only `face` (no animation — the pre-Stage-3b
		# contract, and every test that stubs one callable) still gets it for
		# every action, so turning cannot silently stop working for them.
		var animating: bool = a.anim_ticks > 0 and a.anim.is_valid()
		if dir >= 0 and not animating and not a.facing_locked and a.face.is_valid():
			a.face.call(dir)
		# ⚠️ ORDER IS LOAD-BEARING. Capture the old pixel BEFORE committing,
		# because committing assigns `cell`, whose setter snaps `position`
		# straight to the destination.
		a.from_px = a.node.position
		a.to_px = a.from_px
		if bool(spec["moves"]) and a.commit.is_valid():
			a.commit.call(dir)
			a.to_px = a.node.position
			a.node.position = a.from_px
		return true
	return false
