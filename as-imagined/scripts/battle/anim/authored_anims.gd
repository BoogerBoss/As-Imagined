class_name AuthoredAnims
extends RefCounted

# The registry for HAND-AUTHORED move animations — scenes built in Godot's own
# animation editor, as opposed to the reference scripts `AnimScriptVM` plays.
#
# ⚠️ THIS IS FOR ORIGINAL CONTENT. A move's animation is squarely "would a
# player notice?", so it is BEHAVIOUR, not mechanism: a move the reference has
# an animation for should play the ported one. Registering here overrides that
# port — deliberately, because an explicit registration must beat a default,
# but it means every entry is a fidelity decision. Take it on purpose and
# record it; do not let one arrive because a scene happened to be written.
#
# The intended users are moves this project invents, and Kanto content the
# reference has no animation for.
#
# ── How an entry works ────────────────────────────────────────────────────
#
# `SCENES` maps a move id to a scene whose root:
#
#   * OPTIONALLY has `setup(stage: AnimStage)`, called before it enters the
#     tree, to take its position and size from the battle rather than from
#     whatever was left set in the editor;
#   * FREES ITSELF when it is done. That is the whole completion protocol —
#     `AuthoredAnimRunner` waits for the node to leave the tree. A scene that
#     never frees itself is reaped by the runner's own timeout and reported.
#
# ── The leak rule ─────────────────────────────────────────────────────────
#
# ⚠️ AN AUTHORED SCENE MAY ONLY TOUCH NODES IT SPAWNED, and must leave none
# behind. `m36_leak_harness` walks the VM's 778 extracted scripts and would
# never see one of these, so the runner enforces the layer half itself. The
# rule is deliberately stricter than the VM's: the VM restores a full battler
# baseline (position/scale/rotation/visibility/modulate/material) because a
# ported script legitimately moves battlers; an authored scene has no reason
# to, and "don't touch it" is a rule you cannot half-implement.

## move id -> scene path. Empty by design: nothing is bound until a real
## original move exists to bind. `scenes/battle/anims/vortex.tscn` is built and
## previewable (`vortex_preview.tscn`) but deliberately unregistered — it is an
## original animation with no move of its own yet.
const SCENES := {}

## Test seam, matching this project's `_force_roll` / `_force_crit` / `strict`
## precedent. `SCENES` is a `const` Dictionary and therefore read-only at
## runtime, so a suite cannot exercise the dispatch branch without this.
static var _overrides: Dictionary = {}


static func set_override(move_id: int, scene_path: String) -> void:
	_overrides[move_id] = scene_path


static func clear_overrides() -> void:
	_overrides.clear()


static func path_for(move_id: int) -> String:
	if _overrides.has(move_id):
		return str(_overrides[move_id])
	return str(SCENES.get(move_id, ""))


# ⚠️ FAILS CLOSED, and that is the point. A registered path that does not
# resolve answers `false` here rather than erroring, so the move falls through
# to the ported engine and then to the legacy hit-effect — the same
# "absent data must not crash the battle" posture `AnimData.ensure_loaded()`
# already takes. A typo'd path costs you an animation, never a battle.
static func has(move_id: int) -> bool:
	var path := path_for(move_id)
	return path != "" and ResourceLoader.exists(path)


# The PackedScene, or null. Null is a real answer, not an error: see `has`.
static func scene_for(move_id: int) -> PackedScene:
	if not has(move_id):
		return null
	return load(path_for(move_id)) as PackedScene


# Every registered move id whose scene does NOT resolve. Empty in a healthy
# tree; a suite asserts on it so a typo is caught here rather than as a move
# that silently plays the generic effect forever.
static func broken_entries() -> Array[int]:
	var out: Array[int] = []
	for id in SCENES:
		if not ResourceLoader.exists(str(SCENES[id])):
			out.append(int(id))
	out.sort()
	return out
