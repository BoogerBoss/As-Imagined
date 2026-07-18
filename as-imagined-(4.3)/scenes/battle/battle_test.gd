extends Node

# Milestone 1 integration test: two dummy Pokémon fight with one placeholder
# move until one faints, proving the battle loop terminates correctly.
#
# Run headlessly: godot --headless --path /path/to/project scenes/battle/battle_test.tscn


func _ready() -> void:
	var manager := BattleManager.new()
	add_child(manager)

	manager.move_executed.connect(_on_move_executed)
	manager.pokemon_fainted.connect(_on_pokemon_fainted)
	manager.battle_ended.connect(_on_battle_ended)

	# Dummy species: identical stats except B is slightly faster (speed 60 vs 50)
	# so turn order is deterministic without a tiebreak.
	var species_a := _make_species("Dummy-A", 65, 50)
	var species_b := _make_species("Dummy-B", 65, 60)
	var struggle := _make_struggle()

	var poke_a := BattlePokemon.from_species(species_a, 50)
	poke_a.add_move(struggle)

	var poke_b := BattlePokemon.from_species(species_b, 50)
	poke_b.add_move(struggle)

	print("=== Milestone 1 Battle Test ===")
	print("Dummy-A  HP: %d  Speed: %d" % [poke_a.max_hp, poke_a.speed])
	print("Dummy-B  HP: %d  Speed: %d" % [poke_b.max_hp, poke_b.speed])
	print("")

	manager.start_battle(poke_a, poke_b)


func _on_move_executed(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		damage: int) -> void:
	print("  %s used %s! %s took %d damage. (%d/%d HP)" % [
		attacker.nickname, move.move_name,
		defender.nickname, damage,
		defender.current_hp, defender.max_hp,
	])


func _on_pokemon_fainted(pokemon: BattlePokemon) -> void:
	print("  %s fainted!" % pokemon.nickname)


func _on_battle_ended(winner_side: int) -> void:
	var winner := "Dummy-A" if winner_side == 0 else "Dummy-B"
	print("")
	print("=== %s wins! ===" % winner)
	get_tree().quit()


# --- Helpers for building test data in code (no .tres files needed for M1) ---

func _make_species(
		name: String,
		base_hp: int = 65,
		base_spd: int = 50) -> PokemonSpecies:
	var s := PokemonSpecies.new()
	s.species_name = name
	s.national_dex_num = 0
	s.base_hp = base_hp
	s.base_attack = 50
	s.base_defense = 50
	s.base_sp_attack = 50
	s.base_sp_defense = 50
	s.base_speed = base_spd
	s.types = [0]     # Normal (type id 0)
	s.abilities = [0] # placeholder ability id
	s.learnset = []
	return s


func _make_struggle() -> MoveData:
	var m := MoveData.new()
	m.move_name = "Struggle"
	m.description = "M1 placeholder move. Damage is PLACEHOLDER_DAMAGE, not power."
	m.effect = 0
	m.type = 0       # Normal
	m.category = 0   # Physical
	m.power = 50     # ignored by M1 damage logic
	m.accuracy = 0   # always hits
	m.pp = 1         # not tracked in M1
	m.priority = 0
	m.makes_contact = true
	return m
