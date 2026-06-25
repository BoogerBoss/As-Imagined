class_name PokemonSpecies
extends Resource

# Battle-relevant species data. Graphics, overworld, and audio fields are
# deliberately absent — those belong in a separate presentation layer (M10+).
# Source struct: include/pokemon.h :: struct SpeciesInfo

@export var species_name: String = ""
@export var national_dex_num: int = 0

# Base stats
@export var base_hp: int = 1
@export var base_attack: int = 1
@export var base_defense: int = 1
@export var base_sp_attack: int = 1
@export var base_sp_defense: int = 1
@export var base_speed: int = 1

# Up to 2 Type enum ids. Second entry = TYPE_NONE (0) if single-typed.
@export var types: Array[int] = []

# 3 ability slots: [standard_1, standard_2, hidden]. Ability enum ids.
@export var abilities: Array[int] = []

@export var catch_rate: int = 45
@export var exp_yield: int = 64
@export var growth_rate: int = 0    # GrowthRate enum id
@export var gender_ratio: int = 127 # 255 = genderless; 0 = always male; 254 = always female
@export var egg_groups: Array[int] = []

# Level-up learnset. Each entry: {"level": int, "move_id": int}
# Populated with real data in Milestone 4+; empty for Milestone 1.
@export var learnset: Array[Dictionary] = []
