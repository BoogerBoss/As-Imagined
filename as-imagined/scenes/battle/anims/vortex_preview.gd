extends Node2D

# F6 THIS SCENE TO ITERATE. It exists so `vortex.tscn` can stay battle-clean:
# every preview-only concern -- a dark backdrop, a 4x zoom, a centre point, and
# replaying on a loop -- lives here instead of being set on the animation and
# then having to be remembered and undone before it ships.
#
# That separation is the same reason a baked map scene carries no controller:
# a scene that is both the artifact and the test rig eventually ships as one.
#
# Press SPACE to replay immediately, ESC to quit.

const VORTEX := preload("res://scenes/battle/anims/vortex.tscn")

## Seconds between automatic replays. The animation itself is 1.2s.
const REPLAY_EVERY := 2.0

var _elapsed := 0.0

@onready var _mount: Node2D = $Mount


func _ready() -> void:
	_play_once()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REPLAY_EVERY:
		_elapsed = 0.0
		_play_once()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_SPACE:
		_elapsed = 0.0
		_play_once()
	elif event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _play_once() -> void:
	# Belt and braces: the vortex frees itself when its animation finishes, so
	# this should never find anything. If it ever does, the leak rule has been
	# broken and the preview is the cheapest place to notice.
	for child in _mount.get_children():
		child.queue_free()
	_mount.add_child(VORTEX.instantiate())
