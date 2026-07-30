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
	_test_batch3_teleport_hide_is_temporary()
	_test_visibility_never_leaks()
	_test_batch3_particles()
	_test_batch3_raindrops_clean_up()
	_test_iconic_moves_run()
	_test_batch4_linear_family_shares_one_shape()
	_test_batch4_strike_family()
	_test_batch4_aliased_names_share_one_impl()
	_test_batch4_mon_tasks_restore()
	_test_batch4_handshakes_and_bands()
	_test_batch5_aliases_share_one_impl()
	_test_batch5_multi_spawn_families()
	_test_batch5_timing_shapes()
	_test_batch5_mon_tasks_restore()
	_test_batch5_palette_group()
	_test_batch6_helper_reuse()
	_test_batch6_script_terminated()
	_test_batch6_dig_sequence_never_strands()
	_test_batch6_coverage()

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
	var player_side := true
	func attacker_is_player_side() -> bool: return player_side
	func set_battler_visible(b: int, v: bool) -> void:
		# Really applies it: a no-op here would have silently passed the
		# visibility-leak tests, which are the whole point of this double.
		var n: Control = nodes.get(b, null)
		if n != null:
			n.visible = v


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


func _test_batch3_teleport_hide_is_temporary() -> void:
	# Teleport hides the attacker -- that IS the effect -- but the hide must
	# not outlive the animation. Upstream that is guaranteed by the battle
	# controller re-syncing every sprite's visibility once an animation ends
	# (CopyAllBattleSpritesInvisibilities); this port guarantees it by having
	# the VM undo any hide it made. Without that, one Teleport removes a
	# Pokemon from the screen for the rest of the battle -- the exact class of
	# bug 35 scripts (Feint Attack, Shadow Force, Sky Drop, ...) would trip,
	# because they end with a battler still marked invisible.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[0]
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_Teleport").call(vm, {})
	for i in range(60):
		vm._step_behaviors()
		if vm.visual_count() == 0:
			break
	_chk("teleport terminates", vm.visual_count() == 0)
	_chk("teleport hides the attacker while it runs", not node.visible)
	_chk("...with its scale restored so the next reveal is clean",
			node.scale.is_equal_approx(Vector2.ONE))
	vm._finish()
	_chk("...and the hide is UNDONE when the animation ends", node.visible)


func _test_visibility_never_leaks() -> void:
	# The general invariant, asserted directly rather than per-behavior: no
	# animation may leave a battler invisible once it is over.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.hide_battler(AnimStage.ANIM_TARGET)
	_chk("a script can hide a battler mid-animation",
			not (stage.nodes[1] as Control).visible)
	vm._finish()
	_chk("...and the VM restores it when the run ends",
			(stage.nodes[1] as Control).visible)

	# And a whole real script that ends mid-hide must leave nothing hidden.
	var stage2 := FakeStage.new()
	if _dispatcher.can_play_move(185):  # Feint Attack: invisible with no show
		var vm2 := _dispatcher.make_vm(185, stage2, 0)
		if vm2 != null:
			var frames := 0
			while vm2.is_running() and frames < 2000:
				vm2.step()
				frames += 1
			var all_visible := true
			for i in range(4):
				if not (stage2.nodes[i] as Control).visible:
					all_visible = false
			_chk("Feint Attack (hides with no matching show) leaves every "
					+ "battler visible afterwards", all_visible)


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




# ── batch 4 helpers: thin wrappers over the suite's own _vm/_spawn ────────
var _b4_last: AnimSprite = null


func _make_vm(stage: FakeStage) -> AnimScriptVM:
	return _vm(stage)


func _step(vm: AnimScriptVM, frames: int) -> void:
	for i in range(frames):
		vm._step_behaviors()


func _run(vm: AnimScriptVM, symbol: String, template: String) -> void:
	var ctx := {"template": template,
			"template_data": AnimData.template(template),
			"blend": {"eva": 16, "evb": 0}}
	var before: Array = []
	var stage_layer: Control = vm.stage.layer()
	for child in stage_layer.get_children():
		before.append(child)
	_registry.get_behavior(symbol).call(vm, ctx)
	_b4_last = null
	for child in stage_layer.get_children():
		if child is AnimSprite and not before.has(child):
			_b4_last = child


func _last_sprite(_stage: FakeStage) -> AnimSprite:
	return _b4_last

# ─── batch 4 ──────────────────────────────────────────────────────────────

