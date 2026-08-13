extends Node

# [M36E3] Suite for the BACKGROUND-DEPENDENT behaviors — the half of M36E that
# drives the layer M36E2 built.
#
# What these tests are shaped around: every one of these behaviors is either
# open-ended (it runs until the script says stop) or restores something on the
# way out. Both are invisible to a "did it do anything" check and both fail
# permanently when wrong — an open-ended effect registered as a COUNTED task
# hangs `waitforvisualfinish` forever, and a shake that resets the scroll to
# zero instead of its captured value silently cancels any scroll in progress.
# So the assertions are about task accounting, direction, and restoration.

var _pass := 0
var _fail := 0
var _registry: AnimBehaviorRegistry


func _ready() -> void:
	AnimData.ensure_loaded()
	_registry = AnimBehaviorRegistry.new()
	AnimBehaviors.register_all(_registry)

	_test_palette_rotation_math()
	_test_psychic_background()
	_test_sliding_bg()
	_test_shake_platforms()
	_test_scrolling_fog()
	_test_surf_wave()
	_test_surf_scanline_alpha_band()
	_test_metallic_shine()
	_test_coverage()
	_test_b19_scary_face_ramps_holds_and_clears()
	_test_b19_scary_face_variant_follows_the_target_side()

	var total := _pass + _fail
	print("m36e3_bg_behaviors_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


class BgStage extends RefCounted:
	var layer_node: TextureRect
	var nodes: Dictionary = {}
	var bg_name := ""
	var scroll := Vector2.ZERO
	var fade := 0.0
	var player_side := true
	var remap_from: PackedColorArray = PackedColorArray()
	var remap_to: PackedColorArray = PackedColorArray()
	var remap_cleared := 0
	var bg_cleared := 0

	func _init() -> void:
		layer_node = TextureRect.new()
		layer_node.size = Vector2(1024, 768)
		for i in range(4):
			var n := TextureRect.new()
			n.size = Vector2(64, 64)
			n.position = Vector2(100 + i * 200, 300)
			n.texture = _dummy_texture()
			layer_node.add_child(n)
			nodes[i] = n

	func _dummy_texture() -> Texture2D:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		return ImageTexture.create_from_image(img)

	func sprite_for(b: int) -> Control: return nodes.get(b, null)
	func mon_for(b: int): return nodes.get(b, null)
	func center_of(b: int) -> Vector2:
		var n: Control = nodes.get(b, null)
		return n.position + n.size * 0.5 if n != null else Vector2.ZERO
	func layer() -> Control: return layer_node
	func background_layer() -> TextureRect: return layer_node
	func pixel_scale() -> float: return 1.0
	func facing_sign() -> float: return 1.0
	func attacker_is_player_side() -> bool: return player_side
	func set_battler_visible(b: int, v: bool) -> void:
		var n: Control = nodes.get(b, null)
		if n != null:
			n.visible = v

	func set_background(name: String) -> bool:
		if not AnimData.has_background(name):
			return false
		bg_name = name
		return true

	func clear_background() -> void:
		bg_name = ""
		bg_cleared += 1

	func set_fade(amount: float) -> void:
		fade = amount

	func set_background_scroll(offset: Vector2) -> void:
		scroll = offset

	func scroll_background_by(delta: Vector2) -> void:
		scroll += delta

	func background_scroll() -> Vector2:
		return scroll

	func set_background_palette_remap(f: PackedColorArray,
			t: PackedColorArray) -> void:
		remap_from = f
		remap_to = t

	func clear_background_palette_remap() -> void:
		remap_cleared += 1

	# [M36E5] The per-scanline ALPHA window: (top, bottom, inside, outside),
	# top/bottom in stage pixels. `pixel_scale()` above is 1.0, so on this
	# double they read as GBA screen rows directly.
	var alpha_band := Vector4(0.0, 0.0, 1.0, 1.0)
	var alpha_band_cleared := 0

	func set_background_alpha_band(top: float, bottom: float,
			inside: float, outside: float) -> void:
		alpha_band = Vector4(top, bottom, inside, outside)

	func clear_background_alpha_band() -> void:
		alpha_band = Vector4(0.0, 0.0, 1.0, 1.0)
		alpha_band_cleared += 1

	func background_alpha_band() -> Vector4:
		return alpha_band


func _vm(stage: BgStage) -> AnimScriptVM:
	var vm := AnimScriptVM.new()
	vm.registry = _registry
	vm.stage = stage
	vm.state = AnimScriptVM.State.RUNNING
	vm.args.resize(8)
	vm.args.fill(0)
	return vm


func _pump(vm: AnimScriptVM, frames: int) -> void:
	for i in range(frames):
		vm._step_behaviors()


func _run(vm: AnimScriptVM, name: String) -> void:
	_registry.get_behavior(name).call(vm, {})


# ── the rotation maths ────────────────────────────────────────────────────
# The direction is the whole point: rotating the wrong way makes the psychic
# ramp flow backwards and the surf wave look like it is receding.
func _test_palette_rotation_math() -> void:
	var base := PackedColorArray([
			Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1), Color(1, 1, 0)])
	var r0 := AnimBehaviors._rotated_palette(base, 0)
	_chk("a zero-step rotation is the identity", r0 == base)
	var r1 := AnimBehaviors._rotated_palette(base, 1)
	_chk("one step moves each slot's colour UP one slot (slot 1 takes slot 0)",
			r1[1] == base[0] and r1[2] == base[1] and r1[3] == base[2])
	_chk("...and slot 0 wraps around from the last slot", r1[0] == base[3])
	var rn := AnimBehaviors._rotated_palette(base, base.size())
	_chk("a full cycle returns to the original", rn == base)
	_chk("an empty palette rotates to empty without erroring",
			AnimBehaviors._rotated_palette(PackedColorArray(), 3).is_empty())


