extends Node

## [M27I I3] The bag and the item opcodes.
##
## The bag is a SLOT model, not a {item: count} dictionary, and that is the
## whole reason `checkitemspace` exists as an opcode: "is there room" is a
## question about slots. A dictionary would answer yes forever and make every
## bag-full branch in every script dead code.

const EXPECTED_TOTAL := 52

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _src(ops: Dictionary, texts: Dictionary = {}) -> ScriptVM.ScriptSource:
	var s := ScriptVM.ScriptSource.new()
	s.ops_by_label = ops
	s.texts = texts
	return s


func _op(name: String, args: Array = []) -> Dictionary:
	return {"op": name, "args": args}


func _id(c: String) -> int:
	return PokemonRegistry.item_id_of(c)


func _ready() -> void:
	_test_capacity()
	_test_add_remove()
	_test_single_stack()
	_test_opcodes()
	_test_obtain()
	_test_find_item_removes_object()
	_test_save_shape()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27i_bag_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. capacities, against source ---
func _test_capacity() -> void:
	_chk("A.01 stack cap is source's own", Bag.MAX_STACK == 999)
	_chk("A.02 per-pocket slot counts are source's own",
			int(Bag.CAPACITY[ItemManager.POCKET_ITEMS]) == 30
			and int(Bag.CAPACITY[ItemManager.POCKET_POKE_BALLS]) == 16
			and int(Bag.CAPACITY[ItemManager.POCKET_TM_HM]) == 64
			and int(Bag.CAPACITY[ItemManager.POCKET_BERRIES]) == 46
			and int(Bag.CAPACITY[ItemManager.POCKET_KEY_ITEMS]) == 30)
	_chk("A.03 an item routes to its own pocket",
			Bag.pocket_of(_id("ITEM_POTION")) == ItemManager.POCKET_ITEMS
			and Bag.pocket_of(_id("ITEM_POKE_BALL")) == ItemManager.POCKET_POKE_BALLS
			and Bag.pocket_of(_id("ITEM_TM39")) == ItemManager.POCKET_TM_HM)
	_chk("A.04 an unknown item has no pocket", Bag.pocket_of(999999) == -1)


## --- B. add / remove, and the all-or-nothing contract ---
func _test_add_remove() -> void:
	var b := Bag.new()
	var potion := _id("ITEM_POTION")
	_chk("B.01 a new bag is empty", b.count_of(potion) == 0)
	_chk("B.02 adding succeeds", b.add(potion, 3))
	_chk("B.03 and the count is right", b.count_of(potion) == 3)
	_chk("B.04 adding again stacks rather than opening a slot",
			b.add(potion, 2) and b.count_of(potion) == 5
			and b.slots(ItemManager.POCKET_ITEMS).size() == 1)
	_chk("B.05 has_item respects the count",
			b.has_item(potion, 5) and not b.has_item(potion, 6))
	_chk("B.06 removing takes the right amount",
			b.remove(potion, 2) and b.count_of(potion) == 3)
	# ⚠️ ALL-OR-NOTHING. Source computes into a scratch buffer and only writes
	# once the whole count fits; a partial remove would leave a script that
	# branched on failure holding some of an item it was told it kept.
	_chk("B.07 removing more than held changes NOTHING",
			not b.remove(potion, 99) and b.count_of(potion) == 3)
	_chk("B.08 removing all empties the slot rather than leaving a zero",
			b.remove(potion, 3) and b.slots(ItemManager.POCKET_ITEMS).is_empty())
	# A zero-count slot would still consume capacity — a bag full of nothing.
	_chk("B.09 ITEM_NONE is refused", not b.add(0, 1) and not b.has_space(0, 1))
	_chk("B.10 a zero or negative count is refused",
			not b.add(potion, 0) and not b.remove(potion, -1))

	# Spilling across slots, which is what makes this a slot model.
	var b2 := Bag.new()
	_chk("B.11 one stack holds up to the cap", b2.add(potion, Bag.MAX_STACK)
			and b2.slots(ItemManager.POCKET_ITEMS).size() == 1)
	_chk("B.12 past the cap it opens a second slot",
			b2.add(potion, 1) and b2.slots(ItemManager.POCKET_ITEMS).size() == 2)

	# Filling the pocket: the case checkitemspace exists for.
	var b3 := Bag.new()
	var cap := int(Bag.CAPACITY[ItemManager.POCKET_ITEMS])
	var filled := b3.add(potion, Bag.MAX_STACK * cap)
	_chk("B.13 a pocket can be filled exactly", filled
			and b3.slots(ItemManager.POCKET_ITEMS).size() == cap)
	_chk("B.14 and then genuinely reports no room",
			not b3.has_space(potion, 1) and b3.free_space_for(potion) == 0)
	_chk("B.15 an over-capacity add is refused and changes nothing",
			not b3.add(potion, 1) and b3.count_of(potion) == Bag.MAX_STACK * cap)

	# ⚠️ THE PARTIAL-ADD CASE, and B.15 does NOT cover it. An exactly-full bag
	# cannot overflow anyway — the fill loop simply finds no room — so removing
	# the up-front space check still leaves B.15 green. The real hazard is a bag
	# with a PART-FULL stack and no free slot: a naive add tops that stack up,
	# then discovers it cannot place the rest, and returns false having already
	# banked some. The script branches on "you did not get it" while holding
	# several. Found by injecting the mistake and watching B.15 survive it.
	var b4 := Bag.new()
	b4.add(potion, Bag.MAX_STACK * (cap - 1))   # cap-1 full slots
	b4.add(potion, 500)                          # one part-full slot -> pocket full
	var before := b4.count_of(potion)
	var partial := b4.add(potion, 1000)          # 499 would fit, 501 would not
	_chk("B.16 a partly-fitting add banks NOTHING",
			not partial and b4.count_of(potion) == before)


