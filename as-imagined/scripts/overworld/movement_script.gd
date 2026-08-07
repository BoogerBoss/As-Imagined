class_name Move
extends RefCounted

## [M27G G6] Author a movement script in GDScript.
##
## ⚠️ **A SECOND, SEPARATE LANGUAGE — and that is source's own shape, not a
## simplification here.** Field scripts and movement scripts are different
## instruction sets in FireRed: `applymovement` names a movement label, and that
## label's body is `walk_down` / `face_west` / `step_end`, none of which the
## field-script command table contains. This project already reflects that split
## — `ScriptVM` executes field ops, `MovementRunner` executes movement actions —
## so the builders are split the same way rather than merged for convenience.
##
## Both still compile to `{"op": ..., "args": []}`, and both land in the SAME
## `ops_by_label` table, because the compiler indexes every label uniformly.
## `ScriptDriver.start_pending_movements` looks a movement label up through the
## exact same `source.ops_for()` that `goto` uses — no second pipeline.
##
##     const OAK_WALK := "Oak_WalkToPlayer"
##     EventRegistry.register(OAK_WALK, Move.new().walk_down(2).face_west().done())
##
## ⚠️ **EVERY MOVEMENT SCRIPT MUST END IN `step_end`.** `MovementRunner._begin`
## treats an unrecognised action as "stop this mover here" by design, and treats
## running off the end the same way — but `step_end` is what source emits and
## what the runner reads as a clean finish. `done()` appends it for you;
## forgetting it is exactly the class of bug that truncated Oak's lab-entry
## cutscene (see `gen_map_scripts.py`'s macro-expansion fix).


## Every action this builder can emit. Iterated by the round-trip test the same
## way `EventScript.OPS` is — see that constant's own comment.
const ACTIONS := [
	"walk_up", "walk_down", "walk_left", "walk_right",
	"walk_fast_up", "walk_fast_down", "walk_fast_left", "walk_fast_right",
	"walk_slow_up", "walk_slow_down", "walk_slow_left", "walk_slow_right",
	"face_up", "face_down", "face_left", "face_right",
	"walk_in_place_up", "walk_in_place_down",
	"walk_in_place_left", "walk_in_place_right",
	"delay_16", "step_end",
]

const _DIR_SUFFIX := {"up": "up", "down": "down", "left": "left", "right": "right"}

var _ops: Array = []


func _emit(action: String, times: int = 1) -> Move:
	for _i in range(maxi(1, times)):
		_ops.append({"op": action, "args": []})
	return self


# --- walking -------------------------------------------------------------

func walk_up(times: int = 1) -> Move: return _emit("walk_up", times)
func walk_down(times: int = 1) -> Move: return _emit("walk_down", times)
func walk_left(times: int = 1) -> Move: return _emit("walk_left", times)
func walk_right(times: int = 1) -> Move: return _emit("walk_right", times)

func walk_fast_up(times: int = 1) -> Move: return _emit("walk_fast_up", times)
func walk_fast_down(times: int = 1) -> Move: return _emit("walk_fast_down", times)
func walk_fast_left(times: int = 1) -> Move: return _emit("walk_fast_left", times)
func walk_fast_right(times: int = 1) -> Move: return _emit("walk_fast_right", times)

func walk_slow_up(times: int = 1) -> Move: return _emit("walk_slow_up", times)
func walk_slow_down(times: int = 1) -> Move: return _emit("walk_slow_down", times)
func walk_slow_left(times: int = 1) -> Move: return _emit("walk_slow_left", times)
func walk_slow_right(times: int = 1) -> Move: return _emit("walk_slow_right", times)


# --- turning in place ----------------------------------------------------

func face_up() -> Move: return _emit("face_up")
func face_down() -> Move: return _emit("face_down")
func face_left() -> Move: return _emit("face_left")
func face_right() -> Move: return _emit("face_right")

func step_in_place_up(times: int = 1) -> Move: return _emit("walk_in_place_up", times)
func step_in_place_down(times: int = 1) -> Move: return _emit("walk_in_place_down", times)
func step_in_place_left(times: int = 1) -> Move: return _emit("walk_in_place_left", times)
func step_in_place_right(times: int = 1) -> Move: return _emit("walk_in_place_right", times)


## A 16-frame pause. Source's own unit; `MovementRunner` reads it as such.
func pause(times: int = 1) -> Move: return _emit("delay_16", times)


## Terminate and hand back the built actions. See the class doc comment for why
## `step_end` is not optional.
func done() -> Array:
	_emit("step_end")
	return _ops
