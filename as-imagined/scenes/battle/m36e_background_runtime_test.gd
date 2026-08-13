extends Node

# [M36E2] Suite for the background RUNTIME: the fade state machine and the
# fadetobg / fadetobgfromset / changebg / restorebg / waitbgfade* opcodes.
#
# What matters here is the ORDER of the fade, not merely that a texture gets
# assigned. Upstream (Task_FadeToBg, src/battle_anim.c:1750) the screen goes
# black BEFORE the swap and back afterwards, and the two wait opcodes hang on
# different phases of that. A port that swapped first and faded second would
# look wrong in a way no "did the texture change" assertion would catch, so
# the phase boundaries are asserted directly.

var _pass := 0
var _fail := 0
var _registry: AnimBehaviorRegistry


func _ready() -> void:
	AnimData.ensure_loaded()
	_registry = AnimBehaviorRegistry.new()
	AnimBehaviors.register_all(_registry)

	_test_bg_id_resolution()
	_test_fade_order()
	_test_wait_opcodes_block_on_the_right_phases()
	_test_changebg_is_immediate()
	_test_restore_clears()
	_test_background_never_leaks()
	_test_unknown_bg_still_costs_its_frames()
	_test_real_stage_band_surfaces()

	var total := _pass + _fail
	print("m36e_background_runtime_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# A stage double that records what the VM asks of the background layer.
class BgStage extends RefCounted:
	var layer_node: Control
	var nodes: Dictionary = {}
	var bg_name := ""
	var bg_cleared := 0
	var fade := 0.0
	var player_side := true
	# Log of (fade, bg_name) at each change, so ORDER can be asserted.
	var events: Array = []

	func _init() -> void:
		layer_node = Control.new()
		layer_node.size = Vector2(1024, 768)
		for i in range(4):
			var n := Control.new()
			n.size = Vector2(64, 64)
			n.position = Vector2(100 + i * 200, 300)
			layer_node.add_child(n)
			nodes[i] = n

	func sprite_for(b: int) -> Control: return nodes.get(b, null)
	func mon_for(b: int): return nodes.get(b, null)
	func center_of(b: int) -> Vector2:
		var n: Control = nodes.get(b, null)
		return n.position + n.size * 0.5 if n != null else Vector2.ZERO
	func layer() -> Control: return layer_node
	func pixel_scale() -> float: return 1.0
	func facing_sign() -> float: return 1.0
	func attacker_is_player_side() -> bool: return player_side
	func set_battler_visible(b: int, v: bool) -> void:
		var n: Control = nodes.get(b, null)
		if n != null:
			n.visible = v

	func set_background(name: String) -> bool:
		# Mirrors the real one: refuses a name with no pulled asset.
		if not AnimData.has_background(name):
			return false
		bg_name = name
		events.append({"fade": fade, "bg": name})
		return true

	func clear_background() -> void:
		bg_name = ""
		bg_cleared += 1
		events.append({"fade": fade, "bg": ""})

	func set_fade(amount: float) -> void:
		fade = amount


func _vm(stage: BgStage) -> AnimScriptVM:
	var vm := AnimScriptVM.new()
	vm.registry = _registry
	vm.stage = stage
	vm.state = AnimScriptVM.State.RUNNING
	return vm


# Drives the VM's fade stepper directly, one GBA frame at a time.
func _pump(vm: AnimScriptVM, frames: int) -> void:
	for i in range(frames):
		vm._step_behaviors()


func _test_bg_id_resolution() -> void:
	# The command stream carries BG ids as INTEGERS; the name must come back.
	var psychic_id := -1
	for id in range(0, 90):
		if AnimData.bg_name_for_id(id) == "BG_PSYCHIC":
			psychic_id = id
			break
	_chk("a BG integer id resolves back to its BG_* name (found id %d)"
			% psychic_id, psychic_id >= 0)
	_chk("BG_PSYCHIC has a pulled asset",
			AnimData.has_background("BG_PSYCHIC"))
	_chk("...which loads as a texture",
			AnimData.background_texture("BG_PSYCHIC") != null)
	_chk("an unknown id resolves to empty rather than erroring",
			AnimData.bg_name_for_id(9999) == "")
	_chk("the background set is populated (%d)" % AnimData.background_count(),
			AnimData.background_count() >= 85)


func _test_fade_order() -> void:
	# The screen must be FULLY black at the moment the background swaps.
	var stage := BgStage.new()
	var vm := _vm(stage)
	vm._start_bg_fade("BG_PSYCHIC")
	_chk("fade begins in the FADING_OUT phase",
			vm.bg_fade_state() == AnimScriptVM.BgFade.FADING_OUT)
	_chk("...with nothing swapped yet", stage.bg_name == "")

	_pump(vm, 8)
	_chk("the screen darkens progressively (fade %.2f)" % stage.fade,
			stage.fade > 0.3 and stage.fade < 1.0)
	_chk("...and still nothing has swapped", stage.bg_name == "")

	_pump(vm, 8)
	_chk("the background swaps only once faded out",
			stage.bg_name == "BG_PSYCHIC")
	_chk("...and the swap happened at full black (recorded fade %.2f)"
			% (float(stage.events[0]["fade"]) if stage.events.size() > 0
				else -1.0),
			stage.events.size() > 0
			and is_equal_approx(float(stage.events[0]["fade"]), 1.0))

	_pump(vm, 16)
	_chk("the fade returns to clear", is_zero_approx(stage.fade))
	_chk("...and the state machine lands back on IDLE",
			vm.bg_fade_state() == AnimScriptVM.BgFade.IDLE)
	_chk("the background is still up after the fade-in",
			stage.bg_name == "BG_PSYCHIC")


func _test_wait_opcodes_block_on_the_right_phases() -> void:
	# waitbgfadeout releases once black; waitbgfadein only once fully back.
	var stage := BgStage.new()
	var vm := _vm(stage)
	vm._start_bg_fade("BG_PSYCHIC")
	_pump(vm, 16)
	_chk("after fading out, the state is past FADING_OUT (so waitbgfadeout "
			+ "releases)",
			vm.bg_fade_state() != AnimScriptVM.BgFade.FADING_OUT)
	_chk("...but not yet IDLE (so waitbgfadein still blocks)",
			vm.bg_fade_state() != AnimScriptVM.BgFade.IDLE)
	_pump(vm, 16)
	_chk("once fully faded in, waitbgfadein releases",
			vm.bg_fade_state() == AnimScriptVM.BgFade.IDLE)


func _test_changebg_is_immediate() -> void:
	# changebg swaps with NO fade at all -- that is the whole difference.
	var stage := BgStage.new()
	var vm := _vm(stage)
	var id := -1
	for i in range(0, 90):
		if AnimData.bg_name_for_id(i) == "BG_DARK":
			id = i
			break
	if id < 0:
		return
	vm._execute(["changebg", id])
	_chk("changebg swaps immediately", stage.bg_name == "BG_DARK")
	_chk("...without darkening the screen", is_zero_approx(stage.fade))
	_chk("...and is recorded as a change the VM must undo",
			vm.background_changed())


func _test_restore_clears() -> void:
	var stage := BgStage.new()
	var vm := _vm(stage)
	vm._start_bg_fade("BG_PSYCHIC")
	_pump(vm, 32)
	_chk("a background is up before restoring", stage.bg_name == "BG_PSYCHIC")
	vm._start_bg_restore()
	_pump(vm, 16)
	_chk("restorebg clears only once faded out", stage.bg_cleared == 1)
	_pump(vm, 16)
	_chk("...and fades back to clear", is_zero_approx(stage.fade))
	_chk("...leaving no background up", stage.bg_name == "")


func _test_background_never_leaks() -> void:
	# The same invariant as the visibility fix: a script that ends while its
	# background is up must not leave the battlefield permanently altered.
	var stage := BgStage.new()
	var vm := _vm(stage)
	vm._start_bg_fade("BG_PSYCHIC")
	_pump(vm, 20)
	_chk("background is up mid-animation", stage.bg_name == "BG_PSYCHIC")
	vm._finish()
	_chk("finishing the run clears the background", stage.bg_name == "")
	_chk("...and clears the fade too", is_zero_approx(stage.fade))


func _test_unknown_bg_still_costs_its_frames() -> void:
	# Three assets legitimately have no pull (they span two palette banks),
	# and contest-only ids are never pulled. Those must still consume the
	# fade's frames, or every script using one would run measurably fast.
	var stage := BgStage.new()
	var vm := _vm(stage)
	vm._start_bg_fade("")
	_chk("an unknown background still enters the fade",
			vm.bg_fade_state() == AnimScriptVM.BgFade.FADING_OUT)
	_pump(vm, 32)
	_chk("...and completes on the same schedule",
			vm.bg_fade_state() == AnimScriptVM.BgFade.IDLE)
	_chk("...having swapped nothing", stage.bg_name == "")


# ── The REAL AnimStage, not a double ──────────────────────────────────────
#
# ⚠️ **EVERY OTHER TEST IN THIS FILE DRIVES A `BgStage` DOUBLE, WHICH IS WHY
# A BUG IN THE REAL BACKGROUND CODE COULD SIT THERE UNSEEN.** The doubles
# record what the VM ASKED FOR; nothing anywhere checked that `AnimStage`
# then did it. This section builds the real thing and reads the shader
# uniforms back.
#
# The bug it pins: `_apply_bg_band` read `node.material` instead of creating
# it, so a band set while no material existed was silently dropped. The
# material is made lazily by whichever effect asks first, and
# `clear_background` nulls it while leaving the layer sized — so a run that
# clears a background and then sets a band hit exactly that hole.
func _test_real_stage_band_surfaces() -> void:
	var root := Control.new()
	root.size = Vector2(1200, 800)
	var backdrop := Control.new()
	root.add_child(backdrop)
	var layer := Control.new()
	layer.size = Vector2(1200, 800)
	root.add_child(layer)
	add_child(root)

	var stage := AnimStage.new(func(_m): return null, func(): return layer)
	# Size the layer the way a real run does, then drop the material.
	_chk("real stage installs a pulled background", stage.set_background("SURF_PLAYER"))
	stage.clear_background()
	var node := stage.background_layer()
	_chk("...and clearing it nulls the material but keeps the layer sized",
			node.material == null and node.size.y > 0.0)

	stage.set_background_band(100.0, 400.0, 25.0)
	var mat := node.material as ShaderMaterial
	_chk("a band set with no material present still reaches the shader",
			mat != null)
	if mat != null:
		# Stage pixels -> UV against the layer's own height, the same
		# convention `_apply_bg_scroll` uses.
		var want: float = 100.0 / node.size.y
		_chk("...at the right UV row (%.5f, want %.5f)"
				% [float(mat.get_shader_parameter("band_top")), want],
				is_equal_approx(float(mat.get_shader_parameter("band_top")), want))

	# The [M36E5] alpha window, same question asked of the other surface.
	stage.set_background_alpha_band(240.0, 560.0, 13.0 / 16.0, 0.0)
	var mat2 := node.material as ShaderMaterial
	_chk("the alpha window reaches the shader too", mat2 != null)
	if mat2 != null:
		_chk("...with its inside coefficient intact (%.4f)"
				% float(mat2.get_shader_parameter("alpha_inside")),
				is_equal_approx(float(mat2.get_shader_parameter("alpha_inside")),
						13.0 / 16.0))
		_chk("...and a fully transparent outside, which is what windows it",
				is_equal_approx(float(mat2.get_shader_parameter("alpha_outside")),
						0.0))
	stage.clear_background_alpha_band()
	_chk("clearing the window restores both coefficients to opaque",
			stage.background_alpha_band() == Vector4(0.0, 0.0, 1.0, 1.0))

	root.queue_free()
