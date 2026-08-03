extends Node

## [M27I I1] Item identity: the ITEM_* -> id bridge, and identity lookup.
##
## Scripts name an item ONLY by constant; everything else here uses ids. This
## suite guards the bridge, and specifically the two things that make it more
## than a table lookup: ALIAS spellings, and the TM/HM gap in items.json.

const EXPECTED_TOTAL := 30

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _ready() -> void:
	_test_map_integrity()
	_test_aliases()
	_test_tmhm_bridge()
	_test_identity()
	_test_corpus_coverage()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27i_item_identity_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the generated map itself ---
func _test_map_integrity() -> void:
	var reg := PokemonRegistry
	_chk("A.01 the name map loaded", reg.item_constants().size() > 800)
	_chk("A.02 ITEM_NONE is zero", reg.item_id_of("ITEM_NONE") == 0)
	_chk("A.03 an unknown constant reports -1 rather than 0",
			reg.item_id_of("ITEM_NOT_A_REAL_ITEM") == -1)
	# ⚠️ -1 and 0 must stay distinguishable: 0 is ITEM_NONE, a real value that
	# `giveitem` treats as failure. Collapsing them would make an unresolvable
	# item look like a deliberate "give nothing".
	_chk("A.04 unknown and ITEM_NONE are different answers",
			reg.item_id_of("ITEM_NOT_A_REAL_ITEM") != reg.item_id_of("ITEM_NONE"))
	# Explicit values, straight from the enum.
	_chk("A.05 explicit enum values are exact",
			reg.item_id_of("ITEM_POKE_BALL") == 1
			and reg.item_id_of("ITEM_MASTER_BALL") == 4
			and reg.item_id_of("ITEM_TM01") == 582
			and reg.item_id_of("ITEM_HM01") == 682)
	var all_ok := true
	for c in reg.item_constants():
		if reg.item_id_of(str(c)) < 0:
			all_ok = false
			break
	_chk("A.06 every constant resolves to a non-negative id", all_ok)


## --- B. aliases. The corridor uses BOTH spellings of the same item. ---
func _test_aliases() -> void:
	var reg := PokemonRegistry
	# `ITEM_ITEMFINDER = ITEM_DOWSING_MACHINE` -- pre-Gen-IV name. A parser
	# handling only `= <int>` drops these silently and the script that wanted
	# one then fails to resolve an item that exists.
	var finder := reg.item_id_of("ITEM_ITEMFINDER")
	var dowsing := reg.item_id_of("ITEM_DOWSING_MACHINE")
	_chk("B.01 an alias resolves at all", finder > 0)
	_chk("B.02 and to the SAME id as its modern spelling", finder == dowsing)
	_chk("B.03 the third spelling agrees too",
			reg.item_id_of("ITEM_DOWSING_MCHN") == dowsing)
	# The corridor genuinely references both of these.
	var parcel := reg.item_id_of("ITEM_OAKS_PARCEL")
	_chk("B.04 ITEM_OAKS_PARCEL resolves via its alias target",
			parcel > 0 and parcel == reg.item_id_of("ITEM_PARCEL"))


## --- C. the TM/HM bridge across the items.json gap ---
func _test_tmhm_bridge() -> void:
	var reg := PokemonRegistry
	# The macro-generated move-named forms.
	_chk("C.01 ITEM_TM_<MOVE> resolves to its numbered TM",
			reg.item_id_of("ITEM_TM_ROAR") == reg.item_id_of("ITEM_TM05"))
	_chk("C.02 and the HM forms likewise",
			reg.item_id_of("ITEM_HM_FLY") == reg.item_id_of("ITEM_HM02"))
	# ⚠️ THE GAP. items.json genuinely has no entry for any TM or HM, so a
	# lookup that only read it would return {} for Brock's own reward.
	_chk("C.03 items.json really does lack the TM range (the gap is real)",
			reg.get_item(reg.item_id_of("ITEM_TM39")).is_empty())
	var tm39 := reg.get_item_identity(reg.item_id_of("ITEM_TM39"))
	_chk("C.04 but identity still resolves it", not tm39.is_empty())
	_chk("C.05 naming the ITEM, not the move it teaches",
			str(tm39.get("name", "")) == "TM39")
	_chk("C.06 in the TM/HM pocket", int(tm39.get("pocket", -1)) == ItemManager.POCKET_TM_HM)
	_chk("C.07 and carrying the move it teaches",
			str(tm39.get("description", "")).contains("Rock Tomb"))
	# HMs sit after the 50 TMs in tmhm_map's own 1-58 index -- an off-by-fifty
	# here would map every HM to a TM's move and look plausible.
	var hm05 := reg.get_item_identity(reg.item_id_of("ITEM_HM05"))
	_chk("C.08 HM indexing accounts for the 50 TMs before it",
			str(hm05.get("name", "")) == "HM05"
			and str(hm05.get("description", "")).contains("Flash"))
	_chk("C.09 an id just past the TM block is not treated as a TM",
			reg._tmhm_number_for(reg.item_id_of("ITEM_TM01") - 1) == -1)