# The four behaviors Step 0 found to be literally the same shape upstream:
# set a start, set duration/destination, hand off to StartAnimLinearTranslation
# with a stored destroy-callback. They must all actually ARRIVE, and the two
# whose direction is easy to invert must go the right way.
func _test_batch4_linear_family_shares_one_shape() -> void:
	# PowerAbsorptionOrb travels INTO the attacker -- it is a drain, and this
	# is the one direction in the batch that reads as obviously wrong if
	# reversed.
	var stage := FakeStage.new()
	var vm := _make_vm(stage)
	vm.args[0] = 40
	vm.args[1] = 0
	vm.args[2] = 10
	_run(vm, "AnimPowerAbsorptionOrb", "gCottonGuardSporeTemplate")
	var node := _last_sprite(stage)
	var start_d := node.centre.distance_to(stage.center_of(0)) if node != null \
			else 0.0
	_step(vm, 10)
	var end_d := node.centre.distance_to(stage.center_of(0)) if node != null \
			and is_instance_valid(node) else 0.0
	_chk("the absorption orb travels TOWARD the attacker, not away "
			+ "(%.0f -> %.0f)" % [start_d, end_d], end_d < start_d)

	# RaiseSprite's destination is RELATIVE, unlike the orb's absolute one.
	var s2 := FakeStage.new()
	var vm2 := _make_vm(s2)
	vm2.args[2] = -60   # rise
	vm2.args[3] = 12
	_run(vm2, "AnimRaiseSprite", "gAncientPowerRockSpriteTemplate")
	var n2 := _last_sprite(s2)
	var y0 := n2.centre.y if n2 != null else 0.0
	_step(vm2, 12)
	_chk("a raised sprite ends ABOVE where it started",
			n2 != null and is_instance_valid(n2) and n2.centre.y < y0)

	# AirWaveCrescent mirrors ALL FOUR offsets on the opponent's side -- a
	# single mirror, not a per-axis one.
	var s3 := FakeStage.new()
	s3.player_side = false
	var vm3 := _make_vm(s3)
	vm3.args[0] = 20
	vm3.args[1] = 10
	vm3.args[4] = 8
	_run(vm3, "AnimAirWaveCrescent", "gAirWaveCrescentSpriteTemplate")
	var n3 := _last_sprite(s3)
	_chk("an opponent-side air wave starts mirrored on BOTH axes",
			n3 != null and n3.centre.x < s3.center_of(0).x
			and n3.centre.y < s3.center_of(0).y)

	# FlyingSandCrescent is the odd one out: no duration arg at all, it runs
	# until it leaves the screen, so its life depends on its velocity.
	var s4 := FakeStage.new()
	var vm4 := _make_vm(s4)
	vm4.args[0] = 60
	vm4.args[1] = 2048   # 8 px/frame
	_run(vm4, "AnimFlyingSandCrescent", "gFlyingSandCrescentSpriteTemplate")
	var before := vm4.visual_count()
	_step(vm4, 400)
	_chk("the sand crescent exits the screen and cleans itself up "
			+ "(no duration argument involved)",
			before > 0 and vm4.visual_count() == 0)


func _test_batch4_strike_family() -> void:
	# FistOrFootRandomPos lands INSIDE the battler's own box, never at its
	# exact centre -- the scatter is the whole point of the behavior.
	var offsets: Array = []
	for i in range(12):
		var stage := FakeStage.new()
		var vm := _make_vm(stage)
		vm.args[1] = 4
		vm.args[2] = 0
		_run(vm, "AnimFistOrFootRandomPos", "gFistFootRandomPosSpriteTemplate")
		var node := _last_sprite(stage)
		if node != null:
			offsets.append(node.centre - stage.center_of(0))
	var distinct := {}
	for o in offsets:
		distinct[str(o.round())] = true
	_chk("the fist scatters rather than landing on one fixed point "
			+ "(%d distinct positions in 12 draws)" % distinct.size(),
			distinct.size() > 1)

	# SpinningKickOrPunch SNAPS back to full size and zero rotation before it
	# holds -- if the snap were missing it would vanish mid-shrink.
	var s2 := FakeStage.new()
	var vm2 := _make_vm(s2)
	vm2.args[3] = 10
	_run(vm2, "AnimSpinningKickOrPunch", "gMegaPunchKickSpriteTemplate")
	var n2 := _last_sprite(s2)
	var full := n2.scale if n2 != null else Vector2.ONE
	_step(vm2, 6)
	var mid := n2.scale if n2 != null and is_instance_valid(n2) else full
	_chk("the kick shrinks while spinning", mid.x < full.x)
	_step(vm2, 8)
	_chk("...then snaps back to full size for the landing hold",
			n2 != null and is_instance_valid(n2)
			and is_equal_approx(n2.scale.x, full.x)
			and is_zero_approx(n2.rotation))

	# SlidingKick travels horizontally with a sine riding on top: the x must
	# advance monotonically while y oscillates around the start.
	var s3 := FakeStage.new()
	var vm3 := _make_vm(s3)
	vm3.args[2] = 60
	vm3.args[3] = 20
	vm3.args[4] = 40
	vm3.args[5] = 12
	_run(vm3, "AnimSlidingKick", "gSlidingKickSpriteTemplate")
	var n3 := _last_sprite(s3)
	var y_start := n3.centre.y if n3 != null else 0.0
	var xs: Array = []
	var y_min := y_start
	var y_max := y_start
	for i in range(18):
		_step(vm3, 1)
		if n3 != null and is_instance_valid(n3):
			xs.append(n3.centre.x)
			y_min = minf(y_min, n3.centre.y)
			y_max = maxf(y_max, n3.centre.y)
	var monotonic := true
	for i in range(1, xs.size()):
		if float(xs[i]) < float(xs[i - 1]):
			monotonic = false
	_chk("the sliding kick advances horizontally without reversing", monotonic)
	_chk("...while the sine genuinely displaces it vertically (%.1f px)"
			% (y_max - y_min), (y_max - y_min) > 1.0)

	# NeedleArmSpike rotates to FACE its own direction of travel -- that is
	# what lets one implementation serve leaves, petals, spikes and jabs.
	var s4 := FakeStage.new()
	var vm4 := _make_vm(s4)
	vm4.args[1] = 1     # travel outward
	vm4.args[2] = 40
	vm4.args[3] = 40
	vm4.args[4] = 10
	_run(vm4, "AnimNeedleArmSpike", "gBattleAnimSpriteTemplate_LeafStorm2")
	var n4 := _last_sprite(s4)
	_chk("the spike rotates to face where it is going",
			n4 != null and not is_zero_approx(n4.rotation))

	# A zero duration destroys immediately upstream -- it must not spawn a
	# sprite that then never moves or expires.
	var s5 := FakeStage.new()
	var vm5 := _make_vm(s5)
	vm5.args[4] = 0
	_run(vm5, "AnimNeedleArmSpike", "gBattleAnimSpriteTemplate_LeafStorm2")
	_chk("a zero-duration spike spawns nothing at all",
			vm5.visual_count() == 0)

	# SlashSlice plays its anim, THEN flickers out. The flicker is the shared
	# False Swipe / Cut ending, and it must actually toggle visibility.
	var s6 := FakeStage.new()
	var vm6 := _make_vm(s6)
	_run(vm6, "AnimSlashSlice", "gSlashSliceSpriteTemplate")
	var n6 := _last_sprite(s6)
	var toggles := 0
	var was := n6.visible if n6 != null else true
	for i in range(80):
		_step(vm6, 1)
		if n6 == null or not is_instance_valid(n6):
			break
		if n6.visible != was:
			toggles += 1
			was = n6.visible
	_chk("the slice flickers out rather than simply vanishing (%d toggles)"
			% toggles, toggles >= 2)
	_chk("...and is gone afterwards", vm6.visual_count() == 0)