# ── AnimTask_SetPsychicBackground ─────────────────────────────────────────
func _test_psychic_background() -> void:
	var stage := BgStage.new()
	var vm := _vm(stage)
	stage.set_background("BG_PSYCHIC")
	vm._bg_name = "BG_PSYCHIC"
	var before := vm.visual_count()
	_run(vm, "AnimTask_SetPsychicBackground")
	_chk("the psychic cycle does NOT count toward visual-task completion "
			+ "(so waitforvisualfinish cannot hang on it)",
			vm.visual_count() == before)

	_pump(vm, 3)
	_chk("nothing rotates before the 4-frame period elapses",
			stage.remap_to.is_empty())
	_pump(vm, 1)
	_chk("the palette rotates on the 4th frame", stage.remap_to.size() == 11)
	_chk("...over exactly the 11-entry window source rotates",
			stage.remap_from.size() == 11)
	_chk("...and it really is a rotation, not a no-op recolour",
			stage.remap_to[0] != stage.remap_from[0])

	# Unbounded: it must still be running long past any plausible frame count.
	_pump(vm, 200)
	_chk("it is still running after 200 frames (it is open-ended)",
			vm.visual_count() == before)

	# Only the arg-7 sentinel stops it.
	vm.args[AnimScriptVM.ARG_RET] = -1
	_pump(vm, 1)
	_chk("setting arg 7 to -1 ends it", stage.remap_cleared >= 1)


# ── AnimTask_StartSlidingBg ───────────────────────────────────────────────
func _test_sliding_bg() -> void:
	# 8.8 fixed point: 256 units == 1 px/frame.
	var stage := BgStage.new()
	var vm := _vm(stage)
	vm.args[0] = 256
	vm.args[3] = -1
	var before := vm.visual_count()
	_run(vm, "AnimTask_StartSlidingBg")
	_chk("the sliding scroll does not count toward completion",
			vm.visual_count() == before)
	_pump(vm, 10)
	_chk("256 units/frame scrolls exactly 10px in 10 frames (%.1f)"
			% stage.scroll.x, is_equal_approx(stage.scroll.x, 10.0))

	# The accumulator is the thing worth asserting: a velocity BELOW one pixel
	# per frame must still move, just slower. Truncating each frame instead
	# would freeze every slow scroll dead.
	var s2 := BgStage.new()
	var vm2 := _vm(s2)
	vm2.args[0] = 64  # a quarter pixel per frame
	vm2.args[3] = -1
	_run(vm2, "AnimTask_StartSlidingBg")
	_pump(vm2, 3)
	_chk("a sub-pixel velocity has not moved a whole pixel yet",
			is_zero_approx(s2.scroll.x))
	_pump(vm2, 1)
	_chk("...but the retained fraction delivers a pixel on the 4th frame",
			is_equal_approx(s2.scroll.x, 1.0))

	# The mirror flag, and that it is CONDITIONAL on side.
	var s3 := BgStage.new()
	s3.player_side = false
	var vm3 := _vm(s3)
	vm3.args[0] = 256
	vm3.args[2] = 1
	vm3.args[3] = -1
	_run(vm3, "AnimTask_StartSlidingBg")
	_pump(vm3, 4)
	_chk("arg2 mirrors the scroll for an opponent-side attacker",
			s3.scroll.x < 0.0)
	var s4 := BgStage.new()
	s4.player_side = false
	var vm4 := _vm(s4)
	vm4.args[0] = 256
	vm4.args[2] = 0  # mirror NOT requested
	vm4.args[3] = -1
	_run(vm4, "AnimTask_StartSlidingBg")
	_pump(vm4, 4)
	_chk("...and does not mirror when arg2 is 0, same side", s4.scroll.x > 0.0)

	# Sentinel teardown resets the scroll.
	vm.args[AnimScriptVM.ARG_RET] = -1
	_pump(vm, 1)
	_chk("the sentinel resets the scroll to zero", stage.scroll == Vector2.ZERO)


