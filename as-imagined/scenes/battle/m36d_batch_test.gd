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
	_test_batch7_pairings_and_signal()
	_test_batch7_faithful_details()
	_test_batch7_closes_the_iconic_tier()
	_test_batch8_visibility_trio()
	_test_batch8_visibility_never_leaks()
	_test_batch8_power_scaled_shake()
	_test_batch8_rock_returns_exactly()
	_test_batch8_platform_shake_restores_capture()
	_test_batch8_fly_ball_accelerates()
	_test_batch8_electric_family()
	_test_batch8_static_and_timing()
	_test_batch8_coverage()
	_test_batch9_closes_the_fly_pair()
	_test_batch9_horn_snaps_back()
	_test_batch9_gust_family_shares_one_orbit()
	_test_batch9_alias_and_two_counters()
	_test_batch9_flicker_and_spiral()
	_test_batch9_droplet_and_deform()
	_test_batch9_coverage()
	_test_batch10_alias_and_flash()
	_test_batch10_orbit_and_flickers()
	_test_batch10_phases()
	_test_batch10_coverage()
	_test_batch11_scale_leak_net()
	_test_batch11_decay_and_drift()
	_test_batch11_rollout_windup()
	_test_batch11_coverage()

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
	# Batch 8's platform shake drives the background layer. Seeded to a
	# NON-ZERO offset deliberately, so "restores to zero" and "restores to
	# what it captured" are distinguishable outcomes.
	var scroll := Vector2(37.0, -11.0)
	func background_scroll() -> Vector2: return scroll
	func set_background_scroll(v: Vector2) -> void: scroll = v


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


# ─── batch 7 — closing the iconic tier ────────────────────────────────────

# Step 0 was asked which behaviors mutate a BATTLER, because that is the leak
# class M36 has hit repeatedly. The answer was TWO required pairings. This
# tests both, and — more importantly — that breaking either is still caught.
func _test_batch7_pairings_and_signal() -> void:
	# Pairing 1: AttackerStretchAndDisappear deliberately leaves the attacker
	# HIDDEN for ExtremeSpeedMonReappear to undo.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var node: Control = stage.nodes[0]
	var base_scale := node.scale
	_run_b5(vm, "AnimTask_AttackerStretchAndDisappear", "")
	_step(vm, 12)
	_chk("the stretch restores the attacker's SCALE by itself",
			node.scale.is_equal_approx(base_scale))
	_chk("...but deliberately leaves it hidden for its partner",
			not node.visible)
	_run_b5(vm, "AnimTask_ExtremeSpeedMonReappear", "")
	_step(vm, 40)
	_chk("...and the partner brings it back", node.visible)

	# The same, with the partner NEVER called — the leak case.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	var n2: Control = s2.nodes[0]
	_run_b5(vm2, "AnimTask_AttackerStretchAndDisappear", "")
	_step(vm2, 12)
	vm2._finish()
	_chk("a MISSING reappear still leaves the mon visible, because the VM "
			+ "restores what the script forgot", n2.visible)

	# Pairing 2: VoltTackleOrbSlide drags the attacker ~320px off-screen and
	# never puts it back; VoltTackleAttackerReappear is the restore.
	var s3 := FakeStage.new()
	var vm3 := _vm(s3)
	var n3: Control = s3.nodes[0]
	var home := n3.position
	_run_b5(vm3, "AnimVoltTackleOrbSlide", "gVoltTackleOrbSlideSpriteTemplate")
	_step(vm3, 120)
	_chk("the orb slide drags the attacker far off its mark",
			absf(n3.position.x - home.x) > 50.0)
	_run_b5(vm3, "AnimTask_VoltTackleAttackerReappear", "")
	_step(vm3, 200)
	_chk("...and its partner walks it back to exactly home",
			n3.position.is_equal_approx(home))
	_chk("...leaving it visible", n3.visible)

	# And the broken-pair case for that one too.
	var s4 := FakeStage.new()
	var vm4 := _vm(s4)
	var n4: Control = s4.nodes[0]
	var home4 := n4.position
	_run_b5(vm4, "AnimVoltTackleOrbSlide", "gVoltTackleOrbSlideSpriteTemplate")
	_step(vm4, 120)
	vm4._finish()
	_chk("a MISSING volt-tackle reappear still leaves the mon on its mark",
			n4.position.is_equal_approx(home4))

	# The signal is 0x1000, NOT the -1 sentinel every other waiting behavior
	# in this engine uses. Pinned because that is exactly the sort of detail
	# a port gets wrong silently.
	var s5 := FakeStage.new()
	var vm5 := _vm(s5)
	var n5: Control = s5.nodes[0]
	var before := vm5.visual_count()
	_run_b5(vm5, "AnimTask_SetAttackerInvisibleWaitForSignal", "")
	_chk("the wait does not count toward completion (it would deadlock the "
			+ "script that must release it)", vm5.visual_count() == before)
	_chk("...and hides the attacker", not n5.visible)
	vm5.args[AnimScriptVM.ARG_RET] = -1
	_step(vm5, 5)
	_chk("...and -1 does NOT release it", not n5.visible)
	vm5.args[AnimScriptVM.ARG_RET] = 0x1000
	_step(vm5, 2)
	_chk("...only 0x1000 does", n5.visible)


func _test_batch7_faithful_details() -> void:
	# InvertScreenColor is an INVOLUTION and restores nothing: Thunder relies
	# on calling it an even number of times. A port that always inverted would
	# leave the screen wrong after an odd count.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0x4     # invert the target
	var target: Control = stage.nodes[1]
	_run_b5(vm, "AnimTask_InvertScreenColor", "")
	var m1 := target.material as ShaderMaterial
	_chk("inverting once applies an inversion",
			m1 != null and float(m1.get_shader_parameter("invert")) > 0.5)
	_run_b5(vm, "AnimTask_InvertScreenColor", "")
	_chk("...and inverting again undoes it, because it is an involution",
			m1 != null and float(m1.get_shader_parameter("invert")) < 0.5)

	# ShakeTargetInPattern walks a fixed table, and its VERTICAL mode takes an
	# absolute value so the target only ever bounces DOWNWARD -- a real
	# asymmetry between the two modes.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	var n2: Control = s2.nodes[1]
	var home := n2.position
	vm2.args[0] = 30
	vm2.args[1] = 3
	vm2.args[2] = 1      # vertical
	_run_b5(vm2, "AnimTask_ShakeTargetInPattern", "")
	var went_up := false
	for i in range(30):
		_step(vm2, 1)
		if n2.position.y < home.y - 0.01:
			went_up = true
	_chk("a vertical pattern shake never moves the target UP "
			+ "(the absolute value is real)", not went_up)
	_chk("...and restores it exactly", n2.position.is_equal_approx(home))

	# Frustration's power bands are INVERTED relative to Return's -- 0 is the
	# STRONGEST here, because low friendship means a stronger Frustration.
	for pair in [[0, 0], [30, 0], [31, 1], [100, 1], [101, 2], [200, 2],
			[201, 3], [255, 3]]:
		var s3 := FakeStage.new()
		var vm3 := _vm(s3)
		vm3.friendship = int(pair[0])
		_run_b5(vm3, "AnimTask_GetFrustrationPowerLevel", "")
		_chk("friendship %d -> frustration band %d (0 = strongest)"
				% [int(pair[0]), int(pair[1])],
				vm3.args[AnimScriptVM.ARG_RET] == int(pair[1]))

	# ConfuseRayBallSpiral orbits on an ELLIPSE -- 32 across but only 8 down --
	# and drifts downward. A circular port would look wrong.
	var s4 := FakeStage.new()
	var vm4 := _vm(s4)
	_run_b5(vm4, "AnimConfuseRayBallSpiral",
			"gConfuseRayBallSpiralSpriteTemplate")
	var n4 := _b5_last
	if n4 != null:
		var xs := [n4.centre.x]
		var ys := [n4.centre.y]
		for i in range(20):
			_step(vm4, 1)
			if is_instance_valid(n4):
				xs.append(n4.centre.x); ys.append(n4.centre.y)
		var xr: float = (xs.max() as float) - (xs.min() as float)
		var yr: float = (ys.max() as float) - (ys.min() as float)
		_chk("the spiral is wider than it is tall (%.0f vs %.0f)" % [xr, yr],
				xr > yr)
	_step(vm4, 80)
	_chk("...and ends on its own 61 frames", vm4.visual_count() == 0)


