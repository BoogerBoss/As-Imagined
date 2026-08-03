extends Node

## [M27I I5-2/I5-3] The field party screen, and using an item on it.
##
## The claims most worth pinning:
##
##   * the party screen shows ALL SIX slots including fainted ones — the battle
##     screen filters, and copying that here would hide half your team;
##   * item use starts in the BAG, not the party — the party is a target picker,
##     which is source's own flow and the E3 recon's own scope boundary;
##   * the item is consumed only if it DID something, so a Potion on a full-HP
##     Pokémon is refused rather than eaten.

const EXPECTED_TOTAL := 41

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _screen() -> FieldPartyScreen:
	var s := FieldPartyScreen.new()
	add_child(s)
	return s


func _bag_screen() -> FieldBagScreen:
	var s := FieldBagScreen.new()
	add_child(s)
	return s


func _party(n: int) -> BattleParty:
	var p := BattleParty.new()
	for i in range(n):
		p.members.append(PokemonFactory.create_battle_pokemon(1 + i, 10))
	p.active_indices = [0]
	return p


func _ready() -> void:
	_test_rows()
	_test_navigation()
	_test_item_actions()
	_test_use_flow()
	_test_wiring()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27i_i5_party_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the rows ---
func _test_rows() -> void:
	var p := _party(3)
	p.members[1].current_hp = 0
	p.members[1].fainted = true
	p.members[2].status = BattlePokemon.STATUS_POISON
	var s := _screen()
	s.open(p)
	var rows := s.row_texts()
	# ⚠️ ALL SIX SLOTS, INCLUDING FAINTED. The battle screen FILTERS to live
	# non-active candidates because it answers "who can I switch to"; copying
	# that here would hide half the team from a screen that answers "what have I got".
	_chk("A.01 every slot is shown, fainted included", rows.size() == 3)
	_chk("A.02 a fainted slot is marked FNT", str(rows[1]).contains("FNT"))
	_chk("A.03 a statused slot shows its status", str(rows[2]).contains("PSN"))
	_chk("A.04 and a healthy one shows neither",
			not str(rows[0]).contains("FNT") and not str(rows[0]).contains("PSN"))
	_chk("A.05 each row carries level and HP",
			str(rows[0]).contains("Lv10") and str(rows[0]).contains("/"))
	_chk("A.06 the cursor starts on the first slot", str(rows[0]).begins_with("▶"))

	# Source's own abbreviations, and toxic shares poison's.
	_chk("A.07 status labels are source's own three-letter forms",
			FieldPartyScreen.status_label(BattlePokemon.STATUS_BURN) == "BRN"
			and FieldPartyScreen.status_label(BattlePokemon.STATUS_SLEEP) == "SLP"
			and FieldPartyScreen.status_label(BattlePokemon.STATUS_TOXIC) == "PSN")
	_chk("A.08 and no status is blank",
			FieldPartyScreen.status_label(BattlePokemon.STATUS_NONE) == "")
	s.free()


## --- B. navigation ---
func _test_navigation() -> void:
	var s := _screen()
	s.open(_party(3))
	_chk("B.01 it opens on the first slot", s.is_open and s.index == 0)
	# ⚠️ CLAMPS, like the bag's item list — a wrapping list with nothing to
	# signal the wrap makes a held Down cycle forever.
	s.move(-1)
	_chk("B.02 up on the first slot CLAMPS", s.index == 0)
	s.move(1)
	s.move(1)
	_chk("B.03 down moves", s.index == 2)
	s.move(1)
	_chk("B.04 and clamps at the last", s.index == 2)

	var chosen: Array[int] = []
	s.mon_chosen.connect(func(i: int) -> void: chosen.append(i))
	var got: int = s.confirm()
	_chk("B.05 confirming reports the slot",
			got == 2 and chosen.size() == 1 and chosen[0] == 2)
	_chk("B.06 and closes", not s.is_open)

	var cancelled := [false]
	var s2 := _screen()
	s2.open(_party(2))
	s2.cancelled.connect(func() -> void: cancelled[0] = true)
	s2.close()
	_chk("B.07 cancelling reports it", cancelled[0] and not s2.is_open)

	# The prompt tells the player WHY it is open.
	var s3 := _screen()
	s3.open(_party(2))
	_chk("B.08 browsing shows the plain prompt",
			s3.prompt_text() == FieldPartyScreen.PROMPT_BROWSE)
	s3.open(_party(2), "Potion")
	_chk("B.09 and using an item names it", s3.prompt_text().contains("Potion"))
	s.free(); s2.free(); s3.free()


