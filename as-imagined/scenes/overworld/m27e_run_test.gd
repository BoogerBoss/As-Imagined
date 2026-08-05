extends Node

## [M27E E2] Running: the sheet, the gate, the cadence and the cycle.
##
## The claims most worth pinning:
##
##   * the run frames live on a DIFFERENT SHEET from the walk (`green_surf_run`,
##     raw frames 3-13, alongside the surf poses at 0-2), swapped in for the
##     duration of a run rather than composited into a new sheet — Rob's call,
##     and the -6 shift from source's own pic indices is the one place an
##     off-by-six can hide, so it is pinned twice (arithmetic AND pixels);
##   * the speed is EXACTLY double, ported as a ratio because this project's
##     walk is its own tuned duration rather than source's 16 frames;
##   * the run cycle rests on a RUN-specific neutral frame, never the standing
##     pose the walk rests on, and its entries are UNEVEN (5:3);
##   * every gate condition refuses independently, so "runs when it should" is
##     never satisfied by "always runs".

const EXPECTED_TOTAL := 45

var _total := 0
var _failed := 0
var _gated := 0

const SHEET_DIR := "res://assets/sprites/overworld/object_events/"


func _ready() -> void:
	_test_sheet()
	_test_frame_tables()
	_test_disallowed_tiles()
	_test_cycle()
	_test_gate()
	_test_cadence()
	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27e_run_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the run sheet, read directly rather than composited ---
func _test_sheet() -> void:
	# ⚠️ **THE PLAYER'S OWN SHEET IS UNCHANGED, AND THAT IS THE POINT.** An
	# earlier cut of this feature materialised a 20-frame composite of the two
	# files; Rob's call was to read the run sheet where it already sits. If this
	# ever reports 20 again, a composite has come back and the assets churned.
	var walk: Dictionary = ObjectEventGraphics.BY_ID.get("OBJ_EVENT_GFX_GREEN_NORMAL", {})
	_chk("A.01 the player's walk sheet is untouched at its own 9 frames",
			not walk.is_empty() and int(walk.get("frames", 0)) == 9)

	var run_id := "OBJ_EVENT_GFX_GREEN_SURF"
	var path := ObjectEventGraphics.sheet_path(run_id)
	var tex: Texture2D = load(path) as Texture2D if path != "" else null
	_chk("A.02 the run sheet resolves", tex != null)
	if tex == null:
		_gated += 5
		return
	var size := ObjectEventGraphics.frame_size(run_id)
	var raw := int(tex.get_width() / size.x)
	# 14 on disk: 3 surf poses + 11 run frames.
	_chk("A.03 and carries enough RAW frames to run",
			raw >= ObjectEventGraphics.MIN_RAW_FRAMES_TO_RUN)

	var lowest := 99
	var highest := 0
	for k in ["SOUTH", "NORTH", "WEST", "EAST"]:
		var idxs: Array = [int(ObjectEventGraphics.RUN_IDLE_FRAME[k])]
		for f in ObjectEventGraphics.RUN_STEP_FRAME[k]:
			idxs.append(int(f))
		for i in idxs:
			lowest = mini(lowest, i)
			highest = maxi(highest, i)
	_chk("A.04 every run index is inside the sheet", highest < raw)
	# ⚠️ **THE OFF-BY-SIX GUARD.** Raw frames 0-2 are the SURF poses. If the
	# tables ever carried source's own pic indices (9/12/15) unshifted, A.04
	# would catch it; if they were shifted too far, this catches it.
	_chk("A.05 and none of them lands on a surf pose", lowest >= 3)

	# Pixel proof rather than arithmetic: the three neutral poses must be real,
	# distinct art, and none of them may be a surf pose wearing a run label.
	var img := tex.get_image()
	var f3 := _frame_bytes(img, int(ObjectEventGraphics.RUN_IDLE_FRAME["SOUTH"]), size)
	var f6 := _frame_bytes(img, int(ObjectEventGraphics.RUN_IDLE_FRAME["NORTH"]), size)
	var f9 := _frame_bytes(img, int(ObjectEventGraphics.RUN_IDLE_FRAME["WEST"]), size)
	_chk("A.06 the three run neutrals are genuinely different art",
			f3 != f6 and f6 != f9 and f3 != f9)
	var surf0 := _frame_bytes(img, 0, size)
	var surf1 := _frame_bytes(img, 1, size)
	var surf2 := _frame_bytes(img, 2, size)
	_chk("A.07 and none of them is one of the surf poses",
			f3 != surf0 and f3 != surf1 and f3 != surf2
			and f6 != surf0 and f6 != surf1 and f6 != surf2
			and f9 != surf0 and f9 != surf1 and f9 != surf2)