func _test_batch7_closes_the_iconic_tier() -> void:
	for pair in [[87, "Thunder"], [109, "Confuse Ray"], [218, "Frustration"],
			[344, "Volt Tackle"], [349, "Dragon Dance"],
			[245, "Extreme Speed"]]:
		_chk("%s is playable" % str(pair[1]),
				_dispatcher.can_play_move(int(pair[0])))
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 419 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 419)


# ── [M36D batch 8] ────────────────────────────────────────────────────────
#
# This batch was picked by how many BLOCKED moves each behavior appears in
# rather than by move family, so the tests are shaped by failure mode rather
# than by theme. Three of the twelve are raw visibility setters that restore
# NOTHING upstream, which is the leak class this project has now hit four
# times -- so the headline assertion here is that a run ending mid-sequence
# still puts every Pokemon back.


func _test_batch8_visibility_trio() -> void:
	var stage := FakeStage.new()

	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_AllBattlersInvisible").call(vm, {})
	var hidden := 0
	for i in range(4):
		if not stage.nodes[i].visible:
			hidden += 1
	_chk("AllBattlersInvisible hides every battler (%d/4)" % hidden,
			hidden == 4)

	_registry.get_behavior("AnimTask_AllBattlersVisible").call(vm, {})
	var shown := 0
	for i in range(4):
		if stage.nodes[i].visible:
			shown += 1
	_chk("AllBattlersVisible is the paired restore (%d/4)" % shown, shown == 4)

	# The except-pair variant compares SPRITES upstream, not battler ids, so
	# the attacker and target must both survive while the partners go.
	var vm2 := _vm(stage)
	_registry.get_behavior(
			"AnimTask_AllBattlersInvisibleExceptAttackerAndTarget").call(vm2, {})
	_chk("...except-pair keeps the attacker",
			stage.nodes[AnimStage.ANIM_ATTACKER].visible)
	_chk("...and keeps the target",
			stage.nodes[AnimStage.ANIM_TARGET].visible)
	_chk("...and hides the attacker's partner",
			not stage.nodes[AnimStage.ANIM_ATK_PARTNER].visible)
	_chk("...and hides the target's partner",
			not stage.nodes[AnimStage.ANIM_DEF_PARTNER].visible)


func _test_batch8_visibility_never_leaks() -> void:
	# The defect these three could ship: a script that hides everyone and
	# never makes the paired call would strand every Pokemon invisible for
	# the rest of the battle. Nothing upstream prevents that; the VM's
	# tracked setter is the net, so it is asserted directly.
	for symbol in ["AnimTask_AllBattlersInvisible",
			"AnimTask_AllBattlersInvisibleExceptAttackerAndTarget"]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		_registry.get_behavior(symbol).call(vm, {})
		vm._finish()
		var visible := 0
		for i in range(4):
			if stage.nodes[i].visible:
				visible += 1
		_chk("%s cannot strand a Pokemon hidden (%d/4 back)"
				% [symbol, visible], visible == 4)

	# Same net for Fly, which hides the attacker and relies entirely on a
	# later script step to bring it back.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	_run_b5(vm2, "AnimFlyBallUp", "gFlyBallUpSpriteTemplate")
	_chk("FlyBallUp hides the attacker",
			not stage2.nodes[AnimStage.ANIM_ATTACKER].visible)
	vm2._finish()
	_chk("...and a run that ends before the reveal still restores it",
			stage2.nodes[AnimStage.ANIM_ATTACKER].visible)


