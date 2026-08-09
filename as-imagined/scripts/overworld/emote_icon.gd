class_name EmoteIcon
extends Sprite2D

## [M27R Step 1] The "!" bubble an entity pops above its head.
##
## Ported from `FldEff_ExclamationMarkIcon` + `SpriteCB_TrainerIcons`
## (`trainer_see.c:1037, 1144`). Small, but three details are easy to get wrong
## and all three are visible:
##
##   * **It is a FIELD EFFECT, not part of the entity's own sprite.** Source
##     creates a separate sprite and parents nothing; it merely copies the
##     entity's position each frame. So this is a sibling node that follows,
##     which is also what lets it outlive the movement action that spawned it.
##   * **The action does NOT wait for it.**
##     `MovementAction_EmoteExclamationMark_Step0` starts the effect and returns
##     TRUE in the same step, so `waitmovement` releases immediately and the
##     icon keeps floating. Every real caller pairs it with an explicit `delay`
##     — which is exactly what `PewterCity_EventScript_AideGiveRunningShoes`
##     does — so making the action block would double the pause.
##   * **The bounce is a velocity rule, not a table.** `sYVelocity` starts at
##     -5 and increments whenever the offset is non-zero, so the icon pops up
##     and settles: 0 → -5 → -9 → -12 → -14 → -15, then back down to 0 over the
##     same number of frames, and rests there for the remainder.

## `ANIMCMD_FRAME(0, 60)` — one frame, sixty ticks (`trainer_see.c:356`).
const LIFETIME_FRAMES := 60
const FRAME := 1.0 / 60.0

## Source's own starting velocity (`SetIconSpriteData`, `trainer_see.c:1138`).
const START_VELOCITY := -5

const SHEET := "res://assets/sprites/overworld/field_effects/emotion_exclamation.png"

## One tile above the entity's own origin (`sprite->y = objEventSprite->y - 16`).
const Y_ABOVE := -16.0

var _follow: Node2D = null
var _elapsed := 0.0
var _offset := 0
var _velocity := START_VELOCITY
var _accum := 0.0


static func spawn(parent: Node, follow: Node2D, kind: String = "exclamation") -> EmoteIcon:
	if parent == null or follow == null or not is_instance_valid(follow):
		return null
	var tex := load(SHEET) if ResourceLoader.exists(SHEET) else null
	if tex == null:
		# ⚠️ Degrade silently rather than erroring: `run_overworld_tests.sh`
		# fails a run on any engine ERROR line, and a missing decoration must
		# never be able to fail a suite or stop a cutscene.
		return null
	var icon := EmoteIcon.new()
	icon.texture = tex
	icon.centered = true
	icon._follow = follow
	# Above the entity strata so the bubble is never hidden by a body.
	icon.z_index = 5
	parent.add_child(icon)
	icon._sync()
	return icon


func _process(delta: float) -> void:
	if _follow == null or not is_instance_valid(_follow):
		queue_free()
		return
	_elapsed += delta
	# Stepped at 60 Hz against WALL CLOCK, not per process frame — [M26G4]
	# measured frame-tied stepping running ~10% slow at 144 Hz and half speed
	# at 30 Hz, and every discrete stepper in this project follows that rule.
	_accum += delta
	while _accum >= FRAME:
		_accum -= FRAME
		_offset += _velocity
		if _offset != 0:
			_velocity += 1
		else:
			_velocity = 0
	_sync()
	if _elapsed >= float(LIFETIME_FRAMES) * FRAME:
		queue_free()


func _sync() -> void:
	if _follow == null or not is_instance_valid(_follow):
		return
	position = _follow.position + Vector2(0.0, Y_ABOVE + float(_offset))
