extends Node
func _ready() -> void:
	# Test 1: lambda capture of int
	var ended_side := -1
	var fn := func(w): ended_side = w
	fn.call(42)
	print("lambda int capture: ended_side=", ended_side, " (expect 42)")
	
	# Test 2: via signal
	var sp := PokemonSpecies.new()
	sp.species_name = "A"; sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = 200; sp.base_attack = 200; sp.base_defense = 50
	sp.base_sp_attack = 80; sp.base_sp_defense = 50; sp.base_speed = 200
	var att := BattlePokemon.from_species(sp, 50)
	
	var sp2 := PokemonSpecies.new()
	sp2.species_name = "B"; sp2.types = [TypeChart.TYPE_NORMAL]
	sp2.base_hp = 20; sp2.base_attack = 20; sp2.base_defense = 20
	sp2.base_sp_attack = 20; sp2.base_sp_defense = 20; sp2.base_speed = 20
	var def_ := BattlePokemon.from_species(sp2, 50)
	
	var tackle = load("res://data/moves/move_0033.tres")
	att.add_move(tackle); def_.add_move(tackle)
	
	var winner := -1
	var bm := BattleManager.new()
	add_child(bm)
	bm.battle_ended.connect(func(w): winner = w)
	bm.start_battle(att, def_)
	print("signal int capture: winner=", winner, " (expect 0)")
	get_tree().quit(0)