func _frame_bytes(img: Image, idx: int, size: Vector2i) -> PackedByteArray:
	return img.get_region(Rect2i(idx * size.x, 0, size.x, size.y)).get_data()


## --- B. the frame tables ---
func _test_frame_tables() -> void:
	# Straight from sAnim_Run*Frlg. Wrong indices here would draw the surf poses
	# or read past the sheet, and both look like "running is broken".
	_chk("B.01 the run neutral frames are 3/6/9",
			int(ObjectEventGraphics.RUN_IDLE_FRAME["SOUTH"]) == 3
			and int(ObjectEventGraphics.RUN_IDLE_FRAME["NORTH"]) == 6
			and int(ObjectEventGraphics.RUN_IDLE_FRAME["WEST"]) == 9)
	_chk("B.02 the leg pairs are 4/5, 7/8, 10/11",
			ObjectEventGraphics.RUN_STEP_FRAME["SOUTH"] == [4, 5]
			and ObjectEventGraphics.RUN_STEP_FRAME["NORTH"] == [7, 8]
			and ObjectEventGraphics.RUN_STEP_FRAME["WEST"] == [10, 11])
	# ⚠️ EAST IS WEST MIRRORED — the same convention every other anim uses. A
	# fourth set of frames does not exist on the sheet.
	_chk("B.03 EAST reuses WEST's frames, mirrored",
			int(ObjectEventGraphics.RUN_IDLE_FRAME["EAST"])
					== int(ObjectEventGraphics.RUN_IDLE_FRAME["WEST"])
			and ObjectEventGraphics.RUN_STEP_FRAME["EAST"]
					== ObjectEventGraphics.RUN_STEP_FRAME["WEST"])
	# ⚠️ UNEVEN, and that is the point — averaging to 4/4 would keep the cadence
	# and lose the gait.
	_chk("B.04 the entry lengths are source's uneven 5,3,5,3",
			ObjectEventGraphics.RUN_TICKS == [5, 3, 5, 3])
	# ⚠️ THE RUN NEUTRAL IS NOT THE STANDING POSE. A runner never shows the
	# frame the walk cycle rests on; reusing FACE_FRAME here would make the
	# run read as a walk with extra steps.
	var standing_reused := false
	for k in ["SOUTH", "NORTH", "WEST"]:
		if int(ObjectEventGraphics.RUN_IDLE_FRAME[k]) \
				== int(ObjectEventGraphics.FACE_FRAME[k]):
			standing_reused = true
	_chk("B.05 the run neutral is its own frame, not the standing pose",
			not standing_reused)
	# ⚠️ **THE -6 RELATIONSHIP TO SOURCE, PINNED EXPLICITLY.** Source's own
	# sAnim_Run*Frlg quote 9/12/15 because `sPicTable_GreenNormal` stitches 11
	# frames of this file onto the 9-frame walking sheet. This project reads the
	# file directly, so every index is exactly 6 lower. Written as arithmetic
	# against source's real numbers so the shift is a stated fact rather than
	# three constants someone has to trust.
	const PIC_TO_RAW := 6
	_chk("B.06 the raw indices are source's pic indices minus 6",
			int(ObjectEventGraphics.RUN_IDLE_FRAME["SOUTH"]) == 9 - PIC_TO_RAW
			and int(ObjectEventGraphics.RUN_IDLE_FRAME["NORTH"]) == 12 - PIC_TO_RAW
			and int(ObjectEventGraphics.RUN_IDLE_FRAME["WEST"]) == 15 - PIC_TO_RAW
			and ObjectEventGraphics.RUN_STEP_FRAME["SOUTH"]
					== [10 - PIC_TO_RAW, 11 - PIC_TO_RAW])


