extends Node

# Autoload singleton. Loads the three JSON files produced by tools/convert_pokedata.py
# at startup and exposes indexed lookups for the battle engine and overworld layers.

var _species_by_dex: Dictionary = {}
var _moves_by_id: Dictionary = {}
var _learnsets_by_dex: Dictionary = {}
var _all_species: Array = []


func _ready() -> void:
	_load_pokemon()
	_load_moves()
	_load_learnsets()
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
		_learnsets_by_dex[int(key)] = data[key]


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

	print("PokemonRegistry: smoke test passed — %d species, %d moves, %d learnsets loaded" % [
		_species_by_dex.size(), _moves_by_id.size(), _learnsets_by_dex.size()
	])
