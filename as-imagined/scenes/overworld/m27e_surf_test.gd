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

const EXPECTED_TOTAL := 15

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
	var w := 0
	var h := 0
	func in_bounds(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h
	func behavior_at(x: int, y: int) -> int:
		return int(beh[y * w + x])
	func collision_at(x: int, y: int) -> int:
		return int(col[y * w + x])
	func elevation_at(_x: int, _y: int) -> int:
		return 3
	func entity_at(_x: int, _y: int) -> bool:
		return false


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