## --- C. tiles you cannot run on ---
func _test_disallowed_tiles() -> void:
	_chk("C.01 MB_NO_RUNNING stops a run",
			MetatileBehavior.is_running_disallowed(MetatileBehavior.MB_NO_RUNNING))
	# Long grass reads like an oversight and is not — source really does stop you.
	_chk("C.02 and so does long grass",
			MetatileBehavior.is_running_disallowed(MetatileBehavior.MB_LONG_GRASS))
	_chk("C.03 and hot springs",
			MetatileBehavior.is_running_disallowed(MetatileBehavior.MB_HOT_SPRINGS))
	_chk("C.04 and every Pacifidlog log half",
			MetatileBehavior.is_running_disallowed(
					MetatileBehavior.MB_PACIFIDLOG_VERTICAL_LOG_TOP)
			and MetatileBehavior.is_running_disallowed(
					MetatileBehavior.MB_PACIFIDLOG_VERTICAL_LOG_BOTTOM)
			and MetatileBehavior.is_running_disallowed(
					MetatileBehavior.MB_PACIFIDLOG_HORIZONTAL_LOG_LEFT)
			and MetatileBehavior.is_running_disallowed(
					MetatileBehavior.MB_PACIFIDLOG_HORIZONTAL_LOG_RIGHT))
	# ⚠️ THE DISCRIMINATOR. Without an ordinary tile answering false, "stops a
	# run" is indistinguishable from "stops every run".
	_chk("C.05 but an ordinary tile does not",
			not MetatileBehavior.is_running_disallowed(MetatileBehavior.MB_NORMAL))
	# ⚠️ A SEPARATE BEHAVIOUR THAT IS DELIBERATELY NOT LISTED — source stops you
	# on long grass and lets you run on its south edge. Easy to "tidy" into the
	# list and wrong.
	_chk("C.06 and neither does the long-grass SOUTH EDGE, which source omits",
			not MetatileBehavior.is_running_disallowed(
					MetatileBehavior.MB_LONG_GRASS_SOUTH_EDGE))
	# Tall grass is where most running happens; it is not long grass.
	_chk("C.07 nor tall grass",
			not MetatileBehavior.is_running_disallowed(MetatileBehavior.MB_TALL_GRASS))


## --- D. the cycle ---
func _test_cycle() -> void:
	var step := 0.08
	var unit := step / 8.0
	# The four entries land at 0..5, 5..8, 8..13, 13..16 units.
	_chk("D.01 the cycle opens on the run neutral",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 1.0) == 3)
	_chk("D.02 then the first leg",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 6.0) == 4)
	# ⚠️ THE NEUTRAL RETURNS BETWEEN THE LEGS — the cycle is four entries, not
	# two. Alternating the legs alone reads as a shuffle, the same failure the
	# walk cycle already documents.
	_chk("D.03 then the neutral again, not the other leg",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 10.0) == 3)
	_chk("D.04 then the OTHER leg",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 14.0) == 5)
	_chk("D.05 and it loops",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 17.0) == 3)

	# ⚠️ **THE 5:3 SPLIT IS THE ASSERTION, NOT THE FRAME ORDER.** An even 4/4
	# split would pass D.01-D.05 and still be wrong; this is the sample that
	# separates them, sitting inside entry 0 only because it is 5 units long.
	_chk("D.06 the neutral is held LONGER than the leg (5:3, not 4:4)",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 4.5) == 3
			and WalkAnim.run_cycle_frame("SOUTH", step, unit * 7.5) == 4)

	# ⚠️ SCALED, NOT FIXED. The same phase of the cycle must be reached at the
	# same FRACTION of the step whatever the step's own duration is — the whole
	# reason the run is timed in seconds rather than integer ticks.
	var slow := 0.32
	_chk("D.07 the cycle scales with the step duration",
			WalkAnim.run_cycle_frame("SOUTH", slow, (slow / 8.0) * 6.0) == 4)

	_chk("D.08 each facing runs its own frames",
			WalkAnim.run_cycle_frame("NORTH", step, unit * 6.0) == 7
			and WalkAnim.run_cycle_frame("WEST", step, unit * 6.0) == 10)
	# EAST shares WEST's indices; the mirroring is the renderer's flip_h, so the
	# frame number itself must match rather than differ.
	_chk("D.09 EAST draws WEST's frame (the flip is the renderer's job)",
			WalkAnim.run_cycle_frame("EAST", step, unit * 6.0) == 10)
	# Defensive: a zero/negative duration must not divide by zero.
	_chk("D.10 a zero-length step degrades rather than dividing by zero",
			WalkAnim.run_cycle_frame("SOUTH", 0.0, 0.0) == 3)

	# The walk cycle must be untouched by any of this.
	_chk("D.11 the WALK cycle still rests on the standing frame",
			WalkAnim.cycle_frame("SOUTH", 8, (1.0 / 60.0) * 8.0 * 1.5)
					== int(ObjectEventGraphics.FACE_FRAME["SOUTH"]))


