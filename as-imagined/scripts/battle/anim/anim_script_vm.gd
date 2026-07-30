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

# [M36E2] Background-fade phases, mirroring Task_FadeToBg's own state machine
# (src/battle_anim.c:1750-1785): fade the screen to black, swap the
# background, fade back. `waitbgfadeout` blocks until FADED_OUT and
# `waitbgfadein` until IDLE, which is exactly what the two opcodes wait on
# upstream via sAnimBackgroundFadeState.
enum BgFade { IDLE, FADING_OUT, FADED_OUT, FADING_IN }

# BeginHardwarePaletteFade(..., 16, 0): 16 steps each way.
const BG_FADE_FRAMES := 16

var state: int = State.IDLE
var error_text: String = ""

# Execution context supplied by the host (battle screen or a test double).
# See AnimStage for the real one.
var stage = null
var registry: AnimBehaviorRegistry = null

# Per-run inputs mirroring the reference's globals.
var move_turn := 0        # gAnimMoveTurn: two-turn phase / multi-hit counter
var move_power := 0       # gAnimMovePower
# gAnimFriendship. Not modelled by the battle side yet, so it reads 0 and
# AnimTask_GetReturnPowerLevel reports the weakest band -- see that behavior.
var friendship := 0
var move_damage := 0      # gAnimMoveDmg
var move_type := -1       # for jumpifmovetypeequal
var is_contest := false   # always false here; kept for script branches

var args: Array[int] = []

var _commands: Array = []
var _pc := -1
var _call_stack: Array[int] = []
var _frames_to_wait := 0
var _visual_count := 0
# Steppers registered with counts=false -- see add_stepper().
var _uncounted: Array = []
var _sound_count := 0
var _frame_budget := 0
var _blend: Dictionary = {"eva": 16, "evb": 0}
var _bg_fade: int = BgFade.IDLE
# The background this run swapped in, so `end` can put the battle's own
# backdrop back -- upstream LoadDefaultBg does that via restorebg, but a
# script that ends without restoring would otherwise leave the field wearing
# a move's background for the rest of the battle.
var _bg_changed := false
# The BG_* name currently installed by this run -- see current_background_name().
var _bg_name := ""
var _sound_cues: Array[Dictionary] = []
var _spawned: Array = []

# Active per-frame steppers. Upstream, a sprite callback or task function is
# re-entered every frame until it destroys itself; a Callable invoked once
# cannot express that, so a behavior that lasts more than a frame registers a
# stepper here. Each returns true when it is finished, which is the port of
# calling DestroyAnimSprite/DestroyAnimVisualTask.
var _steppers: Array = []

# Battlers this run hid. Upstream, a script may end with a battler still
# marked invisible because the battle controller re-syncs every sprite's
# visibility right after the animation completes
# (CopyAllBattleSpritesInvisibilities, src/battle_controllers.c:2146). This
# port has no such engine-side re-sync, so without undoing them here a single
# animation could hide a Pokemon for the REST OF THE BATTLE -- which is
# exactly what happened: 35 move scripts (Feint Attack, Shadow Force, Sky
# Drop, ...) hide a battler with no matching `visible` on the path taken.
var _hidden_battlers: Dictionary = {}


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
	_uncounted.clear()
	_bg_name = ""
	_sound_count = 0
	_frame_budget = 0
	_sound_cues.clear()
	_spawned.clear()
	_steppers.clear()
	_hidden_battlers.clear()
	_bg_fade = BgFade.IDLE
	_bg_changed = false
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
			if _uncounted.has(entry):
				_uncounted.erase(entry)
			else:
				_visual_count = maxi(0, _visual_count - 1)
		else:
			survivors.append(entry)
	_steppers = survivors