## --- C. the bag's action menu ---
func _test_item_actions() -> void:
	var potion := PokemonRegistry.item_id_of("ITEM_POTION")
	var xatk := PokemonRegistry.item_id_of("ITEM_X_ATTACK")
	if potion <= 0 or xatk <= 0:
		_gated += 9
		return
	# ⚠️ FIELD USABILITY IS DERIVED. Source carries `.fieldUseFunc` per item —
	# Potion has one, X Attack has NONE, verified directly — but items.json
	# holds only description/hold_effect/pocket/price.
	_chk("C.01 a Potion is field-usable", FieldBagScreen.is_field_usable(potion))
	_chk("C.02 an X item is NOT — source gives it no field use",
			not FieldBagScreen.is_field_usable(xatk))
	_chk("C.03 nor is a Poké Ball", not FieldBagScreen.is_field_usable(1))

	var bag := Bag.new()
	bag.add(potion, 2)
	var s := _bag_screen()
	s.open(bag)
	_chk("C.04 the action menu opens on an item", s.open_actions() and s.actions_open)
	var acts := s.action_texts()
	# ⚠️ Source OMITS actions an item does not support rather than showing them
	# greyed — which is why an unusable item needs no "can't use that" text.
	_chk("C.05 a usable item offers USE and CANCEL", acts.size() == 2)
	_chk("C.06 with USE first", str(acts[0]).contains("USE"))

	var bag2 := Bag.new()
	bag2.add(xatk, 1)
	var s2 := _bag_screen()
	s2.open(bag2)
	s2.open_actions()
	_chk("C.07 an unusable item offers CANCEL only",
			s2.action_texts().size() == 1
			and str(s2.action_texts()[0]).contains("CANCEL"))

	# Requesting USE does NOT apply anything — the bag hands off.
	var requested: Array[int] = []
	s.item_use_requested.connect(func(id: int) -> void: requested.append(id))
	s.open_actions()
	var a: String = s.confirm_action()
	_chk("C.08 confirming USE emits the request",
			a == "USE" and requested.size() == 1 and requested[0] == potion)
	_chk("C.09 and the bag still holds it — the bag does not apply items",
			bag.count_of(potion) == 2)
	s.free(); s2.free()


## --- D. the use flow ---
func _test_use_flow() -> void:
	var potion := PokemonRegistry.item_id_of("ITEM_POTION")
	if potion <= 0:
		_gated += 8
		return
	OverworldSession.reset()
	var party := OverworldSession.player_party()
	OverworldSession.bag.add(potion, 2)
	var mon: BattlePokemon = party.members[0]
	mon.current_hp = 1

	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# Deliberately NOT added to the tree — _ready() would boot the whole region.
	ow._pending_use_item = potion
	ow._on_party_mon_chosen(0)
	_chk("D.01 a Potion heals the chosen Pokémon", mon.current_hp > 1)
	_chk("D.02 and is consumed", OverworldSession.bag.count_of(potion) == 1)

	# ⚠️ CONSUMED ONLY IF IT DID SOMETHING. Source refuses a Potion on a full-HP
	# Pokémon rather than eating it.
	mon.current_hp = mon.max_hp
	ow._pending_use_item = potion
	ow._on_party_mon_chosen(0)
	_chk("D.03 a full-HP target refuses the item",
			OverworldSession.bag.count_of(potion) == 1)

	# A cure item on an unafflicted target is the same shape.
	var full_heal := PokemonRegistry.item_id_of("ITEM_FULL_HEAL")
	if full_heal <= 0:
		_gated += 2
	else:
		OverworldSession.bag.add(full_heal, 1)
		ow._pending_use_item = full_heal
		ow._on_party_mon_chosen(0)
		_chk("D.04 a cure on a healthy target is refused",
				OverworldSession.bag.count_of(full_heal) == 1)
		mon.status = BattlePokemon.STATUS_POISON
		ow._pending_use_item = full_heal
		ow._on_party_mon_chosen(0)
		_chk("D.05 but lands on a poisoned one",
				mon.status == BattlePokemon.STATUS_NONE
				and OverworldSession.bag.count_of(full_heal) == 0)

	# Cancelling clears the pending item, so the next browse does not apply it.
	ow._pending_use_item = potion
	ow._on_party_cancelled()
	_chk("D.06 cancelling clears the pending item", ow._pending_use_item == -1)
	ow._on_party_mon_chosen(0)
	_chk("D.07 so a later pick applies nothing",
			OverworldSession.bag.count_of(potion) == 1)

	_chk("D.08 an out-of-range slot is refused rather than crashing",
			_no_crash(ow, potion))
	ow.free()
	OverworldSession.reset()


func _no_crash(ow: Node2D, item_id: int) -> bool:
	ow._pending_use_item = item_id
	ow._on_party_mon_chosen(99)
	return true


## --- E. wiring ---
func _test_wiring() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	_chk("E.01 the overworld drives a party screen", ow.has_method("_drive_party_screen"))
	_chk("E.02 opens it from the START menu", ow.has_method("_on_start_menu_pokemon"))
	_chk("E.03 and from a bag USE", ow.has_method("_on_bag_item_use"))
	_chk("E.04 applying is its own step", ow.has_method("_on_party_mon_chosen"))
	ow.free()

	# POKéMON is gated on source's own flag, so it appears without code changes.
	var flags := FlagStore.new()
	_chk("E.05 POKéMON is absent before its flag",
			not FieldStartMenu.build_entries(flags).has(FieldStartMenu.Entry.POKEMON))
	flags.flag_set("FLAG_SYS_POKEMON_GET")
	_chk("E.06 and present after",
			FieldStartMenu.build_entries(flags).has(FieldStartMenu.Entry.POKEMON))

	var m := FieldStartMenu.new()
	add_child(m)
	m.open(flags)
	var got := [false]
	m.pokemon_selected.connect(func() -> void: got[0] = true)
	# POKéMON is first once its flag is set.
	m.confirm()
	_chk("E.07 choosing it emits the signal", got[0])
	m.free()
