extends Node

## [M27O O1] The respawn point.
##
## The distinction this suite exists to protect: a heal location's HEAL POINT
## and its RESPAWN POINT are different places. Source keeps two tables for it.
## Collapsing them drops the player outdoors after a whiteout instead of in
## front of a nurse -- and that reads as "the respawn is broken", not as a
## subtle data mix-up.

const EXPECTED_TOTAL := 23

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _src(ops: Dictionary) -> ScriptVM.ScriptSource:
	var s := ScriptVM.ScriptSource.new()
	s.ops_by_label = ops
	return s


func _op(name: String, args: Array = []) -> Dictionary:
	return {"op": name, "args": args}


func _ready() -> void:
	_test_table()
	_test_two_points()
	_test_setting()
	_test_opcode()
	_test_corpus()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27o_respawn_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the generated table ---
func _test_table() -> void:
	if not FileAccess.file_exists(RespawnPoint.TABLE_PATH):
		_gated += 6
		return
	_chk("A.01 the table loaded", RespawnPoint.ids().size() == 42)
	_chk("A.02 Kanto locations are present, not just Hoenn",
			RespawnPoint.is_known("HEAL_LOCATION_PALLET_TOWN")
			and RespawnPoint.is_known("HEAL_LOCATION_PEWTER_CITY")
			and RespawnPoint.is_known("HEAL_LOCATION_VIRIDIAN_CITY"))
	_chk("A.03 an unknown id is not known", not RespawnPoint.is_known("HEAL_LOCATION_NOPE"))
	# Map names are resolved to THIS project's own, not left as MAP_* constants.
	var pewter := RespawnPoint.entry("HEAL_LOCATION_PEWTER_CITY")
	_chk("A.04 map constants are resolved to project map names",
			str(pewter.get("map", "")) == "PewterCity_Frlg"
			and str(pewter.get("respawn_map", "")) == "PewterCity_PokemonCenter_1F_Frlg")
	# ⚠️ The Pokémon-Centre default is real: most entries omit respawn_x/y and
	# source's template fills 7,4. Reading a missing coordinate as 0 would put
	# the player in the wall.
	_chk("A.05 an entry omitting respawn coords gets source's own default",
			int(pewter.get("respawn_x", -1)) == 7 and int(pewter.get("respawn_y", -1)) == 4)
	# Pallet overrides them, so the default must not be applied blindly.
	var pallet := RespawnPoint.entry("HEAL_LOCATION_PALLET_TOWN")
	_chk("A.06 an entry that SPECIFIES them keeps its own",
			int(pallet.get("respawn_x", -1)) == 8 and int(pallet.get("respawn_y", -1)) == 5)


## --- B. heal point vs respawn point ---
func _test_two_points() -> void:
	if not FileAccess.file_exists(RespawnPoint.TABLE_PATH):
		_gated += 4
		return
	var r := RespawnPoint.new()
	r.set_to("HEAL_LOCATION_PEWTER_CITY")
	var heal := r.heal_warp()
	var resp := r.respawn_warp()
	# ⚠️ THE HEADLINE. These are different maps: the heal point is the outdoor
	# tile the Centre stands on; the respawn point is inside it.
	_chk("B.01 the heal point is OUTDOORS", str(heal.get("map", "")) == "PewterCity_Frlg")
	_chk("B.02 the respawn point is INSIDE the centre",
			str(resp.get("map", "")) == "PewterCity_PokemonCenter_1F_Frlg")
	_chk("B.03 and they are genuinely different places",
			str(heal.get("map", "")) != str(resp.get("map", "")))
	# Pallet's respawn is the player's HOUSE, not a Pokémon Centre -- the one
	# entry where a "respawn == centre" assumption would be wrong.
	var r2 := RespawnPoint.new()
	r2.set_to("HEAL_LOCATION_PALLET_TOWN")
	_chk("B.04 Pallet respawns in the player's house, not a centre",
			str(r2.respawn_warp().get("map", "")) == "PalletTown_PlayersHouse_1F_Frlg")


