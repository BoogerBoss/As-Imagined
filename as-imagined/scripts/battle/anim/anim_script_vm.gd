class_name AnimScriptVM
extends RefCounted

# [M36B] The animation script interpreter — a Godot port of the reference's
# bytecode VM (src/battle_anim.c). Scope of record: docs/m26_f1_recon.md.
#
# Semantics reproduced exactly, because they are what make the extracted
# scripts mean anything:
#
# - FRAME-PUMPED, NOT FREE-RUNNING. Commands execute in a tight loop within
#   one frame until something asks to wait; the host then advances one GBA
#   frame (1/60s) and pumps again. So createsprite/createvisualtask/sound
#   commands cost zero frames, exactly as on hardware.
# - COMPLETION ACCOUNTING. Every sprite/task increments a live counter and
#   only its own destruction decrements it. `waitforvisualfinish` blocks on
#   that counter, and `end` implicitly waits for everything before finishing.
#   A behavior that forgets to report completion hangs the animation, so the
#   VM enforces a frame ceiling (see _MAX_FRAMES) rather than hanging a battle.
# - ARGS ARE A GLOBAL EIGHT-SLOT REGISTER FILE. Every create-command
#   overwrites gBattleAnimArgs before the behavior runs; slot 7 is the return
#   channel query tasks write and jumpargeq reads.
# - THE CALL STACK IS FOUR DEEP, as upstream. Exceeding it is a real error
#   in the data, not something to paper over.
#
# Deliberately NOT reproduced (each a no-op that records what it saw):
# - monbg/clearmonbg/splitbgprio: they exist only because GBA OBJs cannot
#   alpha-blend against each other. Godot CanvasItems blend freely.
# - setalpha/blendoff: kept as a blend CONTEXT the sprite host reads, rather
#   than a hardware register write.
# - background opcodes (fadetobg/restorebg/changebg/waitbgfade*): M36E.
# - sound opcodes: M36-S. The SE id and pan are recorded per cue so the audio
#   pass is pure asset work.

const ARG_COUNT := 8
const ARG_RET := 7
const MAX_CALL_DEPTH := 4

# Runaway guard. The longest real animation is well under a thousand frames;
# this exists so a behavior that never reports completion degrades to "the
# animation ended early" instead of freezing the battle forever.
const _MAX_FRAMES := 1800  # 30s at 60fps

enum State { IDLE, RUNNING, DONE, ERROR }

var state: int = State.IDLE
var error_text: String = ""

# Execution context supplied by the host (battle screen or a test double).
# See AnimStage for the real one.
var stage = null
var registry: AnimBehaviorRegistry = null

# Per-run inputs mirroring the reference's globals.
var move_turn := 0        # gAnimMoveTurn: two-turn phase / multi-hit counter
var move_power := 0       # gAnimMovePower
var move_damage := 0      # gAnimMoveDmg
var move_type := -1       # for jumpifmovetypeequal
var is_contest := false   # always false here; kept for script branches

var args: Array[int] = []

var _commands: Array = []
var _pc := -1
var _call_stack: Array[int] = []
var _frames_to_wait := 0
var _visual_count := 0
var _sound_count := 0
var _frame_budget := 0
var _blend: Dictionary = {"eva": 16, "evb": 0}
var _sound_cues: Array[Dictionary] = []
var _spawned: Array = []

# Active per-frame steppers. Upstream, a sprite callback or task function is
# re-entered every frame until it destroys itself; a Callable invoked once
# cannot express that, so a behavior that lasts more than a frame registers a
# stepper here. Each returns true when it is finished, which is the port of
# calling DestroyAnimSprite/DestroyAnimVisualTask.
var _steppers: Array = []


func _init() -> void:
	args.resize(ARG_COUNT)
	args.fill(0)


# Prepares a run. Returns false if the label has no body.
func start(label: String) -> bool:
	_commands = AnimData.commands()
	_pc = AnimData.label_index(label)
	if _pc < 0:
		state = State.ERROR
		error_text = "unknown animation label: %s" % label
		return false
	_call_stack.clear()
	args.fill(0)
	_frames_to_wait = 0
	_visual_count = 0
	_sound_count = 0
	_frame_budget = 0
	_sound_cues.clear()
	_spawned.clear()
	_steppers.clear()
	state = State.RUNNING
	error_text = ""
	return true


func is_running() -> bool:
	return state == State.RUNNING