## --- C. the single-stack pockets ---
func _test_single_stack() -> void:
	# ⚠️ TM/HM and BERRIES take ONE stack per item and refuse more.
	# `BagPocket_AddItem` branches these two out specifically; treating all five
	# alike would let 1000 Berries into a pocket that must say no.
	var b := Bag.new()
	var berry := _id("ITEM_CHESTO_BERRY")
	_chk("C.01 a berry is in the berries pocket",
			Bag.pocket_of(berry) == ItemManager.POCKET_BERRIES)
	_chk("C.02 one full stack fits", b.add(berry, Bag.MAX_STACK))
	_chk("C.03 but a second stack of the SAME berry is refused",
			not b.add(berry, 1) and b.count_of(berry) == Bag.MAX_STACK)
	_chk("C.04 and free space reports zero, not a whole empty slot",
			b.free_space_for(berry) == 0)
	# A DIFFERENT berry still gets its own slot -- the limit is per item.
	var other := _id("ITEM_RAZZ_BERRY")
	_chk("C.05 a different berry still fits", b.add(other, 5)
			and b.count_of(other) == 5)
	# Contrast: an ordinary pocket spills happily.
	var b2 := Bag.new()
	var potion := _id("ITEM_POTION")
	_chk("C.06 an ordinary pocket DOES take a second stack",
			b2.add(potion, Bag.MAX_STACK) and b2.add(potion, 1))


## --- D. the four primitives as opcodes ---
func _test_opcodes() -> void:
	var flags := FlagStore.new()
	var bag := Bag.new()
	var vm := ScriptVM.new(_src({
		"A": [_op("additem", ["ITEM_POTION", "2"]),
			_op("checkitem", ["ITEM_POTION", "2"]),
			_op("end")],
	}), flags)
	vm.bag = bag
	vm.start("A")
	vm.step()
	_chk("D.01 additem puts items in the real bag", bag.count_of(_id("ITEM_POTION")) == 2)
	_chk("D.02 and reports success in VAR_RESULT", flags.var_get("VAR_RESULT") == 1)
	vm.step()
	_chk("D.03 checkitem reports what is held", flags.var_get("VAR_RESULT") == 1)

	# ⚠️ VARIABLE ARGUMENTS. 64 corpus args are variables, and they cluster in
	# exactly these give-and-branch chains.
	flags.var_set("VAR_0x8009", _id("ITEM_POKE_BALL"))
	flags.var_set("VAR_0x800A", 3)
	var vm2 := ScriptVM.new(_src({
		"A": [_op("additem", ["VAR_0x8009", "VAR_0x800A"]), _op("end")],
	}), flags)
	vm2.bag = bag
	vm2.start("A")
	vm2.step()
	_chk("D.04 an item AND a count held in variables both resolve",
			bag.count_of(_id("ITEM_POKE_BALL")) == 3)

	# checkitemspace on a full pocket must report false -- the branch Brock's
	# own chain takes.
	var full := Bag.new()
	full.add(_id("ITEM_POTION"), Bag.MAX_STACK * int(Bag.CAPACITY[ItemManager.POCKET_ITEMS]))
	var vm3 := ScriptVM.new(_src({
		"A": [_op("checkitemspace", ["ITEM_POTION", "1"]), _op("end")],
	}), flags)
	vm3.bag = full
	vm3.start("A")
	vm3.step()
	_chk("D.05 checkitemspace reports FALSE when the pocket is full",
			flags.var_get("VAR_RESULT") == 0)

	# removeitem's failure must not half-empty the bag.
	var vm4 := ScriptVM.new(_src({
		"A": [_op("removeitem", ["ITEM_POTION", "99"]), _op("end")],
	}), flags)
	var b4 := Bag.new()
	b4.add(_id("ITEM_POTION"), 5)
	vm4.bag = b4
	vm4.start("A")
	vm4.step()
	_chk("D.06 a failed removeitem reports FALSE and keeps the items",
			flags.var_get("VAR_RESULT") == 0 and b4.count_of(_id("ITEM_POTION")) == 5)

	# checkitemtype writes the POCKET, not a boolean.
	var vm5 := ScriptVM.new(_src({
		"A": [_op("checkitemtype", ["ITEM_TM39"]), _op("end")],
	}), flags)
	vm5.start("A")
	vm5.step()
	_chk("D.07 checkitemtype writes the pocket ordinal",
			flags.var_get("VAR_RESULT") == ItemManager.POCKET_TM_HM)