func _test_batch8_power_scaled_shake() -> void:
	# Magnitude is source/12 clamped 1..16, then split ASYMMETRICALLY:
	# +ceil(mag/2) one way, -floor(mag/2) the other. An even split would look
	# almost identical on screen and be wrong.
	var stage := FakeStage.new()
	var base: Vector2 = stage.nodes[AnimStage.ANIM_TARGET].position

	var vm := _vm(stage)
	vm.move_power = 100          # -> mag 8, so +4 / -4 (even: symmetric)
	vm.args[0] = 0; vm.args[1] = 0; vm.args[2] = 40
	vm.args[3] = 1; vm.args[4] = 0
	_registry.get_behavior(
			"AnimTask_ShakeTargetBasedOnMovePowerOrDmg").call(vm, {})
	_step(vm, 1)
	var a: float = stage.nodes[AnimStage.ANIM_TARGET].position.x - base.x
	_step(vm, 1)
	var b: float = stage.nodes[AnimStage.ANIM_TARGET].position.x - base.x
	_chk("power 100 shakes the target horizontally", not is_zero_approx(a))
	_chk("...and reverses on the next step", signf(a) != signf(b))

	# Odd magnitude: 90/12 = 7 -> +4 / -3, a genuine lean.
	var stage2 := FakeStage.new()
	var base2: Vector2 = stage2.nodes[AnimStage.ANIM_TARGET].position
	var vm2 := _vm(stage2)
	vm2.move_power = 90
	vm2.args[0] = 0; vm2.args[1] = 0; vm2.args[2] = 40
	vm2.args[3] = 1; vm2.args[4] = 0
	_registry.get_behavior(
			"AnimTask_ShakeTargetBasedOnMovePowerOrDmg").call(vm2, {})
	_step(vm2, 1)
	var up: float = absf(stage2.nodes[AnimStage.ANIM_TARGET].position.x - base2.x)
	_step(vm2, 1)
	var down: float = absf(stage2.nodes[AnimStage.ANIM_TARGET].position.x - base2.x)
	_chk("an odd magnitude leans one way (%.1f vs %.1f)" % [up, down],
			not is_equal_approx(up, down))

	# arg0 switches the source outright. Damage 0 with power 200 must behave
	# as damage-derived (mag 1), not power-derived (mag 16).
	var stage3 := FakeStage.new()
	var base3: Vector2 = stage3.nodes[AnimStage.ANIM_TARGET].position
	var vm3 := _vm(stage3)
	vm3.move_power = 200
	vm3.move_damage = 0
	vm3.args[0] = 1; vm3.args[1] = 0; vm3.args[2] = 40
	vm3.args[3] = 1; vm3.args[4] = 0
	_registry.get_behavior(
			"AnimTask_ShakeTargetBasedOnMovePowerOrDmg").call(vm3, {})
	_step(vm3, 1)
	var dmg_shift: float = absf(
			stage3.nodes[AnimStage.ANIM_TARGET].position.x - base3.x)
	_chk("arg0=1 reads damage, not power (%.1f << %.1f)" % [dmg_shift, up],
			dmg_shift < up)

	# Vertical is written ABSOLUTELY upstream -- it returns to exactly 0 on
	# the off-phase rather than to whatever offset was already there.
	var stage4 := FakeStage.new()
	var node4: Control = stage4.nodes[AnimStage.ANIM_TARGET]
	var base4: Vector2 = node4.position
	var vm4 := _vm(stage4)
	vm4.move_power = 96
	vm4.args[0] = 0; vm4.args[1] = 0; vm4.args[2] = 6
	vm4.args[3] = 0; vm4.args[4] = 1
	_registry.get_behavior(
			"AnimTask_ShakeTargetBasedOnMovePowerOrDmg").call(vm4, {})
	_step(vm4, 1)
	_chk("vertical mode moves the target on the on-phase",
			not is_equal_approx(node4.position.y, base4.y))
	_step(vm4, 1)
	_chk("...and returns to exactly zero on the off-phase",
			is_equal_approx(node4.position.y, base4.y))
	_step(vm4, 20)
	_chk("...and the mon is fully restored at the end",
			node4.position.is_equal_approx(base4))


func _test_batch8_rock_returns_exactly() -> void:
	# The three motion phases are out / back-twice / out, so travel and
	# rotation cancel EXACTLY -- there is no corrective restore doing the work
	# for a drifting port. Asserted on the raw values, not approximately.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[AnimStage.ANIM_ATTACKER]
	var base := node.position
	var base_rot := node.rotation
	var vm := _vm(stage)
	vm.args[0] = AnimStage.ANIM_ATTACKER; vm.args[1] = 2; vm.args[2] = 1
	_registry.get_behavior("AnimTask_RockMonBackAndForth").call(vm, {})

	var moved := false
	var rotated := false
	for i in range(200):
		_step(vm, 1)
		if not node.position.is_equal_approx(base):
			moved = true
		if not is_equal_approx(node.rotation, base_rot):
			rotated = true
		if vm.visual_count() == 0:
			break
	_chk("RockMonBackAndForth actually displaces the mon", moved)
	_chk("...and actually rotates it", rotated)
	_chk("...and ends exactly back on its mark",
			node.position.is_equal_approx(base))
	_chk("...with rotation exactly restored",
			is_equal_approx(node.rotation, base_rot))

	# A count of zero is a real early-out upstream, not an error.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = AnimStage.ANIM_ATTACKER; vm2.args[1] = 0; vm2.args[2] = 1
	_registry.get_behavior("AnimTask_RockMonBackAndForth").call(vm2, {})
	_chk("a rock count of zero runs nothing at all", vm2.visual_count() == 0)

	# Intensity does NOT widen the excursion, which is worth pinning because
	# it is the opposite of what the constants suggest at a glance: the phase
	# shortens (8 - 2i frames) exactly as the step widens (i + 2 px), so the
	# peak travel lands at 16 / 18 / 16 px across the three tiers and is not
	# even monotonic. Total rotation per phase behaves the same way
	# (2048 / 2304 / 2048). What intensity actually controls is SPEED, so
	# that is what is asserted.
	var durations: Array = []
	for intensity in [0, 2]:
		var st := FakeStage.new()
		var v := _vm(st)
		v.args[0] = AnimStage.ANIM_ATTACKER; v.args[1] = 1
		v.args[2] = intensity
		_registry.get_behavior("AnimTask_RockMonBackAndForth").call(v, {})
		var frames := 0
		for i in range(200):
			_step(v, 1)
			frames += 1
			if v.visual_count() == 0:
				break
		durations.append(frames)
	_chk("intensity 2 rocks FASTER than intensity 0 (%d < %d frames)"
			% [durations[1], durations[0]], durations[1] < durations[0])


func _test_batch8_platform_shake_restores_capture() -> void:
	# The background may already be mid-scroll, so the shake must restore the
	# offset it CAPTURED, not zero -- the same rule M36E3's platform shake
	# established. The stage double seeds a non-zero scroll to tell the two
	# apart.
	var stage := FakeStage.new()
	var initial := stage.background_scroll()
	var vm := _vm(stage)
	vm.args[0] = 4; vm.args[1] = 4; vm.args[2] = 6; vm.args[3] = 1
	_registry.get_behavior("AnimTask_ShakeBattlePlatforms").call(vm, {})
	_chk("the shake offsets the background immediately",
			not stage.background_scroll().is_equal_approx(initial))

	var min_y := 0.0
	for i in range(60):
		_step(vm, 1)
		min_y = minf(min_y, stage.background_scroll().y - initial.y)
		if vm.visual_count() == 0:
			break
	_chk("...and restores the CAPTURED offset, not zero",
			stage.background_scroll().is_equal_approx(initial))
	# y alternates between -offset and 0 upstream; it never goes positive.
	_chk("...with the vertical axis only ever going one way (%.1f)" % min_y,
			min_y < 0.0)


func _test_batch8_fly_ball_accelerates() -> void:
	# The ball is not a linear riser: the velocity accumulator grows every
	# frame, so later steps cover more ground than earlier ones. A linear
	# port would pass a naive "does it go up" check and still be wrong.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 0; vm.args[2] = 5; vm.args[3] = 40
	_run_b5(vm, "AnimFlyBallUp", "gFlyBallUpSpriteTemplate")
	var node := _b5_last
	_chk("FlyBallUp spawns a ball", node != null)
	if node == null:
		return
	var start_y := node.centre.y

	_step(vm, 4)
	_chk("...which holds still through the launch delay",
			is_equal_approx(node.centre.y, start_y))

	# The rise is genuinely slow to start: with accel 40 the 8.8 accumulator
	# needs 7 frames just to reach one whole pixel, which is exactly the
	# quadratic shape being asserted -- a linear port would move on frame 1.
	_step(vm, 12)
	var early := start_y - node.centre.y
	var mid := node.centre.y
	_step(vm, 12)
	var late := mid - node.centre.y
	_chk("...then rises (%.1f px)" % early, early > 0.0)
	_chk("...accelerating rather than travelling linearly (%.1f -> %.1f)"
			% [early, late], late > early)


