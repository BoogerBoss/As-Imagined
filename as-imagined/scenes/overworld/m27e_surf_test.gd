extends Node

## [M27E E1] Surfing — the traversal rules.
##
## The claims most worth pinning:
##
##   * surfing INVERTS the collision rule rather than relaxing it: water becomes
##     passable, everything else stays exactly as strict, so the blob cannot ride
##     through a wall;
##   * dismounting needs no rule of its own — the only non-water tile reachable
##     from water is one that was already walkable, i.e. the shore;
##   * `MB_SHALLOW_WATER` is NOT surfable, which source is explicit about and
##     which looks like an omission if you reason from the name.

const EXPECTED_TOTAL := 81

var _total := 0
var _failed := 0
var _gated := 0

## Behaviours, laid out as a tiny hand-built map: L land, W ocean, S shallow,
## X wall (land with a collision bit).
const W := MetatileBehavior.MB_OCEAN_WATER
const L := MetatileBehavior.MB_NORMAL
const S := MetatileBehavior.MB_SHALLOW_WATER


class Cells extends RefCounted:
	var beh: Array = []
	var col: Array = []
	## ⚠️ [M27E E1d] PER-CELL, and it was a flat 3 until a real map proved that
	## wrong. Kanto's water is elevation 1 against land's 3, so a uniform-3
	## fixture makes the elevation rule and the surfing rule agree on every cell
	## — and two competing rules that agree cannot tell each other apart. That
	## is precisely how E1a/E1b/E1c all shipped believing surfing worked while it
	## could not enter water on any real map. Empty still means 3 so the older
	## sections read unchanged.
	var elev: Array = []
	var occupied: Array = []
	var w := 0
	var h := 0
	func in_bounds(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h
	func behavior_at(x: int, y: int) -> int:
		return int(beh[y * w + x])
	func collision_at(x: int, y: int) -> int:
		return int(col[y * w + x])
	func elevation_at(x: int, y: int) -> int:
		var i := y * w + x
		return int(elev[i]) if i < elev.size() else 3
	func entity_at(x: int, y: int) -> bool:
		var i := y * w + x
		return bool(occupied[i]) if i < occupied.size() else false


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


## A 4x1 strip: land, ocean, ocean, land. Water carries a collision bit, exactly
## as the real imported maps do — which is what stops you on foot.
func _strip() -> StepResolver:
	var c := Cells.new()
	c.w = 4; c.h = 1
	c.beh = [L, W, W, L]
	c.col = [0, 1, 1, 0]
	return StepResolver.new(c)


func _ready() -> void:
	_test_on_foot()
	_test_surfing()
	_test_behaviour_set()
	_test_mount()
	_test_blob()
	_test_player_wiring()
	_test_shoreline_elevation()
	_test_ledge_hop()
	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27e_surf_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. on foot, nothing changed ---
func _test_on_foot() -> void:
	var r := _strip()
	var step := r.resolve(Vector2i(0, 0), StepResolver.Dir.EAST, 3)
	_chk("A.01 on foot, water is still impassable",
			int(step["outcome"]) == StepResolver.Outcome.IMPASSABLE)
	_chk("A.02 and the player does not move", step["to"] == Vector2i(0, 0))
	# ⚠️ The surfing flag must default OFF, or every existing map becomes
	# swimmable the moment this ships.
	_chk("A.03 surfing is OFF by default", not r.surfing)


## --- B. surfing ---
func _test_surfing() -> void:
	var r := _strip()
	r.surfing = true
	var onto := r.resolve(Vector2i(0, 0), StepResolver.Dir.EAST, 3)
	_chk("B.01 surfing makes water passable DESPITE its collision bit",
			int(onto["outcome"]) == StepResolver.Outcome.NONE
			and onto["to"] == Vector2i(1, 0))
	var across := r.resolve(Vector2i(1, 0), StepResolver.Dir.EAST, 3)
	_chk("B.02 and you can move water to water",
			int(across["outcome"]) == StepResolver.Outcome.NONE
			and across["to"] == Vector2i(2, 0))
	# ⚠️ DISMOUNT NEEDS NO RULE. The shore is ordinary walkable land, so the
	# ordinary rules already allow it — which is the whole design.
	var ashore := r.resolve(Vector2i(2, 0), StepResolver.Dir.EAST, 3)
	_chk("B.03 stepping ashore works with no dismount rule of its own",
			int(ashore["outcome"]) == StepResolver.Outcome.NONE
			and ashore["to"] == Vector2i(3, 0))

	# ⚠️ **THE GUARD THAT MATTERS: SURFING MUST NOT BECOME `no_collision`.**
	# A wall is land with a collision bit; if surfing merely skipped the bit,
	# the blob would ride straight through it.
	var c := Cells.new()
	c.w = 3; c.h = 1
	c.beh = [W, L, W]
	c.col = [1, 1, 1]          # middle tile is a WALL, not shore
	var r2 := StepResolver.new(c)
	r2.surfing = true
	var wall := r2.resolve(Vector2i(0, 0), StepResolver.Dir.EAST, 3)
	_chk("B.04 a WALL stays impassable while surfing — this is not no_collision",
			int(wall["outcome"]) == StepResolver.Outcome.IMPASSABLE)
	r2.no_collision = true
	_chk("B.05 whereas the real debug toggle DOES pass it, so the two differ",
			int(r2.resolve(Vector2i(0, 0), StepResolver.Dir.EAST, 3)["outcome"])
					== StepResolver.Outcome.NONE)

	# ⚠️ SHALLOW WATER IS WALKABLE ON FOOT AND MUST STAY SO. 747 cells over 16
	# Kanto maps; treating it as surfable would break every one of them.
	var c3 := Cells.new()
	c3.w = 2; c3.h = 1
	c3.beh = [L, S]
	c3.col = [0, 0]
	var r3 := StepResolver.new(c3)
	_chk("B.06 shallow water is walkable ON FOOT",
			int(r3.resolve(Vector2i(0, 0), StepResolver.Dir.EAST, 3)["outcome"])
					== StepResolver.Outcome.NONE)


## --- C. the behaviour set, taken from source rather than the names ---
func _test_behaviour_set() -> void:
	_chk("C.01 ocean, pond and fast water are surfable",
			MetatileBehavior.is_surfable(MetatileBehavior.MB_OCEAN_WATER)
			and MetatileBehavior.is_surfable(MetatileBehavior.MB_POND_WATER)
			and MetatileBehavior.is_surfable(MetatileBehavior.MB_FAST_WATER))
	_chk("C.02 waterfall and the four currents are surfable",
			MetatileBehavior.is_surfable(MetatileBehavior.MB_WATERFALL)
			and MetatileBehavior.is_surfable(MetatileBehavior.MB_NORTHWARD_CURRENT)
			and MetatileBehavior.is_surfable(MetatileBehavior.MB_SOUTHWARD_CURRENT)
			and MetatileBehavior.is_surfable(MetatileBehavior.MB_EASTWARD_CURRENT)
			and MetatileBehavior.is_surfable(MetatileBehavior.MB_WESTWARD_CURRENT))
	# ⚠️ THE ONE THAT LOOKS LIKE AN OMISSION AND IS NOT. Source does not flag
	# shallow water surfable — it is water you WADE through.
	_chk("C.03 shallow water is NOT surfable, which source is explicit about",
			not MetatileBehavior.is_surfable(MetatileBehavior.MB_SHALLOW_WATER))
	_chk("C.04 and ordinary land is not surfable",
			not MetatileBehavior.is_surfable(MetatileBehavior.MB_NORMAL)
			and not MetatileBehavior.is_surfable(MetatileBehavior.MB_TALL_GRASS))
	# The set is source's own, extracted rather than reasoned from names.
	_chk("C.05 the set is source's own size, not a hand-picked subset",
			MetatileBehavior.SURFABLE.size() == 17)
	# Kanto's own 8, so a later trim cannot quietly drop one that is in use.
	_chk("C.06 every behaviour Kanto actually uses is in it",
			MetatileBehavior.is_surfable(MetatileBehavior.MB_CYCLING_ROAD_WATER))


## --- D. [M27E E1b] mounting and dismounting ---
func _test_mount() -> void:
	var f := FlagStore.new()
	# ⚠️ FOUR INDEPENDENT REFUSALS, each with its own cause — a bool return would
	# make the caller re-derive which sentence to print.
	_chk("D.01 facing water without the badge refuses for the RIGHT reason",
			FieldMoves.can_mount(f, W, false) == FieldMoves.Mount.NO_BADGE)
	_chk("D.02 facing land refuses as NOT_WATER, a different cause",
			FieldMoves.can_mount(f, L, false) == FieldMoves.Mount.NOT_WATER)
	f.flag_set("FLAG_BADGE05_GET")
	_chk("D.03 the Soul Badge alone makes facing water mountable",
			FieldMoves.can_mount(f, W, false) == FieldMoves.Mount.OK)
	# ⚠️ AND ONLY THE SOUL BADGE. A fixture holding every badge could not tell
	# "reads the Surf badge" from "reads any badge".
	var f2 := FlagStore.new()
	f2.flag_set("FLAG_BADGE02_GET")   # Cut's badge, not Surf's
	_chk("D.04 a DIFFERENT badge does not unlock surfing",
			FieldMoves.can_mount(f2, W, false) == FieldMoves.Mount.NO_BADGE)
	_chk("D.05 already surfing is its own answer, not OK repeated",
			FieldMoves.can_mount(f, W, true) == FieldMoves.Mount.ALREADY_SURFING)
	# ⚠️ SHALLOW WATER IS NOT MOUNTABLE — it is walkable, so a prompt there would
	# offer to surf on a tile you can already stand on.
	_chk("D.06 shallow water offers no prompt, being walkable already",
			FieldMoves.can_mount(f, S, false) == FieldMoves.Mount.NOT_WATER)

	# ⚠️ DISMOUNT IS DECIDED BY WHERE YOU LANDED. Source has no "get off" key.
	_chk("D.07 landing ashore dismounts", FieldMoves.should_dismount(L, true))
	_chk("D.08 staying on water does not", not FieldMoves.should_dismount(W, true))
	_chk("D.09 and landing ashore on foot is not a dismount",
			not FieldMoves.should_dismount(L, false))

	# Source's own wording, verbatim — the first line reads like scene-setting
	# and is easy to drop.
	_chk("D.10 the prompt is source's own, both lines",
			FieldMoves.SURF_PROMPT.contains("dyed a deep blue")
			and FieldMoves.SURF_PROMPT.contains("Would you like to SURF?"))

	# ⚠️ THE STATE IS ON THE SESSION, NOT THE FIELD. A water encounter is a real
	# scene swap; surfing held on the overworld would clear on the first attack
	# and drop the player onto water on foot, refused in every direction.
	OverworldSession.reset()
	_chk("D.11 surfing starts off and lives on the session",
			not OverworldSession.surfing)
	OverworldSession.surfing = true
	OverworldSession.reset()
	_chk("D.12 and reset clears it, so a new game cannot inherit the water",
			not OverworldSession.surfing)


## --- E. [M27E E1c] the blob itself ---
##
## A dummy rider: a bare Node2D "player" with a 16x32-shaped body sprite at the
## same local position OverworldEntity.make_sprite uses, so attach() sees the
## real geometry without needing a map, a manager or a tree.
func _rider() -> Array:
	var player := Node2D.new()
	var body := Sprite2D.new()
	body.name = "Sprite"
	body.centered = false
	body.position = Vector2(0, -16)
	player.add_child(body)
	return [player, body]


func _detach_restores(_player: Node2D, body: Sprite2D, blob: SurfBlob) -> bool:
	blob.detach()
	return body.position.y == -16.0 and blob.get_parent() == null


func _test_blob() -> void:
	# ⚠️ **THE KANTO SHEET, 192x32 / 6 FRAMES — NOT the 3-frame Emerald
	# field-effect blob this first shipped with.** Rob's call from a live
	# playthrough. Both exist and are visibly different designs; only the
	# Emerald one has a consumer in source, so the frame mapping below is read
	# off the art rather than ported (see SurfBlob's own header).
	var tex := load(SurfBlob.SHEET) as Texture2D
	_chk("E.01 the blob sheet is the 6-frame Kanto asset (192x32)",
			tex != null and tex.get_width() == 192 and tex.get_height() == 32)

	var r := _rider()
	var blob := SurfBlob.attach(r[0], r[1], "SOUTH")
	_chk("E.02 SOUTH is frame 0, unflipped",
			blob.region_rect.position.x == 0 and not blob.flip_h)
	# Frames are PAIRS on this sheet — (facing, bob) — so the facings sit at
	# 0/2/4, not 0/1/2. Only the first of each pair is drawn; see the header on
	# why the spare bob frames are deliberately unused.
	blob.face("NORTH")
	_chk("E.03 NORTH is frame 2 (pairs, not singles)",
			blob.region_rect.position.x == 64)
	blob.face("WEST")
	_chk("E.04 WEST is frame 4, unflipped",
			blob.region_rect.position.x == 128 and not blob.flip_h)
	# ⚠️ EAST HAS NO FRAME OF ITS OWN — WEST mirrored, which IS source's own
	# convention (`sSurfBlobAnim_FaceEast` is `ANIMCMD_FRAME(2, .hFlip = TRUE)`)
	# and holds for the people sheets too.
	blob.face("EAST")
	_chk("E.05 EAST is WEST mirrored, not a fourth facing",
			blob.region_rect.position.x == 128 and blob.flip_h)

	# The bob: 0..-4px triangle, 32-frame period (UpdateBobbingEffect — y steps
	# every 4th frame, velocity flips every 16th, the flip AFTER the step).
	for i in 16:
		blob.advance_frame()
	_chk("E.06 the bob bottoms out at -4px on frame 16", blob.bob_y == -4)
	for i in 16:
		blob.advance_frame()
	_chk("E.07 and returns to 0 on frame 32 — a full period", blob.bob_y == 0)
	var lo := 0
	var hi := 0
	for i in 96:
		blob.advance_frame()
		lo = mini(lo, blob.bob_y)
		hi = maxi(hi, blob.bob_y)
	_chk("E.08 three more periods drift nowhere: the wave stays in [-4, 0]",
			lo == -4 and hi == 0 and blob.bob_y == 0)

	# ⚠️ NEAR A SHORE THE STEP MASK IS 7, NOT 3 — slower AND shallower, since
	# only frames 8 and 16 step before the flip. -2 at frame 16 is the
	# discriminator: the normal mask would read -4 here.
	var r2 := _rider()
	var slow := SurfBlob.attach(r2[0], r2[1], "SOUTH")
	slow.set_near_shore(true)
	for i in 16:
		slow.advance_frame()
	_chk("E.09 shore-adjacent bob is the slow mask: -2 at frame 16, not -4",
			slow.bob_y == -2)

	# ⚠️ BOB_PLAYER_AND_MON: the body rides the SAME offset
	# (`playerSprite->y2 = sprite->y2`), which is what makes it read as riding.
	_chk("E.10 the body bobs in lockstep with the blob",
			r2[1].position.y == -16.0 + float(slow.bob_y)
			and slow.position.y == slow.base_y + float(slow.bob_y))

	_chk("E.11 the blob draws BEHIND the body — first child",
			blob.get_index() == 0 and r[1].get_index() == 1)
	# Same placement formula as make_sprite applied to 32x32: bottoms aligned
	# with the 16x32 body's (both end at the cell's own bottom edge), 8px of
	# ripple either side.
	_chk("E.12 placement is cell-centred with bottoms aligned: (-8, -16)",
			blob.position.x == -8.0 and blob.base_y == -16.0)
	# Detach from a MID-BOB state, so "puts the body back" is a real claim —
	# detaching at bob 0 could not tell restore from never-moved.
	_chk("E.13 detach puts the body back on its feet and unparents the blob",
			slow.bob_y != 0 and _detach_restores(r2[0], r2[1], slow))

	# Wall clock: whole 1/60s steps only, remainder carried across ticks.
	var r3 := _rider()
	var wb := SurfBlob.attach(r3[0], r3[1], "SOUTH")
	wb.tick(1.5 / 60.0)
	var after_one_and_a_half: int = wb.bob_timer
	wb.tick(0.5 / 60.0)
	_chk("E.14 tick() carries the fractional remainder (1.5 frames -> 1, +0.5 -> 2)",
			after_one_and_a_half == 1 and wb.bob_timer == 2)

	# ⚠️ **THE COORDINATE-SPACE HAZARD, ON A PARENT WITH A REAL OFFSET.**
	# `stay_behind()` sets `top_level`, which makes `position` mean GLOBAL —
	# while `tick()` keeps writing `position.y = base_y + bob_y` from a base
	# captured in LOCAL space. Without rebasing, the first bob frame after the
	# switch snaps the blob toward the world origin. Invisible in section G,
	# whose chunk sits at (0, 0) so the two spaces coincide; this parent is
	# deliberately far from it.
	var r4 := _rider()
	add_child(r4[0])
	r4[0].position = Vector2(320, 480)
	var fb := SurfBlob.attach(r4[0], r4[1], "SOUTH")
	for i in 6:
		fb.advance_frame()
	var before := fb.global_position
	fb.stay_behind()
	for i in 40:
		fb.advance_frame()
	_chk("E.15 the blob stays put across the local->global switch",
			absf(fb.global_position.x - before.x) < 0.001
			and absf(fb.global_position.y - before.y) <= 8.0)
	_chk("E.16 and keeps bobbing while no longer driving the rider",
			fb.body == null and fb.top_level)
	r4[0].free()

	r[0].free()
	r2[0].free()
	r3[0].free()


## --- F. [M27E E1c] the player rides it ---
func _test_player_wiring() -> void:
	_chk("F.01 the graphics table declares GREEN_SURF as THREE frames — the pic"
			+ " table's own usage, not the sheet's 14",
			ObjectEventGraphics.frame_count("OBJ_EVENT_GFX_GREEN_SURF") == 3)
	_chk("F.02 and RED_SURF the same",
			ObjectEventGraphics.frame_count("OBJ_EVENT_GFX_RED_SURF") == 3)
	# ⚠️ THE LOAD-BEARING CONSEQUENCE: a 3-frame sheet cannot walk-cycle, so
	# WalkAnim's rest-only path IS source's facing-only surf behaviour. At 14
	# frames the cycle would index the sheet's unrelated RUN frames.
	var wa := WalkAnim.new()
	wa.setup("OBJ_EVENT_GFX_GREEN_SURF")
	_chk("F.03 so the surf sheet does not animate: facing frames only",
			not wa.animates())

	# A bare overworld instance, off-tree so _ready never runs — the project's
	# own bare-instance convention. The player is built by hand from the REAL
	# sheets, so the texture swap below is the real swap.
	var ow = load("res://scenes/overworld/overworld.gd").new()
	ow._player = Node2D.new()
	var body := OverworldEntity.make_sprite(ow.PLAYER_GRAPHICS_ID, "SOUTH")
	ow._player.add_child(body)

	OverworldSession.surfing = true
	ow._update_surf_visuals()
	_chk("F.04 mounting swaps the player's sheet to the surf art",
			body.texture != null
			and body.texture.resource_path.contains("surf_run"))
	_chk("F.05 and attaches the blob BEHIND the body",
			ow._surf_blob != null and is_instance_valid(ow._surf_blob)
			and ow._surf_blob.get_index() == 0 and body.get_index() == 1)

	ow._face_player(StepResolver.Dir.EAST)
	_chk("F.06 turning the player turns the blob with it (EAST = WEST mirrored)",
			ow._surf_blob.flip_h
			and ow._surf_blob.region_rect.position.x == 128)

	# ⚠️ RIDE ASHORE: the flag flips at step START. Mid-tween the blob must
	# STAY — removing it then reads as it sinking under a player still visibly
	# on the water — and the anim must keep driving the surf sheet, because the
	# surf texture is still on the sprite.
	ow._moving = true
	OverworldSession.surfing = false
	ow._update_surf_visuals()
	_chk("F.07 a dismount mid-step defers: blob still up, exit pending",
			ow._surf_blob != null and is_instance_valid(ow._surf_blob)
			and ow._surf_exit_pending)
	_chk("F.08 and the anim keys on the BLOB, not the flag — still the surf"
			+ " sheet while the glide finishes",
			ow._player_graphics_id() == ow.PLAYER_SURF_GRAPHICS_ID)

	ow._moving = false
	ow._update_surf_visuals()
	_chk("F.09 arriving ashore completes the exit: the blob is gone",
			ow._surf_blob == null)
	_chk("F.10 and the walking sheet is back",
			body.texture != null
			and not body.texture.resource_path.contains("surf_run")
			and ow._player_graphics_id() == ow.PLAYER_GRAPHICS_ID)

	ow._player.free()
	ow.free()
	OverworldSession.reset()
	_test_ride_out()


## --- H. [M27E E1d] the shoreline is an ELEVATION change ---
##
## ⚠️ **THIS SECTION EXISTS BECAUSE EVERY EARLIER SURF FIXTURE WAS FLAT.** Real
## Kanto water is elevation 1 and real land is 3, with no transition tiles
## between them — so every shoreline crossing is an elevation mismatch by the
## ordinary rule, and surfing could not enter or leave water on any real map.
## Source does not work around that: `CheckForObjectEventCollision`
## (`field_player_avatar.c:966`) REINTERPRETS the mismatch as
## `COLLISION_STOP_SURFING` when `CanStopSurfing` (`:1000`) agrees.
##
## A 3x1 strip with REAL elevations: land(3) | water(1) | water(1).
func _shore() -> StepResolver:
	var c := Cells.new()
	c.w = 3; c.h = 1
	c.beh = [L, W, W]
	c.col = [0, 1, 1]
	c.elev = [3, 1, 1]
	return StepResolver.new(c)


func _test_shoreline_elevation() -> void:
	# The fixture is not fiction: this is what the baked corridor actually holds.
	if ResourceLoader.exists("res://scenes/maps/PalletTown_Frlg.tscn"):
		var md := load("res://scenes/maps/PalletTown_Frlg_data.tres") as MapData
		var beach := md.elevation[16 * md.width + 7]
		var sea := md.elevation[17 * md.width + 7]
		_chk("H.01 real Pallet data: beach is elevation 3, the sea below it is 1",
				beach == 3 and sea == 1)
	else:
		_gated += 1

	var r := _shore()
	r.surfing = true
	# ⚠️ THE MOUNT IS NOT A STEP. The ordinary rules REFUSE land -> water, which
	# is why source jumps; if this ever starts returning NONE, the jump has been
	# quietly replaced by a rule source does not have.
	_chk("H.02 land -> water is REFUSED even while surfing — hence the jump",
			int(r.resolve(Vector2i(0, 0), StepResolver.Dir.EAST, 3)["outcome"])
					== StepResolver.Outcome.ELEVATION_MISMATCH)
	_chk("H.03 water -> water at the same elevation is an ordinary step",
			int(r.resolve(Vector2i(1, 0), StepResolver.Dir.EAST, 1)["outcome"])
					== StepResolver.Outcome.NONE)
	# THE HEADLINE: riding ashore is the mismatch, reinterpreted.
	var ashore := r.resolve(Vector2i(1, 0), StepResolver.Dir.WEST, 1)
	_chk("H.04 water -> land reports STOP_SURFING and ALLOWS the move",
			int(ashore["outcome"]) == StepResolver.Outcome.STOP_SURFING
			and ashore["to"] == Vector2i(0, 0))
	# ⚠️ GATED ON SURFING. A walker who somehow stood at elevation 1 must still
	# be blocked — otherwise this is a hole in the elevation rule for everyone,
	# not a surf mechanic.
	var r2 := _shore()
	_chk("H.05 and NOT while on foot: the same step is still a plain mismatch",
			int(r2.resolve(Vector2i(1, 0), StepResolver.Dir.WEST, 1)["outcome"])
					== StepResolver.Outcome.ELEVATION_MISMATCH)
	# CanStopSurfing requires ELEVATION_DEFAULT specifically, not "any different
	# elevation" — you cannot dismount onto a bridge deck or a ledge tier.
	var c3 := Cells.new()
	c3.w = 2; c3.h = 1
	c3.beh = [W, L]
	c3.col = [1, 0]
	c3.elev = [1, 4]
	var r3 := StepResolver.new(c3)
	r3.surfing = true
	_chk("H.06 dismounting onto elevation 4 is refused — it must be 3",
			int(r3.resolve(Vector2i(0, 0), StepResolver.Dir.EAST, 1)["outcome"])
					== StepResolver.Outcome.ELEVATION_MISMATCH)
	# CanStopSurfing also refuses an occupied landing tile.
	var c4 := Cells.new()
	c4.w = 2; c4.h = 1
	c4.beh = [W, L]
	c4.col = [1, 0]
	c4.elev = [1, 3]
	c4.occupied = [false, true]
	var r4 := StepResolver.new(c4)
	r4.surfing = true
	_chk("H.07 and refused when somebody is standing on the shore",
			int(r4.resolve(Vector2i(0, 0), StepResolver.Dir.EAST, 1)["outcome"])
					== StepResolver.Outcome.ELEVATION_MISMATCH)


## --- G. [M27E E1c] mounting RIDES OUT onto the water ---
##
## ⚠️ **THIS SECTION EXISTS BECAUSE ITS ABSENCE WAS FOUND BY INJECTION.** The
## first cut of this suite had no guard on the mount's own step: deleting
## `_try_step` from `_ride_out` left all 52 assertions green while leaving the
## player standing on the SHORE with a blob under them — a visibly broken
## mount. Rule (7)'s preventive form applied late: what does the plausible
## WRONG version do differently? It ends the mount on the land cell.
##
## Driven against a REAL MapManager holding a synthetic 3x1 strip
## (land, water, water), because the claim is about a real step resolving.
func _test_ride_out() -> void:
	var ow = load("res://scenes/overworld/overworld.gd").new()
	var mgr := MapManager.new()
	add_child(mgr)
	ow.manager = mgr

	var m := MapData.new()
	m.map_name = "surfstrip"
	m.width = 3
	m.height = 1
	# Water carries a collision bit exactly as the imported maps do — which is
	# what makes the step a real test of the surfing override rather than a
	# stroll across open ground.
	for i in 3:
		m.metatile.append(0)
		m.behavior.append(MetatileBehavior.MB_NORMAL if i == 0 else W)
		m.collision.append(0 if i == 0 else 1)
		# ⚠️ REAL ELEVATIONS — land 3, water 1 — matching the baked corridor.
		# This fixture was flat 3 in E1c, which is why G.03 passed while the
		# mount could not actually move the player on any real map.
		m.elevation.append(3 if i == 0 else 1)
		m.layer_type.append(0)
		m.provenance.append(MapData.Provenance.IMPORTED)
	var root := Node2D.new()
	add_child(root)
	mgr.register_chunk("surfstrip", m, root)
	ow._resolver = mgr.global_resolver()

	ow._cell = Vector2i(0, 0)
	ow._elev = 3
	ow._facing = StepResolver.Dir.EAST
	ow._player = Node2D.new()
	var body := OverworldEntity.make_sprite(ow.PLAYER_GRAPHICS_ID, "SOUTH")
	ow._player.add_child(body)
	root.add_child(ow._player)

	OverworldSession.reset()
	_chk("G.01 the fixture starts ASHORE, so landing on water is a real move",
			ow._cell == Vector2i(0, 0)
			and mgr.behavior_at(Vector2i(0, 0)) == MetatileBehavior.MB_NORMAL)
	ow._ride_out()
	_chk("G.02 mounting sets the session flag", OverworldSession.surfing)
	# THE GUARD THE INJECTION ASKED FOR.
	_chk("G.03 and RIDES OUT onto the water — the player does not stay ashore",
			ow._cell == Vector2i(1, 0)
			and mgr.behavior_at(ow._cell) == W)
	# ⚠️ **THE SHEET SWAPS AT THE START OF THE JUMP, THE BLOB WAITS FOR THE
	# LANDING.** Source does the same split: `ObjectEventSetGraphicsId(SURFING)`
	# runs before the jump, and the blob is created at the DESTINATION while the
	# player arcs onto it. Attaching it early would make it a child of the player
	# and hop the water along with them.
	_chk("G.04 mid-jump the surf sheet is on but the blob is NOT yet attached",
			body.texture != null
			and body.texture.resource_path.contains("surf_run")
			and ow._mount_jump_active and ow._surf_blob == null)
	# The landing, driven directly — `create_tween()` needs a live tree and this
	# fixture is deliberately off-tree, so the tween's own callback never fires.
	ow._finish_mount_jump(body, body.position.y)
	_chk("G.04b and the blob appears once the player lands on it",
			ow._surf_blob != null and is_instance_valid(ow._surf_blob)
			and not ow._mount_jump_active)
	# ⚠️ **AND THE JUMP IS LOAD-BEARING, NOT DECORATIVE.** The very step the
	# mount just performed is one the resolver REFUSES — so a mount routed
	# through `_try_step` (which E1c's was) cannot move the player at all. This
	# is the assertion a flat-elevation fixture could never express.
	_chk("G.05 and the ordinary rules would have REFUSED that same step",
			int(ow.resolve_step(Vector2i(0, 0), StepResolver.Dir.EAST, 3)["outcome"])
					== StepResolver.Outcome.ELEVATION_MISMATCH)

	# ⚠️ **THE DEFERRED DISMOUNT, DRIVEN THROUGH THE REAL STEP PATH.** E1c's own
	# F.07 set `_moving` by hand and so proved only that the mechanism worked in
	# isolation — in production the dismount check ran ABOVE the `_moving = true`
	# assignment, so the blob came off at step START and the deferral was
	# unreachable. Driving `_try_step` is what makes this a real guard.
	# ⚠️ **CLEARING `_moving` FIRST IS WHAT MAKES G.06 A GUARD AT ALL.** The mount
	# jump above sets it and clears it on tween completion, which never arrives
	# for an off-tree node — so it was still true here, the deferral fired for
	# that reason instead of the one under test, and moving `_moving = true` back
	# below the dismount check left G.06 GREEN. Caught by injection, not review.
	# Starting from false is the only state that can tell the orderings apart.
	ow._moving = false
	ow._try_step(StepResolver.Dir.WEST)
	_chk("G.06 riding ashore defers: mid-step the blob is STILL up",
			ow._surf_exit_pending
			and ow._surf_blob != null and is_instance_valid(ow._surf_blob))
	_chk("G.07 and the player is committed to the shore cell",
			ow._cell == Vector2i(0, 0) and not OverworldSession.surfing)

	# --- [M27E E1f] the four live-play findings ---
	#
	# ⚠️ **THE RIDER LIFT IS DERIVED, NOT TUNED.** FRLG ships a COMBINED 32x32
	# surfing sprite (`green_surf.png`) where character and blob are drawn as one
	# piece — the authored answer to how they sit together. Leaf's hat crown is at
	# y4 there and y12 on the standalone sheet, so the rider is exactly 8px low.
	# Reported from play as "the player sits too low on the blob".
	# ⚠️ Explicit types: `ow` is untyped, so `:=` cannot infer through it — this
	# project's own documented GDScript gotcha, and a parse error here takes the
	# WHOLE suite down (the script fails to load, nothing calls quit, the run hangs
	# to the timeout rather than reporting a failure).
	var surf_spr: Sprite2D = ow._player_sprite()
	_chk("G.08 the rider sits %dpx higher than a walker" % ow._SURF_RIDER_LIFT,
			surf_spr.position.y == float(SurfBlob.CELL
					- ObjectEventGraphics.frame_size(ow.PLAYER_SURF_GRAPHICS_ID).y
					- ow._SURF_RIDER_LIFT))

	# ⚠️ **THE BLOB MUST STOP FOLLOWING THE MOMENT THE DISMOUNT STARTS**, which is
	# source's `BOB_JUST_MON`: `UpdateBobbingEffect` runs `sprite->x =
	# playerSprite->x` only while NOT in that state. Reported from play as "the
	# blob follows the player onto land for half a grid space".
	var blob: SurfBlob = ow._surf_blob
	var bx: float = blob.global_position.x
	var by: float = blob.global_position.y
	ow._moving = false
	ow._try_step(StepResolver.Dir.WEST)
	_chk("G.09 the dismount detaches the blob from the player's motion",
			blob.top_level and is_instance_valid(blob))
	# Drive the bob on: the freeze must survive it. `top_level` alone does not —
	# `position` becomes GLOBAL while the bob still writes a LOCAL base, which
	# snaps the blob across the map on its first frame after the switch.
	for i in 40:
		blob.advance_frame()
	# ⚠️ **THIS FIXTURE CANNOT SEE THE VERTICAL HALF, AND SAYS SO.** The real
	# hazard is `top_level` turning `position` into GLOBAL space while the bob
	# keeps writing a LOCAL base — but this chunk sits at origin (0, 0) on a
	# 3x1 strip, so local and global Y are EQUAL here and the correct and broken
	# implementations agree. Both an x-only and an x+y assertion passed with the
	# rebase deleted. The coordinate-space claim is pinned by E.15/E.16 instead,
	# on a rider whose parent has a real offset. Rule (15): pin what IS
	# observable and state what rests elsewhere.
	_chk("G.10 and it does not drift horizontally after the space change",
			absf(blob.global_position.x - bx) < 0.001
			and absf(blob.global_position.y - by) <= 8.0)
	_chk("G.11 while still bobbing — BOB_JUST_MON keeps the wave running",
			blob.bob_y != 0)
	_chk("G.12 and it no longer drives the rider's own y",
			blob.body == null)

	ow._player.free()
	ow.free()
	root.free()
	mgr.free()
	OverworldSession.reset()


## --- I. the ledge hop: pace and shadow ---
##
## [Bugfix, live-reported: "ledge jump doesn't feel canon — speed is fast" and
## "there is no shadow below player"]
##
## ⚠️ **A LEDGE HOP IS TWO TILES AT WALKING PACE.** Source:
## `distanceToTime[JUMP_DISTANCE_FAR] = 32` frames
## (`DoJumpSpriteMovement`, `event_object_movement.c:10916`) against a walk's 16
## per tile. The old value covered BOTH tiles in 0.26s — 0.13s each, ~1.7x too
## fast — which is why it read as wrong without looking obviously broken.
##
## ⚠️ **THE SHADOW IS LEDGE-ONLY, AND THE ASYMMETRY IS SOURCE'S.**
## `InitJumpRegular` ends with `DoShadowFieldEffect`; the surf mount/dismount
## goes through `InitJumpSpecial`, which does not. Giving `_add_jump_arc` a
## shadow in general would be the tidy-looking mistake, so I.05 pins the
## negative case as hard as I.03 pins the positive one.
func _test_ledge_hop() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	add_child(ow)

	# The RATIO is the claim, not the constant — a retuned walk must carry the
	# hop with it. Asserting 0.4467 directly would pass while the invariant rots.
	_chk("I.01 a hop is exactly two walk-steps of time",
			is_equal_approx(ow._LEDGE_HOP_SECONDS, ow._WALK_STEP_SECONDS * 2.0))
	# ⚠️ Guards the regression directly: the retired constant was 0.26, and any
	# value not derived from the walk lands back near it.
	_chk("I.02 and is therefore slower than the old hardcoded 0.26",
			ow._LEDGE_HOP_SECONDS > 0.26)

	_chk("I.03 no shadow while simply standing", ow._jump_shadow == null)

	# ⚠️ **THE BODY SPRITE IS REAL, AND WITHOUT IT I.05 IS VACUOUS.** Injecting
	# "parent the shadow to the arcing sprite instead" PASSED against an earlier
	# draft of this fixture, because with no sprite `_player_sprite()` returns
	# null and the broken code fell back to the player node — the two competing
	# implementations agreed, so the assertion could not tell them apart. A real
	# `make_sprite` child makes them disagree. (Same trap as G.03's own flat
	# elevations, recorded above.)
	var pnode := Node2D.new()
	ow.add_child(pnode)
	ow._player = pnode
	var body := OverworldEntity.make_sprite(ow.PLAYER_GRAPHICS_ID, "SOUTH")
	pnode.add_child(body)
	_chk("I.03b the fixture really has a body sprite distinct from the node",
			ow._player_sprite() != null and ow._player_sprite() != ow._player)

	ow._spawn_jump_shadow()
	var sh: Sprite2D = ow._jump_shadow
	_chk("I.04 a hop puts a real shadow sprite under the player",
			sh != null and is_instance_valid(sh) and sh.texture != null)
	# ⚠️ **THE PROPERTY THAT MAKES IT A JUMP SHADOW.** Source sets the shadow's
	# y from the linked sprite's BASE y, never its `y2` arc — the body rises and
	# the shadow does not. Here that falls out of parenting to the player NODE,
	# which tweens along the ground, while `_add_jump_arc` drives the BODY
	# SPRITE (a separate node, pinned by sections E-G above). If this ever
	# reparents onto the sprite, the shadow starts flying with the player.
	_chk("I.05 parented to the ground-travelling player node, NOT the arcing sprite",
			sh != null and sh.get_parent() == ow._player
			and sh.get_parent() != ow._player_sprite())
	# Half a tile right, and behind the body — the same two corrections
	# `EmoteIcon` documents for its own overlay.
	_chk("I.06 offset half a tile right and drawn behind the body",
			sh != null and is_equal_approx(sh.position.x, float(OverworldEntity.CELL) * 0.5)
			and sh.z_index < 0 and sh.centered)
	ow._clear_jump_shadow()
	_chk("I.07 and it is gone once the hop lands", ow._jump_shadow == null)

	ow.queue_free()
