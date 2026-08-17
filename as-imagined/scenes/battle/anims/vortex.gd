extends Node2D

# An ORIGINAL fire animation built from an existing reference asset: embers
# spiral inward around a point, tighten, and pop into an impact flash.
# Nothing here is ported -- there is no upstream animation this recreates.
#
# THE DIVISION OF LABOUR, which is the point of doing it this way:
#
#   The AnimationPlayer owns the MOTION. `Pivot` spins and `Spawner` slides
#   toward the centre; both are ordinary keyframed tracks you can scrub, drag
#   and re-time in the editor without touching code.
#
#   This script owns only the EMISSION -- it drops an ember at wherever
#   `Spawner` happens to be right now. Because `Spawner` is parented under the
#   spinning `Pivot`, reading its transform per spawn traces the authored
#   spiral for free. There is no spiral maths anywhere in this file, and that
#   is deliberate: the shape is data you can see, not code you have to run.
#
# Emission is a frame counter rather than 21 hand-placed call-method keys.
# Same result, and a keyframe you cannot mis-place is a keyframe that cannot
# drift out of step with the motion tracks when you re-time them.
#
# HOUSE STYLE, borrowed from the extracted corpus rather than invented:
#   one particle every 2 frames  -- Flamethrower's own spawn cadence
#   ~30-frame particle lifetime  -- AnimToTargetInSinWave's hard-coded travel
#   whole animation under 1.5s   -- Flamethrower is 1.30s end to end
#
# ⚠️ POSITION AND SCALE MUST COME FROM THE STAGE, NEVER FROM THE EDITOR.
# `setup()` below is what a real battle calls. The values you set on this node
# in the editor are for previewing only -- see `vortex_preview.tscn`, which
# holds them so this scene stays battle-clean.

const EMBER_SCENE := preload("res://scenes/battle/anims/ember.tscn")

## Stop spawning once the spiral has closed. Matches the 0.7s the two motion
## tracks resolve at -- re-time those and this wants moving with them.
const SPAWN_UNTIL := 0.7

## Seconds between embers. 2 GBA frames is Flamethrower's own cadence; raise
## it for fewer, heavier embers.
const SPAWN_INTERVAL := 2.0 / 60.0

## ⚠️ THIS IS DELIBERATELY KEYED ON ANIMATION TIME, NOT ON A FRAME COUNTER,
## and the first draft got it wrong. Spawning every Nth rendered frame ties
## the ember COUNT to the monitor: the first version of this file produced 15
## live embers where 5 was intended, purely because a headless run renders
## faster than 60 Hz. `[M26G4]` measured the same class of bug in this
## project's own stepping -- ~10% slow at 144 Hz, half speed at 30 Hz -- and
## every discrete stepper here has had to learn it once.
##
## Reading the AnimationPlayer's own clock also means re-timing the motion
## tracks in the editor re-times the emission with them, for free.
var _next_spawn := 0.0
var _done := false

@onready var _player: AnimationPlayer = $AnimationPlayer
@onready var _pivot: Node2D = $Pivot
@onready var _spawner: Marker2D = $Pivot/Spawner


# What a real battle calls before playing. Not used by the preview scene.
#
# ⚠️ `pixel_scale()` is not optional. Every offset authored in this scene is
# in GBA pixels and the canvas is not -- skipping it renders the whole vortex
# at a fraction of its intended size, which looks plausible rather than
# obviously broken, and is therefore the harder bug to notice.
func setup(stage) -> void:
	position = stage.center_of(AnimStage.ANIM_TARGET)
	scale = Vector2.ONE * stage.pixel_scale()


func _ready() -> void:
	_player.animation_finished.connect(_on_finished)
	_player.play(&"swirl")


func _process(_delta: float) -> void:
	if _done or not _player.is_playing():
		return
	var now := minf(_player.current_animation_position, SPAWN_UNTIL)
	# A `while`, not an `if`: on a slow frame more than one ember is owed, and
	# dropping them would thin the stream exactly when the game is struggling.
	# They co-locate, because the pivot is only sampled once per frame -- fine
	# at any sane frame rate, and honest about what it does at a bad one.
	while _next_spawn <= now:
		_spawn()
		_next_spawn += SPAWN_INTERVAL


func _spawn() -> void:
	var e := EMBER_SCENE.instantiate()
	add_child(e)
	# The authored spiral, read rather than computed.
	e.position = _spawner.position.rotated(_pivot.rotation)


# The whole scene owns its own death, for the same reason each ember does.
func _on_finished(_name: StringName) -> void:
	_done = true
	queue_free()
