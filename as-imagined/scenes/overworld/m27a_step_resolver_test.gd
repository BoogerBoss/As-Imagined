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

	print("m27a_step_resolver_test: %d/%d passed" % [_passed, _total])
	if OS.has_feature("headless") or "--autoplay" in OS.get_cmdline_args():
		get_tree().quit()


# --- A. the imported artifact itself ---------------------------------------
func _test_import_integrity() -> void:
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
	_chk("H.01 baked scene exists", ResourceLoader.exists(SCENE))
	_chk("H.02 baked MapData resource exists", ResourceLoader.exists(DATA))
	if not ResourceLoader.exists(DATA):
		return

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
	_chk("H.13 non-drawn events live in a separate trailing container",
			names.size() == 6 and names[5] == "Triggers")
	root.free()


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
		if t.trainer_key == "TRAINER_LASS_ROBIN":
			robin = t
	_chk("I.07 Robin resolved to a real trainer key", robin != null)
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
		# TRIPWIRE, not a regression: a valid key that resolves to nothing,
		# because the 624 Kanto trainers in trainers_frlg.party were never
		# converted. I.14/I.15 exist so that gap cannot close silently.
		# ⚠ CONVERTING THE ROSTER IS EXPECTED TO FLIP BOTH. Invert them then
		# (assert the key resolves and no warning fires) -- do not "fix" them
		# by chasing a bug. See docs/overworld_scope.md §32.
		_chk("I.14 the Kanto roster is still unconverted (see scope §32)",
				not robin.has_registry_entry())
		_chk("I.15 that unresolved key raises a configuration warning",
				_warns_about(robin, "trainers_frlg"))

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


func _warns_about(node: Node, needle: String) -> bool:
	for w in node.call("_get_configuration_warnings"):
		if str(w).findn(needle) != -1:
			return true
	return false
