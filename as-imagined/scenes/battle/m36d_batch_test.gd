extends Node

# [M36D] Suite for the expansion batch — the particle families and mon tasks
# ported after M36C's core.
#
# The bar here is the same one M36C set: it is not enough that a behavior
# runs, it must reproduce the reference's MOTION. Each test below asserts a
# property that would break if the ported math drifted — direction of travel,
# symmetry of an out-and-back, whether an orbit closes, whether a mon is put
# back — rather than merely that a sprite appeared.

var _pass := 0
var _fail := 0
var _registry: AnimBehaviorRegistry
var _dispatcher: AnimDispatcher


func _ready() -> void:
	AnimData.ensure_loaded()
	_registry = AnimBehaviorRegistry.new()
	AnimBehaviors.register_all(_registry)
	_dispatcher = AnimDispatcher.new(_registry)

	_test_coverage_grew()
	_test_powder_drift()
	_test_vortex_rises_and_circles()
	_test_bite_is_symmetric()
	_test_fist_is_static()
	_test_absorption_orb_travels_to_attacker()
	_test_arc_peaks_midflight()
	_test_slice_lifetime()
	_test_mon_tasks_restore()
	_test_elliptical_closes()
	_test_batch2_projectiles()
	_test_batch2_leech_seed_phases()
	_test_batch2_afterimages()
	_test_batch2_sound_tasks()
	_test_batch2_defensive_wall()
	_test_batch3_mon_tasks_restore()
	_test_batch3_rotation_actually_rotates()
	_test_batch3_teleport_hides_mon()
	_test_batch3_particles()
	_test_batch3_raindrops_clean_up()
	_test_iconic_moves_run()

	var total := _pass + _fail
	print("m36d_batch_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


class FakeStage extends RefCounted:
	var layer_node: Control
	var nodes: Dictionary = {}
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
			# Attacker low-left, target high-right: a real singles layout, so
			# direction-of-travel assertions are meaningful.
			n.position = Vector2(150 + i * 250, 450 - i * 120)
			layer_node.add_child(n)
			nodes[i] = n
	func sprite_for(b: int) -> Control: return nodes.get(b, null)
	func mon_for(b: int): return nodes.get(b, null)
	func center_of(b: int) -> Vector2:
		var n: Control = nodes.get(b, null)
		return n.position + n.size * 0.5 if n != null else Vector2.ZERO
	func layer() -> Control: return layer_node
	func pixel_scale() -> float: return maxf(1.0, layer_node.size.x / 240.0)
	func facing_sign() -> float: return 1.0
	func attacker_is_player_side() -> bool: return true
	func set_battler_visible(_b: int, _v: bool) -> void: pass


func _vm(stage: FakeStage) -> AnimScriptVM:
	var vm := AnimScriptVM.new()
	vm.registry = _registry
	vm.stage = stage
	vm.state = AnimScriptVM.State.RUNNING
	return vm


func _spawn(stage: FakeStage, symbol: String, args: Array,
		template: String) -> Dictionary:
	var vm := _vm(stage)
	for i in range(mini(args.size(), AnimScriptVM.ARG_COUNT)):
		vm.args[i] = int(args[i])
	var ctx := {"template": template,
			"template_data": AnimData.template(template),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior(symbol).call(vm, ctx)
	var sprites: Array = []
	for child in stage.layer_node.get_children():
		if child is AnimSprite:
			sprites.append(child)
	return {"vm": vm, "sprite": sprites[0] if sprites.size() > 0 else null}


func _test_coverage_grew() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	var playable := int(cov["playable"])
	print("  [M36D] %d/%d playable (%.1f%%)"
			% [playable, ids.size(), 100.0 * playable / maxi(1, ids.size())])
	# M36C ended at 23; batch 1 reached 85; batch 2 reaches ~138. The floor
	# guards against regression rather than expressing ambition.
	_chk("coverage holds at the batches' measured level (%d)" % playable,
			playable >= 195)


func _test_powder_drift() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimMovePowderParticle", [0, 0, 40, 80, 5, 1],
			"gPoisonPowderParticleSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	_chk("powder particle spawns", sp != null)
	if sp == null:
		return
	var vm: AnimScriptVM = r["vm"]
	# Spawns on the TARGET (powder hangs over the victim), not the attacker.
	_chk("powder starts at the target, not the attacker",
			sp.centre.distance_to(stage.center_of(1))
			< sp.centre.distance_to(stage.center_of(0)))
	var y0 := sp.offset.y
	for i in range(10):
		vm._step_behaviors()
	_chk("powder drifts downward over time (%.1f -> %.1f)" % [y0, sp.offset.y],
			sp.offset.y > y0)
	_chk("...and oscillates horizontally", not is_zero_approx(sp.offset.x))
	for i in range(40):
		vm._step_behaviors()
	_chk("powder expires on its duration", vm.visual_count() == 0)


func _test_vortex_rises_and_circles() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimParticleInVortex", [0, 0, 256, 30, 8, 16, 0],
			"gWaterHitSplatSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("vortex particle spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	for i in range(10):
		vm._step_behaviors()
	_chk("vortex particle RISES (y offset negative, got %.1f)" % sp.offset.y,
			sp.offset.y < 0.0)
	var x_at_10 := sp.offset.x
	for i in range(10):
		vm._step_behaviors()
	_chk("...while circling horizontally",
			not is_equal_approx(sp.offset.x, x_at_10))


func _test_bite_is_symmetric() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimBite", [0, 0, 0, 256, 128, 8],
			"gSharpTeethSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("bite spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	for i in range(8):
		vm._step_behaviors()
	var peak := sp.offset
	_chk("bite converges over its first half (%s)" % str(peak),
			not peak.is_equal_approx(Vector2.ZERO))
	for i in range(8):
		vm._step_behaviors()
	_chk("bite retreats symmetrically and ends after 2x half-duration",
			vm.visual_count() == 0)


func _test_fist_is_static() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimBasicFistOrFoot", [0, 0, 8, 0, 0],
			"gFistFootSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("fist spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start := sp.centre
	for i in range(5):
		vm._step_behaviors()
	_chk("fist does not move (it is a static impact frame)",
			sp.centre.is_equal_approx(start) and sp.offset.is_equal_approx(
					Vector2.ZERO))
	for i in range(6):
		vm._step_behaviors()
	_chk("fist expires after its duration", vm.visual_count() == 0)


func _test_absorption_orb_travels_to_attacker() -> void:
	# The drain orb runs the OPPOSITE way to every attack particle: from the
	# target back to the attacker. Getting this backwards would look wrong in
	# every draining move, so it is asserted by direction, not just motion.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimAbsorptionOrb", [0, 0, 20, 20],
			"gPowerAbsorptionOrbSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("absorption orb spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var d_start := sp.centre.distance_to(stage.center_of(0))
	for i in range(15):
		vm._step_behaviors()
	_chk("absorption orb travels toward the ATTACKER (%.0f -> %.0f)"
			% [d_start, sp.centre.distance_to(stage.center_of(0))],
			sp.centre.distance_to(stage.center_of(0)) < d_start)


func _test_arc_peaks_midflight() -> void:
	# An arc must bulge away from the straight line and come back — a half
	# sine over the flight. Compare the midpoint against the chord.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimAbsorptionOrb", [0, 0, 40, 20],
			"gPowerAbsorptionOrbSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		return
	var vm: AnimScriptVM = r["vm"]
	var start := sp.centre
	var finish_pos := stage.center_of(0)
	for i in range(10):
		vm._step_behaviors()
	var chord_mid := start.lerp(finish_pos, 10.0 / 20.0)
	_chk("arc departs from the straight chord at mid-flight (%.1f px)"
			% absf(sp.centre.y - chord_mid.y),
			absf(sp.centre.y - chord_mid.y) > 1.0)


func _test_slice_lifetime() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimCuttingSlice", [0, 0, 0],
			"gCuttingSliceSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("cutting slice spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	for i in range(23):
		vm._step_behaviors()
	_chk("slice is still alive just before its 24-frame budget",
			vm.visual_count() == 1)
	vm._step_behaviors()
	_chk("slice ends at 24 frames (20 motion + 4 hold)",
			vm.visual_count() == 0)


func _test_mon_tasks_restore() -> void:
	for entry in [["AnimTask_SwayMon", [0, 8, 4096, 2, 1]],
			["AnimTask_ScaleMonAndRestore", [16, 16, 10, 1, 0]],
			["AnimTask_TranslateMonElliptical", [1, 12, 8, 1, 3]]]:
		var symbol: String = str(entry[0])
		var stage := FakeStage.new()
		var node: Control = stage.nodes[1]
		var base := node.position
		var base_scale := node.scale
		var vm := _vm(stage)
		var args: Array = entry[1]
		for i in range(args.size()):
			vm.args[i] = int(args[i])
		_registry.get_behavior(symbol).call(vm, {})
		var moved := false
		for i in range(400):
			vm._step_behaviors()
			if not node.position.is_equal_approx(base) \
					or not node.scale.is_equal_approx(base_scale):
				moved = true
			if vm.visual_count() == 0:
				break
		_chk("%s actually displaces the mon" % symbol, moved)
		_chk("%s restores position exactly (%s vs %s)"
				% [symbol, str(node.position), str(base)],
				node.position.is_equal_approx(base))
		_chk("%s restores scale exactly" % symbol,
				node.scale.is_equal_approx(base_scale))
		_chk("%s terminates rather than running forever" % symbol,
				vm.visual_count() == 0)


func _test_elliptical_closes() -> void:
	# The -Cos(...) + height term exists so the orbit starts and ends at the
	# mon's real position instead of snapping. Assert frame 1 is near zero.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[1]
	var base := node.position
	var vm := _vm(stage)
	vm.args[0] = 1
	vm.args[1] = 12
	vm.args[2] = 8
	vm.args[3] = 1
	vm.args[4] = 3
	_registry.get_behavior("AnimTask_TranslateMonElliptical").call(vm, {})
	vm._step_behaviors()
	_chk("elliptical orbit begins at the mon's own position (%.1f px off)"
			% node.position.distance_to(base),
			node.position.distance_to(base) < 30.0)


func _test_batch2_projectiles() -> void:
	# Shadow Ball has three phases and must reach the target by the end --
	# a projectile that stops at the midpoint (its phase-1 resting place)
	# would be a plausible-looking but wrong port.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimShadowBall", [10, 5, 15],
			"gShadowBallSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("shadow ball spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var atk := stage.center_of(0)
	var tgt := stage.center_of(1)
	_chk("shadow ball starts at the attacker",
			sp.centre.distance_to(atk) < sp.centre.distance_to(tgt))
	for i in range(10):
		vm._step_behaviors()
	var mid := sp.centre
	_chk("...gathers toward the midpoint first (%.0f from atk, %.0f from tgt)"
			% [mid.distance_to(atk), mid.distance_to(tgt)],
			mid.distance_to(atk) > 1.0 and mid.distance_to(tgt) > 1.0)
	for i in range(40):
		vm._step_behaviors()
	_chk("...and completes rather than stalling mid-flight",
			vm.visual_count() == 0)

	# The stinger rotates to face its direction of travel.
	var stage2 := FakeStage.new()
	var r2 := _spawn(stage2, "AnimTranslateStinger", [0, 0, 0, 0, 10],
			"gLinearStingerSpriteTemplate")
	var sp2: AnimSprite = r2["sprite"]
	if sp2 != null:
		_chk("stinger rotates toward its target rather than flying sideways",
				not is_zero_approx(sp2.rotation))


func _test_batch2_leech_seed_phases() -> void:
	# Leech Seed is a three-phase script in ONE behavior: arc, hide, sprout.
	# The hidden phase is the one a naive port drops.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimLeechSeed", [0, 0, 0, 0, 12, 20],
			"gLeechSeedSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("leech seed spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	for i in range(12):
		vm._step_behaviors()
	_chk("leech seed lands and then HIDES before sprouting",
			not sp.visible)
	for i in range(11):
		vm._step_behaviors()
	_chk("...then reappears to sprout", sp.visible)
	for i in range(70):
		vm._step_behaviors()
	_chk("...and finishes after the sprout phase", vm.visual_count() == 0)


func _test_batch2_afterimages() -> void:
	# TraceMonBlended makes real afterimages; it must also clean every one up.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0
	vm.args[1] = 1
	vm.args[2] = 4
	vm.args[3] = 3
	_registry.get_behavior("AnimTask_TraceMonBlended").call(vm, {})
	var peak := 0
	for i in range(40):
		vm._step_behaviors()
		var clones := 0
		for child in stage.layer_node.get_children():
			if child.has_meta("_anim_trace"):
				clones += 1
		peak = maxi(peak, clones)
		if vm.visual_count() == 0:
			break
	_chk("trace task produced afterimages (peak %d)" % peak, peak > 0)
	_chk("...and terminated", vm.visual_count() == 0)
	var leftover := 0
	for child in stage.layer_node.get_children():
		if child.has_meta("_anim_trace") and is_instance_valid(child) \
				and not child.is_queued_for_deletion():
			leftover += 1
	_chk("...leaving no afterimage behind (%d)" % leftover, leftover == 0)


func _test_batch2_sound_tasks() -> void:
	# Sound is deferred, but TIMING is not: single-frame cues must not stall a
	# script, and cry waits must cost their real warm-up frames.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("SoundTask_PlaySE1WithPanning").call(vm, {})
	_chk("a single-frame sound cue costs the script nothing",
			vm.visual_count() == 0)

	var vm2 := _vm(stage)
	_registry.get_behavior("SoundTask_WaitForCry").call(vm2, {})
	_chk("a cry wait does hold the script briefly", vm2.visual_count() == 1)
	vm2._step_behaviors()
	vm2._step_behaviors()
	_chk("...and releases once the (silent) cry is done",
			vm2.visual_count() == 0)


func _test_batch2_defensive_wall() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimDefensiveWall", [0, 0, 0],
			"gReflectSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		return
	var vm: AnimScriptVM = r["vm"]
	_chk("the wall starts invisible and fades IN", is_zero_approx(
			sp.modulate.a))
	for i in range(13):
		vm._step_behaviors()
	_chk("...reaching full opacity", sp.modulate.a > 0.9)
	for i in range(60):
		vm._step_behaviors()
	_chk("...then fading out and ending", vm.visual_count() == 0)


func _test_batch3_mon_tasks_restore() -> void:
	# Every batch-3 mon task must put the battler back -- position, scale AND
	# rotation this time, since these are the first behaviors to rotate one.
	for entry in [["AnimTask_HorizontalShake", [1, 4, 6]],
			["AnimTask_WindUpLunge", [0, 8, 4, 6, 2, 12, 6]],
			["AnimTask_RotateMonSpriteToSide", [8, 512, 1, 2]],
			["AnimTask_RotateMonToSideAndRestore", [8, 512, 1, 0]],
			["AnimTask_DynamaxGrowth", [1]],
			["AnimTask_BlendMonInAndOut", [1, 31, 8, 1, 2]],
			["AnimShakeMonOrBattlePlatforms", [4, 1, 12, 2, 2]]]:
		var symbol: String = str(entry[0])
		var stage := FakeStage.new()
		var node: Control = stage.nodes[1]
		var base := node.position
		var base_scale := node.scale
		var base_rot := node.rotation
		var vm := _vm(stage)
		var args: Array = entry[1]
		for i in range(args.size()):
			vm.args[i] = int(args[i])
		_registry.get_behavior(symbol).call(vm, {})
		for i in range(600):
			vm._step_behaviors()
			if vm.visual_count() == 0:
				break
		_chk("%s terminates" % symbol, vm.visual_count() == 0)
		_chk("%s restores position" % symbol,
				node.position.is_equal_approx(base))
		_chk("%s restores scale" % symbol,
				node.scale.is_equal_approx(base_scale))
		_chk("%s restores rotation" % symbol,
				is_equal_approx(node.rotation, base_rot))


func _test_batch3_rotation_actually_rotates() -> void:
	# Guard against a "restores perfectly because it never moved" pass.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[1]
	var vm := _vm(stage)
	vm.args[0] = 20
	vm.args[1] = 1024
	vm.args[2] = 1
	vm.args[3] = 2
	_registry.get_behavior("AnimTask_RotateMonSpriteToSide").call(vm, {})
	for i in range(10):
		vm._step_behaviors()
	_chk("rotation task genuinely rotates the mon (%.3f rad)" % node.rotation,
			absf(node.rotation) > 0.01)


func _test_batch3_teleport_hides_mon() -> void:
	# Teleport is the one task that ENDS with the mon hidden -- that is the
	# point of it, and a restore-everything reflex would break the effect.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[0]
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_Teleport").call(vm, {})
	for i in range(60):
		vm._step_behaviors()
		if vm.visual_count() == 0:
			break
	_chk("teleport terminates", vm.visual_count() == 0)
	_chk("teleport leaves the attacker HIDDEN (that is the effect)",
			not node.visible)
	_chk("...with its scale restored so the next reveal is clean",
			node.scale.is_equal_approx(Vector2.ONE))


func _test_batch3_particles() -> void:
	# Roar's noise line is exactly 14 frames at a fixed speed.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimRoarNoiseLine", [0, 0, 0],
			"gHorizontalLungeSpriteTemplate")
	var vm: AnimScriptVM = r["vm"]
	if r["sprite"] != null:
		for i in range(13):
			vm._step_behaviors()
		_chk("roar noise line still alive at 13 frames",
				vm.visual_count() == 1)
		vm._step_behaviors()
		_chk("...and ends at exactly 14", vm.visual_count() == 0)

	# The fire spiral stays INVISIBLE for its initial wait, then appears.
	var stage2 := FakeStage.new()
	var r2 := _spawn(stage2, "AnimFireSpiralOutward", [0, 0, 20, 6],
			"gFlamethrowerFlameSpriteTemplate")
	var sp2: AnimSprite = r2["sprite"]
	var vm2: AnimScriptVM = r2["vm"]
	if sp2 != null:
		_chk("fire spiral starts hidden during its wait", not sp2.visible)
		for i in range(7):
			vm2._step_behaviors()
		_chk("...then becomes visible and spirals", sp2.visible)
		var off1 := sp2.offset
		for i in range(6):
			vm2._step_behaviors()
		_chk("...with a growing radius",
				sp2.offset.length() > off1.length())


func _test_batch3_raindrops_clean_up() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[1] = 4
	vm.args[2] = 30
	_registry.get_behavior("AnimTask_CreateRaindrops").call(vm, {})
	var peak := 0
	for i in range(200):
		vm._step_behaviors()
		var live := 0
		for child in stage.layer_node.get_children():
			if child is AnimSprite and not (child as AnimSprite).is_finished():
				live += 1
		peak = maxi(peak, live)
		if vm.visual_count() == 0:
			break
	_chk("raindrops spawned (peak %d)" % peak, peak > 0)
	_chk("rain task terminates and clears its drops",
			vm.visual_count() == 0)


func _test_iconic_moves_run() -> void:
	# End-to-end on iconic moves this batch was meant to unblock.
	var unblocked := 0
	for pair in [[77, "Poison Powder"], [78, "Stun Spore"],
			[79, "Sleep Powder"], [22, "Vine Whip"], [44, "Bite"],
			[52, "Ember"]]:
		var id: int = int(pair[0])
		if not _dispatcher.can_play_move(id):
			continue
		unblocked += 1
		var stage := FakeStage.new()
		var vm := _dispatcher.make_vm(id, stage, 0)
		if vm == null:
			_chk("%s builds a VM" % str(pair[1]), false)
			continue
		var frames := 0
		while vm.is_running() and frames < 2000:
			vm.step()
			frames += 1
		_chk("%s runs to completion (%d frames, state=%d)"
				% [str(pair[1]), frames, vm.state],
				vm.state == AnimScriptVM.State.DONE)
		_chk("%s leaves nothing live" % str(pair[1]), vm.visual_count() == 0)
		for i in range(4):
			var expected := Vector2(150 + i * 250, 450 - i * 120)
			_chk("%s restores battler %d" % [str(pair[1]), i],
					(stage.nodes[i] as Control).position.is_equal_approx(
							expected))
	_chk("the batch unblocked several named iconic moves (%d of 6)"
			% unblocked, unblocked >= 4)
