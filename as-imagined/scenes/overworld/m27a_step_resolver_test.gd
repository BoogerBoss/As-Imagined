extends Node

## [M27A] Step resolver + imported map data.
##
## Deterministic and resolver-level per docs/overworld_scope.md §22: assert on
## landed steps, never on frames, and never wait on a tween — the logic
## position is the truth and the tween is presentation.
##
## Pallet Town carries no directional-block or ledge behaviours (measured:
## those are 0.77% of Kanto and none of them here), so those cases use
## synthetic MapData rather than pretending the real map exercises them.

const MAP_JSON := "res://assets/maps/PalletTown_Frlg.json"

var _passed := 0
var _total := 0
var _gated := 0

## [Step 5 follow-up] Section A asserts against the IMPORTED map JSON, which is
## a generated build input and gitignored by design (docs/overworld_scope.md
## §1.9's generated-vs-tracked split). A fresh clone therefore has none of the
## 421 files, and section A cannot run.
##
## It used to fail: A.01 loaded null and reported FAILED, then early-returned,
## silently taking A.02-A.08 with it -- a clean checkout read 62/63, which
## trains people to treat this suite's red as normal. Gated explicitly instead,
## so a fresh clone reads a clean 62/62 and says why the total is smaller.
const MAP_DATA_ASSERTIONS := 8

## [Rider 1] The suite asserts its own arithmetic, retiring a whole failure
## family rather than another instance of it.
##
## Three separate times, an assertion VANISHED instead of failing, and each time
## the suite still looked green with a quietly smaller total: the fresh-checkout
## 62/63 early-return, a parse error that made Godot hang with no result at all,
## and J.17 crash-aborting its own function on a broken read-back (87/87 ->
## 86/86, nothing named). A pass count is only trustworthy alongside the count
## that was SUPPOSED to run.
##
## `_gated` is added back in so fresh-checkout mode balances too — a clean clone
## runs fewer assertions but must still account for all of them.
##
## Update this when adding or removing assertions. If it drifts, that is the
## point: a number nobody maintains is a number nobody trusts.
## MEASURED-CONSTANT RULE: this number, and every per-section constant below,
## comes from a REAL RUN -- never from grepping `_chk(` call sites. Those two
## disagree, and they disagreed here: `_test_object_events` has 26 call sites
## and runs 25, because I.18 is a fail-fast pair where exactly one of the two
## ever executes. A branch, a loop, or an early return breaks static counting,
## and a constant derived the wrong way makes Z.99 fail for a reason that has
## nothing to do with the code under test -- which is worse than no check,
## because it trains you to adjust the number until it goes green.
##
## To re-measure after adding assertions: temporarily print `_total` around
## each section call in `_ready()` and read the deltas.
const EXPECTED_TOTAL := 294

## K.01-K.07 read the imported JSON, so they gate with section A.
const CELL_INFO_MAP_ASSERTIONS := 7

## M.01-M.09 read the baked corridor scenes, which a fresh checkout has not
## produced yet. Gated the same way section A gates on the imported JSON.
const BAKED_SCENE_ASSERTIONS := 9

## N.01-N.08, same gate: one per baked corridor map.
const OVERLAY_ASSERTIONS := 8

## Sections H/I/J read BAKED SCENES, which a fresh checkout has not produced.
## They used to assert existence and then bare-`return`, so on a fresh tree they
## reported four hard FAILURES and silently dropped ~50 assertions from Z.99's
## accounting — the balance check cannot catch what it is never told about.
## Gated properly now: on a fresh tree they contribute nothing and credit their
## full count instead.
const BAKED_ARTIFACT_ASSERTIONS := 13
## 25, not the 26 `_chk(` call sites you can grep for: I.18 is written as a
## fail-fast pair (one call site inside the loop, one after it) and exactly one
## of the two ever runs. A static grep is the wrong instrument here — this
## number was measured from a real run.
const OBJECT_EVENT_ASSERTIONS := 25
const ROUND_TRIP_ASSERTIONS := 16

## S.11-S.25 read placed entities out of the baked corridor. S.01-S.10 do NOT
## gate: the MAP_* table is generated but committed, like metatile_behavior.gd,
## so a fresh clone can still assert the lookup it depends on.
const EVENTS_MODE_ASSERTIONS := 15

## U.01-U.04 read a placed entity out of the baked corridor. Section T is fully
## synthetic and does NOT gate — sight-line maths needs no baked map.
const ENTITY_AT_ASSERTIONS := 4

## V.01-V.13 use the REAL corridor overlaps as fixtures (Viridian City's Gym
## door, Route 22's three trigger pairs), so they gate with the baked scenes.
## V.14 is synthetic and would run either way; it is inside the gate only
## because splitting one section across two counters is worse than a slightly
## conservative number. Section W is fully synthetic and does NOT gate.
const STACK_ASSERTIONS := 14

## The eight maps chosen for the M27B render/bake subset.
const CORRIDOR_MAPS := [
	"PalletTown_Frlg", "PewterCity_Frlg", "Route1_Frlg", "Route22_Frlg",
	"Route2_Frlg", "Route3_Frlg", "ViridianCity_Frlg", "ViridianForest_Frlg",
]


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if cond:
		_passed += 1
	else:
		print("FAILED: %s" % label)


## Synthetic map: `beh` is a width*height behaviour grid, everything else
## defaults to open ground at ELEVATION_DEFAULT unless overridden.
func _synth(w: int, h: int, beh: Array, coll: Array = [], elev: Array = []) -> MapData:
	var m := MapData.new()
	m.map_name = "synthetic"
	m.width = w
	m.height = h
	for i in range(w * h):
		m.metatile.append(0)
		m.behavior.append(int(beh[i]) if i < beh.size() else 0)
		m.collision.append(int(coll[i]) if i < coll.size() else 0)
		m.elevation.append(int(elev[i]) if i < elev.size() else 3)
		m.layer_type.append(0)
		# Provenance must be FULL LENGTH, like real imported data. It was left
		# empty, and R.06 read index 0 of an empty PackedByteArray: GDScript
		# logged an error and returned 0, which happens to equal
		# Provenance.IMPORTED -- so the assertion passed for entirely the wrong
		# reason. Found by the ERROR-lines-are-failures guard, not by the
		# assertion count, which is exactly the case that guard exists for.
		#
		# attr_explicit is deliberately left empty: _flags_at() treats a short
		# array as "no flags", which is the correct starting point for a
		# fixture whose cells have not been decided yet.
		m.provenance.append(MapData.Provenance.IMPORTED)
	return m


func _ready() -> void:
	_test_import_integrity()
	_test_bounds()
	_test_collision()
	_test_elevation()
	_test_directional_two_sided()
	_test_ledges()
	_test_debug_toggle()
	_test_baked_artifacts()
	_test_object_events()
	_test_marks_survive_round_trip()
	_test_importer_stamps_explicit()
	_test_cell_info_against_a_real_map()
	_test_cell_info_synthetic_edges()
	_test_tool_chain()
	_test_baked_scene_uids()
	_test_overlay_never_baked()
	_test_events_mode_table()
	_test_events_mode_entities()
	_test_trainer_sight()
	_test_entity_at()
	_test_stacks_and_counts()
	_test_bake_guard()
	_test_gesture_lifecycle()
	_test_clip_math()
	_test_write_half()
	_test_author_save_reload()
	_test_undo_symmetry()

	# Counted BEFORE Z.99 itself, so EXPECTED_TOTAL stays the count of real
	# assertions rather than including this bookkeeping one.
	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL],
			accounted == EXPECTED_TOTAL)

	if _gated > 0:
		print("m27a_step_resolver_test: fresh-checkout mode — %d map-data "
				% _gated
				+ "assertions gated (run `python3 scripts/gen_map_import.py all` "
				+ "to enable)")
	print("m27a_step_resolver_test: %d/%d passed" % [_passed, _total])
	# Unconditional. This used to be gated on
	# `OS.has_feature("headless") or "--autoplay" in ...`, and the headless half
	# is simply FALSE in 4.7 -- so the quit only ever fired via the flag, and an
	# invocation without it printed every result and then sat there forever.
	# That is the silent-hang family: a run that finished its work and looks
	# like a deadlock. A test scene has nothing to do after reporting, so it
	# exits, and no flag can change that.
	get_tree().quit()


# --- A. the imported artifact itself ---------------------------------------
func _map_data_available() -> bool:
	return FileAccess.file_exists(MAP_JSON)


func _test_import_integrity() -> void:
	if not _map_data_available():
		_gated += MAP_DATA_ASSERTIONS
		return
	var m := MapData.load_from(MAP_JSON)
	_chk("A.01 map loads", m != null)
	if m == null:
		return
	_chk("A.02 dimensions are Pallet Town's", m.width == 24 and m.height == 20)
	_chk("A.03 cell count == w*h", m.metatile.size() == 480)
	_chk("A.04 all five arrays are full length",
			m.collision.size() == 480 and m.elevation.size() == 480
			and m.behavior.size() == 480 and m.layer_type.size() == 480)

	# §1.4 / §1.7 — only measured values may appear. A new value means either
	# an authored map or a reference update, and must fail loudly.
	var bad_e := 0
	var bad_c := 0
	for i in range(480):
		if not (m.elevation[i] in [0, 1, 3, 4, 5, 15]):
			bad_e += 1
		if not (m.collision[i] in [0, 1]):
			bad_c += 1
	_chk("A.05 no unexpected elevation values", bad_e == 0)
	_chk("A.06 no unexpected collision values", bad_c == 0)

	# Matches the independent Python measurement exactly (§1.4's table).
	var e0 := 0
	var e1 := 0
	var e3 := 0
	for i in range(480):
		match m.elevation[i]:
			0: e0 += 1
			1: e1 += 1
			3: e3 += 1
	_chk("A.07 elevation histogram matches the measured 198/12/270",
			e0 == 198 and e1 == 12 and e3 == 270)
	_chk("A.08 out-of-bounds reads are safe", m.metatile_at(-1, 0) == -1
			and m.collision_at(999, 0) == 1)


# --- B. bounds --------------------------------------------------------------
func _test_bounds() -> void:
	var m := _synth(3, 3, [])
	var r := StepResolver.new(m)
	_chk("B.01 stepping off the north edge is OUTSIDE_RANGE",
			r.resolve(Vector2i(1, 0), StepResolver.Dir.NORTH, 3)["outcome"]
			== StepResolver.Outcome.OUTSIDE_RANGE)
	_chk("B.02 a step inside the map is allowed",
			r.resolve(Vector2i(1, 1), StepResolver.Dir.NORTH, 3)["outcome"]
			== StepResolver.Outcome.NONE)
	_chk("B.03 allowed step reports the target cell",
			r.resolve(Vector2i(1, 1), StepResolver.Dir.SOUTH, 3)["to"] == Vector2i(1, 2))
	_chk("B.04 denied step reports the ORIGIN, not the target",
			r.resolve(Vector2i(1, 0), StepResolver.Dir.NORTH, 3)["to"] == Vector2i(1, 0))