## --- E. giveitem: STD_OBTAIN_ITEM's decision structure ---
func _test_obtain() -> void:
	if not FileAccess.file_exists("res://data/map_texts.json"):
		_gated += 9
		return
	var texts: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())
	var src := ScriptVM.ScriptSource.new()
	src.texts = texts
	src.ops_by_label = {
		"GIVE": [_op("giveitem", ["ITEM_TM39"]), _op("end")],
		"GIVEN": [_op("giveitem", ["ITEM_POTION", "3"]), _op("end")],
		"FIND": [_op("finditem", ["ITEM_POTION"]), _op("end")],
	}
	var flags := FlagStore.new()
	var bag := Bag.new()
	var vm := ScriptVM.new(src, flags)
	vm.bag = bag
	vm.start("GIVE")
	vm.step()
	_chk("E.01 giveitem puts the item in the bag", bag.count_of(_id("ITEM_TM39")) == 1)
	_chk("E.02 and reports success", flags.var_get("VAR_RESULT") == 1)
	# It PAUSES for its message, like `message` does -- a giveitem that ran
	# silently would skip the whole "Obtained the ..." beat.
	_chk("E.03 it pauses on WAIT_MESSAGE", vm.pause_reason == ScriptVM.Pause.WAIT_MESSAGE)
	var page := vm.buffers.expand(vm.pending_pages[0])
	_chk("E.04 the page is source's own obtained-item line, expanded",
			page == "Obtained the TM39!")
	var page2 := vm.buffers.expand(vm.pending_pages[1])
	_chk("E.05 and names the right POCKET", page2.contains("TMs & HMs"))

	# The plural branch: `compare VAR_0x8001, TRUE` picks a different string.
	var vm2 := ScriptVM.new(src, FlagStore.new())
	vm2.bag = Bag.new()
	vm2.start("GIVEN")
	vm2.step()
	_chk("E.06 a count above one takes the plural line",
			vm2.buffers.expand(vm2.pending_pages[0]) == "Obtained 3 Potions!")

	# The failure branch -- what Brock's chain actually guards against.
	var vm3 := ScriptVM.new(src, FlagStore.new())
	var full := Bag.new()
	full.add(_id("ITEM_POTION"), Bag.MAX_STACK * int(Bag.CAPACITY[ItemManager.POCKET_ITEMS]))
	vm3.bag = full
	vm3.start("GIVEN")
	vm3.step()
	_chk("E.07 a full bag reports failure", vm3._flags.var_get("VAR_RESULT") == 0)
	_chk("E.08 and shows the bag-full line rather than an obtained one",
			vm3.buffers.expand(vm3.pending_pages[0]).contains("BAG is full"))

	# finditem uses its own wording -- the item-ball flavour, not a gift.
	var vm4 := ScriptVM.new(src, FlagStore.new())
	vm4.bag = Bag.new()
	vm4.start("FIND")
	vm4.step()
	_chk("E.09 finditem uses the FOUND wording, not OBTAINED",
			vm4.buffers.expand(vm4.pending_pages[0]).contains("found one Potion"))


