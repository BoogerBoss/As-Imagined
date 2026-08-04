extends Node

## [M27E E2] Running: the sheet, the gate, the cadence and the cycle.
##
## The claims most worth pinning:
##
##   * the RUN FRAMES DID NOT EXIST until the generator learned to composite a
##     pic table that spans several pic files — indices 9-17 come out of the
##     *surf_run* sheet, not the walking one, and the composite is an ORDER
##     rather than a concatenation (it starts at that file's frame 3);
##   * the speed is EXACTLY double, ported as a ratio because this project's
##     walk is its own tuned duration rather than source's 16 frames;
##   * the run cycle rests on a RUN-specific neutral frame, never the standing
##     pose the walk rests on, and its entries are UNEVEN (5:3);
##   * every gate condition refuses independently, so "runs when it should" is
##     never satisfied by "always runs".

const EXPECTED_TOTAL := 44

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


## --- A. the composited sheet ---
func _test_sheet() -> void:
	var e: Dictionary = ObjectEventGraphics.BY_ID.get("OBJ_EVENT_GFX_GREEN_NORMAL", {})
	_chk("A.01 the player's id resolves", not e.is_empty())
	if e.is_empty():
		_gated += 5
		return
	# ⚠️ 20, NOT 9. sPicTable_GreenNormal is 9 walking frames followed by 11 run
	# frames living in a DIFFERENT file; before the composite this id reported
	# its walking sheet's own 9 and the run frames were unreachable.
	_chk("A.02 it carries all 20 pic-table frames, not just the walking sheet's 9",
			int(e.get("frames", 0)) == 20)
	_chk("A.03 which is enough to run", int(e.get("frames", 0))
			>= ObjectEventGraphics.MIN_FRAMES_TO_RUN)

	var tex: Texture2D = load(SHEET_DIR + str(e.get("sheet", "")) + ".png") as Texture2D
	_chk("A.04 and the sheet on disk loads", tex != null)
	if tex == null:
		_gated += 2
		return
	# The sheet must be as wide as the table is long, or the run frames would
	# index off the end and silently draw nothing.
	_chk("A.05 the sheet is 20 frames wide on disk",
			tex.get_width() == int(e.get("w", 16)) * 20
			and tex.get_height() == int(e.get("h", 32)))

	# ⚠️ AN NPC MUST NOT BE ABLE TO RUN. Every other id stops at 9 frames, so the
	# `can_run` gate is a property of the sheet rather than a rule to remember.
	var npc: Dictionary = ObjectEventGraphics.BY_ID.get("OBJ_EVENT_GFX_NINJA_BOY", {})
	_chk("A.06 an ordinary NPC sheet has no run frames",
			not npc.is_empty()
			and int(npc.get("frames", 0)) < ObjectEventGraphics.MIN_FRAMES_TO_RUN)