# ── AnimTask_ShakePlatforms ───────────────────────────────────────────────
func _test_shake_platforms() -> void:
	var stage := BgStage.new()
	# A background already mid-scroll: the shake must return HERE, not to zero.
	stage.scroll = Vector2(37.0, 0.0)
	var vm := _vm(stage)
	vm.args[0] = 5  # ANIM_OPPONENT_LEFT -- the platforms path
	vm.args[1] = 2  # intensity -> amplitude 5
	vm.args[2] = 6  # duration
	_run(vm, "AnimTask_ShakePlatforms")

	_pump(vm, 1)
	_chk("the register does not move on the first frame (it updates every "
			+ "SECOND frame, %.1f)" % stage.scroll.x,
			is_equal_approx(stage.scroll.x, 37.0))
	_pump(vm, 1)
	_chk("...and does move on the second", not is_equal_approx(
			stage.scroll.x, 37.0))
	var first := stage.scroll.x
	_pump(vm, 2)
	_chk("consecutive updates alternate sign around the captured base",
			(first - 37.0) * (stage.scroll.x - 37.0) < 0.0)

	_pump(vm, 400)
	_chk("the shake terminates", vm.visual_count() == 0)
	_chk("...and restores the CAPTURED offset exactly, not zero (%.1f)"
			% stage.scroll.x, is_equal_approx(stage.scroll.x, 37.0))

	# Intensity 0 falls back to move power / 10, per source.
	var s2 := BgStage.new()
	var vm2 := _vm(s2)
	vm2.move_power = 100
	vm2.args[0] = 5
	vm2.args[1] = 0
	vm2.args[2] = 4
	_run(vm2, "AnimTask_ShakePlatforms")
	_pump(vm2, 2)
	_chk("intensity 0 derives the amplitude from move power (%.1f)"
			% s2.scroll.x, absf(s2.scroll.x) > 5.0)


# ── AnimTask_HazeScrollingFog ─────────────────────────────────────────────
func _test_scrolling_fog() -> void:
	_chk("the haze blend table is source-exact, including its plateaus "
			+ "(it is not a linear ramp)",
			AnimBehaviors._HAZE_BLEND_AMOUNTS == ([
				0, 1, 2, 2, 2, 2, 3, 4, 4, 4, 5, 6, 6, 6, 6, 7, 8, 8, 8, 9]
				as Array[int]))

	var stage := BgStage.new()
	var vm := _vm(stage)
	_run(vm, "AnimTask_HazeScrollingFog")
	_pump(vm, 10)
	_chk("the fog scrolls left 1px/frame (%.1f after 10)" % stage.scroll.x,
			is_equal_approx(stage.scroll.x, -10.0))
	_pump(vm, 60)
	_chk("the blend ramps in over the fade phase (alpha %.2f)"
			% stage.layer_node.modulate.a,
			stage.layer_node.modulate.a > 0.2)

	_pump(vm, 400)
	_chk("the fog animation terminates on its own (it is finite)",
			vm.visual_count() == 0)
	_chk("...and resets the scroll", stage.scroll == Vector2.ZERO)

	# MistBallFog loads the identical assets upstream and maps to the same
	# behavior -- asserted so a future session doesn't split them apart.
	_chk("AnimTask_MistBallFog resolves to the same behavior",
			_registry.get_behavior("AnimTask_MistBallFog")
			== _registry.get_behavior("AnimTask_HazeScrollingFog"))


