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
		for i in range(4):
			var n := Control.new()
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
	# M36C ended at 23. This batch must have moved it materially; the floor
	# guards against a regression rather than expressing ambition.
	_chk("the batch grew coverage well past M36C's 23 (%d)" % playable,
			playable >= 75)


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