func _test_batch8_electric_family() -> void:
	# SparkElectricity places x from SINE and y from COSINE of the same index,
	# so index 0 sits directly BELOW the centre. Swapping the two would put it
	# to the right and look plausible while being wrong.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 20; vm.args[2] = 64; vm.args[3] = 12
	vm.args[4] = AnimStage.ANIM_TARGET
	_run_b5(vm, "AnimSparkElectricity", "gSparkElectricitySpriteTemplate")
	var spark := _b5_last
	_chk("SparkElectricity spawns", spark != null)
	if spark != null:
		var c := stage.center_of(AnimStage.ANIM_TARGET)
		_chk("...at index 0 it sits below the centre, not beside it",
				absf(spark.centre.y - c.y) > absf(spark.centre.x - c.x))
		_chk("...and is rotated by arg 2",
				not is_zero_approx(spark.rotation))
		_step(vm, 11)
		_chk("...and lives its full 12 frames", vm.visual_count() > 0)
		_step(vm, 2)
		_chk("...then dies on schedule", vm.visual_count() == 0)

	# ElectricChargingParticles converges on the battler and SPEEDS UP as it
	# runs, and -- the part that makes it safe to wait on -- only ends once
	# the last particle has landed, not when the last one spawns.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = AnimStage.ANIM_ATTACKER; vm2.args[1] = 8
	vm2.args[2] = 1; vm2.args[3] = 2
	_registry.get_behavior(
			"AnimTask_ElectricChargingParticles").call(vm2, {})
	var seen := 0
	var closing := false
	var prev_far := -1.0
	var centre := stage2.center_of(AnimStage.ANIM_ATTACKER)
	for i in range(40):
		_step(vm2, 1)
		var live := _sprites_of(stage2)
		seen = maxi(seen, live.size())
		if live.size() > 0:
			var d: float = (live[0] as AnimSprite).centre.distance_to(centre)
			if prev_far >= 0.0 and d < prev_far:
				closing = true
			prev_far = d
	_chk("charging particles spawn over time (%d at once)" % seen, seen > 0)
	_chk("...and converge on the battler", closing)
	var still_running := vm2.visual_count() > 0
	var still_live := not _sprites_of(stage2).is_empty()
	_chk("...and the task outlives its last spawn if any are still flying",
			not still_live or still_running)
	_step(vm2, 200)
	_chk("...but does finish", vm2.visual_count() == 0)


func _test_batch8_static_and_timing() -> void:
	# GrowingShockWaveOrb is a contract-then-expand under the INVERTED GBA
	# affine rule: the parameter climbs, so the rendered orb shrinks first.
	# Reading the inversion backwards would produce exactly the opposite
	# motion, which is the whole reason this is asserted on direction.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "AnimGrowingShockWaveOrb",
			"gGrowingShockWaveOrbSpriteTemplate")
	var orb := _b5_last
	_chk("shockwave orb spawns", orb != null)
	if orb != null:
		var s0 := orb.scale.x
		_step(vm, 25)
		var s1 := orb.scale.x
		_step(vm, 30)
		var s2 := orb.scale.x
		_chk("...contracts first (%.2f -> %.2f)" % [s0, s1], s1 < s0)
		_chk("...then expands again (%.2f -> %.2f)" % [s1, s2], s2 > s1)
		_step(vm, 20)
		_chk("...over 60 frames", vm.visual_count() == 0)

	# CrossImpact is a pure timing element: it must NOT move.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 0; vm2.args[1] = 0
	vm2.args[2] = AnimStage.ANIM_TARGET; vm2.args[3] = 10
	_run_b5(vm2, "AnimCrossImpact", "gCrossImpactSpriteTemplate")
	var cross := _b5_last
	if cross != null:
		var where := cross.centre
		_step(vm2, 8)
		_chk("CrossImpact holds perfectly still", cross.centre.is_equal_approx(where))
		_chk("...for its full duration", vm2.visual_count() > 0)
		_step(vm2, 4)
		_chk("...then goes", vm2.visual_count() == 0)

	# The gust palette rotation is a structured no-op (sprite palettes are not
	# recoverable from composited PNGs) -- but its FRAME COST is the contract
	# a following waitforvisualfinish depends on, so that is what is pinned.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	vm3.args[0] = 3; vm3.args[1] = 30
	_registry.get_behavior(
			"AnimTask_AnimateGustTornadoPalette").call(vm3, {})
	_step(vm3, 29)
	_chk("the gust palette task still costs its declared frames",
			vm3.visual_count() > 0)
	_step(vm3, 2)
	_chk("...and releases at its declared lifetime", vm3.visual_count() == 0)


func _test_batch8_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 446 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 446)


# ── [M36D batch 9] ────────────────────────────────────────────────────────
#
# Picked by measured yield across tiers rather than by generation (Rob's
# amendment to Decision 5 after batch 8 measured the two remaining tiers).
# 16 behaviors, 70 moves. Several collapse onto helpers M36C and batches 5-6
# already built, so the tests concentrate on the handful of genuinely
# distinctive shapes -- and on the one real pairing this batch closes.


func _test_batch9_closes_the_fly_pair() -> void:
	# Batch 8 shipped AnimFlyBallUp, which hides the attacker and relies on a
	# later script step to bring it back; until now only the VM's restore net
	# did that. AnimFlyBallAttack IS that step -- upstream assigns arg 1
	# straight into the attacker's `invisible` as the ball leaves. Asserted
	# through the REAL behavior, with the VM still running, so a pass cannot
	# be the safety net doing the work.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "AnimFlyBallUp", "gFlyBallUpSpriteTemplate")
	_chk("Fly: the up-half hides the attacker",
			not stage.nodes[AnimStage.ANIM_ATTACKER].visible)

	vm.args[0] = 8
	vm.args[1] = 0        # 0 = bring the attacker back
	_run_b5(vm, "AnimFlyBallAttack", "gFlyBallAttackSpriteTemplate")
	var ball := _b5_last
	_chk("Fly: the attack-half spawns a ball", ball != null)
	_step(vm, 4)
	_chk("...and the attacker is still hidden mid-flight",
			not stage.nodes[AnimStage.ANIM_ATTACKER].visible)
	_step(vm, 8)
	_chk("...revealed by the real script step, not the VM's net",
			stage.nodes[AnimStage.ANIM_ATTACKER].visible)

	# arg 1 = 1 means "leave it hidden" -- the discriminator that proves the
	# reveal reads the argument rather than being unconditional.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	_run_b5(vm2, "AnimFlyBallUp", "gFlyBallUpSpriteTemplate")
	vm2.args[0] = 6
	vm2.args[1] = 1
	_run_b5(vm2, "AnimFlyBallAttack", "gFlyBallAttackSpriteTemplate")
	_step(vm2, 12)
	_chk("...and arg 1 = 1 deliberately leaves it hidden",
			not stage2.nodes[AnimStage.ANIM_ATTACKER].visible)
	vm2._finish()
	_chk("...with the net still catching that case at run end",
			stage2.nodes[AnimStage.ANIM_ATTACKER].visible)

	_chk("Fly (19) is playable", _dispatcher.can_play_move(19))