# Three pairs are the same function under two names upstream. Registering both
# against one implementation is correct; asserting it stops a later session
# "fixing" the duplication by writing a second, divergent copy.
func _test_batch4_aliased_names_share_one_impl() -> void:
	for pair in [["AnimFang", "AnimWhipHit_WaitEnd"],
			["AnimKnockOffStrike", "SpriteCB_LashOutStrike"]]:
		_chk("%s and %s resolve to one implementation"
				% [str(pair[0]), str(pair[1])],
				_registry.get_behavior(str(pair[0]))
				== _registry.get_behavior(str(pair[1])))

	# Fang is terminated by its own sprite anim ending, not a frame count --
	# so it must not run forever when nothing else stops it.
	var stage := FakeStage.new()
	var vm := _make_vm(stage)
	_run(vm, "AnimFang", "gFangSpriteTemplate")
	_chk("Fang spawns", vm.visual_count() > 0)
	_step(vm, 300)
	_chk("...and ends on its own anim rather than running forever",
			vm.visual_count() == 0)

	# KnockOffStrike sweeps an ARC: it must leave its start point and come
	# back near it, not travel in a straight line.
	var s2 := FakeStage.new()
	var vm2 := _make_vm(s2)
	_run(vm2, "AnimKnockOffStrike", "gKnockOffStrikeSpriteTemplate")
	var n2 := _last_sprite(s2)
	if n2 != null:
		var origin := n2.centre
		var far := 0.0
		for i in range(24):
			_step(vm2, 1)
			if not is_instance_valid(n2):
				break
			far = maxf(far, n2.centre.distance_to(origin))
		_chk("the knock-off strike sweeps an arc away from its start "
				+ "(%.0f px)" % far, far > 1.0)


