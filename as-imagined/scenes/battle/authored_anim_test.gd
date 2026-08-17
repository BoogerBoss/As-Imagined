extends Node

# Suite for the HAND-AUTHORED animation dispatch seam: the registry
# (`AuthoredAnims`), the runner that plays a scene and polices it
# (`AuthoredAnimRunner`), and the contract an authored scene has to keep.
#
# The load-bearing properties this suite protects, in the order they matter:
#
#   1. THE SEAM CANNOT BREAK A BATTLE. Every way an entry can be wrong — a
#      typo'd path, a scene that never ends, a scene that leaves sprites
#      behind — degrades to something harmless and reportable. A missing
#      animation is a cosmetic loss; a hung `anim_async` beat is an
#      unrecoverable freeze with the player unable to act.
#   2. THE REGISTRY IS EMPTY. Authored animations override PORTED ones, so an
#      entry is a fidelity decision about something a player can see. A.05
#      fails the moment one is added, which is the point: it forces the
#      decision to be made deliberately rather than inherited.
#   3. THE LEAK RULE IS ENFORCED, not just documented. `m36_leak_harness`
#      walks the VM's own scripts and would never see an authored scene.
#
# Both guards are BREAK-TESTED here rather than asserted from a healthy run:
# C.01 drives a scene that genuinely never frees itself, and C.03 a scene that
# genuinely leaks. A guard whose failure case you had to hand-pick is a guard
# you have not tested — this project has paid for that lesson at K.15, B.15
# and AM's own vacuous assertion.

const VORTEX_PATH := "res://scenes/battle/anims/vortex.tscn"
const EMBER_PATH := "res://scenes/battle/anims/ember.tscn"

var _pass := 0
var _fail := 0
var _layer: Control


func _ready() -> void:
	_layer = Control.new()
	_layer.size = Vector2(1200, 800)
	add_child(_layer)

	_test_registry()
	await _test_happy_path()
	await _test_guards()
	_test_scene_contract()
	_test_precedence()

	print("authored_anim_test: %d/%d passed" % [_pass, _pass + _fail])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# A real AnimStage over a stub: no battlers, a real layer. `center_of` answers
# Vector2.ZERO for a null sprite by its own design, so an authored scene's
# `setup()` runs without needing a constructed BattlePokemon.
func _stub_stage() -> AnimStage:
	return AnimStage.new(func(_mon): return null, func(): return _layer)


# Packs a scene from a source string, so the two fault cases below are real
# scenes with real behaviour rather than mocks of the runner's own logic.
func _scene_from(source: String) -> PackedScene:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	var root := Node2D.new()
	root.set_script(script)
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


# ── A. The registry ───────────────────────────────────────────────────────

func _test_registry() -> void:
	AuthoredAnims.clear_overrides()

	_chk("A.01 an unregistered move has no authored animation",
			not AuthoredAnims.has(9999))
	_chk("A.01b and resolves to null rather than erroring",
			AuthoredAnims.scene_for(9999) == null)

	AuthoredAnims.set_override(9999, VORTEX_PATH)
	_chk("A.02 an override registers", AuthoredAnims.has(9999))
	_chk("A.02b and resolves to a real PackedScene",
			AuthoredAnims.scene_for(9999) is PackedScene)

	# ⚠️ The fail-closed case. A registered path that does not resolve must
	# answer false, so the move falls through to the ported engine and then to
	# the legacy effect. A typo costs an animation, never a battle.
	AuthoredAnims.set_override(9998, "res://scenes/battle/anims/does_not_exist.tscn")
	_chk("A.03 a registered-but-missing scene fails CLOSED",
			not AuthoredAnims.has(9998))
	_chk("A.03b and resolves to null",
			AuthoredAnims.scene_for(9998) == null)

	AuthoredAnims.clear_overrides()
	_chk("A.04 clearing overrides restores the real registry",
			not AuthoredAnims.has(9999))

	# ⚠️ THIS ASSERTION IS SUPPOSED TO FAIL WHEN SOMEONE BINDS A MOVE. Read
	# `AuthoredAnims`' header before changing it: an authored animation
	# overrides a faithful port, so binding one is a deliberate fidelity call,
	# not a registration. Update this count WITH the decision, never ahead of
	# it.
	_chk("A.05 the registry ships empty by design (%d entries)"
			% AuthoredAnims.SCENES.size(), AuthoredAnims.SCENES.is_empty())
	_chk("A.06 no registered entry points at a missing scene: %s"
			% str(AuthoredAnims.broken_entries()),
			AuthoredAnims.broken_entries().is_empty())