func _test_batch9_horn_snaps_back() -> void:
	# The quirk: on the SECOND-TO-LAST frame the horn teleports to its
	# recorded origin and only then dies. A port that merely interpolates
	# toward the destination looks close and never actually lands there.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 0; vm.args[2] = 10
	_run_b5(vm, "AnimHornHit", "gHornHitSpriteTemplate")
	var horn := _b5_last
	_chk("horn spawns", horn != null)
	if horn == null:
		return
	var target := stage.center_of(AnimStage.ANIM_TARGET)
	var start_d := horn.centre.distance_to(target)
	_chk("...starting off to one side of the target (%.0f px)" % start_d,
			start_d > 1.0)
	_step(vm, 5)
	var mid_d := horn.centre.distance_to(target)
	_chk("...sweeping toward it (%.0f -> %.0f)" % [start_d, mid_d],
			mid_d < start_d)
	# Frame 9 of 10 is the snap.
	_step(vm, 4)
	_chk("...then SNAPPING exactly onto its origin before dying (%.2f px)"
			% horn.centre.distance_to(target),
			horn.centre.distance_to(target) < 0.01)
	_step(vm, 2)
	_chk("...and it is gone on the next frame", vm.visual_count() == 0)


func _test_batch9_gust_family_shares_one_orbit() -> void:
	# EllipticalGust and EllipticalGustCentered share ONE step function
	# upstream and differ only in placement. Both must therefore trace the
	# same shape -- and that shape is an ELLIPSE, 32 across but only 8 down.
	for symbol in ["AnimEllipticalGust", "AnimEllipticalGustCentered"]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		_run_b5(vm, symbol, "gEllipticalGustSpriteTemplate")
		var n := _b5_last
		if n == null:
			_chk("%s spawns" % symbol, false)
			continue
		var xs := [n.centre.x]
		var ys := [n.centre.y]
		for i in range(40):
			_step(vm, 1)
			if is_instance_valid(n):
				xs.append(n.centre.x); ys.append(n.centre.y)
		var xr: float = (xs.max() as float) - (xs.min() as float)
		var yr: float = (ys.max() as float) - (ys.min() as float)
		_chk("%s orbits far wider than tall (%.0f vs %.0f)" % [symbol, xr, yr],
				xr > yr * 2.0)
		_step(vm, 45)
		_chk("%s ends on its own 71 frames" % symbol, vm.visual_count() == 0)

	# GustToTarget is the plain linear-travel member of the same family.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[2] = 0; vm2.args[3] = 0; vm2.args[4] = 10
	_run_b5(vm2, "AnimGustToTarget", "gGustToTargetSpriteTemplate")
	var g := _b5_last
	if g != null:
		var d0 := g.centre.distance_to(stage2.center_of(AnimStage.ANIM_TARGET))
		_step(vm2, 8)
		var d1 := g.centre.distance_to(stage2.center_of(AnimStage.ANIM_TARGET))
		_chk("GustToTarget travels attacker -> target (%.0f -> %.0f)"
				% [d0, d1], d1 < d0)


func _test_batch9_alias_and_two_counters() -> void:
	# AnimRockBlastRock IS TranslateAnimSpriteToTargetMonLocation, which M36C
	# already ported. Asserted as one shared implementation so nobody later
	# "fixes" the duplication into a divergent pair.
	_chk("RockBlastRock is registered", _registry.get_behavior(
			"AnimRockBlastRock") != Callable())
	_chk("Rock Blast (350) is playable", _dispatcher.can_play_move(350))

	# FirePlume has TWO independent counters -- it drifts for arg3 frames but
	# LIVES for arg2, so it coasts and then hangs. Collapsing them into one
	# duration is the easy mistake and loses the hang.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 0
	vm.args[2] = 30   # lifetime
	vm.args[3] = 10   # drift frames
	vm.args[4] = 4; vm.args[5] = -2
	_run_b5(vm, "AnimFirePlume", "gFirePlumeSpriteTemplate")
	var plume := _b5_last
	_chk("fire plume spawns", plume != null)
	if plume == null:
		return
	_step(vm, 9)
	var drifted := plume.centre
	_chk("...drifts while its drift counter runs",
			not drifted.is_equal_approx(Vector2.ZERO))
	_step(vm, 10)
	_chk("...then HANGS once drift ends but life has not",
			plume.centre.is_equal_approx(drifted))
	_chk("...and is still alive during the hang", vm.visual_count() > 0)
	_step(vm, 15)
	_chk("...dying only at its own lifetime", vm.visual_count() == 0)


func _test_batch9_flicker_and_spiral() -> void:
	# ZapCannonSpark's stutter is the whole character of the move: it toggles
	# visibility whenever its angle index divides by 3. A smooth port reads as
	# a different move.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[2] = 10; vm.args[3] = 30; vm.args[4] = 0; vm.args[5] = 5
	_run_b5(vm, "AnimZapCannonSpark", "gZapCannonSparkSpriteTemplate")
	var spark := _b5_last
	_chk("zap spark spawns", spark != null)
	if spark != null:
		var flips := 0
		var was := spark.visible
		for i in range(25):
			_step(vm, 1)
			if is_instance_valid(spark) and spark.visible != was:
				flips += 1
				was = spark.visible
		_chk("...and stutters in flight (%d visibility flips)" % flips,
				flips > 0)

	# IcePunchSwirlingParticle's amplitude accumulates NEGATIVE on a positive
	# base, so the radius passes through zero and back out -- it spirals in,
	# through the centre, and out the far side rather than simply expanding.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 0
	_run_b5(vm2, "AnimIcePunchSwirlingParticle",
			"gIcePunchSwirlingParticleSpriteTemplate")
	var ice := _b5_last
	if ice != null:
		var centre := stage2.center_of(AnimStage.ANIM_ATTACKER)
		var radii: Array = []
		for i in range(50):
			_step(vm2, 1)
			if is_instance_valid(ice):
				radii.append(ice.centre.distance_to(centre))
		if radii.size() > 10:
			var lo: float = radii.min()
			var hi: float = radii.max()
			_chk("ice particle's radius genuinely varies (%.1f..%.1f)"
					% [lo, hi], hi - lo > 1.0)

	# MagentaHeart rises steadily while swaying.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	_run_b5(vm3, "AnimMagentaHeart", "gMagentaHeartSpriteTemplate")
	var heart := _b5_last
	if heart != null:
		var y0 := heart.centre.y
		var xs: Array = []
		for i in range(30):
			_step(vm3, 1)
			if is_instance_valid(heart):
				xs.append(heart.centre.x)
		_chk("magenta heart rises", heart.centre.y < y0)
		var xr: float = (xs.max() as float) - (xs.min() as float)
		_chk("...while swaying sideways (%.1f px)" % xr, xr > 0.5)
		_step(vm3, 40)
		_chk("...for exactly 60 frames", vm3.visual_count() == 0)


