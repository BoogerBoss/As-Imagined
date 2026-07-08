extends Node

# Autoload singleton. Loads the JSON files produced by tools/convert_pokedata.py
# at startup and exposes indexed lookups for the battle engine and overworld layers.

var _species_by_dex: Dictionary = {}
var _moves_by_id: Dictionary = {}
var _learnsets_by_dex: Dictionary = {}
var _learnable_moves_by_dex: Dictionary = {}
var _universal_moves: Array = []
var _all_species: Array = []
var _items_by_id: Dictionary = {}
var _evolutions_by_dex: Dictionary = {}
var _tmhm_map: Dictionary = {}
var _exp_curves: Dictionary = {}


func _ready() -> void:
	_load_pokemon()
	_load_moves()
	_load_learnsets()
	_load_learnable_moves()
	_load_items()
	_load_evolutions()
	_load_tmhm()
	_load_exp_curves()
	_smoke_test()


func _load_pokemon() -> void:
	var data = _load_json("res://data/pokemon.json")
	for entry in data:
		_species_by_dex[int(entry["dex"])] = entry
	_all_species = data


func _load_moves() -> void:
	var data = _load_json("res://data/moves.json")
	for entry in data:
		_moves_by_id[int(entry["id"])] = entry


func _load_learnsets() -> void:
	var data = _load_json("res://data/learnsets.json")
	for key in data:
		_learnsets_by_dex[int(key)] = data[key]["moves"]


func _load_learnable_moves() -> void:
	var all_learnables = _load_json("res://data/all_learnables.json")
	var special = _load_json("res://data/special_movesets.json")
	if typeof(special) == TYPE_DICTIONARY:
		_universal_moves = special.get("universalMoves", [])
	for entry in _all_species:
		var dex := int(entry["dex"])
		var key := _name_to_learnable_key(entry["name"])
		_learnable_moves_by_dex[dex] = all_learnables.get(key, []) if typeof(all_learnables) == TYPE_DICTIONARY else []


func _load_items() -> void:
	var data = _load_json("res://data/items.json")
	if typeof(data) == TYPE_ARRAY:
		for entry in data:
			_items_by_id[int(entry["id"])] = entry


func _load_evolutions() -> void:
	var data = _load_json("res://data/evolutions.json")
	if typeof(data) == TYPE_DICTIONARY:
		for key in data:
			_evolutions_by_dex[int(key)] = data[key]["evolutions"]


func _load_tmhm() -> void:
	var data = _load_json("res://data/tmhm_map.json")
	if typeof(data) == TYPE_DICTIONARY:
		for key in data:
			var entry: Dictionary = data[key]
			_tmhm_map[key] = {
				"tm_name":   entry.get("tm_name", ""),
				"move_name": entry.get("move_name", ""),
				"move_id":   int(entry.get("move_id", 0)),
				"name":      entry.get("name", ""),
			}


func _load_exp_curves() -> void:
	var data = _load_json("res://data/exp_curves.json")
	if typeof(data) == TYPE_DICTIONARY:
		for curve_name in data:
			var raw_arr: Array = data[curve_name]
			var int_arr: Array = []
			for v in raw_arr:
				int_arr.append(int(v))
			_exp_curves[curve_name] = int_arr


func _name_to_learnable_key(name: String) -> String:
	var s := name
	s = s.replace("♀", "_F")
	s = s.replace("♂", "_M")
	s = s.replace(".", "")
	s = s.replace("'", "")
	s = s.replace(" ", "_")
	s = s.replace("-", "_")
	s = s.to_upper()
	# Base Deoxys is stored as DEOXYS_NORMAL in all_learnables.json
	if s == "DEOXYS":
		return "DEOXYS_NORMAL"
	return s


func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("PokemonRegistry: failed to open %s (error %d)" % [path, FileAccess.get_open_error()])
		return []
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("PokemonRegistry: failed to parse JSON at " + path)
		return []
	return parsed


func get_species(dex_number: int) -> Dictionary:
	return _species_by_dex.get(dex_number, {})


func get_move(move_id: int) -> Dictionary:
	return _moves_by_id.get(move_id, {})


func get_learnset(dex_number: int) -> Array:
	return _learnsets_by_dex.get(dex_number, [])


func get_all_species() -> Array:
	return _all_species


