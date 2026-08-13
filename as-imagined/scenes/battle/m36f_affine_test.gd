extends Node

# [M36F] The SPRITE-path affine player — `AnimSprite.advance_affine()`.
#
# 325 extracted sequences named by 493 of 1,148 templates had never been played:
# `AnimData.affine_sequences_for()` had exactly one caller (M36R's
# `_affine_loop_delta`, which reads a single delta out of one table rather than
# running any of them). This suite covers the runner that now does.
#
# ⚠️ **EVERY ASSERTION HERE IS DERIVED FROM THE NEGATION, PER M36 RULE (7).**
# The five plausible wrong versions this was written against, each of which
# fails a named assertion below rather than merely "not passing":
#
#   1. TASK-path scale convention (`256 / accumulator`) — inverts every one of
#      the 493 templates at once. -> section C, which pins a GROWING table and a
#      SHRINKING one together, because an inversion flips both.
#   2. `duration == 0` read as a zero-length frame to skip, rather than as an
#      ABSOLUTE set. -> D.01.
#   3. The delay applying its delta once and then holding, rather than
#      re-applying it every frame. -> D.02.
#   4. Rotation taken raw instead of `<< 8` — 256x under-rotated. -> E.01.
#   5. The OAM affine mode ignored, animating the 19 templates that carry a
#      table and declare `AffineOff`. -> section B, which needs BOTH halves of
#      the pair to discriminate.
#
# All five were injected and confirmed to fail the named assertions before this
# suite was trusted; a sixth (removing the trailing-LOOP overrun guard) throws
# on every tick and fails F.04.
#
# ⚠️ **AND SECTION H EXISTS BECAUSE OF RULE (16).** `m36_leak_harness` runs all
# 779 playable scripts and passed 785/785 throughout this work — it asserts the
# END state, and the VM restores battlers before it looks. It is structurally
# incapable of seeing whether a matrix was ever applied mid-run. H samples a
# real script DURING one.
#
# Source: `sprite.c` — `BeginAffineAnim` :1086, `ContinueAffineAnim` :1103,
# `AffineAnimCmd_loop` :1143, `JumpToTopOfAffineAnimLoop` :1165,
# `AffineAnimCmd_jump` :1182, `AffineAnimCmd_end` :1191,
# `ApplyAffineAnimFrame` :1345, `ConvertScaleParam` :1337.

var _pass := 0
var _fail := 0

const EXPECTED_TOTAL := 39

# A deliberately NON-UNIT base, so every scale assertion below is also an
# assertion that the player COMPOSES with the pixel scale `_make_sprite` sets
# rather than assigning over it. At base 1.0 the two are indistinguishable —
# rule (13).
const BASE := 5.0