# ── B. The happy path, on the real authored scene ─────────────────────────

func _test_happy_path() -> void:
	var stage := _stub_stage()
	var before := _layer.get_child_count()
	var report: Dictionary = await AuthoredAnimRunner.play(self,
			load(VORTEX_PATH) as PackedScene, stage)

	_chk("B.01 the scene played", bool(report["played"]))
	_chk("B.02 it finished on its own, not by the timeout",
			not bool(report["timed_out"]))
	_chk("B.03 it left nothing on the effect layer",
			not bool(report["leaked"]))
	# Asserted directly as well as via the report: the report is the runner's
	# opinion, the child count is the fact.
	_chk("B.04 the layer is back to its original child count",
			_layer.get_child_count() == before)
	# The scene's own animation is 1.2s. A generous band -- this is a
	# regression guard against "finished instantly" (the scene errored and
	# freed itself) and "ran to the ceiling", not a timing spec.
	var secs := float(report["seconds"])
	_chk("B.05 it ran for a plausible duration (%.2fs)" % secs,
			secs > 0.8 and secs < 3.0)


# ── C. The guards, each driven by a scene that really is broken ───────────

func _test_guards() -> void:
	var restore := AuthoredAnimRunner.TIMEOUT_SECONDS
	AuthoredAnimRunner.TIMEOUT_SECONDS = 0.4

	# A scene that never frees itself. Without the runner's ceiling this hangs
	# the anim beat forever, with the player unable to act.
	var stuck := _scene_from("extends Node2D\nfunc _ready() -> void:\n\tpass\n")
	var before := _layer.get_child_count()
	var r1: Dictionary = await AuthoredAnimRunner.play(self, stuck, _stub_stage())
	_chk("C.01 a scene that never ends is reaped by the timeout",
			bool(r1["timed_out"]))
	# ⚠️ C.02 IS A STATE CHECK, NOT THE DISCRIMINATOR — established by break-
	# testing rather than assumed. Deleting the reap leaves C.02 GREEN, because
	# the leak sweep below then removes the node instead and the layer ends up
	# clean either way. C.05 is the assertion that actually fails, by pinning
	# that a hang is reported as a hang and NOT as a leak. Kept because the
	# end state is still worth asserting; labelled so nobody mistakes it for
	# the guard.
	_chk("C.02 and the layer ends clean (see C.05 for the real discriminator)",
			_layer.get_child_count() == before)

	# A scene that frees itself but leaves a sprite on the layer -- the exact
	# shape of "a Pokemon has a stray flame stuck to it for the rest of the
	# battle", and invisible to any assertion about the scene itself.
	var leaky := _scene_from("""extends Node2D
func _ready() -> void:
	var stray := Node2D.new()
	stray.name = "Stray"
	get_parent().add_child.call_deferred(stray)
	queue_free.call_deferred()
""")
	var r2: Dictionary = await AuthoredAnimRunner.play(self, leaky, _stub_stage())
	_chk("C.03 a scene that leaves nodes behind is reported as leaked",
			bool(r2["leaked"]))
	_chk("C.04 and the runner cleans up after it",
			_layer.get_child_count() == before)
	_chk("C.05 a leak is distinguishable from a hang",
			not bool(r2["timed_out"]) and not bool(r1["leaked"]))

	AuthoredAnimRunner.TIMEOUT_SECONDS = restore
	_chk("C.06 the real timeout is restored, and is generous (%.1fs)"
			% AuthoredAnimRunner.TIMEOUT_SECONDS,
			AuthoredAnimRunner.TIMEOUT_SECONDS >= 5.0)

	# Nothing to play is a real answer, not a crash: this is the path a
	# fail-closed registry entry takes.
	var r3: Dictionary = await AuthoredAnimRunner.play(self, null, _stub_stage())
	_chk("C.07 a null scene declines rather than erroring",
			not bool(r3["played"]))