## --- C. setting and defaulting ---
func _test_setting() -> void:
	if not FileAccess.file_exists(RespawnPoint.TABLE_PATH):
		_gated += 6
		return
	var r := RespawnPoint.new()
	_chk("C.01 a fresh respawn is unset", r.current == "")
	_chk("C.02 and resolves to nothing rather than a wrong place",
			r.respawn_warp().is_empty())
	_chk("C.03 setting a known location works",
			r.set_to("HEAL_LOCATION_VIRIDIAN_CITY")
			and r.current == "HEAL_LOCATION_VIRIDIAN_CITY")
	# ⚠️ Refusing beats storing: an unknown id kept now becomes an unresolvable
	# warp at whiteout time, when the player is already fainted.
	_chk("C.04 an unknown location is REFUSED, not stored",
			not r.set_to("HEAL_LOCATION_NOPE")
			and r.current == "HEAL_LOCATION_VIRIDIAN_CITY")
	# The default follows the start map, so a playtest that moves start_map
	# does not strand its respawn somewhere else.
	var r2 := RespawnPoint.new()
	r2.default_for("PewterCity_Frlg")
	_chk("C.05 the default resolves from the start map",
			r2.current == "HEAL_LOCATION_PEWTER_CITY")
	var r3 := RespawnPoint.new()
	r3.default_for("ViridianForest_Frlg")   # no heal location of its own
	_chk("C.06 a start map with no heal location falls back to the story's own",
			r3.current == RespawnPoint.STORY_DEFAULT)


## --- D. the opcode ---
func _test_opcode() -> void:
	if not FileAccess.file_exists(RespawnPoint.TABLE_PATH):
		_gated += 4
		return
	var vm := ScriptVM.new(_src({
		"A": [_op("setrespawn", ["HEAL_LOCATION_PEWTER_CITY"]), _op("end")],
	}), FlagStore.new())
	vm.start("A")
	vm.step()
	_chk("D.01 setrespawn sets the point", vm.respawn.current == "HEAL_LOCATION_PEWTER_CITY")
	_chk("D.02 and the script keeps running", vm.pause_reason != ScriptVM.Pause.UNKNOWN_OP)
	# An unknown location must NAME itself rather than failing silently -- the
	# same degrade-and-report contract every other opcode here follows.
	var vm2 := ScriptVM.new(_src({
		"A": [_op("setrespawn", ["HEAL_LOCATION_NOPE"]), _op("end")],
	}), FlagStore.new())
	vm2.start("A")
	vm2.step()
	_chk("D.03 an unknown location reports itself", vm2.diagnostic.contains("HEAL_LOCATION_NOPE"))
	_chk("D.04 and leaves the respawn unset rather than broken", vm2.respawn.current == "")


## --- E. against the real corpus ---
func _test_corpus() -> void:
	if not FileAccess.file_exists("res://data/map_scripts.json") \
			or not FileAccess.file_exists(RespawnPoint.TABLE_PATH):
		_gated += 3
		return
	var ops: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var wanted := {}
	for label in ops:
		for o in ops[label]:
			if str(o.get("op", "")) == "setrespawn":
				var a: Array = o.get("args", [])
				if a.size() > 0:
					wanted[str(a[0])] = true
	var unknown: Array[String] = []
	for w in wanted:
		if not RespawnPoint.is_known(str(w)):
			unknown.append(str(w))
	_chk("E.01 the corpus really does call setrespawn", wanted.size() >= 30)
	# Every location any script sets must resolve, or that script sets a
	# respawn the player can never be sent to.
	_chk("E.02 EVERY location the corpus sets is known (%d unknown: %s)"
			% [unknown.size(), str(unknown.slice(0, 5))], unknown.is_empty())
	# And every one must resolve to a real destination, not just be listed.
	var no_dest: Array[String] = []
	for w in wanted:
		var e := RespawnPoint.entry(str(w))
		if str(e.get("respawn_map", "")) == "":
			no_dest.append(str(w))
	_chk("E.03 and each resolves to a real respawn map (%d without: %s)"
			% [no_dest.size(), str(no_dest.slice(0, 5))], no_dest.is_empty())