func get_learnable_moves(dex_number: int) -> Array:
	var species_moves: Array = _learnable_moves_by_dex.get(dex_number, [])
	var combined := species_moves.duplicate()
	for move in _universal_moves:
		if not combined.has(move):
			combined.append(move)
	return combined


func get_item(item_id: int) -> Dictionary:
	return _items_by_id.get(item_id, {})


func get_evolutions(dex_number: int) -> Array:
	return _evolutions_by_dex.get(dex_number, [])


func get_tm_move(tm_number: int) -> Dictionary:
	return _tmhm_map.get(str(tm_number), {})


func get_exp_for_level(growth_rate: String, level: int) -> int:
	var curve: Array = _exp_curves.get(growth_rate, [])
	if curve.is_empty() or level < 0 or level >= curve.size():
		return 0
	return curve[level]


func _smoke_test() -> void:
	var bulbasaur := get_species(1)
	assert(bulbasaur.get("base_hp", 0) > 0, "Bulbasaur (#1) failed to load or has zero base_hp")
	assert(bulbasaur.get("base_atk", 0) > 0, "Bulbasaur (#1) has zero base_atk")

	var charizard := get_species(6)
	assert(charizard.get("base_hp", 0) > 0, "Charizard (#6) failed to load or has zero base_hp")
	assert(charizard.get("base_spe", 0) > 0, "Charizard (#6) has zero base_spe")

	var mewtwo := get_species(150)
	assert(mewtwo.get("base_hp", 0) > 0, "Mewtwo (#150) failed to load or has zero base_hp")
	assert(mewtwo.get("base_spa", 0) > 0, "Mewtwo (#150) has zero base_spa")

	var rayquaza := get_species(384)
	assert(rayquaza.get("base_hp", 0) > 0, "Rayquaza (#384) failed to load or has zero base_hp")
	assert(rayquaza.get("base_atk", 0) > 0, "Rayquaza (#384) has zero base_atk")

	var bulbasaur_learnables := get_learnable_moves(1)
	assert(bulbasaur_learnables.size() > 0, "Bulbasaur (#1) learnable moves list is empty")
	assert("MOVE_TACKLE" in bulbasaur_learnables, "Bulbasaur (#1) learnable moves missing MOVE_TACKLE")

	# M15 Task 4a new assertions
	# Evolution: Bulbasaur evolves to Ivysaur (#2) at level 16
	var bulbasaur_evos := get_evolutions(1)
	assert(bulbasaur_evos.size() > 0, "Bulbasaur evolutions list is empty")
	var first_evo: Dictionary = bulbasaur_evos[0]
	assert(first_evo.get("target_dex", 0) == 2, "Bulbasaur evo target_dex should be 2 (Ivysaur)")
	assert(first_evo.get("method", "") == "level_up", "Bulbasaur evo method should be level_up")
	assert(first_evo.get("condition", 0) == 16, "Bulbasaur evo condition should be 16")

	# TM: TM01 → MOVE_FOCUS_PUNCH (move_id 264)
	var tm01 := get_tm_move(1)
	assert(tm01.get("move_name", "") == "MOVE_FOCUS_PUNCH", "TM01 should map to MOVE_FOCUS_PUNCH")
	assert(tm01.get("move_id", 0) == 264, "TM01 move_id should be 264")

	# EXP: Charizard is Medium Slow; level 100 = 1,059,860
	assert(charizard.get("growth_rate", "") == "MediumSlow", "Charizard growth_rate should be MediumSlow")
	var charizard_exp_100 := get_exp_for_level("MediumSlow", 100)
	assert(charizard_exp_100 == 1059860, "MediumSlow level 100 EXP should be 1059860, got %d" % charizard_exp_100)

	# Item: Potion (id=28) exists and has correct pocket
	var potion := get_item(28)
	assert(potion.get("name", "") == "Potion", "Item 28 should be Potion, got %s" % potion.get("name", ""))
	assert(potion.get("pocket", "") == "items", "Potion pocket should be 'items'")

	# [M18.5j] species_name spot-check — debug-only field, sourced from
	# pokemon.json's own "name" field; not read by get_learnset/get_evolutions,
	# so checked against the raw wrapped JSON directly.
	var raw_learnsets = _load_json("res://data/learnsets.json")
	assert(raw_learnsets["1"]["species_name"] == "Bulbasaur", "learnsets.json species_name for dex 1 should be Bulbasaur")
	assert(raw_learnsets["6"]["species_name"] == "Charizard", "learnsets.json species_name for dex 6 should be Charizard")
	assert(raw_learnsets["150"]["species_name"] == "Mewtwo", "learnsets.json species_name for dex 150 should be Mewtwo")
	var raw_evolutions = _load_json("res://data/evolutions.json")
	assert(raw_evolutions["1"]["species_name"] == "Bulbasaur", "evolutions.json species_name for dex 1 should be Bulbasaur")
	assert(raw_evolutions["384"]["species_name"] == "Rayquaza", "evolutions.json species_name for dex 384 should be Rayquaza")

	# [M19-pipeline-fix] moves.json stat-change/chance extraction spot-checks.
	# Bug 1 (stat_change_stat/amount/self dropped for secondary-effect stat
	# changes on non-EFFECT_STAT_CHANGE moves): Mud-Slap/Icy Wind/Rock Tomb
	# (the 3 originally-cited moves) + Overheat (guaranteed self-drop) +
	# Meteor Mash (probabilistic self-raise) — a representative cross-section
	# of the 88-move fix, not exhaustive (see m19_pipeline_fix_test.tscn for
	# the full list).
	var mud_slap := get_move(189)
	assert(mud_slap.get("stat_change_stat", -1) == 5, "Mud-Slap stat_change_stat should be 5 (ACCURACY)")
	assert(mud_slap.get("stat_change_amount", 0) == -1, "Mud-Slap stat_change_amount should be -1")
	var icy_wind := get_move(196)
	assert(icy_wind.get("stat_change_stat", -1) == 4, "Icy Wind stat_change_stat should be 4 (SPEED)")
	var rock_tomb := get_move(317)
	assert(rock_tomb.get("stat_change_stat", -1) == 4, "Rock Tomb stat_change_stat should be 4 (SPEED)")
	var overheat := get_move(315)
	assert(overheat.get("stat_change_stat", -1) == 2, "Overheat stat_change_stat should be 2 (SPATK)")
	assert(overheat.get("stat_change_amount", 0) == -2, "Overheat stat_change_amount should be -2")
	assert(overheat.get("stat_change_self", false) == true, "Overheat stat_change_self should be true")
	var meteor_mash := get_move(309)
	assert(meteor_mash.get("stat_change_stat", -1) == 0, "Meteor Mash stat_change_stat should be 0 (ATK)")
	assert(meteor_mash.get("stat_change_self", false) == true, "Meteor Mash stat_change_self should be true")

	# Bug 2 (secondary_chance not resolved for ternary-valued .chance fields):
	# Poison Sting/Fire Blast, neither of which is a stat-change move at all
	# (secondary_effect status-infliction only) — confirms this is a genuinely
	# separate fix from Bug 1 above.
	var poison_sting := get_move(40)
	assert(poison_sting.get("secondary_chance", 0) == 30, "Poison Sting secondary_chance should be 30")
	var fire_blast := get_move(126)
	assert(fire_blast.get("secondary_chance", 0) == 10, "Fire Blast secondary_chance should be 10")

	# Regression control: unaffected moves stay bit-identical. Tackle has no
	# additionalEffects at all; Growl's PRIMARY effect IS EFFECT_STAT_CHANGE,
	# the one shape the pre-fix pipeline already extracted correctly.
	var tackle := get_move(33)
	assert(tackle.get("stat_change_stat", -1) == -1, "Tackle stat_change_stat should remain -1 (no stat change)")
	assert(tackle.get("secondary_chance", -1) == 0, "Tackle secondary_chance should remain 0")
	var growl := get_move(45)
	assert(growl.get("stat_change_stat", -1) == 0, "Growl stat_change_stat should remain 0 (ATK)")
	assert(growl.get("stat_change_amount", 0) == -1, "Growl stat_change_amount should remain -1")
	assert(growl.get("stat_change_self", true) == false, "Growl stat_change_self should remain false (lowers the OPPONENT's Attack)")

	print("PokemonRegistry: smoke test passed — %d species, %d moves, %d learnsets, %d learnable-move lists, %d items, %d evo-lists, %d TM/HMs, %d exp curves loaded" % [
		_species_by_dex.size(), _moves_by_id.size(), _learnsets_by_dex.size(), _learnable_moves_by_dex.size(),
		_items_by_id.size(), _evolutions_by_dex.size(), _tmhm_map.size(), _exp_curves.size()
	])