# --- C. collision bits ------------------------------------------------------
func _test_collision() -> void:
	var coll := [0, 0, 0, 0, 1, 0, 0, 0, 0]  # centre blocked
	var m := _synth(3, 3, [], coll)
	var r := StepResolver.new(m)
	_chk("C.01 stepping into a blocked cell is IMPASSABLE",
			r.resolve(Vector2i(1, 2), StepResolver.Dir.NORTH, 3)["outcome"]
			== StepResolver.Outcome.IMPASSABLE)
	_chk("C.02 stepping around it is allowed",
			r.resolve(Vector2i(0, 2), StepResolver.Dir.NORTH, 3)["outcome"]
			== StepResolver.Outcome.NONE)


# --- D. elevation -----------------------------------------------------------
func _test_elevation() -> void:
	# target at elevation 4, walker at 3 -> mismatch
	var elev := [3, 3, 3, 3, 4, 3, 3, 3, 3]
	var m := _synth(3, 3, [], [], elev)
	var r := StepResolver.new(m)
	_chk("D.01 differing elevations block the step",
			r.resolve(Vector2i(1, 2), StepResolver.Dir.NORTH, 3)["outcome"]
			== StepResolver.Outcome.ELEVATION_MISMATCH)
	_chk("D.02 a walker already at 4 may enter",
			r.resolve(Vector2i(1, 2), StepResolver.Dir.NORTH, 4)["outcome"]
			== StepResolver.Outcome.NONE)

	# §1.4 wildcards — 0 is 56% of Kanto and means "unconstrained", not "stairs"
	var elev0 := [3, 3, 3, 3, 0, 3, 3, 3, 3]
	var r0 := StepResolver.new(_synth(3, 3, [], [], elev0))
	_chk("D.03 target elevation 0 (TRANSITION) is a wildcard",
			r0.resolve(Vector2i(1, 2), StepResolver.Dir.NORTH, 4)["outcome"]
			== StepResolver.Outcome.NONE)
	var elev15 := [3, 3, 3, 3, 15, 3, 3, 3, 3]
	var r15 := StepResolver.new(_synth(3, 3, [], [], elev15))
	_chk("D.04 target elevation 15 (MULTI_LEVEL) is a wildcard",
			r15.resolve(Vector2i(1, 2), StepResolver.Dir.NORTH, 4)["outcome"]
			== StepResolver.Outcome.NONE)
	_chk("D.05 a walker AT elevation 0 may enter anything",
			r.resolve(Vector2i(1, 2), StepResolver.Dir.NORTH, 0)["outcome"]
			== StepResolver.Outcome.NONE)

	# ordering: solidity is checked before elevation, so a cell that is both
	# blocked and mismatched reports IMPASSABLE (§1.7).
	var m2 := _synth(3, 3, [], [0, 0, 0, 0, 1, 0, 0, 0, 0], elev)
	_chk("D.06 solidity outranks elevation in the outcome ordering",
			StepResolver.new(m2).resolve(Vector2i(1, 2), StepResolver.Dir.NORTH, 3)["outcome"]
			== StepResolver.Outcome.IMPASSABLE)


# --- E. directional, both sides --------------------------------------------
func _test_directional_two_sided() -> void:
	var N := MetatileBehavior.MB_IMPASSABLE_NORTH
	var S := MetatileBehavior.MB_IMPASSABLE_SOUTH

	# ENTRY rule: target is north-blocked, so it cannot be entered from its
	# north side — i.e. walking SOUTH into it.
	var entry := _synth(3, 3, [0, 0, 0, 0, N, 0, 0, 0, 0])
	var re := StepResolver.new(entry)
	_chk("E.01 entry rule blocks walking south into a north-blocked tile",
			re.resolve(Vector2i(1, 0), StepResolver.Dir.SOUTH, 3)["outcome"]
			== StepResolver.Outcome.IMPASSABLE)
	_chk("E.02 the same tile is enterable from the south",
			re.resolve(Vector2i(1, 2), StepResolver.Dir.NORTH, 3)["outcome"]
			== StepResolver.Outcome.NONE)

	# EXIT rule: standing ON a south-blocked tile, you cannot leave southward.
	# This is the half that is easy to omit and looks fine nearly everywhere.
	var exit_map := _synth(3, 3, [0, 0, 0, 0, S, 0, 0, 0, 0])
	var rx := StepResolver.new(exit_map)
	_chk("E.03 exit rule blocks leaving a south-blocked tile southward",
			rx.resolve(Vector2i(1, 1), StepResolver.Dir.SOUTH, 3)["outcome"]
			== StepResolver.Outcome.IMPASSABLE)
	_chk("E.04 leaving that tile northward is fine",
			rx.resolve(Vector2i(1, 1), StepResolver.Dir.NORTH, 3)["outcome"]
			== StepResolver.Outcome.NONE)
	_chk("E.05 plain tiles are unaffected in every direction",
			StepResolver.new(_synth(3, 3, [])).resolve(
					Vector2i(1, 1), StepResolver.Dir.EAST, 3)["outcome"]
			== StepResolver.Outcome.NONE)


# --- F. ledges are a redirect, not a block ---------------------------------
func _test_ledges() -> void:
	var J := MetatileBehavior.MB_JUMP_SOUTH
	# column of 4: walker at (0,0), ledge at (0,1), landing at (0,2)
	var m := _synth(1, 4, [0, J, 0, 0])
	var r := StepResolver.new(m)

	var jump: Dictionary = r.resolve(Vector2i(0, 0), StepResolver.Dir.SOUTH, 3)
	_chk("F.01 walking into a south ledge is LEDGE_JUMP",
			jump["outcome"] == StepResolver.Outcome.LEDGE_JUMP)
	_chk("F.02 the hop lands TWO cells away, not one",
			jump["to"] == Vector2i(0, 2))

	_chk("F.03 the same ledge cannot be climbed from below",
			r.resolve(Vector2i(0, 2), StepResolver.Dir.NORTH, 3)["outcome"]
			!= StepResolver.Outcome.LEDGE_JUMP)

	# a ledge at the map edge has nowhere to land
	var edge := StepResolver.new(_synth(1, 2, [0, J]))
	_chk("F.04 a ledge with no landing cell is impassable",
			edge.resolve(Vector2i(0, 0), StepResolver.Dir.SOUTH, 3)["outcome"]
			== StepResolver.Outcome.IMPASSABLE)

	# a solid ledge tile must still jump — ledge is checked before collision
	var solid := _synth(1, 4, [0, J, 0, 0], [0, 1, 0, 0])
	_chk("F.05 a ledge is jumpable even though its cell is solid",
			StepResolver.new(solid).resolve(
					Vector2i(0, 0), StepResolver.Dir.SOUTH, 3)["outcome"]
			== StepResolver.Outcome.LEDGE_JUMP)


# --- H. baked artifacts, provenance and draw priority (M27B Change 1) -------
func _test_baked_artifacts() -> void:
	const SCENE := "res://scenes/maps/PalletTown_Frlg.tscn"
	const DATA := "res://scenes/maps/PalletTown_Frlg_data.tres"
	# [Rider C] Gates on BOTH artifacts, not just the .tres. It gated on the
	# .tres while asserting on the .tscn, so a partially-baked tree — data
	# written, bake interrupted before the scene — hard-failed H.01 instead of
	# gating, and then bare-returned, taking the rest of the section with it.
	# That is the misleading-red family this file's own header describes: a red
	# that means "you have not baked yet" trains people to ignore reds that
	# mean something.
	if not ResourceLoader.exists(DATA) or not ResourceLoader.exists(SCENE):
		_gated += BAKED_ARTIFACT_ASSERTIONS
		return
	_chk("H.01 baked scene exists", ResourceLoader.exists(SCENE))
	_chk("H.02 baked MapData resource exists", ResourceLoader.exists(DATA))

	var d: MapData = load(DATA)
	_chk("H.03 baked data is a MapData", d != null)
	if d == null:
		return
	_chk("H.04 baked data matches the imported map", d.width == 24 and d.height == 20)

	# The bug this caught on first run: provenance was declared and written to
	# JSON but never read back, so it persisted empty and the re-import guard
	# could never fire.
	_chk("H.05 provenance is populated, one entry per cell",
			d.provenance.size() == d.metatile.size() and d.provenance.size() == 480)

	# priority comes from source's own sElevationToPriority — 4 -> 1 (above the
	# overhang plane) but 5 -> 2, back to ground level.
	_chk("H.06 elevation 3 is draw priority 2",
			MetatileBehavior.ELEVATION_TO_PRIORITY[3] == 2)
	_chk("H.07 elevation 4 is draw priority 1 (above overhangs)",
			MetatileBehavior.ELEVATION_TO_PRIORITY[4] == 1)
	_chk("H.08 elevation 5 returns to priority 2, NOT 1",
			MetatileBehavior.ELEVATION_TO_PRIORITY[5] == 2)
	_chk("H.09 the table covers all 16 elevations",
			MetatileBehavior.ELEVATION_TO_PRIORITY.size() == 16)

	# has_authored_cells drives the re-import refusal
	var synth := _synth(2, 1, [])
	synth.provenance = PackedByteArray([MapData.Provenance.IMPORTED,
			MapData.Provenance.IMPORTED])
	_chk("H.10 all-imported map reports no authored cells",
			not synth.has_authored_cells())
	synth.provenance[1] = MapData.Provenance.AUTHORED
	_chk("H.11 one authored cell is detected", synth.has_authored_cells())

	# the baked scene carries both entity strata in the right order
	var root: Node2D = (load(SCENE) as PackedScene).instantiate()
	var names: Array = []
	for c in root.get_children():
		names.append(str(c.name))
	# The first five are the DRAW order and their sequence is load-bearing:
	# priority-2 entities must sit below the overhang plane and priority-1 above
	# it. Triggers is appended last and deliberately outside that sequence — it
	# holds warps/coord-events/signs, which are never drawn.
	_chk("H.12 draw order is Ground/Objects/Entities_P2/Overhangs/Entities_P1",
			names.slice(0, 5)
			== ["Ground", "Objects", "Entities_P2", "Overhangs", "Entities_P1"])
	# Asserts the baker's OWN six containers and their order -- deliberately not
	# `names.size() == 6`. A baked scene is also hand-editable (§1.9), and an
	# added child is legitimate content, not a defect: dropping a MapOverlay
	# into a map to inspect it is the intended workflow, and events mode is
	# built around exactly that (MapOverlay.entity_root() falls back to its
	# parent). Forbidding extras would make every legitimate edit look like a
	# regression.
	#
	# [Rider D] This previously claimed Pallet Town carries such an overlay.
	# It does not, and Section N asserts that no baked map does — a comment
	# contradicting a test in the same file. The reasoning above survives; only
	# the example was false.
	_chk("H.13 non-drawn events live in a separate trailing container",
			names.size() >= 6 and names[5] == "Triggers")
	root.free()


