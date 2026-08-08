extends Node

# [M26A1 / 3:2 Phase 3] The letterbox for the three Emerald-UI-Pack screens.
#
# Item/Bag, Switch/Party and Summary are built on 512x384 pack art and laid
# out internally against 1024x768 — exactly 2x, which is why they were
# pixel-perfect at the old 4:3 canvas and why M26A1 chose it. At 1200x800 the
# same art would scale 2.34x horizontally and 2.08x vertically, so they are
# presented at an honest integer 2x with bars instead.
#
# ⚠️ **THIS WHOLE FEATURE IS MEANT TO BE DELETED.** Rob's call: the screens
# get re-authored at 3:2 later, against real FRLG art. So this suite pins the
# things that would make the holding measure WRONG rather than merely
# different — non-integer scale, distortion, and transparent bars over a live
# battle. It deliberately does not pin anything about how the screens look.

const ART := Vector2(512.0, 384.0)
const SCREENS := [
	"res://scenes/battle/item_select_screen.tscn",
	"res://scenes/battle/switch_select_screen.tscn",
	"res://scenes/battle/summary_screen.tscn",
]

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_design_size_is_an_integer_multiple_of_the_art()
	_test_design_size_fits_inside_the_canvas()
	_test_margins_are_the_real_bars()
	# ⚠️ **THESE THREE MUST BE AWAITED, AND THE FIRST DRAFT DID NOT AWAIT
	# THEM.** Each contains `await get_tree().process_frame`, so calling one
	# bare returns at its first await and lets `_ready()` run straight on to
	# the summary — printing a cheerful N/N and calling `quit(0)` while the
	# assertions were still running. Their FAIL lines then appeared AFTER the
	# summary, and the process exited 0.
	#
	# Caught only by injecting a real defect and noticing the failure printed
	# below a passing total. A suite that reports green and exits 0 with real
	# failures in it is the worst shape a suite can have -- `run_overworld_
	# tests.sh` exists because of exactly this class of silent failure.
	await _test_apply_centres_a_fixed_box()
	await _test_expand_covers_the_whole_viewport()
	await _test_apply_works_on_every_real_screen_root()
	_test_every_screen_actually_calls_it()

	var total := _pass + _fail
	print("m26a1_letterbox_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % label)


# ── 1. The scale is a whole number ────────────────────────────────────────
#
# The single claim the whole approach rests on. A non-integer multiple means
# filtering artefacts on pixel art, which is the defect being avoided — not a
# matter of taste.
func _test_design_size_is_an_integer_multiple_of_the_art() -> void:
	var d := UiLetterbox.DESIGN_SIZE
	_chk("the design canvas is exactly 2x the pack art on X",
			is_equal_approx(d.x / ART.x, 2.0))
	_chk("the design canvas is exactly 2x the pack art on Y",
			is_equal_approx(d.y / ART.y, 2.0))
	# ⚠️ UNIFORM matters independently of INTEGER. A 2x-by-3x scale is integer
	# on both axes and still distorts, which is exactly what filling a 3:2
	# viewport with 4:3 art would do.
	_chk("the scale is uniform, so the art is not stretched",
			is_equal_approx(d.x / ART.x, d.y / ART.y))
	_chk("UiLetterbox records the source art size it is derived from",
			UiLetterbox.SOURCE_ART_SIZE.is_equal_approx(ART))


# ── 2. It has to fit ──────────────────────────────────────────────────────
#
# If the design box exceeded the canvas the panel would be cropped rather than
# letterboxed, and `margin()` would go negative — bars pointing the wrong way.
# Cheap to assert, and it is the thing that breaks first if the canvas is ever
# reduced.
func _test_design_size_fits_inside_the_canvas() -> void:
	var v := UiLetterbox.viewport_size()
	var d := UiLetterbox.DESIGN_SIZE
	_chk("the design canvas fits the viewport horizontally", d.x <= v.x)
	_chk("the design canvas fits the viewport vertically", d.y <= v.y)


# ── 3. The bars ───────────────────────────────────────────────────────────
func _test_margins_are_the_real_bars() -> void:
	var m := UiLetterbox.margin()
	# (1200-1024)/2 = 88 and (800-768)/2 = 16.
	_chk("side bars are 88 px at 1200x800", is_equal_approx(m.x, 88.0))
	_chk("top/bottom bars are 16 px at 1200x800", is_equal_approx(m.y, 16.0))


# ── 4-5. The two operations ───────────────────────────────────────────────

func _test_apply_centres_a_fixed_box() -> void:
	var root := Control.new()
	root.size = UiLetterbox.viewport_size()
	add_child(root)
	UiLetterbox.apply(root)
	# A frame is needed for the container maths to settle before reading size.
	await get_tree().process_frame

	_chk("apply() gives the root exactly the design size",
			root.size.is_equal_approx(UiLetterbox.DESIGN_SIZE))
	# Centred, not merely correctly sized — a top-left-pinned box of the right
	# size would satisfy a size-only assertion and put both bars on one side.
	var m := UiLetterbox.margin()
	_chk("apply() centres the box, so the bars are equal on both sides",
			absf(root.position.x - m.x) < 0.5 and absf(root.position.y - m.y) < 0.5)
	root.queue_free()


func _test_expand_covers_the_whole_viewport() -> void:
	var root := Control.new()
	root.size = UiLetterbox.viewport_size()
	add_child(root)
	UiLetterbox.apply(root)
	var bars := ColorRect.new()
	root.add_child(bars)
	UiLetterbox.expand_to_viewport(bars)
	await get_tree().process_frame

	_chk("the bar filler covers the full viewport despite its smaller parent",
			bars.size.is_equal_approx(UiLetterbox.viewport_size()))
	# ⚠️ It must reach the screen's own top-left, not just be the right SIZE.
	# A correctly-sized rect at the wrong origin leaves one bar uncovered and
	# the battle visible through it.
	var m := UiLetterbox.margin()
	_chk("the bar filler starts at the screen's own origin",
			absf(bars.position.x + m.x) < 0.5 and absf(bars.position.y + m.y) < 0.5)
	root.queue_free()


# ── 6. It works on the REAL roots ─────────────────────────────────────────
#
# The helper being correct on a bare `Control` does not prove it survives the
# three real trees, whose roots carry their own authored anchors and presets.
func _test_apply_works_on_every_real_screen_root() -> void:
	for path in SCREENS:
		var scene: PackedScene = load(path as String)
		_chk("%s loads" % (path as String).get_file(), scene != null)
		if scene == null:
			continue
		var root: Control = scene.instantiate() as Control
		_chk("%s root is a Control" % (path as String).get_file(), root != null)
		if root == null:
			continue
		add_child(root)
		UiLetterbox.apply(root)
		await get_tree().process_frame
		_chk("%s letterboxes to the design size" % (path as String).get_file(),
				root.size.is_equal_approx(UiLetterbox.DESIGN_SIZE))
		root.queue_free()


# ── 7. Each screen actually calls it ──────────────────────────────────────
#
# ⚠️ **THIS IS A SOURCE-LEVEL CHECK AND IS WEAKER THAN THE REST — SAID PLAINLY
# RATHER THAN DRESSED UP.** It proves the call SITE exists, not that it runs.
# Driving the real `setup()` would need a live `BattleScreen` parent, a party
# and a mounted `BattleManager`; standing all that up would test the battle
# screen rather than the letterbox.
#
# It is worth having anyway, because the failure it catches is precisely the
# one this phase could ship silently: two screens letterboxed and the third
# left stretched, which nothing else here would notice.
func _test_every_screen_actually_calls_it() -> void:
	for path in SCREENS:
		var gd := (path as String).replace(".tscn", ".gd")
		var f := FileAccess.open(gd, FileAccess.READ)
		_chk("%s is readable" % gd.get_file(), f != null)
		if f == null:
			continue
		var src := f.get_as_text()
		f.close()
		_chk("%s applies the letterbox" % gd.get_file(),
				src.contains("UiLetterbox.apply(self)"))
		_chk("%s fills the letterbox bars opaquely" % gd.get_file(),
				src.contains("UiLetterbox.expand_to_viewport"))