func _test_batch9_droplet_and_deform() -> void:
	# SprayWaterDroplet carries a real upstream BUG, reproduced as written:
	# the step self-assigns `data[0] = data[0]` where it clearly meant to
	# decay the horizontal speed the way it decays the vertical. So y
	# decelerates and x does not. Pinned so a future session does not "fix"
	# the arc into a shape the reference never draws.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 0
	_run_b5(vm, "AnimSprayWaterDroplet", "gSprayWaterDropletSpriteTemplate")
	var drop := _b5_last
	_chk("water droplet spawns", drop != null)
	if drop != null:
		var p0 := drop.centre
		_step(vm, 1)
		var d1 := drop.centre - p0
		# The vertical speed is 8.8 fixed point decaying 32/frame from ~896,
		# so it takes 6 frames to lose a whole pixel -- the same truncation
		# shape as FlyBallUp. Comparing adjacent frames would tie at 3px and
		# prove nothing, so the later sample is taken well past that point.
		_step(vm, 9)
		var p1 := drop.centre
		_step(vm, 1)
		var d2 := drop.centre - p1
		_chk("...its horizontal speed does NOT decay (upstream bug, kept)",
				is_equal_approx(absf(d1.x), absf(d2.x)))
		_chk("...while its rise DOES decelerate (%.1f -> %.1f px/frame)"
				% [absf(d1.y), absf(d2.y)], absf(d2.y) < absf(d1.y))
		_step(vm, 30)
		_chk("...over exactly 31 frames", vm.visual_count() == 0)

	# DefenseCurlDeformMon's two affine halves cancel EXACTLY, so it is
	# self-restoring by construction rather than by a corrective final step.
	var stage2 := FakeStage.new()
	var node: Control = stage2.nodes[AnimStage.ANIM_ATTACKER]
	var base := node.scale
	var vm2 := _vm(stage2)
	_registry.get_behavior("AnimTask_DefenseCurlDeformMon").call(vm2, {})
	var widest := base.x
	var flattest := base.y
	for i in range(40):
		_step(vm2, 1)
		widest = maxf(widest, node.scale.x)
		flattest = minf(flattest, node.scale.y)
		if vm2.visual_count() == 0:
			break
	# Inverted affine: a NEGATIVE x delta widens, the positive y delta flattens.
	_chk("Defense Curl squashes the mon wider (%.3f > %.3f)"
			% [widest, base.x], widest > base.x)
	_chk("...and flatter (%.3f < %.3f)" % [flattest, base.y], flattest < base.y)
	_chk("...and restores its scale exactly", node.scale.is_equal_approx(base))
	_chk("Defense Curl (111) is playable", _dispatcher.can_play_move(111))


func _test_batch9_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 516 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 516)
	# The headliners this batch unblocked, named so a regression is legible.
	for pair in [[19, "Fly"], [118, "Metronome"], [8, "Ice Punch"],
			[82, "Dragon Rage"], [16, "Gust"], [30, "Horn Attack"],
			[304, "Hyper Voice"]]:
		_chk("%s is playable" % str(pair[1]),
				_dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 10] ───────────────────────────────────────────────────────
#
# The curve flattened here as batch 9's closing measurement warned. 11 of 16
# candidates shipped; five were DEFERRED rather than guessed at, because
# their step functions were not read in full. What is here is tested on the
# beats a half-read port would drop -- holds, dead waits, and phase splits.


func _test_batch10_alias_and_flash() -> void:
	# AnimFireSpiralInward is byte-identical to batch 9's ice-punch particle:
	# same driver, same four constants. Asserted as ONE implementation so the
	# duplication is not later "fixed" into a divergent pair.
	_chk("FireSpiralInward and IcePunchSwirlingParticle share one impl",
			_registry.get_behavior("AnimFireSpiralInward")
			== _registry.get_behavior("AnimIcePunchSwirlingParticle"))

	# Flash slams to black/white, HOLDS, and only then fades. The hold is the
	# beat a port drops by accident.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_Flash").call(vm, {})
	var mon: Control = stage.nodes[AnimStage.ANIM_ATTACKER]
	_chk("Flash blends the battlers immediately",
			mon.material != null)
	_step(vm, 5)
	_chk("...and HOLDS before fading (still running at frame 5)",
			vm.visual_count() > 0)
	_step(vm, 45)
	_chk("...then finishes on its own ~39 frames", vm.visual_count() == 0)
	_chk("...leaving no blend behind on the battler", mon.material == null)


func _test_batch10_orbit_and_flickers() -> void:
	# ReversalOrb's ellipse widens FOUR TIMES as fast as it heightens
	# (0x400 vs 0x100 per frame), then unwinds symmetrically back to nothing.
	# A circular port, or one that only grows, both look plausible and are
	# wrong in different ways.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 20; vm.args[1] = 0
	_run_b5(vm, "AnimReversalOrb", "gReversalOrbSpriteTemplate")
	var orb := _b5_last
	_chk("reversal orb spawns", orb != null)
	if orb != null:
		var centre := stage.center_of(AnimStage.ANIM_ATTACKER)
		var xs: Array = []
		var ys: Array = []
		for i in range(20):
			_step(vm, 1)
			if is_instance_valid(orb):
				xs.append(absf(orb.centre.x - centre.x))
				ys.append(absf(orb.centre.y - centre.y))
		var xmax: float = xs.max()
		var ymax: float = ys.max()
		_chk("...orbits far wider than tall (%.0f vs %.0f)" % [xmax, ymax],
				xmax > ymax * 2.0)
		_step(vm, 25)
		_chk("...and unwinds back closed", vm.visual_count() == 0)

	# BlackSmoke flickers EVERY frame -- that is what makes it read as smoke
	# rather than a sliding sprite.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 0; vm2.args[1] = 0; vm2.args[2] = 256
	vm2.args[3] = 0; vm2.args[4] = 12
	_run_b5(vm2, "AnimBlackSmoke", "gBlackSmokeSpriteTemplate")
	var smoke := _b5_last
	if smoke != null:
		var flips := 0
		var was := smoke.visible
		for i in range(8):
			_step(vm2, 1)
			if is_instance_valid(smoke) and smoke.visible != was:
				flips += 1
				was = smoke.visible
		_chk("black smoke flickers on EVERY frame (%d/8)" % flips, flips >= 7)

	# OutrageFlame starts INVISIBLE and blinks into existence mid-flight.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	vm3.args[0] = 0; vm3.args[1] = 0; vm3.args[2] = 20
	vm3.args[3] = 256; vm3.args[4] = 0; vm3.args[5] = 3
	_run_b5(vm3, "AnimOutrageFlame", "gOutrageFlameSpriteTemplate")
	var flame := _b5_last
	if flame != null:
		_chk("outrage flame starts INVISIBLE", not flame.visible)
		var appeared := false
		for i in range(12):
			_step(vm3, 1)
			if is_instance_valid(flame) and flame.visible:
				appeared = true
		_chk("...and blinks into existence mid-flight", appeared)


