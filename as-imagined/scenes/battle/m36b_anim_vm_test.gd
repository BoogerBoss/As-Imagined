extends Node

# [M36B] Suite for the animation runtime core: the VM's execution semantics,
# the behavior registry's static walk, and the fallback contract.
#
# The load-bearing property this suite exists to protect: with an EMPTY
# registry every move must fall back, and the fallback must be decided
# BEFORE any script runs. That is what lets M36 ship in batches without any
# intermediate state breaking a battle. A regression here would not look like
# a crash -- it would look like a move playing half an animation -- so the
# contract is asserted directly rather than inferred from behaviour.
#
# VM semantics are tested against stub behaviors rather than real ones
# (M36C owns those), which keeps this suite about the interpreter: frame
# accounting, call/return, branch selection, completion counting, and the
# guards that stop bad data from hanging a battle.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_loads()
	_test_registry_walk()
	_test_fallback_contract()
	_test_vm_execution()
	_test_vm_control_flow()
	_test_vm_completion_accounting()
	_test_vm_guards()
	_test_dispatcher()
	_test_every_move_script_walks()

	var total := _pass + _fail
	print("m36b_anim_vm_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Data layer ────────────────────────────────────────────────────────────

func _test_data_loads() -> void:
	_chk("AnimData loads all four products (%s)" % AnimData.load_error(),
			AnimData.ensure_loaded())
	_chk("command program is present", AnimData.commands().size() > 30000)
	_chk("opcode signatures published for the VM",
			AnimData.opcode_signatures().size() > 40)
	_chk("Flamethrower resolves to its script",
			AnimData.script_for_move(53) == "gBattleAnimMove_Flamethrower")
	_chk("label lookup resolves a known label",
			AnimData.label_index("gBattleAnimMove_Pound") >= 0)
	_chk("unknown label returns -1 rather than erroring",
			AnimData.label_index("gNotARealLabel") == -1)

	# Sheets: the tag a real template names must load as a texture.
	var tmpl := AnimData.template("gFlamethrowerFlameSpriteTemplate")
	var tag := str((tmpl.get("tile_tag", {}) as Dictionary).get("name", ""))
	_chk("Flamethrower's flame template names ANIM_TAG_SMALL_EMBER",
			tag == "ANIM_TAG_SMALL_EMBER")
	_chk("...and that tag's sheet loads", AnimData.sheet_for_tag(tag) != null)

	# Frame sequences resolve through the file-qualified key + offset.
	var seqs := AnimData.anim_sequences_for("gFlamethrowerFlameSpriteTemplate")
	_chk("flame template resolves at least one frame sequence",
			seqs.size() >= 1 and (seqs[0] as Array).size() > 0)

	# The offset case M36A found: Acid's droplet starts part-way into a
	# shared table, so its first sequence must NOT be the table's entry 0.
	var acid := AnimData.template("gAcidPoisonDropletSpriteTemplate")
	if not acid.is_empty():
		_chk("indexed anim reference preserves its offset",
				int(acid.get("anims_offset", 0)) > 0)


# ── Registry: the static walk ─────────────────────────────────────────────

func _test_registry_walk() -> void:
	var reg := AnimBehaviorRegistry.new()

	# Pound is a known, hand-verified script: one hitsplat sprite + one shake
	# task, so exactly two behaviors.
	var pound := reg.referenced_behaviors("gBattleAnimMove_Pound")
	var expected_pound: Array[String] = ["AnimHitSplatBasic", "AnimTask_ShakeMon"]
	_chk("Pound references exactly its 2 behaviors (got %s)" % str(pound),
			pound == expected_pound)

	# Double Slap branches via choosetwoturnanim; BOTH arms must be walked,
	# because a battle reaches both across its multi-hit turns.
	var slap := reg.referenced_behaviors("gBattleAnimMove_DoubleSlap")
	_chk("choosetwoturnanim walks both arms (got %s)" % str(slap),
			slap.has("AnimHitSplatBasic") and slap.has("AnimTask_ShakeMon"))

	# Flamethrower reaches its behaviors through `call` subroutines.
	var flame := reg.referenced_behaviors("gBattleAnimMove_Flamethrower")
	_chk("call targets are followed (Flamethrower sees its flame callback)",
			flame.has("AnimToTargetInSinWave"))
	_chk("Flamethrower also sees its shake task",
			flame.has("AnimTask_ShakeMon"))

	# Backward gotos are the scripts' only loop; the walk must terminate.
	var surf := reg.referenced_behaviors("gBattleAnimMove_Surf")
	_chk("a goto-looping script terminates and yields behaviors",
			surf.size() > 0)

	_chk("an unknown label is reported rather than passing silently",
			reg.referenced_behaviors("gNopeNotHere")
				.any(func(s): return s.begins_with("<missing label")))


# ── The fallback contract ─────────────────────────────────────────────────

func _test_fallback_contract() -> void:
	var reg := AnimBehaviorRegistry.new()
	_chk("empty registry: nothing is playable",
			not reg.can_play("gBattleAnimMove_Pound"))
	_chk("empty registry: the reason lists every missing behavior",
			reg.missing_behaviors("gBattleAnimMove_Pound").size() == 2)

	# Partial registration is still a fallback -- all-or-nothing per move.
	reg.register("AnimHitSplatBasic", func(_vm, _ctx): pass)
	_chk("partial registration still falls back",
			not reg.can_play("gBattleAnimMove_Pound"))
	var expected_missing: Array[String] = ["AnimTask_ShakeMon"]
	_chk("...and reports only the still-missing one",
			reg.missing_behaviors("gBattleAnimMove_Pound") == expected_missing)

	reg.register("AnimTask_ShakeMon", func(_vm, _ctx): pass)
	_chk("complete registration flips the verdict to playable",
			reg.can_play("gBattleAnimMove_Pound"))


# ── VM execution semantics ────────────────────────────────────────────────

func _make_vm(reg: AnimBehaviorRegistry) -> AnimScriptVM:
	var vm := AnimScriptVM.new()
	vm.registry = reg
	return vm


func _run_to_completion(vm: AnimScriptVM, max_frames: int = 2000) -> int:
	var frames := 0
	while vm.is_running() and frames < max_frames:
		vm.step()
		frames += 1
	return frames


func _test_vm_execution() -> void:
	var reg := AnimBehaviorRegistry.new()
	var spawned: Array[String] = []
	var seen_args: Array = []
	reg.register("AnimHitSplatBasic", func(vm, ctx):
		spawned.append("sprite:" + str(ctx.get("template", "")))
		seen_args.append(vm.args.duplicate()))
	reg.register("AnimTask_ShakeMon", func(vm, _ctx):
		spawned.append("task")
		seen_args.append(vm.args.duplicate()))

	var vm := _make_vm(reg)
	_chk("VM starts on a real label", vm.start("gBattleAnimMove_Pound"))
	var frames := _run_to_completion(vm)
	_chk("Pound runs to DONE (state=%d)" % vm.state,
			vm.state == AnimScriptVM.State.DONE)
	_chk("both of Pound's behaviors were invoked (got %s)" % str(spawned),
			spawned.size() == 2)
	_chk("creating sprites/tasks costs zero frames, so Pound is short (%d)"
			% frames, frames <= 3)

	# Args are the reference's global register file: each create-command
	# overwrites them before its behavior runs.
	_chk("hitsplat received its own inline args (x=0,y=0,relative,anim=2)",
			seen_args.size() == 2
			and (seen_args[0] as Array)[3] == 2)
	_chk("shake task received ITS args, not the sprite's",
			(seen_args[1] as Array)[0] == 1  # ANIM_TARGET
			and (seen_args[1] as Array)[3] == 6)  # 6 shakes


func _test_vm_control_flow() -> void:
	var reg := AnimBehaviorRegistry.new()
	var xs: Array[int] = []
	reg.register("AnimHitSplatBasic", func(vm, _ctx): xs.append(vm.args[0]))
	reg.register("AnimTask_ShakeMon", func(_vm, _ctx): pass)

	# choosetwoturnanim: even turn takes arm 1, odd takes arm 2. Double Slap
	# uses it to alternate slap direction, so the x offset flips sign.
	var even := _make_vm(reg)
	even.move_turn = 0
	even.start("gBattleAnimMove_DoubleSlap")
	_run_to_completion(even)
	var even_x: int = xs[0] if xs.size() > 0 else 999

	xs.clear()
	var odd := _make_vm(reg)
	odd.move_turn = 1
	odd.start("gBattleAnimMove_DoubleSlap")
	_run_to_completion(odd)
	var odd_x: int = xs[0] if xs.size() > 0 else 999

	_chk("choosetwoturnanim picks different arms by turn parity (%d vs %d)"
			% [even_x, odd_x], even_x != odd_x)
	_chk("even turn takes the first arm (x=-8)", even_x == -8)
	_chk("odd turn takes the second arm (x=8)", odd_x == 8)

	# call/return: Flamethrower's flames come from a subroutine called 11
	# times, so a correct implementation invokes the callback 22 times.
	# Array wrapper, not a bare int: GDScript lambdas capture scalars BY
	# VALUE, so `calls += 1` inside the lambda would leave the outer counter
	# at 0 and the assertion would be testing nothing.
	var calls := [0]
	var reg2 := AnimBehaviorRegistry.new()
	for symbol in reg2.referenced_behaviors("gBattleAnimMove_Flamethrower"):
		if symbol == "AnimToTargetInSinWave":
			reg2.register(symbol, func(_vm, _ctx): calls[0] += 1)
		else:
			reg2.register(symbol, func(_vm, _ctx): pass)
	var flame := _make_vm(reg2)
	flame.start("gBattleAnimMove_Flamethrower")
	_run_to_completion(flame)
	_chk("call/return runs the flame subroutine every time (22 flames, got %d)"
			% calls[0], calls[0] == 22)
	_chk("Flamethrower completes rather than stalling",
			flame.state == AnimScriptVM.State.DONE)


func _test_vm_completion_accounting() -> void:
	# waitforvisualfinish must block while anything is live, and `end` must
	# implicitly wait too. A behavior that reports a spawn and only later
	# reports completion is the normal multi-frame case.
	var reg := AnimBehaviorRegistry.new()
	var vm_ref: Array = []
	reg.register("AnimHitSplatBasic", func(vm, _ctx):
		vm.notify_spawned()
		vm_ref.append(vm))
	reg.register("AnimTask_ShakeMon", func(_vm, _ctx): pass)

	var vm := _make_vm(reg)
	vm.start("gBattleAnimMove_Pound")
	# Pump a few frames: the sprite never finishes, so the VM must still be
	# running (blocked at waitforvisualfinish), not done.
	for i in range(30):
		vm.step()
	_chk("waitforvisualfinish blocks while a sprite is live",
			vm.is_running() and vm.visual_count() == 1)

	vm.notify_finished()
	_run_to_completion(vm)
	_chk("...and releases once the sprite reports completion",
			vm.state == AnimScriptVM.State.DONE)


func _test_vm_guards() -> void:
	# A behavior that never reports completion must degrade to an early end,
	# not hang the battle. The frame ceiling is the backstop.
	var reg := AnimBehaviorRegistry.new()
	reg.register("AnimHitSplatBasic", func(vm, _ctx): vm.notify_spawned())
	reg.register("AnimTask_ShakeMon", func(_vm, _ctx): pass)
	var vm := _make_vm(reg)
	vm.start("gBattleAnimMove_Pound")
	var frames := _run_to_completion(vm, 3000)
	_chk("a never-completing behavior trips the frame ceiling instead of " +
			"hanging (%d frames, state=%d)" % [frames, vm.state],
			not vm.is_running() and frames < 3000)

	# Starting an unknown label fails cleanly.
	var bad := _make_vm(reg)
	_chk("starting an unknown label returns false",
			not bad.start("gNotARealLabel"))
	_chk("...and records why", bad.error_text != "")

	# Running a script whose behaviors are unregistered must fail loudly
	# rather than silently skipping sprites -- this path is only reachable if
	# a caller bypassed the fallback check, which is exactly when a silent
	# skip would be most misleading.
	var empty := AnimBehaviorRegistry.new()
	var bypassed := _make_vm(empty)
	bypassed.start("gBattleAnimMove_Pound")
	_run_to_completion(bypassed, 50)
	_chk("bypassing the fallback check errors rather than half-playing",
			bypassed.state == AnimScriptVM.State.ERROR)


# ── Dispatcher ────────────────────────────────────────────────────────────

func _test_dispatcher() -> void:
	var reg := AnimBehaviorRegistry.new()
	var disp := AnimDispatcher.new(reg)

	var v := disp.verdict_for_move(1)  # Pound
	_chk("dispatcher resolves a move's script label",
			str(v.get("label", "")) == "gBattleAnimMove_Pound")
	_chk("with an empty registry the verdict is MISSING_BEHAVIORS",
			int(v.get("reason", -1))
			== AnimDispatcher.Reason.MISSING_BEHAVIORS)
	_chk("dispatcher refuses to build a VM for a falling-back move",
			disp.make_vm(1, null) == null)

	# An id with no script at all is a distinct, reported reason.
	var none := disp.verdict_for_move(999999)
	_chk("an unbound move id reports NO_SCRIPT",
			int(none.get("reason", -1)) == AnimDispatcher.Reason.NO_SCRIPT)

	reg.register("AnimHitSplatBasic", func(_vm, _ctx): pass)
	reg.register("AnimTask_ShakeMon", func(_vm, _ctx): pass)
	disp.invalidate_cache()
	_chk("registering the behaviors flips the verdict",
			disp.can_play_move(1))
	var vm := disp.make_vm(1, null)
	_chk("...and the dispatcher now builds a primed VM",
			vm != null and vm.is_running())

	# The coverage report M36D sequences batches from.
	var cov := disp.coverage([1, 33, 53, 57, 87])
	_chk("coverage counts playable vs blocked (%d/%d playable)"
			% [int(cov["playable"]), int(cov["total"])],
			int(cov["total"]) == 5 and int(cov["playable"]) >= 1)
	_chk("coverage ranks the most-blocking behaviors first",
			(cov["top_blockers"] as Array).size() > 0)


# ── Whole-roster walk ─────────────────────────────────────────────────────

func _test_every_move_script_walks() -> void:
	# The headless parse-all check the recon called for: every bound move's
	# script must walk to completion without an unresolvable label, and the
	# verdict must be decidable. This is what proves the fallback contract
	# holds across the WHOLE roster, not just the moves a test happens to name.
	var reg := AnimBehaviorRegistry.new()
	var disp := AnimDispatcher.new(reg)
	var moves: Dictionary = {}
	for id in range(1, 1000):
		var label := AnimData.script_for_move(id)
		if label != "":
			moves[id] = label

	_chk("bound move scripts found (%d)" % moves.size(), moves.size() > 900)

	var undecidable := 0
	var dangling := ""
	var behaviors := {}
	for id in moves:
		var verdict := disp.verdict_for_move(int(id))
		if int(verdict.get("reason", -1)) == AnimDispatcher.Reason.NO_SCRIPT:
			undecidable += 1
		for symbol in (verdict.get("missing", []) as Array):
			var s := str(symbol)
			if s.begins_with("<missing label"):
				dangling = "%d: %s" % [id, s]
			behaviors[s] = true
	_chk("every bound move yields a decidable verdict (%d undecidable)"
			% undecidable, undecidable == 0)
	_chk("no move's script reaches an unresolvable label (found: '%s')"
			% dangling, dangling == "")

	# With an empty registry every single move must fall back. This is the
	# statement that makes M36B safe to land before any behavior exists.
	var cov := disp.coverage(moves.keys())
	_chk("with no behaviors registered, 0 moves play (playable=%d)"
			% int(cov["playable"]), int(cov["playable"]) == 0)
	# Secret Power's body is literally just `end` -- upstream remaps it at
	# launch to whichever script the terrain calls for, so the placeholder is
	# never executed. It therefore falls back as an EMPTY_SCRIPT rather than
	# as behavior-blocked, and is the only move in that bucket.
	_chk("every move with real content is behavior-blocked (%d of %d)"
			% [int(cov["blocked"]), moves.size()],
			int(cov["blocked"]) == moves.size() - int(cov["no_script"]))
	_chk("exactly one move falls back as an empty script (Secret Power)",
			int(cov["no_script"]) == 1)

	# The distinct-behavior count is the real size of the remaining port --
	# recorded here so M36C/D can see it move.
	print("  [M36B] %d distinct behaviors referenced across %d move scripts"
			% [behaviors.size(), moves.size()])
	var top: Array = cov["top_blockers"]
	if top.size() >= 3:
		print("  [M36B] top blockers: %s (%d moves), %s (%d), %s (%d)"
				% [top[0]["symbol"], top[0]["moves"],
					top[1]["symbol"], top[1]["moves"],
					top[2]["symbol"], top[2]["moves"]])
	_chk("the remaining port is sized (%d distinct behaviors)"
			% behaviors.size(), behaviors.size() > 100)
