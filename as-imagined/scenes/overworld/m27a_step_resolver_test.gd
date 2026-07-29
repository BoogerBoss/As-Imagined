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
const EXPECTED_TOTAL := 133

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
	if not ResourceLoader.exists(DATA):
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
	# added child is legitimate content, not a defect: this very map now carries
	# a hand-instanced MapOverlay. Forbidding extras would make every legitimate
	# edit look like a regression.
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

	# An imported cell is explicit on BOTH attributes: its values came from
	# source and are authoritative, not a guess.
	_chk("J.04 imported cells are explicit on collision", d.collision_is_explicit(0, 0))
	_chk("J.05 imported cells are explicit on elevation", d.elevation_is_explicit(0, 0))
	_chk("J.06 an imported cell therefore needs no review", not d.needs_review(0, 0))
	_chk("J.07 a fully imported map has no review backlog", d.review_cells().is_empty())

	# Now author one cell and half-decide it, which is the state the overlay
	# exists to make visible: painted, but its movement rules never confirmed.
	d.provenance[0] = MapData.Provenance.AUTHORED
	d.attr_explicit[0] = MapData.AttrFlag.ELEVATION_EXPLICIT  # collision left a guess
	_chk("J.08 a half-decided authored cell needs review", d.needs_review(0, 0))
	_chk("J.09 ...and reports which half is still a guess",
			d.elevation_is_explicit(0, 0) and not d.collision_is_explicit(0, 0))
	var review := d.review_cells()
	_chk("J.10 review_cells() finds exactly it",
			review.size() == 1 and review[0] == Vector2i(0, 0))

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
	const CHAIN := [
		"res://scripts/overworld/map_overlay.gd",
		"res://scripts/overworld/step_resolver.gd",
		"res://scripts/overworld/map_data.gd",
		"res://scripts/overworld/metatile_behavior.gd",
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
