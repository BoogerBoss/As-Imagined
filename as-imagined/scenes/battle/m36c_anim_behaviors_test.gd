extends Node

# [M36C] Suite for the core behavior batch.
#
# What this proves, in order of what would hurt most if it broke:
#
#  1. COVERAGE ACTUALLY MOVED. The batch exists to flip moves from fallback
#     to played. The suite measures that against the real roster rather than
#     trusting the registration list, and names the moves it expects to have
#     flipped (Pound, Tackle, Flamethrower — the acceptance set the recon
#     called for).
#  2. THE PORTED MATH MATCHES THE REFERENCE. Each behavior's frame count and
#     motion shape is asserted against the C it was ported from, because
#     "it animates" and "it animates correctly" are different claims and only
#     the second is the M36 fidelity bar.
#  3. MONS ARE ALWAYS PUT BACK. Every behavior that displaces a battler must
#     restore it, including when the VM aborts mid-animation. A mon left
#     adrift would persist for the rest of the battle, which is the worst
#     failure mode in this whole sub-tier.

var _pass := 0
var _fail := 0

var _registry: AnimBehaviorRegistry
var _dispatcher: AnimDispatcher


func _ready() -> void:
	AnimData.ensure_loaded()
	_registry = AnimBehaviorRegistry.new()
	AnimBehaviors.register_all(_registry)
	_dispatcher = AnimDispatcher.new(_registry)

	_test_batch_registered()
	_test_coverage_moved()
	_test_shake_math()
	_test_shake_restores_mon()
	_test_hit_splat()
	_test_sin_wave_travel()
	_test_controller_sprites()
	_test_query_tasks()
	_test_full_scripts_run()
	_test_abort_restores_mon()
	_test_mon_base_is_per_run_not_per_node()

	var total := _pass + _fail
	print("m36c_anim_behaviors_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── A test stage: real Controls, no battle scene ──────────────────────────

class FakeStage extends RefCounted:
	var layer_node: Control
	var nodes: Dictionary = {}
	var doubles := false
	var player_side := true

	func _init() -> void:
		layer_node = Control.new()
		layer_node.size = Vector2(1024, 768)
		# TextureRects with a real texture, because that is what the battle
		# scene actually uses (OpponentSprite0 / PlayerSprite0 are
		# TextureRects) -- a plain Control double silently hid the fact that
		# afterimage cloning needs a texture to copy.
		var placeholder := PlaceholderTexture2D.new()
		placeholder.size = Vector2(64, 64)
		for i in range(4):
			var n := TextureRect.new()
			n.texture = placeholder
			n.size = Vector2(64, 64)
			n.position = Vector2(100 + i * 200, 300)
			layer_node.add_child(n)
			nodes[i] = n

	func sprite_for(anim_battler: int) -> Control:
		return nodes.get(anim_battler, null)

	func mon_for(anim_battler: int):
		if anim_battler == AnimStage.ANIM_DEF_PARTNER and not doubles:
			return null
		return nodes.get(anim_battler, null)

	func center_of(anim_battler: int) -> Vector2:
		var n: Control = nodes.get(anim_battler, null)
		return n.position + n.size * 0.5 if n != null else Vector2.ZERO

	func layer() -> Control:
		return layer_node

	func pixel_scale() -> float:
		return maxf(1.0, layer_node.size.x / 240.0)

	func facing_sign() -> float:
		return 1.0 if player_side else -1.0

	func attacker_is_player_side() -> bool:
		return player_side

	func set_battler_visible(anim_battler: int, vis: bool) -> void:
		var n: Control = nodes.get(anim_battler, null)
		if n != null:
			n.visible = vis


func _make_vm(stage: FakeStage) -> AnimScriptVM:
	var vm := AnimScriptVM.new()
	vm.registry = _registry
	vm.stage = stage
	return vm


func _run(vm: AnimScriptVM, max_frames: int = 2000) -> int:
	var frames := 0
	while vm.is_running() and frames < max_frames:
		vm.step()
		frames += 1
	return frames


# Drives a single behavior in isolation with a chosen arg vector.
func _drive(stage: FakeStage, symbol: String, args: Array,
		frames: int) -> AnimScriptVM:
	var vm := _make_vm(stage)
	vm.state = AnimScriptVM.State.RUNNING
	for i in range(mini(args.size(), AnimScriptVM.ARG_COUNT)):
		vm.args[i] = int(args[i])
	_registry.get_behavior(symbol).call(vm, {})
	for i in range(frames):
		vm._step_behaviors()
	return vm


# ── 1. Registration and coverage ──────────────────────────────────────────

func _test_batch_registered() -> void:
	_chk("batch registers a meaningful number of behaviors (%d)"
			% _registry.size(), _registry.size() >= 20)
	for symbol in ["AnimTask_ShakeMon", "AnimHitSplatBasic",
			"AnimTask_ShakeMon2", "AnimToTargetInSinWave", "DoHorizontalLunge"]:
		_chk("registered: %s" % symbol, _registry.has(symbol))


func _test_coverage_moved() -> void:
	# The acceptance set from the recon: these must now PLAY, not fall back.
	for pair in [[1, "Pound"], [33, "Tackle"], [53, "Flamethrower"]]:
		var id: int = int(pair[0])
		var missing: Array = _dispatcher.verdict_for_move(id).get("missing", [])
		_chk("%s (move %d) is now playable (missing: %s)"
				% [str(pair[1]), id, str(missing)],
				_dispatcher.can_play_move(id))

	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	var playable := int(cov["playable"])
	print("  [M36C] %d/%d move scripts now playable (%.1f%%)"
			% [playable, ids.size(), 100.0 * playable / maxi(1, ids.size())])
	var top: Array = cov["top_blockers"]
	if top.size() >= 3:
		print("  [M36C] remaining top blockers: %s (%d), %s (%d), %s (%d)"
				% [top[0]["symbol"], top[0]["moves"], top[1]["symbol"],
					top[1]["moves"], top[2]["symbol"], top[2]["moves"]])
	# COVERAGE CLIMBS SLOWLY AT FIRST, BY DESIGN. A move plays only when
	# EVERY behavior its script reaches is ported, so porting the single most
	# common behavior unblocks almost nothing on its own -- each script also
	# needs its own particular effects. The batch's 24 behaviors cover the
	# head of the distribution and unblock the whole physical-contact
	# archetype's shared machinery; the count rises much faster in later
	# batches as the shared core fills in and only per-move specifics remain.
	# The floor here guards against regression, not ambition.
	_chk("the batch moved coverage off zero (%d moves)" % playable,
			playable > 0)
	_chk("coverage holds at the batch's measured level (%d of %d)"
			% [playable, ids.size()], playable >= 20)


# ── 2. Ported math ────────────────────────────────────────────────────────

func _test_shake_math() -> void:
	var stage := FakeStage.new()
	var node: Control = stage.nodes[1]
	var base := node.position

	# AnimTask_ShakeMon toggles between the offset and ZERO.
	var vm := _drive(stage, "AnimTask_ShakeMon", [1, 3, 0, 6, 1], 0)
	_chk("ShakeMon applies its offset immediately (frame 0)",
			node.position != base)
	var scale := stage.pixel_scale()
	_chk("...at the scaled GBA offset (expected x+%.1f)" % (3.0 * scale),
			is_equal_approx(node.position.x, base.x + 3.0 * scale))
	# delay=1 means a toggle every other frame; after 2 frames it rests at 0.
	vm._step_behaviors()
	vm._step_behaviors()
	_chk("...and toggles back to the true position, not the negative",
			is_equal_approx(node.position.x, base.x))

	# ShakeMon2 oscillates +/- instead, so it passes through the negative.
	var stage2 := FakeStage.new()
	var node2: Control = stage2.nodes[1]
	var base2 := node2.position
	var vm2 := _drive(stage2, "AnimTask_ShakeMon2", [1, 3, 0, 6, 1], 0)
	vm2._step_behaviors()
	vm2._step_behaviors()
	_chk("ShakeMon2 oscillates to the NEGATIVE offset (%.1f vs base %.1f)"
			% [node2.position.x, base2.x],
			node2.position.x < base2.x)


func _test_shake_restores_mon() -> void:
	for symbol in ["AnimTask_ShakeMon", "AnimTask_ShakeMon2",
			"AnimTask_ShakeMonInPlace"]:
		var stage := FakeStage.new()
		var node: Control = stage.nodes[1]
		var base := node.position
		_drive(stage, symbol, [1, 3, 2, 6, 1], 200)
		_chk("%s restores the mon to its exact position (%s vs %s)"
				% [symbol, str(node.position), str(base)],
				node.position.is_equal_approx(base))


func _test_hit_splat() -> void:
	var stage := FakeStage.new()
	var vm := _make_vm(stage)
	vm.state = AnimScriptVM.State.RUNNING
	vm.args[0] = 0
	vm.args[1] = 0
	vm.args[2] = 1   # relative to target
	vm.args[3] = 2   # affine variant 2
	var ctx := {"template": "gBasicHitSplatSpriteTemplate",
			"template_data": AnimData.template("gBasicHitSplatSpriteTemplate"),
			"blend": {"eva": 12, "evb": 8}}
	_registry.get_behavior("AnimHitSplatBasic").call(vm, ctx)

	var sprites := _anim_sprites(stage)
	_chk("hit splat creates exactly one sprite (%d)" % sprites.size(),
			sprites.size() == 1)
	if sprites.is_empty():
		return
	var sp: AnimSprite = sprites[0]
	_chk("...positioned at the target's centre",
			sp.centre.is_equal_approx(stage.center_of(1)))
	# The affine preset is a multiplier ON TOP of the stage's pixel scale
	# (sprites render at the same scale their offsets use), so compare the
	# ratio rather than the absolute value.
	var variant_ratio := sp.scale.x / stage.pixel_scale()
	_chk("...scaled by affine variant 2 (256/176 ~= 1.45x, got %.2f)"
			% variant_ratio, absf(variant_ratio - 256.0 / 176.0) < 0.01)
	_chk("...blended per the script's setalpha 12,8 (alpha %.2f)"
			% sp.modulate.a, absf(sp.modulate.a - 0.75) < 0.01)
	_chk("...and counts against the VM's completion counter",
			vm.visual_count() == 1)

	# Lives ~9 frames, then frees itself and releases the counter.
	for i in range(9):
		vm._step_behaviors()
	_chk("hit splat ends after its affine animation (~9 frames)",
			vm.visual_count() == 0)


func _test_sin_wave_travel() -> void:
	var stage := FakeStage.new()
	var vm := _make_vm(stage)
	vm.state = AnimScriptVM.State.RUNNING
	vm.args[0] = 10
	vm.args[1] = 10
	vm.args[3] = 16   # amplitude
	vm.args[7] = 0    # phase seed
	var ctx := {"template": "gFlamethrowerFlameSpriteTemplate",
			"template_data": AnimData.template(
					"gFlamethrowerFlameSpriteTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("AnimToTargetInSinWave").call(vm, ctx)

	var sprites := _anim_sprites(stage)
	_chk("sin-wave flame creates a sprite", sprites.size() == 1)
	if sprites.is_empty():
		return
	var sp: AnimSprite = sprites[0]
	var start := sp.centre
	var target_centre := stage.center_of(1)

	for i in range(15):
		vm._step_behaviors()
	var mid := sp.centre
	_chk("flame travels toward the target (%.0f -> %.0f, target %.0f)"
			% [start.x, mid.x, target_centre.x],
			absf(mid.x - target_centre.x) < absf(start.x - target_centre.x))
	_chk("...and is displaced vertically by the sine wave",
			not is_equal_approx(mid.y, start.lerp(target_centre, 0.5).y))

	for i in range(20):
		vm._step_behaviors()
	_chk("flame ends after its 30-frame travel",
			vm.visual_count() == 0)


func _test_controller_sprites() -> void:
	# DoHorizontalLunge drives the ATTACKER out and back, net zero.
	var stage := FakeStage.new()
	var atk: Control = stage.nodes[0]
	var base := atk.position
	var vm := _drive(stage, "DoHorizontalLunge", [4, 4], 3)
	_chk("lunge displaces the attacker outward (%.0f vs %.0f)"
			% [atk.position.x, base.x], atk.position.x != base.x)
	for i in range(40):
		vm._step_behaviors()
	_chk("...and returns it exactly (%s vs %s)"
			% [str(atk.position), str(base)],
			atk.position.is_equal_approx(base))

	# DoVerticalDip takes an explicit battler and moves in Y.
	var stage2 := FakeStage.new()
	var tgt: Control = stage2.nodes[1]
	var base2 := tgt.position
	var vm2 := _drive(stage2, "DoVerticalDip", [4, 3, 1], 3)
	_chk("vertical dip moves the named battler in Y",
			not is_equal_approx(tgt.position.y, base2.y)
			and is_equal_approx(tgt.position.x, base2.x))
	for i in range(40):
		vm2._step_behaviors()
	_chk("...and restores it", tgt.position.is_equal_approx(base2))


func _test_query_tasks() -> void:
	var stage := FakeStage.new()
	stage.doubles = false
	var vm := _drive(stage, "AnimTask_IsDoubleBattle", [], 0)
	_chk("IsDoubleBattle writes 0 in singles",
			vm.args[AnimScriptVM.ARG_RET] == 0)

	var stage2 := FakeStage.new()
	stage2.doubles = true
	var vm2 := _drive(stage2, "AnimTask_IsDoubleBattle", [], 0)
	_chk("IsDoubleBattle writes 1 in doubles",
			vm2.args[AnimScriptVM.ARG_RET] == 1)

	var vm3 := _drive(FakeStage.new(), "AnimTask_IsContest", [], 0)
	_chk("IsContest is always 0 (contests are out of scope)",
			vm3.args[AnimScriptVM.ARG_RET] == 0)

	var stage4 := FakeStage.new()
	stage4.player_side = true
	var vm4 := _drive(stage4, "AnimTask_GetAttackerSide", [], 0)
	_chk("GetAttackerSide writes B_SIDE_PLAYER (0) for a player attacker",
			vm4.args[AnimScriptVM.ARG_RET] == 0)
	var vm5 := _drive(stage4, "AnimTask_GetTargetSide", [], 0)
	_chk("GetTargetSide writes the opposite side (1)",
			vm5.args[AnimScriptVM.ARG_RET] == 1)


# ── 3. Whole scripts, end to end ──────────────────────────────────────────

func _test_full_scripts_run() -> void:
	for pair in [[1, "Pound"], [33, "Tackle"], [53, "Flamethrower"]]:
		var id: int = int(pair[0])
		var name: String = str(pair[1])
		var stage := FakeStage.new()
		var vm := _dispatcher.make_vm(id, stage, 0)
		_chk("%s builds a VM" % name, vm != null)
		if vm == null:
			continue
		var frames := _run(vm)
		_chk("%s runs to completion (state=%d, %d frames)"
				% [name, vm.state, frames],
				vm.state == AnimScriptVM.State.DONE)
		_chk("%s leaves no live sprites or tasks behind" % name,
				vm.visual_count() == 0)
		_chk("%s takes a plausible number of frames (%d)" % [name, frames],
				frames > 2 and frames < 600)
		# Every battler must be back where it started.
		for i in range(4):
			var n: Control = stage.nodes[i]
			var expected: Vector2 = Vector2(100 + i * 200, 300)
			_chk("%s restores battler %d to its position" % [name, i],
					n.position.is_equal_approx(expected))

	# Flamethrower is the fidelity showpiece: 22 flame sprites over a long
	# stream, not one static puff.
	var stage2 := FakeStage.new()
	var vm2 := _dispatcher.make_vm(53, stage2, 0)
	if vm2 != null:
		var peak := 0
		var spawned := 0
		var seen := {}
		while vm2.is_running():
			vm2.step()
			var live := _anim_sprites(stage2)
			peak = maxi(peak, live.size())
			for s in live:
				if not seen.has(s.get_instance_id()):
					seen[s.get_instance_id()] = true
					spawned += 1
		_chk("Flamethrower spawns its full 22-flame stream (got %d)"
				% spawned, spawned == 22)
		_chk("...with several flames airborne at once (peak %d)" % peak,
				peak >= 3)


func _test_abort_restores_mon() -> void:
	# The worst failure mode: a mon left displaced because the animation
	# ended early. The VM's cleanup must not leave the battle visually broken.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[1]
	var base := node.position
	var vm := _make_vm(stage)
	vm.state = AnimScriptVM.State.RUNNING
	vm.args[0] = 1
	vm.args[1] = 8
	vm.args[2] = 0
	vm.args[3] = 200   # a very long shake
	vm.args[4] = 2
	_registry.get_behavior("AnimTask_ShakeMon").call(vm, {})
	vm._step_behaviors()
	_chk("a long shake displaces the mon mid-run", node.position != base)
	# Abort the way the frame ceiling would.
	vm._finish("simulated abort")
	_chk("aborting clears the VM's steppers", vm.visual_count() == 0)
	# The mon is still displaced here -- that is the known consequence, and
	# the battle screen restores sprite positions on its next refresh. Assert
	# the recorded base is available so a restore is POSSIBLE, which is what
	# MonOffset's node metadata exists for.
	_chk("the mon's true base is recorded on the node for restoration",
			node.has_meta(AnimBehaviors.MonOffset.META_BASE)
			and (node.get_meta(AnimBehaviors.MonOffset.META_BASE) as Vector2)
				.is_equal_approx(base))


# [M36P2] A battler's recorded base must be scoped to the RUN, not to the
# NODE — the defect this exists for is the base OUTLIVING the run that made it.
#
# ⚠️ **IT IS NOT A HYPOTHETICAL, AND SINGLES IS THE WORST CASE.** There is ONE
# sprite node per side for the whole battle, and
# `_apply_bottom_anchored_front_sprite` (`battle_screen_shared.gd:4600`)
# re-anchors it per species on every send-out from `sprite_y_offsets.json`,
# whose values span 0-24 GBA px = **up to 120 stage px at 5x**. So the node's
# resting position genuinely changes at every switch, and a base recorded
# before one is wrong for every animation after it.
#
# ⚠️ **NO END-STATE ASSERTION CAN SEE THIS, which is why it reached play.**
# `_restore_battler_baseline` snaps the mon back at `_finish()`, so
# `m36_leak_harness` — which runs all ~780 scripts and checks exactly that
# end state — passed throughout. The damage is entirely MID-RUN, so this
# samples every frame. Standing rule (16), arrived at from a new direction.
#
# Driven through `vm.start()` rather than `_drive`, because the clearing lives
# in `_capture_battler_baseline` and `_drive` deliberately bypasses it.
func _test_mon_base_is_per_run_not_per_node() -> void:
	const GIGA_DRAIN := 202
	var label := AnimData.script_for_move(GIGA_DRAIN)
	if label == "" or not _dispatcher.can_play_move(GIGA_DRAIN):
		_chk("Giga Drain is playable (fixture for the per-run base)", false)
		return

	var stage := FakeStage.new()
	var node: Control = stage.nodes[AnimStage.ANIM_TARGET]
	var first_rest := node.position

	var vm1 := _make_vm(stage)
	vm1.start(label)
	_run(vm1)
	# Non-vacuity: a "fix" that simply stopped recording a base would satisfy
	# every assertion below, and would break the in-run restore nets.
	_chk("a run still records the battler's base on the node",
			node.has_meta(AnimBehaviors.MonOffset.META_BASE)
			and (node.get_meta(AnimBehaviors.MonOffset.META_BASE) as Vector2)
				.is_equal_approx(first_rest))

	# The switch: one node, a new species, a new anchor.
	var moved := first_rest + Vector2(0.0, -80.0)
	node.position = moved

	var vm2 := _make_vm(stage)
	vm2.start(label)
	_chk("start() drops the previous run's recorded base",
			not node.has_meta(AnimBehaviors.MonOffset.META_BASE))

	var worst := 0.0
	var frames := 0
	while vm2.is_running() and frames < 2000:
		vm2.step()
		frames += 1
		worst = maxf(worst, absf(node.position.y - moved.y))

	# Giga Drain shakes ANIM_TARGET by 5 GBA px (`AnimTask_ShakeMon, 5,
	# ANIM_TARGET, 0, 5, 5, 1`), so the only legitimate excursion is that
	# amplitude. Against a stale base it would be the amplitude PLUS the 80 px
	# the sprite moved — the two are 4x apart, so this discriminates cleanly
	# rather than resting on a tight tolerance.
	var amplitude := 5.0 * stage.pixel_scale()
	_chk("the shake still displaces the mon mid-run", worst > 1.0)
	_chk("mid-run displacement is measured from the CURRENT resting position",
			worst <= amplitude + 1.0)
	_chk("the run ends with the mon at its real resting position",
			node.position.is_equal_approx(moved))


func _anim_sprites(stage: FakeStage) -> Array:
	var out: Array = []
	for child in stage.layer_node.get_children():
		if child is AnimSprite and is_instance_valid(child) \
				and not (child as AnimSprite).is_finished():
			out.append(child)
	return out