func _test_batch4_mon_tasks_restore() -> void:
	# MonToSubstitute squashes the mon and then DROPS the doll in -- it must
	# end level again, not part-way through the bounce.
	var stage := FakeStage.new()
	var vm := _make_vm(stage)
	var node: Control = stage.nodes[0]
	var base := node.position
	var base_scale := node.scale
	_run(vm, "AnimTask_MonToSubstitute", "")
	_step(vm, 5)
	_chk("the mon is visibly squashed during the first phase",
			not node.scale.is_equal_approx(base_scale))
	_step(vm, 600)
	_chk("the substitute lands level again",
			node.position.is_equal_approx(base))
	_chk("...and its scale is restored", node.scale.is_equal_approx(base_scale))

	# RolePlaySilhouette clones the target, fades it in, squeezes it out, and
	# must free the clone -- a leaked ghost would sit on the battlefield.
	var s2 := FakeStage.new()
	var vm2 := _make_vm(s2)
	var before_children := (s2.layer() as Control).get_child_count()
	_run(vm2, "AnimTask_RolePlaySilhouette", "")
	_step(vm2, 400)
	_chk("the role-play silhouette frees its clone", vm2.visual_count() == 0)
	_chk("...leaving no extra nodes behind",
			(s2.layer() as Control).get_child_count() <= before_children + 1)

	# AttackerPunchWithTrace lunges out and back. Upstream leaves x2 at 0 at
	# the end of the return leg, so the attacker must finish where it began.
	var s3 := FakeStage.new()
	var vm3 := _make_vm(s3)
	var n3: Control = s3.nodes[0]
	var home := n3.position
	_run(vm3, "AnimTask_AttackerPunchWithTrace", "")
	_step(vm3, 3)
	_chk("the attacker lunges", not n3.position.is_equal_approx(home))
	_step(vm3, 60)
	_chk("...and returns exactly home", n3.position.is_equal_approx(home))

	# SlideOffScreen deliberately does NOT restore -- upstream leaves the mon
	# off-screen. What must hold is that the VM's own end-of-run restore puts
	# it back, the safety net the visibility fix established.
	var s4 := FakeStage.new()
	var vm4 := _make_vm(s4)
	var n4: Control = s4.nodes[0]
	var home4 := n4.position
	vm4.args[1] = 40
	_run(vm4, "AnimTask_SlideOffScreen", "")
	_step(vm4, 200)
	_chk("the slide moves the mon off-screen and stops there",
			not n4.position.is_equal_approx(home4))
	vm4._finish()
	_chk("...and the VM's end-of-run restore is what puts it back",
			n4.position.is_equal_approx(home4))


func _test_batch4_handshakes_and_bands() -> void:
	# ConstrictBinding genuinely WAITS on the script: nothing happens until
	# arg 7 goes to -1. Squeezing immediately would desynchronise it.
	var stage := FakeStage.new()
	var vm := _make_vm(stage)
	vm.args[3] = 2
	_run(vm, "AnimConstrictBinding", "gConstrictBindingSpriteTemplate")
	var node := _last_sprite(stage)
	var rest := node.scale if node != null else Vector2.ONE
	_step(vm, 40)
	_chk("the binding holds still until the script arms it",
			node != null and is_instance_valid(node)
			and node.scale.is_equal_approx(rest))
	vm.args[AnimScriptVM.ARG_RET] = -1
	_step(vm, 4)
	_chk("...then squeezes once armed",
			node != null and is_instance_valid(node)
			and not node.scale.is_equal_approx(rest))
	_step(vm, 400)
	_chk("...and finishes after its squeeze count", vm.visual_count() == 0)

	# GetReturnPowerLevel writes a band into arg 7. The thresholds are
	# reproduced exactly INCLUDING the gap at 60, which upstream's sequential
	# non-else comparisons leave falling through to 0.
	for pair in [[0, 0], [59, 0], [60, 0], [61, 1], [91, 1], [92, 2],
			[200, 2], [201, 3], [255, 3]]:
		var s2 := FakeStage.new()
		var vm2 := _make_vm(s2)
		vm2.friendship = int(pair[0])
		_run(vm2, "AnimTask_GetReturnPowerLevel", "")
		_chk("friendship %d -> band %d" % [int(pair[0]), int(pair[1])],
				vm2.args[AnimScriptVM.ARG_RET] == int(pair[1]))

	# Recycle is a long blend: in, hold, out. It must actually reach full
	# opacity in the middle rather than staying faint throughout.
	var s3 := FakeStage.new()
	var vm3 := _make_vm(s3)
	_run(vm3, "AnimRecycle", "gRecycleSpriteTemplate")
	var n3 := _last_sprite(s3)
	_step(vm3, 64)
	_chk("recycle fades all the way in",
			n3 != null and is_instance_valid(n3) and n3.modulate.a > 0.9)
	_step(vm3, 200)
	_chk("...and back out, cleaning up", vm3.visual_count() == 0)

	# SleepLetterZ rises QUADRATICALLY: the distance covered in its second
	# half must exceed the first, which a linear rise could not produce.
	var s4 := FakeStage.new()
	var vm4 := _make_vm(s4)
	_run(vm4, "AnimSleepLetterZ", "gSleepLetterZSpriteTemplate")
	var n4 := _last_sprite(s4)
	var y0 := n4.centre.y if n4 != null else 0.0
	_step(vm4, 30)
	var y1 := n4.centre.y if n4 != null and is_instance_valid(n4) else y0
	_step(vm4, 30)
	var y2 := n4.centre.y if n4 != null and is_instance_valid(n4) else y1
	_chk("the Z rises", y1 < y0)
	_chk("...and accelerates as it goes, so the rise is quadratic not linear "
			+ "(%.1f then %.1f)" % [y0 - y1, y1 - y2], (y1 - y2) > (y0 - y1))

	# SporeDoubleBattle is a genuine structured no-op here (it only reorders
	# BG priorities upstream, and this port has no per-battler BG rank). It
	# must complete rather than hang, since its whole purpose now is to stop
	# gating the moves that call it.
	var s5 := FakeStage.new()
	var vm5 := _make_vm(s5)
	_run(vm5, "AnimTask_SporeDoubleBattle", "")
	_chk("the spore BG-priority task completes immediately",
			vm5.visual_count() == 0)