# --- J. per-cell marks survive the full save/load chain (M27B Change 3) ------
## The gap section C found: H.10/H.11 assert has_authored_cells() on SYNTHETIC
## in-memory MapData, so nothing guarded save/load fidelity — and Change 1
## nearly shipped provenance write-only for exactly that reason. Both fields are
## only worth anything if a mark set today is still there tomorrow, so this
## drives the real chain: baked .tres -> mutate -> save -> reload.
func _test_marks_survive_round_trip() -> void:
	const BAKED_DATA := "res://scenes/maps/PalletTown_Frlg_data.tres"
	if not ResourceLoader.exists(BAKED_DATA):
		_gated += ROUND_TRIP_ASSERTIONS
		return
	var d: MapData = load(BAKED_DATA) as MapData
	_chk("J.01 baked map data loads", d != null)
	if d == null:
		return
	var cells := d.metatile.size()
	_chk("J.02 provenance is full length", d.provenance.size() == cells)
	_chk("J.03 attr_explicit is full length", d.attr_explicit.size() == cells)

	# THIS MAP IS A LIVE EDITING TARGET. The overlay authors into it by design,
	# so a saved AUTHOR-mode paint legitimately leaves cells in the backlog and
	# legitimately makes a given coordinate no longer imported. The original
	# assertions here read cell (0,0) and demanded an empty backlog — both true
	# only while nobody had used the tool yet, which is not a property worth
	# defending. They now assert the invariants that hold however much the map
	# has been painted.
	var probe := Vector2i(-1, -1)
	for y in range(d.height):
		for x in range(d.width):
			if not d.is_authored(x, y):
				probe = Vector2i(x, y)
				break
		if probe.x >= 0:
			break

	if probe.x < 0:
		# Every cell hand-authored: there is no imported cell left to describe.
		_gated += 3
	else:
		# An imported cell is explicit on BOTH attributes: its values came from
		# source and are authoritative, not a guess.
		_chk("J.04 imported cells are explicit on collision",
				d.collision_is_explicit(probe.x, probe.y))
		_chk("J.05 imported cells are explicit on elevation",
				d.elevation_is_explicit(probe.x, probe.y))
		_chk("J.06 an imported cell therefore needs no review",
				not d.needs_review(probe.x, probe.y))

	# The importer must never MANUFACTURE a review cell — every cell it emitted
	# is stamped explicit on both attributes. Strictly stronger than the old
	# "backlog is empty" for the imported subset, and it survives painting,
	# because it only ever looks at cells a human has not touched.
	var imported_all_explicit := true
	for y in range(d.height):
		for x in range(d.width):
			if d.is_authored(x, y):
				continue
			if not (d.collision_is_explicit(x, y) and d.elevation_is_explicit(x, y)):
				imported_all_explicit = false
	_chk("J.07 the importer emits no half-decided cells", imported_all_explicit)

	# Now author one cell and half-decide it, which is the state the overlay
	# exists to make visible: painted, but its movement rules never confirmed.
	var review_before := d.review_cells()
	d.provenance[0] = MapData.Provenance.AUTHORED
	d.attr_explicit[0] = MapData.AttrFlag.ELEVATION_EXPLICIT  # collision left a guess
	_chk("J.08 a half-decided authored cell needs review", d.needs_review(0, 0))
	_chk("J.09 ...and reports which half is still a guess",
			d.elevation_is_explicit(0, 0) and not d.collision_is_explicit(0, 0))
	# A DELTA, not an absolute: whatever the last save left in the backlog is
	# the baseline, and this cell is the only thing that may have joined it.
	# (0,0) may already have been in there, in which case the size holds.
	var review := d.review_cells()
	var grew_by := 0 if review_before.has(Vector2i(0, 0)) else 1
	_chk("J.10 review_cells() picks up exactly the cell just half-decided",
			review.has(Vector2i(0, 0))
			and review.size() == review_before.size() + grew_by)

	var tmp := "user://m27b_round_trip.tres"
	_chk("J.11 saves", ResourceSaver.save(d, tmp) == OK)
	var back: MapData = ResourceLoader.load(tmp, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	_chk("J.12 reloads", back != null)
	if back == null:
		return
	# The assertions that would have caught Change 1's write-only provenance.
	_chk("J.13 provenance survived the round trip",
			back.provenance.size() == cells
			and back.provenance[0] == MapData.Provenance.AUTHORED)
	_chk("J.14 attr_explicit survived the round trip",
			back.attr_explicit.size() == cells
			and back.attr_explicit[0] == MapData.AttrFlag.ELEVATION_EXPLICIT)
	_chk("J.15 has_authored_cells() still fires after reload", back.has_authored_cells())
	_chk("J.16 the half-decided cell is still flagged for review", back.needs_review(0, 0))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


## The importer's own emission, read straight off the JSON build input rather
## than the baked artifact — the two can disagree, and only this catches it.
func _test_importer_stamps_explicit() -> void:
	# Reads the JSON build input, so it gates with section A on a fresh clone.
	if not _map_data_available():
		_gated += 4
		return
	var m := MapData.load_from(MAP_JSON)
	if m == null:
		return
	# Length is asserted FIRST and separately. Indexing straight into
	# attr_explicit would abort this function on a broken read-back, which
	# LOOKS like a passing suite with a smaller total — proven by deliberately
	# breaking load_from and watching 87/87 become 86/86 with no failure named.
	# This is the assertion that actually guards Change 1's failure mode.
	_chk("J.17 load_from() reads attr_explicit back at full length (got %d, want %d)"
			% [m.attr_explicit.size(), m.metatile.size()],
			m.attr_explicit.size() == m.metatile.size())
	_chk("J.18 load_from() reads provenance back at full length",
			m.provenance.size() == m.metatile.size())
	if m.attr_explicit.size() != m.metatile.size():
		return
	var non_explicit := 0
	for i in range(m.metatile.size()):
		if m.attr_explicit[i] != MapData.ATTR_ALL_EXPLICIT:
			non_explicit += 1
	_chk("J.19 the importer stamps every imported cell explicit on both attributes",
			non_explicit == 0)
	# [Rider 2] The atlas name used to be written only on the render path, so
	# `gen_map_import.py all` -- the mode the fresh-checkout announce line tells
	# people to run -- emitted JSON the baker could not consume. Guarded here
	# because the symptom appeared two steps downstream, at bake time.
	_chk("J.20 the imported JSON carries a non-empty atlas name (got %s)" % m.atlas,
			m.atlas != "")



# --- K. cell_info(): the overlay's read seam (M27B Change 2) ----------------
## §20 requires the overlay to read the REAL resolver. These assert the seam
## bundles what MapData and StepResolver already know WITHOUT re-deriving any
## of it — the failure mode being a renderer that grows its own opinion about
## which behaviours block which way and then drifts from the resolver.
func _test_cell_info_against_a_real_map() -> void:
	var m := MapData.load_from(MAP_JSON)
	if m == null:
		_gated += CELL_INFO_MAP_ASSERTIONS
		return
	var r := StepResolver.new(m)

	var ci := r.cell_info(Vector2i(0, 0))
	_chk("K.01 reports in_bounds for a real cell", ci["in_bounds"])
	_chk("K.02 out-of-bounds is reported, not crashed",
			not r.cell_info(Vector2i(-1, 0))["in_bounds"])
	_chk("K.03 out-of-bounds carries no other keys to misread",
			r.cell_info(Vector2i(999, 999)).size() == 2)

	# Every field must agree with the source it delegates to — the seam adds no
	# opinions of its own.
	var agree := true
	for y in range(m.height):
		for x in range(m.width):
			var c := r.cell_info(Vector2i(x, y))
			if c["behavior"] != m.behavior_at(x, y) \
					or c["collision"] != m.collision_at(x, y) \
					or c["elevation"] != m.elevation_at(x, y) \
					or c["layer_type"] != m.layer_type_at(x, y) \
					or c["priority"] != m.priority_at(x, y) \
					or c["needs_review"] != m.needs_review(x, y):
				agree = false
				break
	_chk("K.04 every cell agrees with MapData across the whole map", agree)

	# Imported data is fully named, so magenta never fires on it. This is the
	# assertion that gives "untagged" its meaning.
	var untagged := 0
	for y in range(m.height):
		for x in range(m.width):
			if r.cell_info(Vector2i(x, y))["untagged"]:
				untagged += 1
	_chk("K.05 no imported cell is untagged (magenta means hand-painted)",
			untagged == 0)
	_chk("K.06 a real cell carries its MB_* name",
			str(ci["behavior_name"]).begins_with("MB_"))
	_chk("K.07 imported cells report both attributes explicit",
			ci["collision_explicit"] and ci["elevation_explicit"])


## Synthetic edges: behaviours the corridor does not contain, and the untagged
## case that cannot exist in imported data at all.
func _test_cell_info_synthetic_edges() -> void:
	var N := MetatileBehavior.MB_IMPASSABLE_NORTH
	var L := MetatileBehavior.MB_JUMP_SOUTH
	var m := _synth(3, 1, [N, L, 0])
	var r := StepResolver.new(m)

	# Two-sided blocking, read straight off the resolver's own tables.
	var n := r.cell_info(Vector2i(0, 0))
	_chk("K.08 a north-blocked tile cannot be ENTERED heading south",
			StepResolver.Dir.SOUTH in n["entries_blocked"])
	_chk("K.09 ...and cannot be LEFT heading north",
			StepResolver.Dir.NORTH in n["exits_blocked"])
	_chk("K.10 ...and is unrestricted east/west",
			not (StepResolver.Dir.EAST in n["exits_blocked"])
			and not (StepResolver.Dir.WEST in n["exits_blocked"]))

	var l := r.cell_info(Vector2i(1, 0))
	_chk("K.11 a ledge reports its direction", l["ledge_dir"] == StepResolver.Dir.SOUTH)
	_chk("K.12 a plain tile reports no ledge", r.cell_info(Vector2i(2, 0))["ledge_dir"] == -1)

	# The untagged case. 240 constants cover 0..239, so anything above is
	# genuinely unnamed — the only way magenta can ever appear.
	var u := _synth(1, 1, [250])
	_chk("K.13 a behaviour with no MB_* name is untagged",
			StepResolver.new(u).cell_info(Vector2i(0, 0))["untagged"])
	_chk("K.14 ...and a named one is not", not StepResolver.is_untagged_behavior(0))

	# Elevation wildcards: 0 is 56% of Kanto and means unconstrained, not stairs.
	var w := _synth(2, 1, [], [], [0, 3])
	var rw := StepResolver.new(w)
	_chk("K.15 elevation 0 is reported as a wildcard",
			rw.cell_info(Vector2i(0, 0))["elevation_wildcard"])
	_chk("K.16 a real elevation is not",
			not rw.cell_info(Vector2i(1, 0))["elevation_wildcard"])

	# A half-decided authored cell — the state the overlay exists to surface.
	m.provenance = PackedByteArray([MapData.Provenance.AUTHORED, 0, 0])
	m.attr_explicit = PackedByteArray([MapData.AttrFlag.ELEVATION_EXPLICIT, 3, 3])
	var hd := StepResolver.new(m).cell_info(Vector2i(0, 0))
	_chk("K.17 a half-decided cell reports needs_review", hd["needs_review"])
	_chk("K.18 ...naming which attribute is still a guess",
			hd["elevation_explicit"] and not hd["collision_explicit"])


# --- G. debug toggle --------------------------------------------------------
func _test_debug_toggle() -> void:
	var r := StepResolver.new(_synth(3, 3, [], [0, 0, 0, 0, 1, 0, 0, 0, 0]))
	r.no_collision = true
	_chk("G.01 no_collision walks through solid cells",
			r.resolve(Vector2i(1, 2), StepResolver.Dir.NORTH, 3)["outcome"]
			== StepResolver.Outcome.NONE)
	_chk("G.02 no_collision still reports the target cell",
			r.resolve(Vector2i(1, 2), StepResolver.Dir.NORTH, 3)["to"] == Vector2i(1, 1))


# --- I. object events emitted as real nodes (M27B) --------------------------
## Every assertion here reads a BAKED scene, not the importer's own JSON — the
## scene is the artifact, so a node that fails to persist (a missing owner, a
## dropped export) has to fail here rather than pass against the input.
func _test_object_events() -> void:
	if not ResourceLoader.exists("res://scenes/maps/Route3_Frlg.tscn"):
		_gated += OBJECT_EVENT_ASSERTIONS
		return
	var packed: PackedScene = load("res://scenes/maps/Route3_Frlg.tscn") as PackedScene
	_chk("I.01 Route 3 baked scene loads", packed != null)
	if packed == null:
		return
	var root: Node2D = packed.instantiate()

	var triggers := root.get_node_or_null("Triggers")
	_chk("I.02 a Triggers container exists", triggers != null)

	var all: Array[OverworldEntity] = []
	for container in ["Entities_P2", "Entities_P1", "Triggers"]:
		var n := root.get_node_or_null(container)
		if n == null:
			continue
		for c in n.get_children():
			if c is OverworldEntity:
				all.append(c)
	_chk("I.03 Route 3 emitted its 11 events", all.size() == 11)

	# The script has to be attached, not just the node created — a bare Node2D
	# would still count above while carrying none of the imported data.
	var trainers: Array[TrainerNPC] = []
	var npcs := 0
	var signs := 0
	for e in all:
		if e is TrainerNPC:
			trainers.append(e)
		elif e is NPC:
			npcs += 1
		elif e is Sign:
			signs += 1
	_chk("I.04 8 trainers, typed as TrainerNPC", trainers.size() == 8)
	_chk("I.05 the plain NPC is NOT typed as a trainer", npcs == 1)
	_chk("I.06 2 signs", signs == 2)

	var robin: TrainerNPC = null
	for t in trainers:
		if t.trainer_key == "TRAINER_LASS_ROBIN_FRLG":
			robin = t
	_chk("I.07 Robin resolved to a canonical, origin-suffixed key", robin != null)
	if robin != null:
		_chk("I.08 her cell survived the bake", robin.cell == Vector2i(40, 11))
		_chk("I.09 position is derived from the cell, not stored separately",
				robin.position == Vector2(40 * 16, 11 * 16))
		_chk("I.10 sight range imported", robin.sight_range == 3)
		_chk("I.11 overworld sprite is PLACEMENT data on the node",
				robin.graphics_id == "OBJ_EVENT_GFX_LASS_FRLG")
		_chk("I.12 movement type imported",
				robin.movement_type == "MOVEMENT_TYPE_WANDER_UP_AND_DOWN")
		_chk("I.13 script label recorded for M27G to route later",
				robin.script_label == "Route3_EventScript_Robin")
		# [Step 5] These two FLIPPED, by design. Until the Kanto roster was
		# converted they were tripwires asserting the gap could not close
		# silently; now they assert it HAS closed. Both directions matter --
		# a placement carrying a valid key that resolves to nothing is the
		# failure mode this whole arc existed to remove.
		_chk("I.14 the key resolves against the converted Kanto roster",
				robin.has_registry_entry())
		_chk("I.15 and therefore raises NO configuration warning",
				not _warns_about(robin, "does not resolve"))
	# Every trainer placement resolved to SOME key — an unresolved placement
	# would be an importer failure, distinct from the roster gap above.
	var keyed := 0
	for t in trainers:
		if t.trainer_key.begins_with("TRAINER_"):
			keyed += 1
	_chk("I.16 all 8 trainer placements carry a real key", keyed == 8)

	# Draw priority routes entities between the two strata; every Route 3
	# event sits at elevation 3, so all of them belong in P2.
	var p1 := root.get_node_or_null("Entities_P1")
	_chk("I.17 nothing lands in the priority-1 stratum on a flat map",
			p1 != null and p1.get_child_count() == 0)
	for t in trainers:
		if t.priority() != 2:
			_chk("I.18 flat-map entities are priority 2", false)
			root.free()
			return
	_chk("I.18 flat-map entities are priority 2", true)

	root.free()

	# Warps and item balls do not appear on Route 3; Viridian City carries both.
	var vpacked: PackedScene = load("res://scenes/maps/ViridianCity_Frlg.tscn") as PackedScene
	_chk("I.19 Viridian City baked scene loads", vpacked != null)
	if vpacked == null:
		return
	var vroot: Node2D = vpacked.instantiate()
	var warps: Array[Warp] = []
	var balls: Array[ItemBall] = []
	for container in ["Entities_P2", "Entities_P1", "Triggers"]:
		var n := vroot.get_node_or_null(container)
		if n == null:
			continue
		for c in n.get_children():
			if c is Warp:
				warps.append(c)
			elif c is ItemBall:
				balls.append(c)
	_chk("I.20 Viridian City emitted its 5 warps", warps.size() == 5)
	_chk("I.21 and its 1 item ball", balls.size() == 1)
	if warps.size() > 0:
		var w: Warp = warps[0]
		_chk("I.22 a warp names a real destination map",
				w.dest_map.begins_with("MAP_"))
		_chk("I.23 dest_warp_id parsed as an int, not left a string",
				typeof(w.dest_warp_id) == TYPE_INT)
	if balls.size() > 0:
		var b: ItemBall = balls[0]
		# Source writes "0" for "no flag"; a pickup genuinely has one, and
		# carrying the literal "0" through would make every plain NPC look gated.
		_chk("I.24 the pickup's hide flag survived", b.visibility_flag.begins_with("FLAG_"))
	var plain_npc: NPC = null
	for c in vroot.get_node_or_null("Entities_P2").get_children():
		if c is NPC and not (c is TrainerNPC):
			plain_npc = c
			break
	_chk("I.25 an unflagged NPC has an EMPTY flag, not the literal \"0\"",
			plain_npc != null and plain_npc.visibility_flag == "")
	vroot.free()


## Section L — the @tool dependency chain.
##
## MapOverlay is an editor surface, and Godot instantiates a NON-@tool script
## as a PLACEHOLDER in the editor: any call into one throws "Attempt to call a
## method on a placeholder instance". So it is not enough for the overlay
## itself to be @tool — every script it reads through must be too.
##
## This shipped broken. The overlay could not render in the editor at all,
## because StepResolver and MapData were placeholders there, and the runtime
## screenshots that "verified" Step C could never have caught it: at runtime
## nothing is a placeholder. Reading the first line of four files is cheap and
## would have caught it for free, so it is a test rather than a note.
##
## metatile_behavior.gd is GENERATED — its @tool comes from the emitter in
## gen_map_import.py, not a hand-added line, which a re-run would wipe.
func _test_tool_chain() -> void:
	# Events mode widened this chain: the overlay now resolves warp
	# destinations through MapConstants (generated, so its @tool comes from the
	# emitter) and type-tests every entity class by name. A non-@tool script
	# anywhere in here is instantiated as a placeholder and takes the whole
	# overlay down with it in the editor.
	const CHAIN := [
		"res://scripts/overworld/map_overlay.gd",
		"res://scripts/overworld/step_resolver.gd",
		"res://scripts/overworld/map_data.gd",
		"res://scripts/overworld/metatile_behavior.gd",
		"res://scripts/overworld/map_constants.gd",
		"res://scripts/overworld/movement_types.gd",
		"res://scripts/overworld/entities/overworld_entity.gd",
		"res://scripts/overworld/entities/npc.gd",
		"res://scripts/overworld/entities/trainer_npc.gd",
		"res://scripts/overworld/entities/item_ball.gd",
		"res://scripts/overworld/entities/warp.gd",
		"res://scripts/overworld/entities/trigger.gd",
		"res://scripts/overworld/entities/sign.gd",
	]
	var i := 0
	for path in CHAIN:
		i += 1
		var f := FileAccess.open(path, FileAccess.READ)
		var first := f.get_line() if f != null else "<missing>"
		if f != null:
			f.close()
		_chk("L.%02d %s starts with @tool (got %s)"
				% [i, path.get_file(), first],
				first.strip_edges() == "@tool")


## Section M — baked scenes carry a stable UID.
##
## A scene with no UID is invisible to the editor's resource pickers, so it
## cannot be selected as an instanced child. `ResourceSaver` does not write
## one; the baker adds it.
##
## M.10-M.13 are the half that matters. The UID must be PRESERVED across a
## re-bake, not re-minted: a baker that mints fresh each bake changes every
## scene's identity per re-bake — the `unique_id` churn problem one line
## higher up, and worse, because other scenes resolve references against a
## UID. These drive the baker's own helper against scratch files rather than
## running a real bake, so the RULE is tested directly and cheaply.
func _test_baked_scene_uids() -> void:
	var baker: GDScript = load("res://scenes/overworld/map_baker.gd")

	if not FileAccess.file_exists("res://scenes/maps/PalletTown_Frlg.tscn"):
		_gated += BAKED_SCENE_ASSERTIONS
	else:
		var seen := {}
		var i := 0
		for nm in CORRIDOR_MAPS:
			i += 1
			var uid: String = baker._existing_uid("res://scenes/maps/%s.tscn" % nm)
			_chk("M.%02d %s carries a uid (got %s)" % [i, nm, uid],
					uid.begins_with("uid://") and uid.length() > 6)
			seen[uid] = nm
		# Distinctness is the cheap proof they were not all minted from one
		# shared constant — which the per-file check above would sail past.
		_chk("M.09 all 8 baked UIDs are distinct (%d unique)" % seen.size(),
				seen.size() == CORRIDOR_MAPS.size())

	# --- the preserve-or-mint rule itself, on scratch files ---
	var dir := "user://uid_rule_test/"
	DirAccess.make_dir_recursive_absolute(dir)

	var kept := dir + "kept.tscn"
	_write_text(kept, "[gd_scene format=4 uid=\"uid://bqqqqqqqqqqqq\"]\n\n[node name=\"R\" type=\"Node2D\"]\n")
	var bk: GDScript = baker
	bk._preserve_or_mint_uid(kept, bk._existing_uid(kept))
	_chk("M.10 an existing UID survives untouched",
			bk._existing_uid(kept) == "uid://bqqqqqqqqqqqq")

	var fresh := dir + "fresh.tscn"
	_write_text(fresh, "[gd_scene format=4]\n\n[node name=\"R\" type=\"Node2D\"]\n")
	bk._preserve_or_mint_uid(fresh, "")
	var minted: String = bk._existing_uid(fresh)
	_chk("M.11 a scene with no UID gets one minted (got %s)" % minted,
			minted.begins_with("uid://") and minted.length() > 6)

	# Idempotence IS the preserve rule: baking twice must not change identity.
	bk._preserve_or_mint_uid(fresh, minted)
	_chk("M.12 a second bake preserves the minted UID",
			bk._existing_uid(fresh) == minted)

	# --- ext_resource uids: restore-only, never mint (the third level) ---
	var ext_src := dir + "ext_src.tscn"
	_write_text(ext_src,
			"[gd_scene format=4 uid=\"uid://bkkkkkkkkkkkk\"]\n"
			+ "[ext_resource type=\"Texture2D\" uid=\"uid://batlas0000001\" path=\"res://a.png\" id=\"1\"]\n"
			+ "[ext_resource type=\"Script\" path=\"res://b.gd\" id=\"2\"]\n")
	var ext_map: Dictionary = bk._existing_ext_uids(ext_src)
	_chk("M.14 ext_resource uids are read keyed by path (%s)" % ext_map,
			ext_map.size() == 1 and ext_map.get("res://a.png", "") == "uid://batlas0000001")

	# What a programmatic save produces: every uid dropped.
	var ext_saved := dir + "ext_saved.tscn"
	_write_text(ext_saved,
			"[gd_scene format=4]\n"
			+ "[ext_resource type=\"Texture2D\" path=\"res://a.png\" id=\"1\"]\n"
			+ "[ext_resource type=\"Script\" path=\"res://b.gd\" id=\"2\"]\n"
			+ "[ext_resource type=\"Texture2D\" path=\"res://never_seen.png\" id=\"3\"]\n")
	bk._restore_ext_resource_uids(ext_saved, ext_map)
	var restored := FileAccess.open(ext_saved, FileAccess.READ).get_as_text()
	_chk("M.15 a known path gets its uid put back",
			restored.contains("uid=\"uid://batlas0000001\" path=\"res://a.png\""))
	# `path=` still sits immediately after `type=`, i.e. no uid was inserted.
	_chk("M.16 a path with no prior uid is left alone, not invented",
			restored.contains("[ext_resource type=\"Script\" path=\"res://b.gd\""))
	_chk("M.17 a path absent from the prior file is left alone too",
			restored.contains("[ext_resource type=\"Texture2D\" path=\"res://never_seen.png\""))

	# Idempotence: re-running must not double-insert.
	bk._restore_ext_resource_uids(ext_saved, ext_map)
	var again := FileAccess.open(ext_saved, FileAccess.READ).get_as_text()
	_chk("M.18 restoring twice is a no-op, not a double insertion",
			again == restored and again.count("uid://batlas0000001") == 1)

	# The rest of the file must survive the header rewrite intact.
	var f := FileAccess.open(fresh, FileAccess.READ)
	var body := f.get_as_text() if f != null else ""
	if f != null:
		f.close()
	_chk("M.13 the header rewrite leaves the scene body intact",
			body.contains("[node name=\"R\" type=\"Node2D\"]"))


## Section N — the overlay is never baked into a map scene.
##
## MapOverlay lives in its own scene and is instanced conditionally. That is
## not a style preference: a persisted instance ships inside the map scene
## unconditionally, which bypasses the `OS.is_debug_build()` gate entirely and
## puts a developer x-ray in a shipped build.
##
## This is here because it already happened. An editor session saved
## PalletTown_Frlg.tscn with the overlay instanced inside it, and the only
## reason anything noticed was H.13's container count going from 6 to 7 — a
## side effect, in a test about draw order, that says nothing about what was
## actually wrong. This names it.
func _test_overlay_never_baked() -> void:
	if not FileAccess.file_exists("res://scenes/maps/PalletTown_Frlg.tscn"):
		_gated += OVERLAY_ASSERTIONS
		return
	var i := 0
	for nm in CORRIDOR_MAPS:
		i += 1
		var f := FileAccess.open("res://scenes/maps/%s.tscn" % nm, FileAccess.READ)
		var text := f.get_as_text() if f != null else ""
		if f != null:
			f.close()
		# Catch it by scene path AND by script path: an instance references the
		# .tscn, but a bare Node2D with the script attached would slip past that.
		_chk("N.%02d %s does not bake in the overlay" % [i, nm],
				not text.contains("scenes/overworld/map_overlay.tscn")
				and not text.contains("scripts/overworld/map_overlay.gd"))


## Section S — events mode: markers and dead doors.
##
## Two things are under test and they fail differently. The MAP_* -> map-name
## table is a generated FACT about the reference and is committed, so it runs
## on a fresh clone. Everything that reads a placed entity needs the corridor
## baked, and gates.
##
## The dead-door check has three outcomes, not two, and keeping them apart is
## the whole point: a real map that is not baked yet is the expected M27C gap,
## while a constant source does not define is an importer bug wearing the same
## costume. A test that only asserted "not baked" would pass for both.
func _test_events_mode_table() -> void:
	_chk("S.01 the map table covers every region, not just Kanto",
			MapConstants.NAME_BY_CONSTANT.size() == 939)
	# The case that proves the table has to EXIST: no casing rule turns
	# MAP_SSANNE_EXTERIOR into SSAnne_Exterior_Frlg.
	_chk("S.02 a name no string transform could derive resolves",
			MapConstants.map_name_for("MAP_SSANNE_EXTERIOR")
					== "SSAnne_Exterior_Frlg")
	_chk("S.03 an ordinary route resolves",
			MapConstants.map_name_for("MAP_ROUTE3") == "Route3_Frlg")
	# Empty, never a guess. A guessed name would make an importer bug look like
	# an unbaked map, which is exactly the confusion this table removes.
	_chk("S.04 an undefined constant resolves to nothing, not a guess",
			MapConstants.map_name_for("MAP_NOT_A_REAL_PLACE") == "")
	_chk("S.05 scene_path_for builds the baker's own path",
			MapConstants.scene_path_for("MAP_ROUTE3")
					== "res://scenes/maps/Route3_Frlg.tscn")
	_chk("S.06 and stays empty for an undefined constant",
			MapConstants.scene_path_for("MAP_NOT_A_REAL_PLACE") == "")
	# A known interior nobody has baked: the dangling stem this mode draws.
	_chk("S.07 a known-but-unbaked interior reads as not baked",
			not MapConstants.is_baked("MAP_VIRIDIAN_CITY_GYM"))

	# The overlay must survive being asked about events with no map under it.
	var orphan := MapOverlay.new()
	_chk("S.08 an overlay with no map reports no entity source",
			not orphan.has_entity_source())
	_chk("S.09 and returns no entities rather than failing",
			orphan.entities().is_empty())

	# Appending EVENTS to the enum has to have joined the F3 cycle; if it did
	# not, the mode is unreachable at runtime no matter how well it draws.
	var seen_events := false
	for _i in range(MapOverlay.Mode.size() + 1):
		orphan.next_mode()
		if orphan.mode == MapOverlay.Mode.EVENTS:
			seen_events = true
	_chk("S.10 EVENTS is reachable by cycling modes", seen_events)
	orphan.free()


func _test_events_mode_entities() -> void:
	if not ResourceLoader.exists("res://scenes/maps/Route3_Frlg.tscn"):
		_gated += EVENTS_MODE_ASSERTIONS
		return
	_chk("S.11 a baked corridor map reads as baked",
			MapConstants.is_baked("MAP_ROUTE3"))

	var root: Node2D = (load("res://scenes/maps/Route3_Frlg.tscn")
			as PackedScene).instantiate()
	var ov := MapOverlay.new()
	# No map_root assigned: this is the expected placement, and the fallback to
	# get_parent() is what makes events mode work by just dropping the overlay
	# into the map scene.
	root.add_child(ov)
	_chk("S.12 the parent fallback finds the map", ov.has_entity_source())
	var found := ov.entities()
	_chk("S.13 both entity strata and the trigger container are walked",
			found.size() == 11)

	var kinds := {}
	for e in found:
		var k := ov.entity_kind(e)
		kinds[k] = int(kinds.get(k, 0)) + 1
	# The subclass trap: TrainerNPC extends NPC, so a naive `is NPC` first
	# would file all 8 trainers as plain people and the marker layer would be
	# quietly, plausibly wrong.
	_chk("S.14 trainers are not filed as plain NPCs", int(kinds.get("trainer", 0)) == 8)
	_chk("S.15 the one plain NPC is still an NPC", int(kinds.get("npc", 0)) == 1)
	_chk("S.16 signs are their own kind", int(kinds.get("sign", 0)) == 2)
	# Every kind drawn must have a marker letter, or it renders blank.
	var lettered := true
	for k in kinds:
		if not MapOverlay.ENTITY_LETTERS.has(k):
			lettered = false
	_chk("S.17 every kind present has a marker letter", lettered)

	# An explicit map_root must win over the parent, or an overlay placed
	# outside the map scene can never be pointed at one.
	var stray := MapOverlay.new()
	add_child(stray)
	_chk("S.18 an overlay parented elsewhere sees nothing by default",
			not stray.has_entity_source())
	stray.map_root = root
	_chk("S.19 an explicit map_root overrides the parent fallback",
			stray.has_entity_source() and stray.entities().size() == 11)
	stray.queue_free()
	root.free()

	# Warps live on Viridian City, and all 5 lead to interiors nobody has baked.
	var vroot: Node2D = (load("res://scenes/maps/ViridianCity_Frlg.tscn")
			as PackedScene).instantiate()
	var vov := MapOverlay.new()
	vroot.add_child(vov)
	var warps: Array[Warp] = []
	for e in vov.entities():
		if e is Warp:
			warps.append(e)
	_chk("S.20 Viridian City's warps are found", warps.size() == 5)

	var states := {}
	for w in warps:
		var s := vov.warp_state(w)
		states[s] = int(states.get(s, 0)) + 1
	_chk("S.21 every real warp names a map source defines",
			int(states.get("unknown", 0)) == 0)
	# A TRIPWIRE, and it is meant to flip. When M27C bakes these interiors this
	# assertion fails, and that failure is the correct signal — the same shape
	# as I.14/I.15, which asserted a gap could not close silently until it did.
	# Re-point it at the new count; do not delete it.
	_chk("S.22 all 5 lead to unbaked interiors — the dangling stems",
			int(states.get("unbaked", 0)) == 5)

	# The three states, driven directly. Synthetic warps because the corridor
	# has no example of the other two: nothing warps to a baked map yet, and an
	# undefined constant would be a bug rather than data.
	var good := Warp.new()
	good.dest_map = "MAP_ROUTE3"
	_chk("S.23 a warp to a baked map reads baked", vov.warp_state(good) == "baked")
	var bogus := Warp.new()
	bogus.dest_map = "MAP_NOT_A_REAL_PLACE"
	_chk("S.24 a warp to an undefined constant is an importer bug, not a gap",
			vov.warp_state(bogus) == "unknown")
	var blank := Warp.new()
	_chk("S.25 a warp with no destination at all is caught too",
			vov.warp_state(blank) == "unknown")
	good.free()
	bogus.free()
	blank.free()
	vroot.free()


## Section T — trainer sight lines.
##
## Rays are drawn ONLY for the four fixed-facing movement types. Everything
## else either rotates in place or walks, and source resolves its facing from
## live object state at check time, so there is no single honest line to draw.
## The tests below are mostly about the NEGATIVE cases: once rays are
## conditional, "no ray" has five distinct meanings and a tool that renders
## them identically is worse than one that draws nothing.
func _test_trainer_sight() -> void:
	_chk("T.01 exactly four movement types have a fixed facing",
			MovementTypes.FIXED_FACING.size() == 4)
	# y is DOWN in cell space. Getting this inverted would point every ray the
	# wrong way while still looking plausible on a symmetric map.
	_chk("T.02 FACE_UP steps to -y, not +y",
			MovementTypes.FIXED_FACING["MOVEMENT_TYPE_FACE_UP"] == Vector2i(0, -1))
	_chk("T.03 FACE_DOWN steps to +y",
			MovementTypes.FIXED_FACING["MOVEMENT_TYPE_FACE_DOWN"] == Vector2i(0, 1))
	_chk("T.04 the full movement-type set was generated, not hand-typed",
			MovementTypes.ALL.size() == 89)
	_chk("T.05 a rotating type is known but has no fixed facing",
			MovementTypes.is_known("MOVEMENT_TYPE_LOOK_AROUND")
			and not MovementTypes.has_fixed_facing("MOVEMENT_TYPE_LOOK_AROUND"))
	_chk("T.06 a typo is not a known movement type",
			not MovementTypes.is_known("MOVEMENT_TYPE_FACE_LEFTT"))

	# Open 7x7 field, trainer dead centre facing east.
	var ov := MapOverlay.new()
	ov.map_data = _synth(7, 7, [])
	var t := TrainerNPC.new()
	t.cell = Vector2i(3, 3)
	t.sight_range = 3
	t.movement_type = "MOVEMENT_TYPE_FACE_RIGHT"
	_chk("T.07 a clear line covers exactly sight_range cells",
			ov.trainer_sight_cells(t).size() == 3)
	_chk("T.08 and starts on the cell in front, not the trainer's own",
			ov.trainer_sight_cells(t)[0] == Vector2i(4, 3))
	_chk("T.09 state reads as shown", ov.trainer_sight_state(t) == "shown")

	# The correction that makes this a tool rather than a compass: source
	# abandons the check on the first collision, so a wall truncates the
	# corridor. A trainer with range 3 behind a wall does not cover 3 cells.
	var walled := _synth(7, 7, [])
	walled.collision[3 * 7 + 5] = 1        # two cells east of the trainer
	ov.map_data = walled
	var cells := ov.trainer_sight_cells(t)
	_chk("T.10 a wall truncates the corridor short of sight_range",
			cells.size() == 1 and cells[0] == Vector2i(4, 3))
	# The wall cell itself is excluded: nobody can stand in it, so it is not a
	# cell you can be caught on.
	var blocked_cells := ov.trainer_sight_cells(t)
	var has_wall := false
	for c in blocked_cells:
		if c == Vector2i(5, 3):
			has_wall = true
	_chk("T.11 the blocking cell itself is not part of the corridor", not has_wall)

	# Wall immediately in front: a real finding, and distinct from 'blind'.
	var adjacent := _synth(7, 7, [])
	adjacent.collision[3 * 7 + 4] = 1
	ov.map_data = adjacent
	_chk("T.12 a wall in the face reads as blocked, not as shown",
			ov.trainer_sight_state(t) == "blocked")
	_chk("T.13 and yields no cells", ov.trainer_sight_cells(t).is_empty())

	# The map edge truncates exactly like a wall.
	ov.map_data = _synth(7, 7, [])
	var edge := TrainerNPC.new()
	edge.cell = Vector2i(5, 3)
	edge.sight_range = 5
	edge.movement_type = "MOVEMENT_TYPE_FACE_RIGHT"
	_chk("T.14 the map edge truncates the corridor",
			ov.trainer_sight_cells(edge).size() == 1)
	edge.free()

	# The four no-ray states, each distinguishable.
	var rot := TrainerNPC.new()
	rot.cell = Vector2i(3, 3)
	rot.sight_range = 4
	rot.movement_type = "MOVEMENT_TYPE_WANDER_UP_AND_DOWN"
	_chk("T.15 a wanderer gets no line even with a real range",
			ov.trainer_sight_state(rot) == "rotates"
			and ov.trainer_sight_cells(rot).is_empty())
	rot.movement_type = "MOVEMENT_TYPE_LOOK_AROUND"
	_chk("T.16 a rotator in place gets no line either",
			ov.trainer_sight_state(rot) == "rotates")
	# 22 real Kanto trainers. Blind is NOT the same as rotating, and a tool
	# that conflated them would hide a genuine fact about the route.
	rot.movement_type = "MOVEMENT_TYPE_FACE_DOWN"
	rot.sight_range = 0
	_chk("T.17 sight_range 0 reads as blind, not as rotating",
			ov.trainer_sight_state(rot) == "blind")
	# The typo case — the exact failure a free-text movement_type invites.
	rot.sight_range = 3
	rot.movement_type = "MOVEMENT_TYPE_FACE_DOWNN"
	_chk("T.18 a typo'd movement type is called out, not silently no-lined",
			ov.trainer_sight_state(rot) == "unknown")
	_chk("T.19 and the node itself raises a configuration warning",
			_warns_about(rot, "not a type source defines"))
	rot.movement_type = "MOVEMENT_TYPE_FACE_DOWN"
	_chk("T.20 a real movement type raises no such warning",
			not _warns_about(rot, "not a type source defines"))
	rot.free()
	t.free()
	ov.free()


## Section U — click-to-select's hit test.
##
## The plugin turns a viewport click into a cell and asks the overlay what is
## there. Only the lookup is testable headlessly; the click plumbing itself is
## editor-only. A null return is as load-bearing as a hit: the plugin returns
## false on null so the click falls through to the editor, and swallowing it
## instead would make everything else in the viewport unselectable.
func _test_entity_at() -> void:
	if not ResourceLoader.exists("res://scenes/maps/Route3_Frlg.tscn"):
		_gated += ENTITY_AT_ASSERTIONS
		return
	var root: Node2D = (load("res://scenes/maps/Route3_Frlg.tscn")
			as PackedScene).instantiate()
	var ov := MapOverlay.new()
	root.add_child(ov)

	var robin: TrainerNPC = null
	for e in ov.entities():
		if e is TrainerNPC and (e as TrainerNPC).trainer_key == "TRAINER_LASS_ROBIN_FRLG":
			robin = e
	_chk("U.01 the fixture trainer is present", robin != null)
	if robin != null:
		var hit := ov.next_in_stack(robin.cell, null)
		_chk("U.02 a click on her cell finds her, not merely something",
				hit == robin)
	# An empty cell must return null so the plugin can decline the click.
	_chk("U.03 an empty cell yields null",
			ov.next_in_stack(Vector2i(0, 0), null) == null
			and ov.entities_at(Vector2i(0, 0)).is_empty())
	_chk("U.04 an out-of-bounds cell yields null rather than erroring",
			ov.next_in_stack(Vector2i(-5, -5), null) == null)
	root.free()


## Section V — stacked cells, the click cycle, and the counts banner.
##
## Fixtures are the REAL corridor overlaps rather than synthetic ones, so this
## gates on a baked tree. Viridian City (36,10) is a Gym door that is both a
## warp and a readable sign; Route 22 carries three cells of paired
## coord_events gated on the same VAR. All 22 such cells in Kanto were read
## and every one is deliberate authoring, which is why the marker is calm and
## the banner counts them without colouring its border.
func _test_stacks_and_counts() -> void:
	# Gates on BOTH maps it asserts against — the same mistake Rider C fixed in
	# section H. A tree with one baked and not the other would otherwise run
	# part of this section and credit none of it, which Z.99 then reports as an
	# arithmetic failure pointing nowhere near the real cause.
	if not ResourceLoader.exists("res://scenes/maps/ViridianCity_Frlg.tscn") \
			or not ResourceLoader.exists("res://scenes/maps/Route22_Frlg.tscn"):
		_gated += STACK_ASSERTIONS
		return

	var vroot: Node2D = (load("res://scenes/maps/ViridianCity_Frlg.tscn")
			as PackedScene).instantiate()
	var ov := MapOverlay.new()
	ov.map_data = load("res://scenes/maps/ViridianCity_Frlg_data.tres")
	vroot.add_child(ov)

	var gym_door := Vector2i(36, 10)
	var stack := ov.entities_at(gym_door)
	_chk("V.01 the Gym door really does hold two events", stack.size() == 2)
	var kinds := {}
	for e in stack:
		kinds[ov.entity_kind(e)] = true
	_chk("V.02 and they are the warp and the sign, not two of one kind",
			kinds.has("warp") and kinds.has("sign"))
	_chk("V.03 a single-entity cell still returns exactly one",
			ov.entities_at(stack[0].cell if stack.size() < 2 else Vector2i(0, 0)).size() <= 1)

	# The cycle: first click takes the top, the next takes the one under it,
	# and the one after wraps. Without wrap the second event is unreachable.
	var first := ov.next_in_stack(gym_door, null)
	_chk("V.04 a first click selects the top of the stack", first == stack[0])
	var second := ov.next_in_stack(gym_door, first)
	_chk("V.05 clicking again moves DOWN the stack, not nowhere",
			second == stack[1] and second != first)
	_chk("V.06 and a third click wraps rather than dead-ending",
			ov.next_in_stack(gym_door, second) == first)
	# A selection sitting on a different cell is the ordinary case of clicking
	# somewhere new; it must not be treated as "already in this stack".
	_chk("V.07 a selection elsewhere restarts at the top",
			ov.next_in_stack(gym_door, vroot) == stack[0])
	_chk("V.08 an empty cell yields nothing to select",
			ov.next_in_stack(Vector2i(1, 1), null) == null)

	var counts := ov.events_counts()
	_chk("V.09 the banner counts the one stacked cell here",
			int(counts["stacked"]) == 1)
	# Viridian City's five warps all lead to unbaked interiors. PENDING, not
	# broken — the banner must not colour its border for these.
	_chk("V.10 all five warps count as pending dead doors",
			int(counts["dead_doors"]) == 5)
	_chk("V.11 and none of them counts as a defect",
			int(counts["broken_warps"]) == 0 and int(counts["typo_trainers"]) == 0)
	vroot.free()

	# Route 22: three stacked cells, all paired triggers on one VAR. Not
	# conditional — the gate above already covers this map.
	var rroot: Node2D = (load("res://scenes/maps/Route22_Frlg.tscn")
			as PackedScene).instantiate()
	var rov := MapOverlay.new()
	rov.map_data = load("res://scenes/maps/Route22_Frlg_data.tres")
	rroot.add_child(rov)
	var rc := rov.events_counts()
	_chk("V.12 Route 22's three trigger pairs are counted once each",
			int(rc["stacked"]) == 3)
	_chk("V.13 stacked triggers are not miscounted as defects",
			int(rc["broken_warps"]) == 0 and int(rc["typo_trainers"]) == 0)
	rroot.free()

	# A genuine defect DOES colour the verdict. Synthetic, because no real map
	# carries one — which is the point.
	var bad := MapOverlay.new()
	bad.map_data = _synth(4, 4, [])
	var holder := Node2D.new()
	var container := Node2D.new()
	container.name = "Triggers"
	holder.add_child(container)
	var w := Warp.new()
	w.cell = Vector2i(1, 1)
	w.dest_map = "MAP_NOT_A_REAL_PLACE"
	container.add_child(w)
	holder.add_child(bad)
	var bc := bad.events_counts()
	_chk("V.14 an undefined destination counts as a defect, not as pending",
			int(bc["broken_warps"]) == 1 and int(bc["dead_doors"]) == 0)
	holder.free()


## Section X — the paint-gesture lifecycle.
##
## [Step 5] Moved off the plugin, which is the one surface here with no
## automated coverage and which has now shipped three defects. The rule worth
## protecting is narrow: an empty snapshot must NOT produce an undo action.
## `restore_cells()` early-returns on `{}`, so committing one anyway leaves an
## entry in the editor's history that silently reverts nothing — and Section R
## cannot see that, because it drives snapshot/restore as pure functions and
## never asserts when they are called.
##
## Diagnosed live in the editor before this landed: the capture was in fact
## happening (`pre_drag=4`), so this is a guard against a fault that has not
## occurred, put on the tested side while the shape of it is still known.
func _test_gesture_lifecycle() -> void:
	var ov := MapOverlay.new()

	# No map: nothing to capture, and the caller must be told so.
	_chk("X.01 a gesture with no map reports nothing to capture",
			not ov.begin_edit_gesture())
	_chk("X.02 and leaves no gesture open", not ov.gesture_is_open())
	_chk("X.03 closing it yields an empty snapshot, not junk",
			ov.end_edit_gesture().is_empty())

	ov.map_data = _synth(4, 4, [], [], [])
	_chk("X.04 a gesture with a real map captures", ov.begin_edit_gesture())
	_chk("X.05 and reports itself open", ov.gesture_is_open())

	# The captured state must be the state BEFORE the paint, or undo returns to
	# the wrong place — the whole point of capturing at mouse-down.
	ov.edit_mode = MapOverlay.EditMode.COLLISION
	ov.paint_collision = 1
	ov.apply_edit(Vector2i(1, 1))
	var pre := ov.end_edit_gesture()
	_chk("X.06 the snapshot predates the paint",
			int(pre["collision"][1 * 4 + 1]) == 0)
	_chk("X.07 while the live map carries it",
			ov.map_data.collision_at(1, 1) == 1)
	_chk("X.08 closing clears the gesture", not ov.gesture_is_open())
	_chk("X.09 and closing twice does not resurrect it",
			ov.end_edit_gesture().is_empty())

	# Restoring that snapshot must actually undo the paint.
	ov.restore_cells(pre)
	_chk("X.10 restoring the captured snapshot reverts the paint",
			ov.map_data.collision_at(1, 1) == 0)

	# The save result must be readable after the fact: painting no longer
	# writes, so a deliberate save failing is the only way an edit is lost, and
	# the plugin reports on this rather than guessing.
	ov.save_map_data()
	_chk("X.11 a pathless MapData records its failure rather than hiding it",
			ov.last_save_error == ERR_FILE_BAD_PATH)

	# --- the dirty invariant, which is what makes stop-saving-on-paint safe ---
	# Every one of these was previously unobservable: while painting saved,
	# "has the file kept up" was never a question anything could ask.
	var md2 := _synth(4, 4, [], [], [])
	ov.map_data = md2
	ov.save_map_data()          # clears whatever the fixtures left set
	md2.resource_path = "user://_x_dirty_test.tres"
	_chk("X.12 a saved overlay starts clean",
			ov.save_map_data() == OK and not ov.has_unsaved_edits())

	ov.edit_mode = MapOverlay.EditMode.COLLISION
	ov.paint_collision = 1
	ov.apply_edit(Vector2i(2, 2))
	_chk("X.13 painting marks the file behind the view", ov.has_unsaved_edits())
	_chk("X.14 and saving clears it",
			ov.save_map_data() == OK and not ov.has_unsaved_edits())

	# An undo moves memory AWAY from disk just as a paint does, so it must
	# dirty rather than clear. Getting this backwards would show "saved" over a
	# view the file does not match — the exact divergence the removed
	# save-on-undo used to prevent by writing.
	ov.restore_cells(pre)
	_chk("X.15 an undo dirties rather than cleans", ov.has_unsaved_edits())

	# A failed save must NOT clear the flag, or the banner goes quiet while the
	# work is still only in memory — the worst of the three states.
	md2.resource_path = ""
	_chk("X.16 a failed save leaves the warning standing",
			ov.save_map_data() != OK and ov.has_unsaved_edits())

	ov.map_data = null
	ov.save_map_data()
	_chk("X.17 an absent MapData records its own distinct code",
			ov.last_save_error == ERR_UNCONFIGURED)

	# --- a paint that changes no VALUE still changes PROVENANCE ---
	# Found on a real editing pass, not by reading: 8 of 38 authored cells came
	# from repainting a value that was already correct. `set_collision` marks the
	# cell authored unconditionally, but `changed` asked only about the value and
	# the explicit bit — so those 8 flipped IMPORTED -> AUTHORED with the banner
	# off and no undo entry, and an AUTHORED cell is precisely what makes the
	# baker refuse a re-bake without `--force`.
	#
	# The fixture has to match REAL imported data, which `_synth` alone does not:
	# imported cells arrive explicit on BOTH attributes. Left at `_synth`'s empty
	# `attr_explicit`, the pre-existing `not ..._is_explicit` clause would catch
	# this by accident and the test would prove nothing.
	var md3 := _synth(4, 4, [], [], [])
	md3.attr_explicit.resize(md3.metatile.size())
	md3.attr_explicit.fill(MapData.ATTR_ALL_EXPLICIT)
	md3.resource_path = "user://_x_authored_test.tres"
	ov.map_data = md3
	ov.edit_mode = MapOverlay.EditMode.COLLISION
	ov.paint_collision = md3.collision_at(1, 1)   # deliberately the SAME value

	_chk("X.18 an imported cell starts unauthored", not md3.is_authored(1, 1))
	_chk("X.19 and out of bounds reports unauthored rather than erroring",
			not md3.is_authored(-1, 0))
	_chk("X.20 the fixture starts clean",
			ov.save_map_data() == OK and not ov.has_unsaved_edits())
	_chk("X.21 repainting the value already there still reports a change",
			ov.apply_edit(Vector2i(1, 1)))
	_chk("X.22 because it flipped provenance", md3.is_authored(1, 1))
	_chk("X.23 and that dirties the file like any other edit",
			ov.has_unsaved_edits())
	# The discriminator: without this the new clause could just be "always true".
	_chk("X.24 a second identical repaint is then a genuine no-op",
			not ov.apply_edit(Vector2i(1, 1)))

	DirAccess.remove_absolute(
			ProjectSettings.globalize_path("user://_x_dirty_test.tres"))
	DirAccess.remove_absolute(
			ProjectSettings.globalize_path("user://_x_authored_test.tres"))
	ov.free()


## Section W — the baker's own re-bake guard.
##
## [Rider A] The guard shipped verified by hand only: one field, one map, one
## direction. It is now the sole automated defender of hand-edited entity data,
## so its normalisation is driven directly against scratch strings — the same
## shape `_test_baked_scene_uids` uses to test UID preservation without running
## real bakes.
##
## The risk being tested is SCOPE. The normalisation strips per-save resource
## labels so the check does not fire on every map; strip one character too
## much and the guard goes quietly blind to a real change. W.04 is that case:
## this project has already eaten a break where a batch refactor renamed atlas
## outputs without updating consumers, which is precisely an `[ext_resource]`
## `path=` moving.
func _test_bake_guard() -> void:
	var baker: GDScript = load("res://scenes/overworld/map_baker.gd")

	const A := "[ext_resource type=\"Texture2D\" path=\"res://a.png\" id=\"1_7t5wp\"]\n" \
			+ "[node name=\"X\" type=\"Node2D\" unique_id=2044649524]\n" \
			+ "tile = SubResource(\"TileSetAtlasSource_vwmun\")\n" \
			+ "script = ExtResource(\"1_7t5wp\")\n" \
			+ "sight_range = 3\n"
	# Same content, every per-save label different — what a scratch bake of an
	# unchanged map actually produces.
	const B := "[ext_resource type=\"Texture2D\" path=\"res://a.png\" id=\"1_kcfnn\"]\n" \
			+ "[node name=\"X\" type=\"Node2D\" unique_id=99999]\n" \
			+ "tile = SubResource(\"TileSetAtlasSource_nmk7p\")\n" \
			+ "script = ExtResource(\"1_kcfnn\")\n" \
			+ "sight_range = 3\n"
	_chk("W.01 per-save labels alone do not count as a change",
			baker._normalise_text(A) == baker._normalise_text(B))

	# The case the guard exists for.
	var edited := A.replace("sight_range = 3", "sight_range = 9")
	_chk("W.02 a hand-tuned sight_range IS a change",
			baker._normalise_text(A) != baker._normalise_text(edited))
	_chk("W.03 and the report names the field rather than dumping the file",
			baker._first_differences(baker._normalise_text(A),
					baker._normalise_text(edited)).contains("sight_range"))

	# [Rider A] Scope check. `path=` sits on the same line as the id that gets
	# normalised, so an over-broad rule would swallow it.
	var repathed := A.replace("res://a.png", "res://renamed.png")
	_chk("W.04 a repointed ext_resource path is NOT masked by normalisation",
			baker._normalise_text(A) != baker._normalise_text(repathed))
	# A stem carries meaning even though the suffix does not: losing the whole
	# label would hide a resource being swapped for a different KIND.
	var restyled := A.replace("SubResource(\"TileSetAtlasSource_vwmun\")",
			"SubResource(\"TileSet_vwmun\")")
	_chk("W.05 a changed resource stem is not masked either",
			baker._normalise_text(A) != baker._normalise_text(restyled))
	# Property values must survive untouched — they can look like labels.
	const PROPS := "script_label = \"Route3_EventScript_Robin\"\n" \
			+ "graphics_id = \"OBJ_EVENT_GFX_LASS_FRLG\"\n" \
			+ "trainer_key = \"TRAINER_LASS_ROBIN_FRLG\"\n"
	_chk("W.06 real property strings are left alone by the label rules",
			baker._normalise_text(PROPS) == PROPS)
	# A node added by hand is the other thing a re-bake would eat.
	var extra := A + "[node name=\"MapOverlay\" type=\"Node2D\" parent=\".\"]\n"
	_chk("W.07 an added node counts as a change",
			baker._normalise_text(A) != baker._normalise_text(extra))
	_chk("W.08 an unchanged file reports no differences at all",
			baker._first_differences(baker._normalise_text(A),
					baker._normalise_text(B)) == "")


## Section O — the runtime clip math, and its fallback.
##
## The editor path no longer exercises clipping at all (it draws the whole map
## on purpose), so without this the runtime clip is code nothing checks. It is
## also where the original defect lived: an empty clip rect made the overlay
## render NOTHING, which reads as "the tool is broken" rather than "the tool
## drew zero cells".
func _test_clip_math() -> void:
	var ov := MapOverlay.new()
	ov.map_data = _synth(24, 20, [], [], [])

	# The override is the seam that lets a region be pinned without a camera.
	ov.visible_rect_override = Rect2i(4, 4, 6, 6)
	_chk("O.01 an override clips to exactly the requested region",
			ov._visible_cells() == Rect2i(4, 4, 6, 6))

	ov.visible_rect_override = Rect2i(20, 16, 40, 40)
	_chk("O.02 an override is clamped to the map, not trusted",
			ov._visible_cells() == Rect2i(20, 16, 4, 4))

	# Zero size means "unset", not "draw nothing" -- Rect2i() is the default.
	ov.visible_rect_override = Rect2i()
	_chk("O.03 a zero-size override falls through to the full map",
			ov._visible_cells() == Rect2i(0, 0, 24, 20))

	# An EXPLICIT off-map override is a request, not a lying transform, and is
	# honoured as one. The fallback below is deliberately not applied here --
	# conflating the two would make O.02's clamping meaningless.
	ov.visible_rect_override = Rect2i(100, 100, 5, 5)
	_chk("O.04 an explicit off-map override is honoured, not overridden",
			ov._visible_cells().size == Vector2i.ZERO)

	# The degenerate-fallback branch itself: a node in a real tree, parked far
	# enough away that the viewport maps to cells nowhere near the map, so the
	# intersection is empty. Drawing everything is wrong-but-visible; drawing
	# nothing reads as a broken tool, which is exactly how this first shipped.
	ov.visible_rect_override = Rect2i()
	add_child(ov)
	ov.position = Vector2(1_000_000, 1_000_000)
	_chk("O.05 a degenerate clip falls back to the full map, never to nothing",
			ov._visible_cells() == Rect2i(0, 0, 24, 20))
	remove_child(ov)

	ov.map_data = null
	_chk("O.06 no map data yields an empty rect rather than crashing",
			ov._visible_cells() == Rect2i())
	ov.map_data = null
	ov.free()


## Section P — the write half.
##
## Driven through `apply_edit()`, not `paint()`: paint()'s editor gate is
## absolute and a headless run is not the editor, so going through it could
## only ever assert that it refused. P.01 asserts exactly that, and everything
## below tests the dispatch underneath it.
func _test_write_half() -> void:
	var ov := MapOverlay.new()
	var md := _synth(4, 4, [], [], [])
	ov.map_data = md

	ov.edit_mode = MapOverlay.EditMode.COLLISION
	ov.paint_collision = 1
	_chk("P.01 paint() refuses outside the editor, whatever the mode",
			ov.paint(Vector2i(1, 1)) == false)
	_chk("P.02 and refusing leaves the cell untouched",
			md.collision_at(1, 1) == 0 and not md.collision_is_explicit(1, 1))

	# --- collision ---
	_chk("P.03 apply_edit sets collision", ov.apply_edit(Vector2i(1, 1)))
	_chk("P.04 the value landed", md.collision_at(1, 1) == 1)
	_chk("P.05 and is marked EXPLICIT, not a guess",
			md.collision_is_explicit(1, 1))
	# An IMPORTED cell is explicit on BOTH from the start -- its values came
	# from source and are authoritative, not a guess (§1.9). This assertion
	# used to claim the opposite and only passed because the fixture left
	# provenance empty, so _resize_attr_explicit's IMPORTED branch never ran.
	# The "one paint does not confirm the other attribute" proof that was
	# intended here lives at P.20, on a cell where it is actually meaningful.
	_chk("P.06 an IMPORTED cell was already explicit on both",
			md.elevation_is_explicit(1, 1))
	_chk("P.07 the cell is now AUTHORED",
			md.provenance[1 * 4 + 1] == MapData.Provenance.AUTHORED)
	_chk("P.08 a repeat of the same edit reports no change",
			ov.apply_edit(Vector2i(1, 1)) == false)

	# --- elevation ---
	ov.edit_mode = MapOverlay.EditMode.ELEVATION
	ov.paint_elevation = 4
	_chk("P.09 apply_edit sets elevation", ov.apply_edit(Vector2i(1, 1)))
	_chk("P.10 the value landed", md.elevation_at(1, 1) == 4)
	_chk("P.11 and is marked EXPLICIT", md.elevation_is_explicit(1, 1))
	_chk("P.12 both attributes confirmed clears needs_review",
			not md.needs_review(1, 1))

	# --- author-with-inherited-defaults: the 87%-right guess ---
	ov.edit_mode = MapOverlay.EditMode.AUTHOR
	# Fully confirmed, both attributes: set_collision alone would leave THIS
	# cell's elevation unconfirmed and it would count as review itself.
	md.set_collision(2, 3, 1)
	md.set_elevation(2, 3, 3)
	_chk("P.13 authoring a cell succeeds", ov.apply_edit(Vector2i(2, 2)))
	_chk("P.14 it is AUTHORED", md.provenance[2 * 4 + 2] == MapData.Provenance.AUTHORED)
	_chk("P.15 collision was INHERITED, not left at zero",
			md.collision_at(2, 2) == 1)
	_chk("P.16 but is NOT marked explicit -- it is a guess",
			not md.collision_is_explicit(2, 2))
	_chk("P.17 nor is elevation", not md.elevation_is_explicit(2, 2))
	_chk("P.18 so the cell reads as needing review", md.needs_review(2, 2))
	_chk("P.19 review_count sees it", ov.review_count() == 1)

	# Confirming one attribute is not enough; that is the whole point of
	# tracking them separately.
	ov.edit_mode = MapOverlay.EditMode.COLLISION
	ov.apply_edit(Vector2i(2, 2))
	_chk("P.20 confirming ONLY collision still leaves it under review",
			md.needs_review(2, 2) and ov.review_count() == 1)
	ov.edit_mode = MapOverlay.EditMode.ELEVATION
	ov.apply_edit(Vector2i(2, 2))
	_chk("P.21 confirming both clears it", ov.review_count() == 0)

	# --- guards ---
	ov.edit_mode = MapOverlay.EditMode.NONE
	_chk("P.22 EditMode.NONE is inert", ov.apply_edit(Vector2i(0, 0)) == false)
	ov.edit_mode = MapOverlay.EditMode.COLLISION
	_chk("P.23 an out-of-bounds cell is refused",
			ov.apply_edit(Vector2i(99, 99)) == false)
	_chk("P.24 cell_at maps a local point to its cell",
			ov.cell_at(Vector2(33.0, 17.0)) == Vector2i(2, 1))
	ov.map_data = null
	ov.free()


## Section Q — author, save, reload.
##
## The round trip is the claim that matters: an edit is worthless if it does
## not survive the file. Runs against a real .tres on disk via the same
## ResourceSaver/load pair the editor uses, not an in-memory copy.
func _test_author_save_reload() -> void:
	const PATH := "user://m27b_round_trip.tres"
	var ov := MapOverlay.new()
	var md := _synth(4, 4, [], [], [])
	ov.map_data = md

	ov.edit_mode = MapOverlay.EditMode.ELEVATION
	ov.paint_elevation = 5
	ov.apply_edit(Vector2i(3, 1))
	ov.edit_mode = MapOverlay.EditMode.AUTHOR
	ov.apply_edit(Vector2i(0, 0))
	var before := ov.review_count()

	_chk("Q.01 saving without a resource_path is refused, not silently lost",
			ov.save_map_data() == ERR_FILE_BAD_PATH)

	md.take_over_path(PATH)
	_chk("Q.02 save succeeds once there is a path", ov.save_map_data() == OK)
	_chk("Q.03 the file exists", FileAccess.file_exists(PATH))

	var reloaded: MapData = ResourceLoader.load(
			PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	_chk("Q.04 it reloads as a MapData", reloaded != null)
	if reloaded != null:
		_chk("Q.05 the confirmed elevation survived", reloaded.elevation_at(3, 1) == 5)
		_chk("Q.06 its EXPLICIT bit survived -- a value without it is a guess",
				reloaded.elevation_is_explicit(3, 1))
		# The AUTHORED cell is where "unconfirmed" is meaningful: an imported
		# one starts explicit on both, so asserting the absence there proved
		# nothing except that the fixture was unrealistic.
		_chk("Q.07 the AUTHORED cell round-trips with BOTH attributes unconfirmed",
				not reloaded.collision_is_explicit(0, 0)
				and not reloaded.elevation_is_explicit(0, 0))
		_chk("Q.08 AUTHORED provenance survived",
				reloaded.provenance[0] == MapData.Provenance.AUTHORED)
		_chk("Q.09 the unconfirmed count survived the round trip (%d)" % before,
				reloaded.review_cells().size() == before)
		_chk("Q.10 an untouched cell is still IMPORTED",
				reloaded.provenance[3 * 4 + 3] == MapData.Provenance.IMPORTED)
	ov.map_data = null
	ov.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## Section R — undo.
##
## The Ctrl+Z keystroke itself is an in-editor check, but the thing it depends
## on is testable here: `snapshot_cells()` / `restore_cells()` are literally
## what the undo action's do and undo methods call, with different data. If
## those are not symmetric, undo is broken no matter how the keystroke is
## wired.
##
## Undo was NOT wired when the write half first shipped. That is worse than it
## sounds: the editor's history stays live, so Ctrl+Z would have undone some
## unrelated earlier action while the paint remained applied.
func _test_undo_symmetry() -> void:
	var ov := MapOverlay.new()
	var md := _synth(4, 4, [], [], [])
	ov.map_data = md

	var probe: Dictionary = ov.snapshot_cells()
	_chk("R.01 a snapshot captures all four mutable arrays",
			probe.has("collision") and probe.has("elevation")
			and probe.has("provenance") and probe.has("attr_explicit"))
	# Packed arrays compare by VALUE in GDScript, so `snap != live` proves
	# nothing about aliasing. Mutate the live array and see if the snapshot
	# follows -- a plain element write, so no provenance/explicit side effects.
	md.collision[3 * 4 + 3] = 1
	_chk("R.02 the snapshot is a COPY -- a live reference would make undo a no-op",
			probe["collision"][3 * 4 + 3] == 0)

	var before: Dictionary = ov.snapshot_cells()

	# A drag's worth of edits, mixing both kinds.
	ov.edit_mode = MapOverlay.EditMode.COLLISION
	ov.paint_collision = 1
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
		ov.apply_edit(c)
	ov.edit_mode = MapOverlay.EditMode.AUTHOR
	ov.apply_edit(Vector2i(1, 1))
	var after: Dictionary = ov.snapshot_cells()
	var review_after := ov.review_count()
	_chk("R.03 the drag actually changed something", review_after > 0)

	# undo
	ov.restore_cells(before)
	_chk("R.04 undo restores the value", md.collision_at(0, 0) == 0)
	_chk("R.05 undo restores the EXPLICIT bit, not just the value",
			not md.collision_is_explicit(0, 0))
	_chk("R.06 undo restores provenance",
			md.provenance[0] == MapData.Provenance.IMPORTED)
	_chk("R.07 and therefore the unconfirmed-defaults counter",
			ov.review_count() == 0)

	# redo -- the same method, the other snapshot
	ov.restore_cells(after)
	_chk("R.08 redo re-applies the value", md.collision_at(0, 0) == 1)
	_chk("R.09 redo re-applies the explicit bit", md.collision_is_explicit(0, 0))
	_chk("R.10 redo restores the counter", ov.review_count() == review_after)

	# Round-tripping must be exactly reversible, not approximately.
	ov.restore_cells(before)
	ov.restore_cells(after)
	ov.restore_cells(before)
	_chk("R.11 repeated undo/redo does not drift",
			md.collision == before["collision"]
			and md.elevation == before["elevation"]
			and md.provenance == before["provenance"]
			and md.attr_explicit == before["attr_explicit"])

	_chk("R.12 an empty snapshot is ignored rather than wiping the map",
			_no_change_on_empty_restore(ov, md))
	ov.map_data = null
	ov.free()


func _no_change_on_empty_restore(ov: MapOverlay, md: MapData) -> bool:
	var keep := md.collision.duplicate()
	ov.restore_cells({})
	return md.collision == keep


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _warns_about(node: Node, needle: String) -> bool:
	for w in node.call("_get_configuration_warnings"):
		if str(w).findn(needle) != -1:
			return true
	return false
