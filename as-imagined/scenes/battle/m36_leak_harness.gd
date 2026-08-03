extends Node
#
# M36 whole-roster LEAK / CLEAN-RUN harness.
#
# What this is FOR, and what it deliberately is not.
#
# Every other M36 suite tests a behavior's own maths on a hand-built fixture.
# None of them plays a REAL move script end to end and asks the question that
# actually bites in a battle: **did the run leave anything behind?** That
# class of defect is invisible to a per-behavior test by construction -- the
# fixture is thrown away after each assertion, so nothing can leak into
# anything -- and it is exactly what a player sees, because a battler left
# displaced, shrunk, hidden or tinted STAYS that way into the next turn.
#
# So this runs all ~780 playable in-scope move scripts against one shared
# stage and checks, per move:
#
#   * the run TERMINATES (no script hangs past a generous ceiling)
#   * the VM does not end in ERROR
#   * every battler is back at its resting position / scale / rotation /
#     visibility / modulate      <- the rule (3) leak class, all at once
#   * the layer is empty afterwards: no AnimSprite, no `_anim_trace` clone
#   * the batch-37 scanline band is cleared
#
# ⚠️ THIS IS DEFECT DETECTION, NOT FIDELITY VERIFICATION. It cannot tell you
# an animation looks right -- only that it ran, cleaned up after itself, and
# did not wedge. Judging whether a port resembles the reference needs the
# reference beside it and remains a human pass. Do not read a green run here
# as "the animations are verified".

const FIRST_Z_MOVE := 848      # Z/Max are out of scope (Rob, 2026-08-03)
const FRAME_CEILING := 1200    # 20 s at 60 fps; a real script never nears it

# ⚠️ KNOWN LEAKS — A PINNED BASELINE, NOT AN ALLOWLIST.
#
# The harness found these on its first run. They are REAL DEFECTS, not
# harness artifacts, and they share ONE root cause in three dresses: the
# VM's cleanup nets only cover the TRACKED path, so a behavior that touches
# a battler node directly, or spawns without registering, escapes them.
#
#   rotated  -> `_restore_scaled_battlers` restores rotation only when the
#               `_anim_mon_rotation` meta is present, which only the MonScale
#               deform helper sets. Behaviors writing `node.rotation = ...`
#               directly are not covered.
#   tinted   -> `_clear_battler_blends` clears only the recolor SHADER.
#               Direct `node.modulate` writes are not covered.
#   sprites  -> `_finish` frees `_spawned`, but `_make_sprite` never calls
#               `notify_spawned`, so sprites whose steppers are cleared by
#               `_finish` before they end are never freed.
#   scaled   -> same family; a direct `node.scale` write outside MonScale.
#
# They are pinned rather than silenced so this suite is GREEN on the known
# set and FAILS the moment the set changes in either direction — a new leak
# from a later batch, or a fix that lands without the baseline being updated.
# **Fixing them is a core-VM change every M36 assertion sits on top of, and
# is deliberately left as its own task rather than rushed in alongside a
# batch.** Shrinking this dictionary is the definition of done.
const KNOWN_LEAKS := {
	# EMPTIED 2026-08-03 by the core-VM cleanup fix. All 23 are gone: the VM
	# now snapshots every battler's whole visual state at `start()` and
	# restores it unconditionally at `_finish()`, and frees every AnimSprite
	# and `_anim_trace` clone left on the layer rather than only the nodes a
	# behavior remembered to register. Keep this dictionary EMPTY -- an entry
	# reappearing means a batch reintroduced the leak class.
}

var _pass := 0
var _fail := 0
var _registry: AnimBehaviorRegistry
var _dispatcher: AnimDispatcher