# ── D. What an authored scene owes the stage ──────────────────────────────

func _test_scene_contract() -> void:
	# ⚠️ Position and scale MUST come from the stage. A scene that keeps its
	# editor transform renders at the wrong size in the wrong place -- and at
	# a plausible-looking size, which is why this is asserted rather than
	# eyeballed.
	_layer.size = Vector2(1200, 800)
	var stage := _stub_stage()
	var v := (load(VORTEX_PATH) as PackedScene).instantiate()
	_chk("D.01 the authored scene exposes setup()", v.has_method("setup"))
	v.call("setup", stage)
	_chk("D.02 it takes its scale from the stage, not the editor (%.2f)"
			% v.scale.x, is_equal_approx(v.scale.x, stage.pixel_scale()))
	_chk("D.03 and its position from the stage",
			v.position == stage.center_of(AnimStage.ANIM_TARGET))
	v.free()

	# The ember is the particle the scene spawns; its own contract is that it
	# plays once and dies, which is what makes the leak rule keepable.
	var e := (load(EMBER_PATH) as PackedScene).instantiate() as AnimatedSprite2D
	var frames: SpriteFrames = e.sprite_frames
	_chk("D.04 the ember carries all five sheet frames",
			frames.get_frame_count(&"default") == 5)
	_chk("D.05 it does NOT loop, so it can end and free itself",
			not frames.get_animation_loop(&"default"))
	_chk("D.06 at the corpus house cadence of 30 FPS",
			is_equal_approx(frames.get_animation_speed(&"default"), 30.0))
	e.free()


# ── E. Precedence: authored -> ported -> legacy ───────────────────────────

func _test_precedence() -> void:
	# A dispatcher with the real behavior registry, so "the engine can play
	# this" is a true statement about the shipped port rather than about an
	# empty registry that declines everything. Same construction
	# `battle_setup_screen` uses, and for the same reason its own comment
	# gives: a bare `AnimDispatcher.new()` answers false for EVERYTHING.
	var reg := AnimBehaviorRegistry.new()
	AnimBehaviors.register_all(reg)
	var disp := AnimDispatcher.new(reg)

	# Flamethrower is ported and playable — the fixture has to be a move the
	# engine really would claim, or "authored wins" proves nothing.
	const FLAMETHROWER := 53
	AuthoredAnims.clear_overrides()
	_chk("E.01 a ported move with no authored scene routes to the engine",
			BattleScreenShared.anim_route_for(FLAMETHROWER, disp)
					== BattleScreenShared.ROUTE_PORTED)

	# ⚠️ THE ONE THAT MATTERS. Registering must beat a faithful port, or
	# registering means nothing — and it is exactly why the registry ships
	# empty and why every entry is a deliberate fidelity call.
	AuthoredAnims.set_override(FLAMETHROWER, VORTEX_PATH)
	_chk("E.02 an authored scene OVERRIDES a move the engine can play",
			BattleScreenShared.anim_route_for(FLAMETHROWER, disp)
					== BattleScreenShared.ROUTE_AUTHORED)

	# Fail-closed, end to end: a typo'd path must not strand the move with no
	# animation at all — it falls straight back to the port.
	AuthoredAnims.set_override(FLAMETHROWER, "res://nope.tscn")
	_chk("E.03 a broken authored entry falls through to the engine",
			BattleScreenShared.anim_route_for(FLAMETHROWER, disp)
					== BattleScreenShared.ROUTE_PORTED)

	AuthoredAnims.clear_overrides()
	# A move id no script exists for: nothing authored, nothing ported.
	_chk("E.04 an unplayable move still reaches the legacy hit-effect",
			BattleScreenShared.anim_route_for(9999, disp)
					== BattleScreenShared.ROUTE_LEGACY)
	_chk("E.05 a null dispatcher degrades to legacy rather than erroring",
			BattleScreenShared.anim_route_for(FLAMETHROWER, null)
					== BattleScreenShared.ROUTE_LEGACY)