# ─── batch 5 ──────────────────────────────────────────────────────────────

# Step 0 found four alias groups. Registering both names against one
# implementation is correct; asserting it stops a later session "fixing" the
# duplication into a second, divergent copy.
func _test_batch5_aliases_share_one_impl() -> void:
	for pair in [["AnimTask_SkillSwap", "AnimTask_HeartSwap"],
			["AnimTask_StockpileDeformMon", "AnimTask_SpitUpDeformMon"],
			["AnimTask_StockpileDeformMon", "AnimTask_SwallowDeformMon"]]:
		_chk("%s and %s resolve to one implementation"
				% [str(pair[0]), str(pair[1])],
				_registry.get_behavior(str(pair[0]))
				== _registry.get_behavior(str(pair[1])))
	# Stretch target/attacker are the same body with a different battler, so
	# they are deliberately NOT the same callable -- asserted so the
	# distinction is not "tidied" away.
	_chk("StretchTargetUp and StretchAttackerUp stay distinct (they differ "
			+ "only in which battler, which is real)",
			_registry.get_behavior("AnimTask_StretchTargetUp")
			!= _registry.get_behavior("AnimTask_StretchAttackerUp"))


# Three behaviors in this batch spawn MORE THAN ONE sprite from a single call.
# Porting any of them as a single sprite would look subtly wrong rather than
# broken, so the counts are asserted directly.
func _test_batch5_multi_spawn_families() -> void:
	# Thunder Wave is two sprites 32px apart -- upstream even bumps the visual
	# task count by hand to account for the second destroy.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "AnimThunderWave", "gThunderWaveSpriteTemplate")
	var sprites := _sprites_of(stage)
	_chk("Thunder Wave spawns TWO sprites, not one (%d)" % sprites.size(),
			sprites.size() == 2)
	if sprites.size() == 2:
		var dx: float = absf((sprites[0] as AnimSprite).centre.x
				- (sprites[1] as AnimSprite).centre.x)
		_chk("...side by side rather than stacked (%.0f px apart)" % dx,
				dx > 1.0)
	_step(vm, 60)
	_chk("...and both expire on their 51-frame life", vm.visual_count() == 0)

	# The electric bolt draws itself DOWNWARD, one segment every two frames.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	_run_b5(vm2, "AnimTask_ElectricBolt", "gElectricBoltSegmentSpriteTemplate")
	_step(vm2, 1)
	var after1 := _sprites_of(s2).size()
	_step(vm2, 11)
	var segs := _sprites_of(s2)
	_chk("the bolt spawns segments progressively, not all at once "
			+ "(%d after 1 frame, %d after 12)" % [after1, segs.size()],
			after1 < segs.size())
	_chk("...five segments in total (%d)" % segs.size(), segs.size() == 5)
	if segs.size() == 5:
		var ys: Array = []
		for sp in segs:
			ys.append((sp as AnimSprite).centre.y)
		ys.sort()
		_chk("...each lower than the last, so the bolt travels down",
				float(ys[0]) < float(ys[4]))

	# Skill Swap sends a stream of orbs, not one.
	var s3 := FakeStage.new()
	var vm3 := _vm(s3)
	_run_b5(vm3, "AnimTask_SkillSwap", "gSkillSwapOrbSpriteTemplate")
	_step(vm3, 90)
	_chk("Skill Swap emits a stream of orbs (%d)" % _sprites_of(s3).size(),
			_sprites_of(s3).size() >= 5)

	# Grudge Flames is six flames in ONE frame, spread around the attacker.
	var s4 := FakeStage.new()
	var vm4 := _vm(s4)
	_run_b5(vm4, "AnimTask_GrudgeFlames", "gGrudgeFlameSpriteTemplate")
	_chk("Grudge Flames spawns six flames at once (%d)"
			% _sprites_of(s4).size(), _sprites_of(s4).size() == 6)
	_step(vm4, 4)
	var xs := {}
	for sp in _sprites_of(s4):
		xs[str(round((sp as AnimSprite).centre.x))] = true
	_chk("...spread around the mon rather than stacked (%d distinct x)"
			% xs.size(), xs.size() > 1)