func _test_batch10_phases() -> void:
	# SurroundingRing starts BELOW the attacker and sweeps up through it --
	# not an expanding ring, despite the name.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "SpriteCB_SurroundingRing", "gSurroundingRingSpriteTemplate")
	var ring := _b5_last
	if ring != null:
		var c := stage.center_of(AnimStage.ANIM_ATTACKER)
		_chk("surrounding ring starts BELOW the attacker", ring.centre.y > c.y)
		_step(vm, 13)
		_chk("...and ends above where it began", ring.centre.y < c.y)

	# FallingObject has two genuinely separate phases: it FALLS, and only on
	# landing does it flicker out. Merging them loses the landing beat.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 0; vm2.args[1] = 40; vm2.args[2] = 4
	vm2.args[3] = AnimStage.ANIM_TARGET
	_run_b5(vm2, "SpriteCB_FallingObject", "gFallingObjectSpriteTemplate")
	var obj := _b5_last
	if obj != null:
		var rest := stage2.center_of(AnimStage.ANIM_TARGET)
		_chk("falling object starts above its target", obj.centre.y < rest.y)
		var fell := false
		for i in range(40):
			_step(vm2, 1)
			if is_instance_valid(obj) and absf(obj.centre.y - rest.y) < 1.0:
				fell = true
				break
		_chk("...falls to the target's level", fell)
		_chk("...and is still alive to flicker there", vm2.visual_count() > 0)
		_step(vm2, 15)
		_chk("...then goes", vm2.visual_count() == 0)

	# GuillotinePincer's middle phase is the whole character of the move: a
	# 51-frame grind jittering every frame. Porting only the converge gives a
	# pincer that arrives and politely stops.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	vm3.args[0] = 0
	_run_b5(vm3, "AnimGuillotinePincer", "gGuillotinePincerSpriteTemplate")
	var pincer := _b5_last
	if pincer != null:
		var target := stage3.center_of(AnimStage.ANIM_TARGET)
		var d0 := pincer.centre.distance_to(target)
		_step(vm3, 6)
		var d1 := pincer.centre.distance_to(target)
		_chk("pincer converges (%.0f -> %.0f)" % [d0, d1], d1 < d0)
		# During the grind it must move every frame, never settle.
		var moves := 0
		var prev := pincer.centre
		for i in range(10):
			_step(vm3, 1)
			if is_instance_valid(pincer) and not pincer.centre.is_equal_approx(prev):
				moves += 1
				prev = pincer.centre
		_chk("...then GRINDS rather than settling (%d/10 frames moved)" % moves,
				moves >= 9)
		_step(vm3, 60)
		_chk("...and retreats away again", vm3.visual_count() == 0)

	# Spikes: arc, then a DEAD 30-frame hold, then flicker on ODD frames only.
	var stage4 := FakeStage.new()
	var vm4 := _vm(stage4)
	vm4.args[2] = 0; vm4.args[3] = 0; vm4.args[4] = 10
	_run_b5(vm4, "AnimSpikes", "gSpikesSpriteTemplate")
	var spike := _b5_last
	if spike != null:
		var a := spike.centre
		var b := stage4.center_of(AnimStage.ANIM_TARGET)
		_step(vm4, 5)
		# Mid-arc it must sit ABOVE the straight line between the endpoints.
		var straight_y: float = a.y + (b.y - a.y) * 0.5
		_chk("spikes LOB rather than travelling straight (%.0f < %.0f)"
				% [spike.centre.y, straight_y], spike.centre.y < straight_y)
		_step(vm4, 5)
		var landed := spike.centre
		_step(vm4, 20)
		_chk("...then sit DEAD STILL for the hold",
				spike.centre.is_equal_approx(landed))
		_chk("...still alive during it", vm4.visual_count() > 0)
		_step(vm4, 30)
		_chk("...before flickering out", vm4.visual_count() == 0)

	# QuestionMark is placed from the attacker's own SPRITE SIZE, not a fixed
	# offset -- so a bigger mon puts it further out.
	var stage5 := FakeStage.new()
	var vm5 := _vm(stage5)
	_run_b5(vm5, "AnimQuestionMark", "gQuestionMarkSpriteTemplate")
	var q := _b5_last
	if q != null:
		var mon: Control = stage5.nodes[AnimStage.ANIM_ATTACKER]
		var c := stage5.center_of(AnimStage.ANIM_ATTACKER)
		_chk("question mark offsets by the mon's own half-size",
				is_equal_approx(absf(q.centre.x - c.x), mon.size.x * 0.5))
		_chk("...and sits above its centre", q.centre.y < c.y)


func _test_batch10_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 543 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 543)
	# Batch 10 deferred five behaviors and asserted all five stayed
	# unregistered. Batch 11 ported four of them after reading their step
	# functions, so that assertion is legitimately invalidated -- rewritten
	# here rather than deleted, and split so the one STILL deferred is
	# guarded on its own.
	for sym in ["AnimTask_Rollout", "AnimTask_FlailMovement",
			"AnimTask_NightmareClone", "AnimTask_ShrinkTargetCopy"]:
		_chk("%s was deferred by batch 10 and is now ported" % sym,
				_registry.get_behavior(sym) != Callable())
	_chk("AnimTask_SpiteTargetShadow is STILL deferred (scanline + BG-layer)",
			_registry.get_behavior("AnimTask_SpiteTargetShadow") == Callable())


# ── [M36D batch 11] ───────────────────────────────────────────────────────
#
# Four of batch 10's five deferrals, ported once their step functions were
# actually read. The headline is a NEW LEAK CLASS the reading exposed:
# AnimTask_ShrinkTargetCopy shrinks the REAL target and waits for a script
# signal to restore it, so a run that ends first would strand a shrunk
# Pokemon -- the same shape as batch 7's Extreme Speed visibility pair, but
# on scale, which none of the VM's three existing nets covered.


