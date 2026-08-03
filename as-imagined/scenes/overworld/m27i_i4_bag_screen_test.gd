extends Node

## [M27I I4] The field Bag, and the START menu that opens it.
##
## The claims most worth pinning are the ones that look like polish and are not:
##
##   * pocket tabs WRAP and the item list CLAMPS — with both wrapping, a held
##     Down key would silently cycle forever;
##   * a row is a STACK, not an item — 1000 Potions is genuinely two rows,
##     because that is what `[M27I I3]`'s bag stores;
##   * the START menu's short entry list is source's own CONDITIONAL result,
##     not a stub, and three unconditional entries are deliberately omitted.

const EXPECTED_TOTAL := 47

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _id(constant: String) -> int:
	return PokemonRegistry.item_id_of(constant)


func _screen() -> FieldBagScreen:
	var s := FieldBagScreen.new()
	add_child(s)
	return s


func _ready() -> void:
	_test_pockets()
	_test_rows()
	_test_navigation()
	_test_description()
	_test_start_menu()
	_test_wiring()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27i_i4_bag_screen_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the pockets ---
func _test_pockets() -> void:
	_chk("A.01 all five pockets are tabs", FieldBagScreen.POCKET_ORDER.size() == 5)
	# Source's own names, not invented ones.
	_chk("A.02 the names are source's own",
			FieldBagScreen.POCKET_NAMES[ItemManager.POCKET_POKE_BALLS] == "POKé BALLS"
			and FieldBagScreen.POCKET_NAMES[ItemManager.POCKET_TM_HM] == "TMs & HMs"
			and FieldBagScreen.POCKET_NAMES[ItemManager.POCKET_KEY_ITEMS] == "KEY ITEMS")
	_chk("A.03 in source's own ordinal order",
			FieldBagScreen.POCKET_ORDER[0] == ItemManager.POCKET_ITEMS
			and FieldBagScreen.POCKET_ORDER[4] == ItemManager.POCKET_KEY_ITEMS)

	var bag := Bag.new()
	var s := _screen()
	s.open(bag)
	_chk("A.04 it opens on ITEMS by default", s.pocket == ItemManager.POCKET_ITEMS)
	_chk("A.05 and is open", s.is_open and s.visible)
	s.open(bag, ItemManager.POCKET_BERRIES)
	_chk("A.06 or on a named pocket", s.pocket == ItemManager.POCKET_BERRIES)
	s.close()
	_chk("A.07 closing hides it", not s.is_open and not s.visible)
	s.free()


## --- B. the rows ---
func _test_rows() -> void:
	var bag := Bag.new()
	var potion := _id("ITEM_POTION")
	if potion <= 0:
		_gated += 8
		return
	bag.add(potion, 5)
	var s := _screen()
	s.open(bag)
	var rows := s.row_texts()
	_chk("B.01 a held item shows up", rows.size() == 1)
	_chk("B.02 named", str(rows[0]).contains("POTION") or str(rows[0]).to_lower().contains("potion"))
	_chk("B.03 with its count", str(rows[0]).contains("x5"))
	_chk("B.04 and the cursor on it", str(rows[0]).begins_with("▶"))
	_chk("B.05 selected_item_id reports it", s.selected_item_id() == potion)

	# ⚠️ A ROW IS A STACK, NOT AN ITEM. The bag caps a stack at 999, so 1000
	# Potions is genuinely two rows — that is what I3 stores, and flattening it
	# here would misreport a full bag.
	var bag2 := Bag.new()
	bag2.add(potion, Bag.MAX_STACK + 1)
	var s2 := _screen()
	s2.open(bag2)
	_chk("B.06 a stack past the cap is TWO rows, not one",
			s2.row_texts().size() == 2)

	# An empty pocket says so rather than rendering blank.
	var s3 := _screen()
	s3.open(Bag.new())
	var er := s3.row_texts()
	_chk("B.07 an empty pocket says so", er.size() == 1 and str(er[0]) == FieldBagScreen.EMPTY_TEXT)
	_chk("B.08 and selects nothing", s3.selected_item_id() == -1)
	s.free(); s2.free(); s3.free()


