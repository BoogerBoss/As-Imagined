class_name AuthoredAnimRunner
extends RefCounted

# Plays one hand-authored animation scene and reports what happened.
#
# Deliberately a standalone class rather than a method on the battle screen,
# for the reason `Shop` is a static class the suite drives directly: every rule
# worth testing lives here, and the screen only decides WHEN to call it. A
# runner buried in a 7,000-line UI file is a runner nobody can break-test.

## Hard ceiling on one animation, in seconds of wall clock.
##
## ⚠️ BOUNDED, NOT OPEN-ENDED, and the failure it prevents is nasty. Completion
## is "the scene freed itself", so a scene that never does would otherwise hang
## the battle inside an `anim_async` beat with the player unable to act —
## unrecoverable, and reported as "the game froze", not as "that animation is
## broken". Same reasoning as `_await_movement`'s own budget in the overworld.
##
## Generous on purpose: it can only fire on a genuine fault. The corpus's
## longest ported animations run a few seconds; Flamethrower is 1.30s.
## A `static var`, not a `const`, purely so a suite can lower it — proving the
## reap fires must not cost eight real seconds per run. Nothing in the game
## writes it.
static var TIMEOUT_SECONDS := 8.0

const _POLL_SECONDS := 1.0 / 60.0


# Plays `scene` on `stage`'s effect layer and returns once it is done.
#
# Returns {played, timed_out, leaked, seconds}:
#   played     the scene was instantiated and entered the tree
#   timed_out  it never freed itself and was reaped
#   leaked     it left nodes on the effect layer after finishing
#   seconds    wall clock actually spent
#
# The caller decides what to do with a bad report; the runner never pushes an
# error itself, so a suite can prove the guards fire without tripping
# `run_overworld_tests.sh`-style "any ERROR line fails the run" checks. Same
# `strict`-seam reasoning as `MapManager.preload_tilesets`.
static func play(host: Node, scene: PackedScene, stage: AnimStage) -> Dictionary:
	var report := {"played": false, "timed_out": false, "leaked": false,
			"seconds": 0.0}
	if host == null or scene == null or stage == null:
		return report
	var layer := stage.layer()
	if layer == null:
		return report

	var before := layer.get_child_count()
	var node := scene.instantiate()
	if node == null:
		return report

	# Position and size come from the battle, never from the editor. Optional
	# so a purely decorative scene needs no script at all.
	if node.has_method("setup"):
		node.call("setup", stage)

	layer.add_child(node)
	report["played"] = true

	var tree := host.get_tree()
	var elapsed := 0.0
	while is_instance_valid(node) and elapsed < TIMEOUT_SECONDS:
		await tree.create_timer(_POLL_SECONDS).timeout
		elapsed += _POLL_SECONDS
	report["seconds"] = elapsed

	if is_instance_valid(node):
		report["timed_out"] = true
		node.queue_free()
		# The reap has to actually land before the leak count is read, or a
		# timed-out scene reports as a leak as well and the two faults become
		# indistinguishable.
		await tree.process_frame
		await tree.process_frame

	# The leak half of the rule. Anything still on the layer was spawned by
	# this animation and not cleaned up.
	var after := layer.get_child_count()
	if after > before:
		report["leaked"] = true
		for i in range(layer.get_child_count() - 1, before - 1, -1):
			layer.get_child(i).queue_free()
		# ⚠️ THE AWAIT IS THE FIX, NOT DECORATION — caught by C.04 on this
		# runner's first real run. `queue_free` is DEFERRED, so returning here
		# hands the caller a layer that still has the leaked nodes on it and a
		# report claiming they were cleaned up. A cleanup that has not landed
		# by the time you return is not a cleanup, and the next animation
		# would have started on top of the debris.
		await tree.process_frame
	return report