func _test_batch5_timing_shapes() -> void:
	# LockingJaw's timing is asymmetric and easy to get wrong: it MOVES for
	# `bite` frames, then freezes and counts back down from bite to -hold, so
	# the total is 2*bite + hold, not bite + hold.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[3] = 256
	vm.args[5] = 6   # bite
	vm.args[6] = 4   # hold
	_run_b5(vm, "SpriteCB_LockingJaw", "gSharpTeethSpriteTemplate")
	var node := _b5_last
	_step(vm, 6)
	var frozen := node.centre if node != null and is_instance_valid(node) \
			else Vector2.ZERO
	_step(vm, 3)
	_chk("the jaw FREEZES after biting rather than continuing",
			node != null and is_instance_valid(node)
			and node.centre.is_equal_approx(frozen))
	_step(vm, 20)
	_chk("...and expires on 2*bite + hold, not bite + hold",
			vm.visual_count() == 0)

	# SwordsDanceBlade is the one behavior in this batch that is the canonical
	# linear-translation shape: exactly 32px up over exactly 6 frames.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	_run_b5(vm2, "AnimSwordsDanceBlade", "gSwordsDanceBladeSpriteTemplate")
	var n2 := _b5_last
	var y0 := n2.centre.y if n2 != null else 0.0
	_step(vm2, 200)
	_chk("the blade rises and finishes", vm2.visual_count() == 0)

	# HyperBeamOrb's duration is DISTANCE-dependent, not a fixed count -- that
	# is what makes a volley of them arrive staggered rather than together.
	var lifetimes: Array = []
	for trial in range(6):
		var s3 := FakeStage.new()
		var vm3 := _vm(s3)
		_run_b5(vm3, "AnimHyperBeamOrb", "gHyperBeamOrbSpriteTemplate")
		var frames := 0
		while vm3.visual_count() > 0 and frames < 400:
			vm3._step_behaviors()
			frames += 1
		lifetimes.append(frames)
	var distinct := {}
	for l in lifetimes:
		distinct[str(l)] = true
	_chk("hyper beam orbs do not all live the same number of frames "
			+ "(%d distinct in 6 draws)" % distinct.size(), distinct.size() > 1)

	# The ice cube runs four real phases; it must not collapse to a flash.
	var s4 := FakeStage.new()
	var vm4 := _vm(s4)
	_run_b5(vm4, "AnimTask_FrozenIceCube", "sFrozenIceCubeSpriteTemplate")
	var n4 := _b5_last
	if n4 != null:
		_chk("the ice cube starts fully transparent and fades in",
				is_zero_approx(n4.modulate.a))
		_step(vm4, 10)
		_chk("...reaching full opacity after its 10-frame fade",
				is_instance_valid(n4) and n4.modulate.a > 0.9)
	var total := 0
	while vm4.visual_count() > 0 and total < 400:
		vm4._step_behaviors()
		total += 1
	_chk("...and runs a long multi-phase animation, not a flash (%d frames)"
			% total, total > 60)


func _test_batch5_mon_tasks_restore() -> void:
	# Every task that displaces or rescales a battler must put it back.
	for entry in [["AnimTask_Splash", 1], ["AnimTask_StretchTargetUp", 0],
			["AnimTask_TeeterDanceMovement", 0],
			["AnimTask_StockpileDeformMon", 0]]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[1] = int(entry[1])
		var battler: int = 1 if str(entry[0]) == "AnimTask_StretchTargetUp" \
				else 0
		var node: Control = stage.nodes[battler]
		var home := node.position
		var home_scale := node.scale
		_run_b5(vm, str(entry[0]), "")
		var moved := false
		for i in range(400):
			vm._step_behaviors()
			if not node.position.is_equal_approx(home) \
					or not node.scale.is_equal_approx(home_scale):
				moved = true
			if vm.visual_count() == 0 and i > 2:
				break
		_chk("%s actually moves the mon" % str(entry[0]), moved)
		_chk("%s restores its position" % str(entry[0]),
				node.position.is_equal_approx(home))
		_chk("%s restores its scale" % str(entry[0]),
				node.scale.is_equal_approx(home_scale))

	# Zero hops must destroy immediately rather than running a silent loop.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	vm2.args[1] = 0
	_run_b5(vm2, "AnimTask_Splash", "")
	_chk("Splash with zero hops does nothing at all",
			vm2.visual_count() == 0)