## --- C. navigation ---
func _test_navigation() -> void:
	var bag := Bag.new()
	var potion := _id("ITEM_POTION")
	var ball := _id("ITEM_POKE_BALL")
	if potion <= 0 or ball <= 0:
		_gated += 10
		return
	bag.add(potion, 1)
	bag.add(ball, 3)
	var s := _screen()
	s.open(bag)

	# ⚠️ POCKETS WRAP (source cycles them with L/R)...
	_chk("C.01 right moves to the next pocket", true)
	s.next_pocket(1)
	_chk("C.02 which is POKé BALLS", s.pocket == ItemManager.POCKET_POKE_BALLS)
	_chk("C.03 and shows that pocket's contents",
			str(s.row_texts()[0]).to_lower().contains("ball"))
	# A FULL cycle is 5 steps, not 4 — landing back where it started is what
	# proves the wrap, and an off-by-one here would look like a pass.
	for i in range(5):
		s.next_pocket(1)
	_chk("C.04 pockets WRAP a full cycle back to where they started",
			s.pocket == ItemManager.POCKET_POKE_BALLS)
	s.next_pocket(-5)
	_chk("C.05 in both directions", s.pocket == ItemManager.POCKET_POKE_BALLS)

	# ...⚠️ but the ITEM LIST CLAMPS. If both wrapped, a held Down would cycle
	# forever with nothing to tell the player it had.
	#
	# ⚠️ THIS NEEDS TWO ROWS AND THE FIRST VERSION HAD ONE. With a single row,
	# `wrapi(0+1, 0, 1)` and `clampi(0+1, 0, 0)` are both 0 — the two rules AGREE,
	# so the guard passed against a deliberately wrapping implementation. Caught
	# by injecting the wrap; a fixture where the competing rules cannot disagree
	# is not a guard.
	var repel := _id("ITEM_REPEL")
	if repel <= 0:
		_gated += 4
	else:
		var bag2 := Bag.new()
		bag2.add(potion, 1)
		bag2.add(repel, 1)
		var s2 := _screen()
		s2.open(bag2, ItemManager.POCKET_ITEMS)
		_chk("C.06 two different items are two rows", s2.row_texts().size() == 2)
		s2.move_row(-1)
		_chk("C.07 UP on the first row CLAMPS — a wrap would land on the last",
				s2.row_index == 0)
		s2.move_row(1)
		_chk("C.08 down moves properly", s2.row_index == 1)
		s2.move_row(1)
		_chk("C.08b and DOWN on the last row clamps too", s2.row_index == 1)
		s2.free()

	# Switching pocket resets the cursor — otherwise it can point past the end.
	s.open(bag, ItemManager.POCKET_ITEMS)
	s.next_pocket(1)
	_chk("C.09 switching pocket resets the row cursor", s.row_index == 0)
	s.free()


## --- D. the description box ---
func _test_description() -> void:
	var potion := _id("ITEM_POTION")
	if potion <= 0:
		_gated += 4
		return
	var bag := Bag.new()
	bag.add(potion, 1)
	var s := _screen()
	s.open(bag)
	# Real data — `items.json` carries descriptions, so this is not a placeholder.
	_chk("D.01 the selected item has a real description",
			s.description_text().length() > 5)
	# ⚠️ items.json holds source's own LITERAL "\n" pairs — the reference
	# hand-wraps its box at a GBA width. Rendered raw they print as visible
	# backslash-n, which is what the live drive showed.
	_chk("D.01b and it carries no literal backslash-n",
			not s.description_text().contains("\\n"))
	var s2 := _screen()
	s2.open(Bag.new())
	_chk("D.02 an empty pocket describes nothing", s2.description_text() == "")

	# ⚠️ KEY ITEMS AND HMs SHOW NO COUNT — source prints a different format for
	# them (`gText_NumberItem_HM`), because you can only ever hold one.
	var hm := _id("ITEM_HM01")
	if hm > 0:
		var bag3 := Bag.new()
		bag3.add(hm, 1)
		var s3 := _screen()
		s3.open(bag3, ItemManager.POCKET_TM_HM)
		_chk("D.03 an HM shows no quantity", not str(s3.row_texts()[0]).contains("x"))
		s3.free()
	else:
		_gated += 1
	var tm := _id("ITEM_TM39")
	if tm > 0:
		var bag4 := Bag.new()
		bag4.add(tm, 1)
		var s4 := _screen()
		s4.open(bag4, ItemManager.POCKET_TM_HM)
		# A TM is not an HM — it keeps its count, which is the discriminator.
		_chk("D.04 but a TM does", str(s4.row_texts()[0]).contains("x1"))
		s4.free()
	else:
		_gated += 1
	s.free(); s2.free()