## --- E. the gate ---
func _test_gate() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# Deliberately NOT added to the tree — _ready() would boot the whole region.
	OverworldSession.reset()
	OverworldSession.flags.flag_set(ow.RUN_FLAG)
	ow._player_anim.setup("OBJ_EVENT_GFX_GREEN_NORMAL")

	var normal := MetatileBehavior.MB_NORMAL
	var none := StepResolver.Outcome.NONE
	_chk("E.01 with the flag, the key held and an ordinary tile, the player runs",
			ow._can_run_with(normal, none, true))
	# ⚠️ EACH CONDITION MUST REFUSE ON ITS OWN, or E.01 is satisfied by a
	# function that ignores its arguments.
	_chk("E.02 releasing the key stops the run",
			not ow._can_run_with(normal, none, false))
	_chk("E.03 a disallowed tile stops the run",
			not ow._can_run_with(MetatileBehavior.MB_NO_RUNNING, none, true))
	_chk("E.04 a ledge hop is never a run",
			not ow._can_run_with(normal, StepResolver.Outcome.LEDGE_JUMP, true))

	OverworldSession.surfing = true
	_chk("E.05 and surfing is never a run",
			not ow._can_run_with(normal, none, true))
	OverworldSession.surfing = false

	OverworldSession.flags.flag_clear(ow.RUN_FLAG)
	_chk("E.06 without the Running Shoes flag, holding the key does nothing",
			not ow._can_run_with(normal, none, true))
	OverworldSession.flags.flag_set(ow.RUN_FLAG)
	_chk("E.07 and setting it again restores the run",
			ow._can_run_with(normal, none, true))

	# ⚠️ **THE PLAYER MUST NOT BE THE CAMEO SPRITE.** This shipped pointing at
	# `OBJ_EVENT_GFX_LEAF`, a different character — and because the run frames
	# are SWAPPED IN from `green_surf_run.png`, that would make the player
	# visibly change design every time they held Shift. Pinned because it is a
	# one-word change with a very visible consequence.
	_chk("E.08 the player walks as the same character the run sheet draws",
			ow.PLAYER_GRAPHICS_ID == "OBJ_EVENT_GFX_GREEN_NORMAL"
			and ow.PLAYER_RUN_SHEET_ID == "OBJ_EVENT_GFX_GREEN_SURF")
	# ⚠️ THE RUN SHEET IS THE LAST GATE, and it is asserted HERE rather than
	# through `_can_run_with` — that function re-binds the real ids every call,
	# so a stubbed sheet cannot survive into it. Tested on WalkAnim directly,
	# which is the exact object the gate consults. A walker with NO run sheet
	# bound is every NPC in the game.
	var npc_anim := WalkAnim.new()
	npc_anim.setup("OBJ_EVENT_GFX_NINJA_BOY")
	var player_anim := WalkAnim.new()
	player_anim.setup(ow.PLAYER_GRAPHICS_ID)
	player_anim.setup_run(ow.PLAYER_RUN_SHEET_ID)
	_chk("E.09 a walker with no run sheet bound refuses, one with it allows",
			not npc_anim.can_run() and player_anim.can_run())

	OverworldSession.reset()
	ow.free()


## --- F. the cadence ---
func _test_cadence() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# ⚠️ EXACTLY DOUBLE. Source's run step table is 8 entries against the walk's
	# 16; the absolute durations are this project's own, the RATIO is ported.
	_chk("F.01 a run step is exactly half a walk step",
			is_equal_approx(ow._RUN_STEP_SECONDS * 2.0, ow._WALK_STEP_SECONDS))
	_chk("F.02 and the walk step is unchanged at 0.16",
			is_equal_approx(ow._WALK_STEP_SECONDS, 0.16))
	# The run's own cycle keeps the walk's invariant: two entries per tile.
	# 5 + 3 == 8 == one step, so the pair spans exactly one tile.
	var t: Array = ObjectEventGraphics.RUN_TICKS
	_chk("F.03 two cycle entries span exactly one tile, as the walk's do",
			int(t[0]) + int(t[1]) == int(t[2]) + int(t[3])
			and int(t[0]) + int(t[1]) + int(t[2]) + int(t[3]) == 16)
	_chk("F.04 the run flag is source's own Running Shoes flag",
			ow.RUN_FLAG == "FLAG_SYS_B_DASH")
	ow.free()

	# The debug boot must actually grant it, or running is unreachable in play:
	# no in-game event sets this flag yet.
	var packed := load("res://scenes/overworld/overworld.tscn") as PackedScene
	var boot: Node2D = packed.instantiate() as Node2D
	var granted := false
	for f in boot.debug_flags:
		if String(f) == boot.RUN_FLAG:
			granted = true
	_chk("F.05 and the debug boot grants it, since nothing in play does yet",
			granted)
	boot.free()


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)