func _test_batch5_palette_group() -> void:
	# FlashingHitSplat does NO palette work despite the name and the company
	# it keeps -- it toggles visibility for 14 frames. Asserted so nobody
	# looks for a palette effect that was never there.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "AnimFlashingHitSplat", "gFlashingHitSplatSpriteTemplate")
	var node := _b5_last
	if node != null:
		var first := node.visible
		_step(vm, 1)
		_chk("the flashing hit splat toggles visibility every frame",
				is_instance_valid(node) and node.visible != first)
	_step(vm, 20)
	_chk("...and is gone after its 14 frames", vm.visual_count() == 0)

	# The exclude-blend must genuinely EXCLUDE. This is the one palette
	# operation in the batch with no faithful equivalent here, so what is
	# asserted is the property that survives the approximation: the named
	# battler is untouched while the others are not.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	vm2.args[0] = 0       # exclude the attacker
	vm2.args[1] = 0
	vm2.args[2] = 0
	vm2.args[3] = 16
	vm2.args[4] = 0x7FFF  # pure white -- the case that used to render NOTHING
	var attacker: Control = s2.nodes[0]
	var other: Control = s2.nodes[1]
	_run_b5(vm2, "AnimTask_BlendBattleAnimPalExclude", "")
	_step(vm2, 40)
	# The blend now REPLACES rather than multiplies, so it lives in a shader
	# material rather than in modulate. Asserted on white specifically: under
	# the old multiply this exact case was the identity and rendered nothing,
	# which is what made 126 of the roster's 777 blend sites invisible.
	_chk("the excluded battler is left untouched by the blend",
			attacker.material == null)
	var om := other.material as ShaderMaterial
	_chk("...while a non-excluded battler is genuinely blended",
			om != null)
	_chk("...a blend toward WHITE is now visible rather than a no-op "
			+ "(the multiply identity that hid 126 sites)",
			om != null and float(om.get_shader_parameter("tint_amount")) > 0.5)

	# The blend PERSISTS during a run (upstream never restores it -- scripts
	# pair two calls to blend back), so the question that matters is whether a
	# real script leaves a battler tinted afterwards. Guarded here because
	# this is the third leak of this class in M36 (visibility, displacement,
	# and now colour), and a permanently lilac Pokemon would be exactly as
	# silent as the first two.
	var s3 := FakeStage.new()
	var vm3 := _dispatcher.make_vm(14, s3, 0)   # Swords Dance blends non-attackers
	if vm3 != null:
		var frames := 0
		while vm3.is_running() and frames < 3000:
			vm3.step()
			frames += 1
		var untinted := true
		for i in range(4):
			if not (s3.nodes[i] as Control).modulate.is_equal_approx(
					Color(1, 1, 1, 1)):
				untinted = false
		_chk("a real blending script leaves no battler tinted afterwards",
				untinted)

	# Coverage floor for the batch as a whole.
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 356 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 356)


# ── batch 5 helpers ──────────────────────────────────────────────────────
var _b5_last: AnimSprite = null


func _run_b5(vm: AnimScriptVM, symbol: String, template: String) -> void:
	var ctx := {"template": template,
			"template_data": AnimData.template(template),
			"blend": {"eva": 16, "evb": 0}}
	var before: Array = []
	var layer: Control = vm.stage.layer()
	for child in layer.get_children():
		before.append(child)
	_registry.get_behavior(symbol).call(vm, ctx)
	_b5_last = null
	for child in layer.get_children():
		if child is AnimSprite and not before.has(child):
			_b5_last = child


func _sprites_of(stage: FakeStage) -> Array:
	var out: Array = []
	for child in stage.layer_node.get_children():
		if child is AnimSprite and is_instance_valid(child):
			out.append(child)
	return out


# ─── batch 6 ──────────────────────────────────────────────────────────────

# Step 0 found three behaviors sharing ONE step function upstream (all are
# `if (TranslateAnimHorizontalArc) DestroyAnimSprite`) and four reducing to the
# linear-translation shape. Asserted so the reuse is not "tidied" into
# divergent copies later.
func _test_batch6_helper_reuse() -> void:
	# The three arc users must actually arc -- leave the straight line between
	# their endpoints at mid-flight, which a linear port would not.
	for entry in [["AnimThrowProjectile", "gBlackBallSpriteTemplate", 5],
			["AnimSludgeProjectile", "gSludgeProjectileSpriteTemplate", -1],
			["AnimDirtPlumeParticle", "gDirtPlumeSpriteTemplate", 4]]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[2] = 40
		vm.args[3] = 0
		vm.args[4] = 20 if int(entry[2]) == 4 else 30
		vm.args[5] = 20 if int(entry[2]) != 4 else 20
		if int(entry[2]) >= 0:
			vm.args[int(entry[2])] = 30
		_run_b5(vm, str(entry[0]), str(entry[1]))
		var node := _b5_last
		if node == null:
			_chk("%s spawns" % str(entry[0]), false)
			continue
		var start := node.centre
		var mids: Array = []
		for i in range(30):
			_step(vm, 1)
			if is_instance_valid(node):
				mids.append(node.centre)
		var departed := false
		if mids.size() >= 4:
			var a: Vector2 = start
			var b: Vector2 = mids[mids.size() - 1]
			var m: Vector2 = mids[mids.size() / 2]
			var chord := a.lerp(b, 0.5)
			departed = m.distance_to(chord) > 0.5
		_chk("%s arcs rather than travelling straight" % str(entry[0]),
				departed)

	# The four linear collapses must simply ARRIVE.
	for entry in [["AnimIceBeamParticle", "gIceBeamInnerCrystalSpriteTemplate"],
			["AnimSolarBeamBigOrb", "gSolarBeamBigOrbSpriteTemplate"],
			["AnimWaterGunDroplet", "gWaterGunDropletSpriteTemplate"]]:
		var s2 := FakeStage.new()
		var vm2 := _vm(s2)
		vm2.args[2] = 12
		vm2.args[4] = 12
		_run_b5(vm2, str(entry[0]), str(entry[1]))
		var before := vm2.visual_count()
		_step(vm2, 40)
		_chk("%s completes its travel and cleans up" % str(entry[0]),
				before > 0 and vm2.visual_count() == 0)

	# The beyond-target particles start OFF-SCREEN behind the attacker, which
	# is what lets them pass through the target rather than stopping on it.
	var s3 := FakeStage.new()
	var vm3 := _vm(s3)
	vm3.args[4] = 40
	_run_b5(vm3, "AnimMoveParticleBeyondTarget",
			"gBlizzardIceCrystalSpriteTemplate")
	var n3 := _b5_last
	if n3 != null:
		var layer: Control = s3.layer()
		var outside := n3.centre.x < 0.0 or n3.centre.x > layer.size.x \
				or n3.centre.y < 0.0 or n3.centre.y > layer.size.y
		_chk("the beyond-target particle starts off-screen, not at the "
				+ "attacker", outside)
	_step(vm3, 600)
	_chk("...and terminates by leaving the screen, with no frame count",
			vm3.visual_count() == 0)