func _ready() -> void:
	if not AnimData.ensure_loaded():
		print("m36_leak_harness: DATA MISSING (%s)" % AnimData.load_error())
		get_tree().quit(1)
		return
	_registry = AnimBehaviorRegistry.new()
	AnimBehaviors.register_all(_registry)
	_dispatcher = AnimDispatcher.new(_registry)

	var ran := 0
	var hangs: Array = []
	var errors: Array = []
	var leaks: Array = []
	var silent: Array = []

	for id in range(1, FIRST_Z_MOVE):
		var label := AnimData.script_for_move(id)
		if label == "":
			continue
		if not _dispatcher.can_play_move(id):
			continue          # falls back to the generic hit effect; nothing to leak
		ran += 1
		var report := _run_one(label)
		if report["hung"]:
			hangs.append("%d %s" % [id, label])
		if report["errored"]:
			errors.append("%d %s (%s)" % [id, label, report["error"]])
		if not (report["leaks"] as Array).is_empty():
			leaks.append("%d %s -> %s" % [id, label,
					", ".join(PackedStringArray(report["leaks"]))])
		if report["spawned"] == 0:
			silent.append("%d %s" % [id, label])
		var seen: String = ", ".join(PackedStringArray(report["leaks"]))
		var want: String = str(KNOWN_LEAKS.get(id, ""))
		_chk("clean run: move %d (%s)" % [id, label],
				not report["hung"] and not report["errored"] and seen == want)

	print("  [harness] ran %d playable in-scope scripts" % ran)
	_chk("the harness actually exercised the roster", ran > 500)
	_chk("no script hangs past %d frames" % FRAME_CEILING, hangs.is_empty())
	_chk("no script ends in VM ERROR", errors.is_empty())
	# The baseline itself: every pinned entry must still be observed, so a fix
	# that lands without updating this dictionary is caught too.
	var seen_ids: Dictionary = {}
	for line in leaks:
		seen_ids[int(str(line).split(" ")[0])] = true
	var missing: Array = []
	for id in KNOWN_LEAKS.keys():
		if not seen_ids.has(id):
			missing.append(id)
	_chk("the known-leak baseline is exactly %d moves" % KNOWN_LEAKS.size(),
			leaks.size() == KNOWN_LEAKS.size())
	_chk("no NEW leak beyond the pinned baseline",
			seen_ids.size() <= KNOWN_LEAKS.size())
	_chk("no pinned leak has silently been fixed without updating the "
			+ "baseline", missing.is_empty())
	if not missing.is_empty():
		print("  --- pinned but no longer leaking (update KNOWN_LEAKS) ---")
		for id in missing:
			print("      move %d" % int(id))

	for label in ["hangs", "errors", "leaks"]:
		var arr: Array = hangs if label == "hangs" \
				else (errors if label == "errors" else leaks)
		if arr.is_empty():
			continue
		print("  --- %s (%d) ---" % [label, arr.size()])
		for line in arr:
			print("      " + str(line))

	# INFORMATIONAL, deliberately not a failure: a script that spawns nothing
	# may be a genuine sound/query-only animation. Printed so a REGRESSION in
	# the count is visible without asserting a number that has no source.
	print("  [harness] scripts that spawned no visual at all: %d" % silent.size())
	if not silent.is_empty() and silent.size() <= 25:
		for line in silent:
			print("      " + str(line))

	var total := _pass + _fail
	print("m36_leak_harness: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _run_one(label: String) -> Dictionary:
	var stage := HarnessStage.new()
	var base := stage.snapshot()
	var vm := AnimScriptVM.new()
	vm.registry = _registry
	vm.stage = stage

	var out := {"hung": false, "errored": false, "error": "", "leaks": [],
			"spawned": 0}
	if not vm.start(label):
		out["errored"] = true
		out["error"] = vm.error_text
		stage.free_all()
		return out

	var frames := 0
	var peak := 0
	while vm.is_running() and frames < FRAME_CEILING:
		vm.step()
		frames += 1
		peak = maxi(peak, stage.live_sprites())
	out["spawned"] = peak
	if vm.is_running():
		out["hung"] = true
		vm._finish()
	elif vm.state == AnimScriptVM.State.ERROR:
		out["errored"] = true
		out["error"] = vm.error_text

	out["leaks"] = stage.diff(base)
	stage.free_all()
	return out


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# A real-shaped stage double. Deliberately the SAME geometry m36d_batch_test
# uses, so a leak reproduced here can be re-tested there by hand.
class HarnessStage extends RefCounted:
	var layer_node: Control
	var nodes: Dictionary = {}
	var band: Vector3 = Vector3.ZERO
	var scroll := Vector2.ZERO
	var player_side := true

	func _init() -> void:
		layer_node = Control.new()
		layer_node.size = Vector2(1024, 768)
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
	func attacker_is_player_side() -> bool: return player_side
	func set_battler_visible(b: int, v: bool) -> void:
		var n: Control = nodes.get(b, null)
		if n != null:
			n.visible = v
	func background_scroll() -> Vector2: return scroll
	func set_background_scroll(v: Vector2) -> void: scroll = v
	func set_background_band(top: float, bottom: float, off: float) -> void:
		band = Vector3(top, bottom, off)
	func clear_background_band() -> void: band = Vector3.ZERO
	func background_band() -> Vector3: return band

	# Every battler property a behavior in this port can mutate.
	func snapshot() -> Array:
		var out: Array = []
		for i in range(4):
			var n: Control = nodes[i]
			out.append({
				"pos": n.position, "scale": n.scale, "rot": n.rotation,
				"vis": n.visible, "mod": n.modulate, "mat": n.material,
			})
		return out

	func live_sprites() -> int:
		var k := 0
		for c in layer_node.get_children():
			if c is AnimSprite and not c.is_queued_for_deletion():
				k += 1
		return k

	# Returns a list of human-readable leak descriptions; empty is clean.
	func diff(base: Array) -> Array:
		var out: Array = []
		for i in range(4):
			var n: Control = nodes[i]
			var b: Dictionary = base[i]
			if not n.position.is_equal_approx(b["pos"]):
				out.append("battler %d displaced" % i)
			if not n.scale.is_equal_approx(b["scale"]):
				out.append("battler %d scaled" % i)
			if not is_equal_approx(n.rotation, float(b["rot"])):
				out.append("battler %d rotated" % i)
			if n.visible != bool(b["vis"]):
				out.append("battler %d visibility" % i)
			if not n.modulate.is_equal_approx(b["mod"]):
				out.append("battler %d tinted" % i)
			if n.material != b["mat"]:
				out.append("battler %d shader left applied" % i)
		var sprites := 0
		var clones := 0
		for c in layer_node.get_children():
			if c.is_queued_for_deletion():
				continue
			if c is AnimSprite:
				sprites += 1
			elif c.has_meta("_anim_trace"):
				clones += 1
		if sprites > 0:
			out.append("%d sprite(s) left on the layer" % sprites)
		if clones > 0:
			out.append("%d clone(s) left on the layer" % clones)
		if band != Vector3.ZERO:
			out.append("scanline band left set")
		return out

	func free_all() -> void:
		if is_instance_valid(layer_node):
			layer_node.free()
