class_name Bag
extends RefCounted

## [M27I I3] The player's bag: five pockets of stacked slots.
##
## Save state, so it lives on [OverworldSession] beside [FlagStore] rather than
## on a scene — a battle is a real scene swap and anything held on the overworld
## would be discarded with it. Shaped for M27L: plain ints and arrays, no node
## or Resource references to serialise around.
##
## ⚠️ **THIS IS A SLOT MODEL, NOT A `{item: count}` DICTIONARY,** and the
## difference is the entire reason `checkitemspace` exists as an opcode.
## Source's bag is a fixed array of slots per pocket; "is there room" is a
## question about SLOTS, not about a total. A dictionary would answer "yes"
## forever and make every bag-full branch in every script dead code.
##
## Capacities and the stack cap are source's own (`include/constants/global.h`,
## `include/constants/items.h`).

const MAX_STACK := 999

## Slots per pocket, indexed by the pocket ordinal.
const CAPACITY := {
	ItemManager.POCKET_ITEMS: 30,
	ItemManager.POCKET_POKE_BALLS: 16,
	ItemManager.POCKET_TM_HM: 64,
	ItemManager.POCKET_BERRIES: 46,
	ItemManager.POCKET_KEY_ITEMS: 30,
}

## ⚠️ TM/HM and BERRIES allow ONE stack per item and no more.
##
## `BagPocket_AddItem` splits these two out into their own branch: if a count
## cannot fit in a single slot it returns FALSE outright, where every other
## pocket happily spills into a second slot. Modelling all five the same way
## would silently let 1000 Berries into a pocket that must refuse them.
const SINGLE_STACK_POCKETS := [ItemManager.POCKET_TM_HM, ItemManager.POCKET_BERRIES]

## pocket ordinal -> Array of {"item": int, "count": int}. Empty slots are
## simply absent; `CAPACITY` bounds how many may exist.
var _pockets: Dictionary = {}


func _init() -> void:
	clear()


func clear() -> void:
	_pockets = {}
	for p in CAPACITY:
		_pockets[p] = []


## Which pocket an item belongs in, from its own identity record.
static func pocket_of(item_id: int) -> int:
	var info := PokemonRegistry.get_item_identity(item_id)
	if info.is_empty():
		return -1
	return int(info.get("pocket", ItemManager.POCKET_ITEMS))


## Live slots in a pocket, for the bag screen (I4) and for tests.
func slots(pocket: int) -> Array:
	return _pockets.get(pocket, [])


## How many of an item the bag holds, across every slot.
func count_of(item_id: int) -> int:
	var pocket := pocket_of(item_id)
	if pocket < 0:
		return 0
	var total := 0
	for slot in _pockets.get(pocket, []):
		if int(slot["item"]) == item_id:
			total += int(slot["count"])
	return total


## Does the bag hold at least `count` of this item?
func has_item(item_id: int, count: int = 1) -> bool:
	if item_id <= 0 or count <= 0:
		return false
	return count_of(item_id) >= count


## How many more of this item would fit.
##
## Existing part-full stacks count toward it, then whole empty slots — except
## in a single-stack pocket, where only one stack is ever available.
func free_space_for(item_id: int) -> int:
	var pocket := pocket_of(item_id)
	if pocket < 0:
		return 0
	var list: Array = _pockets.get(pocket, [])
	var cap := int(CAPACITY.get(pocket, 0))
	var room := 0
	var held := 0
	for slot in list:
		if int(slot["item"]) == item_id:
			held += 1
			room += MAX_STACK - int(slot["count"])
	if SINGLE_STACK_POCKETS.has(pocket):
		# One stack, ever: either the one that exists has headroom, or a single
		# empty slot could take a first stack.
		if held > 0:
			return room
		return MAX_STACK if list.size() < cap else 0
	room += maxi(0, cap - list.size()) * MAX_STACK
	return room


## Is there room for `count` of this item?
func has_space(item_id: int, count: int = 1) -> bool:
	if item_id <= 0 or count <= 0:
		return false
	return free_space_for(item_id) >= count


## Put items in. Returns false and changes NOTHING if they do not all fit.
##
## ⚠️ ALL-OR-NOTHING IS SOURCE'S OWN CONTRACT, not a simplification.
## `BagPocket_AddItem` computes into a scratch buffer and only writes the real
## slots once it knows the whole count fits. A partial add would leave a script
## that branched on failure holding some of an item it was told it did not get.
func add(item_id: int, count: int = 1) -> bool:
	if item_id <= 0 or count <= 0:
		return false
	if not has_space(item_id, count):
		return false
	var pocket := pocket_of(item_id)
	var list: Array = _pockets[pocket]
	var left := count
	# Top up existing stacks first, in slot order, exactly as source scans.
	for slot in list:
		if left <= 0:
			break
		if int(slot["item"]) != item_id:
			continue
		var room := MAX_STACK - int(slot["count"])
		var take := mini(room, left)
		slot["count"] = int(slot["count"]) + take
		left -= take
	while left > 0 and list.size() < int(CAPACITY.get(pocket, 0)):
		var take2 := mini(MAX_STACK, left)
		list.append({"item": item_id, "count": take2})
		left -= take2
	return left == 0


## Take items out. Returns false and changes NOTHING unless the whole count is
## present, mirroring `add`'s contract in the other direction.
func remove(item_id: int, count: int = 1) -> bool:
	if item_id <= 0 or count <= 0:
		return false
	if not has_item(item_id, count):
		return false
	var pocket := pocket_of(item_id)
	var list: Array = _pockets[pocket]
	var left := count
	for slot in list:
		if left <= 0:
			break
		if int(slot["item"]) != item_id:
			continue
		var take := mini(int(slot["count"]), left)
		slot["count"] = int(slot["count"]) - take
		left -= take
	# Emptied slots are removed, not left as zero-count holes — a zero slot
	# would still consume capacity and make the bag full of nothing.
	var kept: Array = []
	for slot in list:
		if int(slot["count"]) > 0:
			kept.append(slot)
	_pockets[pocket] = kept
	return true


## A plain snapshot for M27L to serialise, and to restore from.
func to_save() -> Dictionary:
	var out := {}
	for p in _pockets:
		var rows: Array = []
		for slot in _pockets[p]:
			rows.append({"item": int(slot["item"]), "count": int(slot["count"])})
		out[str(p)] = rows
	return out


func from_save(data: Dictionary) -> void:
	clear()
	for key in data:
		var p := int(key)
		if not _pockets.has(p):
			continue
		for slot in data[key]:
			_pockets[p].append({
				"item": int(slot.get("item", 0)),
				"count": int(slot.get("count", 0)),
			})