# One GBA frame. Executes commands until something waits, then returns.
# The host calls this once per 1/60s until is_running() goes false.
func step() -> void:
	if state != State.RUNNING:
		return

	_frame_budget += 1
	if _frame_budget > _MAX_FRAMES:
		_finish("animation exceeded %d frames -- a behavior never reported completion"
				% _MAX_FRAMES)
		return

	_step_behaviors()

	if _frames_to_wait > 0:
		_frames_to_wait -= 1
		return

	# Tight loop: keep executing until a command asks to wait or we finish.
	var guard := 0
	while state == State.RUNNING and _frames_to_wait == 0:
		guard += 1
		if guard > 10000:
			_finish("animation executed 10000 commands in one frame " +
					"(runaway loop)")
			return
		if _pc < 0 or _pc >= _commands.size():
			_finish("program counter left the command array")
			return
		_execute(_commands[_pc])


# Runs every live behavior one GBA frame. A stepper returning true has
# finished and releases its slot on the completion counter -- which is what
# waitforvisualfinish and `end` are waiting for.
func _step_behaviors() -> void:
	if _steppers.is_empty():
		return
	var survivors: Array = []
	for entry in _steppers:
		var fn: Callable = entry
		var done: bool = false
		if fn.is_valid():
			done = bool(fn.call())
		else:
			done = true
		if done:
			_visual_count = maxi(0, _visual_count - 1)
		else:
			survivors.append(entry)
	_steppers = survivors


# Behaviors that span multiple frames register here instead of finishing
# inline. Counts against the same completion counter a sprite would.
func add_stepper(fn: Callable) -> void:
	_visual_count += 1
	_steppers.append(fn)


func _finish(err: String = "") -> void:
	if err != "":
		state = State.ERROR
		error_text = err
		push_warning("AnimScriptVM: " + err)
	else:
		state = State.DONE
	# Whatever is still alive is cleaned up, mirroring `end`'s own auto-free.
	# Nothing is live once the run is over, so the completion counter goes
	# with the steppers -- otherwise an aborted animation would leave a
	# non-zero count behind for anything inspecting the finished VM.
	_steppers.clear()
	_visual_count = 0
	for node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()


# Behaviors call these to report lifecycle, mirroring the reference's
# gAnimVisualTaskCount bookkeeping.
func notify_spawned(node: Object = null) -> void:
	_visual_count += 1
	if node != null:
		_spawned.append(node)


func notify_finished(node: Object = null) -> void:
	_visual_count = maxi(0, _visual_count - 1)
	if node != null:
		_spawned.erase(node)


func visual_count() -> int:
	return _visual_count


func blend_context() -> Dictionary:
	return _blend


func sound_cues() -> Array[Dictionary]:
	return _sound_cues


# ── Opcode dispatch ───────────────────────────────────────────────────────