# ── AnimTask_CreateSurfWave — the headline ────────────────────────────────
func _test_surf_wave() -> void:
	# The side-dependent asset AND the mirrored velocity. If either is wrong
	# the wave travels away from the target instead of over it, which is the
	# one way this animation can look actively broken rather than plain.
	var stage := BgStage.new()
	stage.player_side = true
	var vm := _vm(stage)
	_run(vm, "AnimTask_CreateSurfWave")
	_chk("a player-side Surf installs the player wave asset",
			stage.bg_name == "SURF_PLAYER")
	var start_x := stage.scroll.x
	_pump(vm, 4)
	_chk("...and travels LEFT and DOWN (%.1f, %.1f)"
			% [stage.scroll.x - start_x, stage.scroll.y],
			stage.scroll.x < start_x)

	var s2 := BgStage.new()
	s2.player_side = false
	var vm2 := _vm(s2)
	_run(vm2, "AnimTask_CreateSurfWave")
	_chk("an opponent-side Surf installs the opponent wave asset",
			s2.bg_name == "SURF_OPPONENT")
	var start2 := s2.scroll.x
	_pump(vm2, 4)
	_chk("...and travels the MIRRORED direction, rightward",
			s2.scroll.x > start2)

	# The palette cycle is what makes the water look like water.
	_pump(vm, 4)
	_chk("the wave cycles its palette (7 entries, not the psychic 11)",
			stage.remap_from.size() == 7)

	# It ends on its own -- unlike the psychic background, no sentinel needed.
	_pump(vm, 400)
	_chk("Surf terminates on its own blend ramp (no sentinel required)",
			vm.visual_count() == 0)
	_chk("...clearing the background it installed", stage.bg_cleared >= 1)
	_chk("...and its palette remap", stage.remap_cleared >= 1)

	# The muddy recolor is a real separate pulled asset, selected by arg0.
	var s3 := BgStage.new()
	var vm3 := _vm(s3)
	vm3.args[0] = 1  # ANIM_SURF_PAL_MUDDY_WATER
	_run(vm3, "AnimTask_CreateSurfWave")
	_chk("arg0 selects the muddy-water recolor where one was pulled",
			s3.bg_name == "SURF_MUDDY_PLAYER")


# [M36E5] Surf's scanline effect is a per-row ALPHA WINDOW, and the window is
# what makes the wave wash across the screen rather than fade in on the spot.
#
# `AnimTask_SurfWaveScanlineEffect` points its DMA at REG_BLDALPHA
# (`battle_anim_water.c:1164`), so rows inside `[data[4], data[5])` show the
# wave at the ramping coefficient and every row outside shows the battle
# backdrop with the wave fully transparent. The band's two edges are seeded
# per side (:1044-1069) and one of them moves one row per frame (:1172-1183).
#
# ⚠️ **THE SIDES OPEN IN OPPOSITE DIRECTIONS, AND THAT IS THE ASSERTION.** A
# port that installed a band but moved the wrong edge would still produce
# "there is a band" and "it changes", so both directions are pinned
# absolutely: the player-side band's TOP falls while its bottom holds, and
# the opponent-side band's BOTTOM rises while its top holds.
func _test_surf_scanline_alpha_band() -> void:
	var stage := BgStage.new()
	stage.player_side = true
	var vm := _vm(stage)
	_run(vm, "AnimTask_CreateSurfWave")
	_pump(vm, 1)
	var b0 := stage.background_alpha_band()
	_chk("Surf installs a per-scanline alpha window at all (%s)" % b0,
			b0.y > b0.x)
	# The whole point of the window: outside it the wave is INVISIBLE, so the
	# battlefield shows through. A uniform fade cannot express this.
	_chk("...whose outside coefficient is fully transparent (%.2f)" % b0.w,
			is_equal_approx(b0.w, 0.0))
	_chk("...seeded on the player side as rows 48..112, per source's data[4]/"
			+ "data[5] (%.0f..%.0f)" % [b0.x, b0.y],
			is_equal_approx(b0.y, 112.0) and b0.x > 40.0 and b0.x <= 48.0)

	_pump(vm, 20)
	var b1 := stage.background_alpha_band()
	_chk("...and OPENS UPWARD: the top edge climbs toward row 0 (%.0f -> %.0f)"
			% [b0.x, b1.x], b1.x < b0.x)
	_chk("...while the bottom edge stays pinned at 112 (%.0f)" % b1.y,
			is_equal_approx(b1.y, 112.0))

	# The opposite side sweeps the other way -- source swaps which edge moves.
	var s2 := BgStage.new()
	s2.player_side = false
	var vm2 := _vm(s2)
	_run(vm2, "AnimTask_CreateSurfWave")
	_pump(vm2, 1)
	var c0 := s2.background_alpha_band()
	_pump(vm2, 20)
	var c1 := s2.background_alpha_band()
	_chk("an opponent-side Surf OPENS DOWNWARD instead (%.0f -> %.0f)"
			% [c0.y, c1.y], c1.y > c0.y)
	_chk("...with its top edge pinned at row 0 (%.0f)" % c1.x,
			is_equal_approx(c1.x, 0.0))
	_chk("...and stops at row 112 like the other side does",
			_band_after(s2, vm2, 200).y <= 112.0)

	# ⚠️ The peak coefficient is 13/16, NOT 1.0: `data[3]` ramps to 13 and the
	# blend is `eva/16`, so the wave is never fully opaque over the battlers.
	# Dividing by 13 -- which is what the uniform fade did -- reaches 1.0.
	var s3 := BgStage.new()
	var vm3 := _vm(s3)
	_run(vm3, "AnimTask_CreateSurfWave")
	_pump(vm3, 40)          # past the 26-frame ramp, inside the hold
	var peak := s3.background_alpha_band().z
	_chk("the wave holds at 13/16 opacity, not fully opaque (%.4f)" % peak,
			is_equal_approx(peak, 13.0 / 16.0))

	# And it takes the window down with it, or the next background installed
	# on this layer would be rendered through Surf's window.
	_pump(vm3, 400)
	_chk("Surf clears its alpha window when it ends",
			s3.alpha_band_cleared >= 1)