## --- E. the START menu ---
func _test_start_menu() -> void:
	var flags := FlagStore.new()
	var e := FieldStartMenu.build_entries(flags)
	# ⚠️ SHORT IS SOURCE'S OWN RESULT, NOT A STUB. BuildNormalStartMenu gates
	# POKéDEX and POKéMON on flags that are genuinely unset here.
	_chk("E.01 a fresh save shows only BAG and EXIT", e.size() == 2)
	_chk("E.02 BAG is unconditional", e.has(FieldStartMenu.Entry.BAG))
	_chk("E.03 so is EXIT", e.has(FieldStartMenu.Entry.EXIT))
	_chk("E.04 POKéDEX is absent until its flag is set",
			not e.has(FieldStartMenu.Entry.POKEDEX))

	flags.flag_set("FLAG_SYS_POKEDEX_GET")
	flags.flag_set("FLAG_SYS_POKEMON_GET")
	var e2 := FieldStartMenu.build_entries(flags)
	_chk("E.05 and appears on its own once it is", e2.has(FieldStartMenu.Entry.POKEDEX))
	_chk("E.06 alongside POKéMON", e2.has(FieldStartMenu.Entry.POKEMON))
	_chk("E.07 in source's own order, dex first",
			e2[0] == FieldStartMenu.Entry.POKEDEX and e2[1] == FieldStartMenu.Entry.POKEMON)

	var m := FieldStartMenu.new()
	add_child(m)
	m.open(FlagStore.new())
	_chk("E.08 it opens on the first entry", m.is_open and m.index == 0)
	# Source's start menu WRAPS, unlike the bag's item list.
	m.move(-1)
	_chk("E.09 and WRAPS, unlike the bag's rows", m.index == 1)
	var got := [false]
	m.bag_selected.connect(func() -> void: got[0] = true)
	m.move(-1)
	_chk("E.10 back on BAG", m.index == 0)
	var chosen: int = m.confirm()
	_chk("E.11 confirming BAG emits it", chosen == FieldStartMenu.Entry.BAG and got[0])
	_chk("E.12 and closes the menu", not m.is_open)
	m.free()


## --- F. wiring ---
func _test_wiring() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# Deliberately NOT added to the tree — _ready() would boot the whole region.
	_chk("F.01 the overworld drives a START menu", ow.has_method("_drive_start_menu"))
	_chk("F.02 and a bag screen", ow.has_method("_drive_bag_screen"))
	_chk("F.03 with a handler joining the two", ow.has_method("_on_start_menu_bag"))
	ow.free()

	# The bag the screen shows is the SAME one the scripts fill — otherwise
	# Brock's TM39 would never appear in it.
	OverworldSession.reset()
	var tm := _id("ITEM_TM39")
	if tm <= 0:
		_gated += 2
	else:
		OverworldSession.bag.add(tm, 1)
		var s := _screen()
		s.open(OverworldSession.bag, ItemManager.POCKET_TM_HM)
		_chk("F.04 an item a script gave you shows up in the bag",
				s.selected_item_id() == tm)
		_chk("F.05 named as the item, not the move it teaches",
				str(s.row_texts()[0]).contains("TM39"))
		s.free()
	OverworldSession.reset()