## --- D. identity for ordinary items ---
func _test_identity() -> void:
	var reg := PokemonRegistry
	var potion := reg.get_item_identity(reg.item_id_of("ITEM_POTION"))
	_chk("D.01 an ordinary item resolves", not potion.is_empty())
	_chk("D.02 with a real name", str(potion.get("name", "")) == "Potion")
	_chk("D.03 a real price", int(potion.get("price", 0)) > 0)
	_chk("D.04 and a pocket ORDINAL, not the JSON's string",
			typeof(potion.get("pocket")) == TYPE_INT
			and int(potion["pocket"]) == ItemManager.POCKET_ITEMS)
	# The pocket mapping must cover all five, not just the two battle needed.
	_chk("D.05 pocket names map to source's own ordinals",
			ItemManager.pocket_from_name("items") == 0
			and ItemManager.pocket_from_name("poke_balls") == 1
			and ItemManager.pocket_from_name("tm_hm") == 2
			and ItemManager.pocket_from_name("berries") == 3
			and ItemManager.pocket_from_name("key_items") == 4)
	_chk("D.06 an unknown pocket falls back rather than erroring",
			ItemManager.pocket_from_name("nonsense") == ItemManager.POCKET_ITEMS)
	_chk("D.07 a real ball lands in the balls pocket",
			int(reg.get_item_identity(reg.item_id_of("ITEM_POKE_BALL")).get("pocket", -1))
			== ItemManager.POCKET_POKE_BALLS)
	_chk("D.08 an unknown id returns {} rather than a half-filled record",
			reg.get_item_identity(999999).is_empty())


## --- E. does this actually cover what the scripts ask for? ---
func _test_corpus_coverage() -> void:
	var reg := PokemonRegistry
	if not FileAccess.file_exists("res://data/map_scripts.json"):
		_gated += 3
		return
	var ops: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var wanted := {}
	const FAM := ["giveitem", "giveitem_msg", "finditem", "additem", "checkitem",
			"checkitemspace", "removeitem", "bufferitemname", "setitemandprice"]
	for label in ops:
		for o in ops[label]:
			if not FAM.has(str(o.get("op", ""))):
				continue
			for a in o.get("args", []):
				if str(a).begins_with("ITEM_"):
					wanted[str(a)] = true
	var unresolved: Array[String] = []
	for c in wanted:
		if reg.item_id_of(str(c)) < 0:
			unresolved.append(str(c))
	# The whole point of I1: every item any script names must resolve. An
	# unresolvable one is a script that cannot run, discovered at play time.
	_chk("E.01 the corpus asks for a real number of distinct items",
			wanted.size() >= 250)
	_chk("E.02 EVERY item constant the corpus names resolves (%d unresolved: %s)"
			% [unresolved.size(), str(unresolved.slice(0, 5))], unresolved.is_empty())
	# Identity too, not just the id -- resolving an id that then has no record
	# would move the failure one step later instead of fixing it.
	var no_identity: Array[String] = []
	for c in wanted:
		var id := reg.item_id_of(str(c))
		if id > 0 and reg.get_item_identity(id).is_empty():
			no_identity.append(str(c))
	_chk("E.03 and every one of them has a real identity record (%d without: %s)"
			% [no_identity.size(), str(no_identity.slice(0, 5))], no_identity.is_empty())