## --- G. the ball removes itself (finditem only) ---
##
## Driven against the REAL compiled forest script, because the whole point is
## that the map script does NOT contain the removal -- asserting it on a
## fixture would prove nothing about where the behaviour has to live.
func _test_find_item_removes_object() -> void:
	if not FileAccess.file_exists("res://data/map_scripts.json"):
		_gated += 6
		return
	var ops: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var label := "ViridianForest_EventScript_ItemAntidote"
	if not ops.has(label):
		_gated += 6
		return
	var texts: Dictionary = {}
	if FileAccess.file_exists("res://data/map_texts.json"):
		texts = JSON.parse_string(
				FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())
	var src := ScriptVM.ScriptSource.new()
	src.ops_by_label = ops
	src.texts = texts

	# The premise: nothing in the ball's own script hides it. If this ever
	# fails, the removal moved into the corpus and this whole section is moot.
	var names := PackedStringArray()
	for o: Dictionary in ops[label]:
		names.append(str(o.get("op", "")))
	_chk("G.01 the real ball script never removes anything itself (%s)"
			% ", ".join(names), not names.has("removeobject"))

	var vm := ScriptVM.new(src, FlagStore.new())
	vm.bag = Bag.new()
	vm.start(label)
	vm.step()
	var removes := vm.pending_object_ops.filter(
			func(o: Dictionary) -> bool: return str(o.get("op", "")) == "remove")
	_chk("G.02 picking it up queues a removal", removes.size() == 1)
	# `VAR_LAST_TALKED` is not decoration: item balls carry NO `local_id`
	# anywhere in the corpus, so it is the only token that can address one.
	# `ScriptDriver.resolve_movement_entity` maps it to `vm.subject`.
	_chk("G.03 targeted at VAR_LAST_TALKED, the only handle a ball has",
			removes.size() == 1 and str(removes[0].get("target", "")) == "VAR_LAST_TALKED")

	# ⚠️ THE DISCRIMINATOR. `giveitem` shares `_obtain_item`, and source keeps
	# it in a standard script that removes NOTHING. Hoisting the removal out of
	# the `finditem` check deletes every NPC who hands the player an item.
	var gsrc := ScriptVM.ScriptSource.new()
	gsrc.texts = texts
	gsrc.ops_by_label = {"GIVE": [_op("giveitem", ["ITEM_POTION"]), _op("end")]}
	var gvm := ScriptVM.new(gsrc, FlagStore.new())
	gvm.bag = Bag.new()
	gvm.start("GIVE")
	gvm.step()
	_chk("G.04 giveitem removes NOTHING (a gift-giver must survive)",
			gvm.pending_object_ops.filter(func(o: Dictionary) -> bool:
					return str(o.get("op", "")) == "remove").is_empty())
	_chk("G.05 and it really did give the item (G.04 is not vacuous)",
			gvm.bag.count_of(_id("ITEM_POTION")) == 1)

	# Success branch only -- source gates on `VAR_0x8007 == TRUE`, so a full
	# bag leaves the ball standing and you can come back for it.
	var fvm := ScriptVM.new(src, FlagStore.new())
	var full := Bag.new()
	full.add(_id("ITEM_ANTIDOTE"), Bag.MAX_STACK * int(Bag.CAPACITY[ItemManager.POCKET_ITEMS]))
	fvm.bag = full
	fvm.start(label)
	fvm.step()
	_chk("G.06 a full bag leaves the ball standing",
			fvm.pending_object_ops.filter(func(o: Dictionary) -> bool:
					return str(o.get("op", "")) == "remove").is_empty())


## --- F. the save shape M27L will serialise ---
func _test_save_shape() -> void:
	var b := Bag.new()
	b.add(_id("ITEM_POTION"), 4)
	b.add(_id("ITEM_TM39"), 1)
	var saved := b.to_save()
	var b2 := Bag.new()
	b2.from_save(saved)
	_chk("F.01 a saved bag round-trips its contents",
			b2.count_of(_id("ITEM_POTION")) == 4 and b2.count_of(_id("ITEM_TM39")) == 1)
	_chk("F.02 and its slot layout, not just totals",
			b2.slots(ItemManager.POCKET_TM_HM).size() == 1)
	_chk("F.03 the save shape is plain data, safe to serialise",
			typeof(saved) == TYPE_DICTIONARY
			and typeof(JSON.stringify(saved)) == TYPE_STRING)
	b.clear()
	_chk("F.04 clear empties every pocket",
			b.count_of(_id("ITEM_POTION")) == 0
			and b.slots(ItemManager.POCKET_TM_HM).is_empty())