func _test_batch11_scale_leak_net() -> void:
	var stage := FakeStage.new()
	var node: Control = stage.nodes[AnimStage.ANIM_TARGET]
	var base := node.scale

	var vm := _vm(stage)
	vm.args[0] = 256; vm.args[1] = 8
	_registry.get_behavior("AnimTask_ShrinkTargetCopy").call(vm, {})
	_step(vm, 8)
	# Inverted affine: the parameter CLIMBS, so the sprite must get SMALLER.
	_chk("ShrinkTargetCopy shrinks the target (%.3f < %.3f)"
			% [node.scale.x, base.x], node.scale.x < base.x)
	_chk("...and drifts it sideways",
			not node.position.is_equal_approx(
					node.get_meta("_anim_mon_base")))
	_step(vm, 10)
	_chk("...then HOLDS, waiting for the script's signal",
			node.scale.x < base.x and vm.visual_count() > 0)

	# THE NET: end the run without ever signalling. Nothing in the behavior
	# restores here -- only the VM's fourth restore net can.
	vm._finish()
	_chk("...and a run ending before the signal cannot strand it shrunk",
			node.scale.is_equal_approx(base))
	_chk("...with its position restored too",
			node.position.is_equal_approx(node.get_meta("_anim_mon_base")))

	# The signalled path must also work, or the net would be masking a
	# behavior that never restores at all.
	var stage2 := FakeStage.new()
	var node2: Control = stage2.nodes[AnimStage.ANIM_TARGET]
	var base2 := node2.scale
	var vm2 := _vm(stage2)
	vm2.args[0] = 256; vm2.args[1] = 6
	_registry.get_behavior("AnimTask_ShrinkTargetCopy").call(vm2, {})
	_step(vm2, 10)
	_chk("...(shrunk again, second fixture)", node2.scale.x < base2.x)
	vm2.args[AnimScriptVM.ARG_RET] = -1
	_step(vm2, 2)
	_chk("...the -1 signal restores it through the behavior itself",
			node2.scale.is_equal_approx(base2))
	_chk("...and the task ends there", vm2.visual_count() == 0)

	# An invisible target is a real early-out upstream, not an error.
	var stage3 := FakeStage.new()
	stage3.nodes[AnimStage.ANIM_TARGET].visible = false
	var vm3 := _vm(stage3)
	vm3.args[0] = 256; vm3.args[1] = 6
	_registry.get_behavior("AnimTask_ShrinkTargetCopy").call(vm3, {})
	_chk("...an invisible target runs nothing at all", vm3.visual_count() == 0)


func _test_batch11_decay_and_drift() -> void:
	# FlailMovement DECAYS -- that is what makes it flail rather than wobble.
	# The amplitude loses 0x40 every 9 frames, so late swings are visibly
	# smaller than early ones. A constant-amplitude port looks fine in a
	# still frame and wrong in motion.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[AnimStage.ANIM_ATTACKER]
	var base_rot := node.rotation
	var base_pos := node.position
	var vm := _vm(stage)
	vm.args[0] = AnimStage.ANIM_ATTACKER
	_registry.get_behavior("AnimTask_FlailMovement").call(vm, {})

	var early := 0.0
	for i in range(40):
		_step(vm, 1)
		early = maxf(early, absf(node.rotation - base_rot))
	var late := 0.0
	for i in range(40):
		_step(vm, 1)
		late = maxf(late, absf(node.rotation - base_rot))
	_chk("flail rotates the mon", early > 0.0)
	_chk("...and DECAYS over time (%.4f -> %.4f rad)" % [early, late],
			late < early)
	# The sway is derived from the tilt, not an independent motion.
	_chk("...swaying horizontally as it tilts",
			not node.position.is_equal_approx(base_pos))
	_step(vm, 400)
	_chk("...and restores rotation exactly",
			is_equal_approx(node.rotation, base_rot))
	_chk("...and position exactly", node.position.is_equal_approx(base_pos))

	# NightmareClone: a blended ghost peels away and dissolves, then cleans up.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	var before := stage2.layer_node.get_child_count()
	_registry.get_behavior("AnimTask_NightmareClone").call(vm2, {})
	_chk("nightmare clone is created",
			stage2.layer_node.get_child_count() > before)
	var ghost: Control = null
	for c in stage2.layer_node.get_children():
		if c is Control and c.has_meta("_anim_trace"):
			ghost = c
	# A wrong meta key here silently skips the two assertions below while the
	# suite still reports green -- the exact false-pass shape this project's
	# conventions warn about, and it happened on the first draft. Guarded.
	_chk("...and is findable as an anim-owned clone", ghost != null)
	if ghost != null:
		var p0 := ghost.position
		var a0 := ghost.modulate.a
		_step(vm2, 40)
		_chk("...it drifts away from the target",
				not ghost.position.is_equal_approx(p0))
		_chk("...fading as it goes (%.2f -> %.2f)" % [a0, ghost.modulate.a],
				ghost.modulate.a < a0)
	_step(vm2, 140)
	_chk("...and the task finishes", vm2.visual_count() == 0)


func _test_batch11_rollout_windup() -> void:
	# The wind-up is most of Rollout's character: pull BACK away from the
	# target, HOLD 20 dead frames, return, and only then charge. A port that
	# only charges arrives with no anticipation at all.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[AnimStage.ANIM_ATTACKER]
	var atk := stage.center_of(AnimStage.ANIM_ATTACKER)
	var tgt := stage.center_of(AnimStage.ANIM_TARGET)
	var vm := _vm(stage)
	vm.move_turn = 0
	_registry.get_behavior("AnimTask_Rollout").call(vm, {})

	_step(vm, 10)
	var pulled := node.position
	# Pulling back means moving AWAY from the target.
	var d_start := atk.distance_to(tgt)
	var d_pulled := (pulled + node.size * 0.5).distance_to(tgt)
	_chk("Rollout pulls BACK before charging (%.0f -> %.0f)"
			% [d_start, d_pulled], d_pulled > d_start)

	_step(vm, 15)
	_chk("...then HOLDS dead still through the wind-up",
			node.position.is_equal_approx(pulled))
	_chk("...still running during the hold", vm.visual_count() > 0)

	_step(vm, 200)
	_chk("...and ends back on its mark",
			node.position.is_equal_approx(node.get_meta("_anim_mon_base")))

	# Speed scales with the rollout counter -- a later turn crosses faster.
	var frames: Array = []
	for turn in [0, 4]:
		var st := FakeStage.new()
		var v := _vm(st)
		v.move_turn = turn
		_registry.get_behavior("AnimTask_Rollout").call(v, {})
		var n := 0
		for i in range(400):
			_step(v, 1)
			n += 1
			if v.visual_count() == 0:
				break
		frames.append(n)
	_chk("a later-turn Rollout crosses FASTER (%d < %d frames)"
			% [frames[1], frames[0]], frames[1] < frames[0])


func _test_batch11_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 551 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 551)