# Behaviors that span multiple frames register here instead of finishing
# inline. Counts against the same completion counter a sprite would.
# `counts` mirrors the reference's own bookkeeping choice. A handful of tasks
# (AnimTask_SetPsychicBackground, AnimTask_StartSlidingBg's updater) decrement
# gAnimVisualTaskCount at setup and keep running, precisely so a later
# `waitforvisualfinish` does NOT wait for them -- they are open-ended effects
# torn down by an explicit `setarg 7, -1`, not by finishing on their own. A
# stepper registered with counts=false reproduces that: it still steps every
# frame, but nothing blocks on it.
func add_stepper(fn: Callable, counts: bool = true) -> void:
	if counts:
		_visual_count += 1
	else:
		_uncounted.append(fn)
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
	_uncounted.clear()
	_visual_count = 0
	# Undo any visibility this run took away, before freeing anything.
	for battler in _hidden_battlers:
		_set_battler_visible(int(battler), true)
	_hidden_battlers.clear()
	# ...and any DISPLACEMENT, for the same reason. Some tasks deliberately
	# never restore -- AnimTask_SlideOffScreen leaves the battler off-screen
	# on purpose, because upstream the script that used it always followed up.
	# Here that leaves a Pokemon parked off the edge of the battlefield for the
	# rest of the battle: the exact silent-and-permanent shape as the M36D
	# visibility leak, so it gets the same safety net rather than a per-task
	# fix. MonOffset records each battler's true base the first time anything
	# moves it, which is what makes this recoverable at all.
	_restore_displaced_battlers()
	# Same reasoning as the visibility restore: a script that ends while its
	# background is still up would leave the battlefield permanently altered.
	if _bg_changed and stage != null:
		if stage.has_method("clear_background"):
			stage.clear_background()
		if stage.has_method("set_fade"):
			stage.set_fade(0.0)
		_bg_changed = false
		_bg_name = ""
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
			hide_battler(int(cmd[1]))
			_pc += 1
		"visible":
			show_battler(int(cmd[1]))
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

		# — [M36E2] backgrounds —
		"fadetobg":
			_start_bg_fade(AnimData.bg_name_for_id(int(cmd[1])))
			_pc += 1
		"fadetobgfromset":
			# opponent / player / contest variants of one background. Contest
			# is unreachable here, so the choice is by attacking side.
			var pick: int = int(cmd[1]) if not _attacker_is_player() \
					else int(cmd[2])
			_start_bg_fade(AnimData.bg_name_for_id(pick))
			_pc += 1
		"changebg":
			# Immediate swap, no fade (LoadMoveBg without Task_FadeToBg).
			if stage != null and stage.has_method("set_background"):
				var immediate := AnimData.bg_name_for_id(int(cmd[1]))
				if stage.set_background(immediate):
					_bg_name = immediate
					_bg_changed = true
			_pc += 1
		"restorebg":
			_start_bg_restore()
			_pc += 1
		"waitbgfadeout":
			if _bg_fade == BgFade.FADING_OUT:
				_frames_to_wait = 1
			else:
				_pc += 1
		"waitbgfadein":
			if _bg_fade == BgFade.FADING_IN or _bg_fade == BgFade.FADING_OUT \
					or _bg_fade == BgFade.FADED_OUT:
				_frames_to_wait = 1
			else:
				_pc += 1

		# — no-ops: GBA-only plumbing with no Godot equivalent —
		"monbg", "clearmonbg", "monbg_static", "clearmonbg_static", \
		"splitbgprio", "splitbgprio_all", "splitbgprio_foes", \
		"unloadspritegfx", "unloadspritepal", "unloadallspritepals", \
		"teamattack_moveback", "teamattack_movefwd":
			_pc += 1

		"nop", "nop2":
			# Upstream these loop forever (they are never reached). Treat as
			# a data error rather than reproducing a hang.
			_finish("reached %s, which never terminates upstream" % op)

		_:
			_finish("unimplemented opcode: %s" % op)


func _attacker_is_player() -> bool:
	if stage != null and stage.has_method("attacker_is_player_side"):
		return stage.attacker_is_player_side()
	return true