func _execute(cmd: Array) -> void:
	var op := str(cmd[0])
	match op:
		# — sprite / task creation —
		"createsprite", "createspriteontargets", "createspriteontargets_onpos":
			_do_createsprite(cmd)
			_pc += 1
		"createdragondartsprite":
			# Builds its template inline upstream; the callback is fixed.
			_spawn_behavior("AnimShadowBall", _argv_of(cmd), {})
			_pc += 1
		"createvisualtask", "createvisualtaskontargets":
			_do_createvisualtask(cmd)
			_pc += 1
		"createsoundtask":
			_sound_cues.append({"kind": "task", "symbol": str(cmd[1])})
			_pc += 1

		# — waits —
		"delay":
			# `delay 0` still costs one frame upstream.
			_frames_to_wait = maxi(1, int(cmd[1]))
			_pc += 1
		"waitforvisualfinish":
			if _visual_count > 0:
				_frames_to_wait = 1
			else:
				_pc += 1
		"waitsound":
			_pc += 1  # sound is M36-S; nothing to wait on yet
		"end":
			if _visual_count > 0:
				_frames_to_wait = 1
			else:
				_finish()

		# — control flow —
		"call":
			if _call_stack.size() >= MAX_CALL_DEPTH:
				_finish("call stack exceeded %d frames deep" % MAX_CALL_DEPTH)
				return
			_call_stack.push_back(_pc + 1)
			_jump_to(str(cmd[1]))
		"return":
			if _call_stack.is_empty():
				_finish("return with an empty call stack")
				return
			_pc = _call_stack.pop_back()
		"goto":
			_jump_to(str(cmd[1]))
		"choosetwoturnanim":
			# Even gAnimMoveTurn -> setup script, odd -> unleash script.
			_jump_to(str(cmd[2]) if (move_turn & 1) == 1 else str(cmd[1]))
		"jumpifmoveturn":
			if int(cmd[1]) == move_turn:
				_jump_to(str(cmd[2]))
			else:
				_pc += 1
		"jumpargeq":
			if args[clampi(int(cmd[1]), 0, ARG_COUNT - 1)] == int(cmd[2]):
				_jump_to(str(cmd[3]))
			else:
				_pc += 1
		"jumpifcontest":
			if is_contest:
				_jump_to(str(cmd[1]))
			else:
				_pc += 1
		"jumpifmovetypeequal":
			if move_type == int(cmd[1]):
				_jump_to(str(cmd[2]))
			else:
				_pc += 1
		"setarg":
			args[clampi(int(cmd[1]), 0, ARG_COUNT - 1)] = int(cmd[2])
			_pc += 1

		# — blending context (see class doc) —
		"setalpha":
			_blend = {"eva": int(cmd[1]), "evb": int(cmd[2])}
			_pc += 1
		"blendoff":
			_blend = {"eva": 16, "evb": 0}
			_pc += 1
		"setbldcnt":
			_pc += 1

		# — battler visibility —
		"invisible":
			_set_battler_visible(int(cmd[1]), false)
			_pc += 1
		"visible":
			_set_battler_visible(int(cmd[1]), true)
			_pc += 1

		# — sound: recorded, not played (M36-S) —
		"playse":
			_sound_cues.append({"se": int(cmd[1]), "pan": 0})
			_pc += 1
		"playsewithpan", "setpan", "waitplaysewithpan", "loopsewithpan", \
		"panse", "panse_adjustnone", "panse_adjustall":
			_sound_cues.append({"op": op, "args": cmd.slice(1)})
			_pc += 1
		"stopsound":
			_pc += 1

		# — no-ops: GBA-only plumbing or deferred to M36E —
		"monbg", "clearmonbg", "monbg_static", "clearmonbg_static", \
		"splitbgprio", "splitbgprio_all", "splitbgprio_foes", \
		"unloadspritegfx", "unloadspritepal", "unloadallspritepals", \
		"fadetobg", "fadetobgfromset", "restorebg", "changebg", \
		"waitbgfadein", "waitbgfadeout", \
		"teamattack_moveback", "teamattack_movefwd":
			_pc += 1

		"nop", "nop2":
			# Upstream these loop forever (they are never reached). Treat as
			# a data error rather than reproducing a hang.
			_finish("reached %s, which never terminates upstream" % op)

		_:
			_finish("unimplemented opcode: %s" % op)


func _jump_to(label: String) -> void:
	var idx := AnimData.label_index(label)
	if idx < 0:
		_finish("jump to unknown label: %s" % label)
		return
	_pc = idx


func _argv_of(cmd: Array) -> Array:
	var last: Variant = cmd[cmd.size() - 1]
	return last if last is Array else []


# Loads argv into the global register file, exactly as every create-command
# does upstream before the behavior's first invocation.
func _load_args(argv: Array) -> void:
	args.fill(0)
	for i in range(mini(argv.size(), ARG_COUNT)):
		args[i] = int(argv[i])


func _do_createsprite(cmd: Array) -> void:
	var template_name := str(cmd[1])
	var tmpl := AnimData.template(template_name)
	var argv := _argv_of(cmd)
	_load_args(argv)

	var callback: Variant = tmpl.get("callback")
	if callback == null:
		return  # inert controller-sprite template
	var ctx := {
		"template": template_name,
		"template_data": tmpl,
		"anim_battler": int(cmd[2]) if cmd.size() > 2 else 0,
		"subpriority": int(cmd[3]) if cmd.size() > 3 else 0,
		"blend": _blend,
	}
	_spawn_behavior(str(callback), argv, ctx)


func _do_createvisualtask(cmd: Array) -> void:
	var symbol := str(cmd[1])
	var argv := _argv_of(cmd)
	_load_args(argv)
	_spawn_behavior(symbol, argv, {"priority": int(cmd[2]) if cmd.size() > 2
			else 0})


# Behaviors are invoked with (vm, ctx). They read `vm.args`, do their work,
# and are responsible for calling notify_spawned/notify_finished around any
# multi-frame effect. A behavior that completes synchronously (a query task
# writing args[7], say) simply returns without touching the counters.
func _spawn_behavior(symbol: String, _argv: Array, ctx: Dictionary) -> void:
	if registry == null or not registry.has(symbol):
		# Unreachable in normal play: the fallback contract rejects the whole
		# script before it starts. Reachable only if a caller bypassed the
		# check, so it fails loudly rather than silently skipping a sprite.
		_finish("behavior '%s' is not registered -- the fallback check was bypassed"
				% symbol)
		return
	var fn := registry.get_behavior(symbol)
	fn.call(self, ctx)


func _set_battler_visible(anim_battler: int, visible: bool) -> void:
	if stage != null and stage.has_method("set_battler_visible"):
		stage.set_battler_visible(anim_battler, visible)