func _band_after(stage: BgStage, vm: AnimScriptVM, frames: int) -> Vector4:
	_pump(vm, frames)
	return stage.background_alpha_band()


# ── AnimTask_MetallicShine ────────────────────────────────────────────────
func _test_metallic_shine() -> void:
	var stage := BgStage.new()
	var vm := _vm(stage)
	var node: Control = stage.nodes[0]
	vm.args[0] = 0  # not permanent
	vm.args[1] = 0  # grayscale rather than a colour blend
	_run(vm, "AnimTask_MetallicShine")
	# The recolour must be a real per-pixel REPLACEMENT, not a modulate tint:
	# modulate multiplies, so grayscaling a default (1,1,1) modulate is a
	# no-op and the effect would be invisible. Asserted at the mechanism
	# because that is the failure this exact check caught.
	var mat := node.material as ShaderMaterial
	_chk("the mon is recoloured through a shader, not modulate "
			+ "(modulate multiplies -- grayscaling it is a no-op)",
			mat != null)
	_chk("...fully desaturating it, matching (r+g+b)/3 upstream",
			mat != null and is_equal_approx(
				float(mat.get_shader_parameter("gray")), 1.0))
	_chk("...and not also tinting it", mat != null and is_zero_approx(
			float(mat.get_shader_parameter("tint_amount"))))

	# 3 sweeps of 32 frames. The palette reverts at sweep 2, and sweep 3 is a
	# real 32 frames during which nothing shows -- shortening it to 64 would
	# make every script using this run measurably fast.
	_pump(vm, 64)
	_chk("the recolour is undone at the end of the second sweep when "
			+ "`permanent` is 0", node.material == null)
	_chk("...but the task is still running (sweep 3 is real)",
			vm.visual_count() > 0)
	_pump(vm, 32)
	_chk("it ends after the third 32-frame sweep, 96 total",
			vm.visual_count() == 0)

	# permanent=1 keeps the recolour.
	var s2 := BgStage.new()
	var vm2 := _vm(s2)
	var n2: Control = s2.nodes[0]
	vm2.args[0] = 1  # permanent
	vm2.args[1] = 0
	_run(vm2, "AnimTask_MetallicShine")
	_pump(vm2, 96)
	_chk("`permanent` = 1 keeps the recolour after the sweeps",
			n2.material != null)

	# The colour branch: arg1 nonzero blends toward the GBA RGB15 literal.
	var s3 := BgStage.new()
	var vm3 := _vm(s3)
	var n3: Control = s3.nodes[0]
	vm3.args[0] = 0
	vm3.args[1] = 1
	vm3.args[2] = (23 << 10) | (6 << 5) | 24  # Poison Tail's RGB(24,6,23)
	_run(vm3, "AnimTask_MetallicShine")
	var mat3 := n3.material as ShaderMaterial
	_chk("a colour blend tints rather than desaturating",
			mat3 != null and is_zero_approx(
				float(mat3.get_shader_parameter("gray")))
			and float(mat3.get_shader_parameter("tint_amount")) > 0.5)
	var t3: Color = mat3.get_shader_parameter("tint") if mat3 != null 			else Color.BLACK
	_chk("...and the GBA RGB15 literal decodes with red strongest "
			+ "(RGB(24,6,23) -> r %.2f g %.2f)" % [t3.r, t3.g], t3.r > t3.g)
	_chk("...blending at source's own 11/16 coefficient",
			mat3 != null and is_equal_approx(
				float(mat3.get_shader_parameter("tint_amount")), 11.0 / 16.0))