func _ready() -> void:
	AnimData.ensure_loaded()

	_test_section_a_corpus()
	_test_section_b_oam_gate()
	_test_section_c_scale_convention()
	_test_section_d_duration_semantics()
	_test_section_e_rotation()
	_test_section_f_control_flow()
	_test_section_g_change_keeps_the_accumulator()
	_test_section_h_during_a_real_run()

	_chk("Z.99 assertion count balances (%d of %d)" % [_pass + _fail, EXPECTED_TOTAL],
			_pass + _fail == EXPECTED_TOTAL - 1)

	var total := _pass + _fail
	print("m36f_affine_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Harness ───────────────────────────────────────────────────────────────

class FakeStage extends RefCounted:
	var layer_node: Control
	var nodes: Dictionary = {}
	func _init() -> void:
		layer_node = Control.new()
		layer_node.size = Vector2(1200, 800)
		var placeholder := PlaceholderTexture2D.new()
		placeholder.size = Vector2(64, 64)
		for i in range(4):
			var n := TextureRect.new()
			n.texture = placeholder
			n.size = Vector2(64, 64)
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


# A bare sprite bound to one real template's table, at a non-unit base scale.
# Deliberately NOT routed through a behavior: the player has to be correct on
# its own before any consumer is judged against it.
func _bind(template_name: String) -> AnimSprite:
	var tmpl := AnimData.template(template_name)
	var oam: Dictionary = tmpl.get("oam", {})
	var tag := str((tmpl.get("tile_tag", {}) as Dictionary).get("name", ""))
	var node := AnimSprite.create(null, tag, int(oam.get("width", 32)),
			int(oam.get("height", 32)))
	add_child(node)
	node.scale = Vector2.ONE * BASE
	node.pivot_offset = node.size * 0.5
	node.setup_affine(template_name, oam)
	return node


# The same, over a HAND-BUILT sequence, for the cases no template reaches.
func _bind_synthetic(seq: Array) -> AnimSprite:
	var node := AnimSprite.create(null, "ANIM_TAG_ORBS", 16, 16)
	add_child(node)
	node.scale = Vector2.ONE * BASE
	node._affine_seqs = [seq]
	node._affine_on = true
	return node


func _tick(node: AnimSprite, frames: int) -> void:
	for _f in range(frames):
		node.advance_affine()


# ── A. The extracted corpus ───────────────────────────────────────────────

func _test_section_a_corpus() -> void:
	var seqs := 0
	var with_table := 0
	var affine_off := 0
	var templates: Dictionary = AnimData._templates
	for name in templates:
		var t: Dictionary = templates[name]
		if t.get("affine_anims_key") == null:
			continue
		with_table += 1
		if str((t.get("oam", {}) as Dictionary).get("affine", "AffineOff")) == "AffineOff":
			affine_off += 1
	seqs = (AnimData._frames.get("affine", {}) as Dictionary).size()

	# The floor F1 restored. `AFFINEANIMCMD_END_ALT` had been silently dropped by
	# the extractor's `elif` chain, costing 10 sequences their terminator; these
	# pin the repaired shape so a future extractor change cannot quietly shrink
	# it again the same way.
	_chk("A.01 the affine corpus still holds 325 sequences (got %d)" % seqs,
			seqs == 325)
	_chk("A.02 493 templates name an affine table (got %d)" % with_table,
			with_table == 493)
	# Section B's whole population. ⓘ This briefly read 27 during development —
	# 8 templates with a bespoke OAM struct the extractor had not decoded were
	# being swept into the off bucket by a defaulted `.get`. All 8 are affine-ON
	# in source; `parse_oam_structs` now reads them and the count is 19 again.
	_chk("A.03 19 of those declare AffineOff (got %d)" % affine_off,
			affine_off == 19)
	# The guard that keeps A.03 honest: an undecoded OAM has no `affine` field
	# at all, and any default folds it into one of the three buckets silently.
	var undecoded := 0
	for name in templates:
		var t: Dictionary = templates[name]
		if t.get("affine_anims_key") == null:
			continue
		if not (t.get("oam", {}) as Dictionary).has("affine"):
			undecoded += 1
	_chk("A.03b every table-carrying template has a DECODED affine mode (%d missing)"
			% undecoded, undecoded == 0)
	# Every sequence is terminated, jumps, or loops. F1's own defect was
	# sequences that simply ran out, which is unrepresentable on hardware.
	var unterminated := 0
	for key in (AnimData._frames.get("affine", {}) as Dictionary):
		var s: Array = AnimData._frames["affine"][key]
		if s.is_empty():
			continue
		var last: Variant = s[-1]
		if last is String:
			continue
		if last is Dictionary and ((last as Dictionary).has("jump")
				or (last as Dictionary).has("loop")):
			continue
		unterminated += 1
	_chk("A.04 no sequence ends on a bare FRAME (got %d)" % unterminated,
			unterminated == 0)


# ── B. The OAM gate ───────────────────────────────────────────────────────

func _test_section_b_oam_gate() -> void:
	# ⚠️ **THE PAIR IS THE TEST.** Asserting only that the AffineOff template
	# stays still would also pass against a player that never ran at all; the
	# AffineNormal half is what proves the gate is a gate rather than an off
	# switch. Rule (13).
	var off := _bind("gAlphaGeyserSpriteTemplate")
	_chk("B.01 an AffineOff template with a table does not arm the player",
			not off.has_affine_anim())
	var before := off.scale
	_tick(off, 30)
	_chk("B.02 ...and 30 frames later its scale is untouched",
			off.scale.is_equal_approx(before))

	var on := _bind("gAbsorptionOrbSpriteTemplate")
	_chk("B.03 an AffineNormal template with the same shape DOES arm it",
			on.has_affine_anim())
	_tick(on, 20)
	_chk("B.04 ...and its scale really moved",
			not on.scale.is_equal_approx(Vector2.ONE * BASE))


# ── C. The scale convention ───────────────────────────────────────────────

func _test_section_c_scale_convention() -> void:
	# `gAbsorptionOrbAffineAnimCmds` = relative -5, jump 0. On the SPRITE path
	# the accumulator is the visual scale, so 256 - 5n SHRINKS.
	var orb := _bind("gAbsorptionOrbSpriteTemplate")
	_tick(orb, 20)
	# 256 - 5*20 = 156 -> 0.609 of base. The task-path reading (256/156 = 1.64)
	# would land ABOVE base, which is what makes this a discriminator rather
	# than a "did anything happen" check.
	_chk("C.01 a negative delta SHRINKS on the sprite path (%.3f of base)"
			% (orb.scale.x / BASE), orb.scale.x < BASE * 0.75)
	_chk("C.02 ...to the accumulator's own value, not its reciprocal",
			absf(orb.scale.x - BASE * 156.0 / 256.0) < BASE * 0.02)

	# `sAffineAnim_SpiderWeb` = absolute 16, then relative +6 with jump 1.
	# An inverted convention flips BOTH of these, which one alone cannot show.
	var web := _bind("gSpiderWebSpriteTemplate")
	_tick(web, 2)
	var early := web.scale.x
	_tick(web, 18)
	_chk("C.03 a positive delta GROWS (%.3f -> %.3f)" % [early, web.scale.x],
			web.scale.x > early)
	# 16 + 6*19 = 130 -> 0.508 of base.
	_chk("C.04 ...and the web still starts far BELOW base, as its table says",
			early < BASE * 0.15)

	# The composition guard: at BASE 1.0 an assigning player and a composing one
	# are identical, so this only means anything at a non-unit base.
	_chk("C.05 the pixel-scale base is composed with, not assigned over",
			absf(web.scale.x - BASE * 130.0 / 256.0) < BASE * 0.02)


# ── D. Duration semantics ─────────────────────────────────────────────────

func _test_section_d_duration_semantics() -> void:
	# `gMimicOrbAffineAnimCmds1` opens `{duration 0, xscale 0}` — an ABSOLUTE set
	# to zero, so the orb begins as nothing and swells. Read as "a zero-length
	# frame, skip it" the orb would simply start at full size.
	var orb := _bind("gMimicOrbSpriteTemplate")
	_tick(orb, 1)
	_chk("D.01 a duration-0 frame is an ABSOLUTE set (%.3f of base)"
			% (orb.scale.x / BASE), orb.scale.x < BASE * 0.05)

	# `gSleepLetterZAffineAnimCmds1` = absolute (20), then +8 for 24 frames.
	var z := _bind("gSleepLetterZSpriteTemplate")
	_tick(z, 3)
	var at3 := z.scale.x
	_tick(z, 17)
	var at20 := z.scale.x
	# The delay re-applies the delta EVERY frame (`AffineAnimDelay` ->
	# `ApplyAffineAnimFrameRelativeAndUpdateMatrix`). Applying it once and
	# holding would freeze this at 28/256 from frame 2 onward.
	_chk("D.02 a multi-frame FRAME keeps moving (%.3f -> %.3f)" % [at3, at20],
			at20 > at3 + BASE * 0.2)
	# 20 + 8*19 = 172 at frame 20, exactly.
	_chk("D.03 ...by exactly one delta per frame",
			absf(at20 - BASE * 172.0 / 256.0) < BASE * 0.02)

	# ⚠️ The delay is the DECREMENTED duration: source decrements its local copy
	# before `delayCounter = frameCmd.duration`. So the 24-frame command occupies
	# 24 ticks (1 apply + 23 delay) and END lands on tick 26, not 27.
	var z2 := _bind("gSleepLetterZSpriteTemplate")
	_tick(z2, 25)
	_chk("D.04 a duration-24 frame has not ended at tick 25",
			not z2.affine_ended())
	_tick(z2, 1)
	_chk("D.05 ...and has by tick 26", z2.affine_ended())


# ── E. Rotation ───────────────────────────────────────────────────────────

func _test_section_e_rotation() -> void:
	# `gSleepLetterZAffineAnimCmds1`'s absolute frame carries rot -30, which
	# source shifts LEFT 8 on the absolute path too — `-30 << 8` is -7680 of
	# 65536, i.e. about -42 degrees. Taken raw it would be -0.16 degrees.
	var z := _bind("gSleepLetterZSpriteTemplate")
	_tick(z, 1)
	var deg := rad_to_deg(z.rotation)
	# ⚠️ Measured as a SIGNED turn from identity, not as a raw magnitude. A first
	# draft asserted `|rotation| > 0.5 rad` and the unshifted injection PASSED
	# it: -30 units masks to 65280, which reads as 358.6 degrees and is a large
	# number while being a 1.4-degree turn. The wrap is what makes this a
	# discriminator — shifted is -42 degrees, unshifted is -1.4.
	var turn := rad_to_deg(wrapf(z.rotation, -PI, PI))
	_chk("E.01 the absolute path shifts rotation left 8 (%.2f deg turn)" % turn,
			absf(turn) > 10.0)
	# 65536 - 7680 = 57856 units -> 317.8 degrees.
	_chk("E.02 ...to exactly the table's own angle", absf(deg - 317.81) < 1.0)

	# The relative path accumulates +1 per frame over 24 frames.
	_tick(z, 24)
	var deg2 := rad_to_deg(z.rotation)
	_chk("E.03 the relative path accumulates rotation too (%.2f deg)" % deg2,
			absf(deg2 - deg) > 1.0)

	# ⚠️ **RULE (15): THE `& ~0xFF` MASK'S NEGATION IS NOT EXPRESSIBLE HERE, AND
	# THIS ASSERTION SAYS SO RATHER THAN PRETENDING OTHERWISE.** Every rotation
	# that reaches the accumulator has already been shifted left 8, so the sum is
	# always a multiple of 256 and the mask can never bite in this corpus. It is
	# ported because it is real (rotation quantises to 256ths of a turn) and
	# would bite the moment anything wrote an unshifted value; what is asserted
	# is only that the invariant it protects holds.
	_chk("E.04 the rotation accumulator stays 256-aligned (mask inert here)",
			(z._affine_rot & 0xFF) == 0)


# ── F. Control flow ───────────────────────────────────────────────────────

func _test_section_f_control_flow() -> void:
	# A JUMP never terminates — on hardware either. 60 of the corpus's commands
	# are jumps, so a port that let one report "ended" would cut short every
	# consumer that waits on the affine clock.
	var orb := _bind("gAbsorptionOrbSpriteTemplate")
	_tick(orb, 200)
	_chk("F.01 a JUMPing sequence never reports ended", not orb.affine_ended())
	_chk("F.02 ...and is still applying the matrix 200 frames in",
			orb.scale.x != BASE)

	var z := _bind("gSleepLetterZSpriteTemplate")
	_tick(z, 40)
	_chk("F.03 an END-terminated sequence does report ended", z.affine_ended())

	# ⚠️ **THE TRAILING-LOOP OVERRUN, REPRODUCED AS A GUARD RATHER THAN AS THE
	# BUG.** `gSleepLetterZAffineAnimCmds1_2` is `[loop 0, frame(24), loop 10]`
	# with no terminator; once the loop is exhausted `JumpToTopOfAffineAnimLoop`
	# stops rewinding and source walks off the end of the array. Driven
	# synthetically because no template's table reaches these two sequences.
	var runaway := _bind_synthetic([
		{"loop": 0},
		{"duration": 24, "rot": 1, "xscale": 0, "yscale": 0},
		{"loop": 10},
	])
	_tick(runaway, 400)
	# ⚠️ Of the two bounds checks this crosses, the LOAD-BEARING one is
	# `_continue_affine`'s `cmd == null -> end` branch, not `_cmd_at`'s own
	# range test: removing the latter alone still terminates, because an
	# out-of-range Array read returns null (loudly). Removing the former throws
	# on every tick and this assertion is what says so.
	_chk("F.04 a sequence ending on LOOP terminates instead of overrunning",
			runaway.affine_ended())
	# The discriminator against "it never started": it must have rotated through
	# the body many times before falling out.
	_chk("F.05 ...having actually run the loop body (%.1f deg)"
			% rad_to_deg(runaway.rotation), absf(runaway.rotation) > 0.1)

	# `sAffineAnim_TailGlowOrb` uses `loop 0` as a loop-TOP MARKER — the count is
	# zero, so it rewinds nothing and the LATER `loop 5` rewinds to it. Read as
	# "loop forever" the orb would never reach the -5/+5 oscillation at all.
	var glow := _bind("gTailGlowOrbSpriteTemplate")
	_tick(glow, 25)
	var samples: Array[float] = []
	for _i in range(40):
		_tick(glow, 1)
		samples.append(glow.scale.x)
	var went_down := false
	var went_up := false
	for i in range(1, samples.size()):
		if samples[i] < samples[i - 1]:
			went_down = true
		elif samples[i] > samples[i - 1]:
			went_up = true
	_chk("F.06 `loop 0` is a marker, so the oscillating body is reached",
			went_down and went_up)


# ── G. change_affine_anim keeps the accumulator ───────────────────────────

func _test_section_g_change_keeps_the_accumulator() -> void:
	# `gMimicOrbAffineAnimCmds1` swells the orb to 672/256 = 2.625 and ends.
	var orb := _bind("gMimicOrbSpriteTemplate")
	_tick(orb, 40)
	_chk("G.01 the first sequence swells the orb well past base (%.2fx)"
			% (orb.scale.x / BASE), orb.scale.x > BASE * 2.0)
	_chk("G.02 ...and ends", orb.affine_ended())

	var handoff := orb.scale.x
	orb.change_affine_anim(1)
	_tick(orb, 1)
	# ⚠️ **THE WHOLE POINT OF `ChangeSpriteAffineAnim` BEING ITS OWN FUNCTION.**
	# It sets only `animNum` and the flags; `StartSpriteAffineAnim` additionally
	# resets the accumulators to identity. Using the wrong one snaps the orb back
	# to 1.0 before the taper — which is 1.0x against the 2.6x asserted here.
	_chk("G.03 changing sequence KEEPS the accumulator (%.2fx, was %.2fx)"
			% [orb.scale.x / BASE, handoff / BASE], orb.scale.x > BASE * 2.0)
	_chk("G.04 ...and the second sequence tapers it down", orb.scale.x < handoff)

	# The contrast, so G.03 is a claim about `change` rather than about the
	# table: `start` on the same sequence DOES reset.
	var reset := _bind("gMimicOrbSpriteTemplate")
	_tick(reset, 40)
	reset.start_affine_anim(1)
	_tick(reset, 1)
	_chk("G.05 `start_affine_anim` by contrast resets to identity first (%.2fx)"
			% (reset.scale.x / BASE), reset.scale.x < BASE * 1.05)


# ── H. During a real run ──────────────────────────────────────────────────

func _test_section_h_during_a_real_run() -> void:
	# ⚠️ **RULE (16).** The leak harness runs every playable script and checks the
	# END state, so it cannot tell a live player from a dead one. This drives the
	# real spawn seam and samples MID-RUN.
	var registry := AnimBehaviorRegistry.new()
	AnimBehaviors.register_all(registry)
	var stage := FakeStage.new()
	var vm := AnimScriptVM.new()
	vm.registry = registry
	vm.stage = stage
	vm.state = AnimScriptVM.State.RUNNING

	var template := "gMimicOrbSpriteTemplate"
	var ctx := {
		"template": template,
		"template_data": AnimData.template(template),
		"anim_battler": 0,
		"blend": {"eva": 16, "evb": 0},
	}
	vm.args[0] = 0
	vm.args[1] = 0
	registry.get_behavior("AnimMimicOrb").call(vm, ctx)

	var spawned: AnimSprite = null
	for child in stage.layer_node.get_children():
		if child is AnimSprite:
			spawned = child as AnimSprite
			break
	_chk("H.01 `_make_sprite` binds the template's affine table",
			spawned != null and spawned.has_affine_anim())
	if spawned == null:
		_chk("H.02 (skipped: nothing spawned)", false)
		_chk("H.03 (skipped: nothing spawned)", false)
		_chk("H.04 (skipped: nothing spawned)", false)
		stage.layer_node.free()
		return

	var base := spawned.scale.x
	_chk("H.02 ...at the stage's own pixel scale (%.2f)" % base, base > 1.0)

	# Drive the VM's real per-frame pair — behaviors then sprites, in that order.
	var peak := base
	for _f in range(30):
		vm._step_behaviors()
		vm._tick_sprites()
		if is_instance_valid(spawned):
			peak = maxf(peak, spawned.scale.x)
	# The orb's own table swells it to 2.6x. Nothing in `_mimic_orb` does that
	# any more — the hand-rolled 8-frame lerp it used to run only ever reached
	# 1.0x, so this figure is only reachable if the TABLE ran.
	_chk("H.03 the table really runs inside a live VM tick (%.2fx base)"
			% (peak / base), peak > base * 2.0)

	# And the behavior handed off on the affine clock rather than a frame count:
	# it can only have reached the travel leg by observing `affine_ended`.
	var moved := is_instance_valid(spawned) \
			and spawned.centre.distance_to(stage.center_of(1)) > 0.0
	_chk("H.04 ...and the consumer advanced past its grow leg", moved)

	stage.layer_node.free()