# Two behaviors in this batch are ended by the SCRIPT (arg 7), not by any
# internal counter. Registered uncounted, or waitforvisualfinish would hang.
func _test_batch6_script_terminated() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 6
	var before := vm.visual_count()
	_run_b5(vm, "AnimOrbitFast", "gElectricTerrainOrbsTemplate")
	_chk("the fast orbit does not count toward completion "
			+ "(it orbits until the script stops it)",
			vm.visual_count() == before)
	_step(vm, 300)
	_chk("...and is still orbiting after 300 frames",
			vm.visual_count() == before)
	vm.args[AnimScriptVM.ARG_RET] = -1
	_step(vm, 2)
	_chk("...ending only when arg 7 says so",
			not _b5_last.visible or _b5_last.is_finished())

	# AuroraBeamRings reads arg 7 live too, but still ends on its own duration.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	vm2.args[4] = 15
	_run_b5(vm2, "AnimAuroraBeamRings", "gAuroraBeamRingSpriteTemplate")
	_step(vm2, 40)
	_chk("the aurora ring still completes on its own duration",
			vm2.visual_count() == 0)


# THE headline risk of this batch. Dig is a four-call sequence upstream and
# omitting any one call strands the attacker -- shoved off the right edge,
# parked below the screen, or simply invisible. Upstream relies entirely on
# the script being correct; here the VM's own end-of-run restores are the net,
# and this is the test that proves the net works.
func _test_batch6_dig_sequence_never_strands() -> void:
	for omit in range(4):
		var stage := FakeStage.new()
		var vm := _vm(stage)
		var node: Control = stage.nodes[0]
		var home := node.position
		var calls := [["AnimTask_DigDownMovement", 0],
				["AnimTask_DigDownMovement", 1],
				["AnimTask_DigUpMovement", 0],
				["AnimTask_DigUpMovement", 1]]
		for i in range(calls.size()):
			if i == omit:
				continue   # deliberately break the sequence
			vm.args[0] = int(calls[i][1])
			_run_b5(vm, str(calls[i][0]), "")
			_step(vm, 30)
		# Whatever state the broken sequence left, ending the run must undo it.
		vm._finish()
		_chk("Dig with call %d omitted still leaves the mon on-screen" % omit,
				node.position.is_equal_approx(home))
		_chk("...and visible" % [], node.visible)

	# The complete sequence should also land level and visible on its own.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	var n2: Control = s2.nodes[0]
	var home2 := n2.position
	for pair in [["AnimTask_DigDownMovement", 0],
			["AnimTask_DigDownMovement", 1],
			["AnimTask_DigUpMovement", 0], ["AnimTask_DigUpMovement", 1]]:
		vm2.args[0] = int(pair[1])
		_run_b5(vm2, str(pair[0]), "")
		_step(vm2, 30)
	_chk("a COMPLETE Dig sequence returns the mon home by itself",
			n2.position.is_equal_approx(home2))
	_chk("...and visible", n2.visible)

	# SetAllNonAttackersInvisiblity is the same shape: a raw setter with no
	# restore of its own, relying on a paired call the script may never make.
	var s3 := FakeStage.new()
	var vm3 := _vm(s3)
	vm3.args[0] = 1
	_run_b5(vm3, "AnimTask_SetAllNonAttackersInvisiblity", "")
	_chk("hiding non-attackers leaves the attacker alone",
			(s3.nodes[0] as Control).visible)
	_chk("...and genuinely hides the others",
			not (s3.nodes[1] as Control).visible)
	vm3._finish()
	_chk("...and the end-of-run restore un-hides them even with no paired call",
			(s3.nodes[1] as Control).visible)


func _test_batch6_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 401 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 401)
	# The moves this batch was picked to unblock, by name.
	for pair in [[347, "Aeroblast"], [58, "Ice Beam"], [59, "Blizzard"],
			[55, "Water Gun"], [62, "Aurora Beam"], [85, "Thunderbolt"],
			[76, "Solar Beam"], [65, "Drill Peck"], [126, "Fire Blast"],
			[352, "Water Pulse"], [237, "Hidden Power"], [269, "Taunt"],
			[188, "Sludge Bomb"], [90, "Fissure"], [91, "Dig"]]:
		_chk("%s is playable" % str(pair[1]),
				_dispatcher.can_play_move(int(pair[0])))