# Fades to black, swaps the background, fades back -- the port of
# Task_FadeToBg. Registered as a stepper so it advances on the VM's own frame
# clock and so `end` cannot finish while a fade is still mid-flight.
func _start_bg_fade(bg_name: String) -> void:
	if stage == null or not stage.has_method("set_fade"):
		return
	if bg_name == "" or not AnimData.has_background(bg_name):
		# No pulled asset for this id (three legitimately span two palette
		# banks, and contest-only ids are never pulled). Consume the fade's
		# frames anyway so the script's pacing is unchanged.
		bg_name = ""
	_bg_fade = BgFade.FADING_OUT
	var st := {"t": 0, "phase": 0}
	add_stepper(func() -> bool:
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if int(st["phase"]) == 0:
			stage.set_fade(float(t) / float(BG_FADE_FRAMES))
			if t >= BG_FADE_FRAMES:
				_bg_fade = BgFade.FADED_OUT
				if bg_name != "" and stage.has_method("set_background"):
					_bg_name = bg_name
					if stage.set_background(bg_name):
						_bg_changed = true
				st["phase"] = 1
				st["t"] = 0
				_bg_fade = BgFade.FADING_IN
			return false
		stage.set_fade(1.0 - float(t) / float(BG_FADE_FRAMES))
		if t >= BG_FADE_FRAMES:
			stage.set_fade(0.0)
			_bg_fade = BgFade.IDLE
			return true
		return false)


# restorebg: the same fade, back to the battle's own backdrop.
func _start_bg_restore() -> void:
	if stage == null or not stage.has_method("set_fade"):
		return
	_bg_fade = BgFade.FADING_OUT
	var st := {"t": 0, "phase": 0}
	add_stepper(func() -> bool:
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if int(st["phase"]) == 0:
			stage.set_fade(float(t) / float(BG_FADE_FRAMES))
			if t >= BG_FADE_FRAMES:
				_bg_fade = BgFade.FADED_OUT
				if stage.has_method("clear_background"):
					stage.clear_background()
				_bg_changed = false
				st["phase"] = 1
				st["t"] = 0
				_bg_fade = BgFade.FADING_IN
			return false
		stage.set_fade(1.0 - float(t) / float(BG_FADE_FRAMES))
		if t >= BG_FADE_FRAMES:
			stage.set_fade(0.0)
			_bg_fade = BgFade.IDLE
			return true
		return false)


func bg_fade_state() -> int:
	return _bg_fade


# The BG_* name currently installed by this run, or "" if none. Read by the
# palette-cycling behaviors, which need to know WHICH background's palette they
# are rotating -- the script installs it with `fadetobg` several commands
# earlier, so the behavior cannot derive it from its own arguments.
func current_background_name() -> String:
	return _bg_name


# Lets a behavior that installs a background itself (the storm/fog loaders,
# which do NOT go through fadetobg) opt into the same restore-on-finish
# guarantee the opcodes get.
func notify_background_changed() -> void:
	_bg_changed = true


# Puts every battler this run displaced back on its recorded base. Reads the
# meta MonOffset writes, so it needs no bookkeeping of its own and cannot
# disagree with whatever actually moved the sprite.
func _restore_displaced_battlers() -> void:
	if stage == null or not stage.has_method("sprite_for"):
		return
	for i in range(4):
		var node: Control = stage.sprite_for(i)
		if node != null and is_instance_valid(node) \
				and node.has_meta("_anim_mon_base"):
			node.position = node.get_meta("_anim_mon_base")


func background_changed() -> bool:
	return _bg_changed


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


# The opcode path, which additionally REMEMBERS a hide so `_finish` can undo
# it. Behaviors that hide a battler (Teleport) go through here too, so no
# code path can leave a Pokemon invisible once the animation is over.
func hide_battler(anim_battler: int) -> void:
	_hidden_battlers[anim_battler] = true
	_set_battler_visible(anim_battler, false)


func show_battler(anim_battler: int) -> void:
	_hidden_battlers.erase(anim_battler)
	_set_battler_visible(anim_battler, true)