# ── coverage ─────────────────────────────────────────────────────────────
func _test_coverage() -> void:
	var dispatcher := AnimDispatcher.new(_registry)
	_chk("SURF IS PLAYABLE — the move this whole sub-tier was for",
			dispatcher.can_play_move(57))
	# Same id sweep the coverage tool uses: every move with a bound script.
	var all_ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			all_ids.append(id)
	var cov: Dictionary = dispatcher.coverage(all_ids)
	var playable := int(cov.get("playable", 0))
	# A floor, not an exact match: later batches should only raise this.
	_chk("roster coverage is at least 228 moves (%d)" % playable,
			playable >= 228)


# ── [M36D batch 19] ScaryFace ─────────────────────────────────────────────

func _test_b19_scary_face_ramps_holds_and_clears() -> void:
	# A pure BLEND ramp over a background, and the reason the off-screen
	# filler row is safe to colour with the visible bank's palette: this
	# behavior never scrolls (upstream holds BG1 X/Y at 0 and only blends).
	var stage := BgStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_ScaryFace").call(vm, {})
	_chk("b19 scary face installs a background", stage.bg_name != "")
	var layer := stage.background_layer()
	_chk("b19 scary face starts fully transparent",
			is_equal_approx(layer.modulate.a, 0.0))

	# eva climbs 1..14 one step every 2 frames -> 28 frames to the peak.
	for i in range(28):
		vm._step_behaviors()
	var peak: float = layer.modulate.a
	_chk("b19 scary face peaks at 14/16, NOT fully opaque (got %.3f)" % peak,
			absf(peak - 14.0 / 16.0) < 0.02)

	# 21-frame hold at the peak.
	for i in range(20):
		vm._step_behaviors()
	_chk("b19 scary face HOLDS at its peak rather than continuing to climb",
			is_equal_approx(layer.modulate.a, peak))

	# ...then unwinds the same way and clears the background behind it.
	for i in range(40):
		vm._step_behaviors()
	_chk("b19 scary face clears its background when it ends", stage.bg_name == "")


func _test_b19_scary_face_variant_follows_the_target_side() -> void:
	# The pick reads backwards at first glance: !IsOnPlayerSide(target)
	# selects the *Player* tilemap, so "Player" names the viewpoint the face
	# is aimed FROM, not the side it sits on. Wiring it the intuitive way
	# would silently swap the two on every use.
	var s1 := BgStage.new()
	s1.player_side = true          # attacker player-side -> target opposing
	var v1 := _vm(s1)
	_registry.get_behavior("AnimTask_ScaryFace").call(v1, {})

	var s2 := BgStage.new()
	s2.player_side = false         # attacker opposing -> target player-side
	var v2 := _vm(s2)
	_registry.get_behavior("AnimTask_ScaryFace").call(v2, {})

	_chk("b19 an opposing target selects the PLAYER-viewpoint variant (got '%s')"
			% s1.bg_name, s1.bg_name == "SCARY_FACE_PLAYER")
	_chk("b19 a player-side target selects the OPPONENT variant (got '%s')"
			% s2.bg_name, s2.bg_name == "SCARY_FACE_OPPONENT")
	_chk("b19 the two sides genuinely pick different backgrounds",
			s1.bg_name != s2.bg_name)