## --- B. the frame tables ---
func _test_frame_tables() -> void:
	# Straight from sAnim_Run*Frlg. Wrong indices here would draw the surf poses
	# or read past the sheet, and both look like "running is broken".
	_chk("B.01 the run neutral frames are 9/12/15",
			int(ObjectEventGraphics.RUN_IDLE_FRAME["SOUTH"]) == 9
			and int(ObjectEventGraphics.RUN_IDLE_FRAME["NORTH"]) == 12
			and int(ObjectEventGraphics.RUN_IDLE_FRAME["WEST"]) == 15)
	_chk("B.02 the leg pairs are 10/11, 13/14, 16/17",
			ObjectEventGraphics.RUN_STEP_FRAME["SOUTH"] == [10, 11]
			and ObjectEventGraphics.RUN_STEP_FRAME["NORTH"] == [13, 14]
			and ObjectEventGraphics.RUN_STEP_FRAME["WEST"] == [16, 17])
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
	# Every index the run tables name must exist on the player's sheet.
	var frames: int = int(ObjectEventGraphics.BY_ID
			.get("OBJ_EVENT_GFX_GREEN_NORMAL", {}).get("frames", 0))
	var highest := 0
	for k in ["SOUTH", "NORTH", "WEST", "EAST"]:
		highest = maxi(highest, int(ObjectEventGraphics.RUN_IDLE_FRAME[k]))
		for f in ObjectEventGraphics.RUN_STEP_FRAME[k]:
			highest = maxi(highest, int(f))
	_chk("B.06 every run frame index is inside the player's sheet",
			highest < frames)


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
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 1.0) == 9)
	_chk("D.02 then the first leg",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 6.0) == 10)
	# ⚠️ THE NEUTRAL RETURNS BETWEEN THE LEGS — the cycle is four entries, not
	# two. Alternating the legs alone reads as a shuffle, the same failure the
	# walk cycle already documents.
	_chk("D.03 then the neutral again, not the other leg",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 10.0) == 9)
	_chk("D.04 then the OTHER leg",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 14.0) == 11)
	_chk("D.05 and it loops",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 17.0) == 9)

	# ⚠️ **THE 5:3 SPLIT IS THE ASSERTION, NOT THE FRAME ORDER.** An even 4/4
	# split would pass D.01-D.05 and still be wrong; this is the sample that
	# separates them, sitting inside entry 0 only because it is 5 units long.
	_chk("D.06 the neutral is held LONGER than the leg (5:3, not 4:4)",
			WalkAnim.run_cycle_frame("SOUTH", step, unit * 4.5) == 9
			and WalkAnim.run_cycle_frame("SOUTH", step, unit * 7.5) == 10)

	# ⚠️ SCALED, NOT FIXED. The same phase of the cycle must be reached at the
	# same FRACTION of the step whatever the step's own duration is — the whole
	# reason the run is timed in seconds rather than integer ticks.
	var slow := 0.32
	_chk("D.07 the cycle scales with the step duration",
			WalkAnim.run_cycle_frame("SOUTH", slow, (slow / 8.0) * 6.0) == 10)

	_chk("D.08 each facing runs its own frames",
			WalkAnim.run_cycle_frame("NORTH", step, unit * 6.0) == 13
			and WalkAnim.run_cycle_frame("WEST", step, unit * 6.0) == 16)
	# EAST shares WEST's indices; the mirroring is the renderer's flip_h, so the
	# frame number itself must match rather than differ.
	_chk("D.09 EAST draws WEST's frame (the flip is the renderer's job)",
			WalkAnim.run_cycle_frame("EAST", step, unit * 6.0) == 16)
	# Defensive: a zero/negative duration must not divide by zero.
	_chk("D.10 a zero-length step degrades rather than dividing by zero",
			WalkAnim.run_cycle_frame("SOUTH", 0.0, 0.0) == 9)

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

	# ⚠️ **THE PLAYER'S OWN ID MUST BE THE RUN-CAPABLE ONE, AND IT WAS NOT.**
	# This shipped pointing at `OBJ_EVENT_GFX_LEAF`, a standalone cameo sprite
	# with 9 frames and no run art anywhere in source — so every other gate
	# below could pass and running would still be impossible. Pinned because it
	# is a one-word change that silently disables the whole feature.
	_chk("E.08 the player's graphics id is one that can actually run",
			int(ObjectEventGraphics.BY_ID.get(ow.PLAYER_GRAPHICS_ID, {})
					.get("frames", 0)) >= ObjectEventGraphics.MIN_FRAMES_TO_RUN)
	# ⚠️ THE SHEET IS THE LAST GATE, and it is asserted HERE rather than through
	# `_can_run_with` — that function re-resolves the real player id every call,
	# so a stubbed NPC sheet cannot survive into it. Tested on WalkAnim directly,
	# which is the exact object the gate consults.
	var npc_anim := WalkAnim.new()
	npc_anim.setup("OBJ_EVENT_GFX_NINJA_BOY")
	var player_anim := WalkAnim.new()
	player_anim.setup(ow.PLAYER_GRAPHICS_ID)
	_chk("E.09 and a sheet without run frames refuses while the player's allows",
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
